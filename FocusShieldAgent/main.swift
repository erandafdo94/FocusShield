import AppKit
import Darwin
import Foundation

if let stateDirectoryIndex = CommandLine.arguments.firstIndex(of: "--hosts-agent"),
   CommandLine.arguments.indices.contains(stateDirectoryIndex + 1) {
    setenv(
        "FOCUS_SHIELD_STATE_DIRECTORY",
        CommandLine.arguments[stateDirectoryIndex + 1],
        1
    )
    let hostsAgent = HostsFileAgent()
    hostsAgent.run()
} else if CommandLine.arguments.contains("--agent") {
    let agent = BackgroundAgent()
    agent.run()
}

private final class BackgroundAgent {
    private var timer: Timer?
    private var launchObserver: NSObjectProtocol?

    func run() {
        enforce()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.enforce()
        }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enforce()
        }
        RunLoop.main.run()
    }

    private func enforce() {
        let state = FocusStateStore.load()
        guard state.isActive() else { return }
        ApplicationBlocker.enforce(
            state: state,
            excluding: ["com.example.FocusShield", "com.example.FocusShield.Agent"]
        )
    }
}

private final class HostsFileAgent {
    private static let beginMarker = "# BEGIN FOCUS SHIELD"
    private static let endMarker = "# END FOCUS SHIELD"
    private static var hostsURL: URL {
        let path = ProcessInfo.processInfo.environment["FOCUS_SHIELD_HOSTS_FILE"] ?? "/etc/hosts"
        return URL(fileURLWithPath: path)
    }
    private var timer: Timer?

    func run() {
        enforce()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.enforce()
        }
        RunLoop.main.run()
    }

    private func enforce() {
        let state = FocusStateStore.load()
        let domains = state.isActive() ? state.blockedDomains : []
        try? updateHostsFile(domains: domains)
    }

    private func updateHostsFile(domains: [String]) throws {
        let current = try String(contentsOf: Self.hostsURL, encoding: .utf8)
        let unmanaged = removingManagedBlock(from: current)
        let hostnames = normalizedHostnames(from: domains)

        var updated = unmanaged.trimmingCharacters(in: .newlines)
        if !hostnames.isEmpty {
            let entries = hostnames.flatMap { hostname in
                ["0.0.0.0 \(hostname)", ":: \(hostname)"]
            }
            updated += "\n\n\(Self.beginMarker)\n"
                + entries.joined(separator: "\n")
                + "\n\(Self.endMarker)"
        }
        updated += "\n"

        guard updated != current else { return }
        try updated.write(to: Self.hostsURL, atomically: false, encoding: .utf8)
        flushDNSCache()
    }

    private func removingManagedBlock(from content: String) -> String {
        var isInsideManagedBlock = false
        var retainedLines: [Substring] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == Self.beginMarker {
                isInsideManagedBlock = true
                continue
            }
            if line == Self.endMarker {
                isInsideManagedBlock = false
                continue
            }
            if !isInsideManagedBlock {
                retainedLines.append(line)
            }
        }
        return retainedLines.joined(separator: "\n")
    }

    private func normalizedHostnames(from domains: [String]) -> [String] {
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        var hostnames = Set<String>()

        for rawDomain in domains {
            let domain = rawDomain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard
                !domain.isEmpty,
                domain.unicodeScalars.allSatisfy(allowedCharacters.contains),
                !domain.contains("..")
            else {
                continue
            }
            hostnames.insert(domain)
            if !domain.hasPrefix("www.") {
                hostnames.insert("www.\(domain)")
            }
        }
        return hostnames.sorted()
    }

    private func flushDNSCache() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-HUP", "mDNSResponder"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
