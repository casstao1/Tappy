import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI
import UniformTypeIdentifiers


/// Optional usage events contain only predefined app actions and bundled pack IDs.
@MainActor
final class TappyTelemetry {
    private let defaults: UserDefaults
    private let enabledKey = "Tappy.analyticsEnabled"
    private let idKey = "Tappy.analyticsInstallID"
    private let sessionConfiguration: URLSessionConfiguration
    private let configurationOverride: (URL, String)?
    private var session: URLSession

    init(defaults: UserDefaults, configurationOverride: (URL, String)? = nil,
         sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.defaults = defaults
        self.configurationOverride = configurationOverride
        self.sessionConfiguration = sessionConfiguration
        self.session = URLSession(configuration: sessionConfiguration)
    }

    private var configuration: (URL, String)? {
        if let configurationOverride { return configurationOverride }
        guard let host = Bundle.main.object(forInfoDictionaryKey: "TappyAnalyticsHost") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "TappyAnalyticsKey") as? String,
              !key.isEmpty, !key.contains("$("),
              let url = URL(string: host), url.scheme == "https", url.host != nil,
              !host.contains("$(") else { return nil }
        return (url.appendingPathComponent("capture/"), key)
    }

    var available: Bool { configuration != nil }
    var enabled: Bool { defaults.bool(forKey: enabledKey) && available }

    func setEnabled(_ enabled: Bool) {
        guard !enabled || available else { return }
        defaults.set(enabled, forKey: enabledKey)
        if enabled {
            defaults.set(UUID().uuidString, forKey: idKey)
        } else {
            session.invalidateAndCancel()
            session = URLSession(configuration: sessionConfiguration)
            defaults.removeObject(forKey: idKey)
        }
    }

    func record(_ event: String, pack: String? = nil, properties: [String: String] = [:]) {
        guard enabled, let (url, key) = configuration,
              let id = defaults.string(forKey: idKey) else { return }
        var values: [String: Any] = [
            "distinct_id": id, "$process_person_profile": false, "$geoip_disable": true,
            "distribution": "app_store", "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        if let pack, TechPack.all.contains(where: { $0.id == pack }) { values["pack_id"] = pack }
        for (key, value) in properties { values[key] = value }
        let body: [String: Any] = ["api_key": key, "event": event, "properties": values]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        session.dataTask(with: request).resume()
    }
}
// MARK: - Setup Phase

