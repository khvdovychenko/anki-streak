import SwiftUI

/// Cinder drawn live in code (same shapes as docs/cinder.js), so every part can move on its own:
/// dancing flame, glowing cracks, blinking eyes, rising embers, sweat, smoke, and a poke reaction.
struct CinderView: View {
    let stage: Int
    let mood: Mood
    @State private var pokedAt: Double = -10

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                CinderPainter(stage: stage, mood: mood, t: t, sincePoke: t - pokedAt).draw(in: &ctx, size: size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            pokedAt = Date.now.timeIntervalSinceReferenceDate
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        .accessibilityLabel("Cinder, \(CinderLogic.stages[stage].name), \(mood.rawValue)")
    }
}

private struct CinderPainter {
    let stage: Int
    let mood: Mood
    let t: Double
    let sincePoke: Double

    var dead: Bool { mood == .dead || stage == 0 }
    var scale: CGFloat { [0.86, 0.86, 0.95, 1.03, 1.1, 1.16][stage] }
    var flameH: CGFloat {
        if dead { return 0 }
        let base: CGFloat = [0, 26, 36, 48, 58, 66][stage]
        let f: CGFloat = [Mood.lit: 1, .partial: 0.8, .new: 0.7, .fading: 0.5, .dying: 0.3][mood] ?? 1
        return base * f * (poke > 0 ? 1 + 0.35 * poke : 1)
    }
    var flameOpacity: Double { [Mood.lit: 1, .partial: 0.9, .new: 0.85, .fading: 0.6, .dying: 0.45][mood] ?? 1 }
    var bodyColor: Color { dead ? Color(hex: 0x8C8580) : stage == 5 ? Color(hex: 0x4A2620) : Color(hex: 0x3B3632) }
    var glowColor: Color {
        if dead { return Color(hex: 0x6E6862) }
        switch mood {
        case .dying: return Color(hex: 0xA8521A)
        case .fading: return Color(hex: 0xD9661A)
        default: return Color(hex: 0xFF5A00)
        }
    }
    var eyeColor: Color { dead ? Color(hex: 0x3B3632) : Color(hex: 0xF6EEE6) }
    var crackCount: Int { dead ? 3 : [3, 2, 3, 5, 6, 8][stage] }
    /// 1 right after a tap, fading to 0 over half a second.
    var poke: CGFloat { sincePoke < 0.5 ? CGFloat(1 - sincePoke / 0.5) : 0 }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        // Map the SVG viewBox (-80 -110 160 160) onto the view.
        let k = min(size.width, size.height) / 160
        ctx.translateBy(x: size.width / 2, y: 110 * k + (size.height - 160 * k) / 2)
        ctx.scaleBy(x: k, y: k)

        // Whole-body motion: breathing, poke hop, dying shiver.
        let hop = -sin(Double(poke) * .pi) * 14
        let shiver = mood == .dying ? sin(t * 38) * 0.7 : 0
        let breathe = 1 + 0.018 * sin(t * 1.7)
        ctx.translateBy(x: shiver, y: 6 + hop)
        ctx.scaleBy(x: scale, y: scale)

        if !dead && stage >= 4 { drawBackFlames(&ctx) }
        if !dead && flameH > 0 { drawMainFlame(&ctx) }
        if dead { drawSmoke(&ctx) }

