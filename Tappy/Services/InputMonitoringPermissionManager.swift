import AppKit
import ApplicationServices
import Foundation

@MainActor
final class InputMonitoringPermissionManager: ObservableObject {
    @Published private(set) var isTrusted = CGPreflightListenEventAccess()

    var onStatusChange: ((Bool) -> Void)?

    private var pollTimer: Timer?

    init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    func refreshStatus() {
        let trusted = CGPreflightListenEventAccess()

        guard trusted != isTrusted else { return }
        isTrusted = trusted
        onStatusChange?(isTrusted)
    }

    func requestListenAccessPrompt() {
        let granted = CGRequestListenEventAccess()
        if granted != isTrusted {
            isTrusted = granted
            onStatusChange?(isTrusted)
        }
    }

    var hasGlobalMonitoringAccess: Bool {
        isTrusted
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }
}
