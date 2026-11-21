import XCTest
import Combine
@testable import Tappy

#if DEBUG
@MainActor
final class AppStorePurchaseStoreTests: XCTestCase {
    enum FakeError: Error { case unavailable }

    func testExistingUnlockIsRestoredAutomaticallyAtLaunchForEveryPack() async throws {
        let suite = "Tappy.ExistingPurchase.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(0.0, forKey: "Tappy.clickVolume")
        defaults.set(TechPack.fart.id, forKey: "Tappy.selectedPackID")
        let store = AppStorePurchaseStore()
        store.debugEntitlementScan = { true }
        store.debugLegacyAppScan = { .unverified }
        store.debugSkipProductLoad = true
        KeyboardSoundController.debugPurchaseStoreFactory = { store }
        KeyboardSoundController.debugSkipStoreRefresh = false
        defer {
            KeyboardSoundController.debugPurchaseStoreFactory = nil
            defaults.removePersistentDomain(forName: suite)
        }
        let controller = KeyboardSoundController(userDefaults: defaults)
        let unlocked = expectation(description: "Existing entitlement unlocks all packs at launch")
        let observation = controller.$premiumUnlocked.dropFirst().filter { $0 }.prefix(1).sink { _ in unlocked.fulfill() }
        await fulfillment(of: [unlocked], timeout: 5)
        withExtendedLifetime(observation) {}
        XCTAssertTrue(TechPack.all.allSatisfy { !controller.isPackLocked($0) })
        XCTAssertEqual(controller.currentPack.id, TechPack.fart.id)
        controller.highlightPack(.thud)
        XCTAssertEqual(controller.currentPack.id, TechPack.thud.id)
    }

    func testVerifiedLegacyAppPurchaseIsIndependentOfUnlockIAP() async {
        let store = AppStorePurchaseStore()
        store.debugEntitlementScan = { false }
        store.debugLegacyAppScan = { .verified(originalVersion: "1.1.0", revoked: false) }
        store.debugSkipProductLoad = true
        await store.refresh()
        XCTAssertTrue(store.hasUnlockedPremium)
        store.applyEvidence(.verifiedRevoked)
        XCTAssertTrue(store.hasUnlockedPremium, "Revoking the IAP cannot remove a verified legacy app purchase")
        store.applyLegacyAppEvidence(.unverified)
        XCTAssertTrue(store.hasUnlockedPremium, "A failed verification cannot erase access already verified this session")
        store.applyLegacyAppEvidence(.verified(originalVersion: "1.0.9", revoked: false))
        XCTAssertFalse(store.hasUnlockedPremium, "Earlier versions were free with a separate unlock")
        store.applyLegacyAppEvidence(.verified(originalVersion: "1.2.0", revoked: false))
        XCTAssertFalse(store.hasUnlockedPremium)
        store.applyLegacyAppEvidence(.verified(originalVersion: "1.1.0", revoked: true))
        XCTAssertFalse(store.hasUnlockedPremium, "A refunded app purchase must not grant legacy access")
        store.applyEvidence(.verifiedActive)
        XCTAssertTrue(store.hasUnlockedPremium, "A verified IAP unlocks regardless of original app version")
    }

    func testPaidAppVersionUnlocksNewPacksAutomaticallyAtLaunch() async throws {
        let suite = "Tappy.ExistingPaidApp.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(0.0, forKey: "Tappy.clickVolume")
        let store = AppStorePurchaseStore()
        store.debugEntitlementScan = { false }
        store.debugLegacyAppScan = { .verified(originalVersion: "1.1.0", revoked: false) }
        store.debugSkipProductLoad = true
        KeyboardSoundController.debugPurchaseStoreFactory = { store }
        KeyboardSoundController.debugSkipStoreRefresh = false
        defer {
            KeyboardSoundController.debugPurchaseStoreFactory = nil
            defaults.removePersistentDomain(forName: suite)
        }
        let controller = KeyboardSoundController(userDefaults: defaults)
        let unlocked = expectation(description: "Paid app entitlement unlocks the current packs at launch")
        let observation = controller.$premiumUnlocked.dropFirst().filter { $0 }.prefix(1).sink { _ in unlocked.fulfill() }
        await fulfillment(of: [unlocked], timeout: 5)
        withExtendedLifetime(observation) {}
        XCTAssertTrue(TechPack.all.allSatisfy { !controller.isPackLocked($0) })
        controller.highlightPack(.thud)
        XCTAssertEqual(controller.currentPack.id, TechPack.thud.id)
    }

