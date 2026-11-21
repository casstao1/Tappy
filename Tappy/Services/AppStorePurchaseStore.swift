import Foundation
import StoreKit

/// Manages the App Store's non-consumable unlock and verified entitlements.
@MainActor
final class AppStorePurchaseStore: ObservableObject {
    static let productID = "com.castao.tappy.unlockall"
    enum PurchaseOutcome: String { case success, pending, cancelled, failed, unavailable }
    enum EntitlementEvidence { case verifiedActive, verifiedRevoked, unverified }
    enum LegacyAppEvidence { case verified(originalVersion: String, revoked: Bool), unverified }
    @Published private(set) var hasUnlockedPremium: Bool
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var displayPrice: String?
    @Published private(set) var lastPurchaseOutcome: PurchaseOutcome = .unavailable

    private var product: Product?
    private var updatesTask: Task<Void, Never>?
    private var hasStoreEntitlement = false
    private var hasLegacyAppEntitlement = false
    private var entitlementRevision = 0
    #if DEBUG
    var debugPurchaseAction: (() async throws -> PurchaseOutcome)?
    var debugRestoreAction: (() async throws -> Bool)?
    var debugRefreshAction: (() async -> Void)?
    var debugPriceRefreshAction: (() async -> Void)?
    var debugEntitlementScan: (() async -> Bool)?
    var debugLegacyAppScan: (() async -> LegacyAppEvidence)?
    var debugSkipProductLoad = false

