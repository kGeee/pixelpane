import Foundation

enum AssistantWorkspaceTask: String, Sendable {
    case build
    case test
    case lint
    case serve
}

enum AssistantWorkspaceFeature: String, Hashable, Sendable {
    case gitRepository
    case packageScripts
    case staticWebsite
    case xcodeProject
    case swiftPackage
    case rustPackage
    case goModule
    case pythonProject
    case modelArtifacts
    case imageCollection
    case documentCollection
}

struct AssistantWorkspaceProfile: Equatable, Sendable {
    let rootPath: String
    let grantedRootPath: String
    let displayName: String
    let features: Set<AssistantWorkspaceFeature>
    let packageScripts: Set<String>
    let evidence: [String]

    nonisolated var isStaticWebsite: Bool {
        features.contains(.staticWebsite)
    }

    nonisolated var hasPackageServeScript: Bool {
        ["dev", "start", "serve", "preview"].contains { packageScripts.contains($0) }
    }
}

struct AssistantWorkspaceProfiler: Sendable {
    private let maxDepth: Int
    private let maxVisitedEntriesPerGrant: Int

    init(maxDepth: Int = 4, maxVisitedEntriesPerGrant: Int = 2_500) {
        self.maxDepth = maxDepth
        self.maxVisitedEntriesPerGrant = maxVisitedEntriesPerGrant
    }

    nonisolated func profiles(for grants: [LocalFileGrant]) -> [AssistantWorkspaceProfile] {
        let folders = grants.filter { grant in
            grant.isDirectory && FileManager.default.fileExists(atPath: grant.path)
        }
        var seen: Set<String> = []
        var profiles: [AssistantWorkspaceProfile] = []

        for grant in folders {
            let root = URL(fileURLWithPath: grant.path).standardizedFileURL
            for candidate in candidateRoots(in: root) {
                let path = candidate.standardizedFileURL.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)
                profiles.append(profile(root: candidate, grantedRoot: root))
            }
        }

