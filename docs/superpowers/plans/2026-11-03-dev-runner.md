# Dev Runner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Costruire l'app menu bar macOS Dev Runner: importa le run configuration di IntelliJ, avvia i comandi in un process group isolato e li ferma con SIGTERM poi SIGKILL.

**Architecture:** La library `DevRunnerCore` contiene modello, JSON atomico, scan XML, preparazione Tomcat, `posix_spawn` e il supervisore. L'eseguibile `DevRunner` è solo SwiftUI (`MenuBarExtra`). I test importano la library, mai l'eseguibile. L'esecuzione di questo piano è sequenziale in un solo worker: i file sono accoppiati e l'utente ha già ordinato di implementare senza chiedere la modalità.

**Tech Stack:** Swift 6, Swift Package Manager, macOS 13+, Foundation, SwiftUI, AppKit, Darwin. Nessun package di terze parti.

## Global Constraints

- macOS 13+. Solo Foundation, SwiftUI, AppKit, Darwin.
- Testi UI in italiano, tranne le etichette approvate Start, Stop, Restart, Logs, Edit, Debug, Clear, Copy. Tema scuro. `MenuBarExtra` `.window`, larghezza 400.
- Avvio reale sempre con `posix_spawn`, `/bin/zsh -l -c` in produzione, `POSIX_SPAWN_SETPGROUP` e `setpgroup(0)` prima dell'exec. Grazia 4 secondi, iniettabile.
- `vmOptions` e `programArguments` non sono campi: finiscono nel comando o in `CATALINA_OPTS` / `JAVA_TOOL_OPTIONS`.
- File corrotto `config.json` mai sovrascritto. Un XML rotto si salta. `commandEdited` protegge il comando in resync.
- I test di porta non chiamano `kill` su pid reali. I test di processo usano `/bin/zsh -f -c`.
- Commit conventional senza id ticket, solo sul branch `dev-runner`. Nessun altro file Markdown oltre spec e piano.
- Obiettivo memoria sotto 25 MB: non è un test e non si aggiungono cache.

## Struttura file

- `Package.swift` — library, poi eseguibile dal task 11.
- `Sources/DevRunnerCore/Model.swift` — `Project`, `RunnerConfig`, origini, fasi.
- `Sources/DevRunnerCore/ConfigStore.swift` — JSON atomico.
- `Sources/DevRunnerCore/RingLog.swift` — `LineBuffer` e ring da 1000.
- `Sources/DevRunnerCore/PortTool.swift` — argv `lsof` e doppio iniettabile.
- `Sources/DevRunnerCore/DebugEnv.swift` — JDWP a runtime.
- `Sources/DevRunnerCore/MacroExpander.swift` — macro e quoting.
- `Sources/DevRunnerCore/JetBrainsLookup.swift` — home Tomcat e JDK.
- `Sources/DevRunnerCore/IdeaScanner.swift` — scan e adattatori.
- `Sources/DevRunnerCore/IdeaImporter.swift` — resync.
- `Sources/DevRunnerCore/TomcatPreparer.swift` — `CATALINA_BASE` e comando eseguito.
- `Sources/DevRunnerCore/DarwinSpawner.swift` — `posix_spawn`.
- `Sources/DevRunnerCore/Session.swift` — supervisore.
- `Sources/DevRunner/` — app SwiftUI.
- `Tests/DevRunnerCoreTests/` — test.
- `Scripts/package-app.sh` — bundle `LSUIElement`.
- `.gitignore`

## Firme usate dai task successivi

- `RunnerConfig(...)` con default: `debugEnabled false`, `debugPort 5005`, `commandEdited false`, `debugInjection .none`.
- `ConfigStore(fileURL:)`, `mutating func load() -> [Project]`, `mutating func save(_:) throws`, `func prepareForOpen() throws`, `var isCorrupt: Bool`.
- `RingLog.append(lines:)`, `filtered(query:) -> [String]`, `capacity` default 1000.
- `LineBuffer.consume(_:) -> [String]`, `flush() -> [String]`.
- `LsofCommand(port:).executable == "/usr/sbin/lsof"`, `.arguments == ["-ti", "tcp:\\(port)"]`.
- `LsofOutput.parsePids(_:) -> [Int32]`.
- `PortTool(run:signal:).isBusy(_:) -> Bool`, `.free(_:) -> [Int32]`, `static func live() -> PortTool`.
- `DebugEnv.agent(port:) -> String`, `DebugEnv.apply(runner:env:) -> [String: String]`.
- `MacroExpander.expand(_:projectRoot:userHome:) -> String`, `ShellWords.quote(_:) -> String`.
- `JetBrainsLookup.catalinaHome(serverName:files:projectRoot:userHome:) -> String?`
- `JetBrainsLookup.jdkHome(name:files:projectRoot:userHome:) -> String?`
- `JetBrainsLookup.discover(userHome:) -> (servers: [URL], jdks: [URL])`
- `IdeaScanRequest(projectRoot:configRoot:userHome:applicationServersFiles:jdkTableFiles:)` — `nil` scopre, `[]` non usa file.
- `IdeaScanner.scan(_:) -> IdeaScanResult` con `runners` e `skippedFiles`.
- `IdeaImporter.resync(existing:imported:configRoot:) -> [RunnerConfig]`.
- `TomcatPreparer.contextFileName(contextPath:) -> String`
- `TomcatPreparer.prepare(runner:) -> Result<TomcatLaunch, TomcatPrepareError>`
- `TomcatLaunch.command: String`
- `SpawnRequest(command:workingDirectory:environment:shellPath:shellArguments:)` default shell `/bin/zsh` e argomenti `["-l", "-c"]`.
- `protocol ProcessSpawning: Sendable { func spawn(_ request: SpawnRequest) throws -> any SpawnedHandle }`
- `SpawnedHandle`: `pid`, `readOutput`, `onExit`, `signalGroup(terminateGrace:)`, `groupAlive() -> Bool`.
- `DarwinProcessSpawner().spawn(_:)`.
- `Session` è `@MainActor`. Metodi: `addProject`, `updateRunner(_:commandDidChange:)`, `setDebugEnabled(_:runnerID:)`, `resync(projectID:)`, `start(projectID:runnerID:)`, `stop(runnerID:)`, `restart(projectID:runnerID:)`, `stopAll()`, `stopAllForTermination()`, `freePort(runnerID:)`, `clearLog(runnerID:)`, `logs(for:)`, `runtime(for:)`, `activeCount()`, `locate(_:)`, `configFileURLForOpen()`.

---

### Task 1: Pacchetto e modello

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/DevRunnerCore/Core.swift` (stub, rimosso nello step 3)
- Create: `Sources/DevRunnerCore/Model.swift`
- Test: `Tests/DevRunnerCoreTests/ModelTests.swift`

**Interfaces:**
- Consumes: niente.
- Produces: `IdeaAdapter`, `DebugInjection`, `IdeaOrigin`, `RunnerConfig`, `Project`, `RunnerPhase`, `RunnerRuntime`, `StoreDocument`.

- [ ] **Step 1: Write the failing test**

`Tests/DevRunnerCoreTests/ModelTests.swift`

```swift
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
```

`Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevRunner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DevRunnerCore", targets: ["DevRunnerCore"])
    ],
    targets: [
        .target(name: "DevRunnerCore"),
        .testTarget(name: "DevRunnerCoreTests", dependencies: ["DevRunnerCore"])
    ]
)
```

`.gitignore`

```gitignore
.build/
dist/
.swiftpm/
.DS_Store
```

`Sources/DevRunnerCore/Core.swift`

```swift
import Foundation
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModelTests`
Expected: FAIL, `cannot find 'RunnerConfig' in scope`

- [ ] **Step 3: Write minimal implementation**

Eliminare `Sources/DevRunnerCore/Core.swift`. Creare `Sources/DevRunnerCore/Model.swift`:

```swift
import Foundation

enum IdeaAdapter: String, Codable, Equatable, Sendable {
    case tomcat
    case npm
    case python
    case maven
    case unmapped
}

enum DebugInjection: String, Codable, Equatable, Sendable {
    case none
    case javaToolOptions
    case catalinaOpts
}

struct IdeaOrigin: Codable, Equatable, Sendable {
    var configurationName: String
    var configurationType: String
    var adapter: IdeaAdapter
}

struct RunnerConfig: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var command: String
    var workingDirectory: String
    var env: [String: String]
    var debugEnabled: Bool
    var debugPort: Int
    var portToCheck: Int?
    var commandEdited: Bool
    var idea: IdeaOrigin?
    var debugInjection: DebugInjection
    var importNote: String?
    var tomcatContextPath: String?
    var tomcatDocBase: String?

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        workingDirectory: String,
        env: [String: String] = [:],
        debugEnabled: Bool = false,
        debugPort: Int = 5005,
        portToCheck: Int? = nil,
        commandEdited: Bool = false,
        idea: IdeaOrigin? = nil,
        debugInjection: DebugInjection = .none,
        importNote: String? = nil,
        tomcatContextPath: String? = nil,
        tomcatDocBase: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.env = env
        self.debugEnabled = debugEnabled
        self.debugPort = debugPort
        self.portToCheck = portToCheck
        self.commandEdited = commandEdited
        self.idea = idea
        self.debugInjection = debugInjection
        self.importNote = importNote
        self.tomcatContextPath = tomcatContextPath
        self.tomcatDocBase = tomcatDocBase
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, command, workingDirectory, env, debugEnabled, debugPort
        case portToCheck, commandEdited, idea, debugInjection, importNote
        case tomcatContextPath, tomcatDocBase
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        debugEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugEnabled) ?? false
        debugPort = try container.decodeIfPresent(Int.self, forKey: .debugPort) ?? 5005
        portToCheck = try container.decodeIfPresent(Int.self, forKey: .portToCheck)
        commandEdited = try container.decodeIfPresent(Bool.self, forKey: .commandEdited) ?? false
        idea = try container.decodeIfPresent(IdeaOrigin.self, forKey: .idea)
        debugInjection = try container.decodeIfPresent(DebugInjection.self, forKey: .debugInjection) ?? .none
        importNote = try container.decodeIfPresent(String.self, forKey: .importNote)
        tomcatContextPath = try container.decodeIfPresent(String.self, forKey: .tomcatContextPath)
        tomcatDocBase = try container.decodeIfPresent(String.self, forKey: .tomcatDocBase)
    }
}

struct Project: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var rootPath: String
    var runners: [RunnerConfig]

    init(id: UUID = UUID(), name: String, rootPath: String, runners: [RunnerConfig] = []) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.runners = runners
    }
}

enum RunnerPhase: String, Equatable, Sendable {
    case stopped
    case starting
    case running
    case crashed
}

struct RunnerRuntime: Equatable, Sendable {
    var phase: RunnerPhase
    var pid: Int32?

    static let stopped = RunnerRuntime(phase: .stopped, pid: nil)
}

struct StoreDocument: Codable, Equatable, Sendable {
    var projects: [Project]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModelTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Package.swift .gitignore Sources/DevRunnerCore/Model.swift Tests/DevRunnerCoreTests/ModelTests.swift
git commit -m "$(cat <<'EOF'
feat: aggiunge il modello dati di Dev Runner

EOF
)"
```

---

### Task 2: ConfigStore

**Files:**
- Create: `Sources/DevRunnerCore/ConfigStore.swift`
- Create: `Tests/DevRunnerCoreTests/TestSupport.swift`
- Test: `Tests/DevRunnerCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `Project`, `RunnerConfig`, `StoreDocument`, `IdeaOrigin`.
- Produces: `ConfigStore`. `TestSupport.makeDirectory()`, `write(_:to:)`, `remove(_:)`.

- [ ] **Step 1: Write the failing test**

`Tests/DevRunnerCoreTests/TestSupport.swift`

```swift
import Foundation

enum TestSupport {
    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
```

`Tests/DevRunnerCoreTests/ConfigStoreTests.swift`

```swift
import XCTest
@testable import DevRunnerCore

final class ConfigStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = try! TestSupport.makeDirectory()
    }

    override func tearDown() {
        TestSupport.remove(root)
        super.tearDown()
    }

    func testRoundTripPreservesProjects() throws {
        let url = root.appendingPathComponent("nested/config.json")
        let origin = IdeaOrigin(configurationName: "dev", configurationType: "js.build_tools.npm", adapter: .npm)
        let runner = RunnerConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "dev",
            command: "npm run dev",
            workingDirectory: "/work",
            env: ["PORT": "3000"],
            debugEnabled: true,
            debugPort: 5005,
            portToCheck: 3000,
            commandEdited: true,
            idea: origin,
            debugInjection: .none,
            importNote: nil,
            tomcatContextPath: nil,
            tomcatDocBase: nil
        )
        let project = Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Demo",
            rootPath: "/work",
            runners: [runner]
        )
        var store = ConfigStore(fileURL: url)
        try store.save([project])
        var loaded = ConfigStore(fileURL: url)
        XCTAssertEqual(loaded.load(), [project])
        XCTAssertFalse(loaded.isCorrupt)
    }

    func testCorruptFileIsNotOverwritten() throws {
        let url = root.appendingPathComponent("config.json")
        try TestSupport.write("{", to: url)
        var store = ConfigStore(fileURL: url)
        XCTAssertEqual(store.load(), [])
        XCTAssertTrue(store.isCorrupt)
        let project = Project(name: "X", rootPath: "/tmp")
        try store.save([project])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text, "{")
    }

    func testPrepareForOpenWritesDefaultOnlyWhenMissing() throws {
        let url = root.appendingPathComponent("config.json")
        var store = ConfigStore(fileURL: url)
        try store.prepareForOpen()
        let created = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(created, "{\"projects\":[]}")
        try TestSupport.write("{", to: url)
        try store.prepareForOpen()
        let untouched = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(untouched, "{")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL, `cannot find 'ConfigStore' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/ConfigStore.swift`

```swift
import Foundation

