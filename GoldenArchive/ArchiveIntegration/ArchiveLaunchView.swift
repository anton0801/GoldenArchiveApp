import SwiftUI

struct ArchiveLaunchView: View {
    @StateObject private var model = ArchiveLaunchModel()
    let container: AppContainer

    var body: some View {
        ZStack {
            switch model.phase {
            case .launching:
                ArchiveSplashView()
            case .noInternet:
                ArchiveOfflineView()
            case .prePermission(let url):
                ArchiveNotificationPermissionView(
                    onAccept: { model.acceptPush(for: url) },
                    onSkip: { model.skipPush(for: url) }
                )
            case .webview(let url):
                Color.black.ignoresSafeArea()
                ArchiveWebViewScreen(url: url)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            case .stub:
                RootView(container: container)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .onAppear { model.start() }
    }
}

struct ArchiveSplashView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(.wrapperMainBG)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: 5)
                    .opacity(0.15)
                    .background(.black.opacity(0.5))
                VStack(spacing: 24) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(GAColor.gold)
                    Text("Golden Archive")
                        .font(.custom("Carter One", size: 32))
                        .foregroundStyle(GAColor.cream)
                    ProgressView()
                        .tint(GAColor.gold)
                }
            }
        }
        .ignoresSafeArea()
    }
}
