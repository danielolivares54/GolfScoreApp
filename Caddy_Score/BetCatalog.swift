import Foundation
import SwiftUI

// MARK: - BetTemplate

struct BetTemplate: Identifiable {
    let id: String
    let name: String
    let vueltaValue: Int
    let presionValue: Int
    let matchValue: Int
    let unitValue: Int
    let puttsEnabled: Bool
    let puttsBetMode: PuttsBetMode
    let puttsBetUnits: Int
    let b9MultiplierAvailable: Bool
    let activeUnitTags: Set<String>
}

// MARK: - Catálogo de templates

extension BetTemplate {
    static let catalog: [BetTemplate] = [syd, syd4, jueves, tpch, fdez]

    static let syd = BetTemplate(
        id: "SYD", name: "S y D",
        vueltaValue: 50, presionValue: 50, matchValue: 100, unitValue: 25,
        puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
        b9MultiplierAvailable: true,
        activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "B18", "OYES"]
    )

    static let syd4 = BetTemplate(
        id: "SYD4", name: "S y D 4",
        vueltaValue: 40, presionValue: 40, matchValue: 80, unitValue: 20,
        puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
        b9MultiplierAvailable: true,
        activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "B18", "OYES"]
    )

    // Jueves: incluye apuesta de putts por 18H
    static let jueves = BetTemplate(
        id: "JUEVES", name: "Jueves",
        vueltaValue: 40, presionValue: 40, matchValue: 80, unitValue: 20,
        puttsEnabled: true, puttsBetMode: .hole18, puttsBetUnits: 2,
        b9MultiplierAvailable: true,
        activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "B18", "OYES"]
    )

    static let tpch = BetTemplate(
        id: "TPCH", name: "TPCH",
        vueltaValue: 20, presionValue: 20, matchValue: 40, unitValue: 10,
        puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
        b9MultiplierAvailable: false,
        activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "OYES"]
    )

    // Fdez: valores pendientes de confirmar — usa S y D por defecto
    static let fdez = BetTemplate(
        id: "FDEZ", name: "Fdez",
        vueltaValue: 50, presionValue: 50, matchValue: 100, unitValue: 25,
        puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
        b9MultiplierAvailable: true,
        activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "B18", "OYES"]
    )
}

// MARK: - BetSetupSheet

