import AppKit
import AVFoundation
import XCTest
@testable import Tappy

final class AppStorePaidAccessTests: XCTestCase {
    func testEveryPackIsUnlockedWithoutAnEntitlement() {
        for pack in TechPack.all {
            XCTAssertFalse(
                KeyboardSoundController.isPackLocked(pack, hasPremiumAccess: false),
                "Paid App Store users should be able to select \(pack.name)"
            )
        }
    }
}

final class InputMonitoringPromptGateTests: XCTestCase {
    func testLiveCaptureIsTheOnlyActiveSetupState() {
        XCTAssertEqual(
            KeyboardSoundController.setupPhase(trusted: true, captureState: .ready),
            .complete
        )
    }

    func testTrustedPermissionWithUnavailableCaptureRequiresRestart() {
        XCTAssertEqual(
            KeyboardSoundController.setupPhase(trusted: true, captureState: .unavailable),
            .needsRestart
        )
    }

    func testUntrustedPermissionWithUnavailableCaptureRequiresPermission() {
        XCTAssertEqual(
            KeyboardSoundController.setupPhase(trusted: false, captureState: .unavailable),
            .needsPermission
        )
    }

    func testRevokedPermissionCannotRemainActiveWithAStaleReadyState() {
        XCTAssertEqual(
            KeyboardSoundController.setupPhase(trusted: false, captureState: .ready),
            .needsPermission
        )
    }

    func testFirstRunBlocksAllInputMonitoringAttempts() {
        XCTAssertFalse(
            KeyboardSoundController.shouldAttemptInputMonitoring(
                isEnabled: true,
                hasSeenWelcome: false,
                isTrusted: true
            )
        )
    }

    func testAcknowledgedWelcomeAndPermissionAllowInputMonitoringAttempts() {
        XCTAssertTrue(
            KeyboardSoundController.shouldAttemptInputMonitoring(
                isEnabled: true,
                hasSeenWelcome: true,
                isTrusted: true
            )
        )
    }

    func testAcknowledgedWelcomeDoesNotAttachListenerBeforePermission() {
        XCTAssertFalse(
            KeyboardSoundController.shouldAttemptInputMonitoring(
                isEnabled: true,
                hasSeenWelcome: true,
                isTrusted: false
            )
        )
    }

    func testPausedFeedbackBlocksInputMonitoringAttempts() {
        XCTAssertFalse(
            KeyboardSoundController.shouldAttemptInputMonitoring(
                isEnabled: false,
                hasSeenWelcome: true,
                isTrusted: true
            )
        )
    }

    func testFirstRunBlocksPromptUntilWelcomeIsAcknowledged() {
        XCTAssertFalse(
            KeyboardSoundController.shouldRequestStartupInputMonitoringPrompt(
                setupPhase: .needsPermission,
                hasSeenWelcome: false,
                didRequestThisLaunch: false
            )
        )
    }

    func testAcknowledgedWelcomeAllowsPrompt() {
        XCTAssertTrue(
            KeyboardSoundController.shouldRequestStartupInputMonitoringPrompt(
                setupPhase: .needsPermission,
                hasSeenWelcome: true,
                didRequestThisLaunch: false
            )
        )
    }

    func testPromptCanOnlyBeRequestedOncePerLaunch() {
        XCTAssertFalse(
            KeyboardSoundController.shouldRequestStartupInputMonitoringPrompt(
                setupPhase: .needsPermission,
                hasSeenWelcome: true,
                didRequestThisLaunch: true
            )
        )
    }

    func testGrantedPermissionNeverRequestsPrompt() {
        XCTAssertFalse(
            KeyboardSoundController.shouldRequestStartupInputMonitoringPrompt(
                setupPhase: .complete,
                hasSeenWelcome: true,
                didRequestThisLaunch: false
            )
        )
    }
}

final class PackCatalogTests: XCTestCase {
    func testDirectEditionCatalogKeepsTwoUngatedPacks() {
        XCTAssertEqual(
            TechPack.all.filter { !$0.isPremium }.map(\.id),
            [TechPack.plasticTapping.id, TechPack.farming.id]
        )
        XCTAssertEqual(TechPack.all.filter(\.isPremium).count, 6)
    }

    func testNewPremiumPacksFollowFreePacks() {
        XCTAssertEqual(
            TechPack.all.map(\.id),
            [
                TechPack.plasticTapping.id,
                TechPack.farming.id,
                TechPack.squishyPop.id,
                TechPack.waxCracking.id,
                TechPack.bubble.id,
                TechPack.analogStopwatch.id,
                TechPack.stars.id,
                TechPack.woodBrush.id
            ]
        )
    }

    func testBubblePackUsesBubblesDisplayName() {
        XCTAssertEqual(TechPack.bubble.name, "Bubbles")
    }
}

final class PremiumDemoResourceTests: XCTestCase {
    func testEveryPremiumPackHasPlayableBundledDemo() throws {
        let resourceURL = try XCTUnwrap(Bundle.main.resourceURL)

        for pack in TechPack.all where pack.isPremium {
            let demoFolderURL = resourceURL
                .appendingPathComponent("BundledSounds", isDirectory: true)
                .appendingPathComponent(pack.id, isDirectory: true)
                .appendingPathComponent("demo", isDirectory: true)
            let demoURLs = try FileManager.default.contentsOfDirectory(
                at: demoFolderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension.lowercased() == "wav" }

            XCTAssertFalse(demoURLs.isEmpty, "Missing bundled demo for \(pack.name)")

            for demoURL in demoURLs {
                let audioFile = try AVAudioFile(forReading: demoURL)
                XCTAssertGreaterThan(audioFile.length, 0, "Empty bundled demo for \(pack.name)")
            }
        }
    }

    func testWetSquishyPopHasMultipleDemoVariations() throws {
        let resourceURL = try XCTUnwrap(Bundle.main.resourceURL)
        let demoFolderURL = resourceURL
            .appendingPathComponent("BundledSounds", isDirectory: true)
            .appendingPathComponent(TechPack.squishyPop.id, isDirectory: true)
            .appendingPathComponent("demo", isDirectory: true)
        let demoURLs = try FileManager.default.contentsOfDirectory(
            at: demoFolderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "wav" }

        XCTAssertGreaterThanOrEqual(demoURLs.count, 4)
    }
}
