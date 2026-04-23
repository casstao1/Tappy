import Foundation
import StoreKit

@MainActor
final class PremiumStore: ObservableObject {
    static let unlockAllProductID = "com.castao.tappy.unlockall"

    @Published private(set) var unlockAllProduct: Product?
    @Published private(set) var hasUnlockedPremium = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var lastMessage: String?

    var onUnlockStateChange: ((Bool) -> Void)?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()

        Task {
            await refreshStore()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var unlockAllPrice: String {
        unlockAllProduct?.displayPrice ?? "$4.99"
    }

    func refreshStore() async {
        isLoading = true
        defer { isLoading = false }

        await refreshEntitlements()

        do {
            let products = try await Product.products(for: [Self.unlockAllProductID])
            unlockAllProduct = products.first

            if unlockAllProduct == nil {
                lastMessage = "In-app purchase product is not configured for this build yet."
            } else if !hasUnlockedPremium {
                lastMessage = nil
            }
        } catch {
            unlockAllProduct = nil
            lastMessage = "Store unavailable: \(error.localizedDescription)"
        }
    }

    func purchaseUnlockAll() async {
        if unlockAllProduct == nil {
            await refreshStore()
        }

        guard let unlockAllProduct else {
            lastMessage = "Unlock product is not available in this build yet."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await unlockAllProduct.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                applyUnlocked(transaction.revocationDate == nil)
                await transaction.finish()
                lastMessage = hasUnlockedPremium ? "Premium packs unlocked." : "Unlock could not be confirmed."

            case .pending:
                lastMessage = "Purchase is pending approval."

            case .userCancelled:
                lastMessage = "Purchase cancelled."

            @unknown default:
                lastMessage = "Purchase did not complete."
            }
        } catch {
            lastMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastMessage = hasUnlockedPremium
                ? "Premium purchase restored."
                : "No premium purchase was found to restore."
        } catch {
            lastMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)

                    if transaction.productID == Self.unlockAllProductID {
                        applyUnlocked(transaction.revocationDate == nil)
                    }

                    await transaction.finish()
                } catch {
                    lastMessage = "Transaction verification failed."
                }
            }
        }
    }

    private func refreshEntitlements() async {
        var unlocked = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == Self.unlockAllProductID, transaction.revocationDate == nil {
                unlocked = true
                break
            }
        }

        applyUnlocked(unlocked)
    }

    private func applyUnlocked(_ unlocked: Bool) {
        let changed = hasUnlockedPremium != unlocked
        hasUnlockedPremium = unlocked

        if changed {
            onUnlockStateChange?(unlocked)
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

extension PremiumStore {
    enum StoreError: LocalizedError {
        case failedVerification

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return "Store transaction could not be verified."
            }
        }
    }
}
