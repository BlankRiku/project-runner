import XCTest
@testable import DevRunnerCore

final class DebugEnvTests: XCTestCase {
    func testInjectsOnlyWhenEnabledAndMapped() {
        var runner = RunnerConfig(name: "a", command: "x", workingDirectory: "/tmp", debugEnabled: true, debugPort: 5005, debugInjection: .catalinaOpts)
        let env = DebugEnv.apply(runner: runner, env: ["CATALINA_OPTS": "-Dfoo=1"])
        XCTAssertEqual(env["CATALINA_OPTS"], "-Dfoo=1 \(DebugEnv.agent(port: 5005))")
        runner.debugInjection = .none
        XCTAssertNil(DebugEnv.apply(runner: runner, env: [:])["JAVA_TOOL_OPTIONS"])
        runner.debugInjection = .javaToolOptions
        runner.debugEnabled = false
        XCTAssertTrue(DebugEnv.apply(runner: runner, env: [:]).isEmpty)
    }

    func testDoesNotDuplicateAgent() {
        let token = DebugEnv.agent(port: 5005)
        let runner = RunnerConfig(name: "a", command: "x", workingDirectory: "/tmp", debugEnabled: true, debugPort: 5005, debugInjection: .javaToolOptions)
        let once = DebugEnv.apply(runner: runner, env: [:])
        let twice = DebugEnv.apply(runner: runner, env: once)
        XCTAssertEqual(twice["JAVA_TOOL_OPTIONS"], token)
    }
}
