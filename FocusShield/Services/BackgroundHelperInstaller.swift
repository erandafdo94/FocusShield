import Combine
import Darwin
import Foundation

@MainActor
final class BackgroundHelperInstaller: ObservableObject {
    private static let hostsAgentLabel = "com.example.FocusShield.hosts-agent"

    @Published private(set) var isInstalled = false
    @Published var errorMessage: String?

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.example.FocusShield.agent.plist")
    }

    private var hostsAgentExecutableURL: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools/\(Self.hostsAgentLabel)")
    }

    private var hostsAgentPlistURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/\(Self.hostsAgentLabel).plist")
    }

    init() {
        refreshStatus()
    }

    func install() {
        do {
            guard let helperURL = Bundle.main.url(forResource: "FocusShieldAgent", withExtension: nil) else {
                throw InstallerError.missingBundledHelper
            }

            try FileManager.default.createDirectory(
                at: FocusStateStore.applicationSupportDirectory,
                withIntermediateDirectories: true
            )

            try installLaunchAgent(helperURL: helperURL)
            try installHostsAgent(helperURL: helperURL)
            refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
            refreshStatus()
        }
    }

    func refreshStatus() {
        isInstalled = FileManager.default.fileExists(atPath: launchAgentURL.path)
            && FileManager.default.fileExists(atPath: hostsAgentExecutableURL.path)
            && FileManager.default.fileExists(atPath: hostsAgentPlistURL.path)
    }

    private func installLaunchAgent(helperURL: URL) throws {
        try FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let propertyList: [String: Any] = [
            "Label": "com.example.FocusShield.agent",
            "ProgramArguments": [helperURL.path, "--agent"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL, options: .atomic)

        let domain = "gui/\(getuid())"
        _ = try? runLaunchctl(["bootout", domain, launchAgentURL.path], requireSuccess: false)
        try runLaunchctl(["bootstrap", domain, launchAgentURL.path], requireSuccess: true)
    }

    private func installHostsAgent(helperURL: URL) throws {
        let stagedPlistURL = FocusStateStore.applicationSupportDirectory
            .appendingPathComponent("\(Self.hostsAgentLabel).plist")
        let propertyList: [String: Any] = [
            "Label": Self.hostsAgentLabel,
            "ProgramArguments": [
                hostsAgentExecutableURL.path,
                "--hosts-agent",
                FocusStateStore.applicationSupportDirectory.path
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: stagedPlistURL, options: .atomic)

        let commands = [
            "/bin/launchctl bootout system/\(Self.hostsAgentLabel) >/dev/null 2>&1 || true",
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/bin/cp \(shellQuote(helperURL.path)) \(shellQuote(hostsAgentExecutableURL.path))",
            "/usr/sbin/chown root:wheel \(shellQuote(hostsAgentExecutableURL.path))",
            "/bin/chmod 755 \(shellQuote(hostsAgentExecutableURL.path))",
            "/bin/cp \(shellQuote(stagedPlistURL.path)) \(shellQuote(hostsAgentPlistURL.path))",
            "/usr/sbin/chown root:wheel \(shellQuote(hostsAgentPlistURL.path))",
            "/bin/chmod 644 \(shellQuote(hostsAgentPlistURL.path))",
            "/bin/launchctl bootstrap system \(shellQuote(hostsAgentPlistURL.path))"
        ].joined(separator: "; ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(appleScriptString(commands))\" with administrator privileges"
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8) ?? "Administrator approval was not granted."
            throw InstallerError.hostsAgentFailed(
                detail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String], requireSuccess: Bool) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if requireSuccess, process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8) ?? "Unknown launchctl error"
            throw InstallerError.launchAgentFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return process.terminationStatus
    }

    private enum InstallerError: LocalizedError {
        case missingBundledHelper
        case launchAgentFailed(String)
        case hostsAgentFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingBundledHelper:
                return "The background helper is missing. Build the complete FocusShield scheme and try again."
            case .launchAgentFailed(let detail):
                return "Couldn’t start the background helper. \(detail)"
            case .hostsAgentFailed(let detail):
                return "Couldn’t install system-wide website blocking. \(detail)"
            }
        }
    }
}
