import Foundation
import XCTest
@testable import Tappy

private final class TelemetryURLProtocol: URLProtocol {
    static var onRequest: ((URLRequest) -> Void)?
    static var onCancel: (() -> Void)?
    static var holdResponse = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.onRequest?(request)
        if !Self.holdResponse {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { Self.onCancel?() }
}

@MainActor
final class TelemetryTests: XCTestCase {
    private let idKey = "Tappy.analyticsInstallID"

    private func makeTelemetry() -> (TappyTelemetry, UserDefaults, String) {
        let suite = "Tappy.TelemetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelemetryURLProtocol.self]
        let telemetry = TappyTelemetry(
            defaults: defaults,
            configurationOverride: (URL(string: "https://example.test/capture/")!, "phc_test_token"),
            sessionConfiguration: configuration
        )
        return (telemetry, defaults, suite)
    }

    func testDefaultOffAndOptInPayload() throws {
        let (telemetry, defaults, suite) = makeTelemetry()
        defer {
            telemetry.setEnabled(false)
            defaults.removePersistentDomain(forName: suite)
            TelemetryURLProtocol.onRequest = nil
            TelemetryURLProtocol.onCancel = nil
            TelemetryURLProtocol.holdResponse = false
        }
        let noRequest = expectation(description: "No request before opting in")
        noRequest.isInverted = true
        TelemetryURLProtocol.onRequest = { _ in noRequest.fulfill() }
        XCTAssertFalse(telemetry.enabled)
        XCTAssertNil(defaults.string(forKey: idKey))
        telemetry.record("demo_played", pack: TechPack.all[0].id)
        wait(for: [noRequest], timeout: 0.2)

        let requestReceived = expectation(description: "Captured event")
        var captured: URLRequest?
        TelemetryURLProtocol.onRequest = { request in
            captured = request
            requestReceived.fulfill()
        }
        telemetry.setEnabled(true)
        let installID = try XCTUnwrap(defaults.string(forKey: idKey))
        XCTAssertNotNil(UUID(uuidString: installID))
        let packID = TechPack.all[0].id
        telemetry.record("demo_played", pack: packID, properties: ["source": "preview"])
        wait(for: [requestReceived], timeout: 2)

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/capture/")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body: Data
        if let data = request.httpBody {
            body = data
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["api_key"] as? String, "phc_test_token")
        XCTAssertEqual(payload["event"] as? String, "demo_played")
        let properties = try XCTUnwrap(payload["properties"] as? [String: Any])
        XCTAssertEqual(properties["distinct_id"] as? String, installID)
        XCTAssertEqual(properties["pack_id"] as? String, packID)
        XCTAssertEqual(properties["source"] as? String, "preview")
        XCTAssertEqual(properties["distribution"] as? String, "app_store")
        XCTAssertEqual(properties["$geoip_disable"] as? Bool, true)
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
    }

    func testOptOutCancelsAndDeletesIDThenOptInCreatesNewID() throws {
        let (telemetry, defaults, suite) = makeTelemetry()
        defer {
            telemetry.setEnabled(false)
            defaults.removePersistentDomain(forName: suite)
            TelemetryURLProtocol.onRequest = nil
            TelemetryURLProtocol.onCancel = nil
            TelemetryURLProtocol.holdResponse = false
        }
        telemetry.setEnabled(true)
        let firstID = try XCTUnwrap(defaults.string(forKey: idKey))
        let requestReceived = expectation(description: "Request started")
        let cancelled = expectation(description: "Request cancelled")
        cancelled.assertForOverFulfill = false
        TelemetryURLProtocol.holdResponse = true
        TelemetryURLProtocol.onRequest = { _ in requestReceived.fulfill() }
        TelemetryURLProtocol.onCancel = { cancelled.fulfill() }
        telemetry.record("demo_played")
        wait(for: [requestReceived], timeout: 2)
        telemetry.setEnabled(false)
        XCTAssertFalse(telemetry.enabled)
        XCTAssertNil(defaults.string(forKey: idKey))
        wait(for: [cancelled], timeout: 2)
        TelemetryURLProtocol.onCancel = nil
        let noRequest = expectation(description: "No request after opting out")
        noRequest.isInverted = true
        TelemetryURLProtocol.onRequest = { _ in noRequest.fulfill() }
        telemetry.record("demo_played")
        wait(for: [noRequest], timeout: 0.2)
        telemetry.setEnabled(true)
        XCTAssertNotEqual(firstID, defaults.string(forKey: idKey))
    }

