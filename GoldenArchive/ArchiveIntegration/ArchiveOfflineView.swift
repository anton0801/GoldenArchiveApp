import SwiftUI

struct ArchiveOfflineView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("WrapperNoInternetBG")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                Image("WrapperOfflineCard")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(geometry.size.width * 0.75, 320))
                    .accessibilityLabel("Please check your internet connection and restart")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}