    func testLateEntitlementScanDoesNotEraseNewVerifiedTransaction() async {
        let store = AppStorePurchaseStore()
        store.debugLegacyAppScan = { .unverified }
        store.debugSkipProductLoad = true
        let scanStarted = expectation(description: "Entitlement scan started")
        var continuation: CheckedContinuation<Bool, Never>?
        store.debugEntitlementScan = {
            await withCheckedContinuation { pending in
                continuation = pending
                scanStarted.fulfill()
            }
        }
        let refresh = Task { await store.refresh() }
        await fulfillment(of: [scanStarted], timeout: 5)
        store.applyEvidence(.verifiedActive)
        continuation?.resume(returning: false)
        await refresh.value
        XCTAssertTrue(store.hasUnlockedPremium)
    }

    func testPurchaseUnlocksOnlyOnVerifiedSuccess() async {
        let store = AppStorePurchaseStore()
        store.debugPurchaseAction = { .pending }
        let pending = await store.purchase()
        XCTAssertFalse(pending)
        XCTAssertEqual(store.lastPurchaseOutcome, .pending)
        XCTAssertFalse(store.hasUnlockedPremium)
        store.debugPurchaseAction = { .failed }
        let failed = await store.purchase()
        XCTAssertFalse(failed)
        XCTAssertEqual(store.lastPurchaseOutcome, .failed)
        XCTAssertFalse(store.hasUnlockedPremium)
        store.debugPurchaseAction = { .success }
        let purchased = await store.purchase()
        XCTAssertTrue(purchased)
        XCTAssertEqual(store.lastPurchaseOutcome, .success)
        XCTAssertTrue(store.hasUnlockedPremium)
    }

    func testUnverifiedEvidenceCannotGrantAccessAndRevocationRemovesIt() {
        let store = AppStorePurchaseStore()
        store.applyEvidence(.unverified)
        XCTAssertFalse(store.hasUnlockedPremium)
        store.applyEvidence(.verifiedActive)
        XCTAssertTrue(store.hasUnlockedPremium)
        store.applyEvidence(.unverified)
        XCTAssertTrue(store.hasUnlockedPremium)
        store.applyEvidence(.verifiedRevoked)
        XCTAssertFalse(store.hasUnlockedPremium)
    }

    func testRestoreFoundNoneAndFailure() async {
        let store = AppStorePurchaseStore()
        store.debugRestoreAction = { true }
        let restored = await store.restore()
        XCTAssertTrue(restored)
        XCTAssertTrue(store.hasUnlockedPremium)
        store.debugRestoreAction = { throw FakeError.unavailable }
        let restoreError = await store.restore()
        XCTAssertTrue(restoreError)
        XCTAssertTrue(store.hasUnlockedPremium)
        XCTAssertEqual(store.statusMessage, "Unable to restore purchases. Please try again.")
        store.debugRestoreAction = { false }
        let notFound = await store.restore()
        XCTAssertFalse(notFound)
        XCTAssertFalse(store.hasUnlockedPremium)
    }

