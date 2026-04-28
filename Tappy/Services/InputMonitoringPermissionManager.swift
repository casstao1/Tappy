import AppKit
import ApplicationServices
import Foundation

@MainActor
final class InputMonitoringPermissionManager: ObservableObject {
    @Published private(set) var isTrusted = CGPreflightListenEventAccess()

    var onStatusChange: ((Bool) -> Void)?

    private var pollTimer: DispatchSourceTimer?
    private var burstRefreshWorkItems: [DispatchWorkItem] = []
    private let pollQueue = DispatchQueue(label: "com.castao.tappy.input-monitoring-poll")

    init() {
        startPolling()
    }

    deinit {
        pollTimer?.cancel()
        burstRefreshWorkItems.forEach { $0.cancel() }
    }

    func refreshStatus(forceNotify: Bool = false) {
        let trusted = CGPreflightListenEventAccess()

        let didChange = trusted != isTrusted
        if didChange {
            isTrusted = trusted
        }

        if didChange || forceNotify {
            onStatusChange?(isTrusted)
        }
    }

    func requestListenAccessPrompt() {
        // Do NOT activate the app before calling CGRequestListenEventAccess().
        // Activating first brings the Tappy window to the front, which causes
        // the macOS permission dialog to appear behind it. Let the dialog appear
        // naturally — macOS will place it in front of the app window on its own.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let granted = CGRequestListenEventAccess()
            self.isTrusted = granted
            self.onStatusChange?(self.isTrusted)
            self.scheduleRefreshBurst()
        }
    }

    var hasGlobalMonitoringAccess: Bool {
        isTrusted
    }

    func openInputMonitoringSettings() {
        refreshStatus(forceNotify: true)

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }

        openAndFocusSystemSettings(url: url)
        scheduleRefreshBurst()
    }

    func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else {
            return
        }

        openAndFocusSystemSettings(url: url)
    }

    private func openAndFocusSystemSettings(url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open([url], withApplicationAt: settingsURL, configuration: configuration) { _, _ in
                Task { @MainActor in
                    self.activateSystemSettings()
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Task { @MainActor in
                self.activateSystemSettings()
            }
        }
    }

    private func activateSystemSettings() {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .first?
            .activate(options: [.activateAllWindows])
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + 0.75, repeating: 0.75)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
        pollTimer = timer
        timer.resume()
    }

    func scheduleRefreshBurst() {
        burstRefreshWorkItems.forEach { $0.cancel() }
        burstRefreshWorkItems.removeAll()

        let delays: [TimeInterval] = [0.15, 0.4, 0.8, 1.4, 2.2, 3.0]
        for delay in delays {
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.refreshStatus(forceNotify: true)
                }
            }
            burstRefreshWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
}
