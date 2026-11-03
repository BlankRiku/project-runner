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
        let store = ConfigStore(fileURL: url)
        try store.prepareForOpen()
        let created = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(created, "{\"projects\":[]}")
        try TestSupport.write("{", to: url)
        try store.prepareForOpen()
        let untouched = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(untouched, "{")
    }
}
