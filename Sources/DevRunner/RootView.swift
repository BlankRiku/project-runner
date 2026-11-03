import AppKit
import DevRunnerCore
import SwiftUI

enum Theme {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let card = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let text = Color.white
    static let secondary = Color(white: 0.68)
    static let pill = Color(red: 0.22, green: 0.24, blue: 0.30)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var logsRunnerID: UUID?
    @State private var adding = false
    @State private var editing: RunnerConfig?

    var body: some View {
        Group {
            if let logsRunnerID, model.locate(logsRunnerID) != nil {
                LogsView(runnerID: logsRunnerID) { self.logsRunnerID = nil }
            } else {
                projectList
            }
        }
        .frame(width: 400)
        .frame(maxHeight: 640)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $adding) { AddProjectSheet(isPresented: $adding).environmentObject(model) }
        .sheet(item: $editing) { runner in EditRunnerSheet(runner: runner).environmentObject(model) }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                Text("Dev Runner").font(.headline)
                Spacer()
                Text("\(model.activeCount) attivo")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.pill, in: Capsule())
            }
            .foregroundStyle(Theme.text)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.projects.isEmpty {
                        Text("Nessun progetto").foregroundStyle(Theme.secondary)
                    }
                    ForEach(model.projects) { project in
                        ProjectBlock(project: project, onLogs: { logsRunnerID = $0 }, onEdit: { editing = $0 })
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                footer("+ Aggiungi Progetto") { adding = true }
                footer("Termina Tutti") { model.session.stopAll() }
                footer("Apri config.json") { openConfig() }
                footer("Esci") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .foregroundStyle(Theme.text)
    }

    private func footer(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openConfig() {
        guard let url = try? model.session.configFileURLForOpen() else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ProjectBlock: View {
    @EnvironmentObject private var model: AppModel
    var project: Project
    var onLogs: (UUID) -> Void
    var onEdit: (RunnerConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name).font(.headline)
            Text(project.rootPath).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
            HStack {
                Button("Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: project.rootPath)) }
                Button("Terminale") { openTerminal(project.rootPath) }
                Button("Sincronizza da .idea") { model.session.resync(projectID: project.id) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            ForEach(project.runners) { runner in
                RunnerRow(project: project, runner: runner, onLogs: { onLogs(runner.id) }, onEdit: { onEdit(runner) })
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private func openTerminal(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        try? process.run()
    }
}

private struct RunnerRow: View {
    @EnvironmentObject private var model: AppModel
    var project: Project
    var runner: RunnerConfig
    var onLogs: () -> Void
    var onEdit: () -> Void

    var body: some View {
        let phase = model.runtime(for: runner.id).phase
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StatusDot(phase: phase)
                Text(runner.name).lineLimit(1)
                Spacer()
                if let pid = model.runtime(for: runner.id).pid, phase == .running || phase == .starting {
                    Text("pid \(pid)").font(.caption).foregroundStyle(Theme.secondary)
                }
                if let port = runner.portToCheck {
                    Text(":\(port)").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            if runner.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Comando da completare").font(.caption).foregroundStyle(Theme.secondary)
                if let note = runner.importNote {
                    Text(note).font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                Toggle("Debug", isOn: Binding(
                    get: { runner.debugEnabled },
                    set: { model.session.setDebugEnabled($0, runnerID: runner.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                if runner.debugInjection != .none {
                    Text(":\(runner.debugPort)").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                Button(phase == .running || phase == .starting ? "Stop" : "Start") {
                    if phase == .running || phase == .starting {
                        model.session.stop(runnerID: runner.id)
                    } else {
                        model.session.start(projectID: project.id, runnerID: runner.id)
                    }
                }
                Button("Restart") { model.session.restart(projectID: project.id, runnerID: runner.id) }
                Button("Logs") { onLogs() }
                Button("Edit") { onEdit() }
                if runner.portToCheck != nil {
                    Button("Libera porta") { model.session.freePort(runnerID: runner.id) }
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}

private struct StatusDot: View {
    var phase: RunnerPhase
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
    private var color: Color {
        switch phase {
        case .stopped: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .crashed: return .red
        }
    }
}

private struct LogsView: View {
    @EnvironmentObject private var model: AppModel
    var runnerID: UUID
    var onBack: () -> Void
    @State private var query = ""

    var body: some View {
        let runner = model.locate(runnerID)?.runner
        let lines = model.logs(for: runnerID).filtered(query: query)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Indietro", action: onBack).buttonStyle(.borderless)
                Text(runner?.name ?? "").font(.headline)
                StatusDot(phase: model.runtime(for: runnerID).phase)
                if let port = runner?.portToCheck { Text(":\(port)").font(.caption) }
                Spacer()
            }
            HStack {
                TextField("Cerca", text: $query).textFieldStyle(.roundedBorder)
                Button("Clear") { model.session.clearLog(runnerID: runnerID) }
                Button("Copy") { copy(lines) }
            }
            .buttonStyle(.borderless)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                }
                .background(Color.black)
                .onAppear { scroll(proxy, lines: lines) }
                .onChange(of: lines.count) { _ in scroll(proxy, lines: lines) }
            }
        }
        .padding(12)
        .foregroundStyle(Theme.text)
    }

    private func scroll(_ proxy: ScrollViewProxy, lines: [String]) {
        if let last = lines.indices.last { proxy.scrollTo(last, anchor: .bottom) }
    }

    private func copy(_ lines: [String]) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

private struct AddProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var folder = ""
    @State private var found: [RunnerConfig] = []
    @State private var selected: Set<UUID> = []
    @State private var scanned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aggiungi Progetto").font(.headline)
            TextField("Nome", text: $name)
            HStack {
                TextField("Cartella", text: $folder)
                Button("Sfoglia") { browse() }
            }
            Text("Trovate in .idea").font(.subheadline)
            if scanned && found.isEmpty {
                Text("Nessuna configurazione in .idea").foregroundStyle(Theme.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(found) { runner in
                        Toggle(isOn: binding(runner.id)) {
                            VStack(alignment: .leading) {
                                Text(runner.name)
                                if runner.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Comando da completare").font(.caption)
                                    if let note = runner.importNote { Text(note).font(.caption2) }
                                } else {
                                    Text(runner.command).font(.caption.monospaced()).lineLimit(1)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            HStack {
                Button("Annulla") { isPresented = false }
                Spacer()
                Button("Runner manuale") { createManual() }.disabled(folder.isEmpty)
                Button("Importa selezionate") { importSelected() }
                    .disabled(folder.isEmpty || found.filter { selected.contains($0.id) }.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420, height: 460)
        .preferredColorScheme(.dark)
        .onChange(of: folder) { _ in scanIfDirectory() }
    }

    private func binding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { isOn in
            if isOn { selected.insert(id) } else { selected.remove(id) }
        })
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Scegli"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }

    private func scanIfDirectory() {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
            found = []
            selected = []
            scanned = false
            return
        }
        let result = IdeaScanner.scan(IdeaScanRequest(
            projectRoot: URL(fileURLWithPath: folder, isDirectory: true),
            configRoot: model.session.configRoot,
            userHome: model.session.userHome
        ))
        found = result.runners
        selected = Set(found.map(\.id))
        scanned = true
    }

    private func resolvedName() -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return URL(fileURLWithPath: folder).lastPathComponent
    }

    private func importSelected() {
        let chosen = found.filter { selected.contains($0.id) }
        model.session.addProject(Project(name: resolvedName(), rootPath: folder, runners: chosen))
        isPresented = false
    }

    private func createManual() {
        let title = resolvedName()
        let runner = RunnerConfig(name: title, command: "", workingDirectory: folder, debugPort: 5005)
        model.session.addProject(Project(name: title, rootPath: folder, runners: [runner]))
        isPresented = false
    }
}

private struct EditRunnerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let original: RunnerConfig
    @State private var name: String
    @State private var command: String
    @State private var workingDirectory: String
    @State private var portText: String
    @State private var debugPortText: String
    @State private var debugEnabled: Bool
    @State private var envRows: [EnvRow]

    init(runner: RunnerConfig) {
        original = runner
        _name = State(initialValue: runner.name)
        _command = State(initialValue: runner.command)
        _workingDirectory = State(initialValue: runner.workingDirectory)
        _portText = State(initialValue: runner.portToCheck.map(String.init) ?? "")
        _debugPortText = State(initialValue: String(runner.debugPort))
        _debugEnabled = State(initialValue: runner.debugEnabled)
        _envRows = State(initialValue: runner.env.keys.sorted().map { EnvRow(key: $0, value: runner.env[$0] ?? "") })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modifica runner").font(.headline)
            TextField("Nome", text: $name)
            Text("Comando").font(.caption)
            TextEditor(text: $command).font(.system(.body, design: .monospaced)).frame(minHeight: 80)
            TextField("Cartella di lavoro", text: $workingDirectory)
            TextField("Porta da controllare", text: $portText)
            TextField("Porta debug", text: $debugPortText)
            Toggle("Debug", isOn: $debugEnabled)
            Text("Variabili").font(.caption)
            ForEach($envRows) { $row in
                HStack {
                    TextField("Nome", text: $row.key)
                    TextField("Valore", text: $row.value)
                    Button("Rimuovi") { envRows.removeAll { $0.id == row.id } }
                }
            }
            Button("Aggiungi") { envRows.append(EnvRow(key: "", value: "")) }
            HStack {
                Button("Annulla") { dismiss() }
                Spacer()
                Button("Salva") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
        .preferredColorScheme(.dark)
    }

    private func save() {
        var updated = original
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.command = command
        updated.workingDirectory = workingDirectory
        let trimmedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPort.isEmpty {
            updated.portToCheck = nil
        } else if let port = Int(trimmedPort) {
            updated.portToCheck = port
        }
        let trimmedDebug = debugPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let port = Int(trimmedDebug) { updated.debugPort = port }
        updated.debugEnabled = debugEnabled
        var env: [String: String] = [:]
        for row in envRows {
            let key = row.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { env[key] = row.value }
        }
        updated.env = env
        model.session.updateRunner(updated, commandDidChange: command != original.command)
        dismiss()
    }
}

private struct EnvRow: Identifiable, Equatable {
    var id = UUID()
    var key: String
    var value: String
}
