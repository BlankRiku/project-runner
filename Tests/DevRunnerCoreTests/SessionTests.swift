#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import XCTest
@testable import DevRunnerCore

@MainActor
final class SessionTests: XCTestCase {
    private var directory: URL!
    private var spawner: RecordingSpawner!
    private var signals: SignalLog!
    private var session: Session!

    override func setUp() async throws {
        directory = try TestSupport.makeDirectory()
        spawner = RecordingSpawner()
        signals = SignalLog()
        let log = signals!
        session = Session(
            store: ConfigStore(fileURL: directory.appendingPathComponent("config.json")),
            spawner: spawner,
            ports: PortTool(
                run: { _, _ in log.output },
                signal: { pid, _ in log.add(pid, SIGKILL) }
            ),
            terminationGrace: 0.2,
            configRoot: directory,
            userHome: directory
        )
    }

    override func tearDown() async throws {
        TestSupport.remove(directory)
    }

    func testEmptyCommandDoesNotSpawn() async {
        let project = add(command: "   ", port: nil)
        session.start(projectID: project.id, runnerID: project.runners[0].id)
        XCTAssertTrue(spawner.requests.isEmpty)
        XCTAssertEqual(session.runtime(for: project.runners[0].id).phase, .crashed)
        XCTAssertEqual(session.logs(for: project.runners[0].id).lines, ["Comando da completare."])
    }

    func testBusyPortDoesNotSpawnOrSignal() async {
        signals.output = "42\n"
        let project = add(command: "echo hi", port: 8080)
        let failure = session.start(projectID: project.id, runnerID: project.runners[0].id)
        XCTAssertEqual(failure, "Porta 8080 occupata.")
        XCTAssertTrue(spawner.requests.isEmpty)
        XCTAssertTrue(signals.killed.isEmpty)
        XCTAssertEqual(session.runtime(for: project.runners[0].id).phase, .stopped)
        XCTAssertEqual(session.logs(for: project.runners[0].id).lines, ["Porta 8080 occupata."])
    }

    func testSecondStartIsIgnoredAndDebugEnvIsApplied() async throws {
        let project = add(command: "echo hi", port: nil, debug: true, injection: .javaToolOptions)
        let runnerID = project.runners[0].id
        session.start(projectID: project.id, runnerID: runnerID)
        session.start(projectID: project.id, runnerID: runnerID)
        XCTAssertEqual(spawner.requests.count, 1)
        XCTAssertEqual(spawner.requests[0].environment["JAVA_TOOL_OPTIONS"], DebugEnv.agent(port: 5005))
        XCTAssertEqual(session.runtime(for: runnerID).phase, .running)
        spawner.handles[0].finish(0)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(session.runtime(for: runnerID).phase, .stopped)
    }

    func testNonZeroExitCrashesAndRestartSpawnsAgain() async throws {
        let project = add(command: "echo hi", port: nil)
        let runnerID = project.runners[0].id
        session.start(projectID: project.id, runnerID: runnerID)
        spawner.handles[0].finish(1)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(session.runtime(for: runnerID).phase, .crashed)
        session.start(projectID: project.id, runnerID: runnerID)
        session.restart(projectID: project.id, runnerID: runnerID)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(spawner.requests.count, 3)
        XCTAssertEqual(session.runtime(for: runnerID).phase, .running)
    }

    func testTomcatPrepareFailureDoesNotSpawn() async {
        let runner = RunnerConfig(
            name: "Tomcat",
            command: "exec \"$CATALINA_HOME\"/bin/catalina.sh run",
            workingDirectory: directory.path,
            env: [
                "CATALINA_HOME": directory.appendingPathComponent("missing-home").path,
                "CATALINA_BASE": directory.appendingPathComponent("base").path
            ],
            idea: IdeaOrigin(configurationName: "Tomcat", configurationType: "Tomcat", adapter: .tomcat),
            debugInjection: .catalinaOpts,
            tomcatContextPath: "/CePosto",
            tomcatDocBase: directory.appendingPathComponent("target/app").path
        )
        let project = Project(name: "P", rootPath: directory.path, runners: [runner])
        session.addProject(project)
        session.start(projectID: project.id, runnerID: runner.id)
        XCTAssertTrue(spawner.requests.isEmpty)
        XCTAssertEqual(session.runtime(for: runner.id).phase, .crashed)
        XCTAssertEqual(session.logs(for: runner.id).lines, ["Configurazione Tomcat incompleta: manca conf."])
    }

    func testLogChunksBecomeLines() async throws {
        let project = add(command: "echo hi", port: nil)
        let runnerID = project.runners[0].id
        session.start(projectID: project.id, runnerID: runnerID)
        spawner.handles[0].push("hel")
        spawner.handles[0].push("lo\nwor")
        spawner.handles[0].push("ld\n")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(session.logs(for: runnerID).lines, ["hello", "world"])
    }

