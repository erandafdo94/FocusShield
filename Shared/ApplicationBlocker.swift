import AppKit

enum ApplicationBlocker {
    @discardableResult
    static func enforce(
        state: FocusShieldState,
        excluding excludedBundleIdentifiers: Set<String> = []
    ) -> [String] {
        guard state.isActive() else { return [] }

        let blockedIdentifiers = Set(state.blockedApplications.map(\.bundleIdentifier))
            .subtracting(excludedBundleIdentifiers)
        guard !blockedIdentifiers.isEmpty else { return [] }

        var requestedTermination: [String] = []
        for application in NSWorkspace.shared.runningApplications {
            guard
                let bundleIdentifier = application.bundleIdentifier,
                blockedIdentifiers.contains(bundleIdentifier),
                !application.isTerminated
            else {
                continue
            }

            if application.terminate() {
                requestedTermination.append(bundleIdentifier)
            }
        }
        return requestedTermination
    }
}
