//
//  BetSwitchesV2.swift
//  Caddie Score — Vista v2: apuestas activas de cada match, editables al momento
//
//  "No, yo no apuesto oyes": cada match (rival o pareja) enseña su apuesta (el tag) con lo que está ENCENDIDO —
//  Vuelta, Presión, Carry, Ajuste 50, Match, Oyes, Unidades— y se apaga o prende con un toque. Se guarda en
//  MatchBetSwitches (las mismas banderas que usa el cálculo de dinero de la v1), sin tocar el catálogo.
//  Lo apagado deja de contar de inmediato; al prenderlo vuelve todo.
//

import SwiftUI

// MARK: - Datos (sin pantalla, para probar)

extension MatchBetSwitches {
    /// Las banderas en el orden en que se muestran, con su nombre.
    static let items: [(label: String, keyPath: WritableKeyPath<MatchBetSwitches, Bool>)] = [
        ("Vuelta", \.vuelta), ("Presión", \.presion), ("Carry", \.carry), ("Ajuste 50", \.adjust50),
        ("Match", \.match), ("Oyes", \.oyes), ("Unidades", \.units)
    ]

    /// "Vuelta · Presión · Match" — lo que está encendido.
    var onText: String {
        let on = Self.items.filter { self[keyPath: $0.keyPath] }.map(\.label)
        return on.isEmpty ? "ninguna" : on.joined(separator: " · ")
    }

    /// Lo apagado, para avisarlo ("sin Oyes").
    var offLabels: [String] { Self.items.filter { !self[keyPath: $0.keyPath] }.map(\.label) }
}

extension MatchManager {
    /// Un match editable: rival individual o pareja.
    struct BetSwitchTargetV2: Identifiable {
        let target: UnitLogTarget
        let title: String
        let tag: String?          // plantilla del match ("TPCH") con sus valores
        var id: String { target.id }
    }

    /// Los matches de la ronda: primero los individuales, luego las parejas activas.
    func betSwitchTargetsV2() -> [BetSwitchTargetV2] {
        var out: [BetSwitchTargetV2] = []
        for opp in players where opp.alias != yoAlias {
            let values = betValues(forOpponent: opp.alias)
            out.append(.init(target: .individual(opp.alias), title: "vs \(opp.name)",
                             tag: betSummaryV2(templateId: values.templateId, values: values)))
        }
        for lane in activeLanes {
            let mine = lane.base.contains(yoAlias)
            let partners = (mine ? lane.base : lane.opp).filter { $0 != yoAlias }
            let rivals = mine ? lane.opp : lane.base
            let title = (partners.isEmpty ? "Pareja" : "con " + partners.joined(separator: " – ")) + " vs " + rivals.joined(separator: " – ")
            let values = OpponentBetValues(templateId: activeTemplateId, vueltaValue: vueltaValue, presionValue: presionValue,
                                           matchValue: matchValue, unitValue: unitValue)
            out.append(.init(target: .pair(lane.id), title: title, tag: betSummaryV2(templateId: activeTemplateId, values: values)))
        }
        return out
    }

    func betSwitchesV2(for target: UnitLogTarget) -> MatchBetSwitches {
        switch target {
        case .individual(let alias): return betSwitchesForIndividual(opponentAlias: alias)
        case .pair(let laneId):      return betSwitchesForPair(laneId: laneId)
        }
    }

    func setBetSwitchesV2(_ switches: MatchBetSwitches, for target: UnitLogTarget) {
        switch target {
        case .individual(let alias): setBetSwitchesForIndividual(opponentAlias: alias, switches: switches)
        case .pair(let laneId):      setBetSwitchesForPair(laneId: laneId, switches: switches)
        }
    }

    /// ¿El catálogo (global) tiene apagada esa bandera? Entonces el interruptor del match no puede encenderla.
    func catalogBlocksV2(_ label: String, pair: Bool) -> Bool {
        label == "Oyes" && !(pair ? (isOyesPairEnabled && isPairMatchEnabled) : isOyesEnabled)
    }

    /// Resumen corto de toda la ronda: "todas activas" o "sin Oyes en 2 matches".
    var betSwitchesSummaryV2: String {
        let all = betSwitchTargetsV2().map { betSwitchesV2(for: $0.target) }
        guard !all.isEmpty else { return "sin matches" }
        let off = MatchBetSwitches.items.compactMap { item -> String? in
            let n = all.filter { !$0[keyPath: item.keyPath] }.count
            return n == 0 ? nil : (n == all.count ? "sin \(item.label)" : "sin \(item.label) en \(n)")
        }
        return off.isEmpty ? "todas activas" : off.joined(separator: " · ")
    }

