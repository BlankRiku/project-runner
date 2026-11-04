import AppKit
import DevRunnerCore
import SwiftUI

enum Theme {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let card = Color(red: 0.17, green: 0.17, blue: 0.18)
    static let runner = Color.white.opacity(0.04)
    static let button = Color.white.opacity(0.06)
    static let text = Color.white
    static let secondary = Color(white: 0.62)
    static let line = Color.white.opacity(0.12)
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var notices = PopoverNotices.shared
    @State private var logsRunnerID: UUID?

    var body: some View {
        Group {
            if let logsRunnerID, model.locate(logsRunnerID) != nil {
                LogsView(runnerID: logsRunnerID) { self.logsRunnerID = nil }
            } else {
                projectList
            }
        }
        // Fixed panel size so lista ↔ log does not resize (and shift) the MenuBarExtra window.
        .frame(width: Self.panelWidth, height: Self.panelHeight, alignment: .top)
        .background(Theme.background)
        .fitMenuBarPanel(
            width: Self.panelWidth,
            maxHeight: Self.panelHeight,
            placementToken: panelPlacementToken
        )
        .preferredColorScheme(.dark)
    }

    private static let panelWidth: CGFloat = 400
    private static let panelHeight: CGFloat = 560

    private var panelPlacementToken: Int {
        var hasher = Hasher()
        hasher.combine(logsRunnerID)
        hasher.combine(notices.confirm?.id)
        hasher.combine(notices.current?.id)
        return hasher.finalize()
    }