struct ConfigStore: Sendable {
    var fileURL: URL
    private(set) var isCorrupt = false

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dev-runner/config.json")
    }

    static var defaultConfigRoot: URL {
        defaultFileURL.deletingLastPathComponent()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    mutating func load() -> [Project] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            isCorrupt = false
            return []
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            isCorrupt = true
            return []
        }
        do {
            let document = try JSONDecoder().decode(StoreDocument.self, from: data)
            isCorrupt = false
            return document.projects
        } catch {
            isCorrupt = true
            return []
        }
    }

    mutating func save(_ projects: [Project]) throws {
        if isCorrupt { return }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(StoreDocument(projects: projects))
        try writeAtomic(data, to: fileURL)
    }

    func prepareForOpen() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { return }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeAtomic(Data("{\"projects\":[]}".utf8), to: fileURL)
    }

    private func writeAtomic(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temp)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/ConfigStore.swift Tests/DevRunnerCoreTests/TestSupport.swift Tests/DevRunnerCoreTests/ConfigStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: persiste i progetti in config.json atomico

EOF
)"
```

---

### Task 3: Ring log

**Files:**
- Create: `Sources/DevRunnerCore/RingLog.swift`
- Test: `Tests/DevRunnerCoreTests/RingLogTests.swift`

**Interfaces:**
- Consumes: niente del modello.
- Produces: `LineBuffer`, `RingLog`.

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RingLogTests`
Expected: FAIL, `cannot find 'RingLog' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/RingLog.swift`

```swift
import Foundation

struct LineBuffer: Equatable, Sendable {
    private var pending = ""

    mutating func consume(_ chunk: String) -> [String] {
        pending.append(contentsOf: chunk)
        var lines: [String] = []
        while let range = pending.range(of: "\n") {
            var line = String(pending[..<range.lowerBound])
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            lines.append(line)
            pending = String(pending[range.upperBound...])
        }
        return lines
    }

    mutating func flush() -> [String] {
        guard !pending.isEmpty else { return [] }
        var line = pending
        pending = ""
        if line.hasSuffix("\r") {
            line.removeLast()
        }
        return [line]
    }
}

struct RingLog: Equatable, Sendable {
    private(set) var lines: [String] = []
    var capacity: Int = 1000

    mutating func append(lines newLines: [String]) {
        guard !newLines.isEmpty else { return }
        lines.append(contentsOf: newLines)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    mutating func clear() {
        lines.removeAll()
    }

    func filtered(query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return lines }
        return lines.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RingLogTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/RingLog.swift Tests/DevRunnerCoreTests/RingLogTests.swift
git commit -m "$(cat <<'EOF'
feat: limita i log di un runner a 1000 righe

EOF
)"
```

---

### Task 4: Porta e debug

**Files:**
- Create: `Sources/DevRunnerCore/PortTool.swift`
- Create: `Sources/DevRunnerCore/DebugEnv.swift`
- Test: `Tests/DevRunnerCoreTests/PortToolTests.swift`
- Test: `Tests/DevRunnerCoreTests/DebugEnvTests.swift`

**Interfaces:**
- Consumes: `RunnerConfig`, `DebugInjection`.
- Produces: `LsofCommand`, `LsofOutput`, `PortTool`, `DebugEnv`.

- [ ] **Step 1: Write the failing test**

`Tests/DevRunnerCoreTests/PortToolTests.swift`

```swift
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
```

`Tests/DevRunnerCoreTests/DebugEnvTests.swift`

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter 'PortToolTests|DebugEnvTests'`
Expected: FAIL, tipi `PortTool` e `DebugEnv` assenti

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/PortTool.swift`

```swift
import Darwin
import Foundation

struct LsofCommand: Equatable, Sendable {
    var port: Int

    var executable: String { "/usr/sbin/lsof" }

    var arguments: [String] { ["-ti", "tcp:\(port)"] }
}

enum LsofOutput {
    static func parsePids(_ text: String) -> [Int32] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return Int32(trimmed)
        }
    }
}

struct PortTool: Sendable {
    var run: @Sendable (_ executable: String, _ arguments: [String]) -> String
    var signal: @Sendable (_ pid: Int32, _ signal: Int32) -> Void

    func isBusy(_ port: Int) -> Bool {
        let command = LsofCommand(port: port)
        return !LsofOutput.parsePids(run(command.executable, command.arguments)).isEmpty
    }

    @discardableResult
    func free(_ port: Int) -> [Int32] {
        let command = LsofCommand(port: port)
        let pids = LsofOutput.parsePids(run(command.executable, command.arguments))
        for pid in pids {
            signal(pid, SIGKILL)
        }
        return pids
    }

    static func live() -> PortTool {
        PortTool(
            run: { executable, arguments in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    return String(decoding: data, as: UTF8.self)
                } catch {
                    return ""
                }
            },
            signal: { pid, sig in
                _ = Darwin.kill(pid, sig)
            }
        )
    }
}
```

`Sources/DevRunnerCore/DebugEnv.swift`

```swift
import Foundation

enum DebugEnv {
    static func agent(port: Int) -> String {
        "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:\(port)"
    }

    static func apply(runner: RunnerConfig, env: [String: String]) -> [String: String] {
        guard runner.debugEnabled else { return env }
        let key: String
        switch runner.debugInjection {
        case .none:
            return env
        case .javaToolOptions:
            key = "JAVA_TOOL_OPTIONS"
        case .catalinaOpts:
            key = "CATALINA_OPTS"
        }
        let token = agent(port: runner.debugPort)
        var copy = env
        let current = copy[key] ?? ""
        if current.contains(token) {
            return copy
        }
        copy[key] = current.isEmpty ? token : current + " " + token
        return copy
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter 'PortToolTests|DebugEnvTests'`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/PortTool.swift Sources/DevRunnerCore/DebugEnv.swift Tests/DevRunnerCoreTests/PortToolTests.swift Tests/DevRunnerCoreTests/DebugEnvTests.swift
git commit -m "$(cat <<'EOF'
feat: prepara il controllo porta e l'agente JDWP

EOF
)"
```

---

### Task 5: Macro e lookup JetBrains

**Files:**
- Create: `Sources/DevRunnerCore/MacroExpander.swift`
- Create: `Sources/DevRunnerCore/JetBrainsLookup.swift`
- Test: `Tests/DevRunnerCoreTests/JetBrainsLookupTests.swift`

**Interfaces:**
- Consumes: `TestSupport`.
- Produces: `MacroExpander`, `ShellWords`, `JetBrainsLookup`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DevRunnerCore

final class JetBrainsLookupTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = try! TestSupport.makeDirectory()
    }

    override func tearDown() {
        TestSupport.remove(root)
        super.tearDown()
    }

    func testApplicationServersHomeAndJdkTable() throws {
        let servers = root.appendingPathComponent("applicationServers.xml")
        let jdks = root.appendingPathComponent("jdk.table.xml")
        try TestSupport.write("""
        <application>
          <component name="ApplicationServersManager">
            <ServerSettings>
              <option name="SERVERS">
                <list>
                  <ServerSettingsImpl>
                    <option name="NAME" value="Tomcat 9.0.41" />
                    <option name="HOME" value="/Users/icsone/Documents/Progetti/apache-tomcat-9.0.41" />
                  </ServerSettingsImpl>
                </list>
              </option>
            </ServerSettings>
          </component>
        </application>
        """, to: servers)
        try TestSupport.write("""
        <application>
          <component name="ProjectJdkTable">
            <jdk version="2">
              <name value="corretto-1.8" />
              <homePath value="$USER_HOME$/Library/Java/JavaVirtualMachines/corretto-1.8.jdk/Contents/Home" />
            </jdk>
          </component>
        </application>
        """, to: jdks)
        let home = URL(fileURLWithPath: "/Users/icsone")
        let project = URL(fileURLWithPath: "/proj")
        XCTAssertEqual(
            JetBrainsLookup.catalinaHome(serverName: "Tomcat 9.0.41", files: [servers], projectRoot: project, userHome: home),
            "/Users/icsone/Documents/Progetti/apache-tomcat-9.0.41"
        )
        XCTAssertEqual(
            JetBrainsLookup.jdkHome(name: "corretto-1.8", files: [jdks], projectRoot: project, userHome: home),
            "/Users/icsone/Library/Java/JavaVirtualMachines/corretto-1.8.jdk/Contents/Home"
        )
        XCTAssertNil(JetBrainsLookup.catalinaHome(serverName: "Manca", files: [servers], projectRoot: project, userHome: home))
    }

    func testJavaEEServersFileAndAbsoluteJre() throws {
        let servers = root.appendingPathComponent("javaeeAppServers.xml")
        try TestSupport.write("""
        <application>
          <component name="AppserversManager">
            <ServerDK NAME="Tomcat 9.0.41">
              <DATA>
                <option name="CATALINA_HOME" value="$USER_HOME$/Documents/Progetti/apache-tomcat-9.0.41" />
              </DATA>
            </ServerDK>
          </component>
        </application>
        """, to: servers)
        let home = URL(fileURLWithPath: "/Users/icsone")
        let project = URL(fileURLWithPath: "/proj")
        XCTAssertEqual(
            JetBrainsLookup.catalinaHome(serverName: "Tomcat 9.0.41", files: [servers], projectRoot: project, userHome: home),
            "/Users/icsone/Documents/Progetti/apache-tomcat-9.0.41"
        )
        XCTAssertEqual(
            JetBrainsLookup.jdkHome(name: "/opt/java", files: [], projectRoot: project, userHome: home),
            "/opt/java"
        )
    }

    func testDiscoverReadsJetBrainsOptions() throws {
        let options = root
            .appendingPathComponent("Library/Application Support/JetBrains/IntelliJIdeaTest/options")
        let servers = options.appendingPathComponent("applicationServers.xml")
        let jdks = options.appendingPathComponent("jdk.table.xml")
        try TestSupport.write("<application/>", to: servers)
        try TestSupport.write("<application/>", to: jdks)
        let found = JetBrainsLookup.discover(userHome: root)
        XCTAssertEqual(found.servers.map(\.lastPathComponent), ["applicationServers.xml"])
        XCTAssertEqual(found.jdks.map(\.lastPathComponent), ["jdk.table.xml"])
        XCTAssertTrue(found.servers.first?.path.contains("IntelliJIdeaTest/options/applicationServers.xml") == true)
        XCTAssertTrue(found.jdks.first?.path.contains("IntelliJIdeaTest/options/jdk.table.xml") == true)
    }

    func testShellQuoteLeavesSafeTokens() {
        XCTAssertEqual(ShellWords.quote("dev"), "dev")
        XCTAssertEqual(ShellWords.quote("a b"), "'a b'")
        XCTAssertEqual(MacroExpander.expand("$PROJECT_DIR$/app.py", projectRoot: URL(fileURLWithPath: "/proj"), userHome: URL(fileURLWithPath: "/Users/icsone")), "/proj/app.py")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter JetBrainsLookupTests`
Expected: FAIL, `cannot find 'JetBrainsLookup' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/MacroExpander.swift`

```swift
import Foundation

enum MacroExpander {
    static func expand(_ value: String, projectRoot: URL, userHome: URL) -> String {
        value
            .replacingOccurrences(of: "$PROJECT_DIR$", with: projectRoot.path)
            .replacingOccurrences(of: "$USER_HOME$", with: userHome.path)
    }
}

enum ShellWords {
    static func quote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._+-:@")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
```

`Sources/DevRunnerCore/JetBrainsLookup.swift`

