import AppKit
import Combine
import CoreGraphics
import Foundation
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Setup Phase

/// Describes where the user is in the Input Monitoring setup flow.
/// Evaluated synchronously at launch so the correct screen is shown immediately
/// with no flash or delay.
enum SetupPhase: Equatable {
    /// No TCC entry exists yet. User must open System Settings and grant access.
    case needsPermission
    /// TCC permission is now detected but this process's event tap still cannot
    /// attach. macOS often requires a relaunch before newly granted permission
    /// takes effect for the running process.
    case needsRestart
    /// Event tap is active and TCC permission is confirmed.
    case complete
}

@MainActor
final class KeyboardSoundController: ObservableObject {
    private enum StorePresentationMode {
        case purchase
        case restore

        var title: String {
            switch self {
            case .purchase:
                return "Unlocking Premium"
            case .restore:
                return "Restoring Purchase"
            }
        }

        var message: String {
            switch self {
            case .purchase:
                return "Complete the App Store confirmation to unlock all premium sound packs."
            case .restore:
                return "Tappy is checking the App Store for a previous premium purchase."
            }
        }
    }

    private enum DefaultsKey {
        static let selectedPackID = "Tappy.selectedPackID"
        static let clickVolume = "Tappy.clickVolume"
        static let trialedPackIDs = "Tappy.trialedPackIDs"
        static let reviewFirstUseTimestamp = "Tappy.reviewFirstUseTimestamp"
        static let reviewLastActiveDayTimestamp = "Tappy.reviewLastActiveDayTimestamp"
        static let reviewActiveDayCount = "Tappy.reviewActiveDayCount"
        static let reviewPromptedTimestamp = "Tappy.reviewPromptedTimestamp"
    }

    private static let livePreviewDurationSeconds = 90
    private static let reviewPromptDelaySeconds: TimeInterval = 0.8
    private static let reviewMinimumElapsedTime: TimeInterval = 60 * 60 * 24 * 2
    private static let reviewMinimumActiveDays = 2

