import Foundation
import CryptoKit

/// One Claude Code config folder (a signed-in account). Read-only metadata.
struct ClaudeProfile: Equatable {
    let directory: URL
    let isDefault: Bool
    /// Overrides the hashed string (CLAUDE_SECURESTORAGE_CONFIG_DIR), if the environment sets it.
    var secureStorageDirectory: String? = nil

    var path: String { Self.trimmed(directory.path) }
    var id: String { isDefault ? "claude" : "claude:" + path }
    var projectsRoot: URL { directory.appendingPathComponent("projects", isDirectory: true) }

    static func trimmed(_ path: String) -> String {
        var value = path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// Keychain services to try, in order. Default: plain service. Custom: SHA-256 prefix of the
    /// directory string (NFC), exactly as given, then with a trailing slash.
    var keychainServices: [String] {
        guard !isDefault else { return ["Claude Code-credentials"] }
        let base = secureStorageDirectory.map(Self.trimmed) ?? path
        return [base, base + "/"].map { Self.service(forDirectory: $0) }
    }

    static func service(forDirectory string: String) -> String {
        let hash = SHA256.hash(data: Data(string.precomposedStringWithCanonicalMapping.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(hash.prefix(8))"
    }

    /// Default profile keeps its metadata in ~/.claude.json, custom ones in <dir>/.claude.json.
    func metadataURL(home: URL) -> URL {
        isDefault ? home.appendingPathComponent(".claude.json") : directory.appendingPathComponent(".claude.json")
    }

    func label(home: URL) -> String {
        if let data = try? Data(contentsOf: metadataURL(home: home)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let account = json["oauthAccount"] as? [String: Any],
           let email = account["emailAddress"] as? String, !email.trimmingCharacters(in: .whitespaces).isEmpty {
            return email
        }
        return isDefault ? "Claude" : directory.lastPathComponent
    }

    /// Path shown in hints, with the home folder abbreviated.
    func displayPath(home: URL) -> String {
        let prefix = Self.trimmed(home.path)
        return path.hasPrefix(prefix + "/") ? "~" + path.dropFirst(prefix.count) : path
    }

    /// Default first, then env profile, then home `.claude*` folders by name. Deduplicated by resolved path.
    static func discover(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                         environment: [String: String] = ProcessInfo.processInfo.environment,
                         fileManager: FileManager = .default) -> [ClaudeProfile] {
        var profiles = [ClaudeProfile(directory: home.appendingPathComponent(".claude"), isDefault: true)]
        var seen: Set<String> = [resolved(profiles[0].directory)]
        func add(_ profile: ClaudeProfile) {
            if seen.insert(resolved(profile.directory)).inserted { profiles.append(profile) }
        }
        let secure = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        if let env = environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            add(ClaudeProfile(directory: URL(fileURLWithPath: trimmed(env), isDirectory: true), isDefault: false, secureStorageDirectory: secure))
        }
        let names = ((try? fileManager.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { $0.hasPrefix(".claude") && $0 != ".claude" }
            .sorted()
        for name in names {
            let directory = home.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  fileManager.fileExists(atPath: directory.appendingPathComponent(".claude.json").path)
                    || fileManager.fileExists(atPath: directory.appendingPathComponent(".credentials.json").path) else { continue }
            add(ClaudeProfile(directory: directory, isDefault: false))
        }
        return profiles
    }

    private static func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// A quota card: one Claude profile, or Codex.
struct SubscriptionAccount: Equatable, Identifiable {
    let id: String
    let provider: SubscriptionProvider
    let label: String
    let profile: ClaudeProfile?

    static let codexAccount = SubscriptionAccount(id: "codex", provider: .codex, label: "Codex", profile: nil)
    static let defaultClaude = SubscriptionAccount(id: "claude", provider: .claude, label: "Claude",
        profile: ClaudeProfile(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"), isDefault: true))
}
