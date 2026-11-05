import XCTest
@testable import DevRunnerCore

final class VSCodeScannerTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = try! TestSupport.makeDirectory()
    }

    override func tearDown() {
        TestSupport.remove(root)
        super.tearDown()
    }

    func testMissingVSCodeFilesAddNoRunners() {
        let result = scan()
        XCTAssertTrue(result.runners.isEmpty)
        XCTAssertTrue(result.skippedFiles.isEmpty)
    }

    func testLaunchAndTaskShareTheSameRunnerList() throws {
        try writeLaunch("""
        {
          "version": "0.2.0",
          "configurations": [
            {
              "name": "api",
              "type": "node",
              "request": "launch",
              "program": "${workspaceFolder}/src/index.js",
              "args": ["--port", "3000"],
              "cwd": "${workspaceFolder}",
              "env": { "PORT": "3000", "URL": "http://example.com" }
            }
          ]
        }
        """)
        try writeTasks("""
        {
          "version": "2.0.0",
          "tasks": [
            {
              "label": "build",
              "type": "shell",
              "command": "npm run build",
              "options": {
                "cwd": "${workspaceFolder}/server",
                "env": { "NODE_ENV": "production" }
              }
            }
          ]
        }
        """)

        let result = scan()
        XCTAssertEqual(result.skippedFiles, [])
        XCTAssertEqual(result.runners.map(\.name), ["api", "build"])

        let api = try XCTUnwrap(result.runners.first)
        XCTAssertEqual(api.idea?.adapter, .vscode)
        XCTAssertEqual(api.idea?.configurationName, "api")
        XCTAssertEqual(api.idea?.configurationType, "vscode.launch.node")
        XCTAssertEqual(api.command, "node \(root.path)/src/index.js --port 3000")
        XCTAssertEqual(api.workingDirectory, root.path)
        XCTAssertEqual(api.env["PORT"], "3000")
        XCTAssertEqual(api.env["URL"], "http://example.com")
        XCTAssertEqual(api.portToCheck, 3000)
        XCTAssertEqual(api.debugInjection, .none)
        XCTAssertFalse(api.debugEnabled)
        XCTAssertFalse(api.commandEdited)
        XCTAssertNil(api.importNote)

        let build = result.runners[1]
        XCTAssertEqual(build.idea?.adapter, .vscode)
        XCTAssertEqual(build.idea?.configurationType, "vscode.task.shell")
        XCTAssertEqual(build.command, "npm run build")
        XCTAssertEqual(build.workingDirectory, root.appendingPathComponent("server").path)
        XCTAssertEqual(build.env["NODE_ENV"], "production")
        XCTAssertNil(build.portToCheck)
    }

    func testJSONCCommentsTrailingCommasAndWorkspaceVariables() throws {
        let home = root.appendingPathComponent("home")
        try writeLaunch("""
        {
          // commento di riga
          "configurations": [
            {
              "name": "web",
              "type": "node",
              "request": "launch",
              "runtimeExecutable": "${userHome}/bin/node",
              "runtimeArgs": ["--enable-source-maps"],
              "program": "${workspaceFolder}/my app.js",
              "cwd": "${workspaceRoot}",
              "env": { "HOME_PAGE": "http://example.com/a", "TITLE": "${workspaceFolderBasename}" }, /* blocco */
            },
          ],
        }
        """)

        let result = scan(userHome: home)
        let web = try XCTUnwrap(result.runners.first { $0.name == "web" })
        XCTAssertEqual(web.command, "\(home.path)/bin/node --enable-source-maps '\(root.path)/my app.js'")
        XCTAssertEqual(web.workingDirectory, root.path)
        XCTAssertEqual(web.env["HOME_PAGE"], "http://example.com/a")
        XCTAssertEqual(web.env["TITLE"], root.lastPathComponent)
        XCTAssertEqual(result.skippedFiles, [])
    }

    func testEmptyConfigurationsProduceNoRunners() throws {
        try writeLaunch(#"{"configurations":[],"compounds":[]}"#)
        try writeTasks(#"{"tasks":[]}"#)
        let result = scan()
        XCTAssertTrue(result.runners.isEmpty)
        XCTAssertTrue(result.skippedFiles.isEmpty)
    }

    func testBrokenFileIsSkippedAndTheOtherStillImports() throws {
        try writeLaunch("{ questo non è json")
        try writeTasks(#"{"tasks":[{"label":"echo","type":"shell","command":"echo hi"}]}"#)
        let brokenTasks = scan()
        XCTAssertEqual(brokenTasks.skippedFiles, ["launch.json"])
        XCTAssertEqual(brokenTasks.runners.map(\.name), ["echo"])
        XCTAssertEqual(brokenTasks.runners[0].command, "echo hi")

        try "/* solo un commento".write(to: tasksURL(), atomically: true, encoding: .utf8)
        try writeLaunch(#"{"configurations":[{"name":"api","type":"node","request":"launch","program":"api.js"}]}"#)
        let brokenLaunch = scan()
        XCTAssertEqual(brokenLaunch.skippedFiles, ["tasks.json"])
        XCTAssertEqual(brokenLaunch.runners.map(\.name), ["api"])
        XCTAssertEqual(brokenLaunch.runners[0].command, "node api.js")
    }

    func testNamelessEntriesAreIgnored() throws {
        try writeLaunch("""
        {"configurations":[
          {"type":"node","program":"a.js"},
          {"name":"   ","program":"b.js"},
          {"name":"ok","type":"node","request":"launch","program":"c.js"}
        ]}
        """)
        XCTAssertEqual(scan().runners.map(\.name), ["ok"])
    }

    func testDuplicateLaunchKeepsTheFirst() throws {
        try writeLaunch("""
        {"configurations":[
          {"name":"api","type":"node","request":"launch","program":"a.js"},
          {"name":"api","type":"node","request":"launch","program":"b.js"}
        ]}
        """)
        let result = scan()
        XCTAssertEqual(result.runners.map(\.name), ["api"])
        XCTAssertEqual(result.runners[0].command, "node a.js")
    }

    func testAttachAndJavaStayVisibleWithoutAShellCommand() throws {
        try writeLaunch("""
        {"configurations":[
          {"name":"attach","type":"node","request":"attach","port":9229},
          {"name":"app","type":"java","request":"launch","mainClass":"com.example.Main"}
        ]}
        """)
        let result = scan()
        let attach = try XCTUnwrap(result.runners.first { $0.name == "attach" })
        XCTAssertEqual(attach.command, "")
        XCTAssertEqual(attach.importNote, "Configurazione VS Code di attach: non è un comando di avvio.")
        XCTAssertEqual(attach.idea?.configurationType, "vscode.launch.node")
        let java = try XCTUnwrap(result.runners.first { $0.name == "app" })
        XCTAssertEqual(java.command, "")
        XCTAssertEqual(java.importNote, "Application con sola main class: il classpath di VS Code non è un comando di shell.")
        XCTAssertEqual(java.idea?.adapter, .vscode)
        XCTAssertEqual(java.idea?.configurationType, "vscode.launch.java")
    }

    func testPythonLaunchNpmTaskAndEnvFile() throws {
        try TestSupport.write("""
        # commento
        NAME=alpha
        PORT=9
        QUOTED="a b"
        """, to: root.appendingPathComponent(".env"))
        try writeLaunch("""
        {"configurations":[{
          "name":"flask",
          "type":"debugpy",
          "request":"launch",
          "module":"flask",
          "args":["run","--port","5002"],
          "python":"${workspaceFolder}/.venv/bin/python",
          "cwd":"service",
          "envFile":"${workspaceFolder}/.env",
          "env":{"PORT":"5002"}
        }]}
        """)
        try writeTasks("""
        {"tasks":[{
          "label":"frontend",
          "type":"npm",
          "script":"dev server",
          "path":"web"
        }]}
        """)

        let result = scan()
        let flask = try XCTUnwrap(result.runners.first { $0.name == "flask" })
        XCTAssertEqual(flask.command, "\(root.path)/.venv/bin/python -m flask run --port 5002")
        XCTAssertEqual(flask.workingDirectory, root.appendingPathComponent("service").path)
        XCTAssertEqual(flask.env["NAME"], "alpha")
        XCTAssertEqual(flask.env["PORT"], "5002")
        XCTAssertEqual(flask.env["QUOTED"], "a b")
        XCTAssertEqual(flask.portToCheck, 5002)
        XCTAssertEqual(flask.idea?.configurationType, "vscode.launch.debugpy")

        let frontend = try XCTUnwrap(result.runners.first { $0.name == "frontend" })
        XCTAssertEqual(frontend.command, "npm run 'dev server'")
        XCTAssertEqual(frontend.workingDirectory, root.appendingPathComponent("web").path)
        XCTAssertEqual(frontend.idea?.configurationType, "vscode.task.npm")
    }

    func testPreLaunchTaskAndCompoundUseResolvedCommands() throws {
        try writeTasks("""
        {"tasks":[
          {"label":"build","type":"shell","command":"echo build"},
          {"label":"prep","dependsOn":["build"],"dependsOrder":"sequence","command":"echo prep"},
          {"label":"echo A","type":"shell","command":"echo A"},
          {"label":"echo B","type":"shell","command":"echo B"},
          {"label":"parallel","dependsOn":["echo A","echo B"],"command":"echo C"},
          {"label":"a","dependsOn":"b"},
          {"label":"b","dependsOn":"a"}
        ]}
        """)
        try writeLaunch("""
        {"configurations":[
          {"name":"api","type":"node","request":"launch","program":"api.js","preLaunchTask":"prep"},
          {"name":"web","type":"node","request":"launch","runtimeExecutable":"npm","runtimeArgs":["run","dev"]},
          {"name":"solo","type":"node","request":"launch","program":"solo.js","preLaunchTask":"assente"}
        ],
        "compounds":[
          {"name":"all","configurations":["api","web","missing",{"name":"web"}],"preLaunchTask":"build"}
        ]}
        """)

        let result = scan()
        XCTAssertEqual(result.runners.map(\.name), ["api", "web", "solo", "all", "build", "prep", "echo A", "echo B", "parallel", "a", "b"])

        XCTAssertEqual(result.runners[0].command, "echo build && echo prep && node api.js")
        XCTAssertNil(result.runners[0].importNote)
        XCTAssertEqual(result.runners[1].command, "npm run dev")
        XCTAssertEqual(result.runners[2].command, "node solo.js")
        XCTAssertEqual(result.runners[2].importNote, "preLaunchTask «assente» non trovato.")

        let compound = result.runners[3]
        XCTAssertEqual(compound.idea?.configurationType, "vscode.compound")
        XCTAssertEqual(
            compound.command,
            "echo build && ((echo build && echo prep && node api.js) & (npm run dev) & (npm run dev) & wait)"
        )
        XCTAssertEqual(compound.importNote, "Compound «all»: configurazione «missing» non trovata.")

        XCTAssertEqual(result.runners.first { $0.name == "parallel" }?.command, "((echo A) & (echo B) & wait) && echo C")
        let cyclic = try XCTUnwrap(result.runners.first { $0.name == "a" })
        XCTAssertEqual(cyclic.command, "")
        XCTAssertTrue(cyclic.importNote?.contains("Dipendenza ciclica") == true)
    }

    func testProcessTaskQuotesArguments() throws {
        try writeTasks("""
        {"tasks":[{"label":"tool","type":"process","command":"echo","args":["hello world"]}]}
        """)
        XCTAssertEqual(scan().runners.first?.command, "echo 'hello world'")
    }

    func testFlaskWorkspaceLaunchesKeepDirectoryPortAndEnvironment() throws {
        try TestSupport.write("bind = \"0.0.0.0:5000\"\n", to: root.appendingPathComponent("main-service/gunicorn_config.py"))
        try TestSupport.write("# bind = \"9\"\nbind = '127.0.0.1:5001'\n", to: root.appendingPathComponent("mqtt-service/gunicorn_config.py"))
        try writeLaunch("""
        {"configurations":[
          {
            "name":"main-service-flask-debug",
            "type":"debugpy",
            "request":"launch",
            "python":"${workspaceFolder}/main-service/.venv/bin/python",
            "module":"flask",
            "cwd":"${workspaceFolder}/main-service",
            "preLaunchTask":"Deps: pip-sync main-service",
            "env":{"FLASK_APP":"app.py","FLASK_DEBUG":"1"},
            "args":["run","--host=127.0.0.1","--port=5000","--no-debugger","--no-reload"]
          },
          {
            "name":"mqtt-service-flask-debug",
            "type":"debugpy",
            "request":"launch",
            "python":"${workspaceFolder}/mqtt-service/.venv/bin/python",
            "module":"flask",
            "cwd":"${workspaceFolder}/mqtt-service",
            "env":{"FLASK_APP":"app.py"},
            "args":["run","--port=5001"]
          }
        ],
        "compounds":[{
          "name":"Flask Debug: all microservices",
          "configurations":["main-service-flask-debug","mqtt-service-flask-debug"]
        }]}
        """)
        try writeTasks("""
        {"tasks":[
          {
            "label":"Deps: pip-sync main-service",
            "type":"shell",
            "command":"./.venv/bin/pip-sync",
            "args":["requirements.txt"],
            "options":{"cwd":"${workspaceFolder}/main-service"}
          },
          {
            "label":"Gunicorn: main-service",
            "type":"shell",
            "command":"./.venv/bin/gunicorn",
            "args":["-c","gunicorn_config.py","wsgi:app"],
            "options":{"cwd":"${workspaceFolder}/main-service","env":{"NO_PROXY":"*"}}
          },
          {
            "label":"Gunicorn: mqtt-service",
            "type":"shell",
            "command":"./.venv/bin/gunicorn",
            "args":["-c","gunicorn_config.py","wsgi:app"],
            "options":{"cwd":"${workspaceFolder}/mqtt-service"}
          },
          {
            "label":"Gunicorn: all microservices",
            "dependsOrder":"parallel",
            "dependsOn":["Gunicorn: main-service","Gunicorn: mqtt-service"]
          }
        ]}
        """)

        let result = scan()
        let main = try XCTUnwrap(result.runners.first { $0.name == "main-service-flask-debug" })
        XCTAssertEqual(main.workingDirectory, root.appendingPathComponent("main-service").path)
        XCTAssertEqual(main.portToCheck, 5000)
        XCTAssertEqual(main.env["FLASK_APP"], "app.py")
        XCTAssertEqual(
            main.command,
            "./.venv/bin/pip-sync requirements.txt && \(root.path)/main-service/.venv/bin/python -m flask run '--host=127.0.0.1' '--port=5000' --no-debugger --no-reload"
        )
        XCTAssertNil(main.importNote)

        let mqtt = try XCTUnwrap(result.runners.first { $0.name == "mqtt-service-flask-debug" })
        XCTAssertEqual(mqtt.portToCheck, 5001)
        XCTAssertEqual(mqtt.workingDirectory, root.appendingPathComponent("mqtt-service").path)

        let compound = try XCTUnwrap(result.runners.first { $0.name == "Flask Debug: all microservices" })
        XCTAssertNil(compound.portToCheck)
        XCTAssertEqual(compound.workingDirectory, root.path)
        XCTAssertEqual(
            compound.command,
            "(cd \(root.path)/main-service && export FLASK_APP=app.py FLASK_DEBUG=1 && ./.venv/bin/pip-sync requirements.txt && \(root.path)/main-service/.venv/bin/python -m flask run '--host=127.0.0.1' '--port=5000' --no-debugger --no-reload) & (cd \(root.path)/mqtt-service && export FLASK_APP=app.py && \(root.path)/mqtt-service/.venv/bin/python -m flask run '--port=5001') & wait"
        )

        let gunicorn = try XCTUnwrap(result.runners.first { $0.name == "Gunicorn: main-service" })
        XCTAssertEqual(gunicorn.portToCheck, 5000)
        XCTAssertEqual(gunicorn.workingDirectory, root.appendingPathComponent("main-service").path)
        XCTAssertEqual(gunicorn.env["NO_PROXY"], "*")
        XCTAssertEqual(gunicorn.command, "./.venv/bin/gunicorn -c gunicorn_config.py wsgi:app")

        let all = try XCTUnwrap(result.runners.first { $0.name == "Gunicorn: all microservices" })
        XCTAssertNil(all.portToCheck)
        XCTAssertEqual(
            all.command,
            "(cd \(root.path)/main-service && export NO_PROXY='*' && ./.venv/bin/gunicorn -c gunicorn_config.py wsgi:app) & (cd \(root.path)/mqtt-service && ./.venv/bin/gunicorn -c gunicorn_config.py wsgi:app) & wait"
        )
        XCTAssertEqual(result.runners.first { $0.name == "Gunicorn: mqtt-service" }?.portToCheck, 5001)
    }

    func testIdeaRunnersStayAheadOfVSCodeInTheSameScan() throws {
        try TestSupport.write("""
        <component name="ProjectRunConfigurationManager">
          <configuration name="dev" type="js.build_tools.npm" factoryName="npm">
            <command value="run" />
            <scripts><script value="dev" /></scripts>
          </configuration>
        </component>
        """, to: root.appendingPathComponent(".idea/runConfigurations/npm.xml"))
        try writeLaunch(#"{"configurations":[{"name":"api","type":"node","request":"launch","program":"api.js"}]}"#)

        let result = scan()
        XCTAssertEqual(result.runners.map(\.name), ["dev", "api"])
        XCTAssertEqual(result.runners[0].idea?.adapter, .npm)
        XCTAssertEqual(result.runners[1].idea?.adapter, .vscode)
    }

    func testResyncMatchesVSCodeRunnerByNameAndType() throws {
        try writeLaunch(#"{"configurations":[{"name":"api","type":"node","request":"launch","program":"api.js"}]}"#)
        let first = try XCTUnwrap(scan().runners.first)
        var edited = first
        edited.command = "custom"
        edited.commandEdited = true
        edited.debugEnabled = true
        try writeLaunch(#"{"configurations":[{"name":"api","type":"node","request":"launch","program":"other.js","env":{"PORT":"4000"}}]}"#)
        let imported = scan().runners
        let merged = IdeaImporter.resync(existing: [edited], imported: imported, configRoot: root.appendingPathComponent("config"))
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, edited.id)
        XCTAssertEqual(merged[0].command, "custom")
        XCTAssertTrue(merged[0].commandEdited)
        XCTAssertTrue(merged[0].debugEnabled)
        XCTAssertEqual(merged[0].env["PORT"], "4000")
        XCTAssertEqual(merged[0].portToCheck, 4000)
    }

    @MainActor
    func testSessionResyncStoresVSCodeWithTheOtherRunners() async throws {
        let directory = try TestSupport.makeDirectory()
        defer { TestSupport.remove(directory) }
        let project = directory.appendingPathComponent("service")
        try TestSupport.write(
            #"{"configurations":[{"name":"api","type":"node","request":"launch","program":"api.js"}]}"#,
            to: project.appendingPathComponent(".vscode/launch.json")
        )
        let session = Session(
            store: ConfigStore(fileURL: directory.appendingPathComponent("config.json")),
            spawner: RecordingSpawner(),
            ports: PortTool(run: { _, _ in "" }, signal: { _, _ in }),
            terminationGrace: 0.01,
            configRoot: directory,
            userHome: directory
        )
        let manual = RunnerConfig(name: "manuale", command: "echo hi", workingDirectory: project.path)
        session.addProject(Project(name: "Servizio", rootPath: project.path, runners: [manual]))
        session.resync(projectID: session.projects[0].id)
        XCTAssertEqual(session.projects[0].runners.map(\.name), ["manuale", "api"])
        XCTAssertEqual(session.projects[0].runners[1].idea?.adapter, .vscode)
        XCTAssertEqual(session.projects[0].runners[1].command, "node api.js")
    }

    private func scan(userHome: URL? = nil) -> IdeaScanResult {
        IdeaScanner.scan(IdeaScanRequest(
            projectRoot: root,
            configRoot: root.appendingPathComponent("config"),
            userHome: userHome ?? root.appendingPathComponent("home"),
            applicationServersFiles: [],
            jdkTableFiles: []
        ))
    }

    private func writeLaunch(_ contents: String) throws {
        try TestSupport.write(contents, to: root.appendingPathComponent(".vscode/launch.json"))
    }

    private func writeTasks(_ contents: String) throws {
        try TestSupport.write(contents, to: tasksURL())
    }

    private func tasksURL() -> URL {
        root.appendingPathComponent(".vscode/tasks.json")
    }
}