```swift
import Foundation

enum JetBrainsLookup {
    static func catalinaHome(serverName: String, files: [URL], projectRoot: URL, userHome: URL) -> String? {
        for file in files {
            guard let document = try? XMLDocument(contentsOf: file, options: [.nodePreserveWhitespace]) else { continue }
            if let home = home(in: document, serverName: serverName) {
                let expanded = MacroExpander.expand(home, projectRoot: projectRoot, userHome: userHome)
                if !expanded.isEmpty { return expanded }
            }
        }
        return nil
    }

    static func jdkHome(name: String, files: [URL], projectRoot: URL, userHome: URL) -> String? {
        if name.contains("/") || name.hasPrefix("$") {
            let expanded = MacroExpander.expand(name, projectRoot: projectRoot, userHome: userHome)
            return expanded.isEmpty ? nil : expanded
        }
        for file in files {
            guard let document = try? XMLDocument(contentsOf: file, options: [.nodePreserveWhitespace]) else { continue }
            guard let nodes = try? document.nodes(forXPath: "//jdk") else { continue }
            for case let element as XMLElement in nodes {
                let jdkName = element.elements(forName: "name").first?.attribute(forName: "value")?.stringValue
                guard jdkName == name else { continue }
                if let home = element.elements(forName: "homePath").first?.attribute(forName: "value")?.stringValue {
                    let expanded = MacroExpander.expand(home, projectRoot: projectRoot, userHome: userHome)
                    if !expanded.isEmpty { return expanded }
                }
            }
        }
        return nil
    }

    static func discover(userHome: URL) -> (servers: [URL], jdks: [URL]) {
        let root = userHome.appendingPathComponent("Library/Application Support/JetBrains", isDirectory: true)
        guard let products = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [])
        }
        var servers: [URL] = []
        var jdks: [URL] = []
        for product in products {
            let options = product.appendingPathComponent("options", isDirectory: true)
            for name in ["applicationServers.xml", "javaeeAppServers.xml"] {
                let url = options.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    servers.append(url)
                }
            }
            let jdk = options.appendingPathComponent("jdk.table.xml")
            if FileManager.default.fileExists(atPath: jdk.path) {
                jdks.append(jdk)
            }
        }
        return (sortByModification(servers), sortByModification(jdks))
    }

    private static func home(in document: XMLDocument, serverName: String) -> String? {
        if let nodes = try? document.nodes(forXPath: "//ServerSettingsImpl") {
            for case let element as XMLElement in nodes {
                guard optionValue(element, name: "NAME") == serverName else { continue }
                if let home = optionValue(element, name: "HOME"), !home.isEmpty {
                    return home
                }
            }
        }
        if let nodes = try? document.nodes(forXPath: "//ServerDK") {
            for case let element as XMLElement in nodes {
                guard element.attribute(forName: "NAME")?.stringValue == serverName else { continue }
                for data in element.elements(forName: "DATA") {
                    if let home = optionValue(data, name: "CATALINA_HOME"), !home.isEmpty {
                        return home
                    }
                }
            }
        }
        return nil
    }

    private static func optionValue(_ element: XMLElement, name: String) -> String? {
        for child in element.elements(forName: "option") {
            if child.attribute(forName: "name")?.stringValue == name {
                return child.attribute(forName: "value")?.stringValue
            }
        }
        return nil
    }

    private static func sortByModification(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if left != right { return left > right }
            return lhs.path < rhs.path
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter JetBrainsLookupTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/MacroExpander.swift Sources/DevRunnerCore/JetBrainsLookup.swift Tests/DevRunnerCoreTests/JetBrainsLookupTests.swift
git commit -m "$(cat <<'EOF'
feat: risolve CATALINA_HOME e JAVA_HOME dai file JetBrains

EOF
)"
```

---

### Task 6: Scanner e adattatori

**Files:**
- Create: `Sources/DevRunnerCore/IdeaScanner.swift`
- Test: `Tests/DevRunnerCoreTests/IdeaScannerTests.swift`

**Interfaces:**
- Consumes: `RunnerConfig`, `IdeaOrigin`, `IdeaAdapter`, `DebugInjection`, `MacroExpander`, `ShellWords`, `JetBrainsLookup`, `TestSupport`.
- Produces: `IdeaScanRequest`, `IdeaScanResult`, `IdeaScanner.scan(_:) -> IdeaScanResult`.

- [ ] **Step 1: Write the failing test**

`Tests/DevRunnerCoreTests/IdeaScannerTests.swift`

```swift
import XCTest
@testable import DevRunnerCore

final class IdeaScannerTests: XCTestCase {
    private let catalinaHome = "/Users/icsone/Documents/Progetti/apache-tomcat-9.0.41"
    private let jdkHome = "/Library/Java/JavaVirtualMachines/corretto-1.8.jdk/Contents/Home"
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = try! TestSupport.makeDirectory()
    }

    override func tearDown() {
        TestSupport.remove(root)
        super.tearDown()
    }

    func testCePostoShapeNpmPythonAndProjectDir() throws {
        let layout = try writeFixture()
        let result = IdeaScanner.scan(request(layout, servers: [layout.servers], jdks: [layout.jdks]))
        XCTAssertEqual(result.skippedFiles, ["broken.xml"])

        let tomcat = try XCTUnwrap(result.runners.first { $0.name == "Tomcat 9.0.41" })
        XCTAssertEqual(tomcat.command, "exec \"$CATALINA_HOME\"/bin/catalina.sh run")
        XCTAssertTrue(tomcat.command.hasSuffix("bin/catalina.sh run"))
        XCTAssertEqual(tomcat.env["CATALINA_HOME"], catalinaHome)
        XCTAssertEqual(tomcat.env["JAVA_HOME"], jdkHome)
        XCTAssertEqual(tomcat.env["CATALINA_BASE"], layout.config.appendingPathComponent("catalina").appendingPathComponent(tomcat.id.uuidString).path)
        XCTAssertEqual(tomcat.tomcatContextPath, "/CePosto")
        XCTAssertEqual(tomcat.tomcatDocBase, layout.root.appendingPathComponent("target/ceposto-java-server").path)
        XCTAssertEqual(tomcat.portToCheck, 8080)
        XCTAssertEqual(tomcat.debugPort, 5005)
        XCTAssertEqual(tomcat.debugInjection, .catalinaOpts)
        XCTAssertEqual(tomcat.idea?.adapter, .tomcat)
        XCTAssertEqual(tomcat.idea?.configurationType, "#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory")
        XCTAssertNil(tomcat.importNote)
        XCTAssertFalse(tomcat.commandEdited)

        let npm = try XCTUnwrap(result.runners.first { $0.name == "dev" })
        XCTAssertEqual(npm.command, "npm run dev")
        XCTAssertEqual(npm.env["PORT"], "3000")
        XCTAssertEqual(npm.debugInjection, .none)
        XCTAssertEqual(npm.workingDirectory, layout.root.path)

        let python = try XCTUnwrap(result.runners.first { $0.name == "app" })
        XCTAssertEqual(python.command, "python3 \(layout.root.path)/app.py")
        XCTAssertEqual(python.workingDirectory, layout.root.path)
        XCTAssertEqual(python.env["PYTHONUNBUFFERED"], "1")
        XCTAssertEqual(python.debugInjection, .none)

        let maven = try XCTUnwrap(result.runners.first { $0.name == "boot" })
        XCTAssertEqual(maven.command, "mvn spring-boot:run")
        XCTAssertEqual(maven.debugInjection, .javaToolOptions)
        XCTAssertEqual(maven.env["JAVA_TOOL_OPTIONS"], "-Dfile.encoding=UTF-8")

        let docker = try XCTUnwrap(result.runners.first { $0.name == "container" })
        XCTAssertEqual(docker.command, "")
        XCTAssertEqual(docker.idea?.adapter, .unmapped)
        XCTAssertEqual(docker.importNote, "Tipo di configurazione non mappato.")
    }

    func testMissingServerYieldsEmptyCommand() throws {
        let layout = try writeFixture()
        let result = IdeaScanner.scan(request(layout, servers: [], jdks: []))
        let tomcat = try XCTUnwrap(result.runners.first { $0.name == "Tomcat 9.0.41" })
        XCTAssertEqual(tomcat.command, "")
        XCTAssertTrue(tomcat.importNote?.contains("Server Tomcat non trovato in applicationServers.xml.") == true)
    }

    func testArtifactOutputPathAndMvnwAndBareApplication() throws {
        let layout = try writeFixture()
        try TestSupport.write("""
        <component name="ArtifactManager">
          <artifact type="exploded-war" name="ceposto-java-server:war exploded">
            <output-path>$PROJECT_DIR$/out/artifacts/ceposto</output-path>
          </artifact>
        </component>
        """, to: layout.root.appendingPathComponent(".idea/artifacts/ceposto.xml"))
        try TestSupport.write("", to: layout.root.appendingPathComponent("mvnw"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration name="Main" type="Application" factoryName="Application">
            <option name="MAIN_CLASS_NAME" value="com.example.Main" />
          </configuration>
          <configuration name="Spring" type="SpringBootApplicationConfigurationType" factoryName="Spring Boot">
            <option name="SPRING_BOOT_MAIN_CLASS" value="com.example.App" />
          </configuration>
        </component>
        """, to: layout.root.appendingPathComponent(".idea/runConfigurations/app-extra.xml"))
        let result = IdeaScanner.scan(request(layout, servers: [layout.servers], jdks: [layout.jdks]))
        let tomcat = try XCTUnwrap(result.runners.first { $0.name == "Tomcat 9.0.41" })
        XCTAssertEqual(tomcat.tomcatDocBase, layout.root.appendingPathComponent("out/artifacts/ceposto").path)
        let maven = try XCTUnwrap(result.runners.first { $0.name == "boot" })
        XCTAssertEqual(maven.command, "./mvnw spring-boot:run")
        XCTAssertEqual(result.runners.first { $0.name == "Main" }?.importNote, "Application con sola main class: il classpath di IntelliJ non è un comando di shell.")
        XCTAssertEqual(result.runners.first { $0.name == "Main" }?.command, "")
        XCTAssertEqual(result.runners.first { $0.name == "Spring" }?.importNote, "Application Spring senza goal Maven portatile.")
        XCTAssertEqual(result.runners.first { $0.name == "Spring" }?.idea?.adapter, .unmapped)
    }

    private struct Layout {
        var root: URL
        var config: URL
        var servers: URL
        var jdks: URL
    }

    private func request(_ layout: Layout, servers: [URL], jdks: [URL]) -> IdeaScanRequest {
        IdeaScanRequest(
            projectRoot: layout.root,
            configRoot: layout.config,
            userHome: URL(fileURLWithPath: "/Users/icsone"),
            applicationServersFiles: servers,
            jdkTableFiles: jdks
        )
    }

    private func writeFixture() throws -> Layout {
        let project = root.appendingPathComponent("project")
        let config = root.appendingPathComponent("config-root")
        let servers = root.appendingPathComponent("applicationServers.xml")
        let jdks = root.appendingPathComponent("jdk.table.xml")
        try TestSupport.write("""
        <project version="4">
          <component name="RunManager" selected="Tomcat Server.Tomcat 9.0.41">
            <configuration name="Tomcat 9.0.41" type="#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory" factoryName="Local" APPLICATION_SERVER_NAME="Tomcat 9.0.41" ALTERNATIVE_JRE_ENABLED="true" ALTERNATIVE_JRE_PATH="corretto-1.8">
              <deployment>
                <artifact name="ceposto-java-server:war exploded">
                  <settings>
                    <option name="CONTEXT_PATH" value="/CePosto" />
                  </settings>
                </artifact>
              </deployment>
              <RunnerSettings RunnerId="Debug">
                <option name="DEBUG_PORT" value="5005" />
              </RunnerSettings>
            </configuration>
          </component>
          <component name="XDebuggerManager">
            <watches-manager>
              <configuration name="#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory" />
            </watches-manager>
          </component>
        </project>
        """, to: project.appendingPathComponent(".idea/workspace.xml"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration name="dev" type="js.build_tools.npm" factoryName="npm">
            <package-json value="$PROJECT_DIR$/package.json" />
            <command value="run" />
            <scripts><script value="dev" /></scripts>
            <envs><env name="PORT" value="3000" /></envs>
          </configuration>
        </component>
        """, to: project.appendingPathComponent(".idea/runConfigurations/npm.xml"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration name="app" type="PythonConfigurationType" factoryName="Python">
            <option name="SDK_HOME" value="" />
            <option name="WORKING_DIRECTORY" value="$PROJECT_DIR$" />
            <option name="SCRIPT_NAME" value="$PROJECT_DIR$/app.py" />
            <option name="PARAMETERS" value="" />
            <option name="MODULE_MODE" value="false" />
            <envs><env name="PYTHONUNBUFFERED" value="1" /></envs>
          </configuration>
        </component>
        """, to: project.appendingPathComponent(".idea/runConfigurations/python.xml"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration name="boot" type="MavenRunConfiguration" factoryName="Maven">
            <option name="WORKING_DIRECTORY" value="$PROJECT_DIR$" />
            <option name="VM_PARAMETERS" value="-Dfile.encoding=UTF-8" />
            <option name="goals"><list><option value="spring-boot:run" /></list></option>
          </configuration>
        </component>
        """, to: project.appendingPathComponent(".idea/runConfigurations/maven.xml"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration name="container" type="DockerRunConfiguration" factoryName="Docker" />
        </component>
        """, to: project.appendingPathComponent(".idea/runConfigurations/docker.xml"))
        try TestSupport.write("<not-xml", to: project.appendingPathComponent(".idea/runConfigurations/broken.xml"))
        try TestSupport.write("""
        <application><component name="ApplicationServersManager"><ServerSettings><option name="SERVERS"><list>
          <ServerSettingsImpl>
            <option name="NAME" value="Tomcat 9.0.41" />
            <option name="HOME" value="\(catalinaHome)" />
          </ServerSettingsImpl>
        </list></option></ServerSettings></component></application>
        """, to: servers)
        try TestSupport.write("""
        <application><component name="ProjectJdkTable"><jdk version="2">
          <name value="corretto-1.8" />
          <homePath value="\(jdkHome)" />
        </jdk></component></application>
        """, to: jdks)
        return Layout(root: project, config: config, servers: servers, jdks: jdks)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IdeaScannerTests`
