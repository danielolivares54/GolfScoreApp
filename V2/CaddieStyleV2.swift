//
//  CaddieStyleV2.swift
//  Caddie Score — Vista v2: tokens and shared components (visual only, no logic)
//
//  Rule: every key datum has ONE look, used the same way on every v2 screen.
//  Copy this file to Caddy_Score/V2/. All types end in V2 so nothing collides with v1.
//

import SwiftUI

// MARK: - Tokens

enum CSV2 {
    static let ink        = Color(hexV2: 0x1A1A17)
    static let secondary  = Color(hexV2: 0x5E584C)   // never use a lighter text colour
    static let background = Color(hexV2: 0xF7F3EA)
    static let surface    = Color.white
    static let line       = Color(hexV2: 0xE4DCCB)
    static let rowLine    = Color(hexV2: 0xEFE8D8)
    static let parFill    = Color(hexV2: 0xEFE8D8)

    static let green  = Color(hexV2: 0x157A3B)       // action · under par · winning
    static let red    = Color(hexV2: 0xB3261E)       // over par · losing
    static let stroke = Color(hexV2: 0x1F4E9C)       // ONLY strokes
    static let unitBg = Color(hexV2: 0xF3E2B3)       // ONLY events / oyes
    static let unitFg = Color(hexV2: 0x6E4600)
    static let unitLine = Color(hexV2: 0xC9A24A)

    static let s1: CGFloat = 8, s2: CGFloat = 16, s3: CGFloat = 24
    static let rCell: CGFloat = 10, rCard: CGFloat = 16
    static let minTap: CGFloat = 48
}

// MARK: - Type (relaxed: system font, tabular digits)

extension Font {
    static let v2Hole   = Font.system(size: 42, weight: .heavy).monospacedDigit()
    static let v2Score  = Font.system(size: 26, weight: .heavy).monospacedDigit()
    static let v2Name   = Font.system(size: 18, weight: .bold)
    static let v2Body   = Font.system(size: 16, weight: .semibold).monospacedDigit()
    static let v2Label  = Font.system(size: 13, weight: .semibold).monospacedDigit()   // minimum size
    static let v2Caps   = Font.system(size: 12, weight: .bold)                          // use with .textCase(.uppercase)
}

// MARK: - Half-stroke formatting: 3.5 -> "3½", 0.5 -> "½", 3 -> "3"

func strokesTextV2(_ value: Double) -> String {
    let v = abs(value)
    let whole = Int(v.rounded(.down))
    let hasHalf = (v - Double(whole)) >= 0.5
    if whole == 0 { return hasHalf ? "½" : "0" }
    return hasHalf ? "\(whole)½" : "\(whole)"
}

// MARK: - Par "P4" (filled) and HCP "HCP 6" (outlined). onGreen = white variant for the hole card.

