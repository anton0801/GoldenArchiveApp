//
//  ArtworkScenes.swift
//  GoldenArchive
//
//  Presentation layer — vector stand-ins for COI_01…COI_10. Each scene is
//  drawn in a fixed design space and scaled by DesignCanvas.
//

import SwiftUI

// MARK: - COI_04 Home guardian

struct GuardianCoinArt: View {
    var body: some View {
        ZStack {
            GlowRays(count: 20, opacity: 0.42)
                .frame(width: 300, height: 300)
                .offset(y: -18)
            GlossyCoin(metal: .gold, relief: .compass, rim: 0.13)
                .frame(width: 196, height: 196)
                .offset(y: -22)
            KeeperGlove()
                .frame(width: 66, height: 66)
                .rotationEffect(.degrees(28))
                .offset(x: -98, y: 30)
            KeeperGlove(mirrored: true)
                .frame(width: 66, height: 66)
                .rotationEffect(.degrees(-28))
                .offset(x: 98, y: 30)
            ZStack {
                RibbonShape()
                    .fill(LinearGradient(colors: [Color(hex: 0x2B4C7E), GAColor.navy, GAColor.navyDeep], startPoint: .top, endPoint: .bottom))
                RibbonShape()
                    .stroke(GAColor.goldRim, lineWidth: 3)
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 120, height: 4)
                    .offset(y: -6)
            }
            .frame(width: 236, height: 50)
            .offset(y: 100)
            Sparkle().frame(width: 22, height: 22).offset(x: -96, y: -104)
            Sparkle().frame(width: 16, height: 16).offset(x: 104, y: -80)
            Sparkle(color: .white).frame(width: 12, height: 12).offset(x: 70, y: -128)
        }
        .frame(width: 260, height: 280)
    }
}

// MARK: - COI_05 Scan lens

struct ScanLensArt: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [GAColor.gold.opacity(0.28), .clear], center: .center, startRadius: 20, endRadius: 115))
                .frame(width: 230, height: 230)
            Circle()
                .stroke(GAColor.gold.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 9]))
                .frame(width: 196, height: 196)
            Circle()
                .stroke(GAColor.ember.opacity(0.35), lineWidth: 8)
                .frame(width: 196, height: 196)
                .blur(radius: 6)
            smallCard.rotationEffect(.degrees(-9)).offset(x: -84, y: -70)
            smallCard.rotationEffect(.degrees(8)).offset(x: 86, y: 74)
            GlossyCoin(metal: .bronze, relief: .leaf, rim: 0.12)
                .frame(width: 128, height: 128)
                .offset(x: -14, y: 12)
            MagnifierArt()
                .frame(width: 150, height: 150)
                .offset(x: 30, y: 18)
            Sparkle().frame(width: 16, height: 16).offset(x: 70, y: -88)
        }
        .frame(width: 240, height: 240)
    }

    private var smallCard: some View {
        ZStack(alignment: .topLeading) {
            BlankCard(lines: 2, accent: GAColor.gold)
            Circle()
                .fill(LinearGradient(colors: [GAColor.silver, Color(hex: 0xB9C4D2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 18, height: 18)
                .offset(x: 30, y: 38)
        }
        .frame(width: 58, height: 70)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 3)
    }
}

// MARK: - COI_06 Album

struct AlbumArt: View {
    var highlightEmpty = false

    private let leftCells: [(ArtMetal?, CoinRelief)] = [
        (.gold, .compass), (.silver, .laurel), (nil, .plain),
        (.bronze, .column), (.gold, .waves), (.silver, .leaf)
    ]
    private let rightCells: [(ArtMetal?, CoinRelief)] = [
        (.silver, .compass), (nil, .plain), (.gold, .laurel),
        (.bronze, .leaf), (.gold, .column), (nil, .plain)
    ]

    var body: some View {
        ZStack {
            // Page block thickness
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: 0xF3E6C4))
                .frame(width: 226, height: 150)
                .offset(y: 12)
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: 0xE3CD95))
                .frame(width: 226, height: 150)
                .offset(y: 16)
            HStack(spacing: 4) {
                page(cells: leftCells, emptyHighlight: nil)
                page(cells: rightCells, emptyHighlight: highlightEmpty ? 5 : nil)
            }
            .frame(width: 224, height: 146)
            // Spine
            Rectangle()
                .fill(LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 14, height: 146)
            Capsule()
                .fill(GAColor.goldRim)
                .frame(width: 4, height: 150)
        }
        .rotation3DEffect(.degrees(16), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .shadow(color: GAColor.navy.opacity(0.3), radius: 10, y: 8)
        .frame(width: 240, height: 180)
    }

    private func page(cells: [(ArtMetal?, CoinRelief)], emptyHighlight: Int?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [GAColor.navySoft, GAColor.navy, GAColor.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(GAColor.goldRim, lineWidth: 3)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 3), spacing: 8) {
                ForEach(cells.indices, id: \.self) { index in
                    VelvetCell(coin: cells[index].0, relief: cells[index].1, highlighted: emptyHighlight == index)
                        .frame(width: 30, height: 30)
                }
            }
        }
    }
}

