import XCTest
@testable import Tappy

final class KeyboardEventDeduplicatorTests: XCTestCase {
    func testRapidPhysicalPressesAreNotDropped() {
        var deduplicator = KeyboardEventDeduplicator()
        XCTAssertFalse(deduplicator.isDuplicate(keyCode: 4, timestamp: 1_000_000_000, origin: .globalBackground))
        XCTAssertFalse(deduplicator.isDuplicate(keyCode: 4, timestamp: 1_020_000_000, origin: .globalBackground))
        XCTAssertTrue(deduplicator.isDuplicate(keyCode: 4, timestamp: 1_000_000_000, origin: .localApp))
        XCTAssertTrue(deduplicator.isDuplicate(keyCode: 4, timestamp: 1_020_000_000, origin: .localApp))
    }

    func testLocalThenGlobalAndInterleavedKeys() {
        var deduplicator = KeyboardEventDeduplicator()
        XCTAssertFalse(deduplicator.isDuplicate(keyCode: 4, timestamp: 100, origin: .localApp))
        XCTAssertFalse(deduplicator.isDuplicate(keyCode: 5, timestamp: 101, origin: .localApp))
        XCTAssertTrue(deduplicator.isDuplicate(keyCode: 4, timestamp: 100, origin: .globalBackground))
        XCTAssertTrue(deduplicator.isDuplicate(keyCode: 5, timestamp: 101, origin: .globalBackground))
    }

    func testMissingTimestampsDoNotSuppressAndClearResetsState() {
        var deduplicator = KeyboardEventDeduplicator()
        XCTAssertFalse(deduplicator.isDuplicate(keyCode: 4, timestamp: 0, origin: .localApp))
        XCTAssertFalse(deduplicator.isDuplicate(keyCode: 4, timestamp: 0, origin: .globalBackground))
        XCTAssertFalse(deduplicator.isDuplicate(keyCode: 4, timestamp: 100, origin: .localApp))
        deduplicator.clear()
        XCTAssertFalse(deduplicator.isDuplicate(keyCode: 4, timestamp: 100, origin: .globalBackground))
    }
}
