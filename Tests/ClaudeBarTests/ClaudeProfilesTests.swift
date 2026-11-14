import XCTest
import CryptoKit
@testable import ClaudeBar

final class ClaudeProfilesTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("quota-profiles-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: home) }

    private func makeDir(_ name: String, files: [String: String] = [:]) throws {
        let dir = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (file, text) in files { try Data(text.utf8).write(to: dir.appendingPathComponent(file)) }
    }

    func testDiscoveryDefaultFirstThenSortedAndFiltered() throws {
        try makeDir(".claude")
        try makeDir(".claude-work", files: [".claude.json": "{}"])
        try makeDir(".claude-2", files: [".credentials.json": "{}"])
        try makeDir(".claude-empty")
        try makeDir(".claudette-other-thing-no-files")
        try Data("{}".utf8).write(to: home.appendingPathComponent(".claude-file.json"))
        let profiles = ClaudeProfile.discover(home: home, environment: [:])
        XCTAssertEqual(profiles.map { $0.directory.lastPathComponent }, [".claude", ".claude-2", ".claude-work"])
        XCTAssertEqual(profiles.map(\.isDefault), [true, false, false])
        XCTAssertEqual(profiles[0].id, "claude")
    }

    func testDiscoverySingleAccountWhenNothingElseExists() {
        XCTAssertEqual(ClaudeProfile.discover(home: home, environment: [:]).count, 1)
    }

    func testEnvProfileIsHonoredAndDeduplicated() throws {
        try makeDir(".claude-2", files: [".claude.json": "{}"])
        let elsewhere = home.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        var profiles = ClaudeProfile.discover(home: home, environment: ["CLAUDE_CONFIG_DIR": elsewhere.path + "/"])
        XCTAssertEqual(profiles.map { $0.directory.lastPathComponent }, [".claude", "elsewhere", ".claude-2"])
        profiles = ClaudeProfile.discover(home: home, environment: ["CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude-2").path])
        XCTAssertEqual(profiles.count, 2)
        profiles = ClaudeProfile.discover(home: home, environment: ["CLAUDE_CONFIG_DIR": home.appendingPathComponent(".claude").path])
        XCTAssertEqual(profiles.count, 2)
    }

    func testLateProfileAppearsOnNextDiscovery() throws {
        XCTAssertEqual(ClaudeProfile.discover(home: home, environment: [:]).count, 1)
        try makeDir(".claude-2", files: [".claude.json": "{}"])
        XCTAssertEqual(ClaudeProfile.discover(home: home, environment: [:]).count, 2)
    }

    func testKeychainServiceNaming() {
        let profile = ClaudeProfile(directory: URL(fileURLWithPath: "/Users/v0687/.claude-2/"), isDefault: false)
        // printf '/Users/v0687/.claude-2' | shasum -a 256 -> first 8 hex chars
        func prefix(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined().prefix(8).description }
        XCTAssertEqual(profile.path, "/Users/v0687/.claude-2")
        XCTAssertEqual(profile.keychainServices, ["Claude Code-credentials-" + prefix("/Users/v0687/.claude-2"),
                                                  "Claude Code-credentials-" + prefix("/Users/v0687/.claude-2/")])
        XCTAssertNotEqual(profile.keychainServices[0], profile.keychainServices[1])
        XCTAssertEqual(ClaudeProfile(directory: URL(fileURLWithPath: "/Users/x/.claude"), isDefault: true).keychainServices, ["Claude Code-credentials"])
    }

    func testKeychainServiceUsesNFCNormalization() {
        let nfd = "/Users/jos\u{0065}\u{0301}/.claude-2"
        let nfc = "/Users/jos\u{00E9}/.claude-2"
        XCTAssertEqual(ClaudeProfile.service(forDirectory: nfd), ClaudeProfile.service(forDirectory: nfc))
    }

    func testLabelUsesEmailWithFolderFallback() throws {
        try makeDir(".claude-2", files: [".claude.json": #"{"oauthAccount":{"emailAddress":"two@example.com","organizationName":"Org"}}"#])
        try makeDir(".claude-work", files: [".credentials.json": "{}"])
        try Data(#"{"oauthAccount":{"emailAddress":"main@example.com"}}"#.utf8).write(to: home.appendingPathComponent(".claude.json"))
        let profiles = ClaudeProfile.discover(home: home, environment: [:])
        XCTAssertEqual(profiles.map { $0.label(home: home) }, ["main@example.com", "two@example.com", ".claude-work"])
    }

    func testDefaultLabelFallsBackToClaude() {
        XCTAssertEqual(ClaudeProfile.discover(home: home, environment: [:])[0].label(home: home), "Claude")
    }

    func testServiceBuildsAccountsWithCodexLast() throws {
        try makeDir(".claude-2", files: [".claude.json": #"{"oauthAccount":{"emailAddress":"two@example.com"}}"#])
        let service = SubscriptionUsageService(home: home, environment: [:])
        let accounts = service.discoverAccounts()
        XCTAssertEqual(accounts.map(\.id), ["claude", "claude:" + home.appendingPathComponent(".claude-2").path, "codex"])
        XCTAssertEqual(accounts[1].label, "two@example.com")
    }

    func testProjectsRootsFeedTranscriptParser() throws {
        try makeDir(".claude")
        try makeDir(".claude-2", files: [".claude.json": "{}"])
        let roots = ClaudeProfile.discover(home: home, environment: [:]).map(\.projectsRoot.lastPathComponent)
        XCTAssertEqual(roots, ["projects", "projects"])
        let line = #"{"type":"assistant","timestamp":"2026-09-05T10:00:00.000Z","sessionId":"s","requestId":"r","message":{"id":"m","model":"claude-sonnet-4","usage":{"input_tokens":10,"output_tokens":5}}}"#
        for (i, name) in [".claude", ".claude-2"].enumerated() {
            let dir = home.appendingPathComponent(name).appendingPathComponent("projects/-p\(i)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(line.replacingOccurrences(of: #""id":"m""#, with: #""id":"m\#(i)""#).replacingOccurrences(of: #""requestId":"r""#, with: #""requestId":"r\#(i)""#).utf8)
                .write(to: dir.appendingPathComponent("s\(i).jsonl"))
        }
        let parser = TranscriptParser(roots: { ClaudeProfile.discover(home: self.home, environment: [:]).map(\.projectsRoot) })
        XCTAssertEqual(parser.snapshot().allTimeTokens, 30)
    }
}
