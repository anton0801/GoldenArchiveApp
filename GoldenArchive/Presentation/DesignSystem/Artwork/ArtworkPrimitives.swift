//
//  ArtworkPrimitives.swift
//  GoldenArchive
//
//  Presentation layer — glossy cartoon building blocks: metal coins with
//  thick rims, reliefs, white keeper gloves, lenses, ribbons and rays.
//

import SwiftUI

// MARK: - Metal

enum ArtMetal {
    case gold
    case bronze
    case silver

    var light: Color {
        switch self {
        case .gold: return Color(hex: 0xFFF1A8)
        case .bronze: return Color(hex: 0xF3B274)
        case .silver: return Color(hex: 0xFFFFFF)
        }
    }

    var mid: Color {
        switch self {
        case .gold: return Color(hex: 0xF7C744)
        case .bronze: return Color(hex: 0xC87722)
        case .silver: return Color(hex: 0xDDE4EC)
        }
    }

    var dark: Color {
        switch self {
        case .gold: return Color(hex: 0xD99A22)
        case .bronze: return Color(hex: 0x94521A)
        case .silver: return Color(hex: 0x98A6B8)
        }
    }

    var deep: Color {
        switch self {
        case .gold: return Color(hex: 0x9A5E12)
        case .bronze: return Color(hex: 0x5E3208)
        case .silver: return Color(hex: 0x5F6E80)
        }
    }
}

enum CoinRelief {
    case compass
    case laurel
    case column
    case leaf
    case waves
    case plain
}

// MARK: - Shapes

struct CompassStar: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.2
        let mid = outer * 0.58
        var path = Path()
        for i in 0..<16 {
            let angle = Double(i) * .pi / 8 - .pi / 2
            let r: CGFloat
            switch i % 4 {
            case 0: r = outer
            case 2: r = mid
            default: r = inner
            }
            let point = CGPoint(x: c.x + CGFloat(cos(angle)) * r, y: c.y + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width / 2, h = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - h))
        path.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: c)
        return path
    }
}

struct BeadRing: Shape {
    var count: Int = 40
    var beadRatio: CGFloat = 0.022

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let bead = radius * 2 * beadRatio
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            let p = CGPoint(x: c.x + CGFloat(cos(angle)) * radius, y: c.y + CGFloat(sin(angle)) * radius)
            path.addEllipse(in: CGRect(x: p.x - bead / 2, y: p.y - bead / 2, width: bead, height: bead))
        }
        return path
    }
}

struct SunRays: Shape {
    var count: Int = 16
    var spread: Double = 0.45

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = max(rect.width, rect.height)
        let step = 2 * Double.pi / Double(count)
        for i in 0..<count {
            let a = Double(i) * step
            let half = step * spread / 2
            path.move(to: c)
            path.addLine(to: CGPoint(x: c.x + CGFloat(cos(a - half)) * r, y: c.y + CGFloat(sin(a - half)) * r))
            path.addLine(to: CGPoint(x: c.x + CGFloat(cos(a + half)) * r, y: c.y + CGFloat(sin(a + half)) * r))
            path.closeSubpath()
        }
        return path
    }
}

/// Leaf-shaped lens (vesica) used for laurel leaves.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.3))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.3))
        return path
    }
}

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.12), control: CGPoint(x: rect.minX + w * 0.78, y: rect.minY + h * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.45))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.minY + h * 0.82))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.45), control: CGPoint(x: rect.minX, y: rect.minY + h * 0.82))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY), control: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.1))
        path.closeSubpath()
        return path
    }
}

/// Banner with notched tails.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let tail = w * 0.12
        let sag = h * 0.22
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + sag))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + sag), control: CGPoint(x: rect.midX, y: rect.minY + sag * 2.2))
        path.addLine(to: CGPoint(x: rect.maxX - tail * 0.45, y: rect.midY + sag * 0.6))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY + sag * 1.2 - h * 0.5 + sag))
        path.addLine(to: CGPoint(x: rect.minX + tail * 0.45, y: rect.midY + sag * 0.6))
        path.closeSubpath()
        return path
    }
}

