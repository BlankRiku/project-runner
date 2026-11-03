import XCTest
@testable import DevRunnerCore

final class ModelTests: XCTestCase {
    func testMissingDebugFieldsUseDefaults() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"A","command":"echo","workingDirectory":"/tmp"}
        """
        let runner = try JSONDecoder().decode(RunnerConfig.self, from: Data(json.utf8))
        XCTAssertEqual(runner.debugPort, 5005)
        XCTAssertEqual(runner.debugInjection, .none)
        XCTAssertFalse(runner.debugEnabled)
        XCTAssertFalse(runner.commandEdited)
        XCTAssertTrue(runner.env.isEmpty)
    }
}