    @Published var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            updateMonitoringState()
        }
    }
    @Published private(set) var availablePacks = TechPack.all
    @Published private(set) var currentPack = TechPack.plasticTapping
    @Published var highlightedPackID = TechPack.plasticTapping.id
    @Published private(set) var backgroundCaptureState: KeyboardMonitor.CaptureState = .stopped
    @Published private(set) var premiumUnlocked = false
    @Published private(set) var trialedPackIDs: Set<String> = []
    @Published private(set) var setupPhase: SetupPhase
    @Published private(set) var isPremiumFlowInFlight = false
    @Published var clickVolume: Double {
        didSet {
            let clampedVolume = min(max(clickVolume, 0), 1)
            if clampedVolume != clickVolume {
                clickVolume = clampedVolume
                return
            }

            userDefaults.set(clampedVolume, forKey: DefaultsKey.clickVolume)
            audioEngine.setVolume(clampedVolume)
        }
    }

    @Published private(set) var statusMessage = "Preparing audio engine..."
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastReloadedAt: Date?

    let permissionManager = InputMonitoringPermissionManager()
    let soundLibrary = SoundLibrary()
    let premiumStore = PremiumStore()

    private let keyboardMonitor = KeyboardMonitor()
    private let audioEngine = LowLatencyAudioEngine()
    private let userDefaults: UserDefaults
    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        premiumUnlocked = false
        trialedPackIDs = Set(userDefaults.stringArray(forKey: DefaultsKey.trialedPackIDs) ?? [])
        if userDefaults.object(forKey: DefaultsKey.clickVolume) == nil {
            clickVolume = 1.0
        } else {
            clickVolume = min(max(userDefaults.double(forKey: DefaultsKey.clickVolume), 0), 1)
        }

        let trusted = CGPreflightListenEventAccess()
        setupPhase = Self.setupPhase(
            trusted: trusted,
            captureState: .stopped,
            allowTapProbe: true
        )

        let savedPackID = userDefaults.string(forKey: DefaultsKey.selectedPackID)

        if let savedPack = Self.startupPack(from: savedPackID, premiumUnlocked: premiumUnlocked) {
            currentPack = savedPack
            highlightedPackID = savedPack.id
        } else {
            persistSelectedPack(TechPack.plasticTapping)
        }

        premiumStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        premiumStore.onUnlockStateChange = { [weak self] unlocked in
            guard let self else { return }

            self.premiumUnlocked = unlocked

            if unlocked {
                // Premium was just confirmed — restore the user's saved premium pack if
                // they had one. This corrects the startup race where premiumUnlocked is
                // always false during init(), causing startupPack() to fall back to
                // plasticTapping even for paying users.
                let savedPackID = self.userDefaults.string(forKey: DefaultsKey.selectedPackID)
                if let pack = Self.startupPack(from: savedPackID, premiumUnlocked: true),
                   pack.isPremium {
                    self.currentPack = pack
                    self.highlightedPackID = pack.id
                    self.restoreBuiltInPack(packID: pack.id)
                }
            } else if self.currentPack.isPremium {
                self.currentPack = .plasticTapping
                self.highlightedPackID = TechPack.plasticTapping.id
                self.persistSelectedPack(.plasticTapping)
                self.restoreBuiltInPack(packID: TechPack.plasticTapping.id)
            }

            self.statusMessage = unlocked ? "Premium packs unlocked." : self.monitoringSummary()
        }

        permissionManager.onStatusChange = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                self.attemptListenerAttachIfNeeded()
                self.reconcileSetupPhase(allowTapProbe: true)
                self.statusMessage = self.monitoringSummary()
            }
        }

        keyboardMonitor.onCaptureStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.backgroundCaptureState = state
                self.reconcileSetupPhase(allowTapProbe: false)
                self.statusMessage = self.monitoringSummary()
            }
        }

        _ = try? soundLibrary.restoreBundledPack(packID: currentPack.id)
        audioEngine.setVolume(clickVolume)
        reloadSounds()
        updateMonitoringState()
        reconcileSetupPhase(allowTapProbe: true)
        setupMenuBarItem()
    }

    deinit {
        keyboardMonitor.stop()
        if let item = menuStatusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Menu bar status item (NSStatusItem-based)

    private var menuStatusItem: NSStatusItem?
    private var menuPopover: NSPopover?
    private var pendingReviewPromptWorkItem: DispatchWorkItem?
    private var storePresentationWindowController: NSWindowController?
    private var storePresentationPreviousActivationPolicy: NSApplication.ActivationPolicy?

    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menuStatusItem = item

        if let button = item.button {
            updateMenuBarIcon()
            button.target = self
            button.action = #selector(handleStatusItemClick)
        }

        let hosting = NSHostingController(
            rootView: MenuBarView().environmentObject(self)
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = hosting
        menuPopover = popover

        // Keep icon in sync with state changes.
        Publishers.CombineLatest($setupPhase, $isEnabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.updateMenuBarIcon() }
            .store(in: &cancellables)

        // Close the popover immediately when the app loses focus so it never
        // shows the inactive/glossy window appearance while dangling open.
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cancelPendingReviewPrompt()
                self?.menuPopover?.close()
            }
            .store(in: &cancellables)

    }

    @objc private func handleStatusItemClick(_ sender: AnyObject) {
        guard let button = menuStatusItem?.button else { return }
        guard let popover = menuPopover else { return }

        if popover.isShown {
            cancelPendingReviewPrompt()
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            if let controller = popover.contentViewController {
                maybeRequestReview(in: controller)
            }
        }
    }

    private func updateMenuBarIcon() {
        guard let button = menuStatusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tappy")
        switch setupPhase {
        case .needsPermission, .needsRestart:
            button.contentTintColor = .systemOrange
        case .complete:
            button.contentTintColor = isEnabled ? nil : NSColor.secondaryLabelColor
        }
    }

    // MARK: - Setup

    var shouldShowSetupGate: Bool {
        setupPhase != .complete
    }

    var setupHeadline: String {
        switch setupPhase {
        case .needsPermission:
            return "Enable Input Monitoring"
        case .needsRestart:
            return "Restart to activate"
        case .complete:
            return ""
        }
    }

    var setupDetail: String {
        switch setupPhase {
        case .needsPermission:
            return "Tappy needs Input Monitoring permission to detect key presses and play sounds while you type in other apps."
        case .needsRestart:
            return "Permission is granted. Restart Tappy once so macOS applies Input Monitoring to this running app."
        case .complete:
            return ""
        }
    }

    var setupPrimaryButtonTitle: String {
        switch setupPhase {
        case .needsPermission:
            return "Open Input Monitoring"
        case .needsRestart:
            return "Restart Tappy"
        case .complete:
            return ""
        }
    }

    func performSetupPrimaryAction() {
        switch setupPhase {
        case .needsPermission:
            openInputMonitoringSettings()
        case .needsRestart:
            relaunchApp()
        case .complete:
            break
        }
    }

    // MARK: - Status

    var soundsFolderPath: String {
        soundLibrary.soundsRootURL.path
    }

    var compactStatus: String {
        if !isEnabled { return "Paused" }
        if setupPhase == .complete { return "Live" }
        return "Setup"
    }

    // MARK: - Pack access

    var highlightedPack: TechPack {
        availablePacks.first(where: { $0.id == highlightedPackID }) ?? currentPack
    }

    var selectedPackID: String {
        currentPack.id
    }

    var highlightedPackIsLocked: Bool {
        isPackLocked(highlightedPack)
    }

    var freePacks: [TechPack] {
        availablePacks.filter { !$0.isPremium }
    }

    var premiumPacks: [TechPack] {
        availablePacks.filter(\.isPremium)
    }

    var premiumUnlockPrice: String {
        premiumStore.unlockAllPrice
    }

    var premiumStoreMessage: String? {
        premiumStore.lastMessage
    }

    var premiumStoreStatusText: String? {
        if premiumStore.isPurchasing {
            return "Waiting for App Store confirmation..."
        }

        if premiumStore.isLoading {
            return "Connecting to the App Store..."
        }

        if isPremiumFlowInFlight {
            return "Preparing App Store purchase..."
        }

        return premiumStore.lastMessage
    }

    var isPremiumStoreLoading: Bool {
        premiumStore.isLoading
    }

    var isPremiumPurchaseInFlight: Bool {
        premiumStore.isPurchasing
    }

    var isPremiumStoreBusy: Bool {
        isPremiumFlowInFlight || premiumStore.isBusy
    }

    // MARK: - Public actions

    func reloadSounds() {
        do {
            try soundLibrary.reload(using: audioEngine)
            lastReloadedAt = Date()
            errorMessage = nil
            statusMessage = soundLibrary.totalSoundCount > 0 ? monitoringSummary() : soundLibrary.lastLoadMessage
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "The sound library failed to load."
        }
    }

    func revealSoundsFolder() {
        soundLibrary.revealInFinder()
    }

    /// Spawns a fresh instance of the current app and quits this one.
    /// Required after granting Input Monitoring on some macOS versions.
    func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let escapedPath = bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; open '\(escapedPath)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    func importSounds(into category: SoundCategory = .standard) {
        let panel = NSOpenPanel()
        panel.title = "Import Keyboard Sounds"
        panel.message = "Choose audio files to copy into the app's \(category.displayName) sound folder."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .wav, .aiff, .mp3, .mpeg4Audio,
            UTType("com.apple.coreaudio-format"),  // caf
        ].compactMap { $0 }

        guard panel.runModal() == .OK else { return }

        do {
            let importedCount = try soundLibrary.importFiles(panel.urls, into: category)
            reloadSounds()
            statusMessage = importedCount == 0
                ? "No compatible files were imported."
                : "Imported \(importedCount) file(s) into \(category.displayName)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importPackFolder() {
        let panel = NSOpenPanel()
        panel.title = "Import Sound Pack Folder"
        panel.message = "Choose a folder that contains default, space, return, delete, and modifier subfolders."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let rootURL = panel.url else { return }

        do {
            let importedCounts = try soundLibrary.importPack(from: rootURL)
            reloadSounds()
            let importedTotal = importedCounts.values.reduce(0, +)
            statusMessage = importedTotal == 0
                ? "No compatible files were found in that pack folder."
                : "Imported \(importedTotal) file(s) from the pack folder."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreBuiltInPack(packID: String? = nil) {
        do {
            let selectedPackID = packID ?? currentPack.id
            let restored = try soundLibrary.restoreBundledPack(packID: selectedPackID)
            reloadSounds()
            statusMessage = restored == 0 ? "Built-in pack unavailable." : "\(currentPack.name) loaded."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func highlightPack(_ pack: TechPack) {
        highlightedPackID = pack.id

        guard pack.isAvailable else {
            statusMessage = "\(pack.name) is not installed yet."
            return
        }

        if isPackLocked(pack) {
            // Just highlight — user starts a trial explicitly via the Try Free button
            return
        }

        // Selecting a free pack cancels any active preview
        if previewPack != nil { cancelLivePreview() }

        guard pack.id != currentPack.id else {
            restoreBuiltInPack(packID: pack.id)
            return
        }

        currentPack = pack
        persistSelectedPack(pack)
        restoreBuiltInPack(packID: pack.id)
    }

    func previewHighlightedPack(category: SoundCategory) {
        let pack = highlightedPack
        if isPackLocked(pack) {
            playPremiumDemo()
            return
        }
        preview(category: category)
    }

    func playPremiumDemo() {
        let pack = highlightedPack
        guard isPackLocked(pack) else {
            preview(category: .standard)
            return
        }

        do {
            try soundLibrary.previewBundledDemo(packID: pack.id, using: audioEngine)
            statusMessage = "Playing \(pack.name) demo."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginUnlockPremiumFlow() {
        Task {
            await premiumStore.refreshStore()
            statusMessage = premiumStore.lastMessage ?? "Premium packs are ready to unlock."
        }
    }

    func purchasePremiumUnlock() async {
        cancelPendingCTA()

        guard !isPremiumFlowInFlight else {
            statusMessage = "The App Store is already processing a request."
            return
        }
        isPremiumFlowInFlight = true
        defer { isPremiumFlowInFlight = false }

        statusMessage = "Connecting to the App Store..."
        let productIsReady = await premiumStore.prepareUnlockAllForPurchase()

        guard !premiumUnlocked else {
            statusMessage = "Premium packs are already unlocked."
            return
        }

        guard productIsReady else {
            statusMessage = premiumStore.lastMessage ?? "Premium unlock is not available yet."
            return
        }

        guard let window = beginStorePresentation(.purchase) else {
            statusMessage = "Unable to open the App Store purchase window."
            return
        }

        defer { endStorePresentation() }

        await premiumStore.purchaseUnlockAll(confirmIn: window)
        if premiumUnlocked, highlightedPack.isPremium {
            showUpgradeCTA = false
            ctaPack = nil
            highlightPack(highlightedPack)
        }
        statusMessage = premiumStore.lastMessage ?? monitoringSummary()
    }

    func restorePremiumPurchases() async {
        cancelPendingCTA()

        guard !isPremiumFlowInFlight else {
            statusMessage = "The App Store is already processing a request."
            return
        }
        isPremiumFlowInFlight = true
        defer { isPremiumFlowInFlight = false }

        let didOpenPresentation = beginStorePresentation(.restore) != nil
        defer {
            if didOpenPresentation {
                endStorePresentation()
            }
        }

        await premiumStore.restorePurchases()
        if premiumUnlocked, highlightedPack.isPremium {
            showUpgradeCTA = false
            ctaPack = nil
            highlightPack(highlightedPack)
        }
        statusMessage = premiumStore.lastMessage ?? monitoringSummary()
    }

    func requestKeyboardPermission() {
        permissionManager.requestListenAccessPrompt()
        statusMessage = monitoringSummary()
    }

    func refreshInputMonitoringStatus() {
        permissionManager.refreshStatus(forceNotify: true)
        permissionManager.scheduleRefreshBurst()
        attemptListenerAttachIfNeeded()
        reconcileSetupPhase(allowTapProbe: true)
        statusMessage = monitoringSummary()
    }

    func openInputMonitoringSettings() {
        permissionManager.openInputMonitoringSettings()
    }

    func openSoundSettings() {
        permissionManager.openSoundSettings()
    }

    /// Called when the setup bar appears. Triggers the macOS Input Monitoring
    /// prompt so users do not have to guess which privacy section to open.
    func requestStartupInputMonitoringPromptIfNeeded() {
        guard setupPhase == .needsPermission else { return }
        permissionManager.requestListenAccessPrompt()
        statusMessage = monitoringSummary()
    }

    func handleAppDidBecomeActive() {
        permissionManager.refreshStatus(forceNotify: true)
        permissionManager.scheduleRefreshBurst()
        attemptListenerAttachIfNeeded()
        reconcileSetupPhase(allowTapProbe: true)
    }

    func handleAppDidResignActive() {
        permissionManager.scheduleRefreshBurst()
    }

    func preview(category: SoundCategory) {
        audioEngine.play(category: category, keyCode: nil)
    }

    func isPackLocked(_ pack: TechPack) -> Bool {
        pack.isPremium && !premiumUnlocked
    }

    func hasTrialedPack(_ pack: TechPack) -> Bool {
        trialedPackIDs.contains(pack.id)
    }

    // MARK: - Live Preview (90-second trial)

    @Published private(set) var previewPack: TechPack? = nil
    @Published private(set) var previewSecondsRemaining: Int = 0
    @Published private(set) var showUpgradeCTA: Bool = false
    @Published private(set) var ctaPack: TechPack? = nil

    private var lastFreePack: TechPack = .plasticTapping
    private var previewTimerCancellable: AnyCancellable?
    private var pendingCTAWorkItem: DispatchWorkItem?

    var previewProgress: Double {
        guard previewPack != nil else { return 0 }
        return Double(previewSecondsRemaining) / Double(Self.livePreviewDurationSeconds)
    }

    var previewCountdownText: String {
        let minutes = previewSecondsRemaining / 60
        let seconds = previewSecondsRemaining % 60
        return String(format: "%d:%02d left", minutes, seconds)
    }

    var livePreviewDurationText: String {
        "\(Self.livePreviewDurationSeconds)-second"
    }

    func startLivePreview(_ pack: TechPack) {
        guard !hasTrialedPack(pack) else { return }

        cancelPendingCTA()
        stopRunningPreview()

        // Record this trial permanently so it can't be repeated
        trialedPackIDs.insert(pack.id)
        userDefaults.set(Array(trialedPackIDs), forKey: DefaultsKey.trialedPackIDs)

        // Remember the free pack to revert to
        if !currentPack.isPremium { lastFreePack = currentPack }

        previewPack = pack
        previewSecondsRemaining = Self.livePreviewDurationSeconds
        showUpgradeCTA = false
        ctaPack = nil

        // Switch sounds immediately — full quality, no degradation
        currentPack = pack
        restoreBuiltInPack(packID: pack.id)
        statusMessage = "Trying \(pack.name) for \(livePreviewDurationText)."

        // Countdown — fires on main thread, safe to mutate @MainActor state
        previewTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.previewSecondsRemaining -= 1
                if self.previewSecondsRemaining <= 0 { self.endLivePreview() }
            }
    }

    private func stopRunningPreview() {
        previewTimerCancellable?.cancel()
        previewTimerCancellable = nil
        previewPack = nil
        previewSecondsRemaining = 0
    }

    private func endLivePreview() {
        let previewed = previewPack
        stopRunningPreview()
        ctaPack = previewed

        // Revert to the free pack they were on
        currentPack = lastFreePack
        restoreBuiltInPack(packID: lastFreePack.id)
        if let previewed {
            statusMessage = "\(previewed.name) trial ended."
        }

        // Brief pause so the reversion is felt before the CTA appears
        cancelPendingCTA()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.ctaPack != nil, self.previewPack == nil, !self.premiumUnlocked else { return }
            self.showUpgradeCTA = true
        }
        pendingCTAWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func dismissUpgradeCTA() {
        cancelPendingCTA()
        showUpgradeCTA = false
        ctaPack = nil
    }

    /// Cancels any active live preview and reverts to the last free pack.
    func cancelLivePreview() {
        guard previewPack != nil else { return }
        cancelPendingCTA()
        stopRunningPreview()
        currentPack = lastFreePack
        restoreBuiltInPack(packID: lastFreePack.id)
        statusMessage = monitoringSummary()
    }

    // MARK: - Private

    private func updateMonitoringState() {
        audioEngine.setEnabled(isEnabled)

        if isEnabled {
            attemptListenerAttachIfNeeded()
            statusMessage = monitoringSummary()
        } else {
            keyboardMonitor.stop()
            statusMessage = "Keyboard sounds are paused."
        }
    }

    private func handle(trigger: KeyboardTrigger) {
        guard isEnabled else { return }
        audioEngine.play(category: trigger.category, keyCode: trigger.keyCode)
    }

    private func monitoringSummary() -> String {
        guard isEnabled else { return "Keyboard sounds are paused." }
        guard soundLibrary.totalSoundCount > 0 else { return soundLibrary.lastLoadMessage }

        switch setupPhase {
        case .needsPermission:
            return "Waiting for Input Monitoring permission."
        case .needsRestart:
            return "Permission granted. Restart Tappy to activate system-wide sounds."
        case .complete:
            if backgroundCaptureState == .unavailable {
                return "Input Monitoring appears available, but the listen-only event tap failed to start."
            }
            return "Keyboard sounds are active system-wide."
        }
    }

    private func attemptListenerAttachIfNeeded() {
        guard isEnabled else { return }

        if keyboardMonitor.captureState == .ready {
            if backgroundCaptureState != .ready {
                backgroundCaptureState = .ready
                reconcileSetupPhase(allowTapProbe: false)
            }
            return
        }

        keyboardMonitor.start { [weak self] trigger in
            DispatchQueue.main.async {
                self?.handle(trigger: trigger)
            }
        }
    }

    private func reconcileSetupPhase(allowTapProbe: Bool) {
        setupPhase = Self.setupPhase(
            trusted: permissionManager.isTrusted,
            captureState: backgroundCaptureState,
            allowTapProbe: allowTapProbe
        )
    }

    private func beginStorePresentation(_ mode: StorePresentationMode) -> NSWindow? {
        cancelPendingReviewPrompt()
        menuPopover?.performClose(nil)

        storePresentationPreviousActivationPolicy = NSApp.activationPolicy()
        if storePresentationPreviousActivationPolicy != .regular {
            _ = NSApp.setActivationPolicy(.regular)
        }

        NSApp.activate(ignoringOtherApps: true)

        let controller = makeStorePresentationWindowController(mode: mode)
        storePresentationWindowController = controller

        guard let window = controller.window else { return nil }

        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return window
    }

    private func endStorePresentation() {
        storePresentationWindowController?.close()
        storePresentationWindowController = nil

        if let previousPolicy = storePresentationPreviousActivationPolicy, previousPolicy != NSApp.activationPolicy() {
            _ = NSApp.setActivationPolicy(previousPolicy)
        }
        storePresentationPreviousActivationPolicy = nil
    }

    private func makeStorePresentationWindowController(mode: StorePresentationMode) -> NSWindowController {
        let hostingController = NSHostingController(
            rootView: StorePresentationView(title: mode.title, message: mode.message)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable]
        window.title = mode.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(NSSize(width: 340, height: 140))
        return NSWindowController(window: window)
    }

    private func persistSelectedPack(_ pack: TechPack) {
        userDefaults.set(pack.id, forKey: DefaultsKey.selectedPackID)
    }

    private func maybeRequestReview(in controller: NSViewController, now: Date = Date()) {
        guard setupPhase == .complete else { return }
        guard userDefaults.object(forKey: DefaultsKey.reviewPromptedTimestamp) == nil else { return }

        recordReviewUsage(for: now)

        guard isEligibleForReviewRequest(at: now) else { return }
        guard pendingReviewPromptWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self, weak controller] in
            guard let self else { return }
            defer { self.pendingReviewPromptWorkItem = nil }

            guard let controller else { return }
            guard self.setupPhase == .complete else { return }
            guard self.menuPopover?.isShown == true else { return }
            guard NSApp.isActive else { return }

            self.userDefaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.reviewPromptedTimestamp)
            AppStore.requestReview(in: controller)
        }

        pendingReviewPromptWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reviewPromptDelaySeconds, execute: workItem)
    }

    private func recordReviewUsage(for now: Date) {
        if userDefaults.object(forKey: DefaultsKey.reviewFirstUseTimestamp) == nil {
            userDefaults.set(now.timeIntervalSince1970, forKey: DefaultsKey.reviewFirstUseTimestamp)
        }

        let todayStart = Calendar.autoupdatingCurrent.startOfDay(for: now).timeIntervalSince1970
        let lastRecordedDay = userDefaults.object(forKey: DefaultsKey.reviewLastActiveDayTimestamp) as? Double

        guard lastRecordedDay != todayStart else { return }

        let activeDayCount = userDefaults.integer(forKey: DefaultsKey.reviewActiveDayCount) + 1
        userDefaults.set(todayStart, forKey: DefaultsKey.reviewLastActiveDayTimestamp)
        userDefaults.set(activeDayCount, forKey: DefaultsKey.reviewActiveDayCount)
    }

    private func isEligibleForReviewRequest(at now: Date) -> Bool {
        let activeDayCount = userDefaults.integer(forKey: DefaultsKey.reviewActiveDayCount)
        guard activeDayCount >= Self.reviewMinimumActiveDays else { return false }

        guard let firstUseTimestamp = userDefaults.object(forKey: DefaultsKey.reviewFirstUseTimestamp) as? Double else {
            return false
        }

        let elapsedTime = now.timeIntervalSince1970 - firstUseTimestamp
        return elapsedTime >= Self.reviewMinimumElapsedTime
    }

    private func cancelPendingReviewPrompt() {
        pendingReviewPromptWorkItem?.cancel()
        pendingReviewPromptWorkItem = nil
    }

    private func cancelPendingCTA() {
        pendingCTAWorkItem?.cancel()
        pendingCTAWorkItem = nil
    }

    /// Synchronously probes whether this process can create and enable a
    /// listen-only CGEvent tap. This is more reliable than TCC preflight alone
    /// because macOS can require a relaunch after newly granted permission.
    private static func canCreateEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        return isEnabled
    }

    private static func setupPhase(
        trusted: Bool,
        captureState: KeyboardMonitor.CaptureState,
        allowTapProbe: Bool
    ) -> SetupPhase {
        if captureState == .ready {
            return .complete
        }

        if allowTapProbe && Self.canCreateEventTap() {
            return .complete
        }

        guard trusted else { return .needsPermission }

        return .needsRestart
    }

    private static func startupPack(from savedPackID: String?, premiumUnlocked: Bool) -> TechPack? {
        guard
            let savedPackID,
            let savedPack = TechPack.all.first(where: { $0.id == savedPackID })
        else {
            return nil
        }

        guard savedPack.isAvailable else { return TechPack.plasticTapping }
        guard !savedPack.isPremium || premiumUnlocked else { return TechPack.plasticTapping }
        return savedPack
    }
}

private struct StorePresentationView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 340, height: 140)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