Expected: FAIL, `cannot find 'IdeaScanner' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/IdeaScanner.swift`

```swift
import Foundation

struct IdeaScanRequest: Sendable {
    var projectRoot: URL
    var configRoot: URL
    var userHome: URL
    var applicationServersFiles: [URL]? = nil
    var jdkTableFiles: [URL]? = nil
}

struct IdeaScanResult: Equatable, Sendable {
    var runners: [RunnerConfig]
    var skippedFiles: [String]
}

enum IdeaScanner {
    static func scan(_ request: IdeaScanRequest) -> IdeaScanResult {
        let servers = request.applicationServersFiles ?? JetBrainsLookup.discover(userHome: request.userHome).servers
        let jdks = request.jdkTableFiles ?? JetBrainsLookup.discover(userHome: request.userHome).jdks
        var runners: [RunnerConfig] = []
        var skipped: [String] = []
        var seen: Set<String> = []
        let runConfigDir = request.projectRoot.appendingPathComponent(".idea/runConfigurations", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: runConfigDir, includingPropertiesForKeys: nil) {
            let xmls = files
                .filter { $0.pathExtension.lowercased() == "xml" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in xmls {
                ingest(file: file, request: request, servers: servers, jdks: jdks, runners: &runners, skipped: &skipped, seen: &seen)
            }
        }
        let workspace = request.projectRoot.appendingPathComponent(".idea/workspace.xml")
        if FileManager.default.fileExists(atPath: workspace.path) {
            ingest(file: workspace, request: request, servers: servers, jdks: jdks, runners: &runners, skipped: &skipped, seen: &seen)
        }
        return IdeaScanResult(runners: runners, skippedFiles: skipped)
    }

    private static func ingest(
        file: URL,
        request: IdeaScanRequest,
        servers: [URL],
        jdks: [URL],
        runners: inout [RunnerConfig],
        skipped: inout [String],
        seen: inout Set<String>
    ) {
        let document: XMLDocument
        do {
            document = try XMLDocument(contentsOf: file, options: [.nodePreserveWhitespace])
        } catch {
            skipped.append(file.lastPathComponent)
            return
        }
        let xpath = "//component[@name='RunManager']/configuration | //component[@name='ProjectRunConfigurationManager']/configuration"
        guard let nodes = try? document.nodes(forXPath: xpath) else { return }
        for case let element as XMLElement in nodes {
            guard let name = element.attribute(forName: "name")?.stringValue,
                  let type = element.attribute(forName: "type")?.stringValue,
                  !name.isEmpty, !type.isEmpty else { continue }
            let key = name + "\u{0}" + type
            if seen.contains(key) { continue }
            seen.insert(key)
            runners.append(map(element: element, name: name, type: type, request: request, servers: servers, jdks: jdks))
        }
    }

    private static func map(
        element: XMLElement,
        name: String,
        type: String,
        request: IdeaScanRequest,
        servers: [URL],
        jdks: [URL]
    ) -> RunnerConfig {
        let factory = element.attribute(forName: "factoryName")?.stringValue ?? ""
        if type.contains("Tomcat") {
            return mapTomcat(element: element, name: name, type: type, request: request, servers: servers, jdks: jdks)
        }
        if type.contains("js.build_tools.npm") || factory.caseInsensitiveCompare("npm") == .orderedSame {
            return mapNpm(element: element, name: name, type: type, request: request)
        }
        if type.contains("Python") {
            return mapPython(element: element, name: name, type: type, request: request)
        }
        if type.localizedCaseInsensitiveContains("Maven") {
            if goals(element).isEmpty {
                return mapUnmapped(element: element, name: name, type: type, request: request)
            }
            return mapMaven(element: element, name: name, type: type, request: request)
        }
        if type.localizedCaseInsensitiveContains("Spring") && !goals(element).isEmpty {
            return mapMaven(element: element, name: name, type: type, request: request)
        }
        return mapUnmapped(element: element, name: name, type: type, request: request)
    }

    private static func mapTomcat(
        element: XMLElement,
        name: String,
        type: String,
        request: IdeaScanRequest,
        servers: [URL],
        jdks: [URL]
    ) -> RunnerConfig {
        let id = UUID()
        let serverName = element.attribute(forName: "APPLICATION_SERVER_NAME")?.stringValue ?? ""
        let home = JetBrainsLookup.catalinaHome(serverName: serverName, files: servers, projectRoot: request.projectRoot, userHome: request.userHome)
        let jreEnabled = element.attribute(forName: "ALTERNATIVE_JRE_ENABLED")?.stringValue == "true"
        let jrePath = element.attribute(forName: "ALTERNATIVE_JRE_PATH")?.stringValue ?? ""
        var notes: [String] = []
        if home == nil {
            notes.append("Server Tomcat non trovato in applicationServers.xml.")
        }
        var javaHome: String?
        if jreEnabled && !jrePath.isEmpty {
            if let resolved = JetBrainsLookup.jdkHome(name: jrePath, files: jdks, projectRoot: request.projectRoot, userHome: request.userHome) {
                javaHome = resolved
            } else {
                notes.append("JRE «\(jrePath)» non trovato in jdk.table.xml.")
            }
        }
        var env = environment(element, request: request)
        if let home { env["CATALINA_HOME"] = home }
        env["CATALINA_BASE"] = request.configRoot.appendingPathComponent("catalina").appendingPathComponent(id.uuidString).path
        if let javaHome { env["JAVA_HOME"] = javaHome }
        let vm = MacroExpander.expand(vmParameters(element), projectRoot: request.projectRoot, userHome: request.userHome)
        appendVar("CATALINA_OPTS", value: vm, env: &env)
        var command = ""
        if home != nil && notes.isEmpty {
            command = "exec \"$CATALINA_HOME\"/bin/catalina.sh run"
            let params = programParameters(element, request: request)
            if !params.isEmpty { command += " " + params }
        }
        let artifact = artifactName(element)
        let context = {
            let raw = (option(element, "CONTEXT_PATH") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "/" : raw
        }()
        let port = Int((option(element, "HTTP_PORT") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
        let debugPort = Int((option(element, "DEBUG_PORT") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5005
        return RunnerConfig(
            id: id,
            name: name,
            command: command,
            workingDirectory: request.projectRoot.path,
            env: env,
            debugPort: debugPort,
            portToCheck: port,
            idea: IdeaOrigin(configurationName: name, configurationType: type, adapter: .tomcat),
            debugInjection: .catalinaOpts,
            importNote: notes.isEmpty ? nil : notes.joined(separator: " "),
            tomcatContextPath: context,
            tomcatDocBase: docBase(artifactName: artifact, request: request)
        )
    }

    private static func mapNpm(element: XMLElement, name: String, type: String, request: IdeaScanRequest) -> RunnerConfig {
        let script = element.elements(forName: "scripts").first?.elements(forName: "script").first?.attribute(forName: "value")?.stringValue
        let npmCommand = element.elements(forName: "command").first?.attribute(forName: "value")?.stringValue ?? option(element, "command") ?? ""
        let command: String
        if npmCommand == "run", let script, !script.isEmpty {
            command = "npm run \(ShellWords.quote(MacroExpander.expand(script, projectRoot: request.projectRoot, userHome: request.userHome)))"
        } else if !npmCommand.isEmpty {
            command = "npm \(ShellWords.quote(npmCommand))"
        } else {
            command = ""
        }
        var work = request.projectRoot.path
        if let raw = element.elements(forName: "package-json").first?.attribute(forName: "value")?.stringValue, !raw.isEmpty {
            let expanded = MacroExpander.expand(raw, projectRoot: request.projectRoot, userHome: request.userHome)
            work = URL(fileURLWithPath: expanded).deletingLastPathComponent().path
        }
        return plain(
            element: element, name: name, type: type, request: request,
            command: command, workingDirectory: work, adapter: .npm, injection: .none, note: nil
        )
    }

    private static func mapPython(element: XMLElement, name: String, type: String, request: IdeaScanRequest) -> RunnerConfig {
        let command: String
        if let shell = firstText(option(element, "SCRIPT_TEXT"), option(element, "COMMAND")) {
            command = MacroExpander.expand(shell, projectRoot: request.projectRoot, userHome: request.userHome)
        } else {
            let sdk = (option(element, "SDK_HOME") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let interpreter = sdk.isEmpty ? "python3" : MacroExpander.expand(sdk, projectRoot: request.projectRoot, userHome: request.userHome)
            let script = MacroExpander.expand(option(element, "SCRIPT_NAME") ?? "", projectRoot: request.projectRoot, userHome: request.userHome)
            let module = option(element, "MODULE_MODE") == "true"
            if module {
                command = "\(ShellWords.quote(interpreter)) -m \(ShellWords.quote(script))"
            } else {
                command = "\(ShellWords.quote(interpreter)) \(ShellWords.quote(script))"
            }
            let params = (option(element, "PARAMETERS") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if params.isEmpty {
                return plain(element: element, name: name, type: type, request: request, command: command, workingDirectory: workingDirectory(element, request: request), adapter: .python, injection: .none, note: nil)
            }
            return plain(element: element, name: name, type: type, request: request, command: command + " " + params, workingDirectory: workingDirectory(element, request: request), adapter: .python, injection: .none, note: nil)
        }
        return plain(element: element, name: name, type: type, request: request, command: command, workingDirectory: workingDirectory(element, request: request), adapter: .python, injection: .none, note: nil)
    }

    private static func mapMaven(element: XMLElement, name: String, type: String, request: IdeaScanRequest) -> RunnerConfig {
        let goalList = goals(element)
        let mvnw = request.projectRoot.appendingPathComponent("mvnw")
        let tool = FileManager.default.fileExists(atPath: mvnw.path) ? "./mvnw" : "mvn"
        var command = ([tool] + goalList.map(ShellWords.quote)).joined(separator: " ")
        let params = programParameters(element, request: request)
        if !params.isEmpty { command += " " + params }
        var env = environment(element, request: request)
        let vm = MacroExpander.expand(vmParameters(element), projectRoot: request.projectRoot, userHome: request.userHome)
        appendVar("JAVA_TOOL_OPTIONS", value: vm, env: &env)
        return RunnerConfig(
            name: name,
            command: command,
            workingDirectory: workingDirectory(element, request: request),
            env: env,
            idea: IdeaOrigin(configurationName: name, configurationType: type, adapter: .maven),
            debugInjection: .javaToolOptions
        )
    }

    private static func mapUnmapped(element: XMLElement, name: String, type: String, request: IdeaScanRequest) -> RunnerConfig {
        plain(
            element: element, name: name, type: type, request: request,
            command: "", workingDirectory: workingDirectory(element, request: request),
            adapter: .unmapped, injection: .none, note: unmappedNote(type)
        )
    }

    private static func plain(
        element: XMLElement,
        name: String,
        type: String,
        request: IdeaScanRequest,
        command: String,
        workingDirectory: String,
        adapter: IdeaAdapter,
        injection: DebugInjection,
        note: String?
    ) -> RunnerConfig {
        RunnerConfig(
            name: name,
            command: command,
            workingDirectory: workingDirectory,
            env: environment(element, request: request),
            idea: IdeaOrigin(configurationName: name, configurationType: type, adapter: adapter),
            debugInjection: injection,
            importNote: note
        )
    }

    private static func unmappedNote(_ type: String) -> String {
        if type.localizedCaseInsensitiveContains("Spring") {
            return "Application Spring senza goal Maven portatile."
        }
        if type == "Application" {
            return "Application con sola main class: il classpath di IntelliJ non è un comando di shell."
        }
        return "Tipo di configurazione non mappato."
    }

    private static func docBase(artifactName: String?, request: IdeaScanRequest) -> String? {
        guard let artifactName, !artifactName.isEmpty else { return nil }
        let artifactsDir = request.projectRoot.appendingPathComponent(".idea/artifacts", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: artifactsDir, includingPropertiesForKeys: nil) {
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension.lowercased() == "xml" {
                guard let document = try? XMLDocument(contentsOf: file, options: [.nodePreserveWhitespace]) else { continue }
                guard let nodes = try? document.nodes(forXPath: "//artifact[@name=\(xpathLiteral(artifactName))]") else { continue }
                for case let artifact as XMLElement in nodes {
                    let text = artifact.elements(forName: "output-path").first?.stringValue?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !text.isEmpty {
                        return MacroExpander.expand(text, projectRoot: request.projectRoot, userHome: request.userHome)
                    }
                }
            }
        }
        let artifactId: String
        if let colon = artifactName.firstIndex(of: ":") {
            artifactId = artifactName[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            artifactId = artifactName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return request.projectRoot.appendingPathComponent("target").appendingPathComponent(artifactId).path
    }

    private static func artifactName(_ element: XMLElement) -> String? {
        guard let nodes = try? element.nodes(forXPath: "./deployment/artifact") else { return nil }
        for case let node as XMLElement in nodes {
            if let name = node.attribute(forName: "name")?.stringValue, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static func goals(_ element: XMLElement) -> [String] {
        var values: [String] = []
        for query in [".//option[@name='goals']/list/option", ".//goals/option"] {
            guard let nodes = try? element.nodes(forXPath: query) else { continue }
            for case let node as XMLElement in nodes {
                let value = (node.attribute(forName: "value")?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { values.append(value) }
            }
        }
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func vmParameters(_ element: XMLElement) -> String {
        for query in [".//ConfigurationWrapper[@RunnerId='Run']//option[@name='VM_PARAMETERS']", ".//option[@name='VM_PARAMETERS']"] {
            guard let nodes = try? element.nodes(forXPath: query) else { continue }
            for case let node as XMLElement in nodes {
                let value = (node.attribute(forName: "value")?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return ""
    }

    private static func environment(_ element: XMLElement, request: IdeaScanRequest) -> [String: String] {
        var result: [String: String] = [:]
        guard let nodes = try? element.nodes(forXPath: ".//envs/env") else { return result }
        for case let node as XMLElement in nodes {
            guard let name = node.attribute(forName: "name")?.stringValue else { continue }
            let value = node.attribute(forName: "value")?.stringValue ?? ""
            result[name] = MacroExpander.expand(value, projectRoot: request.projectRoot, userHome: request.userHome)
        }
        return result
    }

    private static func option(_ element: XMLElement, _ name: String) -> String? {
        guard let nodes = try? element.nodes(forXPath: ".//option[@name='\(name)']") else { return nil }
        for case let node as XMLElement in nodes {
            if let value = node.attribute(forName: "value")?.stringValue {
                return value
            }
            let text = node.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func workingDirectory(_ element: XMLElement, request: IdeaScanRequest) -> String {
        let raw = (option(element, "WORKING_DIRECTORY") ?? option(element, "workingDirPath") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return request.projectRoot.path }
        return MacroExpander.expand(raw, projectRoot: request.projectRoot, userHome: request.userHome)
    }

    private static func programParameters(_ element: XMLElement, request: IdeaScanRequest) -> String {
        let raw = (option(element, "PROGRAM_PARAMETERS") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return MacroExpander.expand(raw, projectRoot: request.projectRoot, userHome: request.userHome)
    }

    private static func appendVar(_ key: String, value: String, env: inout [String: String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existing = env[key] ?? ""
        env[key] = existing.isEmpty ? trimmed : existing + " " + trimmed
    }

    private static func firstText(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func xpathLiteral(_ value: String) -> String {
        if !value.contains("'") { return "'\(value)'" }
        if !value.contains("\"") { return "\"\(value)\"" }
        let parts = value.map { character -> String in
            if character == "'" { return "\"'\"" }
            return "'\(character)'"
        }
        return "concat(\(parts.joined(separator: ",")))"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IdeaScannerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/IdeaScanner.swift Tests/DevRunnerCoreTests/IdeaScannerTests.swift
git commit -m "$(cat <<'EOF'
feat: importa le run configuration da .idea

EOF
)"
```