        // Body squashes from the bottom when breathing or poked.
        var body = ctx
        let squash = 1 - 0.12 * poke
        body.translateBy(x: 0, y: 38)
        body.scaleBy(x: (2 - breathe) * (1 + 0.1 * poke), y: breathe * squash)
        body.translateBy(x: 0, y: -38)
        body.fill(Self.bodyPath, with: .color(bodyColor))
        if stage == 5 && !dead {
            body.fill(Self.lavaPath, with: .color(Color(hex: 0xFF5A00)))
        }
        drawCracks(&body)
        drawFace(&body)
        if !dead && stage >= 3 && (mood == .lit || mood == .partial) { drawEmbers(&ctx) }
    }

    // MARK: parts

    private func drawMainFlame(_ ctx: inout GraphicsContext) {
        var f = ctx
        f.translateBy(x: 0, y: -26)
        let dyingFlutter = mood == .dying ? 0.75 + 0.25 * abs(sin(t * 5.3) * sin(t * 2.1)) : 1
        f.opacity = flameOpacity * dyingFlutter
        let sway = sin(t * 2.7) * 3 + sin(t * 4.3) * 1.5
        f.rotate(by: .degrees(sway))
        f.scaleBy(x: 1 + 0.05 * sin(t * 3.1), y: (1 + 0.07 * sin(t * 4.7 + 1)) * dyingFlutter)
        // Soft glow behind the flame.
        f.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.opacity = 0.55
            layer.fill(Self.flamePath(flameH * 1.05), with: .color(Color(hex: 0xFF7A1A)))
        }
        f.fill(Self.flamePath(flameH), with: .color(Color(hex: 0xFF7A1A)))
        // Inner flame flickers on its own rhythm.
        var inner = f
        inner.rotate(by: .degrees(-sway * 0.6 + sin(t * 6.1) * 2))
        inner.scaleBy(x: 1, y: 1 + 0.1 * sin(t * 6.7))
        inner.fill(Self.flamePath(flameH * 0.58), with: .color(Color(hex: 0xFFD25A)))
    }

    private func drawBackFlames(_ ctx: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            var f = ctx
            f.opacity = flameOpacity * 0.8
            f.translateBy(x: 24 * side, y: -18)
            f.rotate(by: .degrees(18 * side + sin(t * 2.3 + side) * 5))
            f.scaleBy(x: 1, y: 1 + 0.08 * sin(t * 3.9 + side * 2))
            f.fill(Self.flamePath(flameH * 0.7), with: .color(Color(hex: 0xFF5A00)))
        }
    }

    private func drawCracks(_ ctx: inout GraphicsContext) {
        let pulse = dead ? 1 : 0.6 + 0.4 * (0.5 + 0.5 * sin(t * (mood == .dying || mood == .fading ? 1.2 : 2.2)))
        var cracks = Path()
        for p in Self.cracks.prefix(crackCount) { cracks.addPath(p) }
        let style = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        if !dead {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.opacity = pulse
                layer.stroke(cracks, with: .color(glowColor), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        var sharp = ctx
        sharp.opacity = dead ? 1 : 0.55 + 0.45 * pulse
        sharp.stroke(cracks, with: .color(glowColor), style: style)
    }

    private func drawFace(_ ctx: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(eyeColor)
        let stroke = StrokeStyle(lineWidth: 2.6, lineCap: .round)

        if dead {
            var x = Path()
            for cx in [-14.0, 14.0] {
                x.move(to: CGPoint(x: cx - 5, y: -6)); x.addLine(to: CGPoint(x: cx + 5, y: 4))
                x.move(to: CGPoint(x: cx + 5, y: -6)); x.addLine(to: CGPoint(x: cx - 5, y: 4))
            }
            x.move(to: CGPoint(x: -6, y: 16)); x.addLine(to: CGPoint(x: 6, y: 16))
            ctx.stroke(x, with: ink, style: stroke)
            return
        }

        // Blink every ~4.6 s; pupils drift slowly.
        let cycle = t.truncatingRemainder(dividingBy: 4.6)
        let blink: CGFloat = cycle > 4.42 ? CGFloat(max(0.1, abs(cycle - 4.51) / 0.09)) : 1
        let look = CGFloat(sin(t * 0.55)) * 1.6
        for cx in [-14.0, 14.0] {
            let r: CGFloat = 3.4
            let rect = CGRect(x: cx + look - r, y: -r * blink, width: r * 2, height: r * 2 * blink)
            ctx.fill(Path(ellipseIn: rect), with: ink)
        }

        var brows = Path(), mouth = Path()
        switch mood {
        case .lit:
            brows.move(to: CGPoint(x: -22, y: -5)); brows.addLine(to: CGPoint(x: -6, y: -4))
            brows.move(to: CGPoint(x: 6, y: -4)); brows.addLine(to: CGPoint(x: 22, y: -5))
            mouth.move(to: CGPoint(x: -6, y: 16)); mouth.addQuadCurve(to: CGPoint(x: 10, y: 13), control: CGPoint(x: 3, y: 19 + 2 * poke))
        case .partial, .new:
            let raise = CGFloat(sin(t * 0.9)) * 1.2
            brows.move(to: CGPoint(x: -22, y: -6)); brows.addLine(to: CGPoint(x: -6, y: -5))
            brows.move(to: CGPoint(x: 6, y: -9 - raise)); brows.addLine(to: CGPoint(x: 22, y: -6 - raise))
            mouth.move(to: CGPoint(x: -7, y: 16)); mouth.addLine(to: CGPoint(x: 8, y: 15))
        default:
            brows.move(to: CGPoint(x: -21, y: -10)); brows.addLine(to: CGPoint(x: -8, y: -6))
            brows.move(to: CGPoint(x: 8, y: -6)); brows.addLine(to: CGPoint(x: 21, y: -10))
            let w = CGFloat(sin(t * 6)) * 1.2
            mouth.move(to: CGPoint(x: -8, y: 17))
            mouth.addQuadCurve(to: CGPoint(x: 0, y: 17), control: CGPoint(x: -4, y: 13 + w))
            mouth.addQuadCurve(to: CGPoint(x: 8, y: 17), control: CGPoint(x: 4, y: 21 - w))
            drawSweat(&ctx, x: 27, y: -14, phase: 0)
            if mood == .dying { drawSweat(&ctx, x: -30, y: -12, phase: 0.5) }
        }
        ctx.stroke(brows, with: ink, style: stroke)
        ctx.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    private func drawSweat(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, phase: Double) {
        let p = (t / 1.8 + phase).truncatingRemainder(dividingBy: 1)
        var drop = ctx
        drop.opacity = p < 0.15 ? p / 0.15 : 1 - p
        drop.translateBy(x: x, y: y + CGFloat(p) * 16)
        var d = Path()
        d.move(to: CGPoint(x: 0, y: 0))
        d.addCurve(to: CGPoint(x: 1, y: 10), control1: CGPoint(x: -2, y: 6), control2: CGPoint(x: -2, y: 9))
        d.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: 4, y: 9), control2: CGPoint(x: 3, y: 5))
        drop.fill(d, with: .color(Color(hex: 0x7CC4FF)))
    }

    private func drawEmbers(_ ctx: inout GraphicsContext) {
        let xs: [CGFloat] = stage >= 4 ? [-26, 22, -8, 30, -34, 10] : [-26, 22, -8]
        for (i, x0) in xs.enumerated() {
            let p = (t * 0.38 + Double(i) / Double(xs.count)).truncatingRemainder(dividingBy: 1)
            var e = ctx
            e.opacity = p < 0.15 ? p / 0.15 : 1 - p
            let x = x0 + CGFloat(sin(t * 2 + Double(i))) * 4
            let y = -20 - CGFloat(p) * 75
            let r: CGFloat = 1.9 * CGFloat(1 - p * 0.5)
            e.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: 0xFFB02E)))
        }
    }

    private func drawSmoke(_ ctx: inout GraphicsContext) {
        for (i, x0) in [-4.0, 8.0].enumerated() {
            let p = (t / 3.2 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            var s = ctx
            s.opacity = 0.7 * (p < 0.2 ? p / 0.2 : 1 - p)
            s.translateBy(x: x0 + CGFloat(sin(t * 1.3 + Double(i))) * 2, y: -34 - CGFloat(p) * 18)
            var path = Path()
            path.move(to: .zero)
            path.addCurve(to: CGPoint(x: 0, y: -28), control1: CGPoint(x: -8, y: -10), control2: CGPoint(x: 8, y: -16))
            s.stroke(path, with: .color(Color(hex: 0xA8A29C)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    // MARK: shapes (from docs/cinder.js)

    static func flamePath(_ h: CGFloat) -> Path {
        let w = h * 0.42
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -h))
        p.addCurve(to: CGPoint(x: w * 0.95, y: -h * 0.22), control1: CGPoint(x: w * 0.5, y: -h * 0.7), control2: CGPoint(x: w, y: -h * 0.5))
        p.addCurve(to: .zero, control1: CGPoint(x: w * 0.9, y: -h * 0.02), control2: CGPoint(x: w * 0.45, y: 0))
        p.addCurve(to: CGPoint(x: -w * 0.95, y: -h * 0.22), control1: CGPoint(x: -w * 0.45, y: 0), control2: CGPoint(x: -w * 0.9, y: -h * 0.02))
        p.addCurve(to: CGPoint(x: -w * 0.3, y: -h * 0.72), control1: CGPoint(x: -w, y: -h * 0.42), control2: CGPoint(x: -w * 0.45, y: -h * 0.5))
        p.addCurve(to: CGPoint(x: w * 0.1, y: -h * 0.5), control1: CGPoint(x: -w * 0.15, y: -h * 0.6), control2: CGPoint(x: -w * 0.05, y: -h * 0.55))
        p.addCurve(to: CGPoint(x: 0, y: -h), control1: CGPoint(x: -w * 0.05, y: -h * 0.65), control2: CGPoint(x: -w * 0.05, y: -h * 0.85))
        p.closeSubpath()
        return p
    }

    static let bodyPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -38, y: 0))
        p.addCurve(to: CGPoint(x: -4, y: -32), control1: CGPoint(x: -40, y: -22), control2: CGPoint(x: -20, y: -34))
        p.addCurve(to: CGPoint(x: 38, y: 0), control1: CGPoint(x: 16, y: -34), control2: CGPoint(x: 38, y: -24))
        p.addCurve(to: CGPoint(x: 0, y: 38), control1: CGPoint(x: 40, y: 22), control2: CGPoint(x: 24, y: 38))
        p.addCurve(to: CGPoint(x: -38, y: 0), control1: CGPoint(x: -24, y: 40), control2: CGPoint(x: -38, y: 24))
        p.closeSubpath()
        return p
    }()

    static let lavaPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -30, y: 6))
        p.addCurve(to: CGPoint(x: -27, y: 22), control1: CGPoint(x: -31, y: 14), control2: CGPoint(x: -27, y: 16))
        p.addCurve(to: CGPoint(x: -32, y: 22), control1: CGPoint(x: -27, y: 26), control2: CGPoint(x: -32, y: 26))
        p.move(to: CGPoint(x: 30, y: 2))
        p.addCurve(to: CGPoint(x: 29, y: 18), control1: CGPoint(x: 32, y: 10), control2: CGPoint(x: 28, y: 12))
        p.addCurve(to: CGPoint(x: 33, y: 17), control1: CGPoint(x: 29, y: 21), control2: CGPoint(x: 33, y: 21))
        return p
    }()

    static let cracks: [Path] = {
        let segments: [[CGPoint]] = [
            [CGPoint(x: -34, y: -6), CGPoint(x: -27, y: 1)],
            [CGPoint(x: 27, y: -15), CGPoint(x: 33, y: -8)],
            [CGPoint(x: -20, y: 29), CGPoint(x: -11, y: 32)],
            [CGPoint(x: 13, y: 29), CGPoint(x: 22, y: 25)],
            [CGPoint(x: -31, y: 13), CGPoint(x: -25, y: 19)],
            [CGPoint(x: 29, y: 9), CGPoint(x: 34, y: 3)],
            [CGPoint(x: -9, y: -28), CGPoint(x: -1, y: -24), CGPoint(x: 5, y: -27)],
            [CGPoint(x: -2, y: 35), CGPoint(x: 5, y: 32)],
        ]
        return segments.map { pts in
            var p = Path()
            p.addLines(pts)
            return p
        }
    }()
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
