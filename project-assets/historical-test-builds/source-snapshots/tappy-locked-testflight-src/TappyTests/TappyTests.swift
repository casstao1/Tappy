import AppKit
import AVFoundation
import XCTest
@testable import Tappy

final class ReviewPromptScheduleTests: XCTestCase {
    func testNewInstallRequestsOnceAtFirstOpenAndOnceAfterAWeek() {
        let suite = "Tappy.ReviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = ReviewPromptSchedule(defaults: defaults, now: start, existingInstallation: false)
        XCTAssertEqual(schedule.due(at: start), .firstLaunch)
        schedule.markRequested(.firstLaunch)
        XCTAssertNil(schedule.due(at: start.addingTimeInterval(7 * 86400 - 1)))
        let reopened = ReviewPromptSchedule(defaults: defaults, now: start.addingTimeInterval(100), existingInstallation: true)
        XCTAssertEqual(reopened.due(at: start.addingTimeInterval(7 * 86400)), .oneWeek)
        reopened.markRequested(.oneWeek)
        XCTAssertNil(reopened.due(at: start.addingTimeInterval(14 * 86400)))
    }

    func testExistingInstallationSkipsFirstLaunchRequest() {
        let suite = "Tappy.ReviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let schedule = ReviewPromptSchedule(defaults: defaults, now: start, existingInstallation: true)
        XCTAssertNil(schedule.due(at: start))
        XCTAssertEqual(schedule.due(at: start.addingTimeInterval(7 * 86400)), .oneWeek)
    }

