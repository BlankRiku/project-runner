import Foundation

package enum IdeaAdapter: String, Codable, Equatable, Sendable {
    case tomcat
    case npm
    case python
    case maven
    case unmapped
    case vscode
}

package enum DebugInjection: String, Codable, Equatable, Sendable {
    case none
    case javaToolOptions
    case catalinaOpts
}

package struct IdeaOrigin: Codable, Equatable, Sendable {
    package var configurationName: String
    package var configurationType: String
    package var adapter: IdeaAdapter
    package var sourceRoot: String?

    package init(
        configurationName: String,
        configurationType: String,
        adapter: IdeaAdapter,
        sourceRoot: String? = nil
    ) {
        self.configurationName = configurationName
        self.configurationType = configurationType
        self.adapter = adapter
        self.sourceRoot = sourceRoot
    }
}

package struct RunnerConfig: Codable, Equatable, Sendable, Identifiable {
    package var id: UUID
    package var name: String
    package var command: String
    package var workingDirectory: String
    package var env: [String: String]
    package var debugEnabled: Bool
    package var debugPort: Int
    package var portToCheck: Int?
    package var commandEdited: Bool
    package var idea: IdeaOrigin?
    package var debugInjection: DebugInjection
    package var importNote: String?
    package var tomcatContextPath: String?
    package var tomcatDocBase: String?

    package init(
        id: UUID = UUID(),
        name: String,
        command: String,
        workingDirectory: String,
        env: [String: String] = [:],
        debugEnabled: Bool = false,
        debugPort: Int = 5005,
        portToCheck: Int? = nil,
        commandEdited: Bool = false,
        idea: IdeaOrigin? = nil,
        debugInjection: DebugInjection = .none,
        importNote: String? = nil,
        tomcatContextPath: String? = nil,
        tomcatDocBase: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.workingDirectory = workingDirectory
        self.env = env
        self.debugEnabled = debugEnabled
        self.debugPort = debugPort
        self.portToCheck = portToCheck
        self.commandEdited = commandEdited
        self.idea = idea
        self.debugInjection = debugInjection
        self.importNote = importNote
        self.tomcatContextPath = tomcatContextPath
        self.tomcatDocBase = tomcatDocBase
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, command, workingDirectory, env, debugEnabled, debugPort
        case portToCheck, commandEdited, idea, debugInjection, importNote
        case tomcatContextPath, tomcatDocBase
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        debugEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugEnabled) ?? false
        debugPort = try container.decodeIfPresent(Int.self, forKey: .debugPort) ?? 5005
        portToCheck = try container.decodeIfPresent(Int.self, forKey: .portToCheck)
        commandEdited = try container.decodeIfPresent(Bool.self, forKey: .commandEdited) ?? false
        idea = try container.decodeIfPresent(IdeaOrigin.self, forKey: .idea)
        debugInjection = try container.decodeIfPresent(DebugInjection.self, forKey: .debugInjection) ?? .none
        importNote = try container.decodeIfPresent(String.self, forKey: .importNote)
        tomcatContextPath = try container.decodeIfPresent(String.self, forKey: .tomcatContextPath)
        tomcatDocBase = try container.decodeIfPresent(String.self, forKey: .tomcatDocBase)
    }
}

package struct Project: Codable, Equatable, Sendable, Identifiable {
    package var id: UUID
    package var name: String
    package var rootPath: String
    package var roots: [String]
    package var runners: [RunnerConfig]

    package init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        roots: [String]? = nil,
        runners: [RunnerConfig] = []
    ) {
        self.id = id
        self.name = name
        let resolved = Self.normalizedRoots(roots ?? [rootPath], fallback: rootPath)
        self.roots = resolved
        self.rootPath = resolved[0]
        self.runners = runners
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rootPath, roots, runners
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let decodedRoot = try container.decode(String.self, forKey: .rootPath)
        let decodedRoots = try container.decodeIfPresent([String].self, forKey: .roots)
        let resolved = Self.normalizedRoots(decodedRoots ?? [decodedRoot], fallback: decodedRoot)
        roots = resolved
        rootPath = resolved[0]
        runners = try container.decodeIfPresent([RunnerConfig].self, forKey: .runners) ?? []
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(roots[0], forKey: .rootPath)
        try container.encode(roots, forKey: .roots)
        try container.encode(runners, forKey: .runners)
    }

    /// Keeps `rootPath` aligned with the first folder after roots change.
    package mutating func setRoots(_ paths: [String]) {
        let resolved = Self.normalizedRoots(paths, fallback: rootPath)
        roots = resolved
        rootPath = resolved[0]
    }

    private static func normalizedRoots(_ paths: [String], fallback: String) -> [String] {
        let cleaned = paths
            .map { normalizePath($0) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            let fallbackPath = normalizePath(fallback)
            return fallbackPath.isEmpty ? ["/"] : [fallbackPath]
        }
        var seen = Set<String>()
        var unique: [String] = []
        for path in cleaned where seen.insert(path).inserted {
            unique.append(path)
        }
        return unique
    }

    package static func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let url = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
        var result = url.path
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

package enum RunnerPhase: String, Equatable, Sendable {
    case stopped
    case starting
    case running
    case crashed
}

package struct RunnerRuntime: Equatable, Sendable {
    package var phase: RunnerPhase
    package var pid: Int32?

    static let stopped = RunnerRuntime(phase: .stopped, pid: nil)
}

struct StoreDocument: Codable, Equatable, Sendable {
    var projects: [Project]
}