        return profiles.sorted { lhs, rhs in
            if lhs.grantedRootPath == rhs.grantedRootPath {
                return lhs.rootPath.localizedCaseInsensitiveCompare(rhs.rootPath) == .orderedAscending
            }
            return lhs.grantedRootPath.localizedCaseInsensitiveCompare(rhs.grantedRootPath) == .orderedAscending
        }
    }

    nonisolated func profile(rootPath: String) -> AssistantWorkspaceProfile {
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL
        return profile(root: root, grantedRoot: root)
    }

    private nonisolated func candidateRoots(in grantedRoot: URL) -> [URL] {
        var roots: [URL] = [grantedRoot]
        var seen: Set<String> = [grantedRoot.path]

        guard let enumerator = FileManager.default.enumerator(
            at: grantedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return roots
        }

        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > maxVisitedEntriesPerGrant {
                break
            }

            let relative = relativePath(from: grantedRoot, to: url)
            let components = relative.split(separator: "/").map(String.init)
            if shouldSkip(relativePath: relative) {
                enumerator.skipDescendants()
                continue
            }
            guard components.count <= maxDepth else {
                enumerator.skipDescendants()
                continue
            }

            let markerRoot: URL?
            if url.lastPathComponent.hasSuffix(".xcodeproj") {
                markerRoot = url.deletingLastPathComponent()
                enumerator.skipDescendants()
            } else if isWorkspaceMarker(url) {
                markerRoot = url.deletingLastPathComponent()
            } else {
                markerRoot = nil
            }

            guard let markerRoot else { continue }
            let path = markerRoot.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            roots.append(markerRoot)
        }

        return roots
    }

    private nonisolated func profile(root: URL, grantedRoot: URL) -> AssistantWorkspaceProfile {
        var features: Set<AssistantWorkspaceFeature> = []
        var evidence: [String] = []

        if exists(".git", in: root) {
            features.insert(.gitRepository)
            evidence.append(".git")
        }
        if exists("Package.swift", in: root) {
            features.insert(.swiftPackage)
            evidence.append("Package.swift")
        }
        if exists("Cargo.toml", in: root) {
            features.insert(.rustPackage)
            evidence.append("Cargo.toml")
        }
        if exists("go.mod", in: root) {
            features.insert(.goModule)
            evidence.append("go.mod")
        }
        if exists("pyproject.toml", in: root) || exists("requirements.txt", in: root) {
            features.insert(.pythonProject)
            evidence.append(exists("pyproject.toml", in: root) ? "pyproject.toml" : "requirements.txt")
        }
        if firstChild(in: root, where: { $0.pathExtension == "xcodeproj" }) != nil {
            features.insert(.xcodeProject)
            evidence.append("*.xcodeproj")
        }

        let packageScripts = packageScripts(in: root)
        if !packageScripts.isEmpty {
            features.insert(.packageScripts)
            evidence.append("package.json scripts: \(packageScripts.sorted().joined(separator: ", "))")
        }

        if isStaticWebsite(root) {
            features.insert(.staticWebsite)
            evidence.append("static website files")
        }
        if hasModelArtifacts(root) {
            features.insert(.modelArtifacts)
            evidence.append("model artifact files")
        }
        if countChildren(in: root, matchingExtensions: ["png", "jpg", "jpeg", "webp", "gif", "heic"]) >= 3 {
            features.insert(.imageCollection)
            evidence.append("image files")
        }
        if countChildren(in: root, matchingExtensions: ["pdf", "docx", "doc", "md", "txt"]) >= 3 {
            features.insert(.documentCollection)
            evidence.append("document files")
        }

        return AssistantWorkspaceProfile(
            rootPath: root.standardizedFileURL.path,
            grantedRootPath: grantedRoot.standardizedFileURL.path,
            displayName: root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent,
            features: features,
            packageScripts: packageScripts,
            evidence: evidence
        )
    }

    private nonisolated func isWorkspaceMarker(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if [
            "package.json",
            "Package.swift",
            "Cargo.toml",
            "go.mod",
            "pyproject.toml",
            "requirements.txt",
            "Makefile",
            "index.html",
            "CNAME",
            "_config.yml",
            "config.json",
            "tokenizer.json"
        ].contains(name) {
            return true
        }
        return name.hasSuffix(".safetensors") || name.hasSuffix(".gguf")
    }

    private nonisolated func packageScripts(in root: URL) -> Set<String> {
        let packageURL = root.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = object["scripts"] as? [String: Any] else {
            return []
        }
        return Set(scripts.compactMap { key, value in
            guard let script = value as? String,
                  !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !script.localizedCaseInsensitiveContains("no test specified") else {
                return nil
            }
            return key
        })
    }

    private nonisolated func isStaticWebsite(_ root: URL) -> Bool {
        guard exists("index.html", in: root) else { return false }
        if exists("CNAME", in: root) || exists("_config.yml", in: root) {
            return true
        }
        let htmlCount = countChildren(in: root, matchingExtensions: ["html"])
        let assetDirectories = ["css", "styles", "stylesheets", "js", "javascripts", "images", "assets"]
            .filter { exists($0, in: root) }
            .count
        return htmlCount >= 1 && assetDirectories >= 1
    }

    private nonisolated func hasModelArtifacts(_ root: URL) -> Bool {
        exists("config.json", in: root)
            && (exists("tokenizer.json", in: root)
                || firstChild(in: root, where: { $0.lastPathComponent.hasSuffix(".safetensors") || $0.lastPathComponent.hasSuffix(".gguf") }) != nil)
    }

    private nonisolated func exists(_ name: String, in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
    }

    private nonisolated func firstChild(in root: URL, where predicate: (URL) -> Bool) -> URL? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return children.first(where: predicate)
    }

    private nonisolated func countChildren(in root: URL, matchingExtensions extensions: Set<String>) -> Int {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return children.reduce(0) { count, url in
            count + (extensions.contains(url.pathExtension.lowercased()) ? 1 : 0)
        }
    }

    private nonisolated func shouldSkip(relativePath: String) -> Bool {
        let skipped = Set([
            ".git", "node_modules", "DerivedData", ".build", "build", "dist", ".next",
            "Library", "Applications", "System", "Volumes", "private", "dev", "Network"
        ])
        return relativePath.split(separator: "/").contains { skipped.contains(String($0)) }
    }

    private nonisolated func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path != rootPath else { return "." }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }
}

struct AssistantWorkspaceTargetResolver: Sendable {
    private let profiler: AssistantWorkspaceProfiler

    init(profiler: AssistantWorkspaceProfiler = AssistantWorkspaceProfiler()) {
        self.profiler = profiler
    }

