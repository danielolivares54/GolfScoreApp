//
//  PairsNoticeV2.swift
//  Caddie Score — Vista v2: por qué las parejas no cuentan (y cómo arreglarlo)
//
//  Las parejas pueden estar definidas, con strokes, y aun así no calcularse. Hay tres razones y la app las dice:
//   · No hay pareja base (sin ella no hay carriles).
//   · "Match Parejas" está apagado en el catálogo de apuestas (apaga todas las parejas de golpe).
//   · En un hoyo falta el score de alguno de los cuatro (una pareja cuenta cuando sus cuatro jugadores tienen score).
//

import SwiftUI

enum PairsNoticeV2: Equatable {
    case notDefined
    case offInCatalog
    case missingScores(aliases: [String], hole: Int)
}

extension MatchManager {
    /// Por qué las parejas no cuentan ahora, o nil si todo está bien. `hole`: el hoyo que se mira (para avisar scores faltantes).
    func pairsNoticeV2(hole: Int? = nil) -> PairsNoticeV2? {
        guard players.count >= 4 else { return nil }          // con menos de cuatro jugadores no hay parejas
        if baseTeamAliases.count < 2 || lanes.isEmpty { return .notDefined }
        if !isPairMatchEnabled { return .offInCatalog }
        if let hole {
            let involved = Set(lanes.flatMap { $0.base + $0.opp })
            let scored = involved.filter { getScore(hole: hole, player: $0) > 0 }
            if !scored.isEmpty && scored.count < involved.count {
                let missing = players.map(\.alias).filter { involved.contains($0) && getScore(hole: hole, player: $0) <= 0 }
                return .missingScores(aliases: missing, hole: hole)
            }
        }
        return nil
    }

    func pairsNoticeTextV2(_ notice: PairsNoticeV2) -> String {
        switch notice {
        case .notDefined:
            return "Las parejas no están definidas: sin pareja base no se calcula ese match. Defínela en el Setup."
        case .offInCatalog:
            return "Match Parejas está apagado en el catálogo: por eso las parejas, aunque estén definidas y con strokes, no cuentan."
        case .missingScores(let aliases, let hole):
            return "En el hoyo \(hole) faltan los scores de \(spokenList(aliases.map(spokenName))): una pareja cuenta cuando sus cuatro jugadores tienen score."
        }
    }

    /// Prende "Match Parejas" en el catálogo (lo mismo que su interruptor en el editor de unidades).
    func enablePairMatchV2() {
        let store = BetDefinitionStore.shared
        if let def = store.entries.first(where: { $0.tag == "PAIR" }) { store.setEnabled(def, enabled: true) }
        setupDefaultBets()
    }
}

/// El aviso, con el botón para arreglar lo que se pueda arreglar con un toque.
struct PairsNoticeCardV2: View {
    @ObservedObject var matchManager: MatchManager
    var hole: Int? = nil

    var body: some View {
        if let notice = matchManager.pairsNoticeV2(hole: hole) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Parejas sin calcular", systemImage: "exclamationmark.triangle.fill")
                    .font(.v2Label.weight(.semibold)).foregroundStyle(CSV2.warning)
                Text(matchManager.pairsNoticeTextV2(notice)).font(.v2Label).foregroundStyle(CSV2.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if notice == .offInCatalog {
                    Button { matchManager.enablePairMatchV2() } label: {
                        Text("Prender Match Parejas").font(.v2Body.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(CSV2.green, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
            .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).strokeBorder(CSV2.warning, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }
}