    #if DEBUG
    func testConsentPromptPreservesPreviousOptOut() {
        let suite = "Tappy.PreviousConsentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(false, forKey: "Tappy.analyticsEnabled")
        KeyboardSoundController.debugSkipStoreRefresh = true
        KeyboardSoundController.debugTelemetryFactory = { defaults in
            TappyTelemetry(defaults: defaults,
                configurationOverride: (URL(string: "https://example.test/capture/")!, "phc_test_token"))
        }
        defer {
            KeyboardSoundController.debugSkipStoreRefresh = false
            KeyboardSoundController.debugTelemetryFactory = nil
            defaults.removePersistentDomain(forName: suite)
        }
        let controller = KeyboardSoundController(userDefaults: defaults)
        XCTAssertFalse(controller.presentAnalyticsConsentIfNeeded())
        XCTAssertFalse(controller.analyticsEnabled)
        XCTAssertTrue(defaults.bool(forKey: "Tappy.analyticsConsentPromptSeen"))
        XCTAssertNil(defaults.string(forKey: idKey))
    }

    func testConsentPromptPreservesPreviousOptIn() {
        let suite = "Tappy.PreviousConsentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let installID = UUID().uuidString
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(true, forKey: "Tappy.analyticsEnabled")
        defaults.set(installID, forKey: idKey)
        KeyboardSoundController.debugSkipStoreRefresh = true
        KeyboardSoundController.debugTelemetryFactory = { defaults in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TelemetryURLProtocol.self]
            return TappyTelemetry(defaults: defaults,
                configurationOverride: (URL(string: "https://example.test/capture/")!, "phc_test_token"),
                sessionConfiguration: configuration)
        }
        defer {
            KeyboardSoundController.debugSkipStoreRefresh = false
            KeyboardSoundController.debugTelemetryFactory = nil
            defaults.removePersistentDomain(forName: suite)
            TelemetryURLProtocol.onRequest = nil
            TelemetryURLProtocol.onCancel = nil
            TelemetryURLProtocol.holdResponse = false
        }
        let controller = KeyboardSoundController(userDefaults: defaults)
        XCTAssertFalse(controller.presentAnalyticsConsentIfNeeded())
        XCTAssertTrue(controller.analyticsEnabled)
        XCTAssertTrue(defaults.bool(forKey: "Tappy.analyticsConsentPromptSeen"))
        XCTAssertEqual(defaults.string(forKey: idKey), installID)
        controller.setAnalyticsEnabled(false)
    }

