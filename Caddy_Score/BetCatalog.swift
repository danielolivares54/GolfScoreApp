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
                b9MultiplierAvailable: true
            ),
            BetTemplate(
                id: "SYD4", name: "S y D 4",
                vueltaValue: 40, presionValue: 40, matchValue: 80, unitValue: 20,
                puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
                b9MultiplierAvailable: true
            ),
            BetTemplate(
                id: "JUEVES", name: "Jueves",
                vueltaValue: 40, presionValue: 40, matchValue: 80, unitValue: 20,
                puttsEnabled: true, puttsBetMode: .hole18, puttsBetUnits: 2,
                b9MultiplierAvailable: true
            ),
            BetTemplate(
                id: "TPCH", name: "TPCH",
                vueltaValue: 20, presionValue: 20, matchValue: 40, unitValue: 10,
                puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
                b9MultiplierAvailable: false
            ),
            BetTemplate(
                id: "FDEZ", name: "Fdez",
                vueltaValue: 50, presionValue: 50, matchValue: 100, unitValue: 25,
                puttsEnabled: false, puttsBetMode: .hole18, puttsBetUnits: 0,
                b9MultiplierAvailable: true,
                carryMatchEnabled: false
            )
        ]
    }
}

// MARK: - BetDefinitionStore (catálogo de unidades — editable y persistido)
//
// Antes esto era un array hardcodeado dentro de MatchManager.setupDefaultBets(), regenerado
// (con IDs nuevos) cada vez que arrancaba un match. Ahora es un catálogo único, persistido,
// con el mismo patrón que BetTemplateStore/PlayerDirectoryStore — MatchManager solo copia la
// foto de tags habilitados al armar el match (ver setupDefaultBets()).
final class BetDefinitionStore: ObservableObject {
    static let shared = BetDefinitionStore()

    @Published private(set) var entries: [BetDefinition] = []

    private let fileName = "bet_definitions.json"

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    init() {
        load()
        if entries.isEmpty { seedDefaults() }
        ensurePuttsTag()
    }

    // Tag de la apuesta de putts. Encendido = apuesta abierta, "Vale" = precio en unidades,
    // puttsScope = F9 / B9 / 18. Nace APAGADO: los putts del usuario siempre se registran como
    // estadística; solo con el tag encendido se piden y se auditan los de los demás.
    static let puttsTag = "PUTTS"

    private static func defaultPuttsDefinition() -> BetDefinition {
        BetDefinition(tag: puttsTag, name: "Putts", type: .individual, mode: .calculado, units: 2,
                      description: "Menos putts en el alcance", isEnabled: false, puttsScope: .hole18)
    }

    // Catálogos guardados antes de existir el tag no lo traen — se agrega (apagado) sin tocar el resto.
    private func ensurePuttsTag() {
        guard !entries.contains(where: { $0.tag == Self.puttsTag }) else { return }
        entries.append(Self.defaultPuttsDefinition())
        save()
    }

    func setPuttsScope(_ def: BetDefinition, scope: PuttsBetMode) {
        guard let idx = entries.firstIndex(where: { $0.id == def.id }) else { return }
        entries[idx].puttsScope = scope
        save()
    }

    // Escritura desde la pantalla de dinero: units > 0 abre la apuesta con ese precio, 0 la cierra.
    func setPutts(scope: PuttsBetMode, units: Int) {
        guard let idx = entries.firstIndex(where: { $0.tag == Self.puttsTag }) else { return }
        entries[idx].puttsScope = scope
        if units > 0 {
            entries[idx].units = units
            entries[idx].isEnabled = true
        } else {
            entries[idx].isEnabled = false
        }
        save()
    }

    func upsert(_ def: BetDefinition) {
        if let idx = entries.firstIndex(where: { $0.id == def.id }) {
            entries[idx] = def
        } else {
            entries.append(def)
        }
        save()
    }

