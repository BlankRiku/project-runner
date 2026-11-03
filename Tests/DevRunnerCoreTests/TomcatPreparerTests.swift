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
