import Foundation

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
        let runConfigDir = request.projectRoot.appendingPathComponent(".idea/runConfigurations", isDirectory: true)
        if let files = try? FileManager.default.contentsOfDirectory(at: runConfigDir, includingPropertiesForKeys: nil) {
            let xmls = files
                .filter { $0.pathExtension.lowercased() == "xml" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in xmls {
                ingest(file: file, request: request, servers: servers, jdks: jdks, runners: &runners, skipped: &skipped, seen: &seen)
            }
        }
        let workspace = request.projectRoot.appendingPathComponent(".idea/workspace.xml")
        if FileManager.default.fileExists(atPath: workspace.path) {
            ingest(file: workspace, request: request, servers: servers, jdks: jdks, runners: &runners, skipped: &skipped, seen: &seen)
        }
        return IdeaScanResult(runners: runners, skippedFiles: skipped)
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
        if type.contains("Python") {
            return mapPython(element: element, name: name, type: type, request: request)
        }
        if type.localizedCaseInsensitiveContains("Maven") {
            if goals(element).isEmpty {
                return mapUnmapped(element: element, name: name, type: type, request: request)
            }
            return mapMaven(element: element, name: name, type: type, request: request)
        }
        if type.localizedCaseInsensitiveContains("Spring") && !goals(element).isEmpty {
            return mapMaven(element: element, name: name, type: type, request: request)
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
        let jreEnabled = element.attribute(forName: "ALTERNATIVE_JRE_ENABLED")?.stringValue == "true"
        let jrePath = element.attribute(forName: "ALTERNATIVE_JRE_PATH")?.stringValue ?? ""
        var notes: [String] = []
        if home == nil {
            notes.append("Server Tomcat non trovato in applicationServers.xml.")
        }
        var javaHome: String?
        if jreEnabled && !jrePath.isEmpty {
            if let resolved = JetBrainsLookup.jdkHome(name: jrePath, files: jdks, projectRoot: request.projectRoot, userHome: request.userHome) {
                javaHome = resolved
            } else {
                notes.append("JRE «\(jrePath)» non trovato in jdk.table.xml.")
            }
        }
        var env = environment(element, request: request)
        if let home { env["CATALINA_HOME"] = home }
        env["CATALINA_BASE"] = request.configRoot.appendingPathComponent("catalina").appendingPathComponent(id.uuidString).path
        if let javaHome { env["JAVA_HOME"] = javaHome }
        let vm = MacroExpander.expand(vmParameters(element), projectRoot: request.projectRoot, userHome: request.userHome)
        appendVar("CATALINA_OPTS", value: vm, env: &env)
        var command = ""
        if home != nil && notes.isEmpty {
            command = "exec \"$CATALINA_HOME\"/bin/catalina.sh run"
            let params = programParameters(element, request: request)
            if !params.isEmpty { command += " " + params }
        }
        let artifact = artifactName(element)
        let context = {
            let raw = (option(element, "CONTEXT_PATH") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "/" : raw
        }()
        let port = Int((option(element, "HTTP_PORT") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
        let debugPort = Int((option(element, "DEBUG_PORT") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5005
        return RunnerConfig(
            id: id,
            name: name,
            command: command,
            workingDirectory: request.projectRoot.path,
            env: env,
            debugPort: debugPort,
            portToCheck: port,
            idea: IdeaOrigin(configurationName: name, configurationType: type, adapter: .tomcat),
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

    private static func mapPython(element: XMLElement, name: String, type: String, request: IdeaScanRequest) -> RunnerConfig {
        let command: String
        if let shell = firstText(option(element, "SCRIPT_TEXT"), option(element, "COMMAND")) {
            command = MacroExpander.expand(shell, projectRoot: request.projectRoot, userHome: request.userHome)
        } else {
            let sdk = (option(element, "SDK_HOME") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let interpreter = sdk.isEmpty ? "python3" : MacroExpander.expand(sdk, projectRoot: request.projectRoot, userHome: request.userHome)
            let script = MacroExpander.expand(option(element, "SCRIPT_NAME") ?? "", projectRoot: request.projectRoot, userHome: request.userHome)
            let module = option(element, "MODULE_MODE") == "true"
            if module {
                command = "\(ShellWords.quote(interpreter)) -m \(ShellWords.quote(script))"
            } else {
                command = "\(ShellWords.quote(interpreter)) \(ShellWords.quote(script))"
            }
            let params = (option(element, "PARAMETERS") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if params.isEmpty {
                return plain(element: element, name: name, type: type, request: request, command: command, workingDirectory: workingDirectory(element, request: request), adapter: .python, injection: .none, note: nil)
            }
            return plain(element: element, name: name, type: type, request: request, command: command + " " + params, workingDirectory: workingDirectory(element, request: request), adapter: .python, injection: .none, note: nil)
        }
        return plain(element: element, name: name, type: type, request: request, command: command, workingDirectory: workingDirectory(element, request: request), adapter: .python, injection: .none, note: nil)
    }

    private static func mapMaven(element: XMLElement, name: String, type: String, request: IdeaScanRequest) -> RunnerConfig {
        let goalList = goals(element)
        let mvnw = request.projectRoot.appendingPathComponent("mvnw")
        let tool = FileManager.default.fileExists(atPath: mvnw.path) ? "./mvnw" : "mvn"
        var command = ([tool] + goalList.map(ShellWords.quote)).joined(separator: " ")
        let params = programParameters(element, request: request)
        if !params.isEmpty { command += " " + params }
        var env = environment(element, request: request)
        let vm = MacroExpander.expand(vmParameters(element), projectRoot: request.projectRoot, userHome: request.userHome)
        appendVar("JAVA_TOOL_OPTIONS", value: vm, env: &env)
        return RunnerConfig(
            name: name,
            command: command,
            workingDirectory: workingDirectory(element, request: request),
            env: env,
            idea: IdeaOrigin(configurationName: name, configurationType: type, adapter: .maven),
            debugInjection: .javaToolOptions
        )
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
            idea: IdeaOrigin(configurationName: name, configurationType: type, adapter: adapter),
            debugInjection: injection,
            importNote: note
        )
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
        guard let nodes = try? element.nodes(forXPath: ".//envs/env") else { return result }
        for case let node as XMLElement in nodes {
            guard let name = node.attribute(forName: "name")?.stringValue else { continue }
            let value = node.attribute(forName: "value")?.stringValue ?? ""
            result[name] = MacroExpander.expand(value, projectRoot: request.projectRoot, userHome: request.userHome)
        }
        return result
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
}
