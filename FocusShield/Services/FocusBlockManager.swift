import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class FocusBlockManager: ObservableObject {
    @Published private(set) var state: FocusShieldState
    @Published var durationHoursInput = "1"
    @Published var errorMessage: String?

    private var timer: Timer?
    private var launchObserver: NSObjectProtocol?

    init() {
        state = FocusStateStore.load()
        // Persist compatibility migrations immediately so already-running older helpers
        // cannot continue an obsolete indefinite or paused session.
        try? FocusStateStore.save(state)
        beginMonitoring()
        reconcileAndEnforce()
    }

    deinit {
        timer?.invalidate()
        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }
    }

    var isActive: Bool { state.isActive() }
    var isManualFocusActive: Bool { state.isManualFocusActive() }
    var activeEndDate: Date? { state.activeEndDate() }
    var hasBlockedItems: Bool {
        !state.blockedApplications.isEmpty || !state.blockedDomains.isEmpty
    }
    var durationHours: Double? {
        let normalizedInput = durationHoursInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard
            let hours = Double(normalizedInput),
            hours > 0,
            hours <= 24
        else {
            return nil
        }
        return hours
    }

    var remainingText: String {
        guard let endDate = activeEndDate else {
            return "Until you stop"
        }
        let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    func chooseApplications() {
        guard canEditBlockList else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose apps to block"
        panel.prompt = "Add Apps"
        panel.message = "Choose one or more applications. Focus Shield will ask them to quit during focus."
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }

        var applications = state.blockedApplications
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        for url in panel.urls {
            guard
                let bundle = Bundle(url: url),
                let bundleIdentifier = bundle.bundleIdentifier,
                bundleIdentifier != ownBundleIdentifier
            else {
                continue
            }

            let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let item = BlockedApplication(
                bundleIdentifier: bundleIdentifier,
                name: displayName,
                path: url.path
            )
            applications.removeAll { $0.bundleIdentifier == bundleIdentifier }
            applications.append(item)
        }

        state.blockedApplications = applications.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        persist()
        reconcileAndEnforce()
    }

    func removeApplication(_ application: BlockedApplication) {
        guard canEditBlockList else { return }
        state.blockedApplications.removeAll { $0.id == application.id }
        persist()
    }

    @discardableResult
    func addDomain(_ input: String) -> Bool {
        guard canEditBlockList else { return false }
        guard let domain = Self.normalizedDomain(from: input) else {
            errorMessage = "Enter a domain such as youtube.com."
            return false
        }
        guard !state.blockedDomains.contains(domain) else { return true }
        state.blockedDomains.append(domain)
        state.blockedDomains.sort()
        persist()
        return true
    }

    func removeDomain(_ domain: String) {
        guard canEditBlockList else { return }
        state.blockedDomains.removeAll { $0 == domain }
        persist()
    }

    func startTimedFocus() {
        guard hasBlockedItems else {
            errorMessage = "Add at least one app or website before starting focus."
            return
        }
        guard let durationHours else {
            errorMessage = "Enter a duration greater than 0 and no more than 24 hours."
            return
        }
        state.mode = .timed
        state.endDate = Date().addingTimeInterval(durationHours * 3_600)
        persist()
        reconcileAndEnforce()
        closeChromeAfterWebsiteBlockActivation()
    }

    func refreshFromDisk() {
        state = FocusStateStore.load()
        reconcileAndEnforce()
    }

    private func beginMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileAndEnforce()
            }
        }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcileAndEnforce()
            }
        }
    }

    private func reconcileAndEnforce() {
        let previousState = state
        state.reconcileExpiration()
        if state != previousState {
            persist()
        }
        guard state.isActive() else { return }

        let exclusions = Set([
            Bundle.main.bundleIdentifier,
            "com.example.FocusShield.Agent"
        ].compactMap { $0 })
        ApplicationBlocker.enforce(state: state, excluding: exclusions)
    }

    private func closeChromeAfterWebsiteBlockActivation() {
        guard !state.blockedDomains.isEmpty else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard
                let self,
                self.state.isManualFocusActive(),
                !self.state.blockedDomains.isEmpty
            else {
                return
            }

            for application in NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.google.Chrome"
            ) {
                application.forceTerminate()
            }
        }
    }

    private var canEditBlockList: Bool {
        guard !state.isActive() else {
            errorMessage = "The block list is locked until focus ends."
            return false
        }
        return true
    }

    private func persist() {
        do {
            try FocusStateStore.save(state)
        } catch {
            errorMessage = "Couldn’t save the block list: \(error.localizedDescription)"
        }
    }

    private static func normalizedDomain(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var host = URLComponents(string: candidate)?.host, !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }
}
