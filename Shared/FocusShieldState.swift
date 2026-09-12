import Foundation

struct BlockedApplication: Codable, Equatable, Hashable, Identifiable {
    let bundleIdentifier: String
    let name: String
    let path: String

    var id: String { bundleIdentifier }
}

struct FocusShieldState: Codable, Equatable {
    enum Mode: String, Codable {
        case inactive
        case timed
        case untilStopped
    }

    var blockedApplications: [BlockedApplication] = []
    var blockedDomains: [String] = []
    var mode: Mode = .inactive
    var endDate: Date?

    func isManualFocusActive(at date: Date = Date()) -> Bool {
        switch mode {
        case .inactive, .untilStopped:
            return false
        case .timed:
            return endDate.map { $0 > date } ?? false
        }
    }

    func isActive(at date: Date = Date()) -> Bool {
        isManualFocusActive(at: date)
    }

    func activeEndDate(at date: Date = Date()) -> Date? {
        isManualFocusActive(at: date) ? endDate : nil
    }

    mutating func reconcileExpiration(at date: Date = Date()) {
        // Migrate sessions created by older releases, which allowed an indefinite mode.
        if mode == .untilStopped {
            mode = .inactive
            endDate = nil
        }
        if mode == .timed, !isManualFocusActive(at: date) {
            mode = .inactive
            endDate = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case blockedApplications
        case blockedDomains
        case mode
        case endDate
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockedApplications = try container.decodeIfPresent([BlockedApplication].self, forKey: .blockedApplications) ?? []
        blockedDomains = try container.decodeIfPresent([String].self, forKey: .blockedDomains) ?? []
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .inactive
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
    }
}

enum FocusStateStore {
    static let directoryName = "FocusShield"
    static let fileName = "state.json"

    static var applicationSupportDirectory: URL {
        if let overridePath = ProcessInfo.processInfo.environment["FOCUS_SHIELD_STATE_DIRECTORY"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var stateURL: URL {
        applicationSupportDirectory.appendingPathComponent(fileName)
    }

    static func load(now: Date = Date()) -> FocusShieldState {
        guard
            let data = try? Data(contentsOf: stateURL),
            var state = try? JSONDecoder().decode(FocusShieldState.self, from: data)
        else {
            return FocusShieldState()
        }

        state.reconcileExpiration(at: now)
        return state
    }

    static func save(_ state: FocusShieldState) throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

}
