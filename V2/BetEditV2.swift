//
//  BetEditV2.swift
//  Caddie Score — Vista v2: editar la apuesta de un match (el tag, los valores y lo que cuenta)
//
//  En el reporte del match el tag sale con su NOMBRE (TPCH, no "$50") y al tocarlo se edita ahí mismo:
//   · el tag (la plantilla) de ESE match,
//   · el valor de Vuelta, Presión, Match y Unidad (en pesos),
//   · y qué cuenta: Vuelta, Presión, Match, Carry, Ajuste 50, Oyes y Unidades se prenden o apagan.
//  Individual: los valores son de ese rival. Pareja: los valores son los de las parejas (los mismos para todas).
//  Todo se guarda y el dinero se recalcula al instante.
//

import SwiftUI

// MARK: - Datos (sin pantalla, para probar)

extension MatchManager {
    /// Valores de apuesta de un match: del rival, o los de las parejas.
    func betValuesV2(for target: UnitLogTarget) -> OpponentBetValues {
        switch target {
        case .individual(let alias): return betValues(forOpponent: alias)
        case .pair:
            return OpponentBetValues(templateId: activeTemplateId, vueltaValue: vueltaValue, presionValue: presionValue,
                                     matchValue: matchValue, unitValue: unitValue)
        }
    }

    /// Cambia los valores de un match. Si la unidad seguía a la vuelta (unidad = vuelta ÷ 2), sigue haciéndolo.
    func setBetValuesV2(_ new: OpponentBetValues, for target: UnitLogTarget) {
        var next = new
        next.vueltaValue = max(0, next.vueltaValue); next.presionValue = max(0, next.presionValue)
        next.matchValue = max(0, next.matchValue); next.unitValue = max(0, next.unitValue)
        switch target {
        case .individual(let alias):
            betValuesByOpponent[alias] = next
        case .pair:
            // Los valores de parejas son los globales; un rival que aún no tenía los suyos los usaba por defecto.
            // Se le guardan antes de cambiarlos para que editar las parejas no mueva sus apuestas individuales.
            for opp in players.map(\.alias) where opp != yoAlias && betValuesByOpponent[opp] == nil {
                betValuesByOpponent[opp] = betValues(forOpponent: opp)
            }
            vueltaValue = next.vueltaValue; presionValue = next.presionValue
            matchValue = next.matchValue; unitValue = next.unitValue
        }
        saveBetConfig()
    }

    /// Cambia el valor de la vuelta moviendo la unidad con ella cuando estaban ligadas.
    func setVueltaV2(_ value: Int, for target: UnitLogTarget) {
        var v = betValuesV2(for: target)
        let linked = v.unitValue == v.vueltaValue / 2
        v.vueltaValue = max(0, value)
        if linked { v.unitValue = v.vueltaValue / 2 }
        setBetValuesV2(v, for: target)
    }

    /// Cambia el tag (la plantilla) de un match y le copia sus valores.
    func setTemplateV2(_ template: BetTemplate, for target: UnitLogTarget) {
        switch target {
        case .individual(let alias): setBetTemplateForOpponent(alias, template: template)
        case .pair: applyBetTemplate(template)
        }
    }

    /// Nombre del tag del match ("TPCH"); nil si no tiene plantilla.
    func betTagNameV2(for target: UnitLogTarget) -> String? {
        betValuesV2(for: target).templateId.flatMap { id in BetTemplateStore.shared.entries.first { $0.id == id }?.name }
    }

    /// ¿Los valores del match ya no son los de su plantilla? (se editaron a mano)
    func betIsEditedV2(for target: UnitLogTarget) -> Bool {
        let v = betValuesV2(for: target)
        guard let id = v.templateId, let t = BetTemplateStore.shared.entries.first(where: { $0.id == id }) else { return false }
        return (t.vueltaValue, t.presionValue, t.matchValue, t.unitValue) != (v.vueltaValue, v.presionValue, v.matchValue, v.unitValue)
    }

    /// Lo que se muestra en el reporte en lugar de "Tag $50": "TPCH" o "TPCH · editado".
    func betTagLabelV2(for target: UnitLogTarget) -> String {
        guard let name = betTagNameV2(for: target) else { return "Apuesta" }
        return betIsEditedV2(for: target) ? "\(name) · editado" : name
    }
}

// MARK: - Pantalla

struct BetEditSheetV2: View {
    @ObservedObject var matchManager: MatchManager
    let target: UnitLogTarget
    let title: String
    @ObservedObject private var templates = BetTemplateStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCatalog = false

    private var isPair: Bool { if case .pair = target { return true } else { return false } }