struct BetSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    // Valores editables locales
    @State private var vueltaText = ""
    @State private var presionText = ""
    @State private var matchText = ""
    @State private var unitText = ""

    // Apuestas activas — mismo modelo que GuidedSetupView.apuestasStep (Set<UUID> sobre matchManager.betCatalog).
    // Antes había una lista de 7 tags hardcodeados aquí, distinta de la del Setup, y no incluía apuestas de parejas.
    @State private var selectedBetIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.965, green: 0.953, blue: 0.925).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        templatePickerSection
                        valoresSection
                        unidadesToggleSection
                        betSelectionSection(title: "APUESTAS INDIVIDUALES", type: .individual)
                        betSelectionSection(title: "APUESTAS POR PAREJAS", type: .parejas)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Definir apuesta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Aplicar") { applyAndDismiss() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.122, green: 0.239, blue: 0.169))
                }
            }
        }
        .onAppear { syncFromManager() }
    }

    // MARK: Template picker

    private var templatePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PLANTILLA")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BetTemplate.catalog) { tpl in
                        let selected = matchManager.activeTemplateId == tpl.id
                        Button { loadTemplate(tpl) } label: {
                            Text(tpl.name)
                                .font(.system(size: 13, weight: selected ? .black : .semibold))
                                .foregroundColor(selected ? .white : Color(red: 0.122, green: 0.239, blue: 0.169))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(selected ? Color(red: 0.122, green: 0.239, blue: 0.169) : Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color(red: 0.122, green: 0.239, blue: 0.169).opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Valores

    private var valoresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("VALORES")
            HStack(spacing: 10) {
                valueField("Vuelta", text: $vueltaText)
                valueField("Presión", text: $presionText)
                valueField("Match", text: $matchText)
                valueField("Unidad", text: $unitText)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.890, green: 0.875, blue: 0.824), lineWidth: 1))
    }

    private func valueField(_ label: String, text: Binding<String>) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
            HStack(spacing: 2) {
                Text("$").font(.system(size: 11)).foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
                TextField("0", text: text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.110, green: 0.137, blue: 0.129))
                    .multilineTextAlignment(.center)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.965, green: 0.953, blue: 0.925))
            .cornerRadius(8)
        }
    }

    // MARK: Selección de apuestas — mismo catálogo y mismo Set<UUID> que GuidedSetupView.apuestasStep

    // Unidades calculadas (Birdie, Águila, Albatros, Hole in One, Birdie 18) son automáticas —
    // un solo switch las activa/desactiva todas, no se eligen una por una.
    private var calculadoBets: [BetDefinition] { matchManager.betCatalog.filter { $0.mode == .calculado } }

    private var unidadesOn: Bool {
        let ids = calculadoBets.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { selectedBetIds.contains($0) }
    }

    private func setUnidadesOn(_ on: Bool) {
        let ids = calculadoBets.map(\.id)
        if on { selectedBetIds.formUnion(ids) } else { selectedBetIds.subtract(ids) }
    }

    private var unidadesToggleSection: some View {
        Group {
            if !calculadoBets.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UNIDADES").font(.system(size: 11, weight: .bold)).foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
                        Text(calculadoBets.map(\.name).joined(separator: ", "))
                            .font(.system(size: 12)).foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { unidadesOn }, set: { setUnidadesOn($0) }))
                        .labelsHidden().tint(Color(red: 0.122, green: 0.239, blue: 0.169))
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.890, green: 0.875, blue: 0.824), lineWidth: 1))
            }
        }
    }

    // Apuestas manuales (no las de unidades automáticas) — una lista con scroll por tipo, para ahorrar espacio.
    private func betSelectionSection(title: String, type: BetType) -> some View {
        let bets = matchManager.betCatalog.filter { $0.type == type && $0.mode == .manual }
        return Group {
            if !bets.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text(title).font(.system(size: 11, weight: .bold)).kerning(0.5)
                            .foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(bets.enumerated()), id: \.offset) { idx, bet in
                                let isOn = selectedBetIds.contains(bet.id)
                                Button {
                                    if isOn { selectedBetIds.remove(bet.id) } else { selectedBetIds.insert(bet.id) }
                                } label: {
                                    HStack {
                                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isOn ? Color(red: 0.122, green: 0.239, blue: 0.169) : Color(red: 0.855, green: 0.835, blue: 0.769))
                                            .font(.system(size: 18))
                                        Text(bet.name)
                                            .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                                            .foregroundColor(isOn ? Color(red: 0.110, green: 0.137, blue: 0.129) : Color(red: 0.431, green: 0.416, blue: 0.361))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                }
                                .buttonStyle(.plain)
                                .background(Color.white)
                                if idx < bets.count - 1 {
                                    Color(red: 0.941, green: 0.929, blue: 0.898).frame(height: 1).padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
                .background(Color.white)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.890, green: 0.875, blue: 0.824), lineWidth: 1))
            }
        }
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.5)
            .foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
    }

    private func syncFromManager() {
        vueltaText  = matchManager.vueltaValue  > 0 ? "\(matchManager.vueltaValue)"  : ""
        presionText = matchManager.presionValue > 0 ? "\(matchManager.presionValue)" : ""
        matchText   = matchManager.matchValue   > 0 ? "\(matchManager.matchValue)"   : ""
        unitText    = matchManager.unitValue    > 0 ? "\(matchManager.unitValue)"    : ""
        selectedBetIds = Set(matchManager.activeBets.map { $0.definition.id })
    }

    private func loadTemplate(_ tpl: BetTemplate) {
        matchManager.applyBetTemplate(tpl)
        syncFromManager()
    }

    private func applyAndDismiss() {
        let v = Int(vueltaText)  ?? matchManager.vueltaValue
        let p = Int(presionText) ?? matchManager.presionValue
        let m = Int(matchText)   ?? matchManager.matchValue
        let u = Int(unitText)    ?? matchManager.unitValue
        matchManager.setApuestaValues(vuelta: v, presion: p, match: m)
        matchManager.setUnitValue(u)

        matchManager.setActiveBets(
            matchManager.betCatalog
                .filter { selectedBetIds.contains($0.id) }
                .map { ActiveBet(definition: $0, tagOverride: nil) }
        )
        dismiss()
    }
}