// MARK: - COI_07 Certificate & shield

struct CertificateShieldArt: View {
    var body: some View {
        ZStack {
            ZStack {
                ShieldShape().fill(Color(hex: 0x9A5E12)).offset(x: 3, y: 5)
                ShieldShape().fill(LinearGradient(colors: [GAColor.brightCoin, GAColor.gold, GAColor.bronze], startPoint: .topLeading, endPoint: .bottomTrailing))
                ShieldShape().fill(LinearGradient(colors: [GAColor.navySoft, GAColor.navy], startPoint: .top, endPoint: .bottom)).padding(12)
                CompassStar().fill(GAColor.gold).frame(width: 40, height: 40).offset(y: -4)
                Ellipse().fill(Color.white.opacity(0.35)).frame(width: 40, height: 14).rotationEffect(.degrees(-25)).offset(x: -18, y: -38).blur(radius: 2)
            }
            .frame(width: 96, height: 118)
            .rotationEffect(.degrees(-8))
            .offset(x: -56, y: -14)

            ZStack(alignment: .bottomTrailing) {
                BlankCard(lines: 4, accent: GAColor.gold)
                SealBadge().frame(width: 40, height: 40).offset(x: 8, y: 10)
            }
            .frame(width: 98, height: 122)
            .rotationEffect(.degrees(6))
            .offset(x: 34, y: -18)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 4)

            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0x2B4C7E), GAColor.navy, GAColor.navyDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: 104, height: 36)
                Capsule().strokeBorder(GAColor.gold.opacity(0.7), lineWidth: 1.5).frame(width: 104, height: 36)
                HStack(spacing: 30) {
                    Circle().fill(GAColor.gold).frame(width: 5, height: 5)
                    Circle().fill(GAColor.gold).frame(width: 5, height: 5)
                }
                GlossyCoin(metal: .silver, relief: .laurel, rim: 0.12)
                    .frame(width: 50, height: 50)
                    .offset(y: -20)
            }
            .offset(x: -6, y: 58)
        }
        .frame(width: 220, height: 180)
    }
}

// MARK: - COI_08 Duplicate stacks

struct CoinStack: View {
    var count: Int
    var metal: ArtMetal
    var width: CGFloat

    var body: some View {
        let step = width * 0.17
        let drift: [CGFloat] = [0, 0.03, -0.02, 0.025, -0.015, 0.02]
        ZStack(alignment: .bottom) {
            ForEach(0..<count, id: \.self) { i in
                CoinDisc(metal: metal)
                    .frame(width: width)
                    .offset(x: width * drift[i % drift.count], y: -CGFloat(i) * step)
            }
        }
        .frame(width: width, height: width * 0.54 + CGFloat(count - 1) * step, alignment: .bottom)
    }
}

