import SwiftUI

@main
struct FocusShieldApp: App {
    @StateObject private var focusManager = FocusBlockManager()
    @StateObject private var helperInstaller = BackgroundHelperInstaller()

    var body: some Scene {
        WindowGroup {
            ContentView(
                focusManager: focusManager,
                helperInstaller: helperInstaller
            )
            .frame(minWidth: 640, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 800)
    }
}