struct ParTagV2: View {
    let par: Int
    var onGreen = false
    var body: some View {
        Text("P\(par)").font(.v2Label).foregroundStyle(CSV2.ink)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(onGreen ? Color.white : CSV2.parFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct HcpTagV2: View {
    let hcp: Int
    var onGreen = false
    var body: some View {
        Text("HCP \(hcp)").font(.v2Label).foregroundStyle(onGreen ? .white : CSV2.ink)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(onGreen ? Color.white : CSV2.secondary, lineWidth: 2))
    }
}

// MARK: - Score mark (golf standard): ○ birdie, ◎ eagle+, □ bogey, ⧈ double+, dashed = empty

struct ScoreMarkV2: View {
    let gross: Int?
    let par: Int
    var size: CGFloat = 44
    var strokeDots: Double = 0      // strokes received on this hole for the match being viewed (0.5 = half)
    var hasEvent = false            // gold marker: event or oye on this hole

    private var diff: Int { (gross ?? par) - par }
    private var color: Color {
        guard gross != nil else { return CSV2.secondary }
        return diff < 0 ? CSV2.green : diff > 0 ? CSV2.red : CSV2.ink
    }

    var body: some View {
        Text(gross.map(String.init) ?? "—")
            .font(.system(size: size * 0.58, weight: .heavy).monospacedDigit())
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .overlay { outline }
            .overlay(alignment: .topTrailing) {
                if strokeDots > 0 {
                    Circle()
                        .fill(strokeDots >= 1 ? CSV2.stroke : .clear)
                        .overlay(Circle().stroke(CSV2.stroke, lineWidth: 1.5))
                        .frame(width: 8, height: 8)
                        .offset(x: 7, y: -5)
                        .accessibilityLabel(strokeDots >= 1 ? "recibe stroke" : "recibe medio stroke")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if hasEvent {
                    RoundedRectangle(cornerRadius: 2).fill(CSV2.unitLine)
                        .frame(width: 8, height: 8).offset(x: -7, y: 5)
                }
            }
    }

    @ViewBuilder private var outline: some View {
        if gross == nil {
            RoundedRectangle(cornerRadius: CSV2.rCell)
                .strokeBorder(CSV2.secondary, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        } else if diff <= -2 {
            ZStack { Circle().strokeBorder(color, lineWidth: 2.5); Circle().strokeBorder(color, lineWidth: 2.5).padding(-5) }
        } else if diff == -1 {
            Circle().strokeBorder(color, lineWidth: 2.5)
        } else if diff == 1 {
            Rectangle().strokeBorder(color, lineWidth: 2.5)
        } else if diff >= 2 {
            ZStack { Rectangle().strokeBorder(color, lineWidth: 2.5); Rectangle().strokeBorder(color, lineWidth: 2.5).padding(-5) }
        }
    }
}

// MARK: - Strokes in words: "ALC recibe 3½" (never +/−)

struct StrokeTextV2: View {
    let receiver: String
    let amount: Double
    var from: String? = nil
    var detail: String? = nil       // e.g. "hoyos 17, 4, 11 y ½ en 2"
    var body: some View {
        HStack(spacing: 6) {
            if amount > 0 { Circle().fill(CSV2.stroke).frame(width: 9, height: 9) }
            Text(text).font(.v2Label).foregroundStyle(amount > 0 ? CSV2.stroke : CSV2.secondary)
        }
    }
    private var text: String {
        guard amount > 0 else { return "sin strokes" }
        var t = "\(receiver) recibe \(strokesTextV2(amount))"
        if let from { t += " de \(from)" }
        if let detail { t += " · \(detail)" }
        return t
    }
}

// MARK: - Event pill: "MIG 3 Putt −1"

struct EventPillV2: View {
    let alias: String
    let label: String
    let units: Int
    var body: some View {
        let sign = units > 0 ? "+\(units)" : "−\(abs(units))"
        Text("\(alias) \(label) \(sign)").font(.v2Label).foregroundStyle(CSV2.unitFg)
            .padding(.horizontal, 12).frame(minHeight: 32)
            .background(CSV2.unitBg, in: Capsule())
    }
}

// MARK: - Oye chip (par 3): rank 1º, 2º… or empty (dashed)

struct OyeChipV2: View {
    let alias: String
    let rank: Int?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(alias).font(.v2Body).foregroundStyle(CSV2.ink)
                if let rank { Text("\(rank)º").font(.v2Label).foregroundStyle(CSV2.unitFg) }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(rank != nil ? CSV2.unitBg : CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCell))
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCell)
                .strokeBorder(CSV2.unitLine, style: StrokeStyle(lineWidth: 2, dash: rank == nil ? [4, 3] : [])))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Match status "2↑" / "E" / "1↓" / "—" (always from DAN's side) and money

struct MatchStatusV2: View {
    let net: Int
    let played: Int
    var size: CGFloat = 16
    var body: some View {
        let (t, c): (String, Color) =
            played == 0 ? ("—", CSV2.secondary) :
            net > 0 ? ("\(net)↑", CSV2.green) :
            net < 0 ? ("\(-net)↓", CSV2.red) : ("E", CSV2.secondary)
        Text(t).font(.system(size: size, weight: .bold).monospacedDigit()).foregroundStyle(c)
    }
}

struct MoneyTextV2: View {
    let amount: Int
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    var body: some View {
        let t = amount > 0 ? "+$\(amount)" : amount < 0 ? "−$\(-amount)" : "$0"
        let c = amount > 0 ? CSV2.green : amount < 0 ? CSV2.red : CSV2.secondary
        Text(t).font(.system(size: size, weight: weight).monospacedDigit()).foregroundStyle(c)
    }
}

// MARK: - Buttons

struct StepButtonV2: View {
    let symbol: String          // "minus" / "plus"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(CSV2.ink)
                .frame(width: CSV2.minTap, height: CSV2.minTap)
                .background(CSV2.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CSV2.line))
        }
        .buttonStyle(.plain)
    }
}