struct DuplicateStacksArt: View {
    var body: some View {
        ZStack {
            Ellipse().fill(GAColor.navy.opacity(0.14)).frame(width: 200, height: 24).offset(y: 70)
            CoinStack(count: 4, metal: .gold, width: 72).offset(x: -58, y: 20)
            CoinStack(count: 4, metal: .gold, width: 72).offset(x: 58, y: 20)
            MagnifierArt()
                .frame(width: 92, height: 92)
                .offset(x: 6, y: -34)
            Sparkle().frame(width: 14, height: 14).offset(x: -24, y: -70)
        }
        .frame(width: 220, height: 170)
    }
}

// MARK: - COI_09 Wish-list case

struct WishlistCaseArt: View {
    var body: some View {
        ZStack {
            // Lid (open, leaning back)
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(GAColor.navyFill)
                RoundedRectangle(cornerRadius: 16).strokeBorder(GAColor.goldRim, lineWidth: 3)
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B4C7E), GAColor.navy], startPoint: .top, endPoint: .bottom))
                    .padding(10)
            }
            .frame(width: 168, height: 64)
            .rotation3DEffect(.degrees(-38), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
            .offset(y: -30)

            // Bookmark with target rings
            ZStack(alignment: .bottom) {
                RibbonTail().fill(LinearGradient(colors: [GAColor.ember, Color(hex: 0xD9651A)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 58)
                ZStack {
                    Circle().strokeBorder(GAColor.brightCoin, lineWidth: 2).frame(width: 14, height: 14)
                    Circle().fill(GAColor.brightCoin).frame(width: 5, height: 5)
                }
                .offset(y: -20)
            }
            .offset(x: 66, y: -10)

            // Base
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x0A1526)).offset(y: 6)
                RoundedRectangle(cornerRadius: 18).fill(GAColor.navyFill)
                RoundedRectangle(cornerRadius: 18).strokeBorder(GAColor.goldRim, lineWidth: 3)
                RoundedRectangle(cornerRadius: 12)
                    .fill(RadialGradient(colors: [Color(hex: 0x2B4C7E), GAColor.navyDeep], center: .center, startRadius: 4, endRadius: 90))
                    .padding(10)
                VelvetCell(coin: nil, highlighted: true).frame(width: 46, height: 46)
            }
            .frame(width: 180, height: 76)
            .offset(y: 40)

            // Glowing coin outline waiting for its place
            ZStack {
                Circle().stroke(GAColor.brightCoin.opacity(0.55), lineWidth: 6).blur(radius: 5)
                Circle().stroke(GAColor.brightCoin, style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))
                BeadRing(count: 24, beadRatio: 0.035).fill(GAColor.brightCoin.opacity(0.8)).padding(7)
            }
            .frame(width: 50, height: 50)
            .offset(y: -22)
            Sparkle().frame(width: 14, height: 14).offset(x: -40, y: -52)
            Sparkle(color: .white).frame(width: 9, height: 9).offset(x: 28, y: -58)
        }
        .frame(width: 220, height: 170)
    }
}

// MARK: - COI_10 Exhibition

