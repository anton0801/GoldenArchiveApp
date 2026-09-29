//
//  OnboardingView.swift
//  GoldenArchive
//
//  Presentation layer — three slides, each with its own full-screen
//  background. The example collection is only artwork: no demo records
//  are created. The camera is requested only from the Allow Camera button.
//

import SwiftUI

enum OnboardingDestination {
    case home
    case addCoin
    case addManually
}

private struct OnboardingSlide: Identifiable {
    let id: Int
    let artwork: Artwork
    let title: String
    let message: String
}

struct OnboardingView: View {
    var onFinish: (OnboardingDestination) -> Void

    @State private var page = 0
    @State private var cameraState = CameraPermission.state

    private let slides = [
        OnboardingSlide(
            id: 0,
            artwork: .onboardingCollection,
            title: "Build Your Collection",
            message: "Keep every coin, token and medal you own in one personal archive, organised by country, era, material or your own themes."
        ),
        OnboardingSlide(
            id: 1,
            artwork: .onboardingDetails,
            title: "Record Every Detail",
            message: "Photograph the obverse, reverse and edge, note attributes and condition in your own words, and attach receipts or certificates. The app never declares an item genuine — you decide what goes on record."
        ),
        OnboardingSlide(
            id: 2,
            artwork: .onboardingSets,
            title: "Complete Sets",
            message: "Build albums with the positions you want, see what is collected and what is missing, and turn gaps into wish-list items and goals."
        )
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                ForEach(slides) { slide in
                    ArtworkView(artwork: slide.artwork)
                        .ignoresSafeArea()
                        .tag(slide.id)
                        .accessibilityHidden(true)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            panel
        }
        .background(GAColor.navyDeep.ignoresSafeArea())
        .statusBar(hidden: true)
    }

    private var panel: some View {
        let slide = slides[page]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(page + 1)/\(slides.count)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundColor(GAColor.bronzeText)
                    .accessibilityLabel("Step \(page + 1) of \(slides.count)")
                HStack(spacing: 6) {
                    ForEach(slides) { item in
                        Capsule()
                            .fill(item.id == page ? GAColor.gold : GAColor.stroke)
                            .frame(width: item.id == page ? 26 : 8, height: 8)
                    }
                }
                .accessibilityHidden(true)
                Spacer()
                if page < slides.count - 1 {
                    Button("Skip") { onFinish(.home) }
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(GAColor.navy)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }

            Text(slide.title)
                .font(GAFont.display(.title))
                .foregroundColor(GAColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .id("title-\(page)")
            Text(slide.message)
                .font(.body)
                .foregroundColor(GAColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .id("message-\(page)")

            if page == slides.count - 1 {
                cameraCard
            }

            HStack(spacing: 12) {
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }
                        .buttonStyle(.ga(.outline, fullWidth: false))
                }
                if page < slides.count - 1 {
                    Button("Next") { withAnimation { page += 1 } }
                        .buttonStyle(.gaPrimary)
                } else {
                    Button("Get Started") { onFinish(.addCoin) }
                        .buttonStyle(.gaPrimary)
                }
            }
        }
        .padding(20)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(GAColor.cream)
                .shadow(color: .black.opacity(0.35), radius: 20, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(GAColor.goldRim, lineWidth: 3)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                IconBadge(symbol: "camera.fill", tint: GAColor.navy, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Camera is optional")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(GAColor.text)
                    Text(cameraExplanation)
                        .font(.footnote)
                        .foregroundColor(GAColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                switch cameraState {
                case .notDetermined:
                    Button("Allow Camera") {
                        CameraPermission.request { _ in cameraState = CameraPermission.state }
                    }
                    .buttonStyle(.ga(.secondary, compact: true))
                case .denied:
                    Button("Open Settings") { CameraPermission.openSettings() }
                        .buttonStyle(.ga(.secondary, compact: true))
                case .authorized, .unavailable:
                    EmptyView()
                }
                Button("Add Manually") { onFinish(.addManually) }
                    .buttonStyle(.ga(.outline, compact: true))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GAColor.creamDeep))
    }

    private var cameraExplanation: String {
        switch cameraState {
        case .notDetermined:
            return "It is used only when you photograph an item or scan a document. Manual entry always works."
        case .authorized:
            return "Camera access is on. You can still enter any item manually."
        case .denied:
            return "Camera access is off. You can turn it on in Settings, or add items manually and from your photo library."
        case .unavailable:
            return "This device has no camera. Add items manually or from your photo library."
        }
    }
}