    func testConsentWaitsForReviewAttemptAndLaterMenuInteraction() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var gate = AnalyticsConsentOfferGate()
        XCTAssertFalse(gate.canOffer(at: now, initialReviewPending: true, isActive: true, hasModalOrSheet: false))
        gate.didRequestReview(at: now)
        XCTAssertFalse(gate.canOffer(at: now.addingTimeInterval(2), initialReviewPending: false, isActive: true, hasModalOrSheet: false))
        XCTAssertFalse(gate.canOffer(at: now.addingTimeInterval(4), initialReviewPending: false, isActive: true, hasModalOrSheet: true))
        XCTAssertFalse(gate.canOffer(at: now.addingTimeInterval(4), initialReviewPending: false, isActive: false, hasModalOrSheet: false))
        XCTAssertTrue(gate.canOffer(at: now.addingTimeInterval(4), initialReviewPending: false, isActive: true, hasModalOrSheet: false))
    }

    func testExistingInstallCanOfferConsentWithoutAnotherReviewRequest() {
        let gate = AnalyticsConsentOfferGate()
        XCTAssertTrue(gate.canOffer(at: Date(), initialReviewPending: false, isActive: true, hasModalOrSheet: false))
    }
}
final class AppStoreAccessTests: XCTestCase {
    func testOnlyPremiumPacksAreLockedWithoutAnEntitlement() {
        for pack in TechPack.all {
            XCTAssertEqual(
                KeyboardSoundController.isPackLocked(pack, hasPremiumAccess: false),
                pack.isPremium,
                "Unexpected lock state for \(pack.name)"
            )
            XCTAssertFalse(KeyboardSoundController.isPackLocked(pack, hasPremiumAccess: true))
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
    func testAppStoreCatalogKeepsThreeFreePacks() {
        XCTAssertEqual(
            TechPack.all.filter { !$0.isPremium }.map(\.id),
            [TechPack.plasticTapping.id, TechPack.farming.id, TechPack.squishyPop.id]
        )
        XCTAssertEqual(TechPack.all.filter(\.isPremium).count, 19)
    }

    func testNewPremiumPacksFollowFreePacks() {
        XCTAssertEqual(
            TechPack.all.map(\.id),
            [
                TechPack.plasticTapping.id,
                TechPack.farming.id,
                TechPack.squishyPop.id,
                TechPack.swordBattle.id,
                TechPack.waxCracking.id,
                TechPack.bubble.id,
                TechPack.analogStopwatch.id,
                TechPack.stars.id,
                TechPack.woodBrush.id,
                TechPack.fart.id,
                TechPack.splashingWater.id,
                TechPack.paperCrinkle.id,
                TechPack.plasticCrinkle.id,
                TechPack.wetMouth.id,
                TechPack.suckingWaterThroughATube.id,
                TechPack.hairBrushing.id,
                TechPack.gentleWaterSwishing.id,
                TechPack.scissorsCutting.id,
                TechPack.catMeows.id,
                TechPack.dogBarks.id,
                TechPack.running.id,
                TechPack.thud.id
            ]
        )
    }

    func testBubblePackUsesBubblesDisplayName() {
        XCTAssertEqual(TechPack.bubble.name, "Bubbles")
    }
}

final class PremiumDemoResourceTests: XCTestCase {
    func testTypingPreviewRequiresActiveFeedbackAndInputMonitoring() {
        XCTAssertNotNil(KeyboardSoundController.livePreviewUnavailableReason(isEnabled: false, setupPhase: .complete))
        XCTAssertNotNil(KeyboardSoundController.livePreviewUnavailableReason(isEnabled: true, setupPhase: .needsPermission))
        XCTAssertNotNil(KeyboardSoundController.livePreviewUnavailableReason(isEnabled: true, setupPhase: .needsRestart))
        XCTAssertNil(KeyboardSoundController.livePreviewUnavailableReason(isEnabled: true, setupPhase: .complete))
    }

    func testThudPreservesFullSoundAfterRemovingLeadIn() throws {
        let resourceURL = try XCTUnwrap(Bundle.main.resourceURL)
        let url = resourceURL.appendingPathComponent("BundledSounds/thud/default/thud.wav")
        let audio = try AVAudioFile(forReading: url)
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        XCTAssertEqual(duration, 2.797574, accuracy: 0.01)
        XCTAssertNil(SoundLibrary.maximumDuration(for: url, packID: TechPack.thud.id))
        XCTAssertEqual(SoundLibrary.maximumDuration(for: url, packID: TechPack.running.id), LowLatencyAudioEngine.maximumClickDuration)
    }

    #if DEBUG
    @MainActor
    func testUnavailableTypingPreviewDoesNotConsumeTrial() throws {
        let suite = "Tappy.UnavailablePreview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(0.0, forKey: "Tappy.clickVolume")
        let controller = KeyboardSoundController(userDefaults: defaults)
        controller.isEnabled = false

        controller.startLivePreview(.thud)
        XCTAssertFalse(controller.hasTrialedPack(.thud))
        XCTAssertNil(controller.previewPack)
        XCTAssertEqual(controller.sampleErrorMessage, "Turn on Feedback before starting a typing preview.")

        controller.debugPreviewAvailabilityOverride = true
        controller.startLivePreview(.thud)
        XCTAssertTrue(controller.hasTrialedPack(.thud))
        XCTAssertEqual(controller.previewPack?.id, TechPack.thud.id)
        controller.cancelLivePreview()
    }

    func testTrialPreparationKeepsOriginalPoolAndRejectsMissingPack() async throws {
        try await MainActor.run {
            let engine = LowLatencyAudioEngine()
            engine.setEnabled(false)
            let library = SoundLibrary()
            let original = try library.loadBundledPreviewPack(packID: TechPack.bubble.id, using: engine)
            let originalCount = original.sounds.values.reduce(0) { $0 + $1.count }
            XCTAssertGreaterThan(originalCount, 0)
            try engine.setLoadedSounds(original.sounds, keySounds: original.keySounds)

            let trial = try library.loadBundledPreviewPack(packID: TechPack.thud.id, using: engine)
            let trialCount = trial.sounds.values.reduce(0) { $0 + $1.count }
            try engine.setPreviewSounds(trial.sounds, keySounds: trial.keySounds, allowVoiceExpansion: true)
            XCTAssertGreaterThan(trialCount, 0)
            XCTAssertEqual(engine.debugLoadedSoundCount, originalCount)
            XCTAssertEqual(engine.debugPreviewSoundCount, trialCount)

            XCTAssertThrowsError(try library.loadBundledPreviewPack(packID: "missing-trial-pack", using: engine))
            XCTAssertEqual(engine.debugLoadedSoundCount, originalCount)
            XCTAssertEqual(engine.debugPreviewSoundCount, trialCount)
            engine.clearPreviewSounds()
            XCTAssertEqual(engine.debugPreviewSoundCount, 0)
            XCTAssertEqual(engine.debugLoadedSoundCount, originalCount)
        }
    }

    func testSamplePlaysWhenTypingSoundsArePaused() throws {
        let resourceURL = try XCTUnwrap(Bundle.main.resourceURL)
        let url = resourceURL.appendingPathComponent("BundledSounds/thud/demo/demo.wav")
        let engine = LowLatencyAudioEngine()
        engine.setVolume(0)
        engine.setEnabled(false)
        engine.play(buffer: try engine.makeBuffer(from: url))
        XCTAssertTrue(engine.debugSampleIsPlaying)
        engine.setEnabled(false)
    }

    @MainActor
    func testEveryLockedPackDemoCanStartWithFeedbackPaused() throws {
        let engine = LowLatencyAudioEngine()
        let library = SoundLibrary()
        engine.setVolume(0)
        engine.setEnabled(false)
        var started: [XCTestExpectation] = []
        for pack in TechPack.all where pack.isPremium {
            let buffer = try engine.makeBuffer(from: library.bundledDemoURL(packID: pack.id))
            let expectation = expectation(description: "Start \(pack.name) sample")
            started.append(expectation)
            engine.playSample(buffer: buffer) { result in
                if case .failure(let error) = result { XCTFail("\(pack.name): \(error)") }
                expectation.fulfill()
            }
        }
        wait(for: started, timeout: 10)
        engine.stopSample()
    }

    func testLongSoundAddsVoiceWhenExistingVoiceIsBusy() throws {
        let resourceURL = try XCTUnwrap(Bundle.main.resourceURL)
        let url = resourceURL.appendingPathComponent("BundledSounds/thud/default/thud.wav")
        let engine = LowLatencyAudioEngine(concurrentVoices: 1)
        engine.setVolume(0)
        let buffer = try engine.makeBuffer(from: url)
        let sound = LoadedSound(category: .standard, url: url, buffer: buffer)
        try engine.setLoadedSounds([.standard: [sound]], keySounds: [:], allowVoiceExpansion: true)
        engine.play(category: .standard)
        engine.play(category: .standard)
        XCTAssertEqual(engine.debugVoiceCount, 2)
        engine.setEnabled(false)
    }
    #endif

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