    var body: some View {
        let values = matchManager.betValuesV2(for: target)
        let switches = matchManager.betSwitchesV2(for: target)
        ZStack {
            CSV2.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: CSV2.s2) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Editar apuesta").font(.v2Name).foregroundStyle(CSV2.ink)
                            Text(title).font(.v2Label).foregroundStyle(CSV2.secondary)
                        }
                        Spacer()
                        PrimaryButtonV2(title: "Listo") { dismiss() }
                    }
                    Text(isPair
                         ? "Los valores de las parejas son los mismos para todas las parejas."
                         : "Estos valores son solo de este match. Lo que apagues deja de contar al momento.")
                        .font(.v2Label).foregroundStyle(CSV2.secondary)
                    tagCard
                    CardV2 {
                        VStack(spacing: 0) {
                            conceptRow("Vuelta", on: \.vuelta, switches: switches, value: values.vueltaValue) { matchManager.setVueltaV2($0, for: target) }
                            RowDividerV2()
                            conceptRow("Presión", on: \.presion, switches: switches, value: values.presionValue) { var v = values; v.presionValue = $0; matchManager.setBetValuesV2(v, for: target) }
                            RowDividerV2()
                            conceptRow("Match", on: \.match, switches: switches, value: values.matchValue) { var v = values; v.matchValue = $0; matchManager.setBetValuesV2(v, for: target) }
                            RowDividerV2()
                            conceptRow("Unidades", on: \.units, switches: switches, value: values.unitValue, note: "cada unidad vale") { var v = values; v.unitValue = $0; matchManager.setBetValuesV2(v, for: target) }
                            RowDividerV2()
                            conceptRow("Carry", on: \.carry, switches: switches, value: nil)
                            RowDividerV2()
                            conceptRow("Ajuste 50", on: \.adjust50, switches: switches, value: nil)
                            RowDividerV2()
                            oyesRow(switches)
                        }
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

    // MARK: Tag

    private var tagCard: some View {
        CardV2 {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tag").capsStyleV2()
                    Text(matchManager.betTagLabelV2(for: target)).font(.v2Name).foregroundStyle(CSV2.ink)
                }
                Spacer()
                Menu {
                    ForEach(templates.entries) { t in
                        Button(t.name) { matchManager.setTemplateV2(t, for: target) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Cambiar").font(.v2Body)
                        Image(systemName: "chevron.down").font(.system(.caption, weight: .bold))
                    }
                    .foregroundStyle(CSV2.green)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(CSV2.green.opacity(0.4)))
                }
            }
            .padding(CSV2.s2)
        }
    }

    // MARK: Conceptos: se prenden / apagan y (los que tienen valor) se editan

    private func conceptRow(_ name: String, on keyPath: WritableKeyPath<MatchBetSwitches, Bool>, switches: MatchBetSwitches,
                            value: Int?, note: String? = nil, onValue: ((Int) -> Void)? = nil) -> some View {
        let isOn = switches[keyPath: keyPath]
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { isOn }, set: { newValue in
                var next = matchManager.betSwitchesV2(for: target); next[keyPath: keyPath] = newValue
                matchManager.setBetSwitchesV2(next, for: target)
            })) {
                Text(name).font(.v2Name).foregroundStyle(isOn ? CSV2.ink : CSV2.secondary).strikethrough(!isOn)
            }
            .tint(CSV2.green)
            if let value, let onValue {
                ValueEditorV2(label: note ?? "vale", value: value, dimmed: !isOn, onChange: onValue)
            }
        }
        .padding(CSV2.s2)
    }

    private func oyesRow(_ switches: MatchBetSwitches) -> some View {
        let blocked = matchManager.catalogBlocksV2("Oyes", pair: isPair)
        let on = switches.oyes && !blocked
        let units = matchManager.catalogUnits(forTag: isPair ? "OYESP" : "OYES") ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { on }, set: { newValue in
                var next = matchManager.betSwitchesV2(for: target); next.oyes = newValue
                matchManager.setBetSwitchesV2(next, for: target)
            })) {
                Text("Oyes").font(.v2Name).foregroundStyle(on ? CSV2.ink : CSV2.secondary).strikethrough(!on)
            }
            .tint(CSV2.green)
            .disabled(blocked)
            Text(blocked ? "Apagado en el catálogo" : "Vale \(units) unidad\(units == 1 ? "" : "es") (se cambia en el catálogo)")
                .font(.v2Label).foregroundStyle(CSV2.secondary)
        }
        .padding(CSV2.s2)
    }
}

/// "$ 50" con − y + de 5 en 5 y el número editable.
struct ValueEditorV2: View {
    let label: String
    let value: Int
    var dimmed = false
    let onChange: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.v2Label).foregroundStyle(CSV2.secondary)
            Spacer()
            StepButtonV2(symbol: "minus") { onChange(max(0, value - 5)) }.accessibilityLabel("\(label): 5 pesos menos")
            HStack(spacing: 2) {
                Text("$").font(.v2Body).foregroundStyle(CSV2.secondary)
                TextField("0", text: $text)
                    .keyboardType(.numberPad).font(.v2Body.monospacedDigit()).multilineTextAlignment(.trailing)
                    .frame(minWidth: 56, maxWidth: 90)
                    .focused($focused)
                    .onChange(of: text) { _, new in
                        let digits = new.filter(\.isNumber)
                        if digits != new { text = digits }
                        if focused, let n = Int(digits), n != value { onChange(n) }
                    }
            }
            .padding(.horizontal, 10).frame(minHeight: 44)
            .background(CSV2.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CSV2.line))
            StepButtonV2(symbol: "plus") { onChange(value + 5) }.accessibilityLabel("\(label): 5 pesos más")
        }
        .opacity(dimmed ? 0.5 : 1)
        .onAppear { text = String(value) }
        .onChange(of: value) { _, new in if !focused { text = String(new) } }
    }
}

#if DEBUG
#Preview("BetEditSheetV2 · ROB") {
    let manager = MatchManager()
    manager.loadDemo18()
    return BetEditSheetV2(matchManager: manager, target: .individual("ROB"), title: "vs Roberto")
}
#endif
