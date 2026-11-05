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

    func testSameNameInTwoRootsStaysTwoRunners() {
        let front = IdeaOrigin(configurationName: "start", configurationType: "js.build_tools.npm", adapter: .npm, sourceRoot: "/fe")
        let back = IdeaOrigin(configurationName: "start", configurationType: "js.build_tools.npm", adapter: .npm, sourceRoot: "/be")
        let existing = [
            RunnerConfig(name: "start", command: "npm run start", workingDirectory: "/fe", idea: front),
            RunnerConfig(name: "start", command: "npm run start", workingDirectory: "/be", idea: back)
        ]
        let imported = [
            RunnerConfig(name: "start", command: "npm run start", workingDirectory: "/fe", idea: front),
            RunnerConfig(name: "start", command: "npm run start", workingDirectory: "/be", idea: back)
        ]
        let result = IdeaImporter.resync(
            existing: existing,
            imported: imported,
            configRoot: URL(fileURLWithPath: "/tmp/cfg"),
            primaryRoot: "/fe"
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map { $0.idea?.sourceRoot }, ["/fe", "/be"])
    }

    func testApplySelectionDropsDeselectedAndKeepsManual() {
        let front = IdeaOrigin(configurationName: "start", configurationType: "js.build_tools.npm", adapter: .npm, sourceRoot: "/fe")
        let back = IdeaOrigin(configurationName: "api", configurationType: "js.build_tools.npm", adapter: .npm, sourceRoot: "/be")
        let keepID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let dropID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let existing = [
            RunnerConfig(id: keepID, name: "start", command: "npm run start", workingDirectory: "/fe", idea: front),
            RunnerConfig(id: dropID, name: "api", command: "npm run api", workingDirectory: "/be", idea: back),
            RunnerConfig(name: "manual", command: "echo hi", workingDirectory: "/fe")
        ]
        let selected = [
            RunnerConfig(name: "start", command: "npm run start", workingDirectory: "/fe", idea: front),
            RunnerConfig(
                name: "lint",
                command: "npm run lint",
                workingDirectory: "/fe",
                idea: IdeaOrigin(configurationName: "lint", configurationType: "js.build_tools.npm", adapter: .npm, sourceRoot: "/fe")
            )
        ]
        let result = IdeaImporter.applySelection(
            existing: existing,
            selected: selected,
            configRoot: URL(fileURLWithPath: "/tmp/cfg"),
            primaryRoot: "/fe"
        )
        XCTAssertEqual(result.map(\.name), ["manual", "start", "lint"])
        XCTAssertEqual(result[1].id, keepID)
        XCTAssertFalse(result.contains { $0.id == dropID })
    }

    func testNilSourceRootMatchesOnlyPrimaryRoot() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let legacy = IdeaOrigin(configurationName: "start", configurationType: "js.build_tools.npm", adapter: .npm)
        let existing = RunnerConfig(id: id, name: "start", command: "npm run old", workingDirectory: "/fe", idea: legacy)
        let front = RunnerConfig(
            name: "start",
            command: "npm run front",
            workingDirectory: "/fe",
            idea: IdeaOrigin(configurationName: "start", configurationType: "js.build_tools.npm", adapter: .npm, sourceRoot: "/fe")
        )
        let back = RunnerConfig(
            name: "start",
            command: "npm run back",
            workingDirectory: "/be",
            idea: IdeaOrigin(configurationName: "start", configurationType: "js.build_tools.npm", adapter: .npm, sourceRoot: "/be")
        )
        let result = IdeaImporter.resync(
            existing: [existing],
            imported: [front, back],
            configRoot: URL(fileURLWithPath: "/tmp/cfg"),
            primaryRoot: "/fe"
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, id)
        XCTAssertEqual(result[0].command, "npm run front")
        XCTAssertEqual(result[0].idea?.sourceRoot, "/fe")
        XCTAssertEqual(result[1].idea?.sourceRoot, "/be")
        XCTAssertEqual(result[1].command, "npm run back")
    }
}