    func setEnabled(_ def: BetDefinition, enabled: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == def.id }) else { return }
        entries[idx].isEnabled = enabled
        save()
    }

    func setUnits(_ def: BetDefinition, units: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == def.id }) else { return }
        entries[idx].units = max(1, units)
        save()
    }

    func remove(_ def: BetDefinition) {
        entries.removeAll { $0.id == def.id }
        save()
    }

    // Mismo patrón que PlayerDirectoryStore/BetTemplateStore: 3 letras del nombre + contador si colisiona.
    func suggestTag(forName name: String) -> String {
        let letters = name.uppercased().filter { $0.isLetter }
        let base = letters.isEmpty ? "TAG" : String(letters.prefix(4))
        var candidate = base
        var counter = 1
        while entries.contains(where: { $0.tag == candidate }) {
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
            print("❌ Error guardando catálogo de unidades: \(error)")
        }
    }

    private func load() {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([BetDefinition].self, from: data)
        } catch {
            print("❌ Error cargando catálogo de unidades: \(error)")
        }
    }

    private func seedDefaults() {
        entries = [
            BetDefinition(tag: "BIRD",  name: "Birdie",            type: .individual, mode: .calculado, units: 1, description: "Par - 1"),
            BetDefinition(tag: "EAG",   name: "Águila",            type: .individual, mode: .calculado, units: 1, description: "Par - 2"),
            BetDefinition(tag: "ALB",   name: "Albatros",          type: .individual, mode: .calculado, units: 1, description: "Par - 3"),
            BetDefinition(tag: "HIO",   name: "Hole in One",       type: .individual, mode: .calculado, units: 1, description: "Ace"),
            BetDefinition(tag: "B18",   name: "Birdie en 18",      type: .individual, mode: .calculado, units: 1, description: "Birdie en hoyo 18"),
            BetDefinition(tag: "3P",    name: "3 Putt",            type: .individual, mode: .manual,    units: 1, description: "Manual"),
            BetDefinition(tag: "HO",    name: "Hole Out",          type: .individual, mode: .manual,    units: 1, description: "Manual"),
            BetDefinition(tag: "OYES",  name: "Oyes Rank",         type: .individual, mode: .manual,    units: 1, description: "Ranking par 3"),
            BetDefinition(tag: "PAIR",  name: "Match Parejas",     type: .parejas,    mode: .manual,    units: 1, description: "Manual"),
            BetDefinition(tag: "OYESP", name: "Oyes Rank Parejas", type: .parejas,    mode: .manual,    units: 1, description: "Ranking par 3 (parejas)")
        ]
        save()
    }
}

// MARK: - BetDefinitionEditorView (editor del catálogo de unidades)
//
// Fonts grandes, una fila por tag: nombre, toggle activa/inactiva, y stepper de valor en
// unidades. Agregar una unidad nueva (ej. "Sandy Par") solo permite modo manual — un tag
// calculado necesita fórmula de detección propia en MatchManager, no es editable desde datos.
struct BetDefinitionEditorView: View {
    @ObservedObject private var store = BetDefinitionStore.shared
    @State private var showingNew = false

    private var individualDefs: [BetDefinition] {
        store.entries.filter { $0.type == .individual }.sorted { $0.name < $1.name }
    }
    private var parejasDefs: [BetDefinition] {
        store.entries.filter { $0.type == .parejas }.sorted { $0.name < $1.name }
    }

