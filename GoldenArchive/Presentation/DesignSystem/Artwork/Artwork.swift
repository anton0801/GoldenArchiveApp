//
//  Artwork.swift
//  GoldenArchive
//
//  Presentation layer — the ten decorative assets (COI_01…COI_10).
//  A bundled bitmap with the asset's file name always wins (drop
//  `coin_home_guardian.webp` or a PNG imageset with that name into the
//  target). Until then a vector drawing in the same style is shown.
//  Artwork never contains text, numbers, faces or denominations.
//

import SwiftUI
import UIKit

enum Artwork: String, CaseIterable, Identifiable {
    case onboardingCollection = "coin_onboarding_collection"
    case onboardingDetails = "coin_onboarding_details"
    case onboardingSets = "coin_onboarding_sets"
    case homeGuardian = "coin_home_guardian"
    case scanLens = "coin_scan_lens"
    case album = "coin_album"
    case certificateShield = "coin_certificate_shield"
    case duplicateStacks = "coin_duplicate_stacks"
    case wishlistCase = "coin_wishlist_case"
    case exhibitionWreath = "coin_exhibition_wreath"

    var id: String { rawValue }

    var code: String {
        switch self {
        case .onboardingCollection: return "COI_01"
        case .onboardingDetails: return "COI_02"
        case .onboardingSets: return "COI_03"
        case .homeGuardian: return "COI_04"
        case .scanLens: return "COI_05"
        case .album: return "COI_06"
        case .certificateShield: return "COI_07"
        case .duplicateStacks: return "COI_08"
        case .wishlistCase: return "COI_09"
        case .exhibitionWreath: return "COI_10"
        }
    }

    /// Pixel size from the asset specification.
    var pixelSize: CGSize {
        switch self {
        case .onboardingCollection, .onboardingDetails, .onboardingSets: return CGSize(width: 1290, height: 2796)
        case .homeGuardian: return CGSize(width: 1300, height: 1400)
        case .scanLens: return CGSize(width: 1000, height: 1000)
        case .album, .exhibitionWreath: return CGSize(width: 1200, height: 900)
        case .certificateShield: return CGSize(width: 1100, height: 900)
        case .duplicateStacks, .wishlistCase: return CGSize(width: 1100, height: 850)
        }
    }

    var isFullScreenBackground: Bool {
        switch self {
        case .onboardingCollection, .onboardingDetails, .onboardingSets: return true
        default: return false
        }
    }
}

enum ArtworkLibrary {
    private static var cache: [Artwork: UIImage] = [:]
    private static var misses: Set<Artwork> = []

    /// A real bitmap for the asset, if one is bundled.
    static func bitmap(for artwork: Artwork) -> UIImage? {
        if let cached = cache[artwork] { return cached }
        if misses.contains(artwork) { return nil }
        var image = UIImage(named: artwork.rawValue)
        if image == nil {
            for ext in ["webp", "png", "jpg"] {
                if let path = Bundle.main.path(forResource: artwork.rawValue, ofType: ext),
                   let loaded = UIImage(contentsOfFile: path) {
                    image = loaded
                    break
                }
            }
        }
        if let image { cache[artwork] = image } else { misses.insert(artwork) }
        return image
    }
}

struct ArtworkView: View {
    var artwork: Artwork

    var body: some View {
        if let image = ArtworkLibrary.bitmap(for: artwork) {
            if artwork.isFullScreenBackground {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(uiImage: image).resizable().scaledToFit()
            }
        } else {
            ArtworkIllustration(artwork: artwork)
        }
    }
}

/// Draws a vector scene in a fixed design space and scales it to the frame.
struct DesignCanvas<Content: View>: View {
    var size: CGSize
    var fill = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let scale = fill
                ? max(proxy.size.width / size.width, proxy.size.height / size.height)
                : min(proxy.size.width / size.width, proxy.size.height / size.height)
            content()
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }
}

struct ArtworkIllustration: View {
    var artwork: Artwork

    var body: some View {
        switch artwork {
        case .onboardingCollection: OnboardingCollectionScene()
        case .onboardingDetails: OnboardingDetailsScene()
        case .onboardingSets: OnboardingSetsScene()
        case .homeGuardian: DesignCanvas(size: CGSize(width: 260, height: 280)) { GuardianCoinArt() }
        case .scanLens: DesignCanvas(size: CGSize(width: 240, height: 240)) { ScanLensArt() }
        case .album: DesignCanvas(size: CGSize(width: 240, height: 180)) { AlbumArt() }
        case .certificateShield: DesignCanvas(size: CGSize(width: 220, height: 180)) { CertificateShieldArt() }
        case .duplicateStacks: DesignCanvas(size: CGSize(width: 220, height: 170)) { DuplicateStacksArt() }
        case .wishlistCase: DesignCanvas(size: CGSize(width: 220, height: 170)) { WishlistCaseArt() }
        case .exhibitionWreath: DesignCanvas(size: CGSize(width: 240, height: 180)) { ExhibitionWreathArt() }
        }
    }
}