    private var activeSummary: String {
        switch model.activeCount {
        case 0: return "Nessuno attivo"
        case 1: return "1 attivo"
        default: return "\(model.activeCount) attivi"
        }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                MenuBarMark(height: 16)
                Text("Dev Runner").font(.headline)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Circle()
                        .fill(model.activeCount > 0 ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(activeSummary)
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(model.activeCount > 0 ? Color.green.opacity(0.22) : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(model.activeCount > 0 ? Color.green : Theme.secondary)
            }
            .foregroundStyle(Theme.text)
            Divider().overlay(Theme.line)
            // Notices overlay the body so the MenuBarExtra panel height (and Y) stay put.
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    // A ScrollView's ideal height inside MenuBarExtra is about zero, so the rows never appear.
                    MenuBarColumn(maxHeight: 400) {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.projects.isEmpty {
                                Text("Nessun progetto").foregroundStyle(Theme.secondary)
                            }
                            ForEach(model.projects) { project in
                                ProjectBlock(project: project, onLogs: { logsRunnerID = $0 }, onEdit: { edit($0) })
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Divider().overlay(Theme.line)
                    HStack {
                        Button(action: addProject) {
                            Label("Aggiungi Progetto", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(action: { model.session.stopAll() }) {
                            Label("Termina Tutti", systemImage: "stop.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .disabled(model.activeCount == 0)
                    }
                    .font(.caption.weight(.semibold))
                    HStack {
                        Button(action: openConfig) {
                            Label("Apri config.json", systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        Spacer()
                        Button(action: { NSApplication.shared.terminate(nil) }) {
                            Label("Esci", systemImage: "power")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondary)
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if let confirm = notices.confirm {
                    PopoverConfirmCard(
                        prompt: confirm,
                        onCancel: { notices.cancelConfirm() },
                        onConfirm: { notices.performConfirm() }
                    )
                    .background(Theme.background)
                } else if let notice = notices.current {
                    PopoverBanner(notice: notice) {
                        notices.dismiss(notice.id)
                    }
                    .background(Theme.background)
                }
            }
        }
        .padding(12)
        .foregroundStyle(Theme.text)
    }

    private func openConfig() {
        guard let url = try? model.session.configFileURLForOpen() else { return }
        NSWorkspace.shared.open(url)
    }

    private func addProject() {
        FormWindowPresenter.shared.present(
            title: "Aggiungi Progetto",
            content: AddProjectSheet(onClose: { FormWindowPresenter.shared.close() })
                .environmentObject(model)
        )
    }

    private func edit(_ runner: RunnerConfig) {
        FormWindowPresenter.shared.present(
            title: "Modifica runner",
            content: EditRunnerSheet(runner: runner, onClose: { FormWindowPresenter.shared.close() })
                .environmentObject(model)
        )
    }
}

private struct ProjectBlock: View {
    @EnvironmentObject private var model: AppModel
    var project: Project
    var onLogs: (UUID) -> Void
    var onEdit: (RunnerConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text(projectIsActive ? "Attivo" : "Fermo")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(projectIsActive ? Color.green.opacity(0.2) : Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(projectIsActive ? Color.green : Theme.secondary)
            }
            Text(project.rootPath)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 4) {
                WordButton(title: "Finder", systemImage: "folder", help: "Apri la cartella nel Finder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.rootPath))
                }
                WordButton(title: "Terminale", systemImage: "terminal", help: "Apri la cartella nel Terminale") {
                    openTerminal(project.rootPath)
                }
                WordButton(title: "Sincronizza", systemImage: "arrow.triangle.2.circlepath", help: "Sincronizza le run configuration di IntelliJ") {
                    model.session.resync(projectID: project.id)
                }
                Spacer(minLength: 8)
                WordButton(title: "Elimina", systemImage: "trash", help: "Elimina il progetto", role: .destructive) {
                    confirmDelete()
                }
            }
            if !project.runners.isEmpty {
                Divider().overlay(Theme.line)
            }
            ForEach(project.runners) { runner in
                RunnerRow(project: project, runner: runner, onLogs: { onLogs(runner.id) }, onEdit: { onEdit(runner) })
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private var projectIsActive: Bool {
        project.runners.contains { runner in
            let phase = model.runtime(for: runner.id).phase
            return phase == .running || phase == .starting
        }
    }

    private func openTerminal(_ path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        try? process.run()
    }

    private func confirmDelete() {
        let name = project.name
        let projectID = project.id
        let liveCount = project.runners.filter { runner in
            let phase = model.runtime(for: runner.id).phase
            return phase == .running || phase == .starting
        }.count
        var detail = "Il progetto «\(name)» verrà eliminato."
        if liveCount == 1 {
            detail += " Il runner avviato verrà fermato."
        } else if liveCount > 1 {
            detail += " I runner avviati verranno fermati."
        }
        PopoverNotices.shared.askConfirm(
            title: "Eliminare il progetto «\(name)»?",
            detail: detail
        ) {
            model.session.removeProject(projectID: projectID)
            PopoverNotices.shared.show("Progetto eliminato")
        }
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
        let live = phase == .running || phase == .starting
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(runner.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if runner.debugInjection != .none {
                    Text(":\(plain(runner.debugPort))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.cyan)
                }
                Text("Debug").font(.caption).foregroundStyle(Theme.secondary)
                Toggle("", isOn: Binding(
                    get: { runner.debugEnabled },
                    set: { model.session.setDebugEnabled($0, runnerID: runner.id) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Debug JDWP")
            }
            HStack(spacing: 6) {
                StatusDot(phase: phase)
                Text(phase.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(phase == .stopped ? Theme.secondary : phase.tint)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let pid = model.runtime(for: runner.id).pid, live {
                    Text("PID \(String(pid))").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                if let port = runner.portToCheck {
                    Text(":\(plain(port))").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if runner.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Comando da completare").font(.caption).foregroundStyle(.orange)
                if let note = runner.importNote {
                    Text(note).font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    WordButton(
                        title: live ? "Ferma" : "Avvia",
                        systemImage: live ? "stop.fill" : "play.fill",
                        help: live ? "Ferma il runner" : "Avvia il runner",
                        role: live ? .stop : .start,
                        fillsRow: true
                    ) {
                        if live {
                            model.session.stop(runnerID: runner.id)
                        } else {
                            reportStartFailure(
                                model.session.start(projectID: project.id, runnerID: runner.id)
                            )
                        }
                    }
                    WordButton(
                        title: "Riavvia",
                        systemImage: "arrow.clockwise",
                        help: "Riavvia il runner",
                        fillsRow: true,
                        isEnabled: phase != .stopped
                    ) {
                        reportStartFailure(
                            model.session.restart(projectID: project.id, runnerID: runner.id)
                        )
                    }
                    WordButton(title: "Log", systemImage: "doc.text", help: "Apri il log", fillsRow: true, action: onLogs)
                }
                HStack(spacing: 6) {
                    WordButton(title: "Modifica", systemImage: "pencil", help: "Modifica il runner", fillsRow: true, action: onEdit)
                    WordButton(
                        title: "Libera porta",
                        systemImage: "network.slash",
                        help: runner.portToCheck.map { "Libera la porta \($0)" } ?? "Nessuna porta da liberare",
                        fillsRow: true,
                        isEnabled: runner.portToCheck != nil
                    ) {
                        model.session.freePort(runnerID: runner.id)
                    }
                    WordButton(
                        title: "Elimina",
                        systemImage: "trash",
                        help: "Elimina la configurazione",
                        role: .destructive,
                        fillsRow: true
                    ) {
                        confirmDelete(phase)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.runner, in: RoundedRectangle(cornerRadius: 8))
    }

    private func confirmDelete(_ phase: RunnerPhase) {
        let name = runner.name
        let runnerID = runner.id
        var detail = "La configurazione «\(name)» verrà eliminata."
        if phase == .running {
            detail += " Il runner è in esecuzione e verrà fermato."
        } else if phase == .starting {
            detail += " Il runner è in avvio e verrà fermato."
        }
        PopoverNotices.shared.askConfirm(
            title: "Eliminare «\(name)»?",
            detail: detail
        ) {
            model.session.removeRunner(runnerID: runnerID)
            PopoverNotices.shared.show("Configurazione eliminata")
        }
    }

    private func reportStartFailure(_ message: String?) {
        guard let message else { return }
        PopoverNotices.shared.showError("«\(runner.name)»: \(message)")
    }

    private func plain(_ value: Int) -> String { String(value) }
}

private enum WordRole {
    case normal, start, stop, destructive
}

private struct WordButton: View {
    var title: String
    var systemImage: String
    var help: String
    var role: WordRole = .normal
    var fillsRow = false
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(fillsRow ? 0.8 : 1)
                if fillsRow {
                    Spacer(minLength: 0)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: fillsRow ? .infinity : nil, minHeight: 26, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .help(help)
        .frame(maxWidth: fillsRow ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: !fillsRow, vertical: false)
        .accessibilityLabel(title)
    }

    private var fill: Color {
        switch role {
        case .normal, .destructive: return Theme.button
        case .start: return Color.blue.opacity(0.92)
        case .stop: return Color.red.opacity(0.88)
        }
    }

    private var foreground: Color {
        switch role {
        case .normal: return Theme.text
        case .start, .stop: return .white
        case .destructive: return .red
        }
    }

    private var border: Color {
        switch role {
        case .normal: return Theme.line
        case .start: return Color.blue.opacity(0.95)
        case .stop: return Color.red.opacity(0.95)
        case .destructive: return Color.red.opacity(0.45)
        }
    }
}

private extension RunnerPhase {
    var label: String {
        switch self {
        case .stopped: return "Fermo"
        case .starting: return "Avvio"
        case .running: return "In esecuzione"
        case .crashed: return "Errore"
        }
    }

    var tint: Color {
        switch self {
        case .stopped: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .crashed: return .red
        }
    }
}

private struct StatusDot: View {
    var phase: RunnerPhase
    var body: some View {
        Circle().fill(phase.tint).frame(width: 8, height: 8)
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
                Text(runner?.name ?? "").font(.headline).lineLimit(1)
                StatusDot(phase: model.runtime(for: runnerID).phase)
                if let port = runner?.portToCheck {
                    Text(":\(String(port))").font(.caption.monospacedDigit())
                }
                Spacer()
            }
            HStack {
                TextField("Cerca", text: $query).textFieldStyle(.roundedBorder)
                Button("Svuota") { model.session.clearLog(runnerID: runnerID) }
                Button("Copia") { copy(lines) }
            }
            .buttonStyle(.borderless)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color(white: 0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onAppear { scroll(proxy, lines: lines) }
                .onChange(of: lines.count) { _ in scroll(proxy, lines: lines) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    var onClose: () -> Void
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
            Text("Run configuration di IntelliJ").font(.subheadline)
            if scanned && found.isEmpty {
                Text("Nessuna run configuration di IntelliJ").foregroundStyle(Theme.secondary)
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
                Button("Annulla") { onClose() }
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
        if let url = DirectoryPicker.chooseDirectory() {
            folder = url.path
        }
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
        PopoverNotices.shared.show("Progetto aggiunto")
        onClose()
    }

    private func createManual() {
        let title = resolvedName()
        let runner = RunnerConfig(name: title, command: "", workingDirectory: folder, debugPort: 5005)
        model.session.addProject(Project(name: title, rootPath: folder, runners: [runner]))
        PopoverNotices.shared.show("Progetto aggiunto")
        onClose()
    }
}

private struct EditRunnerSheet: View {
    @EnvironmentObject private var model: AppModel
    let original: RunnerConfig
    var onClose: () -> Void
    @State private var name: String
    @State private var command: String
    @State private var workingDirectory: String
    @State private var portText: String
    @State private var debugPortText: String
    @State private var debugEnabled: Bool
    @State private var envRows: [EnvRow]

    init(runner: RunnerConfig, onClose: @escaping () -> Void) {
        original = runner
        self.onClose = onClose
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
            HStack {
                TextField("Cartella di lavoro", text: $workingDirectory)
                Button("Sfoglia") {
                    if let url = DirectoryPicker.chooseDirectory() {
                        workingDirectory = url.path
                    }
                }
            }
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
                Button("Annulla") { onClose() }
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
        onClose()
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuBarColumn<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var uncapped: CGFloat = 0

    var body: some View {
        Group {
            if uncapped > maxHeight {
                ScrollView { content() }
                    .frame(height: maxHeight)
            } else {
                content()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(ContentHeightKey.self) { newHeight in
            guard uncapped <= maxHeight, abs(newHeight - uncapped) > 0.5 else { return }
            uncapped = newHeight
        }
    }
}

private struct EnvRow: Identifiable, Equatable {
    var id = UUID()
    var key: String
    var value: String
}