/// Union of a cartoon glove's parts. Stroke first, then fill, so only the
/// outer silhouette keeps an outline.
struct GloveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100, sy = rect.height / 100
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: w * sx, height: h * sy)
        }
        var path = Path()
        path.addRoundedRect(in: r(18, 34, 62, 44), cornerSize: CGSize(width: 20 * sx, height: 20 * sy))
        path.addRoundedRect(in: r(22, 8, 17, 42), cornerSize: CGSize(width: 8.5 * sx, height: 8.5 * sy))
        path.addRoundedRect(in: r(40, 4, 17, 46), cornerSize: CGSize(width: 8.5 * sx, height: 8.5 * sy))
        path.addRoundedRect(in: r(58, 10, 17, 40), cornerSize: CGSize(width: 8.5 * sx, height: 8.5 * sy))
        let thumb = Path(roundedRect: r(0, 0, 16, 36), cornerSize: CGSize(width: 8 * sx, height: 8 * sy))
            .applying(CGAffineTransform(rotationAngle: -.pi / 4.2))
            .applying(CGAffineTransform(translationX: rect.minX + 2 * sx, y: rect.minY + 50 * sy))
        path.addPath(thumb)
        path.addRoundedRect(in: r(24, 72, 50, 24), cornerSize: CGSize(width: 8 * sx, height: 8 * sy))
        return path
    }
}

// MARK: - Coin

struct CoinReliefView: View {
    var relief: CoinRelief
    var metal: ArtMetal

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            let depth = max(0.6, d * 0.018)
            ZStack {
                embossed(depth: depth, d: d)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func embossed(depth: CGFloat, d: CGFloat) -> some View {
        let lightFill = LinearGradient(colors: [metal.light, metal.mid], startPoint: .topLeading, endPoint: .bottomTrailing)
        switch relief {
        case .compass:
            ZStack {
                Circle().strokeBorder(metal.deep.opacity(0.55), lineWidth: d * 0.03).offset(x: depth, y: depth)
                Circle().strokeBorder(lightFill, lineWidth: d * 0.03)
                CompassStar().fill(metal.deep.opacity(0.7)).padding(d * 0.04).offset(x: depth, y: depth)
                CompassStar().fill(lightFill).padding(d * 0.04)
                CompassStar().stroke(metal.dark.opacity(0.6), lineWidth: max(0.5, d * 0.008)).padding(d * 0.04)
                // Half-shaded arms give the star its relief.
                CompassStar().fill(LinearGradient(colors: [.clear, metal.dark.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(d * 0.04)
                Circle().fill(metal.deep.opacity(0.6)).frame(width: d * 0.16).offset(x: depth, y: depth)
                Circle().fill(RadialGradient(colors: [metal.light, metal.mid], center: .topLeading, startRadius: 0, endRadius: d * 0.12)).frame(width: d * 0.16)
            }
        case .laurel:
            ZStack {
                LaurelWreath(leafColor: metal.deep.opacity(0.6), leaves: 7).offset(x: depth, y: depth)
                LaurelWreath(leafColor: metal.light, leaves: 7)
                Circle().fill(metal.deep.opacity(0.6)).frame(width: d * 0.2).offset(x: depth, y: depth)
                Circle().fill(lightFill).frame(width: d * 0.2)
            }
            .padding(d * 0.04)
        case .column:
            ZStack {
                ColumnGlyph().fill(metal.deep.opacity(0.6)).offset(x: depth, y: depth)
                ColumnGlyph().fill(lightFill)
            }
            .padding(d * 0.14)
        case .leaf:
            ZStack {
                LeafShape().fill(metal.deep.opacity(0.6)).rotationEffect(.degrees(-45)).offset(x: depth, y: depth)
                LeafShape().fill(lightFill).rotationEffect(.degrees(-45))
                Rectangle().fill(metal.dark.opacity(0.7)).frame(width: d * 0.62, height: max(0.6, d * 0.02)).rotationEffect(.degrees(-45))
            }
            .padding(d * 0.12)
        case .waves:
            VStack(spacing: d * 0.06) {
                ForEach(0..<3, id: \.self) { _ in
                    WaveLine().stroke(lightFill, style: StrokeStyle(lineWidth: d * 0.045, lineCap: .round))
                        .shadow(color: metal.deep.opacity(0.6), radius: 0, x: depth, y: depth)
                        .frame(height: d * 0.12)
                }
            }
            .padding(d * 0.12)
        case .plain:
            Circle().strokeBorder(metal.dark.opacity(0.35), lineWidth: max(0.5, d * 0.02)).padding(d * 0.18)
        }
    }
}

struct WaveLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        let segments = 3
        let w = rect.width / CGFloat(segments)
        for i in 0..<segments {
            let x0 = rect.minX + CGFloat(i) * w
            path.addCurve(
                to: CGPoint(x: x0 + w, y: rect.midY),
                control1: CGPoint(x: x0 + w * 0.3, y: rect.minY),
                control2: CGPoint(x: x0 + w * 0.7, y: rect.maxY)
            )
        }
        return path
    }
}

struct ColumnGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        // Pediment
        path.move(to: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 0.28))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.05, y: rect.minY + h * 0.28))
        path.closeSubpath()
        // Columns
        for i in 0..<4 {
            let x = rect.minX + w * (0.14 + CGFloat(i) * 0.2)
            path.addRoundedRect(in: CGRect(x: x, y: rect.minY + h * 0.34, width: w * 0.11, height: h * 0.48), cornerSize: CGSize(width: 2, height: 2))
        }
        // Base
        path.addRect(CGRect(x: rect.minX, y: rect.minY + h * 0.86, width: w, height: h * 0.12))
        return path
    }
}

