import Foundation

enum IdeaImporter {
    static func resync(existing: [RunnerConfig], imported: [RunnerConfig], configRoot: URL) -> [RunnerConfig] {
        var pending = imported
        var result: [RunnerConfig] = []
        for runner in existing {
            guard let idea = runner.idea else {
                result.append(runner)
                continue
            }
            guard let index = pending.firstIndex(where: {
                $0.idea?.configurationName == idea.configurationName &&
                $0.idea?.configurationType == idea.configurationType
            }) else {
                result.append(runner)
                continue
            }
            let importedRunner = pending.remove(at: index)
            if runner.commandEdited {
                var updated = runner
                updated.name = importedRunner.name
                updated.env = rewriteBase(importedRunner.env, id: runner.id, configRoot: configRoot)
                updated.portToCheck = importedRunner.portToCheck
                result.append(updated)
            } else {
                var updated = importedRunner
                updated.id = runner.id
                updated.debugEnabled = runner.debugEnabled
                updated.commandEdited = false
                updated.env = rewriteBase(updated.env, id: runner.id, configRoot: configRoot)
                result.append(updated)
            }
        }
        result.append(contentsOf: pending)
        return result
    }

    private static func rewriteBase(_ env: [String: String], id: UUID, configRoot: URL) -> [String: String] {
        var env = env
        if env["CATALINA_BASE"] != nil {
            env["CATALINA_BASE"] = configRoot
                .appendingPathComponent("catalina")
                .appendingPathComponent(id.uuidString)
                .path
        }
        return env
    }
}
