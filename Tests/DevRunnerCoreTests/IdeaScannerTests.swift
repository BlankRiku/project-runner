import XCTest
@testable import DevRunnerCore

final class IdeaScannerTests: XCTestCase {
    private var paths: TestPaths!
    private var catalinaHome: String { paths.catalinaHome }
    private var jdkHome: String { paths.javaHome }
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

    func testEphemeralRunnerSettingsPortIsNotJdwp() throws {
        let project = try writeTomcatWorkspace(extra: """
              <option name="HTTP_PORT" value="8080" />
              <RunnerSettings RunnerId="Debug">
                <option name="DEBUG_PORT" value="53894" />
              </RunnerSettings>
        """)
        let tomcat = try scanTomcat(project)
        XCTAssertEqual(tomcat.debugPort, 5005)
        XCTAssertEqual(tomcat.portToCheck, 8080)
    }

    func testJdwpAddressOverridesEphemeralDebugPort() throws {
        let project = try writeTomcatWorkspace(extra: """
              <option name="VM_PARAMETERS" value="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5010" />
              <RunnerSettings RunnerId="Debug">
                <option name="DEBUG_PORT" value="53894" />
              </RunnerSettings>
        """)
        let tomcat = try scanTomcat(project)
        XCTAssertEqual(tomcat.debugPort, 5010)
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

    func testSpringBootWithoutGoalsUsesMavenWrapperAndProjectJdk() throws {
        let project = root.appendingPathComponent("todo")
        let home = root.appendingPathComponent("home")
        let jdk = home.appendingPathComponent("Library/Java/JavaVirtualMachines/corretto-25.0.2/Contents/Home").path
        try TestSupport.write("<project/>", to: project.appendingPathComponent("pom.xml"))
        try TestSupport.write("", to: project.appendingPathComponent("mvnw"))
        try TestSupport.write("""
        <project version="4">
          <component name="ProjectRootManager" project-jdk-name="corretto-25 (2)" project-jdk-type="JavaSDK" />
        </project>
        """, to: project.appendingPathComponent(".idea/misc.xml"))
        try TestSupport.write("""
        <application><component name="ProjectJdkTable"><jdk version="2">
          <name value="corretto-25 (2)" />
          <homePath value="$USER_HOME$/Library/Java/JavaVirtualMachines/corretto-25.0.2/Contents/Home" />
        </jdk></component></application>
        """, to: root.appendingPathComponent("jdk.table.xml"))
        try TestSupport.write("""
        <project version="4">
          <component name="MavenImportPreferences">
            <option name="generalSettings">
              <MavenGeneralSettings>
                <option name="mavenHomeTypeForPersistence" value="WRAPPER" />
              </MavenGeneralSettings>
            </option>
          </component>
          <component name="RunManager">
            <configuration name="TodoApplication" type="SpringBootApplicationConfigurationType" factoryName="Spring Boot">
              <option name="SPRING_BOOT_MAIN_CLASS" value="it.dev.todo.TodoApplication" />
            </configuration>
          </component>
        </project>
        """, to: project.appendingPathComponent(".idea/workspace.xml"))

        let result = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: project,
            configRoot: root.appendingPathComponent("config"),
            userHome: home,
            applicationServersFiles: [],
            jdkTableFiles: [root.appendingPathComponent("jdk.table.xml")]
        ))
        let app = try XCTUnwrap(result.runners.first { $0.name == "TodoApplication" })
        XCTAssertEqual(app.command, "./mvnw '-Dspring-boot.run.mainClass=it.dev.todo.TodoApplication' spring-boot:run")
        XCTAssertEqual(app.env["JAVA_HOME"], jdk)
        XCTAssertEqual(app.workingDirectory, project.path)
        XCTAssertEqual(app.idea?.adapter, .maven)
        XCTAssertEqual(app.idea?.configurationType, "SpringBootApplicationConfigurationType")
        XCTAssertEqual(app.debugInjection, .javaToolOptions)
        XCTAssertNil(app.importNote)
    }

    func testMavenHomeFollowsIntelliJSetting() throws {
        let wrapperProject = root.appendingPathComponent("wrapper-only")
        try TestSupport.write("<project/>", to: wrapperProject.appendingPathComponent("pom.xml"))
        try TestSupport.write("""
        <project version="4">
          <component name="MavenImportPreferences">
            <option name="generalSettings">
              <MavenGeneralSettings>
                <option name="mavenHomeTypeForPersistence" value="WRAPPER" />
              </MavenGeneralSettings>
            </option>
          </component>
          <component name="RunManager">
            <configuration name="TodoApplication" type="SpringBootApplicationConfigurationType" factoryName="Spring Boot">
              <option name="SPRING_BOOT_MAIN_CLASS" value="it.dev.todo.TodoApplication" />
            </configuration>
          </component>
        </project>
        """, to: wrapperProject.appendingPathComponent(".idea/workspace.xml"))

        let customProject = root.appendingPathComponent("custom-maven")
        let mavenHome = root.appendingPathComponent("apache-maven")
        try TestSupport.write("", to: mavenHome.appendingPathComponent("bin/mvn"))
        try TestSupport.write("<project/>", to: customProject.appendingPathComponent("pom.xml"))
        try TestSupport.write("", to: customProject.appendingPathComponent("mvnw"))
        try TestSupport.write("""
        <project version="4">
          <component name="MavenImportPreferences">
            <option name="generalSettings">
              <MavenGeneralSettings>
                <option name="mavenHomeTypeForPersistence" value="CUSTOM" />
                <option name="mavenHome" value="\(mavenHome.path)" />
              </MavenGeneralSettings>
            </option>
          </component>
          <component name="RunManager">
            <configuration name="boot" type="MavenRunConfiguration" factoryName="Maven">
              <option name="goals"><list><option value="spring-boot:run" /></list></option>
            </configuration>
          </component>
        </project>
        """, to: customProject.appendingPathComponent(".idea/workspace.xml"))

        let wrapper = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: wrapperProject,
            configRoot: root.appendingPathComponent("config"),
            userHome: root,
            applicationServersFiles: [],
            jdkTableFiles: []
        ))
        let missingWrapper = try XCTUnwrap(wrapper.runners.first { $0.name == "TodoApplication" })
        XCTAssertEqual(missingWrapper.command, "")
        XCTAssertEqual(missingWrapper.importNote, "Maven wrapper impostato in IntelliJ, ma mvnw non c'è nella radice del progetto.")

        let custom = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: customProject,
            configRoot: root.appendingPathComponent("config"),
            userHome: root,
            applicationServersFiles: [],
            jdkTableFiles: []
        ))
        let boot = try XCTUnwrap(custom.runners.first { $0.name == "boot" })
        XCTAssertEqual(boot.command, "\(mavenHome.appendingPathComponent("bin/mvn").path) spring-boot:run")
        XCTAssertNil(boot.importNote)
    }

    func testDotRunImportsFlaskGunicornAndVSCodeLaunch() throws {
        let project = root.appendingPathComponent("import-service")
        let home = root.appendingPathComponent("home")
        let python = home.appendingPathComponent("venv/bin/python").path
        try TestSupport.write("""
        # commento
        export LOG_LEVEL=DEBUG
        SERVICE_PORT=5002
        QUOTED="a b"
        FLASK_RUN_PORT=1111
        """, to: project.appendingPathComponent(".env"))
        try TestSupport.write("""
        SERVICE_PORT=5002
        """, to: project.appendingPathComponent(".env.gunicorn"))
        try TestSupport.write("""
        <application><component name="ProjectJdkTable"><jdk version="2">
          <name value="Python 3.12 (import-service)" />
          <homePath value="$USER_HOME$/venv/bin/python" />
        </jdk></component></application>
        """, to: root.appendingPathComponent("jdk.table.xml"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration default="false" name="import-service-dev" type="Python.FlaskServer">
            <option name="target" value="$PROJECT_DIR$/app.py" />
            <option name="targetType" value="PATH" />
            <option name="ENV_FILES" value="$PROJECT_DIR$/.env" />
            <envs>
              <env name="FLASK_RUN_PORT" value="5002" />
            </envs>
            <option name="SDK_HOME" value="" />
            <option name="SDK_NAME" value="Python 3.12 (import-service)" />
            <option name="WORKING_DIRECTORY" value="$PROJECT_DIR$" />
            <method v="2">
              <option name="RunConfigurationTask" enabled="true" run_configuration_name="aggiorna dipendenze" run_configuration_type="ShConfigurationType" />
            </method>
          </configuration>
        </component>
        """, to: project.appendingPathComponent(".run/import-service-dev.run.xml"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration default="false" name="import-service-prod" type="PythonConfigurationType" factoryName="Python">
            <option name="ENV_FILES" value="$PROJECT_DIR$/.env.gunicorn" />
            <option name="SDK_HOME" value="" />
            <option name="SDK_NAME" value="Python 3.12 (import-service)" />
            <option name="WORKING_DIRECTORY" value="$PROJECT_DIR$" />
            <option name="SCRIPT_NAME" value="gunicorn" />
            <option name="PARAMETERS" value="-c gunicorn_config.py wsgi:app" />
            <option name="MODULE_MODE" value="true" />
            <envs>
              <env name="PYTHONUNBUFFERED" value="1" />
            </envs>
          </configuration>
        </component>
        """, to: project.appendingPathComponent(".run/import-service-prod.run.xml"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration default="false" name="aggiorna dipendenze" type="ShConfigurationType">
            <option name="SCRIPT_TEXT" value="pip-sync requirements.txt" />
            <option name="INTERPRETER_PATH" value="/bin/zsh" />
            <option name="SCRIPT_WORKING_DIRECTORY" value="$PROJECT_DIR$" />
          </configuration>
        </component>
        """, to: project.appendingPathComponent(".run/aggiorna dipendenze.run.xml"))
        try TestSupport.write("""
        {"configurations":[{"name":"import-service-flask-debug","module":"flask"}]}
        """, to: project.appendingPathComponent(".vscode/launch.json"))
        try TestSupport.write("bind = \"127.0.0.1:5002\"\n", to: project.appendingPathComponent("gunicorn_config.py"))

        let result = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: project,
            configRoot: root.appendingPathComponent("config"),
            userHome: home,
            applicationServersFiles: [],
            jdkTableFiles: [root.appendingPathComponent("jdk.table.xml")]
        ))

        XCTAssertEqual(result.runners.map(\.name).sorted(), [
            "aggiorna dipendenze", "import-service-dev", "import-service-flask-debug", "import-service-prod"
        ])
        let vscode = try XCTUnwrap(result.runners.first { $0.name == "import-service-flask-debug" })
        XCTAssertEqual(vscode.idea?.adapter, .vscode)
        XCTAssertEqual(vscode.idea?.configurationType, "vscode.launch")
        XCTAssertEqual(vscode.command, "python3 -m flask")
        XCTAssertEqual(vscode.workingDirectory, project.path)
        XCTAssertNil(vscode.importNote)
        let flask = try XCTUnwrap(result.runners.first { $0.name == "import-service-dev" })
        XCTAssertEqual(flask.command, "\(python) -m flask run")
        XCTAssertEqual(flask.env["FLASK_APP"], project.appendingPathComponent("app.py").path)
        XCTAssertEqual(flask.env["LOG_LEVEL"], "DEBUG")
        XCTAssertEqual(flask.env["QUOTED"], "a b")
        XCTAssertEqual(flask.env["SERVICE_PORT"], "5002")
        XCTAssertEqual(flask.env["FLASK_RUN_PORT"], "5002")
        XCTAssertEqual(flask.portToCheck, 5002)
        XCTAssertEqual(flask.workingDirectory, project.path)
        XCTAssertEqual(flask.idea?.adapter, .python)
        XCTAssertEqual(flask.idea?.configurationType, "Python.FlaskServer")
        XCTAssertNil(flask.importNote)

        let gunicorn = try XCTUnwrap(result.runners.first { $0.name == "import-service-prod" })
        XCTAssertEqual(gunicorn.command, "\(python) -m gunicorn -c gunicorn_config.py wsgi:app")
        XCTAssertEqual(gunicorn.env["SERVICE_PORT"], "5002")
        XCTAssertEqual(gunicorn.env["PYTHONUNBUFFERED"], "1")
        XCTAssertNil(gunicorn.portToCheck)
        XCTAssertEqual(gunicorn.idea?.configurationType, "PythonConfigurationType")
        XCTAssertNil(gunicorn.importNote)

        let shell = try XCTUnwrap(result.runners.first { $0.name == "aggiorna dipendenze" })
        XCTAssertEqual(shell.command, "")
        XCTAssertEqual(shell.idea?.adapter, .unmapped)
        XCTAssertEqual(shell.importNote, "Tipo di configurazione non mappato.")
    }

    func testFlaskDefaultPortAndUnresolvedInterpreter() throws {
        let project = root.appendingPathComponent("service")
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration name="flask-dev" type="Python.FlaskServer">
            <option name="target" value="$PROJECT_DIR$/app.py" />
            <option name="SDK_HOME" value="/usr/bin/python3" />
            <option name="WORKING_DIRECTORY" value="$PROJECT_DIR$" />
          </configuration>
        </component>
        """, to: project.appendingPathComponent(".idea/runConfigurations/flask.xml"))
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration name="flask-missing" type="Python.FlaskServer">
            <option name="target" value="$PROJECT_DIR$/app.py" />
            <option name="SDK_HOME" value="" />
            <option name="SDK_NAME" value="Python assente" />
            <option name="WORKING_DIRECTORY" value="$PROJECT_DIR$" />
          </configuration>
        </component>
        """, to: project.appendingPathComponent(".run/flask-missing.run.xml"))

        let result = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: project,
            configRoot: root.appendingPathComponent("config"),
            userHome: root,
            applicationServersFiles: [],
            jdkTableFiles: []
        ))
        let flask = try XCTUnwrap(result.runners.first { $0.name == "flask-dev" })
        XCTAssertEqual(flask.command, "/usr/bin/python3 -m flask run")
        XCTAssertEqual(flask.portToCheck, 5000)
        XCTAssertNil(flask.env["FLASK_RUN_PORT"])
        XCTAssertEqual(flask.env["FLASK_APP"], project.appendingPathComponent("app.py").path)

        let missing = try XCTUnwrap(result.runners.first { $0.name == "flask-missing" })
        XCTAssertEqual(missing.command, "")
        XCTAssertEqual(missing.importNote, "Interprete «Python assente» non trovato in jdk.table.xml.")
        XCTAssertEqual(missing.portToCheck, 5000)
        XCTAssertEqual(missing.env["FLASK_APP"], project.appendingPathComponent("app.py").path)
    }

    private struct Layout {
        var root: URL
        var config: URL
        var servers: URL
        var jdks: URL
    }

    private func writeTomcatWorkspace(extra: String) throws -> URL {
        let project = root.appendingPathComponent("tomcat-project-\(UUID().uuidString)")
        try TestSupport.write("""
        <project version="4">
          <component name="RunManager">
            <configuration name="Tomcat 9.0.41" type="#com.intellij.j2ee.web.tomcat.TomcatRunConfigurationFactory" factoryName="Local" APPLICATION_SERVER_NAME="Tomcat 9.0.41">
        \(extra)
            </configuration>
          </component>
        </project>
        """, to: project.appendingPathComponent(".idea/workspace.xml"))
        return project
    }

    private func scanTomcat(_ project: URL) throws -> RunnerConfig {
        let result = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: project,
            configRoot: root.appendingPathComponent("config-root"),
            userHome: root,
            applicationServersFiles: [],
            jdkTableFiles: []
        ))
        return try XCTUnwrap(result.runners.first { $0.name == "Tomcat 9.0.41" })
    }

    private func request(_ layout: Layout, servers: [URL], jdks: [URL]) -> IdeaScanRequest {
        IdeaScanRequest(
            projectRoot: layout.root,
            configRoot: layout.config,
            userHome: paths.home,
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