struct LaurelWreath: View {
    var leafColor: Color
    var leaves: Int = 8

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            let radius = d * 0.4
            ZStack {
                ForEach(0..<leaves, id: \.self) { i in
                    leaf(index: i, side: -1, radius: radius, d: d)
                    leaf(index: i, side: 1, radius: radius, d: d)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func leaf(index: Int, side: Double, radius: CGFloat, d: CGFloat) -> some View {
        // Leaves climb from the bottom (90°) to near the top on each side.
        let t = Double(index) / Double(max(leaves - 1, 1))
        let angle = (90 + side * (25 + t * 125)) * .pi / 180
        let x = CGFloat(cos(angle)) * radius
        let y = CGFloat(sin(angle)) * radius
        let tangent = angle * 180 / .pi + (side > 0 ? 90 : -90) + side * 25
        return LeafShape()
            .fill(leafColor)
            .frame(width: d * 0.2, height: d * 0.085)
            .rotationEffect(.degrees(tangent))
            .offset(x: x, y: y)
    }
}

/// A glossy collectible coin: thick rim, beaded border, relief and specular.
struct GlossyCoin: View {
    var metal: ArtMetal = .gold
    var relief: CoinRelief = .compass
    var rim: CGFloat = 0.11
    var showsShadow = true

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                if showsShadow {
                    Circle().fill(Color.black.opacity(0.28)).offset(y: d * 0.05).blur(radius: d * 0.035)
                }
                Circle().fill(metal.deep).offset(y: d * 0.028)
                Circle().fill(
                    AngularGradient(
                        colors: [metal.light, metal.mid, metal.dark, metal.mid, metal.light, metal.mid, metal.dark, metal.mid, metal.light],
                        center: .center
                    )
                )
                Circle()
                    .fill(LinearGradient(colors: [metal.dark, metal.light], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(d * rim * 0.78)
                Circle()
                    .fill(RadialGradient(colors: [metal.light, metal.mid, metal.dark], center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: d * 0.6))
                    .padding(d * rim)
                BeadRing(count: 44, beadRatio: 0.024)
                    .fill(metal.dark.opacity(0.75))
                    .padding(d * (rim + 0.045))
                CoinReliefView(relief: relief, metal: metal)
                    .padding(d * (rim + 0.12))
                Ellipse()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: d * 0.44, height: d * 0.17)
                    .rotationEffect(.degrees(-32))
                    .offset(x: -d * 0.15, y: -d * 0.25)
                    .blur(radius: d * 0.025)
                Circle().strokeBorder(metal.deep.opacity(0.55), lineWidth: max(0.6, d * 0.012))
            }
            .frame(width: d, height: d)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A coin seen edge-on in a stack.
struct CoinDisc: View {
    var metal: ArtMetal = .gold
    var thickness: CGFloat = 0.18

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let faceH = w * 0.36
            let t = w * thickness
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: faceH / 2)
                    .fill(LinearGradient(colors: [metal.dark, metal.mid, metal.light, metal.mid, metal.dark], startPoint: .leading, endPoint: .trailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: faceH / 2)
                            .stroke(metal.deep.opacity(0.75), lineWidth: max(1, w * 0.022))
                    )
                    .frame(height: faceH / 2 + t + faceH / 2)
                    .overlay(
                        VStack(spacing: 0) {
                            Spacer().frame(height: faceH / 2)
                            HStack(spacing: w * 0.035) {
                                ForEach(0..<14, id: \.self) { _ in
                                    Rectangle().fill(metal.deep.opacity(0.35)).frame(width: max(0.5, w * 0.012))
                                }
                            }
                            .frame(height: t)
                            Spacer(minLength: 0)
                        }
                    )
                Ellipse()
                    .fill(RadialGradient(colors: [metal.light, metal.mid, metal.dark], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: w * 0.5))
                    .frame(height: faceH)
                Ellipse()
                    .strokeBorder(metal.dark.opacity(0.7), lineWidth: max(0.6, w * 0.02))
                    .padding(w * 0.06)
                    .frame(height: faceH)
            }
            .frame(width: w, height: faceH + t, alignment: .top)
        }
        .aspectRatio(1 / (0.36 + thickness), contentMode: .fit)
    }
}

