import SwiftUI

struct ArchiveNotificationPermissionView: View {
    let onAccept: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            ZStack {
                Image("WrapperMainBG")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                if landscape {
                    landscapeContent(in: geometry)
                } else {
                    portraitContent(in: geometry)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func landscapeContent(in geometry: GeometryProxy) -> some View {
        let leftInset = max(geometry.safeAreaInsets.leading + 16, geometry.size.width * 0.09)
        let rightInset = max(geometry.safeAreaInsets.trailing + 16, geometry.size.width * 0.04)
        let usableWidth = geometry.size.width - leftInset - rightInset

        return ZStack {
            logo(width: min(geometry.size.width * 0.38, geometry.size.height * 0.82))
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.33)

            HStack(alignment: .bottom, spacing: 0) {
                texts(alignment: .leading, titleSize: 22, landscape: true)
                    .frame(width: usableWidth * 0.47, alignment: .leading)
                    .padding(.bottom, 18)
                Spacer(minLength: 0)
                buttons
                    .frame(width: usableWidth * 0.43)
            }
            .frame(width: usableWidth)
            .padding(.leading, leftInset)
            .padding(.trailing, rightInset)
            .padding(.bottom, geometry.safeAreaInsets.bottom + 12)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
    }

    private func portraitContent(in geometry: GeometryProxy) -> some View {
        ZStack {
            logo(width: geometry.size.width * 0.85)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.43)

            VStack(spacing: 24) {
                texts(alignment: .center, titleSize: 20, landscape: false)
                buttons
            }
            .frame(width: geometry.size.width * 0.86)
            .padding(.bottom, geometry.safeAreaInsets.bottom + 16)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
    }

    private func logo(width: CGFloat) -> some View {
        Image("WrapperLogo")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: width)
            .shadow(color: .black.opacity(0.55), radius: 8, y: 5)
            .accessibilityLabel("Build Nova")
    }

    private func texts(alignment: TextAlignment, titleSize: CGFloat, landscape: Bool) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 12) {
            Text("ALLOW NOTIFICATIONS ABOUT\nBONUSES AND PROMOS")
                .font(.custom("Carter One", size: titleSize))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 3, y: 3)
                .multilineTextAlignment(alignment)
                .minimumScaleFactor(0.7)
            Text(landscape
                 ? "Stay tuned with best offers from our casino"
                 : "Stay tuned with best offers from\nour casino")
                .font(.custom("Carter One", size: 16))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 3)
                .multilineTextAlignment(alignment)
                .minimumScaleFactor(0.8)
        }
    }

    private var buttons: some View {
        VStack(spacing: 18) {
            Button(action: onAccept) {
                Image("WrapperAcceptButton")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 440)
            }
            .accessibilityLabel("Allow notifications")
            Button(action: onSkip) {
                Image("WrapperSkipButton")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420)
            }
            .accessibilityLabel("Skip notifications")
        }
    }
}
