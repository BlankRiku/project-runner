import XCTest
@testable import DevRunnerCore

final class RingLogTests: XCTestCase {
    func testCapsAtOneThousandDroppingOldest() {
        var log = RingLog()
        let lines = (0..<1005).map(String.init)
        log.append(lines: lines)
        XCTAssertEqual(log.lines.count, 1000)
        XCTAssertEqual(log.lines.first, "5")
        XCTAssertEqual(log.lines.last, "1004")
    }

    func testFilterDoesNotMutateBuffer() {
        var log = RingLog()
        log.append(lines: ["alpha", "BETA"])
        XCTAssertEqual(log.filtered(query: "bet"), ["BETA"])
        XCTAssertEqual(log.lines, ["alpha", "BETA"])
        XCTAssertEqual(log.filtered(query: "  "), ["alpha", "BETA"])
    }

    func testLineBufferSplitsAndFlushesRemainder() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.consume("hel"), [])
        XCTAssertEqual(buffer.consume("lo\nwor"), ["hello"])
        XCTAssertEqual(buffer.consume("ld\r\n"), ["world"])
        XCTAssertEqual(buffer.consume("tail"), [])
        XCTAssertEqual(buffer.flush(), ["tail"])
        XCTAssertEqual(buffer.flush(), [])
    }
}