---

### Task 7: Resync

**Files:**
- Create: `Sources/DevRunnerCore/IdeaImporter.swift`
- Test: `Tests/DevRunnerCoreTests/ResyncTests.swift`

**Interfaces:**
- Consumes: `RunnerConfig`, `IdeaOrigin`.
- Produces: `IdeaImporter.resync(existing:imported:configRoot:) -> [RunnerConfig]`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DevRunnerCore

final class ResyncTests: XCTestCase {
    func testEditedCommandIsKeptWhileMetadataUpdates() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let origin = IdeaOrigin(configurationName: "dev", configurationType: "js.build_tools.npm", adapter: .npm)
        let existing = RunnerConfig(
            id: id, name: "Old", command: "custom", workingDirectory: "/keep",
            env: ["A": "1"], debugEnabled: true, debugPort: 5005, portToCheck: 1,
            commandEdited: true, idea: origin, debugInjection: .none
        )
        let imported = RunnerConfig(
            name: "New", command: "npm run dev", workingDirectory: "/other",
            env: ["B": "2"], portToCheck: 3000, idea: origin, debugInjection: .none
        )
        let result = IdeaImporter.resync(existing: [existing], imported: [imported], configRoot: URL(fileURLWithPath: "/tmp/cfg"))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].command, "custom")
        XCTAssertEqual(result[0].name, "New")
        XCTAssertEqual(result[0].env, ["B": "2"])
        XCTAssertEqual(result[0].portToCheck, 3000)
        XCTAssertEqual(result[0].workingDirectory, "/keep")
        XCTAssertEqual(result[0].id, id)
        XCTAssertTrue(result[0].commandEdited)
        XCTAssertTrue(result[0].debugEnabled)
        XCTAssertEqual(result[0].debugPort, 5005)
    }

    func testUneditedCommandIsReplacedAndManualRunnersStay() {
        let id = UUID()
        let origin = IdeaOrigin(configurationName: "dev", configurationType: "js.build_tools.npm", adapter: .npm)
        let existing = RunnerConfig(id: id, name: "Old", command: "npm run old", workingDirectory: "/work", debugEnabled: true, idea: origin)
        let manual = RunnerConfig(name: "manual", command: "echo hi", workingDirectory: "/work")
        let imported = RunnerConfig(name: "New", command: "npm run dev", workingDirectory: "/work", idea: origin)
        let extra = RunnerConfig(name: "other", command: "npm test", workingDirectory: "/work", idea: IdeaOrigin(configurationName: "other", configurationType: "js.build_tools.npm", adapter: .npm))
        let result = IdeaImporter.resync(existing: [manual, existing], imported: [imported, extra], configRoot: URL(fileURLWithPath: "/tmp/cfg"))
        XCTAssertEqual(result.map(\.name), ["manual", "New", "other"])
        XCTAssertEqual(result[1].id, id)
        XCTAssertEqual(result[1].command, "npm run dev")
        XCTAssertTrue(result[1].debugEnabled)
        XCTAssertFalse(result[1].commandEdited)
    }

    func testCatalinaBaseStaysOnExistingId() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let origin = IdeaOrigin(configurationName: "Tomcat 9.0.41", configurationType: "Tomcat", adapter: .tomcat)
        let config = URL(fileURLWithPath: "/tmp/cfg")
        var existing = RunnerConfig(id: id, name: "Old", command: "custom", workingDirectory: "/p", commandEdited: true, idea: origin, debugInjection: .catalinaOpts)
        existing.env = ["CATALINA_BASE": "/old", "CATALINA_HOME": "/home"]
        var imported = RunnerConfig(name: "New", command: "exec \"$CATALINA_HOME\"/bin/catalina.sh run", workingDirectory: "/p", portToCheck: 8080, idea: origin, debugInjection: .catalinaOpts)
        imported.env = ["CATALINA_BASE": "/new-uuid", "CATALINA_HOME": "/home"]
        let result = IdeaImporter.resync(existing: [existing], imported: [imported], configRoot: config)
        XCTAssertEqual(result[0].command, "custom")
        XCTAssertEqual(result[0].env["CATALINA_HOME"], "/home")
        XCTAssertEqual(result[0].env["CATALINA_BASE"], config.appendingPathComponent("catalina").appendingPathComponent(id.uuidString).path)
        XCTAssertEqual(result[0].portToCheck, 8080)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ResyncTests`
Expected: FAIL, `cannot find 'IdeaImporter' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/IdeaImporter.swift`

```swift
import Foundation

enum IdeaImporter {
    static func resync(existing: [RunnerConfig], imported: [RunnerConfig], configRoot: URL) -> [RunnerConfig] {
        var pending = imported
        var result: [RunnerConfig] = []
        for runner in existing {
            guard let idea = runner.idea else {
                result.append(runner)
                continue
            }
            guard let index = pending.firstIndex(where: {
                $0.idea?.configurationName == idea.configurationName &&
                $0.idea?.configurationType == idea.configurationType
            }) else {
                result.append(runner)
                continue
            }
            let importedRunner = pending.remove(at: index)
            if runner.commandEdited {
                var updated = runner
                updated.name = importedRunner.name
                updated.env = rewriteBase(importedRunner.env, id: runner.id, configRoot: configRoot)
                updated.portToCheck = importedRunner.portToCheck
                result.append(updated)
            } else {
                var updated = importedRunner
                updated.id = runner.id
                updated.debugEnabled = runner.debugEnabled
                updated.commandEdited = false
                updated.env = rewriteBase(updated.env, id: runner.id, configRoot: configRoot)
                result.append(updated)
            }
        }
        result.append(contentsOf: pending)
        return result
    }

