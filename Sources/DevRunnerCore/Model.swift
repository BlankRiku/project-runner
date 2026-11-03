import Foundation

enum IdeaAdapter: String, Codable, Equatable, Sendable {
    case tomcat
    case npm
    case python
    case maven
    case unmapped
}

enum DebugInjection: String, Codable, Equatable, Sendable {
    case none
    case javaToolOptions
    case catalinaOpts
}

struct IdeaOrigin: Codable, Equatable, Sendable {
    var configurationName: String
    var configurationType: String
    var adapter: IdeaAdapter
}

struct RunnerConfig: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var command: String
    var workingDirectory: String
    var env: [String: String]
    var debugEnabled: Bool
    var debugPort: Int
    var portToCheck: Int?
    var commandEdited: Bool
    var idea: IdeaOrigin?
    var debugInjection: DebugInjection
    var importNote: String?
    var tomcatContextPath: String?
    var tomcatDocBase: String?

    init(
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

    init(from decoder: Decoder) throws {
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

struct Project: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var rootPath: String
    var runners: [RunnerConfig]

    init(id: UUID = UUID(), name: String, rootPath: String, runners: [RunnerConfig] = []) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.runners = runners
    }
}

enum RunnerPhase: String, Equatable, Sendable {
    case stopped
    case starting
    case running
    case crashed
}

struct RunnerRuntime: Equatable, Sendable {
    var phase: RunnerPhase
    var pid: Int32?

    static let stopped = RunnerRuntime(phase: .stopped, pid: nil)
}

struct StoreDocument: Codable, Equatable, Sendable {
    var projects: [Project]
}
