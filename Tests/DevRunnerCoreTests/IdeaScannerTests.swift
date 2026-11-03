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