    // Sin NavigationStack/toolbar propios — vive embebido como una de las dos páginas de
    // BetsHubView (Valores/Catálogo), que aporta el único título y botón "Cerrar".
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Qué cuenta y cuántas unidades vale")
                    .font(.system(size: 12.5)).foregroundColor(.secondary)
                Spacer()
                Button { showingNew = true } label: {
                    Label("Nueva", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            List {
                Section("Individual") {
                    ForEach(individualDefs) { def in row(def) }
                }
                Section("Parejas") {
                    ForEach(parejasDefs) { def in row(def) }
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            BetDefinitionNewView()
        }
    }

    private func row(_ def: BetDefinition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(def.isEnabled ? .primary : .secondary)
                    Text(def.mode == .calculado ? "Calculado · \(def.description)" : "Manual")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { def.isEnabled },
                    set: { store.setEnabled(def, enabled: $0) }
                ))
                .labelsHidden()
            }
            HStack(spacing: 14) {
                Text("Vale")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                stepperButton(icon: "minus") { store.setUnits(def, units: def.units - 1) }
                Text("\(def.units)")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .frame(minWidth: 46)
                stepperButton(icon: "plus") { store.setUnits(def, units: def.units + 1) }
                Text(def.units == 1 ? "unidad" : "unidades")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            // Apuesta de putts: alcance F9 / B9 / 18. Encendida = apuesta abierta (se piden y
            // auditan los putts de todos); apagada = solo se registran los míos como estadística.
            if def.tag == BetDefinitionStore.puttsTag {
                Picker("Alcance", selection: Binding(
                    get: { def.puttsScope ?? .hole18 },
                    set: { store.setPuttsScope(def, scope: $0) }
                )) {
                    Text("F9").tag(PuttsBetMode.f9)
                    Text("B9").tag(PuttsBetMode.b9)
                    Text("18").tag(PuttsBetMode.hole18)
                    Text("Vuelta").tag(PuttsBetMode.byRound)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 8)
        .opacity(def.isEnabled ? 1.0 : 0.45)
    }

    private func stepperButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 40, height: 40)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct BetDefinitionNewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = BetDefinitionStore.shared
    @State private var name: String = ""
    @State private var type: BetType = .individual
    @State private var units: Int = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Nueva unidad manual") {
                    TextField("Nombre (ej. Sandy Par)", text: $name)
                        .font(.system(size: 17))
                    Picker("Tipo", selection: $type) {
                        Text("Individual").tag(BetType.individual)
                        Text("Parejas").tag(BetType.parejas)
                    }
                    Stepper("Vale \(units) \(units == 1 ? "unidad" : "unidades")", value: $units, in: 1...20)
                }
                Text("Las unidades nuevas siempre son manuales — se registran con un toque en cancha, no se detectan solas del score.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .navigationTitle("Nueva unidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") {
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let tag = store.suggestTag(forName: cleanName)
                        store.upsert(BetDefinition(tag: tag, name: cleanName, type: type, mode: .manual, units: units, description: "Manual"))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - BetsHubView (fusión de "Definir apuesta" + "Catálogo de Unidades")
//
// Antes eran dos botones separados ("$" en la pantalla principal, "Catálogo" en Setup) con
// nombres que competían por el mismo territorio semántico ("apuestas"). Ahora es un solo punto
// de entrada "Apuestas" (reachable solo desde Setup), con dos páginas: Valores (dinero de este
// match) y Catálogo (qué cuenta como unidad, global).
struct BetsHubView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    private enum Page: String, CaseIterable {
        case valores = "Valores"
        case catalogo = "Catálogo"
    }
    @State private var page: Page = .valores

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $page) {
                    ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)

                switch page {
                case .valores:
                    BetSetupSheet(matchManager: matchManager)
                case .catalogo:
                    BetDefinitionEditorView()
                }
            }
            .navigationTitle("Apuestas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
            }
        }
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

    @State private var editingTemplate: BetTemplate?
    @State private var showingNewTemplate = false

    // Sin NavigationStack/toolbar propios — vive embebido como una de las dos páginas de
    // BetsHubView (Valores/Catálogo), que aporta el único título y botón "Cerrar".
    var body: some View {
        ZStack {
            Color(red: 0.965, green: 0.953, blue: 0.925).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    templatePickerSection
                    valoresSection
                    activeTagsSection
                    Button { applyAndDismiss() } label: {
                        Text("Aplicar")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color(red: 0.122, green: 0.239, blue: 0.169))
                            .cornerRadius(12)
                    }
                }
                .padding(18)
            }
        }
        .onAppear { syncFromManager() }
        .sheet(item: $editingTemplate) { tpl in
            BetTemplateEditView(template: tpl, matchManager: matchManager)
        }
        .sheet(isPresented: $showingNewTemplate) {
            BetTemplateEditView(template: nil, matchManager: matchManager)
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

    // Recap de solo-lectura de qué tags del catálogo global están activos ahora mismo — para
    // que el valor de "Unidad" de arriba no quede en el aire sin saber a qué eventos aplica.
    // Editar cuáles están activos o cuánto valen se hace en la página "Catálogo" del hub.
    private var activeTagsSection: some View {
        let individual = matchManager.betCatalog.filter { $0.type == .individual }.sorted { $0.name < $1.name }
        let parejas = matchManager.betCatalog.filter { $0.type == .parejas }.sorted { $0.name < $1.name }
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("UNIDADES ACTIVAS")
            if individual.isEmpty && parejas.isEmpty {
                Text("Ninguna activa — actívalas en el Catálogo.")
                    .font(.system(size: 12.5)).foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
            } else {
                if !individual.isEmpty { tagChipRow("Individual", individual) }
                if !parejas.isEmpty { tagChipRow("Parejas", parejas) }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.890, green: 0.875, blue: 0.824), lineWidth: 1))
    }

    private func tagChipRow(_ label: String, _ defs: [BetDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.431, green: 0.416, blue: 0.361))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(defs) { def in
                        Text("\(def.name) · \(def.units)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.122, green: 0.239, blue: 0.169))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(red: 0.122, green: 0.239, blue: 0.169).opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
        }
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
    // Para propagar los valores editados al match en curso (ver save()).
    let matchManager: MatchManager

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
                // La apuesta de putts (encendida, precio y alcance F9/B9/18) vive en el tag PUTTS
                // del Catálogo, no en la plantilla. Los valores guardados aquí se conservan tal cual.
                Section("Otros ajustes") {
                    Toggle("Multiplicador en B9 disponible", isOn: $b9MultiplierAvailable)
                    Toggle("Ajusta stroke entre rondas", isOn: $carryMatchEnabled)
                    Text("Si se apaga, el ganador del B9 no mueve el stroke del rival para el próximo match.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
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
            carryMatchEnabled: carryMatchEnabled
        )
        store.upsert(tpl)
        // Los valores de la plantilla se copian al match al elegirla — sin esto, editar el monto
        // (ej. 100 → 50) no cambiaba el match en curso. Recalcula todo con el valor nuevo.
        matchManager.refreshBetValues(fromTemplate: tpl)
        dismiss()
    }
}
