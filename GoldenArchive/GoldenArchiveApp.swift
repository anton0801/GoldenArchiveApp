import SwiftUI

@main
struct GoldenArchiveApp: App {
    @UIApplicationDelegateAdaptor(ArchiveAppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        GATheme.configureUIKitAppearance()
//        #if DEBUG
//        if QASelfTest.isRequested {
//            Task { @MainActor in
//                exit(await QASelfTest.run() ? 0 : 1)
//            }
//        }
//        #endif
    }

    var body: some Scene {
        WindowGroup {
            ArchiveLaunchView(container: container)
                .environmentObject(container)
                .environmentObject(router)
                .preferredColorScheme(.light)
                .accentColor(GAColor.navy)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { container.flush() }
        }
    }
}