// MARK: - Props

struct KeeperGlove: View {
    var mirrored = false

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                GloveShape().stroke(GAColor.navy.opacity(0.55), lineWidth: max(1, w * 0.06))
                GloveShape().fill(LinearGradient(colors: [.white, Color(hex: 0xF2F4F8), GAColor.silver], startPoint: .topLeading, endPoint: .bottomTrailing))
                // Back-of-hand stitching lines
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(GAColor.silver.opacity(0.95))
                        .frame(width: w * 0.04, height: w * 0.18)
                        .offset(x: w * (-0.12 + CGFloat(i) * 0.12), y: w * 0.06)
                }
                // Cuff band
                RoundedRectangle(cornerRadius: w * 0.04)
                    .fill(GAColor.navy)
                    .frame(width: w * 0.5, height: w * 0.07)
                    .offset(x: -w * 0.01, y: w * 0.34)
                RoundedRectangle(cornerRadius: w * 0.02)
                    .fill(GAColor.gold)
                    .frame(width: w * 0.5, height: w * 0.022)
                    .offset(x: -w * 0.01, y: w * 0.305)
            }
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct MagnifierArt: View {
    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            let lens = d * 0.62
            ZStack(alignment: .topLeading) {
                // Handle
                RoundedRectangle(cornerRadius: d * 0.05)
                    .fill(LinearGradient(colors: [GAColor.navySoft, GAColor.navy, GAColor.navyDeep], startPoint: .leading, endPoint: .trailing))
                    .frame(width: d * 0.13, height: d * 0.42)
                    .overlay(
                        VStack(spacing: d * 0.05) {
                            Rectangle().fill(GAColor.goldRim).frame(height: d * 0.035)
                            Spacer()
                            Rectangle().fill(GAColor.goldRim).frame(height: d * 0.025)
                        }
                        .padding(.vertical, d * 0.02)
                    )
                    .rotationEffect(.degrees(-45))
                    .offset(x: lens * 0.95, y: lens * 0.72)
                // Glass
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.35), Color(hex: 0xBFE3FF, opacity: 0.22), Color.white.opacity(0.08)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: lens * 0.6))
                    .frame(width: lens, height: lens)
                Circle()
                    .trim(from: 0.55, to: 0.72)
                    .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: lens * 0.05, lineCap: .round))
                    .frame(width: lens * 0.72, height: lens * 0.72)
                    .offset(x: lens * 0.14, y: lens * 0.14)
                // Rim
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: [GAColor.brightCoin, GAColor.gold, GAColor.bronze, GAColor.gold, GAColor.brightCoin], center: .center),
                        lineWidth: lens * 0.12
                    )
                    .frame(width: lens, height: lens)
                Circle()
                    .strokeBorder(Color(hex: 0x9A5E12).opacity(0.6), lineWidth: 1)
                    .frame(width: lens, height: lens)
            }
            .frame(width: d, height: d, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct Sparkle: View {
    var color: Color = GAColor.brightCoin

    var body: some View {
        SparkleShape()
            .fill(color)
            .shadow(color: color.opacity(0.8), radius: 3)
    }
}

/// Soft orange-gold rays that fade outwards.
struct GlowRays: View {
    var count = 18
    var opacity = 0.55

    var body: some View {
        GeometryReader { proxy in
            let size = max(proxy.size.width, proxy.size.height)
            ZStack {
                SunRays(count: count, spread: 0.42)
                    .fill(RadialGradient(colors: [GAColor.ember.opacity(opacity), GAColor.gold.opacity(opacity * 0.4), .clear], center: .center, startRadius: 0, endRadius: size * 0.5))
                Circle()
                    .fill(RadialGradient(colors: [GAColor.brightCoin.opacity(opacity), GAColor.ember.opacity(opacity * 0.25), .clear], center: .center, startRadius: 0, endRadius: size * 0.34))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// White document card with placeholder lines — never real text.
struct BlankCard: View {
    var lines = 4
    var accent: Color = GAColor.gold

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w * 0.08)
                    .fill(LinearGradient(colors: [.white, Color(hex: 0xF4F1EA)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: w * 0.08)
                    .strokeBorder(accent, lineWidth: max(1, w * 0.03))
                VStack(alignment: .leading, spacing: h * 0.07) {
                    RoundedRectangle(cornerRadius: 2).fill(GAColor.navy.opacity(0.55)).frame(width: w * 0.5, height: h * 0.06)
                    ForEach(0..<lines, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(GAColor.silver)
                            .frame(width: w * (i % 2 == 0 ? 0.72 : 0.56), height: h * 0.045)
                    }
                }
                .padding(w * 0.12)
            }
        }
    }
}

struct SealBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                HStack(spacing: d * 0.08) {
                    RibbonTail().fill(GAColor.ember).frame(width: d * 0.24, height: d * 0.5).rotationEffect(.degrees(12))
                    RibbonTail().fill(Color(hex: 0xD9651A)).frame(width: d * 0.24, height: d * 0.5).rotationEffect(.degrees(-12))
                }
                .offset(y: d * 0.36)
                Circle().fill(GAColor.bronze).offset(y: d * 0.03)
                Circle().fill(RadialGradient(colors: [GAColor.brightCoin, GAColor.gold, Color(hex: 0xD99A22)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.6))
                BeadRing(count: 20, beadRatio: 0.05).fill(Color(hex: 0xB47420).opacity(0.8)).padding(d * 0.12)
                CompassStar().fill(Color(hex: 0xFFF1A8)).padding(d * 0.3)
            }
            .frame(width: d, height: d)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct RibbonTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Navy velvet cell, empty or holding a coin.
struct VelvetCell: View {
    var coin: ArtMetal?
    var relief: CoinRelief = .plain
    var highlighted = false

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(Color(hex: 0x0A1526))
                Circle().fill(RadialGradient(colors: [Color(hex: 0x0A1526), Color(hex: 0x1D3354)], center: UnitPoint(x: 0.45, y: 0.35), startRadius: 0, endRadius: d * 0.6)).padding(d * 0.04)
                if let coin {
                    GlossyCoin(metal: coin, relief: relief, rim: 0.12, showsShadow: false).padding(d * 0.1)
                }
                Circle().strokeBorder(highlighted ? GAColor.brightCoin : GAColor.gold.opacity(0.55), lineWidth: highlighted ? max(1.5, d * 0.07) : max(0.8, d * 0.04))
                if highlighted {
                    Circle().stroke(GAColor.brightCoin.opacity(0.7), lineWidth: max(1, d * 0.04)).blur(radius: d * 0.08)
                }
            }
            .frame(width: d, height: d)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