struct HalfButtonV2: View {
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("½").font(.system(size: 18, weight: .bold))
                .foregroundStyle(isOn ? .white : CSV2.ink)
                .frame(width: 44, height: CSV2.minTap)
                .background(isOn ? CSV2.stroke : CSV2.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOn ? CSV2.stroke : CSV2.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Medio stroke activo" : "Medio stroke")
    }
}

struct PrimaryButtonV2: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 16).frame(minHeight: 40)
                .background(CSV2.green, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom bar for every round screen: Tarjeta · Evento · Mic · Nota · Resultado

enum RoundTabV2 { case none, tarjeta, resultado }

struct RoundBarV2: View {
    var active: RoundTabV2 = .none
    var isRecording = false
    let onTarjeta: () -> Void
    let onEvento: () -> Void
    let onMic: () -> Void
    let onNota: () -> Void
    let onResultado: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab("Tarjeta", "square.grid.2x2", on: active == .tarjeta, action: onTarjeta)
            tab("Evento", "plus.circle", tint: CSV2.unitFg, action: onEvento)
            Button(action: onMic) {
                ZStack {
                    Circle().fill(CSV2.green).frame(width: 62, height: 62)
                    if isRecording {
                        Circle().stroke(CSV2.green.opacity(0.25), lineWidth: 6).frame(width: 72, height: 72)
                        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "mic.fill").font(.system(size: 26)).foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain).frame(maxWidth: .infinity)
            .accessibilityLabel(isRecording ? "Detener dictado" : "Dictar el hoyo")
            tab("Nota", "pencil", action: onNota)
            tab("Resultado", "chart.bar", on: active == .resultado, action: onResultado)
        }
        .frame(height: 84)
        .background(CSV2.surface)
        .overlay(alignment: .top) { Rectangle().fill(CSV2.line).frame(height: 1) }
    }

    private func tab(_ title: String, _ icon: String, on: Bool = false, tint: Color = CSV2.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title).font(.system(size: 12, weight: on ? .bold : .semibold))
            }
            .foregroundStyle(on ? CSV2.green : tint)
            .frame(maxWidth: .infinity, minHeight: 64)
            .overlay(alignment: .top) { if on { Rectangle().fill(CSV2.green).frame(height: 3) } }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card container

struct CardV2<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).stroke(CSV2.line))
    }
}

// MARK: - Helper

extension Color {
    init(hexV2 hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

#Preview("Estándar v2") {
    VStack(alignment: .leading, spacing: 16) {
        HStack { ParTagV2(par: 4); HcpTagV2(hcp: 6) }
        HStack(spacing: 16) {
            ScoreMarkV2(gross: 2, par: 4); ScoreMarkV2(gross: 3, par: 4)
            ScoreMarkV2(gross: 4, par: 4, strokeDots: 1)
            ScoreMarkV2(gross: 5, par: 4, strokeDots: 0.5, hasEvent: true)
            ScoreMarkV2(gross: 6, par: 4); ScoreMarkV2(gross: nil, par: 4)
        }
        StrokeTextV2(receiver: "ALC", amount: 3.5, detail: "hoyos 17, 4, 11 y ½ en 2")
        HStack { EventPillV2(alias: "MIG", label: "3 Putt", units: -1); OyeChipV2(alias: "DAN", rank: 1) {} }
        HStack(spacing: 16) {
            MatchStatusV2(net: 2, played: 5); MatchStatusV2(net: 0, played: 5)
            MatchStatusV2(net: -1, played: 5); MoneyTextV2(amount: 125)
        }
        Spacer()
        RoundBarV2(onTarjeta: {}, onEvento: {}, onMic: {}, onNota: {}, onResultado: {})
    }
    .padding().background(CSV2.background)
}
