import AppKit
import Foundation
import StoreKit

@MainActor
final class PremiumStore: ObservableObject {
    static let unlockAllProductID = "com.castao.tappy.unlockall"
    private static let productLoadTimeoutNanoseconds: UInt64 = 12_000_000_000

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

    var isBusy: Bool {
        isLoading || isPurchasing
    }

    func refreshStore() async {
        isLoading = true
        defer { isLoading = false }

        await refreshEntitlements()

        do {
            let products = try await loadProductsWithTimeout()
            unlockAllProduct = products.first

            if unlockAllProduct == nil {
                lastMessage = "Premium unlock is not available from the App Store yet. Check the product ID and App Store Connect setup."
            } else if !hasUnlockedPremium {
                lastMessage = nil
            }
        } catch StoreError.productLoadTimedOut {
            unlockAllProduct = nil
            lastMessage = "The App Store did not respond. Check your connection and try again."
        } catch {
            unlockAllProduct = nil
            lastMessage = "Store unavailable: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func prepareUnlockAllForPurchase() async -> Bool {
        if hasUnlockedPremium {
            lastMessage = "Premium packs are already unlocked."
            return true
        }

        if unlockAllProduct != nil {
            return true
        }

        await refreshStore()
        return unlockAllProduct != nil
    }

    func purchaseUnlockAll(confirmIn window: NSWindow) async {
        guard !isPurchasing else {
            lastMessage = "A purchase is already in progress."
            return
        }

        guard let unlockAllProduct else {
            lastMessage = "Premium unlock is not ready yet. Try again after the price finishes loading."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result: Product.PurchaseResult
            if #available(macOS 15.2, *) {
                result = try await unlockAllProduct.purchase(confirmIn: window)
            } else {
                result = try await unlockAllProduct.purchase()
            }

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
        } catch is CancellationError {
            lastMessage = "Purchase cancelled."
        } catch {
            if Task.isCancelled {
                lastMessage = "Purchase cancelled."
            } else {
                lastMessage = "Purchase failed: \(error.localizedDescription)"
            }
        }
    }

    func restorePurchases() async {
        guard !isPurchasing else {
            lastMessage = "Finish or cancel the current purchase before restoring."
            return
        }

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

    private func loadProductsWithTimeout() async throws -> [Product] {
        let race = ProductLoadRace()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.start(
                    productID: Self.unlockAllProductID,
                    timeoutNanoseconds: Self.productLoadTimeoutNanoseconds,
                    continuation: continuation
                )
            }
        } onCancel: {
            race.cancel()
        }
    }

    private final class ProductLoadRace {
        private let lock = NSLock()
        private var didFinish = false
        private var continuation: CheckedContinuation<[Product], Error>?
        private var productTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?

        func start(
            productID: String,
            timeoutNanoseconds: UInt64,
            continuation: CheckedContinuation<[Product], Error>
        ) {
            lock.lock()
            if didFinish {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            lock.unlock()

            let productTask = Task {
                do {
                    let products = try await Product.products(for: [productID])
                    finish(.success(products))
                } catch {
                    finish(.failure(error))
                }
            }

            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    finish(.failure(StoreError.productLoadTimedOut))
                } catch {
                    // Cancelled because product loading finished first.
                }
            }

            lock.lock()
            if didFinish {
                lock.unlock()
                productTask.cancel()
                timeoutTask.cancel()
                return
            }
            self.productTask = productTask
            self.timeoutTask = timeoutTask
            lock.unlock()
        }

        func cancel() {
            finish(.failure(CancellationError()))
        }

        private func finish(_ result: Result<[Product], Error>) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }

            didFinish = true
            let continuation = continuation
            let productTask = productTask
            let timeoutTask = timeoutTask
            self.continuation = nil
            self.productTask = nil
            self.timeoutTask = nil
            lock.unlock()

            productTask?.cancel()
            timeoutTask?.cancel()
            continuation?.resume(with: result)
        }
    }
}

extension PremiumStore {
    enum StoreError: LocalizedError {
        case failedVerification
        case productLoadTimedOut

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return "Store transaction could not be verified."
            case .productLoadTimedOut:
                return "The App Store did not respond."
            }
        }
    }
}
