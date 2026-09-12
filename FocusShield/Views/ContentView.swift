import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var focusManager: FocusBlockManager
    @ObservedObject var helperInstaller: BackgroundHelperInstaller

    @State private var domainInput = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                setupCard
                focusCard
                blockListCard
                privacyNote
            }
            .frame(maxWidth: 680)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Focus Shield", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(focusManager.errorMessage ?? helperInstaller.errorMessage ?? "Something went wrong.")
        }
        .onAppear {
            focusManager.refreshFromDisk()
            helperInstaller.refreshStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.indigo.gradient)
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text("Focus Shield")
                    .font(.largeTitle.bold())
                Text("A quieter Mac for study time")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var setupCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: helperInstaller.isInstalled ? "checkmark.circle.fill" : "gearshape.2")
                .font(.title2)
                .foregroundStyle(helperInstaller.isInstalled ? .green : .indigo)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(helperInstaller.isInstalled ? "Background helper installed" : "One-time setup")
                    .font(.headline)
                Text(helperInstaller.isInstalled
                     ? "Apps and websites stay blocked across this Mac when the window is closed."
                     : "Install the helpers once. macOS will request administrator approval for system-wide website blocking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(helperInstaller.isInstalled ? "Reinstall Helper" : "Install Helper") {
                        helperInstaller.install()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                }
                .controlSize(.regular)
            }
            Spacer(minLength: 0)
        }
        .focusCardStyle()
    }

    private var focusCard: some View {
        VStack(spacing: 18) {
            if focusManager.isActive {
                activeFocusContent
            } else {
                idleFocusContent
            }
        }
        .focusCardStyle()
    }

    private var idleFocusContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready to focus?")
                        .font(.title2.bold())
                    Text(focusManager.state.blockedDomains.isEmpty
                         ? "Save your work first—blocked apps will be asked to quit."
                         : "Save your work first—blocked apps and Chrome will close when focus starts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("1", text: $focusManager.durationHoursInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .accessibilityLabel("Focus duration in hours")
                    Text("hours")
                        .foregroundStyle(.secondary)
                    Spacer()

                    Button {
                        focusManager.startTimedFocus()
                    } label: {
                        Label("Start Timer", systemImage: "timer")
                            .frame(minWidth: 130, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(!focusManager.hasBlockedItems || focusManager.durationHours == nil)
                }

                if focusManager.durationHours == nil {
                    Label(
                        "Enter a number greater than 0 and no more than 24.",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                } else {
                    Text("Enter any duration up to 24 hours, such as 1.5.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        }
    }

    private var activeFocusContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 34))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)

            Text(activeFocusTitle)
                .font(.title2.bold())

            Text(focusManager.remainingText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .accessibilityLabel(focusManager.activeEndDate == nil ? "Focus duration" : "Time remaining")

            if let endDate = focusManager.activeEndDate {
                Text("Ends at \(endDate.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                Text("Focus will unlock automatically when the active window ends.")
                    .foregroundStyle(.secondary)
            }

            Label("This timed session cannot be stopped early.", systemImage: "lock.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var activeFocusTitle: String {
        "Focus is active"
    }

    private var blockListCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your block list")
                    .font(.title2.bold())
                Text("This list is saved locally and reused for every session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if focusManager.isActive {
                    Label("Locked until the active focus session ends.", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            appListSection
                .disabled(focusManager.isActive)
            Divider()
            websiteListSection
                .disabled(focusManager.isActive)
        }
        .focusCardStyle()
    }

    private var appListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Applications", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
                Button("Choose Apps") {
                    focusManager.chooseApplications()
                }
            }

            if focusManager.state.blockedApplications.isEmpty {
                emptyRow("No applications selected")
            } else {
                ForEach(focusManager.state.blockedApplications) { application in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.path))
                            .resizable()
                            .frame(width: 30, height: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(application.name)
                                .fontWeight(.medium)
                            Text(application.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        removeButton("Remove \(application.name)") {
                            focusManager.removeApplication(application)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var websiteListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Websites across this Mac", systemImage: "globe")
                .font(.headline)

            Text("Each domain and its www address are blocked in every browser and app during focus.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("youtube.com", text: $domainInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDomain)
                Button("Add Website", action: addDomain)
                    .disabled(domainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if focusManager.state.blockedDomains.isEmpty {
                emptyRow("No websites added")
            } else {
                ForEach(focusManager.state.blockedDomains, id: \.self) { domain in
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        Text(domain)
                            .fontWeight(.medium)
                        Spacer()
                        removeButton("Remove \(domain)") {
                            focusManager.removeDomain(domain)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var privacyNote: some View {
        Label(
            "Everything stays on this Mac. The helpers read only Focus Shield’s local state and never inspect your browsing.",
            systemImage: "lock.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func removeButton(_ accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func addDomain() {
        if focusManager.addDomain(domainInput) {
            domainInput = ""
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: {
                focusManager.errorMessage != nil || helperInstaller.errorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    focusManager.errorMessage = nil
                    helperInstaller.errorMessage = nil
                }
            }
        )
    }

}

private extension View {
    func focusCardStyle() -> some View {
        padding(20)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}
