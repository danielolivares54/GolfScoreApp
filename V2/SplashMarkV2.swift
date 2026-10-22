//
//  SplashMarkV2.swift
//  Caddie Score — new splash mark: shaded golf ball with dimples + hole with flagstick on a green.
//  Drawn with SwiftUI Canvas (no asset images, the target has no Copy Bundle Resources phase).
//
//  How to use: in SplashView (Caddy_ScoreApp.swift) replace `CaddieBallFlagMark()` with
//  `CaddieSplashMarkV2()`. Nothing else changes (same wordmark, same colors, same timing).
//

import SwiftUI

struct CaddieSplashMarkV2: View {
    // Scene is drawn in a 300 × 270 pt box and scaled with `scale`.
    var scale: CGFloat = 1

    private let brand   = Color(red: 0.114, green: 0.627, blue: 0.310)   // #1DA04F
    private let brandDk = Color(red: 0.086, green: 0.541, blue: 0.259)   // #168A42
    private let ink     = Color(red: 0.043, green: 0.122, blue: 0.090)   // #0B1F17
    private let pin     = Color(red: 0.169, green: 0.184, blue: 0.173)   // #2B2F2C

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: scale, y: scale)

            // 1. Putting green
            let green = Path(ellipseIn: CGRect(x: 0, y: 199, width: 300, height: 68))
            ctx.fill(green, with: .radialGradient(
                Gradient(colors: [Color(red: 0.839, green: 0.925, blue: 0.863), Color(red: 0.737, green: 0.863, blue: 0.773)]),
                center: CGPoint(x: 150, y: 220), startRadius: 0, endRadius: 160))

            // 2. Cup
            let cup = Path(ellipseIn: CGRect(x: 179, y: 221.5, width: 48, height: 15))
            ctx.fill(cup, with: .linearGradient(
                Gradient(colors: [Color(red: 0.02, green: 0.067, blue: 0.047), Color(red: 0.11, green: 0.2, blue: 0.153)]),
                startPoint: CGPoint(x: 203, y: 222), endPoint: CGPoint(x: 203, y: 236)))
            var lip = Path()
            lip.addArc(center: CGPoint(x: 203, y: 229), radius: 24, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false,
                       transform: CGAffineTransform(translationX: 203, y: 229).scaledBy(x: 1, y: 7.5 / 24).translatedBy(x: -203, y: -229))
            ctx.stroke(lip, with: .color(Color(red: 0.612, green: 0.78, blue: 0.659)), lineWidth: 2)

            // 3. Flagstick standing in the cup
            ctx.fill(Path(roundedRect: CGRect(x: 201.5, y: 5, width: 3.5, height: 225), cornerRadius: 1.7), with: .color(pin))
            ctx.fill(Path(ellipseIn: CGRect(x: 199.8, y: 0.6, width: 6.8, height: 6.8)), with: .color(pin))

            // 4. Waving flag
            var flag = Path()
            flag.move(to: CGPoint(x: 205, y: 9))
            flag.addCurve(to: CGPoint(x: 273, y: 9), control1: CGPoint(x: 227, y: 1), control2: CGPoint(x: 245, y: 17))
            flag.addCurve(to: CGPoint(x: 271, y: 55), control1: CGPoint(x: 261, y: 27), control2: CGPoint(x: 259, y: 39))
            flag.addCurve(to: CGPoint(x: 205, y: 55), control1: CGPoint(x: 247, y: 61), control2: CGPoint(x: 229, y: 47))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(brand))
            var fold = Path()
            fold.move(to: CGPoint(x: 205, y: 9))
            fold.addCurve(to: CGPoint(x: 233, y: 13), control1: CGPoint(x: 217, y: 5), control2: CGPoint(x: 225, y: 9))
            fold.addLine(to: CGPoint(x: 233, y: 51))
            fold.addCurve(to: CGPoint(x: 205, y: 55), control1: CGPoint(x: 223, y: 49), control2: CGPoint(x: 215, y: 51))
            fold.closeSubpath()
            ctx.fill(fold, with: .color(brandDk.opacity(0.6)))

            // 5. Ball shadow on the green
            var shadowCtx = ctx
            shadowCtx.addFilter(.blur(radius: 4))
            shadowCtx.fill(Path(ellipseIn: CGRect(x: 79, y: 223, width: 106, height: 18)), with: .color(ink.opacity(0.22)))

            // 6. Ball (spherical shading)
            let c = CGPoint(x: 120, y: 165), r: CGFloat = 62
            let ballRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            let ball = Path(ellipseIn: ballRect)
            ctx.fill(ball, with: .radialGradient(
                Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: Color(red: 0.953, green: 0.957, blue: 0.941), location: 0.55),
                    .init(color: Color(red: 0.851, green: 0.867, blue: 0.839), location: 0.85),
                    .init(color: Color(red: 0.725, green: 0.749, blue: 0.718), location: 1)]),
                center: CGPoint(x: c.x - r * 0.28, y: c.y - r * 0.40), startRadius: 0, endRadius: r * 1.6))

            // 7. Dimples: hex grid projected on the sphere (smaller + fainter toward the edge)
            var dimpleCtx = ctx
            dimpleCtx.clip(to: ball)
            let step: CGFloat = 0.17
            for j in -13...13 {
                let v = CGFloat(j) * step * 0.866
                let off: CGFloat = j % 2 == 0 ? 0 : step / 2
                for i in -13...13 {
                    let u = CGFloat(i) * step + off
                    let rr = u * u + v * v
                    guard rr <= 0.93 else { continue }
                    let z = sqrt(1 - rr)
                    let p = CGPoint(x: c.x + u * r, y: c.y + v * r)
                    let size = r * 0.058
                    let angle = atan2(v, u)
                    var t = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: angle)
                    let dimple = Path(ellipseIn: CGRect(x: -size * max(z, 0.25), y: -size, width: 2 * size * max(z, 0.25), height: 2 * size))
                        .applying(t)
                    dimpleCtx.fill(dimple, with: .color(Color(red: 0.49, green: 0.514, blue: 0.486).opacity(0.10 + 0.10 * z)))
                    t = t.translatedBy(x: -size * 0.25 * max(z, 0.25), y: 0)
                    let hi = Path(ellipseIn: CGRect(x: -size * 0.8 * max(z, 0.25), y: -size * 0.8, width: 1.6 * size * max(z, 0.25), height: 1.6 * size))
                        .applying(t)
                    dimpleCtx.fill(hi, with: .color(.white.opacity(0.5)))
                }
            }
            ctx.stroke(ball, with: .color(Color(red: 0.769, green: 0.788, blue: 0.761)), lineWidth: 1)

            // 8. Specular highlight
            var hlCtx = ctx
            hlCtx.translateBy(x: c.x - 20, y: c.y - 24)
            hlCtx.rotate(by: .degrees(-30))
            hlCtx.fill(Path(ellipseIn: CGRect(x: -18, y: -11, width: 36, height: 22)), with: .color(.white.opacity(0.55)))

            // 9. "CGM" stamped on the ball
            var txtCtx = ctx
            txtCtx.translateBy(x: c.x + 2, y: c.y + 1)
            txtCtx.rotate(by: .degrees(-10))
            txtCtx.draw(Text("CGM").font(.system(size: 19, weight: .heavy)).kerning(1).foregroundColor(brand),
                        at: .zero, anchor: .center)
        }
        .frame(width: 300 * scale, height: 270 * scale)
        .accessibilityLabel("Pelota de golf CGM junto al hoyo con bandera")
    }
}

#Preview("Splash mark v2") {
    VStack(spacing: 22) {
        CaddieSplashMarkV2()
        HStack(spacing: 6) {
            Text("Caddie").font(.system(size: 34, weight: .heavy)).foregroundColor(Color(red: 0.043, green: 0.122, blue: 0.090))
            Text("Score").font(.system(size: 34, weight: .heavy)).foregroundColor(Color(red: 0.114, green: 0.627, blue: 0.310))
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 0.961, green: 0.965, blue: 0.949))
}