    private static func rewriteBase(_ env: [String: String], id: UUID, configRoot: URL) -> [String: String] {
        var env = env
        if env["CATALINA_BASE"] != nil {
            env["CATALINA_BASE"] = configRoot
                .appendingPathComponent("catalina")
                .appendingPathComponent(id.uuidString)
                .path
        }
        return env
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ResyncTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/IdeaImporter.swift Tests/DevRunnerCoreTests/ResyncTests.swift
git commit -m "$(cat <<'EOF'
feat: risincronizza .idea senza toccare un comando modificato

EOF
)"
```

---

### Task 8: Preparazione Tomcat

**Files:**
- Create: `Sources/DevRunnerCore/TomcatPreparer.swift`
- Test: `Tests/DevRunnerCoreTests/TomcatPreparerTests.swift`

**Interfaces:**
- Consumes: `RunnerConfig`, `IdeaOrigin`.
- Produces: `TomcatLaunch`, `TomcatPrepareError`, `TomcatPreparer.contextFileName(contextPath:)`, `TomcatPreparer.prepare(runner:) -> Result<TomcatLaunch, TomcatPrepareError>`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import DevRunnerCore

final class TomcatPreparerTests: XCTestCase {
    func testContextFileName() {
        XCTAssertEqual(TomcatPreparer.contextFileName(contextPath: "/CePosto"), "CePosto.xml")
        XCTAssertEqual(TomcatPreparer.contextFileName(contextPath: "/"), "ROOT.xml")
        XCTAssertEqual(TomcatPreparer.contextFileName(contextPath: "/a/b"), "a#b.xml")
    }

    func testPrepareWritesContextAndPrefixesMavenUntilDocBaseExists() throws {
        let root = try TestSupport.makeDirectory()
        defer { TestSupport.remove(root) }
        let home = root.appendingPathComponent("tomcat")
        try TestSupport.write("ORIGINAL", to: home.appendingPathComponent("conf/server.xml"))
        let base = root.appendingPathComponent("base")
        let docBase = root.appendingPathComponent("target/ceposto-java-server").path
        let stored = "exec \"$CATALINA_HOME\"/bin/catalina.sh run"
        var runner = RunnerConfig(
            name: "Tomcat 9.0.41",
            command: stored,
            workingDirectory: root.path,
            env: ["CATALINA_HOME": home.path, "CATALINA_BASE": base.path],
            idea: IdeaOrigin(configurationName: "Tomcat 9.0.41", configurationType: "Tomcat", adapter: .tomcat),
            debugInjection: .catalinaOpts,
            tomcatContextPath: "/CePosto",
            tomcatDocBase: docBase
        )
        let first = try XCTUnwrap(try TomcatPreparer.prepare(runner: runner).get())
        XCTAssertEqual(first.command, "mvn -DskipTests -q war:exploded && \(stored)")
        let context = base.appendingPathComponent("conf/Catalina/localhost/CePosto.xml")
        let contextText = try String(contentsOf: context, encoding: .utf8)
        XCTAssertTrue(contextText.contains(docBase))
        XCTAssertEqual(try String(contentsOf: base.appendingPathComponent("conf/server.xml"), encoding: .utf8), "ORIGINAL")
        try TestSupport.write("EDITED", to: base.appendingPathComponent("conf/server.xml"))
        try FileManager.default.createDirectory(atPath: docBase, withIntermediateDirectories: true)
        let second = try XCTUnwrap(try TomcatPreparer.prepare(runner: runner).get())
        XCTAssertEqual(second.command, stored)
        XCTAssertEqual(try String(contentsOf: base.appendingPathComponent("conf/server.xml"), encoding: .utf8), "EDITED")
        runner.commandEdited = true
        try FileManager.default.removeItem(atPath: docBase)
        let edited = try XCTUnwrap(try TomcatPreparer.prepare(runner: runner).get())
        XCTAssertEqual(edited.command, stored)
    }

    func testMissingConfDoesNotPretendSuccess() throws {
        let root = try TestSupport.makeDirectory()
        defer { TestSupport.remove(root) }
        let runner = RunnerConfig(
            name: "Tomcat",
            command: "exec \"$CATALINA_HOME\"/bin/catalina.sh run",
            workingDirectory: root.path,
            env: ["CATALINA_HOME": root.appendingPathComponent("missing").path, "CATALINA_BASE": root.appendingPathComponent("base").path],
            tomcatContextPath: "/CePosto",
            tomcatDocBase: root.appendingPathComponent("target/app").path
        )
        let result = TomcatPreparer.prepare(runner: runner)
        guard case .failure(.missingConf) = result else {
            return XCTFail("atteso missingConf, ottenuto \(result)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TomcatPreparerTests`
Expected: FAIL, `cannot find 'TomcatPreparer' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/TomcatPreparer.swift`

```swift
import Foundation

struct TomcatLaunch: Equatable, Sendable {
    var command: String
}

enum TomcatPrepareError: Error, Equatable, CustomStringConvertible {
    case missingCatalinaHome
    case missingJavaHome
    case missingArtifactPath
    case missingCatalinaBase
    case missingConf
    case copyFailed(String)

    var description: String {
        switch self {
        case .missingCatalinaHome:
            return "CATALINA_HOME non trovato."
        case .missingJavaHome:
            return "JRE non trovato sul disco."
        case .missingArtifactPath:
            return "Percorso artifact mancante."
        case .missingCatalinaBase:
            return "CATALINA_BASE mancante."
        case .missingConf:
            return "Configurazione Tomcat incompleta: manca conf."
        case .copyFailed(let message):
            return "Copia di conf non riuscita: \(message)"
        }
    }
}

enum TomcatPreparer {
    static func contextFileName(contextPath: String) -> String {
        var path = contextPath
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { return "ROOT.xml" }
        path = path.replacingOccurrences(of: "/", with: "#")
        return path + ".xml"
    }

    static func prepare(runner: RunnerConfig, fileManager: FileManager = .default) -> Result<TomcatLaunch, TomcatPrepareError> {
        let home = runner.env["CATALINA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if home.isEmpty { return .failure(.missingCatalinaHome) }
        if let java = runner.env["JAVA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !java.isEmpty {
            var isDir: ObjCBool = false
            if !fileManager.fileExists(atPath: java, isDirectory: &isDir) || !isDir.boolValue {
                return .failure(.missingJavaHome)
            }
        }
        let docBase = runner.tomcatDocBase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if docBase.isEmpty { return .failure(.missingArtifactPath) }
        let basePath = runner.env["CATALINA_BASE"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if basePath.isEmpty { return .failure(.missingCatalinaBase) }
        let base = URL(fileURLWithPath: basePath, isDirectory: true)
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
            for folder in ["logs", "temp", "webapps", "work"] {
                try fileManager.createDirectory(at: base.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
            }
            let confDest = base.appendingPathComponent("conf", isDirectory: true)
            if !fileManager.fileExists(atPath: confDest.path) {
                let confSource = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("conf", isDirectory: true)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: confSource.path, isDirectory: &isDir), isDir.boolValue else {
                    return .failure(.missingConf)
                }
                try fileManager.copyItem(at: confSource, to: confDest)
            }
            let fileName = contextFileName(contextPath: runner.tomcatContextPath ?? "/")
            let localhost = confDest.appendingPathComponent("Catalina/localhost", isDirectory: true)
            try fileManager.createDirectory(at: localhost, withIntermediateDirectories: true)
            try contextXML(docBase: docBase).write(to: localhost.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }
        let stored = runner.command
        let command: String
        if runner.commandEdited || directoryExists(docBase, fileManager) {
            command = stored
        } else {
            command = "mvn -DskipTests -q war:exploded && \(stored)"
        }
        return .success(TomcatLaunch(command: command))
    }

    private static func directoryExists(_ path: String, _ fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func contextXML(docBase: String) -> String {
        let escaped = docBase
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Context docBase="\(escaped)" />
        """
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TomcatPreparerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/TomcatPreparer.swift Tests/DevRunnerCoreTests/TomcatPreparerTests.swift
git commit -m "$(cat <<'EOF'
feat: prepara CATALINA_BASE prima di catalina.sh

EOF
)"
```

---

### Task 9: Process group con posix_spawn

**Files:**
- Create: `Sources/DevRunnerCore/DarwinSpawner.swift`
- Test: `Tests/DevRunnerCoreTests/ProcessGroupTests.swift`

**Interfaces:**
- Consumes: niente dei task UI.
- Produces: `SpawnRequest`, `SpawnedHandle`, `ProcessSpawning`, `DarwinProcessSpawner`, `SpawnError`.

I test di questo task vanno eseguiti fuori dalla sandbox: `zsh` chiama `nice` quando mette un job in background e la sandbox lo blocca. Il comando di verifica è `swift test --filter ProcessGroupTests`.

- [ ] **Step 1: Write the failing test**

```swift
import Darwin
import XCTest
@testable import DevRunnerCore

final class ProcessGroupTests: XCTestCase {
    func testBackgroundSleepDiesWithItsGroup() throws {
        let spawner = DarwinProcessSpawner()
        let handle = try spawner.spawn(SpawnRequest(
            command: "sleep 30 & echo $!; wait",
            workingDirectory: "/tmp",
            environment: [:],
            shellPath: "/bin/zsh",
            shellArguments: ["-f", "-c"]
        ))
        defer {
            Darwin.kill(-handle.pid, SIGKILL)
            var status: Int32 = 0
            waitpid(handle.pid, &status, WNOHANG)
        }
        let box = TextBox()
        let ready = expectation(description: "pid")
        ready.assertForOverFulfill = false
        handle.readOutput { chunk in
            box.append(chunk)
            if box.text.contains("\n") { ready.fulfill() }
        }
        wait(for: [ready], timeout: 3)
        let sleepPid = box.text.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }.first
        let sleep = try XCTUnwrap(sleepPid)
        XCTAssertEqual(getpgid(handle.pid), handle.pid)
        XCTAssertEqual(getpgid(sleep), handle.pid)
        handle.signalGroup(terminateGrace: 1)
        let deadline = Date().addingTimeInterval(2)
        var dead = false
        while Date() < deadline {
            if Darwin.kill(sleep, 0) != 0 && !handle.groupAlive() {
                dead = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(dead)
    }

    func testIgnoredTermDiesAfterSigkill() throws {
        let spawner = DarwinProcessSpawner()
        let handle = try spawner.spawn(SpawnRequest(
            command: "trap '' TERM; echo READY; while true; do sleep 0.2; done",
            workingDirectory: "/tmp",
            environment: [:],
            shellPath: "/bin/zsh",
            shellArguments: ["-f", "-c"]
        ))
        defer {
            Darwin.kill(-handle.pid, SIGKILL)
            var status: Int32 = 0
            waitpid(handle.pid, &status, WNOHANG)
        }
        let box = TextBox()
        let ready = expectation(description: "ready")
        ready.assertForOverFulfill = false
        handle.readOutput { chunk in
            box.append(chunk)
            if box.text.contains("READY") { ready.fulfill() }
        }
        wait(for: [ready], timeout: 3)
        XCTAssertEqual(getpgid(handle.pid), handle.pid)
        handle.signalGroup(terminateGrace: 0.4)
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertTrue(handle.groupAlive())
        let deadline = Date().addingTimeInterval(1.5)
        var dead = false
        while Date() < deadline {
            if !handle.groupAlive() {
                dead = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(dead)
    }
}

final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func append(_ chunk: String) {
        lock.lock()
        storage += chunk
        lock.unlock()
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProcessGroupTests`
Expected: FAIL, `cannot find 'DarwinProcessSpawner' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/DarwinSpawner.swift`

```swift
import Darwin
import Foundation

struct SpawnRequest: Equatable, Sendable {
    var command: String
    var workingDirectory: String
    var environment: [String: String]
    var shellPath: String = "/bin/zsh"
    var shellArguments: [String] = ["-l", "-c"]
}

protocol SpawnedHandle: AnyObject, Sendable {
    var pid: Int32 { get }
    func readOutput(_ handler: @escaping @Sendable (String) -> Void)
    func onExit(_ handler: @escaping @Sendable (Int32) -> Void)
    func signalGroup(terminateGrace seconds: TimeInterval)
    func stopAndWait(grace: TimeInterval)
    func groupAlive() -> Bool
}

protocol ProcessSpawning: Sendable {
    func spawn(_ request: SpawnRequest) throws -> any SpawnedHandle
}

enum SpawnError: Error, Equatable, CustomStringConvertible {
    case pipe
    case setup(String)
    case spawn(Int32)

    var description: String {
        switch self {
        case .pipe:
            return "Pipe di log non disponibile."
        case .setup(let message):
            return "Preparazione del processo non riuscita: \(message)"
        case .spawn(let code):
            return "Avvio non riuscito (\(code))."
        }
    }
}

struct DarwinProcessSpawner: ProcessSpawning {
    func spawn(_ request: SpawnRequest) throws -> any SpawnedHandle {
        var fds = [Int32](repeating: 0, count: 2)
        guard pipe(&fds) == 0 else { throw SpawnError.pipe }
        let readFD = fds[0]
        let writeFD = fds[1]
        var actions: posix_spawn_file_actions_t?
        var attr: posix_spawnattr_t?
        var actionsReady = false
        var attrReady = false
        var transferred = false
        defer {
            if actionsReady { posix_spawn_file_actions_destroy(&actions) }
            if attrReady { posix_spawnattr_destroy(&attr) }
            if !transferred {
                close(readFD)
                close(writeFD)
            }
        }
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw SpawnError.setup("file actions") }
        actionsReady = true
        guard posix_spawnattr_init(&attr) == 0 else { throw SpawnError.setup("attributi") }
        attrReady = true
        guard posix_spawn_file_actions_adddup2(&actions, writeFD, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, writeFD, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&actions, readFD) == 0,
              posix_spawn_file_actions_addclose(&actions, writeFD) == 0 else {
            throw SpawnError.setup("redirect")
        }
        let chdirResult = request.workingDirectory.withCString { addChdir(&actions, $0) }
        guard chdirResult == 0 else { throw SpawnError.setup("cartella di lavoro") }
        guard posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attr, 0) == 0 else {
            throw SpawnError.setup("process group")
        }
        let argv = [request.shellPath] + request.shellArguments + [request.command]
        let env = mergedEnvironment(request.environment)
        var pid: pid_t = 0
        let code: Int32 = CStringBuffer.with(argv) { argvPtr in
            CStringBuffer.with(env) { envPtr in
                request.shellPath.withCString { path in
                    posix_spawn(&pid, path, &actions, &attr, argvPtr, envPtr)
                }
            }
        }
        guard code == 0 else { throw SpawnError.spawn(code) }
        _ = fcntl(readFD, F_SETFD, FD_CLOEXEC)
        close(writeFD)
        transferred = true
        let handle = DarwinProcessHandle(pid: pid, readFD: readFD)
        handle.start()
        return handle
    }

    private func mergedEnvironment(_ overlay: [String: String]) -> [String] {
        var dict = ProcessInfo.processInfo.environment
        for (key, value) in overlay where !key.isEmpty {
            dict[key] = value
        }
        return dict.map { "\($0.key)=\($0.value)" }
    }
}

private func addChdir(_ actions: UnsafeMutablePointer<posix_spawn_file_actions_t?>, _ path: UnsafePointer<CChar>) -> Int32 {
    if #available(macOS 26.0, *) {
        return posix_spawn_file_actions_addchdir(actions, path)
    } else {
        return posix_spawn_file_actions_addchdir_np(actions, path)
    }
}

private enum CStringBuffer {
    static func with<R>(_ values: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        let allocated: [UnsafeMutablePointer<CChar>?] = values.map { strdup($0) }
        defer { allocated.forEach { free($0) } }
        var pointers = allocated
        pointers.append(nil)
        return pointers.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!)
        }
    }
}

final class DarwinProcessHandle: SpawnedHandle, @unchecked Sendable {
    let pid: Int32
    private let lock = NSLock()
    private var outputHandler: (@Sendable (String) -> Void)?
    private var exitHandler: (@Sendable (Int32) -> Void)?
    private var buffered: [String] = []
    private var readFD: Int32
    private var source: DispatchSourceProcess?

    init(pid: Int32, readFD: Int32) {
        self.pid = pid
        self.readFD = readFD
    }

    func start() {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            let result = waitpid(self.pid, &status, WNOHANG)
            guard result == self.pid else { return }
            self.lock.lock()
            let handler = self.exitHandler
            self.lock.unlock()
            handler?(Self.exitCode(status))
        }
        self.source = source
        source.resume()
        let fd = readFD
        Thread.detachNewThread { [weak self] in
            self?.readLoop(fd: fd)
        }
    }

    func readOutput(_ handler: @escaping @Sendable (String) -> Void) {
        lock.lock()
        outputHandler = handler
        let pending = buffered
        buffered.removeAll()
        lock.unlock()
        pending.forEach(handler)
    }

    func onExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        exitHandler = handler
        lock.unlock()
    }

    func signalGroup(terminateGrace seconds: TimeInterval) {
        let group = pid
        _ = Darwin.kill(-group, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if Darwin.kill(-group, 0) == 0 {
                _ = Darwin.kill(-group, SIGKILL)
            }
        }
    }

    func stopAndWait(grace: TimeInterval) {
        _ = Darwin.kill(-pid, SIGTERM)
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline {
            if Darwin.kill(-pid, 0) != 0 { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if Darwin.kill(-pid, 0) == 0 {
            _ = Darwin.kill(-pid, SIGKILL)
        }
    }

    func groupAlive() -> Bool {
        Darwin.kill(-pid, 0) == 0
    }

    private func readLoop(fd: Int32) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            deliver(String(decoding: data, as: UTF8.self))
        }
        closeRead()
    }

    private func deliver(_ text: String) {
        lock.lock()
        let handler = outputHandler
        if handler == nil {
            buffered.append(text)
        }
        lock.unlock()
        handler?(text)
    }

    private func closeRead() {
        lock.lock()
        let fd = readFD
        readFD = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
    }

    deinit { closeRead() }

    private static func exitCode(_ status: Int32) -> Int32 {
        if status & 0x7f == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + (status & 0x7f)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProcessGroupTests`
Expected: PASS. Se `nice(5) failed: operation not permitted`, rilanciare il test fuori dalla sandbox.

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/DarwinSpawner.swift Tests/DevRunnerCoreTests/ProcessGroupTests.swift
git commit -m "$(cat <<'EOF'
feat: isola ogni runner in un process group

EOF
)"
```

---

### Task 10: Supervisore

**Files:**
- Create: `Sources/DevRunnerCore/Session.swift`
- Test: `Tests/DevRunnerCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes: `ConfigStore`, `PortTool`, `DebugEnv`, `TomcatPreparer`, `IdeaScanner`, `IdeaImporter`, `ProcessSpawning`, `SpawnedHandle`, `RingLog`, `LineBuffer`, `SpawnError`.
- Produces: `Session` con i metodi elencati nelle firme globali.