    func testOptInAndSelectingPackEmitsAppStoreEvents() throws {
        let suite = "Tappy.TelemetryFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(0.0, forKey: "Tappy.clickVolume")
        KeyboardSoundController.debugTelemetryFactory = { defaults in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TelemetryURLProtocol.self]
            return TappyTelemetry(defaults: defaults,
                configurationOverride: (URL(string: "https://example.test/capture/")!, "phc_test_token"),
                sessionConfiguration: configuration)
        }
        defer {
            KeyboardSoundController.debugTelemetryFactory = nil
            defaults.removePersistentDomain(forName: suite)
            TelemetryURLProtocol.onRequest = nil
            TelemetryURLProtocol.onCancel = nil
            TelemetryURLProtocol.holdResponse = false
        }
        let enabled = expectation(description: "analytics enabled")
        let selected = expectation(description: "pack selected")
        let lock = NSLock()
        var selectedProperties: [String: Any]?
        TelemetryURLProtocol.onRequest = { request in
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = body["event"] as? String else { return }
            if event == "analytics_enabled" { enabled.fulfill() }
            if event == "pack_selected" {
                lock.lock()
                selectedProperties = body["properties"] as? [String: Any]
                lock.unlock()
                selected.fulfill()
            }
        }
        let controller = KeyboardSoundController(userDefaults: defaults)
        XCTAssertTrue(controller.analyticsAvailable)
        controller.setAnalyticsEnabled(true)
        controller.highlightPack(.thud)
        wait(for: [enabled, selected], timeout: 5)
        lock.lock()
        let properties = selectedProperties
        lock.unlock()
        XCTAssertEqual(properties?["pack_id"] as? String, TechPack.thud.id)
        XCTAssertEqual(properties?["locked"] as? String, "yes")
        controller.setAnalyticsEnabled(false)
    }
    #endif

    #if DEBUG
    func testCustomerPreviewFlowEmitsEventsForTheSelectedPack() throws {
        let suite = "Tappy.TelemetryFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(1, forKey: "Tappy.welcomeVersionSeen")
        defaults.set(0.0, forKey: "Tappy.clickVolume")
        defaults.set(TechPack.farming.id, forKey: "Tappy.selectedPackID")
        KeyboardSoundController.debugTelemetryFactory = { defaults in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TelemetryURLProtocol.self]
            return TappyTelemetry(defaults: defaults,
                configurationOverride: (URL(string: "https://example.test/capture/")!, "phc_test_token"),
                sessionConfiguration: configuration)
        }
        defer {
            KeyboardSoundController.debugTelemetryFactory = nil
            defaults.removePersistentDomain(forName: suite)
            TelemetryURLProtocol.onRequest = nil
            TelemetryURLProtocol.onCancel = nil
            TelemetryURLProtocol.holdResponse = false
        }

        let events = ["analytics_enabled", "pack_selected", "demo_played", "preview_started", "preview_completed", "upgrade_prompt_shown", "upgrade_prompt_dismissed"]
        let received = Dictionary(uniqueKeysWithValues: events.map { ($0, expectation(description: $0)) })
        let lock = NSLock()
        var payloads: [String: [String: Any]] = [:]
        TelemetryURLProtocol.onRequest = { request in
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = body["event"] as? String, let expected = received[event] else { return }
            lock.lock()
            payloads[event] = body
            lock.unlock()
            expected.fulfill()
        }

        let controller = KeyboardSoundController(userDefaults: defaults)
        controller.debugPreviewAvailabilityOverride = true
        XCTAssertEqual(controller.currentPack.id, TechPack.farming.id)
        XCTAssertTrue(controller.analyticsAvailable)
        controller.setAnalyticsEnabled(true)
        controller.highlightPack(.thud)
        controller.playPremiumDemo()
        wait(for: [received["analytics_enabled"]!, received["pack_selected"]!, received["demo_played"]!], timeout: 5)
        controller.startLivePreview(.thud)
        XCTAssertEqual(controller.currentPack.id, TechPack.thud.id)
        XCTAssertEqual(controller.previewPack?.id, TechPack.thud.id)
        for _ in 0..<100 { controller.debugConsumePreviewKeystroke() }
        wait(for: [received["preview_started"]!, received["preview_completed"]!, received["upgrade_prompt_shown"]!], timeout: 5)
        XCTAssertNil(controller.previewPack)
        XCTAssertEqual(controller.currentPack.id, TechPack.farming.id)
        XCTAssertTrue(controller.showUpgradeCTA)
        controller.dismissUpgradeCTA()
        wait(for: [received["upgrade_prompt_dismissed"]!], timeout: 3)
        lock.lock()
        let captured = payloads
        lock.unlock()
        for event in events where event != "analytics_enabled" {
            let properties = try XCTUnwrap(captured[event]?["properties"] as? [String: Any], "Missing \(event)")
            XCTAssertEqual(properties["pack_id"] as? String, TechPack.thud.id, event)
        }
        XCTAssertEqual((captured["pack_selected"]?["properties"] as? [String: Any])?["locked"] as? String, "yes")
        controller.setAnalyticsEnabled(false)
    }
    #endif
}