    func debugSetSimulatedPrice(_ price: String?) {
        displayPrice = price
    }
    #endif
    init() {
        hasUnlockedPremium = false
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func refresh() async {
        #if DEBUG
        if let debugRefreshAction {
            await debugRefreshAction()
            return
        }
        #endif
        await refreshEntitlements()
        await refreshLegacyAppEntitlement()
        #if DEBUG
        if debugSkipProductLoad { return }
        #endif
        await loadProduct()
    }

    /// Refresh only the product metadata without disturbing verified access.
    func refreshPrice() async {
        #if DEBUG
        if let debugPriceRefreshAction {
            await debugPriceRefreshAction()
            return
        }
        #endif
        await loadProduct()
    }

    private func loadProduct() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.productID]).first
            displayPrice = product?.displayPrice
            if product == nil {
                statusMessage = "The App Store unlock is currently unavailable. Please try again later."
            } else if statusMessage == "The App Store unlock is currently unavailable. Please try again later."
                        || statusMessage == "Unable to load the App Store unlock. Please try again later." {
                statusMessage = "App Store price loaded. Tap Buy to continue."
            }
        } catch {
            product = nil
            displayPrice = nil
            statusMessage = "Unable to load the App Store unlock. Please try again later."
        }
    }

    @discardableResult
    func purchase() async -> Bool {
        guard !isPurchasing && !isRestoring else {
            lastPurchaseOutcome = .unavailable
            return hasUnlockedPremium
        }
        lastPurchaseOutcome = .unavailable
        isPurchasing = true
        defer { isPurchasing = false }
        #if DEBUG
        if let debugPurchaseAction {
            do { applyPurchaseOutcome(try await debugPurchaseAction()) }
            catch { applyPurchaseOutcome(.failed) }
            return hasUnlockedPremium
        }
        #endif
        if product == nil { await loadProduct() }
        guard let product else {
            if isLoading { statusMessage = "The App Store unlock is still loading. Please try again." }
            return hasUnlockedPremium
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    guard transaction.productID == Self.productID, transaction.revocationDate == nil else {
                        applyPurchaseOutcome(.failed)
                        return hasUnlockedPremium
                    }
                    applyPurchaseOutcome(.success)
                    await transaction.finish()
                case .unverified:
                    applyPurchaseOutcome(.failed)
                }
            case .pending:
                applyPurchaseOutcome(.pending)
            case .userCancelled:
                applyPurchaseOutcome(.cancelled)
            @unknown default:
                applyPurchaseOutcome(.failed)
            }
        } catch {
            applyPurchaseOutcome(.failed)
        }
        return hasUnlockedPremium
    }

    @discardableResult
    func restore() async -> Bool {
        guard !isPurchasing && !isRestoring else { return hasUnlockedPremium }
        isRestoring = true
        defer { isRestoring = false }
        do {
            #if DEBUG
            if let debugRestoreAction {
                let found = try await debugRestoreAction()
                applyEvidence(found ? .verifiedActive : .verifiedRevoked)
                updateRestoreMessage()
                return hasUnlockedPremium
            }
            #endif
            try await AppStore.sync()
            await refreshEntitlements()
            await refreshLegacyAppEntitlement()
            updateRestoreMessage()
        } catch {
            statusMessage = "Unable to restore purchases. Please try again."
        }
        return hasUnlockedPremium
    }

    private func refreshEntitlements() async {
        let revision = entitlementRevision
        #if DEBUG
        if let debugEntitlementScan {
            let found = await debugEntitlementScan()
            applyScannedEntitlements(found, revision: revision)
            return
        }
        #endif
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                found = true
            }
        }
        applyScannedEntitlements(found, revision: revision)
    }

    private func applyScannedEntitlements(_ found: Bool, revision: Int) {
        // A verified purchase or update received during the scan is newer.
        guard revision == entitlementRevision else { return }
        hasStoreEntitlement = found
        updateAccess()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, transaction.productID == Self.productID else { return }
        if transaction.revocationDate == nil {
            // An approved pending purchase can arrive before currentEntitlements catches up.
            applyEvidence(.verifiedActive)
            statusMessage = "All sound packs are unlocked."
        } else {
            applyEvidence(.verifiedRevoked)
        }
        await transaction.finish()
    }

    private func refreshLegacyAppEntitlement() async {
        #if DEBUG
        if let debugLegacyAppScan {
            applyLegacyAppEvidence(await debugLegacyAppScan())
            return
        }
        #endif
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction):
                // AppTransaction.revocationDate was added in the Xcode 27 SDK and
                // back-deploys to macOS 13. Older SDKs lack the property entirely.
                #if compiler(>=6.4)
                let revoked = transaction.revocationDate != nil
                #else
                let revoked = false
                #endif
                applyLegacyAppEvidence(.verified(originalVersion: transaction.originalAppVersion,
                                                 revoked: revoked))
            case .unverified:
                applyLegacyAppEvidence(.unverified)
            }
        } catch {
            // An unavailable or unverified app transaction cannot grant access.
            // Keep any verified entitlement already established this session.
        }
    }

    // Tappy 1.1.0 included all packs; earlier free versions required an IAP.
    func applyLegacyAppEvidence(_ evidence: LegacyAppEvidence) {
        switch evidence {
        case .verified(let originalVersion, let revoked):
            hasLegacyAppEntitlement = originalVersion == "1.1.0" && !revoked
            updateAccess()
        case .unverified:
            break
        }
    }

    // Only verified transactions may alter access; failed verification leaves it unchanged.
    func applyEvidence(_ evidence: EntitlementEvidence) {
        switch evidence {
        case .verifiedActive: hasStoreEntitlement = true
        case .verifiedRevoked: hasStoreEntitlement = false
        case .unverified: return
        }
        entitlementRevision += 1
        updateAccess()
    }

    private func applyPurchaseOutcome(_ outcome: PurchaseOutcome) {
        lastPurchaseOutcome = outcome
        switch outcome {
        case .success:
            applyEvidence(.verifiedActive)
            statusMessage = "All sound packs are unlocked."
        case .pending:
            statusMessage = "The purchase is pending approval. Tappy will unlock when it completes."
        case .cancelled:
            statusMessage = nil
        case .failed:
            statusMessage = "The purchase could not be completed or verified. Please try again."
        case .unavailable:
            statusMessage = "The App Store unlock is currently unavailable. Please try again later."
        }
    }

    private func updateRestoreMessage() {
        statusMessage = hasUnlockedPremium ? "All sound packs are unlocked." : "No previous unlock was found for this Apple Account."
    }

    private func updateAccess() {
        hasUnlockedPremium = hasStoreEntitlement || hasLegacyAppEntitlement
    }
}
