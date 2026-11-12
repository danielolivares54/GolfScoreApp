//
//  SkinsV2.swift
//  Caddie Score — Vista v2: Skins (ventana aparte con la tarjeta de netos de quienes juegan)
//
//  Por hoyo gana el skin quien le gana en neto a todos los demás (con los strokes que se dan cada dos jugadores). Si arriba hay
//  empate el skin se acumula al siguiente hoyo y quien gane después se lleva todos los acumulados. Los datos salen de
//  MatchManager.skinsSummary(); aquí solo se muestran y se eligen los jugadores. Se enciende y se le pone valor en el Catálogo.
//

import SwiftUI

struct SkinsV2: View {
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    /// Hoyo abierto para ver los netos entre cada pareja de jugadores.
    @State private var expandedHole: Int?

    var body: some View {
        let parts = matchManager.skinsPlayerAliases
        let summary = matchManager.skinsSummary()
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: CSV2.s2) {
                        if !matchManager.isSkinsEnabled {
                            notice("Skins está apagado. Préndelo en el Catálogo de apuestas y ponle cuántas unidades vale cada skin.")
                        } else {
                            playersCard
                            if parts.count < 2 {
                                notice("Elige al menos dos jugadores para jugar Skins.")
                            } else {
                                totalsCard(summary, parts)
                                cardTable(summary, parts)
                            }
                        }
                    }
                    .padding(CSV2.s2)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: Piezas

    private var header: some View {
        HStack {
            BackButtonV2 { dismiss() }
            Spacer()
            let units = matchManager.skinUnits
            Text("Skins · cada uno vale \(units) \(units == 1 ? "unidad" : "unidades")").font(.v2Name).foregroundStyle(CSV2.ink)
        }
        .padding(.horizontal, CSV2.s2)
    }

    private func notice(_ text: String) -> some View {
        Text(text).font(.v2Body).foregroundStyle(CSV2.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(CSV2.s2)
    }

    private var playersCard: some View {
        CardV2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quién juega").capsStyleV2()
                FlowChipsV2 {
                    ForEach(matchManager.players, id: \.alias) { player in
                        let playing = matchManager.skinsPlayerAliases.contains(player.alias)
                        Button {
                            matchManager.setSkinsParticipant(player.alias, playing: !playing)
                        } label: {
                            Text(player.alias)
                                .font(.v2Label.weight(.semibold))
                                .foregroundStyle(playing ? .white : CSV2.secondary)
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(playing ? CSV2.green : CSV2.surface, in: Capsule())
                                .overlay(Capsule().stroke(playing ? CSV2.green : CSV2.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(player.name), \(playing ? "juega Skins" : "no juega Skins")")
                    }
                }
            }
            .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Skins ganados y unidades netas de cada jugador: cada skin se lo paga cada uno de los demás.
    private func totalsCard(_ summary: SkinsSummary, _ parts: [String]) -> some View {
        let units = matchManager.skinUnits
        let totalWins = summary.wins.values.reduce(0, +)
        return CardV2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Skins ganados").capsStyleV2()
                ForEach(parts, id: \.self) { alias in
                    let wins = summary.wins[alias] ?? 0
                    let net = (wins * (parts.count - 1) - (totalWins - wins)) * units
                    HStack {
                        Text(alias).font(.v2Name).foregroundStyle(CSV2.ink)
                        Spacer()
                        Text("\(wins) \(wins == 1 ? "skin" : "skins")").font(.v2Body).foregroundStyle(CSV2.secondary)
                        Text(net > 0 ? "+\(net)" : "\(net)")
                            .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                            .foregroundStyle(net > 0 ? CSV2.green : net < 0 ? CSV2.red : CSV2.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                }
                if summary.pending > 0 {
                    Text("En juego: \(summary.pending) \(summary.pending == 1 ? "skin acumulado" : "skins acumulados") sin ganador")
                        .font(.v2Label).foregroundStyle(CSV2.warning)
                }
            }
            .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cardTable(_ summary: SkinsSummary, _ parts: [String]) -> some View {
        CardV2 {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("HOYO").frame(width: 48, alignment: .leading)
                    ForEach(parts, id: \.self) { Text($0).frame(maxWidth: .infinity) }
                    Text("SKIN").frame(width: 72, alignment: .trailing)
                }
                .font(.v2Label.weight(.semibold)).foregroundStyle(CSV2.secondary)
                .padding(.horizontal, CSV2.s2).padding(.vertical, 8)
                if summary.holes.isEmpty {
                    RowDividerV2()
                    Text("Todavía no hay hoyos con el score de todos.").font(.v2Label).foregroundStyle(CSV2.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(CSV2.s2)
                }
                ForEach(summary.holes) { result in
                    RowDividerV2()
                    holeRow(result, parts)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func holeRow(_ result: SkinsHoleResult, _ parts: [String]) -> some View {
        let expanded = expandedHole == result.hole
        return VStack(spacing: 6) {
            Button {
                expandedHole = expanded ? nil : result.hole
            } label: {
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(result.hole)").font(.system(.body, design: .rounded, weight: .bold).monospacedDigit()).foregroundStyle(CSV2.ink)
                        if let par = matchManager.getHole(result.hole)?.par {
                            Text("P\(par)").font(.v2Label).foregroundStyle(CSV2.secondary)
                        }
                    }
                    .frame(width: 48, alignment: .leading)
                    ForEach(parts, id: \.self) { alias in
                        let won = result.winner == alias
                        Text("\(result.grosses[alias] ?? 0)")
                            .font(.system(.body, design: .rounded, weight: won ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(won ? .white : CSV2.ink)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(won ? CSV2.green : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    resultLabel(result).frame(width: 72, alignment: .trailing)
                }
                .padding(.horizontal, CSV2.s2).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Oculta los netos" : "Muestra los netos entre cada pareja de jugadores")
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Netos entre cada dos jugadores (con los strokes que se dan)").font(.v2Label).foregroundStyle(CSV2.secondary)
                    ForEach(Array(result.pairs.enumerated()), id: \.offset) { _, pair in
                        HStack {
                            Text("\(pair.a) \(MatchManager.skinsNumber(pair.netA))")
                                .foregroundStyle(pair.netA < pair.netB ? CSV2.green : CSV2.ink)
                            Spacer()
                            Text("vs").foregroundStyle(CSV2.secondary)
                            Spacer()
                            Text("\(MatchManager.skinsNumber(pair.netB)) \(pair.b)")
                                .foregroundStyle(pair.netB < pair.netA ? CSV2.green : CSV2.ink)
                        }
                        .font(.v2Label.monospacedDigit())
                    }
                }
                .padding(.horizontal, CSV2.s2).padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder private func resultLabel(_ result: SkinsHoleResult) -> some View {
        if let winner = result.winner {
            Text(result.skins > 1 ? "\(winner) ×\(result.skins)" : winner)
                .font(.v2Label.weight(.bold)).foregroundStyle(CSV2.green)
        } else {
            Text("se acumula · \(result.pot)").font(.v2Label).foregroundStyle(CSV2.warning)
                .multilineTextAlignment(.trailing)
        }
    }
}

#if DEBUG
#Preview("SkinsV2") {
    let manager = MatchManager()
    manager.loadDemo18()
    manager.betCatalog = [BetDefinition(tag: "SKIN", name: "Skins", type: .individual, mode: .calculado, units: 2, description: "")]
    manager.skinsParticipantAliases = ["DAN", "ROB", "FER"]
    return SkinsV2(matchManager: manager)
}
#endif
