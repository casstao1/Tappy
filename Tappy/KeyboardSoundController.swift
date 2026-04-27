import AppKit
import Combine
import Foundation
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
    /// attach — macOS requires a relaunch before a newly granted permission
    /// takes effect for running processes. One restart fixes it.
    case needsRestart
    /// Event tap is active and TCC permission is confirmed. App is fully functional.
    case complete
}

@MainActor
final class KeyboardSoundController: ObservableObject {
    private enum DefaultsKey {
        static let selectedPackID = "Tappy.selectedPackID"
        static let clickVolume = "Tappy.clickVolume"
        static let trialedPackIDs = "Tappy.trialedPackIDs"
    }

    private static let livePreviewDurationSeconds = 90

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

        // Evaluate setup phase synchronously so the correct screen is shown
        // on the very first SwiftUI render — no flash, no async race.
        //
        // CGPreflightListenEventAccess() alone is unreliable: it caches stale
        // TCC results across launches. We also probe whether an event tap can
        // actually be created in this process, which is the definitive test.
        let trusted = CGPreflightListenEventAccess()
        if !trusted {
            setupPhase = .needsPermission
        } else if Self.canCreateEventTap() {
            setupPhase = .complete
        } else {
            // TCC says yes but the tap creation fails — this happens when
            // permission was just granted and the running process hasn't
            // received it yet. A relaunch resolves it (macOS requirement).
            setupPhase = .needsRestart
        }

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

        permissionManager.onStatusChange = { [weak self] trusted in
            Task { @MainActor in
                guard let self else { return }

                if trusted && self.setupPhase == .needsPermission {
                    // Permission was just granted while the app was open.
                    // Probe whether this process can use it without relaunching.
                    if Self.canCreateEventTap() {
                        self.setupPhase = .complete
                    } else {
                        // Most common path: tap doesn't work until relaunch.
                        self.setupPhase = .needsRestart
                    }
                }

                self.attemptListenerAttachIfNeeded()
                self.statusMessage = self.monitoringSummary()
            }
        }

        keyboardMonitor.onCaptureStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.backgroundCaptureState = state
                self.statusMessage = self.monitoringSummary()

