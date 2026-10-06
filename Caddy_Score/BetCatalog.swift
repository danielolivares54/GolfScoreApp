import Foundation
import Combine
import SwiftUI

// MARK: - BetTemplate

struct BetTemplate: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var vueltaValue: Int
    var presionValue: Int
    var matchValue: Int
    var unitValue: Int
    var puttsEnabled: Bool
    var puttsBetMode: PuttsBetMode
    var puttsBetUnits: Int
    var b9MultiplierAvailable: Bool
    var activeUnitTags: Set<String>
    // Ajuste de stroke entre rondas (regla 2026-10-06): si es true, el ganador del B9 de un
    // duelo IND mueve ±1 el strokeVsBase del rival en el directorio para el próximo match.
    // Default true — los casos de "no cambio" son la excepción, no la regla.
    var carryMatchEnabled: Bool = true
}

// MARK: - BetTemplateStore

// Directorio de plantillas de apuesta — antes era un array estático (BetTemplate.catalog),
// ahora es editable/creable desde la app (botón "$" → Definir apuesta), igual patrón que
// PlayerDirectoryStore. La semilla inicial reproduce las 5 plantillas que existían hardcodeadas.
final class BetTemplateStore: ObservableObject {
    static let shared = BetTemplateStore()

    @Published private(set) var entries: [BetTemplate] = []

    private let fileName = "bet_templates.json"

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    init() {
        load()
        if entries.isEmpty { seedDefaults() }
    }

    func upsert(_ template: BetTemplate) {
        if let idx = entries.firstIndex(where: { $0.id == template.id }) {
            entries[idx] = template
        } else {
            entries.append(template)
        }
        save()
    }

    // Nunca se borra la última plantilla — varios call sites (GuidedSetupView, applySetup)
    // asumen que siempre existe al menos una para usar como default.
    func remove(_ template: BetTemplate) {
        guard entries.count > 1 else { return }
        entries.removeAll { $0.id == template.id }
        save()
    }

    // Mismo patrón que PlayerDirectoryStore.seedInitialData: 4 letras del nombre + contador si colisiona.
    func suggestId(forName name: String) -> String {
        let letters = name.uppercased().filter { $0.isLetter }
        let base = letters.isEmpty ? "TPL" : String(letters.prefix(4))
        var candidate = base
        var counter = 1
        while entries.contains(where: { $0.id == candidate }) {
            candidate = base + String(counter)
            counter += 1
        }
        return candidate
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url)
        } catch {
            print("❌ Error guardando plantillas de apuesta: \(error)")
        }
    }

    private func load() {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([BetTemplate].self, from: data)
        } catch {
            print("❌ Error cargando plantillas de apuesta: \(error)")
        }
    }

    private func seedDefaults() {
        entries = [
            BetTemplate(
                id: "SYD", name: "S y D",
                vueltaValue: 50, presionValue: 50, matchValue: 100, unitValue: 25,
                puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
                b9MultiplierAvailable: true,
                activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "B18", "OYES"]
            ),
            BetTemplate(
                id: "SYD4", name: "S y D 4",
                vueltaValue: 40, presionValue: 40, matchValue: 80, unitValue: 20,
                puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
                b9MultiplierAvailable: true,
                activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "B18", "OYES"]
            ),
            BetTemplate(
                id: "JUEVES", name: "Jueves",
                vueltaValue: 40, presionValue: 40, matchValue: 80, unitValue: 20,
                puttsEnabled: true, puttsBetMode: .hole18, puttsBetUnits: 2,
                b9MultiplierAvailable: true,
                activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "B18", "OYES"]
            ),
            BetTemplate(
                id: "TPCH", name: "TPCH",
                vueltaValue: 20, presionValue: 20, matchValue: 40, unitValue: 10,
                puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
                b9MultiplierAvailable: false,
                activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "OYES"]
            ),
            BetTemplate(
                id: "FDEZ", name: "Fdez",
                vueltaValue: 50, presionValue: 50, matchValue: 100, unitValue: 25,
                puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
                b9MultiplierAvailable: true,
                activeUnitTags: ["BIRD", "EAG", "ALB", "HIO", "B18", "OYES"],
                carryMatchEnabled: false
            )
        ]
        save()
    }
}

// MARK: - BetSetupSheet

