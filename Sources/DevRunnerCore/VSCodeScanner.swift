import Foundation

package struct VSCodeScanResult: Equatable, Sendable {
    package var runners: [RunnerConfig]
    package var skippedFiles: [String]
}

package enum VSCodeScanner {
    package static func scan(projectRoot: URL, userHome: URL) -> VSCodeScanResult {
        var skipped: [String] = []
        let launchURL = projectRoot.appendingPathComponent(".vscode/launch.json")
        let tasksURL = projectRoot.appendingPathComponent(".vscode/tasks.json")
        let launchObject = loadObject(at: launchURL, skipped: &skipped)
        let tasksObject = loadObject(at: tasksURL, skipped: &skipped)
        let context = Context(projectRoot: projectRoot, userHome: userHome)
        let tasks = (tasksObject?["tasks"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.compactMap { TaskDef($0, context: context) }
        let taskIndex = TaskIndex(tasks)
        var runners: [RunnerConfig] = []
        var seen: Set<String> = []
        var launchesByName: [String: RunnerConfig] = [:]

        for configuration in launchObject?["configurations"] as? [Any] ?? [] {
            guard let object = configuration as? [String: Any] else { continue }
            guard let runner = launchRunner(object, context: context, tasks: taskIndex) else { continue }
            guard remember(runner, seen: &seen) else { continue }
            runners.append(runner)
            if launchesByName[runner.name] == nil {
                launchesByName[runner.name] = runner
            }
        }
        for compound in launchObject?["compounds"] as? [Any] ?? [] {
            guard let object = compound as? [String: Any] else { continue }
            guard let runner = compoundRunner(object, launches: launchesByName, context: context, tasks: taskIndex) else { continue }
            guard remember(runner, seen: &seen) else { continue }
            runners.append(runner)
        }
        for task in tasks {
            let resolved = taskIndex.resolve(task.label)
            guard let runner = taskRunner(task, command: resolved.command, notes: resolved.notes) else { continue }
            guard remember(runner, seen: &seen) else { continue }
            runners.append(runner)
        }
        return VSCodeScanResult(runners: runners, skippedFiles: skipped)
    }

    private static func remember(_ runner: RunnerConfig, seen: inout Set<String>) -> Bool {
        let key = runner.name + "\u{0}" + (runner.idea?.configurationType ?? "")
        if seen.contains(key) { return false }
        seen.insert(key)
        return true
    }

    private static func loadObject(at url: URL, skipped: inout [String]) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let object = JSONC.object(from: text) else {
            skipped.append(url.lastPathComponent)
            return nil
        }
        return object
    }

    private static func launchRunner(_ object: [String: Any], context: Context, tasks: TaskIndex) -> RunnerConfig? {
        let name = text(object, "name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let type = text(object, "type").trimmingCharacters(in: .whitespacesAndNewlines)
        let request = text(object, "request").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var notes: [String] = []
        var command = ""
        if request == "attach" {
            notes.append("Configurazione VS Code di attach: non è un comando di avvio.")
        } else {
            let built = launchCommand(object, type: type.lowercased(), context: context)
            command = built.command
            if let note = built.note { notes.append(note) }
        }
        let preLaunch = text(object, "preLaunchTask").trimmingCharacters(in: .whitespacesAndNewlines)
        if !preLaunch.isEmpty {
            if tasks.contains(preLaunch) {
                let resolved = tasks.resolve(preLaunch)
                notes.append(contentsOf: resolved.notes)
                if resolved.command.isEmpty {
                    notes.append("preLaunchTask «\(preLaunch)» senza comando.")
                } else if !command.isEmpty {
                    command = ShellScript.join(resolved.command, command)
                }
            } else {
                notes.append("preLaunchTask «\(preLaunch)» non trovato.")
            }
        }
        if command.isEmpty && notes.isEmpty {
            notes.append("Configurazione VS Code senza comando.")
        }
        let env = environment(object, context: context)
        let cwd = text(object, "cwd")
        return make(
            name: name,
            configurationType: typed("vscode.launch", type),
            command: command,
            workingDirectory: context.directory(cwd),
            env: env,
            portToCheck: port(in: env),
            note: notes
        )
    }

    private static func launchCommand(_ object: [String: Any], type: String, context: Context) -> (command: String, note: String?) {
        let args = list(object, "args").map { context.expand($0) }
        let runtimeArgs = list(object, "runtimeArgs").map { context.expand($0) }
        let program = context.expand(text(object, "program"))
        let runtime = context.expand(text(object, "runtimeExecutable"))
        let module = context.expand(text(object, "module"))
        let commandField = context.expand(text(object, "command"))
        let python = context.expand(firstText(text(object, "python"), text(object, "pythonPath")))
        let mainClass = text(object, "mainClass").trimmingCharacters(in: .whitespacesAndNewlines)
        if !runtime.isEmpty {
            return (ShellScript.words([runtime] + runtimeArgs + (program.isEmpty ? [] : [program]) + args), nil)
        }
        if type == "npm" {
            let script = context.expand(firstText(text(object, "script"), commandField))
            if !script.isEmpty {
                return (ShellScript.append("npm run \(ShellWords.quote(script))", args), nil)
            }
        }
        if isPython(type) || (!module.isEmpty && type.isEmpty) {
            let interpreter = python.isEmpty ? "python3" : python
            if !module.isEmpty {
                return (ShellScript.words([interpreter, "-m", module] + args), nil)
            }
            if !program.isEmpty {
                return (ShellScript.words([interpreter, program] + args), nil)
            }
        }
        if !commandField.isEmpty {
            return (ShellScript.append(commandField, args), nil)
        }
        if type == "java" && !mainClass.isEmpty && program.isEmpty {
            return ("", "Application con sola main class: il classpath di VS Code non è un comando di shell.")
        }
        if isNode(type) && !program.isEmpty {
            return (ShellScript.words(["node", program] + args), nil)
        }
        if !program.isEmpty {
            return (ShellScript.words([program] + args), nil)
        }
        if type == "java" && !mainClass.isEmpty {
            return ("", "Application con sola main class: il classpath di VS Code non è un comando di shell.")
        }
        return ("", nil)
    }

    private static func compoundRunner(
        _ object: [String: Any],
        launches: [String: RunnerConfig],
        context: Context,
        tasks: TaskIndex
    ) -> RunnerConfig? {
        let name = text(object, "name").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var notes: [String] = []
        var commands: [String] = []
        for reference in references(object["configurations"]) {
            if let runner = launches[reference], !runner.command.isEmpty {
                commands.append(runner.command)
            } else if launches[reference] == nil {
                notes.append("Compound «\(name)»: configurazione «\(reference)» non trovata.")
            }
        }
        var command = ShellScript.parallel(commands)
        let preLaunch = text(object, "preLaunchTask").trimmingCharacters(in: .whitespacesAndNewlines)
        if !preLaunch.isEmpty {
            if tasks.contains(preLaunch) {
                let resolved = tasks.resolve(preLaunch)
                notes.append(contentsOf: resolved.notes)
                if !resolved.command.isEmpty && !command.isEmpty {
                    command = ShellScript.join(resolved.command, command)
                } else if resolved.command.isEmpty {
                    notes.append("preLaunchTask «\(preLaunch)» senza comando.")
                }
            } else {
                notes.append("preLaunchTask «\(preLaunch)» non trovato.")
            }
        }
        if command.isEmpty && notes.isEmpty {
            notes.append("Configurazione VS Code senza comando.")
        }
        return make(
            name: name,
            configurationType: "vscode.compound",
            command: command,
            workingDirectory: context.projectRoot.path,
            env: environment(object, context: context),
            portToCheck: nil,
            note: notes
        )
    }

    private static func taskRunner(_ task: TaskDef, command: String, notes: [String]) -> RunnerConfig? {
        var notes = notes
        if command.isEmpty && notes.isEmpty {
            notes.append("Configurazione VS Code senza comando.")
        }
        return make(
            name: task.label,
            configurationType: typed("vscode.task", task.type),
            command: command,
            workingDirectory: task.workingDirectory,
            env: task.env,
            portToCheck: port(in: task.env),
            note: notes
        )
    }

    private static func make(
        name: String,
        configurationType: String,
        command: String,
        workingDirectory: String,
        env: [String: String],
        portToCheck: Int?,
        note: [String]
    ) -> RunnerConfig {
        RunnerConfig(
            name: name,
            command: command,
            workingDirectory: workingDirectory,
            env: env,
            portToCheck: portToCheck,
            idea: IdeaOrigin(configurationName: name, configurationType: configurationType, adapter: .vscode),
            debugInjection: .none,
            importNote: note.isEmpty ? nil : note.joined(separator: " ")
        )
    }

    private static func environment(_ object: [String: Any], context: Context) -> [String: String] {
        var result: [String: String] = [:]
        let file = context.expand(text(object, "envFile")).trimmingCharacters(in: .whitespacesAndNewlines)
        if !file.isEmpty {
            let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : context.projectRoot.appendingPathComponent(file)
            result.merge(DotEnv.parse(at: url)) { _, new in new }
        }
        if let env = object["env"] as? [String: Any] {
            for (key, value) in env {
                guard let text = value as? String else { continue }
                result[key] = context.expand(text)
            }
        }
        return result
    }

    private static func port(in env: [String: String]) -> Int? {
        for key in ["PORT", "FLASK_RUN_PORT"] {
            let raw = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let port = Int(raw), (1...65535).contains(port) { return port }
        }
        return nil
    }

    private static func references(_ value: Any?) -> [String] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { item in
            if let name = item as? String {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let object = item as? [String: Any] {
                let name = text(object, "name").trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
            return nil
        }
    }

    private static func isPython(_ type: String) -> Bool {
        type == "python" || type == "debugpy" || type.contains("python")
    }

    private static func isNode(_ type: String) -> Bool {
        type == "node" || type == "pwa-node" || type == "node-terminal"
    }

    private static func typed(_ prefix: String, _ type: String) -> String {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return prefix }
        return prefix + "." + trimmed
    }

    private static func text(_ object: [String: Any], _ key: String) -> String {
        object[key] as? String ?? ""
    }

    private static func list(_ object: [String: Any], _ key: String) -> [String] {
        if let values = object[key] as? [Any] {
            return values.compactMap { $0 as? String }
        }
        if let value = object[key] as? String { return [value] }
        return []
    }

    private static func firstText(_ values: String...) -> String {
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}

private struct Context: Sendable {
    var projectRoot: URL
    var userHome: URL

    func expand(_ value: String) -> String {
        var result = value
        let pairs = [
            ("${workspaceFolderBasename}", projectRoot.lastPathComponent),
            ("${workspaceFolder}", projectRoot.path),
            ("${workspaceRoot}", projectRoot.path),
            ("${userHome}", userHome.path)
        ]
        for (token, replacement) in pairs {
            result = result.replacingOccurrences(of: token, with: replacement)
        }
        return result
    }

    func directory(_ raw: String) -> String {
        let expanded = expand(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if expanded.isEmpty { return projectRoot.path }
        if expanded.hasPrefix("/") { return expanded }
        return projectRoot.appendingPathComponent(expanded).path
    }
}

private struct TaskDef {
    var label: String
    var type: String
    var ownCommand: String
    var dependsOn: [String]
    var sequence: Bool
    var workingDirectory: String
    var env: [String: String]

    init?(_ object: [String: Any], context: Context) {
        let label = VSCodeScannerLabel.label(object)
        guard !label.isEmpty else { return nil }
        let type = (object["type"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let options = object["options"] as? [String: Any] ?? [:]
        let args = ((object["args"] as? [Any]) ?? []).compactMap { $0 as? String }.map { context.expand($0) }
        let commandText = context.expand(object["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let script = context.expand(object["script"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let own: String
        if type.lowercased() == "npm" {
            if script.isEmpty {
                own = ""
            } else {
                own = ShellScript.append("npm run \(ShellWords.quote(script))", args)
            }
        } else if type.lowercased() == "process" {
            own = commandText.isEmpty ? "" : ShellScript.words([commandText] + args)
        } else {
            own = commandText.isEmpty ? "" : ShellScript.append(commandText, args)
        }
        var cwd = options["cwd"] as? String ?? ""
        if cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, type.lowercased() == "npm" {
            cwd = object["path"] as? String ?? ""
        }
        var env: [String: String] = [:]
        if let values = options["env"] as? [String: Any] {
            for (key, value) in values {
                guard let text = value as? String else { continue }
                env[key] = context.expand(text)
            }
        }
        self.label = label
        self.type = type
        self.ownCommand = own
        self.dependsOn = TaskDef.dependencies(object["dependsOn"])
        let order = (object["dependsOrder"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.sequence = order.lowercased() == "sequence"
        self.workingDirectory = context.directory(cwd)
        self.env = env
    }

    private static func dependencies(_ value: Any?) -> [String] {
        if let name = value as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { item in
            if let name = item as? String {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let object = item as? [String: Any] {
                let name = ((object["task"] as? String) ?? (object["label"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
            return nil
        }
    }
}

private enum VSCodeScannerLabel {
    static func label(_ object: [String: Any]) -> String {
        let label = (object["label"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        return (object["taskName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class TaskIndex {
    var tasks: [String: TaskDef]
    private var memo: [String: (command: String, notes: [String])] = [:]

    init(_ tasks: [TaskDef]) {
        var indexed: [String: TaskDef] = [:]
        for task in tasks where indexed[task.label] == nil {
            indexed[task.label] = task
        }
        self.tasks = indexed
    }

    func contains(_ label: String) -> Bool {
        tasks[label] != nil
    }

    func resolve(_ label: String) -> (command: String, notes: [String]) {
        resolve(label, stack: [])
    }

    private func resolve(_ label: String, stack: Set<String>) -> (command: String, notes: [String]) {
        if stack.contains(label) {
            return ("", ["Dipendenza ciclica nel task «\(label)»."])
        }
        if let cached = memo[label] { return cached }
        guard let task = tasks[label] else {
            return ("", ["Task «\(label)» non trovato."])
        }
        var next = stack
        next.insert(label)
        var notes: [String] = []
        var dependencies: [String] = []
        for name in task.dependsOn {
            let resolved = resolve(name, stack: next)
            notes.append(contentsOf: resolved.notes)
            if !resolved.command.isEmpty { dependencies.append(resolved.command) }
        }
        let command: String
        if task.sequence || dependencies.count <= 1 {
            command = ShellScript.sequence(dependencies + (task.ownCommand.isEmpty ? [] : [task.ownCommand]))
        } else if task.ownCommand.isEmpty {
            command = ShellScript.parallel(dependencies)
        } else {
            command = ShellScript.join(ShellScript.parallel(dependencies), task.ownCommand)
        }
        let result = (command, notes)
        memo[label] = result
        return result
    }
}

private enum ShellScript {
    static func words(_ values: [String]) -> String {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map(ShellWords.quote).joined(separator: " ")
    }

    static func append(_ command: String, _ args: [String]) -> String {
        let head = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = words(args)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }

    static func sequence(_ parts: [String]) -> String {
        let cleaned = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if cleaned.count <= 1 { return cleaned.first ?? "" }
        return cleaned.map(group).joined(separator: " && ")
    }

    static func join(_ first: String, _ second: String) -> String {
        sequence([first, second])
    }

    static func parallel(_ parts: [String]) -> String {
        let cleaned = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if cleaned.count <= 1 { return cleaned.first ?? "" }
        return cleaned.map { "(\($0))" }.joined(separator: " & ") + " & wait"
    }

    private static func group(_ command: String) -> String {
        if needsGroup(command) { return "(\(command))" }
        return command
    }

    /// `&&` and `||` associate with a later `&&`. A background `&`, a pipe or a `;` does not.
    private static func needsGroup(_ command: String) -> Bool {
        var index = command.startIndex
        while index < command.endIndex {
            let character = command[index]
            if character == "&" || character == "|" {
                let next = command.index(after: index)
                if next < command.endIndex, command[next] == character {
                    index = command.index(after: next)
                    continue
                }
                return true
            }
            if character == ";" || character == "\n" { return true }
            index = command.index(after: index)
        }
        return false
    }
}

private enum JSONC {
    static func object(from text: String) -> [String: Any]? {
        var source = text
        if source.hasPrefix("\u{feff}") { source.removeFirst() }
        guard let data = strip(source).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func strip(_ text: String) -> String {
        var output = ""
        let chars = Array(text)
        var index = 0
        var inString = false
        var escaped = false
        while index < chars.count {
            let character = chars[index]
            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index += 1
                continue
            }
            if character == "/", index + 1 < chars.count {
                let next = chars[index + 1]
                if next == "/" {
                    index += 2
                    while index < chars.count, chars[index] != "\n" { index += 1 }
                    continue
                }
                if next == "*" {
                    index += 2
                    while index + 1 < chars.count, !(chars[index] == "*" && chars[index + 1] == "/") {
                        index += 1
                    }
                    index = min(index + 2, chars.count)
                    output.append(" ")
                    continue
                }
            }
            output.append(character)
            index += 1
        }
        return stripTrailingCommas(output)
    }

    private static func stripTrailingCommas(_ text: String) -> String {
        var output = ""
        let chars = Array(text)
        var index = 0
        var inString = false
        var escaped = false
        while index < chars.count {
            let character = chars[index]
            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index += 1
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index += 1
                continue
            }
            if character == "," {
                var look = index + 1
                while look < chars.count, chars[look].isWhitespace { look += 1 }
                if look < chars.count, chars[look] == "}" || chars[look] == "]" {
                    index += 1
                    continue
                }
            }
            output.append(character)
            index += 1
        }
        return output
    }
}