    /// Apaga o prende una bandera en todos los matches a la vez ("nadie apuesta oyes").
    func setAllBetSwitchesV2(_ keyPath: WritableKeyPath<MatchBetSwitches, Bool>, to value: Bool) {
        for entry in betSwitchTargetsV2() {
            var sw = betSwitchesV2(for: entry.target)
            sw[keyPath: keyPath] = value
            setBetSwitchesV2(sw, for: entry.target)
        }
    }
}

// MARK: - Fichas de un match

struct BetSwitchChipsV2: View {
    @ObservedObject var matchManager: MatchManager
    let target: UnitLogTarget

    private var isPair: Bool { if case .pair = target { return true } else { return false } }

    var body: some View {
        let switches = matchManager.betSwitchesV2(for: target)
        FlowChipsV2 {
            ForEach(MatchBetSwitches.items, id: \.label) { item in
                let blocked = matchManager.catalogBlocksV2(item.label, pair: isPair)
                let on = switches[keyPath: item.keyPath] && !blocked
                Button {
                    var next = switches
                    next[keyPath: item.keyPath].toggle()
                    matchManager.setBetSwitchesV2(next, for: target)
                } label: {
                    Text(item.label)
                        .font(.v2Label.weight(.semibold))
                        .strikethrough(!on)
                        .foregroundStyle(on ? .white : CSV2.secondary)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(on ? CSV2.green : CSV2.surface, in: Capsule())
                        .overlay(Capsule().stroke(on ? CSV2.green : CSV2.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(blocked)
                .accessibilityLabel("\(item.label), \(on ? "activa" : blocked ? "apagada en el catálogo" : "apagada")")
                .accessibilityHint(blocked ? "" : "Toca para \(on ? "apagarla" : "prenderla")")
            }
        }
    }
}

/// Fichas que saltan de renglón cuando no caben (con letra grande también).
struct FlowChipsV2<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        FlowLayoutV2(spacing: 8) { content }
    }
}

private struct FlowLayoutV2: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

// MARK: - Pantalla: apuestas de la ronda

struct BetSwitchesSheetV2: View {
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    @State private var showCatalog = false

    var body: some View {
        let entries = matchManager.betSwitchTargetsV2()
        ZStack {
            CSV2.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: CSV2.s2) {
                    HStack {
                        Text("Apuestas activas").font(.v2Name).foregroundStyle(CSV2.ink)
                        Spacer()
                        PrimaryButtonV2(title: "Listo") { dismiss() }
                    }
                    Text("Lo que apagues deja de contar al momento en ese match; si lo vuelves a prender, regresa todo. No cambia el catálogo.")
                        .font(.v2Label).foregroundStyle(CSV2.secondary)
                    PairsNoticeCardV2(matchManager: matchManager)
                    if entries.isEmpty {
                        Text("Configura jugadores en Setup para ver las apuestas.").font(.v2Body).foregroundStyle(CSV2.secondary)
                    } else {
                        oyesForEveryone
                        ForEach(entries) { entry in matchCard(entry) }
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
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showCatalog) { CatalogoV2(matchManager: matchManager) }
    }

    /// "Nadie apuesta oyes": un toque en vez de uno por match.
    private var oyesForEveryone: some View {
        let all = matchManager.betSwitchTargetsV2().map { matchManager.betSwitchesV2(for: $0.target).oyes }
        let allOn = all.allSatisfy { $0 }
        return CardV2 {
            Toggle(isOn: Binding(get: { allOn }, set: { matchManager.setAllBetSwitchesV2(\.oyes, to: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Oyes en todos los matches").font(.v2Body).foregroundStyle(CSV2.ink)
                    Text(allOn ? "Todos apuestan oyes" : (all.contains(true) ? "Solo en algunos" : "Nadie apuesta oyes"))
                        .font(.v2Label).foregroundStyle(CSV2.secondary)
                }
            }
            .tint(CSV2.green)
            .padding(CSV2.s2).frame(minHeight: CSV2.minTap)
        }
    }

    private func matchCard(_ entry: MatchManager.BetSwitchTargetV2) -> some View {
        let switches = matchManager.betSwitchesV2(for: entry.target)
        return CardV2 {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title).font(.v2Name).foregroundStyle(CSV2.ink)
                if let tag = entry.tag { Text(tag).font(.v2Label).foregroundStyle(CSV2.secondary) }
                BetSwitchChipsV2(matchManager: matchManager, target: entry.target)
                Text(switches.offLabels.isEmpty ? "Todo activo" : "Apagado: " + switches.offLabels.joined(separator: ", "))
                    .font(.v2Label).foregroundStyle(switches.offLabels.isEmpty ? CSV2.secondary : CSV2.warning)
            }
            .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview("BetSwitchesSheetV2") {
    let manager = MatchManager()
    manager.loadDemo18()
    var sw = manager.betSwitchesForIndividual(opponentAlias: "ROB")
    sw.oyes = false
    manager.setBetSwitchesForIndividual(opponentAlias: "ROB", switches: sw)
    return BetSwitchesSheetV2(matchManager: manager)
}
#endif