struct ExhibitionWreathArt: View {
    var body: some View {
        ZStack {
            // Spotlights
            HStack(spacing: 50) {
                SpotlightCone().frame(width: 70, height: 150).rotationEffect(.degrees(12))
                SpotlightCone().frame(width: 70, height: 150).rotationEffect(.degrees(-12))
            }
            .offset(y: -8)

            LaurelWreath(leafColor: GAColor.gold, leaves: 7)
                .frame(width: 118, height: 118)
                .offset(y: -44)
            LaurelWreath(leafColor: GAColor.bronze.opacity(0.45), leaves: 7)
                .frame(width: 118, height: 118)
                .offset(x: 1.5, y: -42)
                .zIndex(-1)

            // Glass case
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.14))
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                Rectangle().fill(Color.white.opacity(0.35)).frame(width: 3, height: 56).rotationEffect(.degrees(20)).offset(x: -70)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 2, height: 40).rotationEffect(.degrees(20)).offset(x: -60, y: 6)
            }
            .frame(width: 204, height: 70)
            .offset(y: 30)

            HStack(alignment: .bottom, spacing: 16) {
                exhibit(.silver, .laurel, 44)
                exhibit(.gold, .compass, 54)
                exhibit(.bronze, .column, 44)
            }
            .offset(y: 30)

            // Cabinet
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(GAColor.navyFill)
                RoundedRectangle(cornerRadius: 10).strokeBorder(GAColor.goldRim, lineWidth: 3)
                Capsule().fill(GAColor.gold.opacity(0.7)).frame(width: 150, height: 3).offset(y: -6)
            }
            .frame(width: 214, height: 34)
            .offset(y: 78)
        }
        .frame(width: 240, height: 180)
    }

    private func exhibit(_ metal: ArtMetal, _ relief: CoinRelief, _ size: CGFloat) -> some View {
        VStack(spacing: -4) {
            GlossyCoin(metal: metal, relief: relief, rim: 0.12).frame(width: size, height: size)
            Trapezoid().fill(GAColor.navy).frame(width: size * 0.6, height: 12)
        }
    }
}

struct SpotlightCone: View {
    var body: some View {
        Trapezoid(topRatio: 0.2)
            .fill(LinearGradient(colors: [GAColor.brightCoin.opacity(0.55), GAColor.brightCoin.opacity(0.0)], startPoint: .top, endPoint: .bottom))
            .blur(radius: 3)
    }
}

struct Trapezoid: Shape {
    var topRatio: CGFloat = 0.6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * (1 - topRatio) / 2
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct CaliperArt: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.white, GAColor.silver, Color(hex: 0x98A6B8)], startPoint: .top, endPoint: .bottom))
                .frame(width: 190, height: 18)
            HStack(spacing: 7) {
                ForEach(0..<20, id: \.self) { i in
                    Rectangle().fill(GAColor.navy.opacity(0.55)).frame(width: 1.2, height: i % 5 == 0 ? 9 : 5)
                }
            }
            .offset(x: 30, y: 2)
            Trapezoid(topRatio: 1)
                .fill(LinearGradient(colors: [GAColor.silver, Color(hex: 0x98A6B8)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 18, height: 62)
                .offset(x: 6, y: 10)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [.white, GAColor.silver], startPoint: .leading, endPoint: .trailing))
                .frame(width: 30, height: 26)
                .offset(x: 96, y: -4)
            Trapezoid(topRatio: 1)
                .fill(LinearGradient(colors: [GAColor.silver, Color(hex: 0x98A6B8)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 16, height: 56)
                .offset(x: 100, y: 12)
        }
        .frame(width: 190, height: 80, alignment: .topLeading)
    }
}

// MARK: - Onboarding backgrounds (COI_01…COI_03)

private struct OnboardingBackdrop: View {
    var raysCenterY: CGFloat = 250
    var intensity = 0.5

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x24406A), GAColor.navy, GAColor.navyDeep, GAColor.navyDeep], startPoint: .top, endPoint: .bottom)
            GlowRays(count: 22, opacity: intensity)
                .frame(width: 900, height: 900)
                .offset(y: raysCenterY - 450)
            // Floor glow
            Ellipse()
                .fill(RadialGradient(colors: [GAColor.gold.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 200))
                .frame(width: 420, height: 120)
                .offset(y: raysCenterY + 170)
        }
        .frame(width: 390, height: 844)
    }
}

