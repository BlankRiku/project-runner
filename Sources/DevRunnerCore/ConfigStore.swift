import Foundation

struct ConfigStore: Sendable {
    var fileURL: URL
    private(set) var isCorrupt = false

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dev-runner/config.json")
    }

    static var defaultConfigRoot: URL {
        defaultFileURL.deletingLastPathComponent()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    mutating func load() -> [Project] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            isCorrupt = false
            return []
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            isCorrupt = true
            return []
        }
        do {
            let document = try JSONDecoder().decode(StoreDocument.self, from: data)
            isCorrupt = false
            return document.projects
        } catch {
            isCorrupt = true
            return []
        }
    }

    mutating func save(_ projects: [Project]) throws {
        if isCorrupt { return }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(StoreDocument(projects: projects))
        try writeAtomic(data, to: fileURL)
    }

    func prepareForOpen() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { return }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeAtomic(Data("{\"projects\":[]}".utf8), to: fileURL)
    }

    private func writeAtomic(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temp)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}