    func testAddRootRejectsDuplicateAndRemoveKeepsManual() throws {
        let primary = try TestSupport.makeDirectory()
        defer { TestSupport.remove(primary) }
        let secondary = try TestSupport.makeDirectory()
        defer { TestSupport.remove(secondary) }
        let imported = RunnerConfig(
            name: "dev",
            command: "npm run dev",
            workingDirectory: primary.path,
            idea: IdeaOrigin(
                configurationName: "dev",
                configurationType: "js.build_tools.npm",
                adapter: .npm,
                sourceRoot: Project.normalizePath(primary.path)
            )
        )
        let manual = RunnerConfig(name: "manual", command: "echo hi", workingDirectory: primary.path)
        let project = Project(name: "P", rootPath: primary.path, runners: [imported, manual])
        session.addProject(project)
        XCTAssertNil(session.addRoot(projectID: project.id, path: secondary.path))
        XCTAssertEqual(session.projects[0].roots.count, 2)
        XCTAssertEqual(session.addRoot(projectID: project.id, path: secondary.path), "Cartella già presente.")
        XCTAssertEqual(session.removeRoot(projectID: project.id, path: primary.path), nil)
        XCTAssertEqual(session.projects[0].roots, [Project.normalizePath(secondary.path)])
        XCTAssertEqual(session.projects[0].runners.map(\.name), ["manual"])
        XCTAssertEqual(session.removeRoot(projectID: project.id, path: secondary.path), "Serve almeno una cartella.")
    }

    func testResyncScansEveryRoot() throws {
        let front = try TestSupport.makeDirectory()
        defer { TestSupport.remove(front) }
        let back = try TestSupport.makeDirectory()
        defer { TestSupport.remove(back) }
        try FileManager.default.createDirectory(
            at: front.appendingPathComponent(".vscode"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: back.appendingPathComponent(".vscode"),
            withIntermediateDirectories: true
        )
        try TestSupport.write(
            """
            {"version":"0.2.0","configurations":[{"name":"start","type":"node","request":"launch","runtimeExecutable":"npm","runtimeArgs":["run","start"]}]}
            """,
            to: front.appendingPathComponent(".vscode/launch.json")
        )
        try TestSupport.write(
            """
            {"version":"0.2.0","configurations":[{"name":"start","type":"node","request":"launch","runtimeExecutable":"npm","runtimeArgs":["run","start"]}]}
            """,
            to: back.appendingPathComponent(".vscode/launch.json")
        )
        let project = Project(name: "todo", rootPath: front.path, roots: [front.path, back.path])
        session.addProject(project)
        session.resync(projectID: project.id)
        let runners = session.projects[0].runners
        XCTAssertEqual(runners.count, 2)
        XCTAssertEqual(Set(runners.map { $0.idea?.sourceRoot }), Set([
            Project.normalizePath(front.path),
            Project.normalizePath(back.path)
        ]))
    }

    private func add(command: String, port: Int?, debug: Bool = false, injection: DebugInjection = .none) -> Project {
        let runner = RunnerConfig(
            name: "run",
            command: command,
            workingDirectory: directory.path,
            debugEnabled: debug,
            portToCheck: port,
            debugInjection: injection
        )
        let project = Project(name: "P", rootPath: directory.path, runners: [runner])
        session.addProject(project)
        return project
    }
}

final class SignalLog: @unchecked Sendable {
    var output = ""
    var killed: [Int32] = []
    func add(_ pid: Int32, _ signal: Int32) { killed.append(pid) }
}

final class RecordingSpawner: ProcessSpawning, @unchecked Sendable {
    var requests: [SpawnRequest] = []
    var handles: [FakeHandle] = []
    func spawn(_ request: SpawnRequest) throws -> any SpawnedHandle {
        requests.append(request)
        let handle = FakeHandle(pid: Int32(1000 + requests.count))
        handles.append(handle)
        return handle
    }
}

final class FakeHandle: SpawnedHandle, @unchecked Sendable {
    let pid: Int32
    private let lock = NSLock()
    private var outputHandler: (@Sendable (String) -> Void)?
    private var exitHandler: (@Sendable (Int32) -> Void)?
    init(pid: Int32) { self.pid = pid }
    func readOutput(_ handler: @escaping @Sendable (String) -> Void) {
        lock.lock(); outputHandler = handler; lock.unlock()
    }
    func onExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock(); exitHandler = handler; lock.unlock()
    }
    func signalGroup(terminateGrace seconds: TimeInterval) { finish(143) }
    func stopAndWait(grace: TimeInterval) { finish(143) }
    func groupAlive() -> Bool { false }
    func push(_ text: String) {
        lock.lock(); let handler = outputHandler; lock.unlock()
        handler?(text)
    }
    func finish(_ code: Int32) {
        lock.lock(); let handler = exitHandler; lock.unlock()
        handler?(code)
    }
}