struct OnboardingCollectionScene: View {
    var body: some View {
        DesignCanvas(size: CGSize(width: 390, height: 844), fill: true) {
            ZStack(alignment: .top) {
                OnboardingBackdrop(raysCenterY: 240, intensity: 0.5)
                ZStack {
                    // Cabinet
                    RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0x0A1526)).frame(width: 262, height: 300).offset(y: 8)
                    RoundedRectangle(cornerRadius: 22).fill(GAColor.navyFill).frame(width: 262, height: 300)
                    RoundedRectangle(cornerRadius: 22).strokeBorder(GAColor.goldRim, lineWidth: 6).frame(width: 262, height: 300)
                    VStack(spacing: 118) {
                        shelf
                        shelf
                    }
                    .offset(y: 42)
                    HStack(spacing: 10) {
                        GlossyCoin(metal: .gold, relief: .compass).frame(width: 104, height: 104)
                        GlossyCoin(metal: .silver, relief: .laurel).frame(width: 92, height: 92)
                    }
                    .offset(y: -62)
                    HStack(spacing: 14) {
                        GlossyCoin(metal: .bronze, relief: .column).frame(width: 86, height: 86)
                        GlossyCoin(metal: .gold, relief: .waves).frame(width: 94, height: 94)
                    }
                    .offset(y: 70)
                    // Open glass door
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(GAColor.goldRim, lineWidth: 4))
                        .overlay(Rectangle().fill(Color.white.opacity(0.35)).frame(width: 4, height: 180).rotationEffect(.degrees(16)).offset(x: -10))
                        .frame(width: 110, height: 296)
                        .rotation3DEffect(.degrees(-58), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
                        .offset(x: 186, y: 0)
                }
                .offset(y: 118)
                Sparkle().frame(width: 26, height: 26).offset(x: -140, y: 110)
                Sparkle().frame(width: 18, height: 18).offset(x: 150, y: 90)
                Sparkle(color: .white).frame(width: 12, height: 12).offset(x: 120, y: 470)
            }
        }
    }

    private var shelf: some View {
        ZStack {
            Rectangle().fill(GAColor.goldRim).frame(width: 240, height: 6)
            Rectangle().fill(Color.black.opacity(0.3)).frame(width: 240, height: 6).offset(y: 6)
        }
    }
}

struct OnboardingDetailsScene: View {
    var body: some View {
        DesignCanvas(size: CGSize(width: 390, height: 844), fill: true) {
            ZStack(alignment: .top) {
                OnboardingBackdrop(raysCenterY: 260, intensity: 0.7)
                ZStack {
                    BlankCard(lines: 5, accent: GAColor.gold)
                        .frame(width: 130, height: 168)
                        .rotationEffect(.degrees(7))
                        .offset(x: 104, y: -24)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                    GlossyCoin(metal: .gold, relief: .laurel)
                        .frame(width: 178, height: 178)
                        .offset(x: -44, y: 0)
                    MagnifierArt()
                        .frame(width: 210, height: 210)
                        .offset(x: -10, y: 26)
                    CaliperArt()
                        .rotationEffect(.degrees(-12))
                        .offset(x: 30, y: 176)
                    KeeperGlove()
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -136, y: 150)
                    KeeperGlove(mirrored: true)
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(10))
                        .offset(x: -84, y: 172)
                }
                .offset(y: 190)
                Sparkle().frame(width: 24, height: 24).offset(x: 150, y: 120)
                Sparkle(color: .white).frame(width: 14, height: 14).offset(x: -150, y: 150)
            }
        }
    }
}

struct OnboardingSetsScene: View {
    var body: some View {
        DesignCanvas(size: CGSize(width: 390, height: 844), fill: true) {
            ZStack(alignment: .top) {
                OnboardingBackdrop(raysCenterY: 170, intensity: 0.55)
                GlossyCoin(metal: .gold, relief: .compass)
                    .frame(width: 96, height: 96)
                    .shadow(color: GAColor.brightCoin.opacity(0.6), radius: 18)
                    .offset(x: 62, y: 118)
                Sparkle().frame(width: 24, height: 24).offset(x: 122, y: 100)
                Sparkle(color: .white).frame(width: 14, height: 14).offset(x: 10, y: 150)
                AlbumArt(highlightEmpty: true)
                    .scaleEffect(1.5)
                    .offset(y: 300)
            }
        }
    }
}