    func testBuyRetriesMissingProductAndShowsPriceBeforePurchasing() async throws {
        let suite = "Tappy.PurchaseRetryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(0.0, forKey: "Tappy.clickVolume")
        KeyboardSoundController.debugSkipStoreRefresh = true
        defer {
            KeyboardSoundController.debugSkipStoreRefresh = false
            defaults.removePersistentDomain(forName: suite)
        }
        let controller = KeyboardSoundController(userDefaults: defaults)
        var refreshes = 0
        var purchases = 0
        controller.purchaseStore.debugRefreshAction = {
            refreshes += 1
            controller.purchaseStore.debugSetSimulatedPrice("$2.99")
        }
        controller.purchaseStore.debugPurchaseAction = {
            purchases += 1
            return .success
        }
        defer { controller.purchaseStore.debugRefreshAction = nil }
        XCTAssertTrue(controller.canRequestPremiumPurchase)
        XCTAssertFalse(controller.isPremiumPurchaseAvailable)

        let refreshed = expectation(description: "Product refresh completed")
        let refreshObservation = controller.$isStoreRefreshInFlight.dropFirst().filter { !$0 }.prefix(1).sink { _ in refreshed.fulfill() }
        controller.buyPremium()
        controller.buyPremium() // A second tap while loading must not start another request.
        await fulfillment(of: [refreshed], timeout: 5)
        withExtendedLifetime(refreshObservation) {}
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(purchases, 0)
        XCTAssertEqual(controller.premiumUnlockPrice, "$2.99")
        XCTAssertTrue(controller.isPremiumPurchaseAvailable)

        let purchased = expectation(description: "Purchase completed after price was shown")
        let purchaseObservation = controller.$premiumUnlocked.dropFirst().filter { $0 }.prefix(1).sink { _ in purchased.fulfill() }
        controller.buyPremium()
        controller.buyPremium() // The request is guarded before its async task starts.
        await fulfillment(of: [purchased], timeout: 5)
        withExtendedLifetime(purchaseObservation) {}
        XCTAssertEqual(purchases, 1)
        XCTAssertFalse(controller.isPackLocked(.thud))
    }

    func testControllerUnlocksPackAfterSimulatedPurchaseAndRestore() async throws {
        let suite = "Tappy.PurchaseControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(0.0, forKey: "Tappy.clickVolume")
        KeyboardSoundController.debugSkipStoreRefresh = true
        defer {
            KeyboardSoundController.debugSkipStoreRefresh = false
            defaults.removePersistentDomain(forName: suite)
        }
        let controller = KeyboardSoundController(userDefaults: defaults)
        controller.purchaseStore.debugSetSimulatedPrice("$2.99")
        controller.purchaseStore.debugPurchaseAction = { .success }
        XCTAssertTrue(controller.isPackLocked(.thud))
        XCTAssertTrue(controller.isPremiumPurchaseAvailable)
        controller.highlightPack(.thud)

        let purchased = expectation(description: "Controller unlocks after simulated purchase")
        let purchaseObservation = controller.$premiumUnlocked.dropFirst().filter { $0 }.prefix(1).sink { _ in purchased.fulfill() }
        controller.buyPremium()
        await fulfillment(of: [purchased], timeout: 5)
        withExtendedLifetime(purchaseObservation) {}
        XCTAssertFalse(controller.isPackLocked(.thud))
        XCTAssertTrue(TechPack.all.allSatisfy { !controller.isPackLocked($0) })
        controller.highlightPack(.fart)
        XCTAssertEqual(controller.currentPack.id, TechPack.fart.id)

        let revoked = expectation(description: "Controller locks packs after simulated revocation")
        let revocationObservation = controller.$premiumUnlocked.dropFirst().filter { !$0 }.prefix(1).sink { _ in revoked.fulfill() }
        controller.purchaseStore.applyEvidence(.verifiedRevoked)
        await fulfillment(of: [revoked], timeout: 5)
        withExtendedLifetime(revocationObservation) {}
        XCTAssertTrue(controller.isPackLocked(.thud))
        XCTAssertFalse(controller.currentPack.isPremium)

        let restored = expectation(description: "Controller unlocks after simulated restore")
        let restoreObservation = controller.$premiumUnlocked.dropFirst().filter { $0 }.prefix(1).sink { _ in restored.fulfill() }
        controller.purchaseStore.debugRestoreAction = { true }
        controller.restorePurchases()
        await fulfillment(of: [restored], timeout: 5)
        withExtendedLifetime(restoreObservation) {}
        XCTAssertFalse(controller.isPackLocked(.thud))
        controller.highlightPack(.thud)
        XCTAssertEqual(controller.currentPack.id, TechPack.thud.id)
    }
}
#endif