/// Describes where the user is in the Input Monitoring setup flow for
/// system-wide auditory typing feedback.
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
    private enum DefaultsKey {
        static let selectedPackID = "Tappy.selectedPackID"
        static let clickVolume = "Tappy.clickVolume"
        static let trialedPackIDs = "Tappy.trialedPackIDs"
        static let hasSeenWelcome = "Tappy.hasSeenWelcome"
        static let welcomeVersionSeen = "Tappy.welcomeVersionSeen"
    }

    /// Number of premium keystrokes a locked pack can be previewed for before the
    /// sound reverts to the free default and the unlock prompt appears.
    private static let livePreviewKeystrokeLimit = 100
    private static let currentWelcomeVersion = 1

    private static var debugSelectedPackID: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["TAPPY_DEBUG_PACK_ID"]
        #else
        nil
        #endif
    }

    @Published var isEnabled = false {
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
    @Published private(set) var sampleErrorMessage: String?
    @Published private(set) var lastReloadedAt: Date?

    let permissionManager = InputMonitoringPermissionManager()
    let soundLibrary = SoundLibrary()
    let purchaseStore: AppStorePurchaseStore
    @Published private(set) var isStoreRefreshInFlight = false
    @Published private(set) var isStoreActionPending = false
    private let telemetry: TappyTelemetry
    #if DEBUG
    static var debugTelemetryFactory: ((UserDefaults) -> TappyTelemetry)?
    static var debugPurchaseStoreFactory: (() -> AppStorePurchaseStore)?
    static var debugSkipStoreRefresh = false
    #endif
    @Published private(set) var analyticsEnabled = false
    var analyticsAvailable: Bool { telemetry.available }
    private let analyticsConsentPromptSeenKey = "Tappy.analyticsConsentPromptSeen"
    private var isShowingAnalyticsPrivacy = false

    func setAnalyticsEnabled(_ enabled: Bool) {
        telemetry.setEnabled(enabled)
        analyticsEnabled = telemetry.enabled
        if analyticsEnabled {
            telemetry.record("analytics_enabled", pack: currentPack.id, properties: ["setup": setupPhase.analyticsValue])
        }
    }

    /// Asks only when the user has not already made an analytics choice.
    @discardableResult
    func presentAnalyticsConsentIfNeeded() -> Bool {
        guard analyticsAvailable, !isShowingAnalyticsPrivacy,
              !userDefaults.bool(forKey: analyticsConsentPromptSeenKey) else { return false }
        // Preserve choices made by users of earlier builds with the checkbox.
        if userDefaults.object(forKey: "Tappy.analyticsEnabled") != nil {
            userDefaults.set(true, forKey: analyticsConsentPromptSeenKey)
            return false
        }
        showAnalyticsPrivacy()
        return true
    }

    /// The menu entry lets the user change or withdraw consent at any time.
    func showAnalyticsPrivacy() {
        let policyURL = URL(string: "https://casstao1.github.io/Tappy/privacy.html")!
        guard analyticsAvailable else {
            NSWorkspace.shared.open(policyURL)
            return
        }
        guard !isShowingAnalyticsPrivacy else { return }
        isShowingAnalyticsPrivacy = true
        defer { isShowingAnalyticsPrivacy = false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = analyticsEnabled ? "Usage data sharing is on" : "Share optional usage data?"
        alert.informativeText = "Tappy can send sound choices, previews, and purchase steps to PostHog with a random installation ID to help improve the app. It never sends typed text or individual keystrokes. You can change your choice anytime under Privacy in Tappy."
        alert.addButton(withTitle: analyticsEnabled ? "Stop Sharing" : "Share Usage Data")
        alert.addButton(withTitle: analyticsEnabled ? "Keep Sharing" : "Don't Share")
        alert.addButton(withTitle: "Privacy Policy")
        // Returning or closing the window must not opt the user in.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        let result = alert.runModal()
        if result == .alertThirdButtonReturn {
            NSWorkspace.shared.open(policyURL)
            return
        }
        if result == .alertFirstButtonReturn {
            setAnalyticsEnabled(!analyticsEnabled)
        } else if result == .alertSecondButtonReturn && !analyticsEnabled {
            setAnalyticsEnabled(false)
        }
        userDefaults.set(true, forKey: analyticsConsentPromptSeenKey)
    }

    private let keyboardMonitor = KeyboardMonitor()
    private let audioEngine = LowLatencyAudioEngine()
    private let userDefaults: UserDefaults
    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()
    private var appURLHandler: TappyAppURLHandler?
    private var sampleRequestID = UUID()
    private var sampleLoadTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        #if DEBUG
        purchaseStore = Self.debugPurchaseStoreFactory?() ?? AppStorePurchaseStore()
        telemetry = Self.debugTelemetryFactory?(userDefaults) ?? TappyTelemetry(defaults: userDefaults)
        #else
        purchaseStore = AppStorePurchaseStore()
        telemetry = TappyTelemetry(defaults: userDefaults)
        #endif
        analyticsEnabled = telemetry.enabled
        premiumUnlocked = purchaseStore.hasUnlockedPremium
        trialedPackIDs = Set(userDefaults.stringArray(forKey: DefaultsKey.trialedPackIDs) ?? [])
        if userDefaults.object(forKey: DefaultsKey.clickVolume) == nil {
            clickVolume = 1.0
        } else {
            clickVolume = min(max(userDefaults.double(forKey: DefaultsKey.clickVolume), 0), 1)
        }

        let trusted = InputMonitoringPermissionManager.listenEventAccessGranted()
        setupPhase = Self.setupPhase(
            trusted: trusted,
            captureState: .stopped
        )

        let savedPackID = Self.debugSelectedPackID ?? userDefaults.string(forKey: DefaultsKey.selectedPackID)

        if let savedPack = Self.startupPack(from: savedPackID, premiumUnlocked: hasPremiumAccess) {
            currentPack = savedPack
            highlightedPackID = savedPack.id
        } else {
            persistSelectedPack(TechPack.plasticTapping)
        }

        purchaseStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        purchaseStore.$hasUnlockedPremium.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reconcilePremiumUnlockState() }
            .store(in: &cancellables)
        #if DEBUG
        if !Self.debugSkipStoreRefresh { refreshStore() }
        #else
        refreshStore()
        #endif

        permissionManager.onStatusChange = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                self.attemptListenerAttachIfNeeded()
                self.reconcileSetupPhase()
                self.statusMessage = self.monitoringSummary()
            }
        }

        keyboardMonitor.onCaptureStateChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.backgroundCaptureState = state
                self.reconcileSetupPhase()
                self.statusMessage = self.monitoringSummary()
            }
        }

        _ = try? soundLibrary.restoreBundledPack(packID: currentPack.id)
        audioEngine.setVolume(clickVolume)
        reloadSounds()
        updateMonitoringState()
        reconcileSetupPhase()
        setupMenuBarItem()
        appURLHandler = TappyAppURLHandler(controller: self)
        presentWelcomeIfNeeded()
        telemetry.record("app_launched", pack: currentPack.id, properties: ["setup": setupPhase.analyticsValue, "unlocked": premiumUnlocked ? "yes" : "no"])
    }

    deinit {
        keyboardMonitor.stop()
        appURLHandler?.invalidate()
        if let item = menuStatusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    // MARK: - Menu bar status item (NSStatusItem-based)

    private var menuStatusItem: NSStatusItem?
    private var menuPopover: NSPopover?
    private var welcomeWindow: NSWindow?
    private var isWelcomePresentationScheduled = false
    private var didRequestStartupInputMonitoringPrompt = true

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
        hosting.sizingOptions = [.preferredContentSize]
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
                self?.menuPopover?.close()
            }
            .store(in: &cancellables)

    }

    @objc private func handleStatusItemClick(_ sender: AnyObject) {
        if menuPopover?.isShown == true {
            menuPopover?.performClose(nil)
        } else {
            showMenuPopover()
        }
    }

    private func showMenuPopover() {
        guard let button = menuStatusItem?.button else { return }
        guard let popover = menuPopover else { return }

        refreshStorePrice()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
            return "Enable Auditory Feedback"
        case .needsRestart:
            return "Restart to activate"
        case .complete:
            return ""
        }
    }

    var setupDetail: String {
        switch setupPhase {
        case .needsPermission:
            return "Tappy needs Input Monitoring to detect physical key categories for local auditory feedback while you type in other apps. Tappy does not read, store, or transmit typed text."
        case .needsRestart:
            return "Permission is granted. Restart Tappy once so macOS applies auditory feedback to this running app."
        case .complete:
            return ""
        }
    }

    var setupPrimaryButtonTitle: String {
        switch setupPhase {
        case .needsPermission:
            return "Open Privacy Settings"
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
        if setupPhase == .complete { return "Active" }
        return "Setup"
    }

    /// A single error to surface in the panel only when system-wide input
    /// monitoring isn't working. nil whenever feedback is active (or
    /// intentionally paused), and nil while the setup bar is already prompting
    /// for permission — so the panel stays quiet unless there's a problem the
    /// user wouldn't otherwise see.
    var inputMonitoringIssue: String? {
        guard isEnabled else { return nil }
        switch setupPhase {
        case .needsPermission, .needsRestart:
            return nil
        case .complete:
            if backgroundCaptureState == .unavailable {
                return "Tappy can't detect your keyboard. Open Input Monitoring in System Settings and make sure Tappy is enabled."
            }
            return nil
        }
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

    var hasPremiumAccess: Bool {
        premiumUnlocked
    }

    var premiumUnlockPrice: String {
        isPremiumStoreLoading ? "" : (purchaseStore.displayPrice ?? "")
    }

    var premiumStoreMessage: String? {
        purchaseStore.statusMessage
    }

    var premiumStoreStatusText: String? {
        if purchaseStore.isPurchasing { return "Completing App Store purchase..." }
        if purchaseStore.isRestoring { return "Restoring purchases..." }
        if isStoreRefreshInFlight || purchaseStore.isLoading { return "Loading App Store purchase..." }
        return purchaseStore.statusMessage
    }

    var isPremiumStoreLoading: Bool {
        isStoreRefreshInFlight || purchaseStore.isLoading
    }

    var isPremiumPurchaseInFlight: Bool {
        purchaseStore.isPurchasing
    }

    var isPremiumStoreBusy: Bool {
        isStoreRefreshInFlight || isStoreActionPending || purchaseStore.isLoading || purchaseStore.isPurchasing || purchaseStore.isRestoring
    }

    var isPremiumPurchaseAvailable: Bool {
        purchaseStore.displayPrice != nil && !isPremiumStoreBusy
    }

    /// A Buy click can also retry loading the App Store product if no price is available.
    var canRequestPremiumPurchase: Bool { !isPremiumStoreBusy }

    var shouldShowPremiumPurchaseUI: Bool {
        !premiumUnlocked
    }

    // MARK: - Public actions

    func reloadSounds() {
        do {
            try soundLibrary.reload(using: audioEngine, packID: currentPack.id)
            lastReloadedAt = Date()
            errorMessage = nil
            statusMessage = soundLibrary.totalSoundCount > 0 ? monitoringSummary() : soundLibrary.lastLoadMessage
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "The feedback library failed to load."
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
        panel.title = "Import Feedback Cues"
        panel.message = "Choose audio files to copy into the app's \(category.displayName) feedback folder."
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
        panel.title = "Import Feedback Pack Folder"
        panel.message = "Choose a folder that contains default, space, return, delete, and modifier cue subfolders."
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
        telemetry.record("pack_selected", pack: pack.id, properties: ["locked": isPackLocked(pack) ? "yes" : "no"])

        guard pack.isAvailable else {
            statusMessage = "\(pack.name) is not installed yet."
            return
        }

        if isPackLocked(pack) {
            // Just highlight — the preview/purchase prompt is started explicitly from the pack row.
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
        sampleLoadTask?.cancel()
        let requestID = UUID()
        sampleRequestID = requestID
        audioEngine.stopSample()
        sampleErrorMessage = nil
        let pack = highlightedPack
        guard isPackLocked(pack) else {
            preview(category: .standard)
            return
        }

        do {
            let demoURL = try soundLibrary.bundledDemoURL(packID: pack.id)
            let engine = audioEngine
            sampleLoadTask = Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try engine.makeBuffer(from: demoURL) }
                }.value
                guard let self, !Task.isCancelled, self.sampleRequestID == requestID else { return }
                switch result {
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.sampleErrorMessage = "The sample for \(pack.name) could not be played."
                case .success(let buffer):
                    engine.playSample(buffer: buffer) { [weak self] result in
                        guard let self, self.sampleRequestID == requestID else { return }
                        switch result {
                        case .success:
                            self.telemetry.record("demo_played", pack: pack.id)
                            self.statusMessage = "Playing \(pack.name) demo."
                        case .failure(let error):
                            self.errorMessage = error.localizedDescription
                            self.sampleErrorMessage = "The sample for \(pack.name) could not be played."
                        }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            sampleErrorMessage = "The sample for \(pack.name) could not be played."
        }
    }

    func buyPremium() {
        guard canRequestPremiumPurchase else { return }
        // Do not start a transaction until the real, localized price is visible.
        // If StoreKit failed to load, let Buy retry instead of leaving a dead button.
        guard purchaseStore.displayPrice != nil else {
            refreshStore()
            return
        }
        cancelPendingCTA()
        telemetry.record("purchase_requested", pack: ctaPack?.id ?? highlightedPackID)
        isStoreActionPending = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isStoreActionPending = false }
            let unlocked = await self.purchaseStore.purchase()
            self.telemetry.record("purchase_finished", properties: [
                "access": unlocked ? "unlocked" : "not_unlocked",
                "result": self.purchaseStore.lastPurchaseOutcome.rawValue
            ])
            self.reconcilePremiumUnlockState()
        }
    }

    func restorePurchases() {
        guard !isPremiumStoreBusy else { return }
        telemetry.record("restore_requested")
        isStoreActionPending = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isStoreActionPending = false }
            let unlocked = await self.purchaseStore.restore()
            self.telemetry.record("restore_finished", properties: ["access": unlocked ? "unlocked" : "not_unlocked"])
            self.reconcilePremiumUnlockState()
        }
    }

    func refreshStore() {
        guard !isPremiumStoreBusy else { return }
        isStoreRefreshInFlight = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isStoreRefreshInFlight = false }
            await self.purchaseStore.refresh()
            self.reconcilePremiumUnlockState()
        }
    }

    func refreshStorePrice() {
        guard !hasPremiumAccess, !isPremiumStoreBusy else { return }
        isStoreRefreshInFlight = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isStoreRefreshInFlight = false }
            await self.purchaseStore.refreshPrice()
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "tappy" else { return }

        let action = (url.host ?? url.pathComponents.dropFirst().first ?? "").lowercased()

        switch action {
        case "open", "menu":
            showMenuPopover()
        default:
            statusMessage = "Tappy did not recognize that link."
            showMenuPopover()
        }
    }

    func showWelcomeWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let welcomeWindow {
            welcomeWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: WelcomeView().environmentObject(self)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: WelcomeView.width, height: WelcomeView.height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tappy Input Monitoring Setup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()

        welcomeWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func finishWelcome() {
        markWelcomeSeen()
        welcomeWindow?.close()
        menuPopover?.performClose(nil)

        if setupPhase == .needsPermission {
            requestStartupInputMonitoringPromptIfNeeded()
        } else {
            updateMonitoringState()
            reconcileSetupPhase()
        }
    }

    func markWelcomeSeen() {
        userDefaults.set(true, forKey: DefaultsKey.hasSeenWelcome)
        userDefaults.set(Self.currentWelcomeVersion, forKey: DefaultsKey.welcomeVersionSeen)
    }

    func refreshInputMonitoringStatus() {
        permissionManager.refreshStatus(forceNotify: true)
        permissionManager.scheduleRefreshBurst()
        attemptListenerAttachIfNeeded()
        reconcileSetupPhase()
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
        guard Self.shouldRequestStartupInputMonitoringPrompt(
            setupPhase: setupPhase,
            hasSeenWelcome: hasSeenCurrentWelcome,
            didRequestThisLaunch: didRequestStartupInputMonitoringPrompt
        ) else { return }

        didRequestStartupInputMonitoringPrompt = true
        permissionManager.requestListenAccessPrompt()
        statusMessage = monitoringSummary()
    }

    nonisolated static func shouldRequestStartupInputMonitoringPrompt(
        setupPhase: SetupPhase,
        hasSeenWelcome: Bool,
        didRequestThisLaunch: Bool
    ) -> Bool {
        setupPhase == .needsPermission && hasSeenWelcome && !didRequestThisLaunch
    }

    nonisolated static func shouldAttemptInputMonitoring(
        isEnabled: Bool,
        hasSeenWelcome: Bool,
        isTrusted: Bool
    ) -> Bool {
        isEnabled && hasSeenWelcome && isTrusted
    }

    func handleAppDidBecomeActive() {
        permissionManager.refreshStatus(forceNotify: true)
        permissionManager.scheduleRefreshBurst()
        attemptListenerAttachIfNeeded()
        reconcileSetupPhase()
        presentWelcomeIfNeeded(delay: 0.1)
    }

    func handleAppDidResignActive() {
        permissionManager.scheduleRefreshBurst()
    }

    func preview(category: SoundCategory) {
        audioEngine.playLoadedSample(category: category)
    }

    func isPackLocked(_ pack: TechPack) -> Bool {
        Self.isPackLocked(pack, hasPremiumAccess: hasPremiumAccess)
    }

    nonisolated static func isPackLocked(_ pack: TechPack, hasPremiumAccess: Bool) -> Bool {
        pack.isPremium && !hasPremiumAccess
    }

    func hasTrialedPack(_ pack: TechPack) -> Bool {
        trialedPackIDs.contains(pack.id)
    }

    // MARK: - Live Preview (keystroke-limited demo)

    @Published private(set) var previewPack: TechPack? = nil
    @Published private(set) var showUpgradeCTA: Bool = false
    @Published private(set) var ctaPack: TechPack? = nil

    // Internal counter only — no UI observes it, so it isn't @Published (avoids a
    // spurious view update on every previewed keystroke).
    private var previewKeystrokesRemaining = 0
    private var lastFreePack: TechPack = .plasticTapping
    private var pendingCTAWorkItem: DispatchWorkItem?

    var livePreviewLimitText: String {
        "\(Self.livePreviewKeystrokeLimit)-keystroke"
    }

    var livePreviewUnavailableReason: String? {
        #if DEBUG
        if let override = debugPreviewAvailabilityOverride {
            return override ? nil : "Enable typing feedback before starting a preview."
        }
        #endif
        return Self.livePreviewUnavailableReason(isEnabled: isEnabled, setupPhase: setupPhase)
    }

    nonisolated static func livePreviewUnavailableReason(isEnabled: Bool, setupPhase: SetupPhase) -> String? {
        guard isEnabled else { return "Turn on Feedback before starting a typing preview." }
        switch setupPhase {
        case .needsPermission:
            return "Enable Input Monitoring before starting a typing preview."
        case .needsRestart:
            return "Restart Tappy after enabling Input Monitoring before starting a typing preview."
        case .complete:
            return nil
        }
    }

    var canStartLivePreview: Bool { livePreviewUnavailableReason == nil }

    #if DEBUG
    // Tests can simulate an active keyboard monitor without accessing real input.
    var debugPreviewAvailabilityOverride: Bool?
    #endif

    func startLivePreview(_ pack: TechPack) {
        guard !hasTrialedPack(pack) else { return }
        guard canStartLivePreview else {
            sampleErrorMessage = livePreviewUnavailableReason
            return
        }

        // Prepare the new sounds before consuming a trial or changing the
        // current preview. The regular sound library stays available as-is.
        do {
            let contents = try soundLibrary.loadBundledPreviewPack(packID: pack.id, using: audioEngine)
            let longSoundPack = pack.id == TechPack.thud.id || pack.id == TechPack.catMeows.id
            try audioEngine.setPreviewSounds(contents.sounds, keySounds: contents.keySounds, allowVoiceExpansion: longSoundPack)
        } catch {
            errorMessage = error.localizedDescription
            sampleErrorMessage = "The preview for \(pack.name) could not be loaded. Try again."
            return
        }
        sampleErrorMessage = nil
        cancelPendingCTA()
        if let previous = previewPack { telemetry.record("preview_cancelled", pack: previous.id) }
        previewPack = nil
        previewKeystrokesRemaining = 0

        telemetry.record("preview_started", pack: pack.id)

        // Record this preview permanently so it can't be repeated
        trialedPackIDs.insert(pack.id)
        userDefaults.set(Array(trialedPackIDs), forKey: DefaultsKey.trialedPackIDs)

        // Remember the free pack to revert to
        if !currentPack.isPremium { lastFreePack = currentPack }

        previewPack = pack
        previewKeystrokesRemaining = Self.livePreviewKeystrokeLimit
        showUpgradeCTA = false
        ctaPack = nil

        // Switch sounds immediately — full quality, no degradation
        currentPack = pack
        statusMessage = "Previewing \(pack.name) for your next \(Self.livePreviewKeystrokeLimit) keystrokes."
    }

    /// Counts one premium keystroke against the preview budget. Called for each
    /// sound-producing key event while a preview is active; reverts to the free
    /// sound once the budget is exhausted.
    private func consumePreviewKeystroke() {
        guard previewPack != nil else { return }
        previewKeystrokesRemaining -= 1
        if previewKeystrokesRemaining <= 0 {
            endLivePreview()
        }
    }

    #if DEBUG
    func debugConsumePreviewKeystroke() {
        consumePreviewKeystroke()
    }
    #endif

    private func stopRunningPreview() {
        previewPack = nil
        previewKeystrokesRemaining = 0
        audioEngine.clearPreviewSounds()
    }

    private func endLivePreview() {
        let previewed = previewPack
        if let previewed { telemetry.record("preview_completed", pack: previewed.id) }
        stopRunningPreview()
        ctaPack = previewed

        // Revert to the free pack they were on
        currentPack = lastFreePack
        if let previewed {
            statusMessage = "\(previewed.name) preview ended."
        }

        // Brief pause so the reversion is felt before the CTA appears
        cancelPendingCTA()
        guard !hasPremiumAccess else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.ctaPack != nil, self.previewPack == nil, !self.hasPremiumAccess else { return }
            self.showUpgradeCTA = true
            self.telemetry.record("upgrade_prompt_shown", pack: self.ctaPack?.id)
        }
        pendingCTAWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func dismissUpgradeCTA() {
        if showUpgradeCTA { telemetry.record("upgrade_prompt_dismissed", pack: ctaPack?.id) }
        cancelPendingCTA()
        showUpgradeCTA = false
        ctaPack = nil
    }

    /// Cancels any active live preview and reverts to the last free pack.
    func cancelLivePreview() {
        guard let previewPack else { return }
        telemetry.record("preview_cancelled", pack: previewPack.id)
        cancelPendingCTA()
        stopRunningPreview()
        currentPack = lastFreePack
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
            statusMessage = "Auditory feedback is paused."
        }
    }

    private func handle(trigger: KeyboardTrigger) {
        guard isEnabled else { return }
        if previewPack != nil {
            audioEngine.playPreview(category: trigger.category, keyCode: trigger.keyCode)
        } else {
            audioEngine.play(category: trigger.category, keyCode: trigger.keyCode)
        }
        // Each premium keystroke counts against the preview budget.
        consumePreviewKeystroke()
    }

    private func reconcilePremiumUnlockState() {
        premiumUnlocked = purchaseStore.hasUnlockedPremium

        if hasPremiumAccess {
            cancelPendingCTA()
            showUpgradeCTA = false
            ctaPack = nil

            if let previewPack {
                stopRunningPreview()
                selectUnlockedPremiumPack(previewPack)
            } else if highlightedPack.isPremium {
                selectUnlockedPremiumPack(highlightedPack)
            } else {
                let savedPackID = userDefaults.string(forKey: DefaultsKey.selectedPackID)
                if let savedPack = Self.startupPack(from: savedPackID, premiumUnlocked: true),
                   savedPack.isPremium {
                    selectUnlockedPremiumPack(savedPack)
                }
            }

            statusMessage = purchaseStore.statusMessage ?? "Premium ASMR packs unlocked."
            return
        }

        if currentPack.isPremium && previewPack == nil {
            currentPack = .plasticTapping
            highlightedPackID = TechPack.plasticTapping.id
            persistSelectedPack(.plasticTapping)
            restoreBuiltInPack(packID: TechPack.plasticTapping.id)
        }

        statusMessage = purchaseStore.statusMessage ?? monitoringSummary()
    }

    private func selectUnlockedPremiumPack(_ pack: TechPack) {
        guard pack.isAvailable else { return }
        currentPack = pack
        highlightedPackID = pack.id
        persistSelectedPack(pack)
        restoreBuiltInPack(packID: pack.id)
    }

    private var hasSeenCurrentWelcome: Bool {
        let welcomeVersionSeen = userDefaults.integer(forKey: DefaultsKey.welcomeVersionSeen)
        return welcomeVersionSeen >= Self.currentWelcomeVersion
    }

    private func presentWelcomeIfNeeded(delay: TimeInterval = 0.6) {
        guard !hasSeenCurrentWelcome else { return }
        guard !isWelcomePresentationScheduled else { return }
        isWelcomePresentationScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.isWelcomePresentationScheduled = false
            guard !self.hasSeenCurrentWelcome else { return }
            self.showWelcomeWindow()
        }
    }

    private func monitoringSummary() -> String {
        guard isEnabled else { return "Auditory typing feedback is paused." }
        guard soundLibrary.totalSoundCount > 0 else { return soundLibrary.lastLoadMessage }

        switch setupPhase {
        case .needsPermission:
            return "Waiting for permission. Tappy only uses physical key codes for local auditory feedback."
        case .needsRestart:
            return "Permission granted. Restart Tappy to activate system-wide auditory feedback."
        case .complete:
            if backgroundCaptureState == .unavailable {
                return "Input Monitoring appears available, but the listen-only event tap failed to start."
            }
            return "Auditory typing feedback is active system-wide."
        }
    }

    private func attemptListenerAttachIfNeeded() {
        guard Self.shouldAttemptInputMonitoring(
            isEnabled: isEnabled,
            hasSeenWelcome: hasSeenCurrentWelcome,
            isTrusted: permissionManager.isTrusted
        ) else {
            if keyboardMonitor.isMonitoring {
                keyboardMonitor.stop()
            }
            return
        }

        if keyboardMonitor.captureState == .ready {
            if backgroundCaptureState != .ready {
                backgroundCaptureState = .ready
                reconcileSetupPhase()
            }
            return
        }

        keyboardMonitor.start { [weak self] trigger in
            MainActor.assumeIsolated {
                self?.handle(trigger: trigger)
            }
        }
    }

    private func reconcileSetupPhase() {
        let previous = setupPhase
        setupPhase = Self.setupPhase(
            trusted: permissionManager.isTrusted,
            captureState: backgroundCaptureState
        )
        if setupPhase != previous { telemetry.record("setup_changed", properties: ["setup": setupPhase.analyticsValue]) }
    }

    private func persistSelectedPack(_ pack: TechPack) {
        userDefaults.set(pack.id, forKey: DefaultsKey.selectedPackID)
    }

    private func cancelPendingCTA() {
        pendingCTAWorkItem?.cancel()
        pendingCTAWorkItem = nil
    }

    nonisolated static func setupPhase(
        trusted: Bool,
        captureState: KeyboardMonitor.CaptureState
    ) -> SetupPhase {
        guard trusted else { return .needsPermission }

        if captureState == .ready {
            return .complete
        }

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

private struct WelcomeView: View {
    static let width: CGFloat = 288
    static let height: CGFloat = 360

    @EnvironmentObject private var controller: KeyboardSoundController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
                .padding(.bottom, 10)

            Text("Tappy uses Input Monitoring")
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Text("Tappy needs permission to play typing feedback in other apps.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 10) {
                instruction(number: 1, text: "Choose Open System Settings in the macOS prompt.")
                instruction(number: 2, text: "Enable Tappy under Privacy & Security > Input Monitoring.")
                instruction(number: 3, text: "Return to Tappy and restart if requested.")
            }
            .padding(.top, 14)

            Text("Tappy uses key codes only and never reads or stores what you type.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Spacer(minLength: 8)

            Button {
                controller.finishWelcome()
            } label: {
                Text("OK")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        }
    }

    private func instruction(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 16, alignment: .trailing)

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private final class TappyAppURLHandler: NSObject {
    private weak var controller: KeyboardSoundController?
    private var isInstalled = false

    init(controller: KeyboardSoundController) {
        self.controller = controller
        super.init()
        install()
    }

    func invalidate() {
        guard isInstalled else { return }
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        isInstalled = false
    }

    private func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        isInstalled = true
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: rawURL)
        else {
            return
        }

        Task { @MainActor [weak controller] in
            controller?.handleIncomingURL(url)
        }
    }
}

private extension SetupPhase {
    var analyticsValue: String {
        switch self {
        case .needsPermission: return "needs_permission"
        case .needsRestart: return "needs_restart"
        case .complete: return "complete"
        }
    }
}