- [ ] **Step 1: Write the failing test**

```swift
import Darwin
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

    func testEmptyCommandDoesNotSpawn() {
        let project = add(command: "   ", port: nil)
        session.start(projectID: project.id, runnerID: project.runners[0].id)
        XCTAssertTrue(spawner.requests.isEmpty)
        XCTAssertEqual(session.runtime(for: project.runners[0].id).phase, .crashed)
        XCTAssertEqual(session.logs(for: project.runners[0].id).lines, ["Comando da completare."])
    }

    func testBusyPortDoesNotSpawnOrSignal() {
        signals.output = "42\n"
        let project = add(command: "echo hi", port: 8080)
        session.start(projectID: project.id, runnerID: project.runners[0].id)
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

    func testTomcatPrepareFailureDoesNotSpawn() {
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionTests`
Expected: FAIL, `cannot find 'Session' in scope`

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunnerCore/Session.swift`

```swift
import Darwin
import Foundation

@MainActor
final class Session {
    private var store: ConfigStore
    private let spawner: any ProcessSpawning
    private let ports: PortTool
    let terminationGrace: TimeInterval
    let configRoot: URL
    let userHome: URL
    private(set) var projects: [Project] = []
    private var runtimes: [UUID: RunnerRuntime] = [:]
    private var logsStorage: [UUID: RingLog] = [:]
    private var handles: [UUID: any SpawnedHandle] = [:]
    private var lineBuffers: [UUID: LineBuffer] = [:]
    private var intentionalStops: Set<UUID> = []
    private var restartAfterStop: Set<UUID> = []
    private var projectIDByRunner: [UUID: UUID] = [:]
    var onChange: (() -> Void)?
    private let sink = MainThreadSink()

    init(
        store: ConfigStore,
        spawner: any ProcessSpawning,
        ports: PortTool,
        terminationGrace: TimeInterval = 4,
        configRoot: URL? = nil,
        userHome: URL? = nil
    ) {
        self.store = store
        self.spawner = spawner
        self.ports = ports
        self.terminationGrace = terminationGrace
        self.configRoot = configRoot ?? store.fileURL.deletingLastPathComponent()
        self.userHome = userHome ?? FileManager.default.homeDirectoryForCurrentUser
        projects = self.store.load()
        indexRunners()
        sink.bind(self)
    }

    func logs(for runnerID: UUID) -> RingLog { logsStorage[runnerID] ?? RingLog() }
    func runtime(for runnerID: UUID) -> RunnerRuntime { runtimes[runnerID] ?? .stopped }
    func activeCount() -> Int { runtimes.values.filter { $0.phase == .running }.count }

    func locate(_ runnerID: UUID) -> (project: Project, runner: RunnerConfig)? {
        for project in projects {
            if let runner = project.runners.first(where: { $0.id == runnerID }) {
                return (project, runner)
            }
        }
        return nil
    }

    func addProject(_ project: Project) {
        projects.append(project)
        indexRunners()
        persist()
        changed()
    }

    func updateRunner(_ runner: RunnerConfig, commandDidChange: Bool) {
        guard let projectIndex = projects.firstIndex(where: { $0.runners.contains { $0.id == runner.id } }),
              let runnerIndex = projects[projectIndex].runners.firstIndex(where: { $0.id == runner.id }) else { return }
        var updated = runner
        if commandDidChange { updated.commandEdited = true }
        if !updated.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.importNote = nil
        }
        projects[projectIndex].runners[runnerIndex] = updated
        indexRunners()
        persist()
        changed()
    }

    func setDebugEnabled(_ enabled: Bool, runnerID: UUID) {
        guard let projectIndex = projects.firstIndex(where: { $0.runners.contains { $0.id == runnerID } }),
              let runnerIndex = projects[projectIndex].runners.firstIndex(where: { $0.id == runnerID }) else { return }
        projects[projectIndex].runners[runnerIndex].debugEnabled = enabled
        persist()
        changed()
    }

    func resync(projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let project = projects[index]
        let scanned = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: URL(fileURLWithPath: project.rootPath, isDirectory: true),
            configRoot: configRoot,
            userHome: userHome
        ))
        projects[index].runners = IdeaImporter.resync(existing: project.runners, imported: scanned.runners, configRoot: configRoot)
        indexRunners()
        persist()
        changed()
    }

    func start(projectID: UUID, runnerID: UUID) {
        guard let runner = runner(projectID: projectID, runnerID: runnerID) else { return }
        let phase = runtime(for: runnerID).phase
        if phase == .starting || phase == .running { return }
        if runner.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setRuntime(runnerID, RunnerRuntime(phase: .crashed, pid: nil))
            appendLog(runner.importNote ?? "Comando da completare.", runnerID: runnerID)
            return
        }
        if let port = runner.portToCheck, ports.isBusy(port) {
            appendLog("Porta \(port) occupata.", runnerID: runnerID)
            return
        }
        var command = runner.command
        if runner.idea?.adapter == .tomcat {
            switch TomcatPreparer.prepare(runner: runner) {
            case .failure(let error):
                setRuntime(runnerID, RunnerRuntime(phase: .crashed, pid: nil))
                appendLog(error.description, runnerID: runnerID)
                return
            case .success(let launch):
                command = launch.command
            }
        }
        let environment = DebugEnv.apply(runner: runner, env: runner.env)
        setRuntime(runnerID, RunnerRuntime(phase: .starting, pid: nil))
        do {
            let handle = try spawner.spawn(SpawnRequest(
                command: command,
                workingDirectory: runner.workingDirectory,
                environment: environment
            ))
            handles[runnerID] = handle
            lineBuffers[runnerID] = LineBuffer()
            let sink = self.sink
            handle.readOutput { chunk in sink.consume(chunk, runnerID: runnerID) }
            handle.onExit { code in sink.exited(code, runnerID: runnerID) }
            setRuntime(runnerID, RunnerRuntime(phase: .running, pid: handle.pid))
        } catch {
            handles[runnerID] = nil
            setRuntime(runnerID, RunnerRuntime(phase: .crashed, pid: nil))
            let message = (error as? SpawnError)?.description ?? error.localizedDescription
            appendLog(message, runnerID: runnerID)
        }
    }

    func stop(runnerID: UUID) {
        let phase = runtime(for: runnerID).phase
        guard phase == .starting || phase == .running else { return }
        guard let handle = handles[runnerID] else {
            setRuntime(runnerID, .stopped)
            return
        }
        intentionalStops.insert(runnerID)
        handle.signalGroup(terminateGrace: terminationGrace)
    }

    func restart(projectID: UUID, runnerID: UUID) {
        projectIDByRunner[runnerID] = projectID
        let phase = runtime(for: runnerID).phase
        if phase == .starting || phase == .running {
            restartAfterStop.insert(runnerID)
            stop(runnerID: runnerID)
        } else {
            start(projectID: projectID, runnerID: runnerID)
        }
    }

    func stopAll() {
        for project in projects {
            for runner in project.runners { stop(runnerID: runner.id) }
        }
    }

    func stopAllForTermination() {
        let current = Array(handles.values)
        let grace = terminationGrace
        let group = DispatchGroup()
        for handle in current {
            group.enter()
            DispatchQueue.global().async {
                handle.stopAndWait(grace: grace)
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + grace + 2)
    }

    func freePort(runnerID: UUID) {
        guard let runner = locate(runnerID)?.runner, let port = runner.portToCheck else { return }
        let pids = ports.free(port)
        if pids.isEmpty {
            appendLog("Nessun processo in ascolto sulla porta \(port).", runnerID: runnerID)
        } else {
            appendLog("Porta \(port) liberata.", runnerID: runnerID)
        }
    }

    func clearLog(runnerID: UUID) {
        logsStorage[runnerID] = RingLog()
        changed()
    }

    func configFileURLForOpen() throws -> URL {
        try store.prepareForOpen()
        return store.fileURL
    }

    func consumeOutput(_ chunk: String, runnerID: UUID) {
        var buffer = lineBuffers[runnerID] ?? LineBuffer()
        let lines = buffer.consume(chunk)
        lineBuffers[runnerID] = buffer
        guard !lines.isEmpty else { return }
        var log = logsStorage[runnerID] ?? RingLog()
        log.append(lines: lines)
        logsStorage[runnerID] = log
        changed()
    }

    func consumeExit(_ code: Int32, runnerID: UUID) {
        if var buffer = lineBuffers.removeValue(forKey: runnerID) {
            let tail = buffer.flush()
            if !tail.isEmpty {
                var log = logsStorage[runnerID] ?? RingLog()
                log.append(lines: tail)
                logsStorage[runnerID] = log
            }
        }
        handles[runnerID] = nil
        let intentional = intentionalStops.remove(runnerID) != nil
        if intentional || code == 0 {
            setRuntime(runnerID, .stopped)
        } else {
            setRuntime(runnerID, RunnerRuntime(phase: .crashed, pid: nil))
        }
        if restartAfterStop.remove(runnerID) != nil, let projectID = projectIDByRunner[runnerID] {
            start(projectID: projectID, runnerID: runnerID)
        }
    }

    private func runner(projectID: UUID, runnerID: UUID) -> RunnerConfig? {
        projects.first { $0.id == projectID }?.runners.first { $0.id == runnerID }
    }

    private func appendLog(_ line: String, runnerID: UUID) {
        var log = logsStorage[runnerID] ?? RingLog()
        log.append(lines: [line])
        logsStorage[runnerID] = log
        changed()
    }

    private func setRuntime(_ runnerID: UUID, _ runtime: RunnerRuntime) {
        runtimes[runnerID] = runtime
        changed()
    }

    private func indexRunners() {
        projectIDByRunner = [:]
        for project in projects {
            for runner in project.runners { projectIDByRunner[runner.id] = project.id }
        }
    }

    private func persist() { try? store.save(projects) }
    private func changed() { onChange?() }
}

final class MainThreadSink: @unchecked Sendable {
    weak var session: Session?
    func bind(_ session: Session) { self.session = session }

    func consume(_ chunk: String, runnerID: UUID) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.session?.consumeOutput(chunk, runnerID: runnerID)
            }
        }
    }

    func exited(_ code: Int32, runnerID: UUID) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.session?.consumeExit(code, runnerID: runnerID)
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/DevRunnerCore/Session.swift Tests/DevRunnerCoreTests/SessionTests.swift
git commit -m "$(cat <<'EOF'
feat: avvia, ferma e riavvia i runner dal supervisore

EOF
)"
```

---

### Task 11: Interfaccia menu bar

**Files:**
- Modify: `Package.swift`
- Create: `Sources/DevRunner/DevRunnerApp.swift`
- Create: `Sources/DevRunner/AppModel.swift`
- Create: `Sources/DevRunner/RootView.swift`

**Interfaces:**
- Consumes: `Session`, `IdeaScanner`, `IdeaScanRequest`, `Project`, `RunnerConfig`, `RunnerPhase`, `ConfigStore`, `DarwinProcessSpawner`, `PortTool`.
- Produces: eseguibile `DevRunner`.

- [ ] **Step 1: Write the failing build**

Sostituire `Package.swift` con:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevRunner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DevRunnerCore", targets: ["DevRunnerCore"]),
        .executable(name: "DevRunner", targets: ["DevRunner"])
    ],
    targets: [
        .target(name: "DevRunnerCore"),
        .executableTarget(name: "DevRunner", dependencies: ["DevRunnerCore"]),
        .testTarget(name: "DevRunnerCoreTests", dependencies: ["DevRunnerCore"])
    ]
)
```

- [ ] **Step 2: Run build to verify it fails**

Run: `swift build`
Expected: FAIL, l'eseguibile non ha sorgenti

- [ ] **Step 3: Write minimal implementation**

`Sources/DevRunner/DevRunnerApp.swift`

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.terminationTarget?.session.stopAllForTermination()
        }
    }
}

