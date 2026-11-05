import Foundation

package enum IdeaImporter {
    package static func resync(
        existing: [RunnerConfig],
        imported: [RunnerConfig],
        configRoot: URL,
        primaryRoot: String? = nil
    ) -> [RunnerConfig] {
        let primary = primaryRoot.map(Project.normalizePath)
        var pending = imported
        var result: [RunnerConfig] = []
        for runner in existing {
            guard let idea = runner.idea else {
                result.append(runner)
                continue
            }
            guard let index = pending.firstIndex(where: { matches(existing: idea, imported: $0.idea, primaryRoot: primary) }) else {
                result.append(runner)
                continue
            }
            let importedRunner = pending.remove(at: index)
            if runner.commandEdited {
                var updated = runner
                updated.name = importedRunner.name
                updated.env = rewriteBase(importedRunner.env, id: runner.id, configRoot: configRoot)
                updated.portToCheck = importedRunner.portToCheck
                if var origin = updated.idea {
                    origin.sourceRoot = importedRunner.idea?.sourceRoot ?? origin.sourceRoot
                    updated.idea = origin
                }
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

    /// Keeps manuals, updates/adds only the selected scan results, drops deselected imports.
    package static func applySelection(
        existing: [RunnerConfig],
        selected: [RunnerConfig],
        configRoot: URL,
        primaryRoot: String? = nil
    ) -> [RunnerConfig] {
        let primary = primaryRoot.map(Project.normalizePath)
        let manuals = existing.filter { $0.idea == nil }
        let relevant = existing.filter { runner in
            guard let idea = runner.idea else { return false }
            return selected.contains { matches(existing: idea, imported: $0.idea, primaryRoot: primary) }
        }
        return resync(
            existing: manuals + relevant,
            imported: selected,
            configRoot: configRoot,
            primaryRoot: primaryRoot
        )
    }

    package static func isPresent(
        scanned: RunnerConfig,
        in existing: [RunnerConfig],
        primaryRoot: String? = nil
    ) -> Bool {
        let primary = primaryRoot.map(Project.normalizePath)
        guard let scannedIdea = scanned.idea else { return false }
        return existing.contains { runner in
            guard let idea = runner.idea else { return false }
            return matches(existing: idea, imported: scannedIdea, primaryRoot: primary)
        }
    }

    private static func matches(existing: IdeaOrigin, imported: IdeaOrigin?, primaryRoot: String?) -> Bool {
        guard let imported else { return false }
        guard existing.configurationName == imported.configurationName,
              existing.configurationType == imported.configurationType else {
            return false
        }
        let importedRoot = imported.sourceRoot.map(Project.normalizePath)
        if let existingRoot = existing.sourceRoot.map(Project.normalizePath) {
            return existingRoot == importedRoot
        }
        guard let primaryRoot else { return importedRoot == nil }
        return importedRoot == primaryRoot
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