struct BetSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager
    @ObservedObject private var templateStore = BetTemplateStore.shared

    // Valores editables locales
    @State private var vueltaText = ""
    @State private var presionText = ""
    @State private var matchText = ""
    @State private var unitText = ""

    // Apuestas activas — mismo modelo que GuidedSetupView.apuestasStep (Set<UUID> sobre matchManager.betCatalog).
    // Antes había una lista de 7 tags hardcodeados aquí, distinta de la del Setup, y no incluía apuestas de parejas.
    @State private var selectedBetIds: Set<UUID> = []

    @State private var editingTemplate: BetTemplate?
    @State private var showingNewTemplate = false

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
        .sheet(item: $editingTemplate) { tpl in
            BetTemplateEditView(template: tpl, catalogBets: matchManager.betCatalog)
        }
        .sheet(isPresented: $showingNewTemplate) {
            BetTemplateEditView(template: nil, catalogBets: matchManager.betCatalog)
        }
    }

    // MARK: Template picker

    private var templatePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("PLANTILLA")
                Spacer()
                if let current = templateStore.entries.first(where: { $0.id == matchManager.activeTemplateId }) {
                    Button { editingTemplate = current } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(red: 0.122, green: 0.239, blue: 0.169))
                    }
                }
                Button { showingNewTemplate = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(red: 0.122, green: 0.239, blue: 0.169))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templateStore.entries) { tpl in
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

// MARK: - BetTemplateEditView

// Crear o editar una plantilla/tag de apuesta (botón ✏️/+ junto a "PLANTILLA" en BetSetupSheet).
// El id/tag es estable una vez creado — no se re-genera al renombrar, porque PlayerDirectoryEntry
// y MatchManager.betValuesByOpponent lo referencian por ese id.
private struct BetTemplateEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = BetTemplateStore.shared
    let template: BetTemplate?
    let catalogBets: [BetDefinition]

    @State private var name = ""
    @State private var vueltaText = ""
    @State private var presionText = ""
    @State private var matchText = ""
    @State private var unitText = ""
    @State private var puttsEnabled = false
    @State private var puttsBetMode: PuttsBetMode = .hole18
    @State private var puttsBetUnitsText = ""
    @State private var b9MultiplierAvailable = true
    @State private var carryMatchEnabled = true
    @State private var activeTags: Set<String> = []

    private var calculadoBets: [BetDefinition] { catalogBets.filter { $0.mode == .calculado } }
    private var manualBets: [BetDefinition] { catalogBets.filter { $0.mode == .manual } }
    private var calculadoOn: Bool {
        let tags = calculadoBets.map { $0.tag.uppercased() }
        return !tags.isEmpty && tags.allSatisfy { activeTags.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plantilla") {
                    TextField("Nombre", text: $name)
                    if let template {
                        HStack {
                            Text("Tag")
                            Spacer()
                            Text(template.id).foregroundColor(.secondary)
                        }
                    }
                }
                Section("Valores") {
                    TextField("Vuelta", text: $vueltaText).keyboardType(.numberPad)
                    TextField("Presión", text: $presionText).keyboardType(.numberPad)
                    TextField("Match", text: $matchText).keyboardType(.numberPad)
                    TextField("Unidad", text: $unitText).keyboardType(.numberPad)
                }
                Section("Putts") {
                    Toggle("Apuesta de putts", isOn: $puttsEnabled)
                    if puttsEnabled {
                        Picker("Modo", selection: $puttsBetMode) {
                            Text("18 hoyos").tag(PuttsBetMode.hole18)
                            Text("Por vuelta").tag(PuttsBetMode.byRound)
                        }
                        TextField("Unidades de putts", text: $puttsBetUnitsText).keyboardType(.numberPad)
                    }
                }
                Section("Otros ajustes") {
                    Toggle("Multiplicador en B9 disponible", isOn: $b9MultiplierAvailable)
                    Toggle("Ajusta stroke entre rondas", isOn: $carryMatchEnabled)
                    Text("Si se apaga, el ganador del B9 no mueve el stroke del rival para el próximo match.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Section("Apuestas de campo activas") {
                    // Las calculadas (Birdie, Águila, Albatros, Hole in One, Birdie 18) son un solo
                    // concepto — un switch las prende/apaga todas, igual que unidadesToggleSection
                    // en BetSetupSheet. No tiene caso enumerarlas una por una en el formulario.
                    if !calculadoBets.isEmpty {
                        Toggle(calculadoBets.map(\.name).joined(separator: ", "), isOn: Binding(
                            get: { calculadoOn },
                            set: { on in
                                let ids = Set(calculadoBets.map { $0.tag.uppercased() })
                                if on { activeTags.formUnion(ids) } else { activeTags.subtract(ids) }
                            }
                        ))
                    }
                    ForEach(manualBets) { bet in
                        let tag = bet.tag.uppercased()
                        let isOn = activeTags.contains(tag)
                        Button {
                            if isOn { activeTags.remove(tag) } else { activeTags.insert(tag) }
                        } label: {
                            HStack {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isOn ? .accentColor : .secondary)
                                Text(bet.name)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if template != nil {
                    Section {
                        Button("Eliminar plantilla", role: .destructive) {
                            if let template { store.remove(template) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(template == nil ? "Nueva plantilla" : "Editar plantilla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let template {
                    name = template.name
                    vueltaText = "\(template.vueltaValue)"
                    presionText = "\(template.presionValue)"
                    matchText = "\(template.matchValue)"
                    unitText = "\(template.unitValue)"
                    puttsEnabled = template.puttsEnabled
                    puttsBetMode = template.puttsBetMode
                    puttsBetUnitsText = "\(template.puttsBetUnits)"
                    b9MultiplierAvailable = template.b9MultiplierAvailable
                    carryMatchEnabled = template.carryMatchEnabled
                    activeTags = template.activeUnitTags
                }
            }
        }
    }

    private func save() {
        let id = template?.id ?? store.suggestId(forName: name)
        let tpl = BetTemplate(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            vueltaValue: Int(vueltaText) ?? 0,
            presionValue: Int(presionText) ?? 0,
            matchValue: Int(matchText) ?? 0,
            unitValue: Int(unitText) ?? 0,
            puttsEnabled: puttsEnabled,
            puttsBetMode: puttsBetMode,
            puttsBetUnits: Int(puttsBetUnitsText) ?? 0,
            b9MultiplierAvailable: b9MultiplierAvailable,
            activeUnitTags: activeTags,
            carryMatchEnabled: carryMatchEnabled
        )
        store.upsert(tpl)
        dismiss()
    }
}
