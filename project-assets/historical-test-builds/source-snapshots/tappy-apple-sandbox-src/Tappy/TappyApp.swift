import AppKit
import StoreKit

/// Stores requests, rather than displayed prompts: StoreKit decides whether to show one.
final class ReviewPromptSchedule {
    enum Request { case firstLaunch, oneWeek }
    private let defaults: UserDefaults
    private let firstOpenedKey = "Tappy.reviewFirstOpenedAt"
    private let firstRequestedKey = "Tappy.reviewFirstRequested"
    private let weekRequestedKey = "Tappy.reviewWeekRequested"
    private let week: TimeInterval = 7 * 24 * 60 * 60

    init(defaults: UserDefaults, now: Date, existingInstallation: Bool) {
        self.defaults = defaults
        if defaults.object(forKey: firstOpenedKey) == nil {
            defaults.set(now, forKey: firstOpenedKey)
            if existingInstallation {
                defaults.set(true, forKey: firstRequestedKey)
            }
        }
    }

    func due(at now: Date) -> Request? {
        if !defaults.bool(forKey: firstRequestedKey) { return .firstLaunch }
        guard !defaults.bool(forKey: weekRequestedKey),
              let firstOpened = defaults.object(forKey: firstOpenedKey) as? Date,
              now.timeIntervalSince(firstOpened) >= week else { return nil }
        return .oneWeek
    }

    func markRequested(_ request: Request) {
        switch request {
        case .firstLaunch: defaults.set(true, forKey: firstRequestedKey)
        case .oneWeek: defaults.set(true, forKey: weekRequestedKey)
        }
    }
}

/// StoreKit doesn't report whether its review prompt appeared or closed. Wait
/// for a later menu interaction rather than layering consent over the request.
struct AnalyticsConsentOfferGate {
    private(set) var lastReviewRequest: Date?
    private let minimumDelay: TimeInterval = 3

    mutating func didRequestReview(at date: Date) {
        lastReviewRequest = date
    }

    func canOffer(at date: Date, initialReviewPending: Bool, isActive: Bool,
                  hasModalOrSheet: Bool) -> Bool {
        guard !initialReviewPending, isActive, !hasModalOrSheet else { return false }
        guard let lastReviewRequest else { return true }
        return date.timeIntervalSince(lastReviewRequest) >= minimumDelay
    }
}

@main
final class TappyAppDelegate: NSObject, NSApplicationDelegate {
    private static var sharedDelegate: TappyAppDelegate?

    private var controller: KeyboardSoundController?
    private var reviewSchedule: ReviewPromptSchedule?
    private var reviewTimer: Timer?
    private var reviewReady = false
    private var consentOfferGate = AnalyticsConsentOfferGate()
    private var menuObserver: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = TappyAppDelegate()
        sharedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        let defaults = UserDefaults(suiteName: "com.castao.tappy.purchase-sandbox-test")!
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(true, forKey: "Tappy.reviewFirstRequested")
        defaults.set(true, forKey: "Tappy.reviewWeekRequested")
        let existingInstallation = defaults.bool(forKey: "Tappy.hasSeenWelcome") || defaults.integer(forKey: "Tappy.welcomeVersionSeen") > 0
        reviewSchedule = ReviewPromptSchedule(defaults: defaults, now: Date(), existingInstallation: existingInstallation)
        controller = KeyboardSoundController(userDefaults: defaults)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let url = URL(string: "tappy://menu") else { return }
            self?.controller?.handleIncomingURL(url)
        }
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didShowNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.offerAnalyticsConsentAfterMenuInteraction() }
        }
        // Let the first-launch welcome window appear before requesting the system sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.reviewReady = true
            self?.requestReviewIfDue()
        }
        reviewTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.requestReviewIfDue()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller?.handleAppDidBecomeActive()
        requestReviewIfDue()
    }

    func applicationDidResignActive(_ notification: Notification) {
        controller?.handleAppDidResignActive()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestReviewIfDue() {
        guard reviewReady, NSApp.isActive, NSApp.modalWindow == nil,
              let schedule = reviewSchedule, let request = schedule.due(at: Date()) else { return }
        schedule.markRequested(request)
        consentOfferGate.didRequestReview(at: Date())
        SKStoreReviewController.requestReview()
    }

    @MainActor
    private func offerAnalyticsConsentAfterMenuInteraction() {
        guard reviewReady, let schedule = reviewSchedule else { return }
        let initialReviewPending = schedule.due(at: Date()) == .firstLaunch
        let hasModalOrSheet = NSApp.modalWindow != nil || NSApp.windows.contains { $0.attachedSheet != nil }
        guard consentOfferGate.canOffer(at: Date(), initialReviewPending: initialReviewPending,
                                        isActive: NSApp.isActive, hasModalOrSheet: hasModalOrSheet) else { return }
        controller?.presentAnalyticsConsentIfNeeded()
    }
}
