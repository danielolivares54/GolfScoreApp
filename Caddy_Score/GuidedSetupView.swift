import SwiftUI

struct GuidedSetupView: View {
    enum Step: Int, CaseIterable {
        case campo, hoyoSalida, jugadores, strokes, parejas, strokesParejas, apuestas

        var title: String {
            switch self {
            case .campo: return "Campo"
            case .hoyoSalida: return "Hoyo de salida"
            case .jugadores: return "Jugadores"
            case .strokes: return "Strokes individuales"
            case .parejas: return "Parejas"
            case .strokesParejas: return "Strokes en parejas"
            case .apuestas: return "Apuestas"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager
    @State private var stepIndex = 0
    @State private var selectedCourseId: String = ""
    @State private var startHole: Int = 1
    @State private var playerNames: [String] = []
    @State private var newPlayerName = ""
    @State private var strokesByAlias: [String: Double] = [:]
    @State private var base1: String = ""
    @State private var base2: String = ""
    @State private var laneStrokes: [String: Double] = [:]
    @State private var laneCarrierByKey: [String: String] = [:]
    @State private var vueltaValueText: String = ""
    @State private var selectedBetIds: Set<UUID> = []
    @State private var betTagOverrides: [UUID: String] = [:]

    private var step: Step { Step.allCases[stepIndex] }

    var body: some View {
        NavigationView {
            List {
                Section("Paso \(stepIndex + 1)/\(Step.allCases.count): \(step.title)") {
                    switch step {
                    case .campo:
                        ForEach(CourseCatalog.all, id: \.id) { course in
                            Button(action: { selectedCourseId = course.id }) {
                                HStack {
                                    Text(course.name)
                                    Spacer()
                                    if course.id == selectedCourseId {
                                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    case .hoyoSalida:
                        Stepper(value: $startHole, in: 1...18) { Text("Hoyo \(startHole)") }
                    case .jugadores:
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Nombre jugador", text: $newPlayerName)
                                    .textInputAutocapitalization(.words)
                                Button("Agregar") { addPlayerName() }
                                    .disabled(newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || playerNames.count >= 5)
                            }
                            if playerNames.isEmpty {
                                Text("Agrega hasta 5 jugadores (incluyéndote).")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        ForEach(playerNames.indices, id: \.self) { idx in
                            HStack {
                                Text("\(playerAliases[idx].alias) (\(playerAliases[idx].name))")
                                Spacer()
                                Button("Eliminar") {
                                    playerNames.remove(at: idx)
                                    syncStrokes(); syncBaseDefaults()
                                }.foregroundColor(.red)
                            }
                        }
                    case .strokes:
                        if playerAliases.isEmpty {
                            Text("Primero agrega jugadores.").font(.caption).foregroundColor(.secondary)
                        } else {
                            let rivals = playerAliases.filter { $0.alias != matchManager.yoAlias }
                            if rivals.isEmpty {
                                Text("No hay rivales para asignar strokes.").font(.caption).foregroundColor(.secondary)
                            } else {
                                ForEach(rivals, id: \.alias) { p in
                                    HStack(spacing: 8) {
                                        Text(p.alias).font(.subheadline.bold()).frame(width: 54, alignment: .leading)
                                        Button("-") { adjustStroke(alias: p.alias, delta: -1.0) }.buttonStyle(.bordered)
                                        Text(formatSignedStroke(strokesByAlias[p.alias] ?? 0))
                                            .font(.body.monospacedDigit()).frame(width: 68)
                                        Button("+") { adjustStroke(alias: p.alias, delta: 1.0) }.buttonStyle(.bordered)
                                        Button(".5") { adjustStroke(alias: p.alias, delta: 0.5) }.buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                        }
                    case .parejas:
                        if playerAliases.count < 4 {
                            Text("Se necesitan al menos 4 jugadores.").font(.caption).foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Pareja base 1", selection: $base1) {
                                    ForEach(playerAliases, id: \.alias) { p in
                                        Text("\(p.alias) (\(p.name))").tag(p.alias)
                                    }
                                }
                                Picker("Pareja base 2", selection: $base2) {
                                    ForEach(playerAliases, id: \.alias) { p in
                                        Text("\(p.alias) (\(p.name))").tag(p.alias)
                                    }
                                }
                                if base1 == base2 {
                                    Text("La pareja base debe tener 2 jugadores distintos.")
                                        .font(.caption).foregroundColor(.red)
                                }
                                let opp = opponentsForBase()
                                Text("Oponentes: \(opp.isEmpty ? "—" : opp.joined(separator: ", "))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    case .strokesParejas:
                        let lanes = buildLocalLanes()
                        if lanes.isEmpty {
                            Text("Define primero las parejas.").font(.caption).foregroundColor(.secondary)
                        } else {
                            ForEach(lanes, id: \.id) { lane in
                                let key = lane.id
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text("\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))")
                                            .font(.caption).lineLimit(1)
                                        Spacer()
                                        Button("-") { adjustLaneStroke(key: key, delta: -1.0) }.buttonStyle(.bordered)
                                        Text(formatStroke(laneStrokes[key] ?? 0))
                                            .font(.body.monospacedDigit()).frame(width: 42)
                                        Button("+") { adjustLaneStroke(key: key, delta: 1.0) }.buttonStyle(.bordered)
                                        Button(".5") { adjustLaneStroke(key: key, delta: 0.5) }.buttonStyle(.borderedProminent)
                                    }
                                    HStack(spacing: 8) {
                                        Text("Lleva").font(.caption2.bold()).foregroundColor(.secondary)
                                        Picker("Lleva", selection: Binding(
                                            get: { laneCarrierByKey[key] ?? "" },
                                            set: { laneCarrierByKey[key] = $0 }
                                        )) {
                                            Text("—").tag("")
                                            ForEach(lane.base + lane.opp, id: \.self) { alias in
                                                Text(alias).tag(alias)
                                            }
                                        }.pickerStyle(.menu)
                                    }
                                }
                            }
                        }
                    case .apuestas:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Valor").font(.caption.bold())
                            TextField("Valor vuelta", text: $vueltaValueText).keyboardType(.numberPad)
                            Text("Unidad: \(unitValueFromText())").font(.caption).foregroundColor(.secondary)
                            Text("Regla: unidad = mitad del valor de la vuelta").font(.caption2).foregroundColor(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apuestas individuales").font(.caption.bold())
                            ForEach(matchManager.betCatalog.filter { $0.type == .individual }) { bet in betRow(bet) }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apuestas por parejas").font(.caption.bold())
                            ForEach(matchManager.betCatalog.filter { $0.type == .parejas }) { bet in betRow(bet) }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Activación por partido (Individual)").font(.caption.bold())
                            let rivals = playerAliases.filter { $0.alias != matchManager.yoAlias }
                            if rivals.isEmpty {
                                Text("No hay rivales.").font(.caption2).foregroundColor(.secondary)
                            } else {
                                ForEach(rivals, id: \.alias) { rival in
                                    perMatchToggleRow(
                                        label: "vs \(rival.alias)",
                                        switches: matchManager.betSwitchesForIndividual(opponentAlias: rival.alias),
                                        onChange: { matchManager.setBetSwitchesForIndividual(opponentAlias: rival.alias, switches: $0) }
                                    )
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Activación por partido (Parejas)").font(.caption.bold())
                            let lanes = matchManager.lanes.prefix(3)
                            if lanes.isEmpty {
                                Text("Define parejas para activar apuestas por match.").font(.caption2).foregroundColor(.secondary)
                            } else {
                                ForEach(Array(lanes), id: \.id) { lane in
                                    perMatchToggleRow(
                                        label: "\(lane.base.joined(separator: "+"))/\(lane.opp.joined(separator: "+"))",
                                        switches: matchManager.betSwitchesForPair(laneId: lane.id),
                                        onChange: { matchManager.setBetSwitchesForPair(laneId: lane.id, switches: $0) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Setup guiado")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadDefaults(); syncLaneSetupState() }
            .onChange(of: base1) { _ in syncLaneSetupState() }
            .onChange(of: base2) { _ in syncLaneSetupState() }
            .onChange(of: playerNames) { _ in syncLaneSetupState() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Atrás") { stepIndex = max(0, stepIndex - 1) }
                        .disabled(stepIndex == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(stepIndex == Step.allCases.count - 1 ? "Guardar" : "Siguiente") {
                        if stepIndex == Step.allCases.count - 1 { applySetup(); dismiss() }
                        else { stepIndex = min(Step.allCases.count - 1, stepIndex + 1) }
                    }
                    .disabled(!canAdvance())
                }
            }
        }
    }

    private var playerAliases: [(alias: String, name: String)] { buildAliases(from: playerNames) }

    private func loadDefaults() {
        if !selectedCourseId.isEmpty { return }
        selectedCourseId = matchManager.courseId.isEmpty ? CourseCatalog.default.id : matchManager.courseId
        startHole = matchManager.startHole
        playerNames = matchManager.players.map { $0.name }
        if playerNames.isEmpty { playerNames = ["Daniel"] }
        syncStrokes()
        if let first = playerAliases.first?.alias { base1 = first }
        if playerAliases.count > 1 { base2 = playerAliases[1].alias }
        syncLaneSetupState()
        vueltaValueText = matchManager.vueltaValue > 0 ? "\(matchManager.vueltaValue)" : ""
        selectedBetIds = Set(matchManager.activeBets.map { $0.definition.id })
        for bet in matchManager.activeBets {
            if let tag = bet.tagOverride { betTagOverrides[bet.definition.id] = tag }
        }
    }

    private func addPlayerName() {
        let clean = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, playerNames.count < 5 else { return }
        playerNames.append(clean); newPlayerName = ""
        syncStrokes(); syncBaseDefaults()
    }

    private func syncStrokes() {
        let aliases = playerAliases.map { $0.alias }.filter { $0 != matchManager.yoAlias }
        for a in aliases where strokesByAlias[a] == nil {
            strokesByAlias[a] = matchManager.players.first(where: { $0.alias == a })?.strokesVsBase ?? 0
        }
        for key in strokesByAlias.keys where !aliases.contains(key) { strokesByAlias.removeValue(forKey: key) }
    }

    private func syncBaseDefaults() {
        if base1.isEmpty, let first = playerAliases.first?.alias { base1 = first }
        if base2.isEmpty, playerAliases.count > 1 { base2 = playerAliases[1].alias }
    }

    private func opponentsForBase() -> [String] {
        let base = [base1, base2].filter { !$0.isEmpty }
        return playerAliases.map { $0.alias }.filter { !base.contains($0) }
    }

    private func buildLocalLanes() -> [LocalLane] {
        let base = [base1, base2].filter { !$0.isEmpty }
        if base.count < 2 { return [] }
        let all = playerAliases.map { $0.alias }
        let opp = all.filter { !base.contains($0) }
        if opp.count == 2 { return [LocalLane(base: base, opp: opp)] }
        if opp.count == 3 {
            return [[opp[0], opp[1]], [opp[0], opp[2]], [opp[1], opp[2]]].map { LocalLane(base: base, opp: $0) }
        }
        if base.count == 3 && opp.count == 2 { return [LocalLane(base: base, opp: opp)] }
        return []
    }

    private func unitValueFromText() -> Int {
        guard let v = Int(vueltaValueText) else { return 0 }
        return v / 2
    }

    private func betRow(_ bet: BetDefinition) -> some View {
        let isOn = selectedBetIds.contains(bet.id)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { selectedBetIds.contains(bet.id) },
                set: { on in if on { selectedBetIds.insert(bet.id) } else { selectedBetIds.remove(bet.id) } }
            )) {
                Text("\(bet.name) · \(bet.units)u · \(bet.mode == .calculado ? "calc" : "manual")")
            }
            if isOn {
                TextField("Tag (default \(bet.tag)-ALIAS)", text: Binding(
                    get: { betTagOverrides[bet.id] ?? "" },
                    set: { betTagOverrides[bet.id] = $0 }
                )).textInputAutocapitalization(.characters)
            }
        }
    }

    private func perMatchToggleRow(label: String, switches: MatchBetSwitches, onChange: @escaping (MatchBetSwitches) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).lineLimit(1).frame(width: 140, alignment: .leading)
            toggleChip("V", isOn: switches.vuelta) { var n = switches; n.vuelta.toggle(); onChange(n) }
            toggleChip("P", isOn: switches.presion) { var n = switches; n.presion.toggle(); onChange(n) }
            toggleChip("C", isOn: switches.carry) { var n = switches; n.carry.toggle(); onChange(n) }
            toggleChip("M", isOn: switches.match) { var n = switches; n.match.toggle(); onChange(n) }
            toggleChip("U", isOn: switches.units) { var n = switches; n.units.toggle(); onChange(n) }
            Spacer(minLength: 0)
        }
    }

    private func toggleChip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption2.bold())
                .foregroundColor(isOn ? .white : .primary)
                .frame(width: 24, height: 24)
                .background(isOn ? Color.green : Color(.secondarySystemBackground))
                .cornerRadius(6)
        }.buttonStyle(.plain)
    }

    private func canAdvance() -> Bool {
        switch step {
        case .campo: return !selectedCourseId.isEmpty
        case .hoyoSalida: return startHole >= 1 && startHole <= 18
        case .jugadores: return playerNames.count >= 2 && playerNames.count <= 5
        case .strokes: return !playerAliases.isEmpty
        case .parejas: return playerAliases.count < 4 || (base1 != base2 && !base1.isEmpty && !base2.isEmpty)
        case .strokesParejas, .apuestas: return true
        }
    }

    private func applySetup() {
        if let course = CourseCatalog.all.first(where: { $0.id == selectedCourseId }) {
            matchManager.setCourse(course, resetScores: false)
        }
        matchManager.updateStartHole(startHole, resetScores: false)
        matchManager.setPlayers(names: playerNames, preserveScores: true)
        for p in matchManager.players {
            if p.alias == matchManager.yoAlias { continue }
            matchManager.setStrokesVsBase(alias: p.alias, value: strokesByAlias[p.alias] ?? 0)
        }
        let base = [base1, base2].filter { !$0.isEmpty }
        if base.count >= 2 {
            let opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
            _ = matchManager.setBaseTeam(base, opponentsOverride: opp)
            for lane in buildLocalLanes() {
                let key = lane.id
                matchManager.setLaneStrokesForMatch(base: lane.base, opp: lane.opp, value: laneStrokes[key] ?? 0)
                if let carrier = laneCarrierByKey[key], !carrier.isEmpty {
                    matchManager.setLaneCarrierForMatch(base: lane.base, opp: lane.opp, carrier: carrier)
                }
            }
        }
        if let v = Int(vueltaValueText) { matchManager.setVueltaValue(v) }
        let active = matchManager.betCatalog
            .filter { selectedBetIds.contains($0.id) }
            .map { def in ActiveBet(definition: def, tagOverride: tagOverridesValue(for: def.id)) }
        matchManager.setActiveBets(active)
    }

    private func tagOverridesValue(for id: UUID) -> String? {
        guard let raw = betTagOverrides[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    private func buildAliases(from names: [String]) -> [(alias: String, name: String)] {
        var out: [(alias: String, name: String)] = []
        for name in names {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { continue }
            let alias = suggestAliasLocal(name: clean, existing: out.map { $0.alias })
            if alias.isEmpty { continue }
            out.append((alias: alias, name: clean))
        }
        return out
    }

    private func suggestAliasLocal(name: String, existing: [String]) -> String {
        let letters = name.uppercased().filter { $0.isLetter }
        if letters.isEmpty { return "" }
        var alias = String(letters.prefix(3))
        var counter = 1
        while existing.contains(alias) { alias = String(letters.prefix(3)) + String(counter); counter += 1 }
        return alias
    }

    private func formatStroke(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    private func formatSignedStroke(_ value: Double) -> String {
        (value > 0 ? "+" : "") + formatStroke(value)
    }

    private func adjustStroke(alias: String, delta: Double) {
        let next = max(-20, min(20, (strokesByAlias[alias] ?? 0) + delta))
        strokesByAlias[alias] = (next * 2).rounded() / 2
    }

    private func adjustLaneStroke(key: String, delta: Double) {
        let next = max(0, min(20, (laneStrokes[key] ?? 0) + delta))
        laneStrokes[key] = (next * 2).rounded() / 2
    }

    private func syncLaneSetupState() {
        let lanes = buildLocalLanes()
        let keys = Set(lanes.map { $0.id })
        for lane in lanes {
            let key = lane.id
            if laneStrokes[key] == nil {
                if let existing = matchManager.lanes.first(where: { Set($0.base) == Set(lane.base) && Set($0.opp) == Set(lane.opp) }) {
                    laneStrokes[key] = existing.strokes
                    laneCarrierByKey[key] = existing.strokeCarrier ?? ""
                } else {
                    laneStrokes[key] = 0; laneCarrierByKey[key] = ""
                }
            } else if laneCarrierByKey[key] == nil {
                laneCarrierByKey[key] = ""
            }
        }
        for key in laneStrokes.keys where !keys.contains(key) { laneStrokes.removeValue(forKey: key) }
        for key in laneCarrierByKey.keys where !keys.contains(key) { laneCarrierByKey.removeValue(forKey: key) }
    }

    private struct LocalLane: Identifiable {
        let id: String
        let base: [String]
        let opp: [String]
        init(base: [String], opp: [String]) {
            self.base = base; self.opp = opp
            self.id = (base.sorted() + ["vs"] + opp.sorted()).joined(separator: "-")
        }
    }
}
