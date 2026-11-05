import XCTest
@testable import DevRunnerCore

final class ConfigStoreTests: XCTestCase {
    private var paths: TestPaths!
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        paths = try TestPaths.load()
        root = try TestSupport.makeDirectory()
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

    func testCePostoShapedDocumentIsNotDropped() throws {
        let url = root.appendingPathComponent("config.json")
        let rootPath = paths.home.appendingPathComponent("sample/ceposto-java-server").path
        try TestSupport.write(cePostoJSON(paths: paths, rootPath: rootPath), to: url)
        var store = ConfigStore(fileURL: url)
        let projects = store.load()
        XCTAssertFalse(store.isCorrupt)
        XCTAssertEqual(projects.map(\.name), ["ceposto"])
        XCTAssertEqual(projects.first?.rootPath, rootPath)
        let runner = try XCTUnwrap(projects.first?.runners.first)
        XCTAssertEqual(runner.id, UUID(uuidString: "2AE60F9B-518D-405A-BEBD-95FB5397B83D"))
        XCTAssertEqual(runner.name, "Tomcat 9.0.41")
        XCTAssertEqual(runner.portToCheck, 8080)
        XCTAssertEqual(runner.workingDirectory, rootPath)
        XCTAssertEqual(runner.command, "exec \"$CATALINA_HOME\"/bin/catalina.sh run")
        XCTAssertEqual(runner.env["CATALINA_HOME"], paths.catalinaHome)
        XCTAssertEqual(runner.env["JAVA_HOME"], paths.javaHome)
        XCTAssertEqual(runner.idea?.adapter, .tomcat)
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

private func cePostoJSON(paths: TestPaths, rootPath: String) -> String {
    let catalinaBase = paths.home.appendingPathComponent(".config/dev-runner/catalina/2AE60F9B-518D-405A-BEBD-95FB5397B83D").path
    let docBase = URL(fileURLWithPath: rootPath).appendingPathComponent("target/ceposto-java-server").path
    return """
    {
      "projects" : [
        {
          "id" : "9DE1B3A5-0396-415E-897D-22C13664E2B8",
          "name" : "ceposto",
          "rootPath" : "\(rootPath)",
          "runners" : [
            {
              "command" : "exec \\"$CATALINA_HOME\\"/bin/catalina.sh run",
              "commandEdited" : false,
              "debugEnabled" : false,
              "debugInjection" : "catalinaOpts",
              "debugPort" : 53894,
              "env" : {
                "CATALINA_BASE" : "\(catalinaBase)",
                "CATALINA_HOME" : "\(paths.catalinaHome)",
                "JAVA_HOME" : "\(paths.javaHome)"
              },
              "id" : "2AE60F9B-518D-405A-BEBD-95FB5397B83D",
              "idea" : {
                "adapter" : "tomcat",
                "configurationName" : "Tomcat 9.0.41",
                "configurationType" : "#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory"
              },
              "name" : "Tomcat 9.0.41",
              "portToCheck" : 8080,
              "tomcatContextPath" : "/CePosto",
              "tomcatDocBase" : "\(docBase)",
              "workingDirectory" : "\(rootPath)"
            }
          ]
        }
      ]
    }
    """
}
