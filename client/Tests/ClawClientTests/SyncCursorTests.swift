import XCTest
@testable import ClawClient

final class SyncCursorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        SyncCursor.reset()
    }

    override func tearDown() {
        SyncCursor.reset()
        super.tearDown()
    }

    func testDefaultsToZero() {
        XCTAssertEqual(SyncCursor.value, 0)
    }

    func testSetAndGet() {
        SyncCursor.value = 12345
        XCTAssertEqual(SyncCursor.value, 12345)
    }

    func testAdvanceMovesForward() {
        SyncCursor.value = 100
        SyncCursor.advance(to: 200)
        XCTAssertEqual(SyncCursor.value, 200)
    }

    func testAdvanceDoesNotGoBackward() {
        SyncCursor.value = 500
        SyncCursor.advance(to: 100)
        XCTAssertEqual(SyncCursor.value, 500)
    }

    func testAdvanceWithEqualValueIsNoOp() {
        SyncCursor.value = 300
        SyncCursor.advance(to: 300)
        XCTAssertEqual(SyncCursor.value, 300)
    }

    func testReset() {
        SyncCursor.value = 9999
        SyncCursor.reset()
        XCTAssertEqual(SyncCursor.value, 0)
    }
}
