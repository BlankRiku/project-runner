#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import XCTest
@testable import DevRunnerCore

final class PortToolTests: XCTestCase {
    func testLsofArgumentsAndParser() {
        let command = LsofCommand(port: 8080)
        XCTAssertEqual(command.executable, "/usr/sbin/lsof")
        XCTAssertEqual(command.arguments, ["-ti", "tcp:8080"])
        XCTAssertEqual(LsofOutput.parsePids("10\n20\n"), [10, 20])
        XCTAssertEqual(LsofOutput.parsePids("\nnope\n"), [])
    }

    func testFreeUsesDoubleAndDoesNotNeedRealKill() {
        final class Box: @unchecked Sendable {
            var commands: [(String, [String])] = []
            var signals: [(Int32, Int32)] = []
        }
        let box = Box()
        let tool = PortTool(
            run: { executable, arguments in
                box.commands.append((executable, arguments))
                return "10\n20\n"
            },
            signal: { pid, sig in
                box.signals.append((pid, sig))
            }
        )
        XCTAssertTrue(tool.isBusy(8080))
        XCTAssertEqual(tool.free(8080), [10, 20])
        XCTAssertEqual(box.commands.count, 2)
        XCTAssertEqual(box.commands[0].1, ["-ti", "tcp:8080"])
        XCTAssertEqual(box.signals.map(\.0), [10, 20])
        XCTAssertEqual(box.signals.map(\.1), [SIGKILL, SIGKILL])
    }

    func testEmptyOutputIsNotBusy() {
        let tool = PortTool(run: { _, _ in "" }, signal: { _, _ in XCTFail("nessun segnale") })
        XCTAssertFalse(tool.isBusy(9))
        XCTAssertEqual(tool.free(9), [])
    }
}