    nonisolated func resolve(
        question: String,
        task: AssistantWorkspaceTask,
        grants: [LocalFileGrant],
        toolState: AssistantToolState
    ) -> AssistantWorkspaceProfile? {
        let profiles = profiler.profiles(for: grants)
        guard !profiles.isEmpty else { return nil }
        let normalized = normalize(question)
        let scored = profiles
            .map { profile in
                (profile, score(profile, for: normalized, task: task, toolState: toolState))
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.rootPath.count < rhs.0.rootPath.count
                }
                return lhs.1 > rhs.1
            }
        return scored.first?.0
    }

    private nonisolated func score(
        _ profile: AssistantWorkspaceProfile,
        for normalized: String,
        task: AssistantWorkspaceTask,
        toolState: AssistantToolState
    ) -> Int {
        var score = 0
        let path = profile.rootPath.lowercased()
        let name = profile.displayName.lowercased()
        let queryTokens = normalized
            .replacingOccurrences(of: #"[^a-z0-9._-]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }
        for token in queryTokens {
            if name.contains(token) { score += 24 }
            if path.contains(token) { score += 10 }
        }

        if let listed = toolState.lastListedFolder,
           isPath(profile.rootPath, inside: listed.path) || isPath(listed.path, inside: profile.rootPath) {
            score += 22
        }
        for source in toolState.grantedSourcesUsed + toolState.lastFileSources {
            if isPath(source.path, inside: profile.rootPath) || isPath(profile.rootPath, inside: source.path) {
                score += 14
            }
        }

        switch task {
        case .serve:
            if profile.hasPackageServeScript { score += 80 }
            if profile.features.contains(.staticWebsite) { score += 78 }
            if profile.features.contains(.pythonProject) { score += 20 }
            if profile.features.contains(.xcodeProject) { score -= 25 }
        case .build:
            if profile.packageScripts.contains("build") { score += 70 }
            if profile.features.contains(.xcodeProject) { score += 65 }
            if profile.features.contains(.swiftPackage) { score += 55 }
            if profile.features.contains(.rustPackage) { score += 45 }
            if profile.features.contains(.goModule) { score += 45 }
            if profile.features.contains(.staticWebsite) { score += 18 }
        case .test:
            if profile.packageScripts.contains("test") { score += 65 }
            if profile.features.contains(.swiftPackage) { score += 45 }
            if profile.features.contains(.rustPackage) { score += 45 }
            if profile.features.contains(.goModule) { score += 45 }
        case .lint:
            if profile.packageScripts.contains("lint") { score += 65 }
            if profile.packageScripts.contains("typecheck") { score += 58 }
            if profile.features.contains(.rustPackage) { score += 40 }
        }

        if normalized.contains("site") || normalized.contains("website") || normalized.contains("web site") {
            if profile.features.contains(.staticWebsite) { score += 100 }
            if profile.hasPackageServeScript { score += 40 }
            if path.contains("github.io") { score += 40 }
            if path.contains("backend") { score -= 55 }
            if profile.features.contains(.xcodeProject) { score -= 35 }
        }
        if normalized.contains("personal") {
            if path.contains("github.io") || profile.features.contains(.staticWebsite) { score += 38 }
            if path.contains("pixel-pane") { score -= 25 }
        }
        if normalized.contains("backend") || normalized.contains("server api") || normalized.contains("api server") {
            if path.contains("backend") { score += 80 }
            if profile.hasPackageServeScript { score += 25 }
        }
        if normalized.contains("app") || normalized.contains("xcode") || normalized.contains("mac app") {
            if profile.features.contains(.xcodeProject) { score += 70 }
        }
        if normalized.contains("model") || normalized.contains("local model") {
            if profile.features.contains(.modelArtifacts) { score += 90 }
        }
        if normalized.contains("image") || normalized.contains("images") || normalized.contains("photo") {
            if profile.features.contains(.imageCollection) { score += 60 }
        }

        if profile.rootPath == profile.grantedRootPath {
            score += 6
        }
        if profile.features.isEmpty {
            score -= 20
        }
        return score
    }

    private nonisolated func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func isPath(_ path: String, inside rootPath: String) -> Bool {
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        if candidate == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return candidate.hasPrefix(prefix)
    }
}
