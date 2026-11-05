import Foundation
#if !canImport(Darwin) && canImport(FoundationXML)
import FoundationXML
#endif

package struct IdeaScanRequest: Sendable {
    package var projectRoot: URL
    package var configRoot: URL
    package var userHome: URL
    package var applicationServersFiles: [URL]?
    package var jdkTableFiles: [URL]?

    package init(
        projectRoot: URL,
        configRoot: URL,
        userHome: URL,
        applicationServersFiles: [URL]? = nil,
        jdkTableFiles: [URL]? = nil
    ) {
        self.projectRoot = projectRoot
        self.configRoot = configRoot
        self.userHome = userHome
        self.applicationServersFiles = applicationServersFiles
        self.jdkTableFiles = jdkTableFiles
    }
}

package struct IdeaScanResult: Equatable, Sendable {
    package var runners: [RunnerConfig]
    package var skippedFiles: [String]
}

package enum IdeaScanner {
    package static func scan(_ request: IdeaScanRequest) -> IdeaScanResult {
        let servers = request.applicationServersFiles ?? JetBrainsLookup.discover(userHome: request.userHome).servers
        let jdks = request.jdkTableFiles ?? JetBrainsLookup.discover(userHome: request.userHome).jdks
        var runners: [RunnerConfig] = []
        var skipped: [String] = []
        var seen: Set<String> = []
        ingestDirectory(
            request.projectRoot.appendingPathComponent(".idea/runConfigurations", isDirectory: true),
            request: request, servers: servers, jdks: jdks, runners: &runners, skipped: &skipped, seen: &seen
        )
        ingestDirectory(
            request.projectRoot.appendingPathComponent(".run", isDirectory: true),
            request: request, servers: servers, jdks: jdks, runners: &runners, skipped: &skipped, seen: &seen
        )
        let workspace = request.projectRoot.appendingPathComponent(".idea/workspace.xml")
        if FileManager.default.fileExists(atPath: workspace.path) {
            ingest(file: workspace, request: request, servers: servers, jdks: jdks, runners: &runners, skipped: &skipped, seen: &seen)
        }
        let vscode = VSCodeScanner.scan(projectRoot: request.projectRoot, userHome: request.userHome)
        for runner in vscode.runners {
            let key = runner.name + "\u{0}" + (runner.idea?.configurationType ?? "")
            if seen.contains(key) { continue }
            seen.insert(key)
            runners.append(runner)
        }
        skipped.append(contentsOf: vscode.skippedFiles)
        return IdeaScanResult(runners: runners, skippedFiles: skipped)
    }

    private static func ingestDirectory(
        _ directory: URL,
        request: IdeaScanRequest,
        servers: [URL],
        jdks: [URL],
        runners: inout [RunnerConfig],
        skipped: inout [String],
        seen: inout Set<String>
    ) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let xmls = files
            .filter { $0.pathExtension.lowercased() == "xml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in xmls {
            ingest(file: file, request: request, servers: servers, jdks: jdks, runners: &runners, skipped: &skipped, seen: &seen)
        }
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
        guard isWellFormed(file) else {
            skipped.append(file.lastPathComponent)
            return
        }
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
        if type.contains("FlaskServer") || factory.localizedCaseInsensitiveContains("flask") {
            return mapFlask(element: element, name: name, type: type, request: request, jdks: jdks)
        }
        if type.contains("Python") {
            return mapPython(element: element, name: name, type: type, request: request, jdks: jdks)
        }
        if type.localizedCaseInsensitiveContains("Maven") {
            if goals(element).isEmpty {
                return mapUnmapped(element: element, name: name, type: type, request: request)
            }
            return mapMaven(element: element, name: name, type: type, request: request, jdks: jdks)
        }
        if type.localizedCaseInsensitiveContains("Spring") && !goals(element).isEmpty {
            return mapMaven(element: element, name: name, type: type, request: request, jdks: jdks)
        }
        if type.localizedCaseInsensitiveContains("Spring") {
            return mapSpringBoot(element: element, name: name, type: type, request: request, jdks: jdks)
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
        var notes: [String] = []
        if home == nil {
            notes.append("Server Tomcat non trovato in applicationServers.xml.")
        }
        var env = environment(element, request: request)
        if let home { env["CATALINA_HOME"] = home }
        env["CATALINA_BASE"] = request.configRoot.appendingPathComponent("catalina").appendingPathComponent(id.uuidString).path
        applyJavaHome(element: element, request: request, jdks: jdks, env: &env, notes: &notes)
        let vm = MacroExpander.expand(vmParameters(element), projectRoot: request.projectRoot, userHome: request.userHome)
        appendVar("CATALINA_OPTS", value: vm, env: &env)
        let before = beforeLaunch(element: element, request: request)
        var command = ""
        if home != nil && notes.isEmpty && !before.blocked {
            var launch = "exec \"$CATALINA_HOME\"/bin/catalina.sh run"
            let params = programParameters(element, request: request)
            if !params.isEmpty { launch += " " + params }
            command = (before.commands + [launch]).joined(separator: " && ")
        }
        notes.append(contentsOf: before.notes)
        let artifact = artifactName(element)
        let context = {
            let raw = (option(element, "CONTEXT_PATH") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "/" : raw
        }()
        let port = Int((option(element, "HTTP_PORT") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
        // RunnerSettings DEBUG_PORT is an ephemeral IDE listener, not a JDWP address.
        let debugPort = explicitJdwpPort(element) ?? 5005
        return RunnerConfig(
            id: id,
            name: name,
            command: command,
            workingDirectory: request.projectRoot.path,
            env: env,
            debugPort: debugPort,
            portToCheck: port,
            idea: IdeaOrigin(
                configurationName: name,
                configurationType: type,
                adapter: .tomcat,
                sourceRoot: Project.normalizePath(request.projectRoot.path)
            ),
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

    private static func mapFlask(
        element: XMLElement,
        name: String,
        type: String,
        request: IdeaScanRequest,
        jdks: [URL]
    ) -> RunnerConfig {
        let resolution = resolveInterpreter(element: element, request: request, jdks: jdks)
        let command: String
        let note: String?
        switch resolution {
        case .command(let interpreter):
            command = "\(ShellWords.quote(interpreter)) -m flask run"
            note = nil
        case .missing(let message):
            command = ""
            note = message
        }
        var runner = plain(
            element: element, name: name, type: type, request: request,
            command: command, workingDirectory: workingDirectory(element, request: request),
            adapter: .python, injection: .none, note: note
        )
        let target = MacroExpander.expand(
            (option(element, "target") ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            projectRoot: request.projectRoot,
            userHome: request.userHome
        )
        if !target.isEmpty {
            runner.env["FLASK_APP"] = target
        }
        runner.portToCheck = flaskPort(runner.env["FLASK_RUN_PORT"])
        return runner
    }

    private static func mapPython(
        element: XMLElement,
        name: String,
        type: String,
        request: IdeaScanRequest,
        jdks: [URL]
    ) -> RunnerConfig {
        let work = workingDirectory(element, request: request)
        if let shell = firstText(option(element, "SCRIPT_TEXT"), option(element, "COMMAND")) {
            let command = MacroExpander.expand(shell, projectRoot: request.projectRoot, userHome: request.userHome)
            return plain(
                element: element, name: name, type: type, request: request,
                command: command, workingDirectory: work, adapter: .python, injection: .none, note: nil
            )
        }
        let interpreter: String
        switch resolveInterpreter(element: element, request: request, jdks: jdks) {
        case .command(let value):
            interpreter = value
        case .missing(let message):
            return plain(
                element: element, name: name, type: type, request: request,
                command: "", workingDirectory: work, adapter: .python, injection: .none, note: message
            )
        }
        let script = MacroExpander.expand(option(element, "SCRIPT_NAME") ?? "", projectRoot: request.projectRoot, userHome: request.userHome)
        let module = option(element, "MODULE_MODE") == "true"
        var command = module
            ? "\(ShellWords.quote(interpreter)) -m \(ShellWords.quote(script))"
            : "\(ShellWords.quote(interpreter)) \(ShellWords.quote(script))"
        let params = (option(element, "PARAMETERS") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !params.isEmpty { command += " " + params }
        return plain(
            element: element, name: name, type: type, request: request,
            command: command, workingDirectory: work, adapter: .python, injection: .none, note: nil
        )
    }

    private enum InterpreterResolution {
        case command(String)
        case missing(String)
    }

    private static func resolveInterpreter(element: XMLElement, request: IdeaScanRequest, jdks: [URL]) -> InterpreterResolution {
        let sdkHome = (option(element, "SDK_HOME") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !sdkHome.isEmpty {
            return .command(MacroExpander.expand(sdkHome, projectRoot: request.projectRoot, userHome: request.userHome))
        }
        let sdkName = (option(element, "SDK_NAME") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if sdkName.isEmpty { return .command("python3") }
        if let home = JetBrainsLookup.jdkHome(name: sdkName, files: jdks, projectRoot: request.projectRoot, userHome: request.userHome) {
            return .command(home)
        }
        return .missing("Interprete «\(sdkName)» non trovato in jdk.table.xml.")
    }

    private static func flaskPort(_ raw: String?) -> Int {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let port = Int(text), (1...65535).contains(port) { return port }
        return 5000
    }

    private static func mapSpringBoot(
        element: XMLElement,
        name: String,
        type: String,
        request: IdeaScanRequest,
        jdks: [URL]
    ) -> RunnerConfig {
        let pom = request.projectRoot.appendingPathComponent("pom.xml")
        guard FileManager.default.fileExists(atPath: pom.path) else {
            return mapUnmapped(element: element, name: name, type: type, request: request)
        }
        let tool: String
        switch resolveMaven(request) {
        case .command(let value):
            tool = value
        case .missing(let message):
            return springRunner(
                element: element, name: name, type: type, request: request, jdks: jdks,
                command: "", note: message
            )
        }
        var args = [tool]
        let mainClass = (option(element, "SPRING_BOOT_MAIN_CLASS") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !mainClass.isEmpty {
            args.append(ShellWords.quote("-Dspring-boot.run.mainClass=\(mainClass)"))
        }
        let profiles = (option(element, "ACTIVE_PROFILES") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !profiles.isEmpty {
            args.append(ShellWords.quote("-Dspring-boot.run.profiles=\(profiles)"))
        }
        args.append("spring-boot:run")
        var command = args.joined(separator: " ")
        let params = programParameters(element, request: request)
        if !params.isEmpty { command += " " + params }
        return springRunner(
            element: element, name: name, type: type, request: request, jdks: jdks,
            command: command, note: nil
        )
    }

    private static func springRunner(
        element: XMLElement,
        name: String,
        type: String,
        request: IdeaScanRequest,
        jdks: [URL],
        command: String,
        note: String?
    ) -> RunnerConfig {
        var env = environment(element, request: request)
        let vm = MacroExpander.expand(vmParameters(element), projectRoot: request.projectRoot, userHome: request.userHome)
        appendVar("JAVA_TOOL_OPTIONS", value: vm, env: &env)
        var notes: [String] = []
        if let note, !note.isEmpty { notes.append(note) }
        applyJavaHome(element: element, request: request, jdks: jdks, env: &env, notes: &notes)
        return RunnerConfig(
            name: name,
            command: command,
            workingDirectory: workingDirectory(element, request: request),
            env: env,
            idea: origin(name: name, type: type, adapter: .maven, request: request),
            debugInjection: .javaToolOptions,
            importNote: notes.isEmpty ? nil : notes.joined(separator: " ")
        )
    }

    private static func mapMaven(element: XMLElement, name: String, type: String, request: IdeaScanRequest, jdks: [URL]) -> RunnerConfig {
        let goalList = goals(element)
        let tool: String
        switch resolveMaven(request) {
        case .command(let value):
            tool = value
        case .missing(let message):
            return RunnerConfig(
                name: name,
                command: "",
                workingDirectory: workingDirectory(element, request: request),
                env: environment(element, request: request),
                idea: origin(name: name, type: type, adapter: .maven, request: request),
                debugInjection: .javaToolOptions,
                importNote: message
            )
        }
        var command = ([tool] + goalList.map(ShellWords.quote)).joined(separator: " ")
        let params = programParameters(element, request: request)
        if !params.isEmpty { command += " " + params }
        var env = environment(element, request: request)
        let vm = MacroExpander.expand(vmParameters(element), projectRoot: request.projectRoot, userHome: request.userHome)
        appendVar("JAVA_TOOL_OPTIONS", value: vm, env: &env)
        var notes: [String] = []
        applyJavaHome(element: element, request: request, jdks: jdks, env: &env, notes: &notes)
        return RunnerConfig(
            name: name,
            command: command,
            workingDirectory: workingDirectory(element, request: request),
            env: env,
            idea: origin(name: name, type: type, adapter: .maven, request: request),
            debugInjection: .javaToolOptions,
            importNote: notes.isEmpty ? nil : notes.joined(separator: " ")
        )
    }

    /// Run configuration JRE when enabled, otherwise the project SDK from `.idea/misc.xml`.
    private static func applyJavaHome(
        element: XMLElement,
        request: IdeaScanRequest,
        jdks: [URL],
        env: inout [String: String],
        notes: inout [String]
    ) {
        let alternative = element.attribute(forName: "ALTERNATIVE_JRE_ENABLED")?.stringValue == "true"
        let alternativeName = element.attribute(forName: "ALTERNATIVE_JRE_PATH")?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = alternative && !alternativeName.isEmpty ? alternativeName : projectJdkName(request.projectRoot)
        guard let name, !name.isEmpty else { return }
        guard let home = JetBrainsLookup.jdkHome(name: name, files: jdks, projectRoot: request.projectRoot, userHome: request.userHome) else {
            notes.append("JRE «\(name)» non trovato in jdk.table.xml.")
            return
        }
        env["JAVA_HOME"] = home
        env["JRE_HOME"] = home
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
            idea: origin(name: name, type: type, adapter: adapter, request: request),
            debugInjection: injection,
            importNote: note
        )
    }

    private static func origin(
        name: String,
        type: String,
        adapter: IdeaAdapter,
        request: IdeaScanRequest
    ) -> IdeaOrigin {
        IdeaOrigin(
            configurationName: name,
            configurationType: type,
            adapter: adapter,
            sourceRoot: Project.normalizePath(request.projectRoot.path)
        )
    }

    private enum MavenHomeKind {
        case unspecified
        case wrapper
        case bundled
        case custom(String)
    }

    private enum ResolvedMaven {
        case command(String)
        case missing(String)
    }

    private static func resolveMaven(_ request: IdeaScanRequest) -> ResolvedMaven {
        let mvnw = request.projectRoot.appendingPathComponent("mvnw")
        switch mavenHomeKind(request.projectRoot) {
        case .wrapper:
            if FileManager.default.fileExists(atPath: mvnw.path) { return .command("./mvnw") }
            return .missing("Maven wrapper impostato in IntelliJ, ma mvnw non c'è nella radice del progetto.")
        case .bundled:
            if let path = bundledMaven(userHome: request.userHome) { return .command(ShellWords.quote(path)) }
            return .missing("Maven incluso in IntelliJ non trovato.")
        case .custom(let home):
            let expanded = MacroExpander.expand(home, projectRoot: request.projectRoot, userHome: request.userHome)
            let bin = URL(fileURLWithPath: expanded).appendingPathComponent("bin/mvn").path
            if FileManager.default.fileExists(atPath: bin) { return .command(ShellWords.quote(bin)) }
            return .missing("Maven «\(expanded)» non trovato.")
        case .unspecified:
            if FileManager.default.fileExists(atPath: mvnw.path) { return .command("./mvnw") }
            return .command("mvn")
        }
    }

    private static func mavenHomeKind(_ projectRoot: URL) -> MavenHomeKind {
        let workspace = projectRoot.appendingPathComponent(".idea/workspace.xml")
        guard let document = try? XMLDocument(contentsOf: workspace, options: [.nodePreserveWhitespace]),
              let nodes = try? document.nodes(forXPath: "//MavenGeneralSettings") else { return .unspecified }
        for case let element as XMLElement in nodes {
            let type = directOption(element, "mavenHomeTypeForPersistence") ?? ""
            switch type {
            case "WRAPPER":
                return .wrapper
            case "BUNDLED":
                return .bundled
            case "CUSTOM":
                let home = (directOption(element, "mavenHome") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !home.isEmpty { return .custom(home) }
            default:
                continue
            }
        }
        return .unspecified
    }

    private static func directOption(_ element: XMLElement, _ name: String) -> String? {
        for child in element.elements(forName: "option") {
            if child.attribute(forName: "name")?.stringValue == name {
                return child.attribute(forName: "value")?.stringValue
            }
        }
        return nil
    }

    private static func bundledMaven(userHome: URL) -> String? {
        var candidates: [URL] = []
        let jetbrains = userHome.appendingPathComponent("Library/Application Support/JetBrains", isDirectory: true)
        if let products = try? FileManager.default.contentsOfDirectory(
            at: jetbrains,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for product in products {
                let mvn = product.appendingPathComponent("plugins/maven/lib/maven3/bin/mvn")
                if FileManager.default.fileExists(atPath: mvn.path) { candidates.append(mvn) }
            }
        }
        for apps in [URL(fileURLWithPath: "/Applications", isDirectory: true), userHome.appendingPathComponent("Applications", isDirectory: true)] {
            guard let bundles = try? FileManager.default.contentsOfDirectory(at: apps, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for bundle in bundles where bundle.pathExtension == "app" {
                let mvn = bundle.appendingPathComponent("Contents/plugins/maven/lib/maven3/bin/mvn")
                if FileManager.default.fileExists(atPath: mvn.path) { candidates.append(mvn) }
            }
        }
        let newest = candidates.max { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        return newest?.path
    }

    private static func projectJdkName(_ projectRoot: URL) -> String? {
        let misc = projectRoot.appendingPathComponent(".idea/misc.xml")
        guard let document = try? XMLDocument(contentsOf: misc, options: [.nodePreserveWhitespace]),
              let nodes = try? document.nodes(forXPath: "//component[@name='ProjectRootManager']") else { return nil }
        for case let element as XMLElement in nodes {
            let name = element.attribute(forName: "project-jdk-name")?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty { return name }
        }
        return nil
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

    private struct BeforeLaunch {
        var commands: [String]
        var notes: [String]
        var blocked: Bool
    }

    private enum BeforeStep {
        case compile
        case exploded
        case maven(String)
    }

    /// IntelliJ `<method v="2">` tasks. Make plus a war-exploded artifact is one `war:exploded`, which compiles and refreshes the docBase Tomcat serves.
    private static func beforeLaunch(element: XMLElement, request: IdeaScanRequest) -> BeforeLaunch {
        guard let method = element.elements(forName: "method").first else {
            return BeforeLaunch(commands: [], notes: [], blocked: false)
        }
        var steps: [BeforeStep] = []
        var notes: [String] = []
        for option in method.elements(forName: "option") {
            if option.attribute(forName: "enabled")?.stringValue == "false" { continue }
            let name = option.attribute(forName: "name")?.stringValue ?? ""
            switch name {
            case "Make", "MakeProject", "Build":
                steps.append(.compile)
            case "BuildArtifacts":
                appendArtifactBuild(option, steps: &steps, notes: &notes)
            case "Maven.BeforeRunTask":
                let goal = (option.attribute(forName: "goal")?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if goal.isEmpty {
                    notes.append("Before launch Maven senza goal.")
                } else {
                    steps.append(.maven(goal))
                }
            default:
                if !name.isEmpty {
                    notes.append("Before launch «\(name)» non replicato.")
                }
            }
        }
        if steps.contains(where: { if case .exploded = $0 { return true }; return false }) {
            steps.removeAll { if case .compile = $0 { return true }; return false }
        }
        if steps.isEmpty {
            return BeforeLaunch(commands: [], notes: notes, blocked: false)
        }
        let tool: String
        switch resolveMaven(request) {
        case .command(let value):
            tool = value
        case .missing(let message):
            notes.append(message)
            return BeforeLaunch(commands: [], notes: notes, blocked: true)
        }
        let commands = steps.map { step -> String in
            switch step {
            case .compile:
                return "\(tool) -DskipTests -q compile"
            case .exploded:
                return "\(tool) -DskipTests -q war:exploded"
            case .maven(let goal):
                return "\(tool) \(goal)"
            }
        }
        return BeforeLaunch(commands: commands, notes: notes, blocked: false)
    }

    private static func appendArtifactBuild(_ option: XMLElement, steps: inout [BeforeStep], notes: inout [String]) {
        let artifacts = option.elements(forName: "artifact").compactMap { node -> String? in
            let value = node.attribute(forName: "name")?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        if artifacts.isEmpty {
            if !steps.contains(where: { if case .exploded = $0 { return true }; return false }) {
                steps.append(.exploded)
            }
            return
        }
        var exploded = false
        for artifact in artifacts {
            if isExplodedWar(artifact) {
                exploded = true
            } else {
                notes.append("Before launch Build «\(artifact)» non replicato.")
            }
        }
        if exploded, !steps.contains(where: { if case .exploded = $0 { return true }; return false }) {
            steps.append(.exploded)
        }
    }

    private static func isExplodedWar(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("war exploded") || lower.contains("exploded-war") || lower.hasSuffix(":exploded")
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
        let files = (option(element, "ENV_FILES") ?? "").split(separator: ";", omittingEmptySubsequences: true)
        for file in files {
            let expanded = MacroExpander.expand(
                file.trimmingCharacters(in: .whitespacesAndNewlines),
                projectRoot: request.projectRoot,
                userHome: request.userHome
            )
            guard !expanded.isEmpty else { continue }
            for (key, value) in DotEnv.parse(at: URL(fileURLWithPath: expanded)) {
                result[key] = value
            }
        }
        if let nodes = try? element.nodes(forXPath: ".//envs/env") {
            for case let node as XMLElement in nodes {
                guard let name = node.attribute(forName: "name")?.stringValue else { continue }
                let value = node.attribute(forName: "value")?.stringValue ?? ""
                result[name] = MacroExpander.expand(value, projectRoot: request.projectRoot, userHome: request.userHome)
            }
        }
        return result
    }

    private static func explicitJdwpPort(_ element: XMLElement) -> Int? {
        let xml = element.xmlString.lowercased()
        var start = xml.startIndex
        while let marker = xml.range(of: "jdwp=", range: start..<xml.endIndex) {
            let after = xml[marker.upperBound...]
            let chunkEnd = after.firstIndex(where: { $0 == "\"" || $0 == "<" }) ?? after.endIndex
            let chunk = after[..<chunkEnd]
            if let address = chunk.range(of: "address=") {
                var token = ""
                for character in chunk[address.upperBound...] {
                    if character == "," || character == " " || character == "\t" || character == "'" {
                        break
                    }
                    token.append(character)
                    if token.count > 100 { break }
                }
                let portText = String(token.split(separator: ":").last ?? "")
                if let port = Int(portText), (1...65535).contains(port) {
                    return port
                }
            }
            start = marker.upperBound
        }
        return nil
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

    private static func isWellFormed(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let parser = XMLParser(data: data)
        let delegate = WellFormedXML()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        return !delegate.failed
    }
}

private final class WellFormedXML: NSObject, XMLParserDelegate {
    var failed = false

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failed = true
    }
}
