//
//  CatalogoV2.swift
//  Caddie Score — Vista v2, Paso 11: editar el catálogo de apuestas (el "tag")
//
//  Qué cuenta y cuántas unidades vale. Cada cambio se guarda en BetDefinitionStore (el mismo catálogo global de
//  la v1) y se aplica al match en curso al instante (MatchManager.setupDefaultBets). Reglas:
//   · Oyes, Oyes Parejas y Match Parejas se pueden apagar de verdad (dejan de contar y de pedirse).
//   · El "Vale" de cada unidad se usa (también el de Oyes).
//   · Las unidades que crea el usuario (Sandy par, Green en regulación…) se pueden renombrar y borrar; las que trae la
//     app solo se apagan o cambian de valor. Una unidad apagada deja de contar pero sus eventos se conservan.
//   · Las unidades nuevas son de captura manual e individuales (las de parejas no tienen dónde capturarse).
//

import SwiftUI

struct CatalogoV2: View {
    @ObservedObject var matchManager: MatchManager
    @ObservedObject private var store = BetDefinitionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false
    @State private var renaming: BetDefinition?
    @State private var renameText = ""
    @State private var deleting: BetDefinition?

    private var individual: [BetDefinition] {
        store.entries.filter { $0.type == .individual }.sorted { $0.name < $1.name }
    }
    /// "Match Parejas" no aparece: las parejas cuentan siempre que haya pareja base en el Setup.
    private var parejas: [BetDefinition] {
        store.entries.filter { $0.type == .parejas && $0.tag != "PAIR" }.sorted { $0.name < $1.name }
    }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: CSV2.s2) {
                        Text("Qué cuenta y cuántas unidades vale. Lo que apagues deja de contar en el match en curso; lo que reactives vuelve a contar. Las parejas cuentan siempre que haya pareja base en el Setup.")
                            .font(.v2Label).foregroundStyle(CSV2.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        group("Individual", individual)
                        group("Parejas", parejas)
                    }
                    .padding(CSV2.s2)
                }
            }
        }
        .onChange(of: store.entries) { _, _ in matchManager.setupDefaultBets() }
        .sheet(isPresented: $showNew) { NewUnitSheetV2() }
        .alert("Renombrar unidad", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") { if let def = renaming { store.rename(def, name: renameText) }; renaming = nil }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("¿Borrar esta unidad?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar \(deleting?.name ?? "")", role: .destructive) {
                if let def = deleting { store.removeCustom(def) }
                deleting = nil
            }
            Button("Cancelar", role: .cancel) { deleting = nil }
        } message: {
            Text("Los eventos ya anotados con esta unidad dejan de contar.")
        }
    }

    private var header: some View {
        HStack {
            BackButtonV2 { dismiss() }
            Spacer()
            Text("Catálogo de apuestas").font(.v2Name).foregroundStyle(CSV2.ink)
            Spacer()
            PrimaryButtonV2(title: "Nueva") { showNew = true }
        }
        .padding(.horizontal, CSV2.s2)
    }

    @ViewBuilder private func group(_ title: String, _ defs: [BetDefinition]) -> some View {
        if !defs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).capsStyleV2()
                CardV2 {
                    VStack(spacing: 0) {
                        ForEach(Array(defs.enumerated()), id: \.element.id) { index, def in
                            if index > 0 { RowDividerV2() }
                            row(def)
                        }
                    }
                }
            }
        }
    }

    private func modeText(_ def: BetDefinition) -> String {
        if def.tag == BetDefinitionStore.puttsTag { return "Apuesta de putts · menos putts en el alcance" }
        switch def.tag.uppercased() {
        case "OYES": return "Puesto en los par 3"
        case "OYESP": return "Mejor puesto de cada pareja en los par 3"
        case "PAIR": return "Match de parejas completo"
        default: return def.mode == .calculado ? "Calculada · \(def.description)" : "Captura manual"
        }
    }

    private func row(_ def: BetDefinition) -> some View {
        let builtIn = store.isBuiltIn(def)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name).font(.v2Name).foregroundStyle(def.isEnabled ? CSV2.ink : CSV2.secondary)
                    Text(modeText(def)).font(.v2Label).foregroundStyle(CSV2.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { def.isEnabled }, set: { store.setEnabled(def, enabled: $0) }))
                    .labelsHidden().tint(CSV2.green)
                    .accessibilityLabel("\(def.name) \(def.isEnabled ? "activa" : "apagada")")
            }
            HStack(spacing: 8) {
                Text("Vale").font(.v2Body).foregroundStyle(CSV2.secondary)
                Spacer()
                StepButtonV2(symbol: "minus") { store.setUnits(def, units: def.units - 1) }
                    .accessibilityLabel("Una unidad menos")
                Text("\(def.units)").font(.v2Score).foregroundStyle(CSV2.ink).frame(minWidth: 44)
                StepButtonV2(symbol: "plus") { store.setUnits(def, units: def.units + 1) }
                    .accessibilityLabel("Una unidad más")
                Text(def.units == 1 ? "unidad" : "unidades").font(.v2Label).foregroundStyle(CSV2.secondary)
            }
            if def.tag == BetDefinitionStore.puttsTag {
                Picker("Alcance", selection: Binding(get: { def.puttsScope ?? .hole18 }, set: { store.setPuttsScope(def, scope: $0) })) {
                    Text("F9").tag(PuttsBetMode.f9)
                    Text("B9").tag(PuttsBetMode.b9)
                    Text("18").tag(PuttsBetMode.hole18)
                    Text("Vuelta").tag(PuttsBetMode.byRound)
                }
                .pickerStyle(.segmented)
            }
            if !builtIn {
                HStack(spacing: 12) {
                    Button { renameText = def.name; renaming = def } label: {
                        Label("Renombrar", systemImage: "pencil").font(.v2Body).foregroundStyle(CSV2.green)
                            .frame(minHeight: CSV2.minTap)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { deleting = def } label: {
                        Label("Borrar", systemImage: "trash").font(.v2Body).foregroundStyle(CSV2.red)
                            .frame(minHeight: CSV2.minTap)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(CSV2.s2)
        .opacity(def.isEnabled ? 1 : 0.6)
    }
}

/// Alta de una unidad nueva: captura manual e individual (Sandy par, Green en regulación, Chip…).
private struct NewUnitSheetV2: View {
    @ObservedObject private var store = BetDefinitionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var units = 1

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: CSV2.s2) {
                HStack {
                    Button { dismiss() } label: {
                        Text("Cancelar").font(.v2Body).foregroundStyle(CSV2.ink).frame(minHeight: CSV2.minTap)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Nueva unidad").font(.v2Name).foregroundStyle(CSV2.ink)
                    Spacer()
                    Button {
                        store.upsert(BetDefinition(tag: store.suggestTag(forName: cleanName), name: cleanName, type: .individual,
                                                   mode: .manual, units: units, description: "Manual"))
                        dismiss()
                    } label: {
                        Text("Guardar").font(.system(.subheadline, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(minHeight: 40)
                            .background(CSV2.green, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain).disabled(cleanName.isEmpty).opacity(cleanName.isEmpty ? 0.4 : 1)
                }
                TextField("Nombre (ej. Sandy par, Green en regulación)", text: $name)
                    .font(.v2Body).padding(.horizontal, 14).frame(minHeight: CSV2.minTap)
                    .background(CSV2.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CSV2.line))
                HStack(spacing: 8) {
                    Text("Vale").font(.v2Body).foregroundStyle(CSV2.secondary)
                    Spacer()
                    StepButtonV2(symbol: "minus") { units = max(1, units - 1) }
                    Text("\(units)").font(.v2Score).foregroundStyle(CSV2.ink).frame(minWidth: 44)
                    StepButtonV2(symbol: "plus") { units = min(20, units + 1) }
                    Text(units == 1 ? "unidad" : "unidades").font(.v2Label).foregroundStyle(CSV2.secondary)
                }
                Text("Las unidades nuevas son individuales y de captura manual: se marcan con un toque en la hoja Unidades de cada hoyo. Las calculadas (birdie, águila…) vienen con la app.")
                    .font(.v2Label).foregroundStyle(CSV2.secondary)
                Spacer()
            }
            .padding(CSV2.s2)
        }
    }
}

#if DEBUG
#Preview("CatalogoV2") {
    let manager = MatchManager()
    manager.loadDemo18()
    return CatalogoV2(matchManager: manager)
}
#endif
