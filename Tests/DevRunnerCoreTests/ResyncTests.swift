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
