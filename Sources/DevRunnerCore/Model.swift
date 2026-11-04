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
    package var runners: [RunnerConfig]

    package init(id: UUID = UUID(), name: String, rootPath: String, runners: [RunnerConfig] = []) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.runners = runners
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
