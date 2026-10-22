//
//  EventSheetV2.swift
//  Caddie Score — Vista v2, Paso 4: unidades del hoyo (las activas del catálogo)
//
//  Mismas llamadas que la v1 (ContentView.unitToggleBtn): upsertUnitEvent / removeUnitEvent sobre
//  unitEventsByHole, con el catálogo manual individual (sin Oyes, que tiene su propia tarjeta).
//

import SwiftUI

extension MatchManager {
    /// 3 Putt y Hole Out no llevan botón en la hoja Unidades (decisión de Daniel, 21-oct): el 3 Putt se marca solo
    /// al anotar los putts y siguen existiendo en el catálogo.
    static let unitsWithoutButtonV2: Set<String> = ["3P", "4P", "HO"]

    /// Unidades manuales individuales activas del catálogo que llevan botón: sin Oyes (tiene su tarjeta) ni 3 Putt / Hole Out.
    var manualUnitBetsV2: [BetDefinition] {
        betCatalog.filter {
            $0.type == .individual && $0.mode == .manual && $0.tag.uppercased() != "OYES"
                && !Self.unitsWithoutButtonV2.contains($0.tag.uppercased())
        }
    }
}

struct EventSheetV2: View {
    @ObservedObject var matchManager: MatchManager
    let hole: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAlias: String?
    @State private var showCatalog = false

    private var alias: String? { selectedAlias ?? matchManager.players.first?.alias }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: CSV2.s2) {
                    HStack {
                        Text("Unidades · hoyo \(hole)").font(.v2Name).foregroundStyle(CSV2.ink)
                        Spacer()
                        PrimaryButtonV2(title: "Listo") { dismiss() }
                    }
                    if matchManager.players.isEmpty {
                        Text("Configura jugadores en Setup.").font(.v2Body).foregroundStyle(CSV2.secondary)
                    } else {
                        playerPicker
                        unitsGrid
                    }
                    Button { showCatalog = true } label: {
                        Label("Editar el catálogo de unidades", systemImage: "slider.horizontal.3")
                            .font(.v2Body).foregroundStyle(CSV2.green).frame(maxWidth: .infinity, minHeight: CSV2.minTap)
                    }
                    .buttonStyle(.plain)
                }
                .padding(CSV2.s2)
            }
        }
        .sheet(isPresented: $showCatalog) { CatalogoV2(matchManager: matchManager) }
    }

    private var playerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Jugador").font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
            HStack(spacing: 6) {
                ForEach(matchManager.players, id: \.id) { player in
                    let on = player.alias == alias
                    Button { selectedAlias = player.alias } label: {
                        Text(player.alias).font(.v2Body).foregroundStyle(on ? .white : CSV2.ink)
                            .frame(maxWidth: .infinity, minHeight: CSV2.minTap)
                            .background(on ? CSV2.green : CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCell))
                            .overlay(RoundedRectangle(cornerRadius: CSV2.rCell).stroke(on ? CSV2.green : CSV2.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(player.name)\(on ? ", seleccionado" : "")")
                }
            }
        }
    }

    /// Las unidades que se capturan a mano salen del catálogo de apuestas (Sandy par, Green en regulación, 3 Putt…):
    /// cada una se define y se activa allá. Aquí no hay botones fijos ni tags escritos a mano.
    private var unitsGrid: some View {
        let active = Set((matchManager.unitEventsByHole[hole] ?? [])
            .filter { $0.alias == alias }.map { $0.code.uppercased() })
        let bets = matchManager.manualUnitBetsV2
        return VStack(alignment: .leading, spacing: 6) {
            Text("Unidades activas").font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
            if bets.isEmpty {
                Text("No hay unidades de captura manual activas. Se definen y se activan en el catálogo de apuestas.")
                    .font(.v2Label).foregroundStyle(CSV2.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(bets, id: \.id) { bet in
                    unitTile(bet, isOn: active.contains(bet.tag.uppercased()))
                }
            }
        }
    }

    private func unitTile(_ bet: BetDefinition, isOn: Bool) -> some View {
        Button {
            guard let alias else { return }
            if isOn { matchManager.removeUnitEvent(hole: hole, alias: alias, code: bet.tag) }
            else { matchManager.upsertUnitEvent(hole: hole, alias: alias, code: bet.tag, units: bet.units) }
        } label: {
            VStack(spacing: 2) {
                Text(bet.name).font(.v2Body).foregroundStyle(isOn ? CSV2.unitFg : CSV2.ink).lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(isOn ? "Agregado" : "\(bet.units) unidad\(bet.units == 1 ? "" : "es")")
                    .font(.v2Label).foregroundStyle(isOn ? CSV2.unitFg : CSV2.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(isOn ? CSV2.unitBg : CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard)
                .strokeBorder(CSV2.unitLine, style: StrokeStyle(lineWidth: 2, dash: isOn ? [] : [4, 3])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(bet.name)\(isOn ? ", agregado" : "")")
    }
}

#if DEBUG
#Preview("EventSheetV2 · hoyo 14") {
    let manager = MatchManager()
    manager.loadDemo18()
    if let tag = manager.manualUnitBetsV2.first?.tag {
        manager.upsertUnitEvent(hole: 14, alias: "DAN", code: tag, units: 1)
    }
    return EventSheetV2(matchManager: manager, hole: 14)
}
#endif