                // If the tap attaches AND TCC confirms trust, we're fully live.
                if state == .ready && self.permissionManager.isTrusted {
                    self.setupPhase = .complete
                }
            }
        }

        _ = try? soundLibrary.restoreBundledPack(packID: currentPack.id)
        audioEngine.setVolume(clickVolume)
        reloadSounds()
        updateMonitoringState()
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
            .sink { [weak self] _ in self?.menuPopover?.close() }
            .store(in: &cancellables)
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject) {
        guard let button = menuStatusItem?.button else { return }
        guard let popover = menuPopover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateMenuBarIcon() {
        guard let button = menuStatusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Tappy")
        // Orange tint signals setup is incomplete; default (template) color = ready.
        switch setupPhase {
        case .needsPermission, .needsRestart:
            button.contentTintColor = .systemOrange
        case .complete:
            button.contentTintColor = nil  // system default (adapts to light/dark)
        }
    }

    // MARK: - Routing

    var shouldShowSetupGate: Bool {
        setupPhase != .complete
    }

    // MARK: - Setup screen content

    var setupHeadline: String {
        switch setupPhase {
        case .needsPermission:
            return "Enable Input Monitoring"
        case .needsRestart:
            return "Almost there — restart to activate"
        case .complete:
            return ""
        }
    }

    var setupDetail: String {
        switch setupPhase {
        case .needsPermission:
            return "Tappy needs Input Monitoring permission to play sounds while you type in any app. Open System Settings → Privacy & Security → Input Monitoring and switch on Tappy."
        case .needsRestart:
            return "Permission granted! macOS requires Tappy to restart once before the keyboard listener can attach. This only happens on first-time setup."
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

    var accessibilitySummary: String {
        permissionManager.hasGlobalMonitoringAccess
            ? "System-wide key monitoring is available."
            : "Background key clicks need confirmed Input Monitoring access."
    }

    var isRunningFromDerivedData: Bool {
        Bundle.main.bundleURL.path.contains("/DerivedData/")
    }

    /// True when both TCC permission and the event tap are confirmed working.
    /// Used by diagnostics and the warning banner.
    var hasConfirmedInputMonitoring: Bool {
        setupPhase == .complete
    }

    var compactStatus: String {
        if !isEnabled { return "Paused" }
        if setupPhase == .complete { return "Live" }
        return "Window Only"
    }

    var launchWarning: String? {
        // Only show warnings on the home screen (after setup is complete)
        guard setupPhase == .complete else { return nil }

        if !permissionManager.isTrusted {
            return "Input Monitoring was revoked. Re-enable Tappy in System Settings → Privacy & Security → Input Monitoring."
        }

        if isEnabled && backgroundCaptureState == .unavailable {
            return "Background capture failed to start. Try relaunching Tappy."
        }

        return nil
    }

    var permissionDebugSummary: String {
        "TCC preflight: \(permissionManager.isTrusted ? "✓" : "✗"), event tap: \(backgroundCaptureState == .ready ? "✓" : "✗")"
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

    var isPremiumStoreLoading: Bool {
        premiumStore.isLoading
    }

    var isPremiumPurchaseInFlight: Bool {
        premiumStore.isPurchasing
    }

    var stableAppPath: String {
        workspaceAppURL.path
    }

    private var workspaceAppURL: URL {
        URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Tappy.app", isDirectory: true)
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

    func revealStableApp() {
        NSWorkspace.shared.selectFile(stableAppPath, inFileViewerRootedAtPath: NSString(string: stableAppPath).deletingLastPathComponent)
    }

    func openStableApp() {
        NSWorkspace.shared.openApplication(at: workspaceAppURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Spawns a fresh instance of the current app and quits this one.
    /// Required after granting Input Monitoring — macOS does not allow a
    /// running process to attach an event tap until it relaunches.
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
        await premiumStore.purchaseUnlockAll()
        if premiumUnlocked, highlightedPack.isPremium {
            showUpgradeCTA = false
            ctaPack = nil
            highlightPack(highlightedPack)
        }
        statusMessage = premiumStore.lastMessage ?? monitoringSummary()
    }

    func restorePremiumPurchases() async {
        cancelPendingCTA()
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
        permissionManager.refreshStatus()
        permissionManager.scheduleRefreshBurst()
        attemptListenerAttachIfNeeded()
        statusMessage = monitoringSummary()
    }

    func openInputMonitoringSettings() {
        permissionManager.openInputMonitoringSettings()
    }

    func openSoundSettings() {
        permissionManager.openSoundSettings()
    }

    /// Called when the setup screen appears. Triggers the macOS permission
    /// dialog so the user sees it immediately without having to press a button.
    func requestStartupInputMonitoringPromptIfNeeded() {
        guard setupPhase == .needsPermission else { return }
        permissionManager.requestListenAccessPrompt()
        statusMessage = monitoringSummary()
    }

    func handleAppDidBecomeActive() {
        permissionManager.refreshStatus()
        permissionManager.scheduleRefreshBurst()
        attemptListenerAttachIfNeeded()
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
            return "Permission granted — restart Tappy to activate system-wide sounds."
        case .complete:
            if backgroundCaptureState == .unavailable {
                return "Input Monitoring appears available, but the background event tap failed to start."
            }
            return "Keyboard sounds are active system-wide."
        }
    }

    private func attemptListenerAttachIfNeeded() {
        guard isEnabled else { return }
        guard backgroundCaptureState != .ready else { return }

        keyboardMonitor.start { [weak self] trigger in
            DispatchQueue.main.async {
                self?.handle(trigger: trigger)
            }
        }
    }

    private func persistSelectedPack(_ pack: TechPack) {
        userDefaults.set(pack.id, forKey: DefaultsKey.selectedPackID)
    }

    private func cancelPendingCTA() {
        pendingCTAWorkItem?.cancel()
        pendingCTAWorkItem = nil
    }

    /// Synchronously probes whether this process can create and enable a
    /// CGEvent tap. This is the definitive test for whether Input Monitoring
    /// is functional — more reliable than CGPreflightListenEventAccess() alone.
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
        return isEnabled
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
