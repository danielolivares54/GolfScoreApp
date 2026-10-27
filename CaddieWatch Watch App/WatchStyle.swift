//
//  WatchStyle.swift
//  Mismos colores y pesos que CaddieStyleV2 (iPhone), pensados para el reloj: el fondo es el crema de la app
//  y el texto escala con Dynamic Type.
//

import SwiftUI

enum CSW {
    static let ink        = Color(hex: 0x1A1A17)
    static let secondary  = Color(hex: 0x5E584C)
    static let background = Color(hex: 0xF7F3EA)
    static let surface    = Color.white
    static let line       = Color(hex: 0xE4DCCB)
    static let green      = Color(hex: 0x157A3B)   // acción · bajo par
    static let red        = Color(hex: 0xB3261E)
    static let unitBg     = Color(hex: 0xF3E2B3)   // solo eventos / oyes
    static let unitFg     = Color(hex: 0x6E4600)
    static let warning    = Color(hex: 0xB45309)   // falta / dudoso
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    static let wScore = Font.system(.title2, weight: .heavy).monospacedDigit()
    static let wName  = Font.system(.footnote, weight: .bold)
    static let wBody  = Font.system(.footnote, weight: .semibold).monospacedDigit()
    static let wCaps  = Font.system(.caption2, weight: .bold)
}

/// Botón principal verde, como PrimaryButtonV2 del iPhone.
struct WatchPrimaryButton: View {
    let title: String
    var color: Color = CSW.green
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(.headline, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background((enabled ? color : CSW.secondary.opacity(0.5)), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
