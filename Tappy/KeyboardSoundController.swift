import AppKit
import Combine
import Foundation

@MainActor
final class KeyboardSoundController: ObservableObject {
    private enum DefaultsKey {
        static let inputMonitoringPromptShown = "Tappy.inputMonitoringPromptShown"
        static let setupCompleted = "Tappy.setupCompleted"
        static let manualPermissionOverride = "Tappy.inputMonitoringManualOverride"
        static let selectedPackID = "Tappy.selectedPackID"
        static let premiumUnlocked = "Tappy.premiumUnlocked"
    }

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
    @Published private(set) var setupCompleted = false
    @Published private(set) var manualPermissionOverride = false
    @Published private(set) var premiumUnlocked = false

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
        setupCompleted = userDefaults.bool(forKey: DefaultsKey.setupCompleted)
        manualPermissionOverride = userDefaults.bool(forKey: DefaultsKey.manualPermissionOverride)
        premiumUnlocked = userDefaults.bool(forKey: DefaultsKey.premiumUnlocked)

        // The manual override is only meant to paper over a macOS reporting
        // quirk within a single session. If we relaunch and the OS still
        // reports Input Monitoring as denied, drop the stale override so the
        // setup gate reappears instead of pretending everything is fine.
        if manualPermissionOverride, !permissionManager.isTrusted {
            manualPermissionOverride = false
            userDefaults.set(false, forKey: DefaultsKey.manualPermissionOverride)
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
            self.userDefaults.set(unlocked, forKey: DefaultsKey.premiumUnlocked)

            if !unlocked, self.currentPack.isPremium {
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

                if trusted {
                    // Real permission confirmed by macOS — drop any stale
                    // manual override the user set before permission existed.
                    if self.manualPermissionOverride {
                        self.manualPermissionOverride = false
                        self.userDefaults.set(false, forKey: DefaultsKey.manualPermissionOverride)
                    }

                    // If the event tap hasn't actually attached yet, (re)start
                    // it now that permission is live. Without this the app
                    // keeps running with a zombie tap even after the user
                    // flips the switch in Settings.
                    if self.isEnabled, self.backgroundCaptureState != .ready {
                        self.keyboardMonitor.start { [weak self] trigger in
                            DispatchQueue.main.async {
                                self?.handle(trigger: trigger)
                            }
                        }
                    }
                }

                self.statusMessage = self.monitoringSummary()
            }
        }
        keyboardMonitor.onCaptureStateChange = { [weak self] state in
            Task { @MainActor in
                self?.backgroundCaptureState = state
                self?.statusMessage = self?.monitoringSummary() ?? ""
            }
        }