@main
struct DevRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                if model.activeCount > 0 {
                    Text("\(model.activeCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
```

`Sources/DevRunner/AppModel.swift`

```swift
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static weak var terminationTarget: AppModel?
    let session: Session
    @Published private(set) var revision = 0
    private var pending = false
    private var lastRefresh = Date.distantPast

    init(session: Session) {
        self.session = session
        Self.terminationTarget = self
        session.onChange = { [weak self] in
            Task { @MainActor in self?.schedule() }
        }
    }

    convenience init() {
        let store = ConfigStore(fileURL: ConfigStore.defaultFileURL)
        let session = Session(store: store, spawner: DarwinProcessSpawner(), ports: PortTool.live())
        self.init(session: session)
    }

    var projects: [Project] { _ = revision; return session.projects }
    var activeCount: Int { _ = revision; return session.activeCount() }

    func runtime(for runnerID: UUID) -> RunnerRuntime { _ = revision; return session.runtime(for: runnerID) }
    func logs(for runnerID: UUID) -> RingLog { _ = revision; return session.logs(for: runnerID) }
    func locate(_ runnerID: UUID) -> (project: Project, runner: RunnerConfig)? {
        _ = revision
        return session.locate(runnerID)
    }

    private func schedule() {
        let delta = Date().timeIntervalSince(lastRefresh)
        if delta >= 0.2 {
            lastRefresh = Date()
            revision += 1
            return
        }
        if pending { return }
        pending = true
        let wait = 0.2 - delta
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            self.pending = false
            self.lastRefresh = Date()
            self.revision += 1
        }
    }
}
```

`Sources/DevRunner/RootView.swift`

```swift
import AppKit
import SwiftUI

enum Theme {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let card = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let text = Color.white
    static let secondary = Color(white: 0.68)
    static let pill = Color(red: 0.22, green: 0.24, blue: 0.30)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var logsRunnerID: UUID?
    @State private var adding = false
    @State private var editing: RunnerConfig?

    var body: some View {
        Group {
            if let logsRunnerID, model.locate(logsRunnerID) != nil {
                LogsView(runnerID: logsRunnerID) { self.logsRunnerID = nil }
            } else {
                projectList
            }
        }
        .frame(width: 400)
        .frame(maxHeight: 640)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $adding) { AddProjectSheet(isPresented: $adding).environmentObject(model) }
        .sheet(item: $editing) { runner in EditRunnerSheet(runner: runner).environmentObject(model) }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                Text("Dev Runner").font(.headline)
                Spacer()
                Text("\(model.activeCount) attivo")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.pill, in: Capsule())
            }
            .foregroundStyle(Theme.text)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.projects.isEmpty {
                        Text("Nessun progetto").foregroundStyle(Theme.secondary)
                    }
                    ForEach(model.projects) { project in
                        ProjectBlock(project: project, onLogs: { logsRunnerID = $0 }, onEdit: { editing = $0 })
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                footer("+ Aggiungi Progetto") { adding = true }
                footer("Termina Tutti") { model.session.stopAll() }
                footer("Apri config.json") { openConfig() }
                footer("Esci") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .foregroundStyle(Theme.text)
    }

    private func footer(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openConfig() {
        guard let url = try? model.session.configFileURLForOpen() else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ProjectBlock: View {
    @EnvironmentObject private var model: AppModel
    var project: Project
    var onLogs: (UUID) -> Void
    var onEdit: (RunnerConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name).font(.headline)
            Text(project.rootPath).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Button("Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: project.rootPath)) }
                Button("Terminale") { openTerminal(project.rootPath) }
                Button("Sincronizza da .idea") { model.session.resync(projectID: project.id) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            ForEach(project.runners) { runner in
                RunnerRow(project: project, runner: runner, onLogs: { onLogs(runner.id) }, onEdit: { onEdit(runner) })
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func openTerminal(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        try? process.run()
    }
}

private struct RunnerRow: View {
    @EnvironmentObject private var model: AppModel
    var project: Project
    var runner: RunnerConfig
    var onLogs: () -> Void
    var onEdit: () -> Void

    var body: some View {
        let phase = model.runtime(for: runner.id).phase
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StatusDot(phase: phase)
                Text(runner.name).lineLimit(1)
                Spacer()
                if let pid = model.runtime(for: runner.id).pid, phase == .running || phase == .starting {
                    Text("pid \(pid)").font(.caption).foregroundStyle(Theme.secondary)
                }
                if let port = runner.portToCheck {
                    Text(":\(port)").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            if runner.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Comando da completare").font(.caption).foregroundStyle(Theme.secondary)
                if let note = runner.importNote {
                    Text(note).font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                Toggle("Debug", isOn: Binding(
                    get: { runner.debugEnabled },
                    set: { model.session.setDebugEnabled($0, runnerID: runner.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                if runner.debugInjection != .none {
                    Text(":\(runner.debugPort)").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                Button(phase == .running || phase == .starting ? "Stop" : "Start") {
                    if phase == .running || phase == .starting {
                        model.session.stop(runnerID: runner.id)
                    } else {
                        model.session.start(projectID: project.id, runnerID: runner.id)
                    }
                }
                Button("Restart") { model.session.restart(projectID: project.id, runnerID: runner.id) }
                Button("Logs") { onLogs() }
                Button("Edit") { onEdit() }
                if runner.portToCheck != nil {
                    Button("Libera porta") { model.session.freePort(runnerID: runner.id) }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}

private struct StatusDot: View {
    var phase: RunnerPhase
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
    private var color: Color {
        switch phase {
        case .stopped: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .crashed: return .red
        }
    }
}

private struct LogsView: View {
    @EnvironmentObject private var model: AppModel
    var runnerID: UUID
    var onBack: () -> Void
    @State private var query = ""

    var body: some View {
        let runner = model.locate(runnerID)?.runner
        let lines = model.logs(for: runnerID).filtered(query: query)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Indietro", action: onBack).buttonStyle(.borderless)
                Text(runner?.name ?? "").font(.headline)
                StatusDot(phase: model.runtime(for: runnerID).phase)
                if let port = runner?.portToCheck { Text(":\(port)").font(.caption) }
                Spacer()
            }
            HStack {
                TextField("Cerca", text: $query).textFieldStyle(.roundedBorder)
                Button("Clear") { model.session.clearLog(runnerID: runnerID) }
                Button("Copy") { copy(lines) }
            }
            .buttonStyle(.borderless)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                }
                .background(Color.black)
                .onAppear { scroll(proxy, lines: lines) }
                .onChange(of: lines.count) { _ in scroll(proxy, lines: lines) }
            }
        }
        .padding(12)
        .foregroundStyle(Theme.text)
    }

    private func scroll(_ proxy: ScrollViewProxy, lines: [String]) {
        if let last = lines.indices.last { proxy.scrollTo(last, anchor: .bottom) }
    }

    private func copy(_ lines: [String]) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

private struct AddProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var folder = ""
    @State private var found: [RunnerConfig] = []
    @State private var selected: Set<UUID> = []
    @State private var scanned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aggiungi Progetto").font(.headline)
            TextField("Nome", text: $name)
            HStack {
                TextField("Cartella", text: $folder)
                Button("Sfoglia") { browse() }
            }
            Text("Trovate in .idea").font(.subheadline)
            if scanned && found.isEmpty {
                Text("Nessuna configurazione in .idea").foregroundStyle(Theme.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(found) { runner in
                        Toggle(isOn: binding(runner.id)) {
                            VStack(alignment: .leading) {
                                Text(runner.name)
                                if runner.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Comando da completare").font(.caption)
                                    if let note = runner.importNote { Text(note).font(.caption2) }
                                } else {
                                    Text(runner.command).font(.caption.monospaced()).lineLimit(1)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            HStack {
                Button("Annulla") { isPresented = false }
                Spacer()
                Button("Runner manuale") { createManual() }.disabled(folder.isEmpty)
                Button("Importa selezionate") { importSelected() }
                    .disabled(folder.isEmpty || found.filter { selected.contains($0.id) }.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420, height: 460)
        .preferredColorScheme(.dark)
        .onChange(of: folder) { _ in scanIfDirectory() }
    }

    private func binding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { isOn in
            if isOn { selected.insert(id) } else { selected.remove(id) }
        })
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Scegli"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }

    private func scanIfDirectory() {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
            found = []
            selected = []
            scanned = false
            return
        }
        let result = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: URL(fileURLWithPath: folder, isDirectory: true),
            configRoot: model.session.configRoot,
            userHome: model.session.userHome
        ))
        found = result.runners
        selected = Set(found.map(\.id))
        scanned = true
    }

    private func resolvedName() -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return URL(fileURLWithPath: folder).lastPathComponent
    }

    private func importSelected() {
        let chosen = found.filter { selected.contains($0.id) }
        model.session.addProject(Project(name: resolvedName(), rootPath: folder, runners: chosen))
        isPresented = false
    }

    private func createManual() {
        let title = resolvedName()
        let runner = RunnerConfig(name: title, command: "", workingDirectory: folder, debugPort: 5005)
        model.session.addProject(Project(name: title, rootPath: folder, runners: [runner]))
        isPresented = false
    }
}

private struct EditRunnerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: RunnerConfig
    @State private var name: String
    @State private var command: String
    @State private var workingDirectory: String
    @State private var portText: String
    @State private var debugPortText: String
    @State private var debugEnabled: Bool
    @State private var envRows: [EnvRow]

    init(runner: RunnerConfig) {
        original = runner
        _name = State(initialValue: runner.name)
        _command = State(initialValue: runner.command)
        _workingDirectory = State(initialValue: runner.workingDirectory)
        _portText = State(initialValue: runner.portToCheck.map(String.init) ?? "")
        _debugPortText = State(initialValue: String(runner.debugPort))
        _debugEnabled = State(initialValue: runner.debugEnabled)
        _envRows = State(initialValue: runner.env.keys.sorted().map { EnvRow(key: $0, value: runner.env[$0] ?? "") })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modifica runner").font(.headline)
            TextField("Nome", text: $name)
            Text("Comando").font(.caption)
            TextEditor(text: $command).font(.system(.body, design: .monospaced)).frame(minHeight: 80)
            TextField("Cartella di lavoro", text: $workingDirectory)
            TextField("Porta da controllare", text: $portText)
            TextField("Porta debug", text: $debugPortText)
            Toggle("Debug", isOn: $debugEnabled)
            Text("Variabili").font(.caption)
            ForEach($envRows) { $row in
                HStack {
                    TextField("Nome", text: $row.key)
                    TextField("Valore", text: $row.value)
                    Button("Rimuovi") { envRows.removeAll { $0.id == row.id } }
                }
            }
            Button("Aggiungi") { envRows.append(EnvRow(key: "", value: "")) }
            HStack {
                Button("Annulla") { dismiss() }
                Spacer()
                Button("Salva") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
        .preferredColorScheme(.dark)
    }

    private func save() {
        var updated = original
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.command = command
        updated.workingDirectory = workingDirectory
        let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPort.isEmpty {
            updated.portToCheck = nil
        } else if let port = Int(trimmedPort) {
            updated.portToCheck = port
        }
        let trimmedDebug = debugPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let port = Int(trimmedDebug) { updated.debugPort = port }
        updated.debugEnabled = debugEnabled
        var env: [String: String] = [:]
        for row in envRows {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { env[key] = row.value }
        }
        updated.env = env
        model.session.updateRunner(updated, commandDidChange: command != original.command)
        dismiss()
    }
}

private struct EnvRow: Identifiable, Equatable {
    var id = UUID()
    var key: String
    var value: String
}
```

- [ ] **Step 4: Run build to verify it passes**

Run: `swift build`
Expected: PASS, nessun errore. Correggere gli eventuali warning di concorrenza introdotti qui.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/DevRunner
git commit -m "$(cat <<'EOF'
feat: aggiunge la finestra menu bar di Dev Runner

EOF
)"
```

---

### Task 12: Bundle e verifica finale

**Files:**
- Create: `Scripts/package-app.sh`

**Interfaces:**
- Consumes: l'eseguibile `DevRunner` prodotto da `swift build -c release`.
- Produces: `dist/DevRunner.app` con `LSUIElement` vero. Nessuna firma.

- [ ] **Step 1: Write the script**

`Scripts/package-app.sh`

```bash
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/DevRunner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/DevRunner" "$APP/Contents/MacOS/DevRunner"
chmod +x "$APP/Contents/MacOS/DevRunner"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>it</string>
  <key>CFBundleExecutable</key>
  <string>DevRunner</string>
  <key>CFBundleIdentifier</key>
  <string>it.icsone.dev-runner</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Dev Runner</string>
  <key>CFBundleDisplayName</key>
  <string>Dev Runner</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
echo "Created $APP"
```

- [ ] **Step 2: Make it executable and check syntax**

```bash
chmod +x Scripts/package-app.sh
zsh -n Scripts/package-app.sh
```

Expected: nessun output, exit 0

- [ ] **Step 3: Run the whole suite and the release bundle**

```bash
swift test
swift build
Scripts/package-app.sh
```

Expected: `swift test` con tutti i test passati, `swift build` senza errori, `dist/DevRunner.app/Contents/Info.plist` contiene `<key>LSUIElement</key>` seguito da `<true/>`.

- [ ] **Step 4: Commit**

```bash
git add Scripts/package-app.sh
git commit -m "$(cat <<'EOF'
feat: impacchetta Dev Runner come app senza icona nel Dock

EOF
)"
```
