import XCTest
@testable import ClawClient

final class WsEventTests: XCTestCase {

    // MARK: - message.delta

    func testParsesMessageDelta() {
        let json = """
        {"type":"message.delta","messageId":"m1","conversationId":"c1","delta":"Hello","seq":7}
        """
        guard case .messageDelta(let mid, let cid, let delta, let seq) = WsEvent.parse(json) else {
            XCTFail("expected messageDelta"); return
        }
        XCTAssertEqual(mid, "m1")
        XCTAssertEqual(cid, "c1")
        XCTAssertEqual(delta, "Hello")
        XCTAssertEqual(seq, 7)
    }

    // MARK: - message.complete

    func testParsesMessageComplete() {
        let json = """
        {"type":"message.complete","messageId":"m2","conversationId":"c1","content":"Full text","seq":10}
        """
        guard case .messageComplete(let mid, let cid, let content, let seq) = WsEvent.parse(json) else {
            XCTFail("expected messageComplete"); return
        }
        XCTAssertEqual(mid, "m2")
        XCTAssertEqual(cid, "c1")
        XCTAssertEqual(content, "Full text")
        XCTAssertEqual(seq, 10)
    }

    // MARK: - message.error

    func testParsesMessageError() {
        let json = """
        {"type":"message.error","messageId":"m3","conversationId":"c1","error":"timeout"}
        """
        guard case .messageError(let mid, let cid, let error) = WsEvent.parse(json) else {
            XCTFail("expected messageError"); return
        }
        XCTAssertEqual(mid, "m3")
        XCTAssertEqual(cid, "c1")
        XCTAssertEqual(error, "timeout")
    }

    // MARK: - tool.start / tool.end

    func testParsesToolStart() {
        let json = """
        {"type":"tool.start","messageId":"m1","tool":"Bash","label":"Running command…"}
        """
        guard case .toolStart(let mid, let tool, let label) = WsEvent.parse(json) else {
            XCTFail("expected toolStart"); return
        }
        XCTAssertEqual(mid, "m1")
        XCTAssertEqual(tool, "Bash")
        XCTAssertEqual(label, "Running command…")
    }

    func testParsesToolEnd() {
        let json = """
        {"type":"tool.end","messageId":"m1","tool":"Bash"}
        """
        guard case .toolEnd(let mid, let tool) = WsEvent.parse(json) else {
            XCTFail("expected toolEnd"); return
        }
        XCTAssertEqual(mid, "m1")
        XCTAssertEqual(tool, "Bash")
    }

    // MARK: - conversation.updated

    func testParsesConversationUpdated() {
        let json = """
        {"type":"conversation.updated","conversationId":"c42"}
        """
        guard case .conversationUpdated(let cid) = WsEvent.parse(json) else {
            XCTFail("expected conversationUpdated"); return
        }
        XCTAssertEqual(cid, "c42")
    }

    // MARK: - Unknown / malformed

    func testReturnsNilForUnknownType() {
        let json = """
        {"type":"something.new","foo":"bar"}
        """
        XCTAssertNil(WsEvent.parse(json))
    }

    func testReturnsNilForMalformedJson() {
        XCTAssertNil(WsEvent.parse("not json at all"))
        XCTAssertNil(WsEvent.parse("{}"))
        XCTAssertNil(WsEvent.parse(""))
    }

    func testReturnsNilForMissingFields() {
        // message.delta missing seq
        let json = """
        {"type":"message.delta","messageId":"m1","conversationId":"c1","delta":"hi"}
        """
        XCTAssertNil(WsEvent.parse(json))
    }
}
