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

    func testProjectWithoutRootsUsesRootPath() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000010","name":"todo","rootPath":"/Users/me/todo","runners":[]}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        XCTAssertEqual(project.rootPath, "/Users/me/todo")
        XCTAssertEqual(project.roots, ["/Users/me/todo"])
    }

    func testProjectEncodesRootsAndKeepsRootPathAsFirst() throws {
        let project = Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            name: "todo",
            rootPath: "/Users/me/todo",
            roots: ["/Users/me/todo", "/Users/me/todo-be"]
        )
        let data = try JSONEncoder().encode(project)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["rootPath"] as? String, "/Users/me/todo")
        XCTAssertEqual(object?["roots"] as? [String], ["/Users/me/todo", "/Users/me/todo-be"])
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded.roots, ["/Users/me/todo", "/Users/me/todo-be"])
        XCTAssertEqual(decoded.rootPath, "/Users/me/todo")
    }

    func testIdeaOriginMissingSourceRootIsNil() throws {
        let json = """
        {"configurationName":"dev","configurationType":"js.build_tools.npm","adapter":"npm"}
        """
        let origin = try JSONDecoder().decode(IdeaOrigin.self, from: Data(json.utf8))
        XCTAssertNil(origin.sourceRoot)
    }

    func testNormalizePathStripsTrailingSlash() {
        XCTAssertEqual(Project.normalizePath("/tmp/work/"), "/tmp/work")
        XCTAssertEqual(Project.normalizePath("/"), "/")
    }
}