        _ = try? soundLibrary.restoreBundledPack(packID: currentPack.id)
        reloadSounds()
        updateMonitoringState()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            self.autoRequestInputMonitoringIfNeeded()
        }
    }

    deinit {
        keyboardMonitor.stop()
    }

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

    var shouldShowSetupGate: Bool {
        !setupCompleted || !hasSatisfiedSetupAccess
    }

    var isReadyForHomeScreen: Bool {
        manualPermissionOverride ||
            (permissionManager.hasGlobalMonitoringAccess && backgroundCaptureState != .unavailable)
    }

    var canUseManualPermissionOverride: Bool {
        !permissionManager.hasGlobalMonitoringAccess
    }

    private var hasSatisfiedSetupAccess: Bool {
        permissionManager.hasGlobalMonitoringAccess || manualPermissionOverride
    }

    var setupHeadline: String {
        if permissionManager.hasGlobalMonitoringAccess {
            if backgroundCaptureState == .unavailable {
                return "Almost there"
            }
            return "You’re ready"
        }

        return "Enable keyboard access"
    }

    var setupDetail: String {
        if permissionManager.hasGlobalMonitoringAccess {
            if backgroundCaptureState == .unavailable {
                return "Tappy has permission, but the background listener did not attach on this launch. Refresh once or relaunch the app."
            }
            return "Tappy can play your clicks across the Mac. Press the button below to enter the home screen."
        }

        return "Tappy could not confirm Input Monitoring for this launch. If Tappy is already enabled in System Settings, quit and reopen the app once, then check again."
    }

    var setupChecklist: [SetupItem] {
        return [
            SetupItem(
                title: "Input Monitoring",
                detail: permissionManager.isTrusted
                    ? "Tappy is approved in Privacy & Security."
                    : manualPermissionOverride
                        ? "You manually confirmed the setting because macOS did not report it back to the app."
                        : "If Tappy is already enabled in Privacy & Security, relaunch the app once. Otherwise turn it on there first.",
                isComplete: permissionManager.isTrusted || manualPermissionOverride,
                actionTitle: "Open Settings",
                action: { [weak self] in
                    self?.openInputMonitoringSettings()
                }
            ),
            SetupItem(
                title: "Listener Ready",
                detail: backgroundCaptureState == .ready
                    ? "The background keyboard listener is attached."
                    : "If access is already enabled, refresh or relaunch Tappy once.",
                isComplete: permissionManager.isTrusted && backgroundCaptureState == .ready,
                actionTitle: "Refresh",
                action: { [weak self] in
                    self?.refreshInputMonitoringStatus()
                }
            )
        ]
    }

    var compactStatus: String {
        if !isEnabled {
            return "Paused"
        }
        if permissionManager.hasGlobalMonitoringAccess {
            return "Live"
        }
        return "Window Only"
    }

    var permissionDebugSummary: String {
        "Input \(permissionManager.isTrusted ? "On" : "Off")"
    }

    var highlightedPack: TechPack {
        availablePacks.first(where: { $0.id == highlightedPackID }) ?? currentPack
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

    var launchWarning: String? {
        if !permissionManager.isTrusted {
            return "Tappy could not confirm Input Monitoring for this launch."
        }

        if isEnabled && backgroundCaptureState == .unavailable {
            return "Background capture failed to start for this launch."
        }

        return nil
    }

    var stableAppPath: String {
        stableAppURL.path
    }

    var installedPreviewAppPath: String {
        installedPreviewAppURL.path
    }

    private var stableAppURL: URL {
        if fileManager.fileExists(atPath: installedPreviewAppURL.path) {
            return installedPreviewAppURL
        }

        return workspaceAppURL
    }

    private var installedPreviewAppURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Tappy Preview.app", isDirectory: true)
    }

    private var workspaceAppURL: URL {
        URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Tappy.app", isDirectory: true)
    }

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
        NSWorkspace.shared.openApplication(at: stableAppURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Spawns a fresh instance of the current app and quits this one. After
    /// enabling Input Monitoring in System Settings, macOS often requires a
    /// relaunch before the event tap can actually attach.
    func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundleURL.path]
        try? task.run()

        // Give the new instance a moment to start before we exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.terminate(nil)
        }
    }

    func importSounds(into category: SoundCategory = .standard) {
        let panel = NSOpenPanel()
        panel.title = "Import Keyboard Sounds"
        panel.message = "Choose audio files to copy into the app's \(category.displayName) sound folder."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []

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

        guard !isPackLocked(pack) else {
            statusMessage = "Preview \(pack.name) here. Unlock premium packs to activate it."
            return
        }

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
            do {
                try soundLibrary.previewBundledSound(packID: pack.id, category: category, using: audioEngine)
                statusMessage = "Previewing \(pack.name) \(category.displayName.lowercased()) sound."
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        preview(category: category)
    }

    func beginUnlockPremiumFlow() {
        Task {
            await premiumStore.refreshStore()
            statusMessage = premiumStore.lastMessage ?? "Premium packs are ready to unlock."
        }
    }

    func purchasePremiumUnlock() async {
        await premiumStore.purchaseUnlockAll()

        if premiumUnlocked, highlightedPack.isPremium {
            highlightPack(highlightedPack)
        }

        statusMessage = premiumStore.lastMessage ?? monitoringSummary()
    }

    func restorePremiumPurchases() async {
        await premiumStore.restorePurchases()

        if premiumUnlocked, highlightedPack.isPremium {
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
        if permissionManager.hasGlobalMonitoringAccess, isEnabled {
            keyboardMonitor.start { [weak self] trigger in
                DispatchQueue.main.async {
                    self?.handle(trigger: trigger)
                }
            }
        }
        statusMessage = monitoringSummary()
    }

    func openInputMonitoringSettings() {
        permissionManager.openInputMonitoringSettings()
    }

    func openSoundSettings() {
        permissionManager.openSoundSettings()
    }

    func preview(category: SoundCategory) {
        audioEngine.play(category: category, keyCode: nil)
    }

    func completeSetupAndEnterHome() {
        guard isReadyForHomeScreen else { return }
        setupCompleted = true
        userDefaults.set(true, forKey: DefaultsKey.setupCompleted)
        statusMessage = monitoringSummary()
    }

    func confirmPermissionOverride() {
        manualPermissionOverride = true
        userDefaults.set(true, forKey: DefaultsKey.manualPermissionOverride)
        setupCompleted = true
        userDefaults.set(true, forKey: DefaultsKey.setupCompleted)
        statusMessage = "Continuing with your manual Input Monitoring confirmation."
    }

    private func updateMonitoringState() {
        audioEngine.setEnabled(isEnabled)

        if isEnabled {
            keyboardMonitor.start { [weak self] trigger in
                DispatchQueue.main.async {
                    self?.handle(trigger: trigger)
                }
            }
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
        guard isEnabled else {
            return "Keyboard sounds are paused."
        }

        guard soundLibrary.totalSoundCount > 0 else {
            return soundLibrary.lastLoadMessage
        }

        if permissionManager.hasGlobalMonitoringAccess {
            if backgroundCaptureState == .unavailable {
                return "Input Monitoring appears available, but the background event tap failed to start."
            }
            return "Keyboard sounds are active system-wide."
        }

        return "Keyboard sounds are active in this window. If Input Monitoring is already enabled, relaunch the app once to restore system-wide clicks."
    }

    private func autoRequestInputMonitoringIfNeeded() {
        // Always ask on launch when we aren't trusted. CGRequestListenEventAccess
        // is idempotent — macOS only shows the dialog the first time per install
        // (or after the user removes us from Input Monitoring), so calling it
        // every cold start is safe and crucial: without this the user can
        // revoke permission, relaunch, and get no prompt at all.
        if !permissionManager.isTrusted {
            userDefaults.set(true, forKey: DefaultsKey.inputMonitoringPromptShown)
            permissionManager.requestListenAccessPrompt()
        }

        statusMessage = monitoringSummary()
    }

    private func persistSelectedPack(_ pack: TechPack) {
        userDefaults.set(pack.id, forKey: DefaultsKey.selectedPackID)
    }

    func isPackLocked(_ pack: TechPack) -> Bool {
        pack.isPremium && !premiumUnlocked
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

extension KeyboardSoundController {
    struct SetupItem: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let isComplete: Bool
        let actionTitle: String
        let action: () -> Void
    }
}
