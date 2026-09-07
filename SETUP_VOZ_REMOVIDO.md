# Setup por voz y asistentes removidos (referencia)

Esta nota guarda el código removido para conservarlo como referencia.

## SetupWizardView

```swift
struct SetupWizardView: View {
    enum SetupStep: Int, CaseIterable {
        case campo
        case hoyoSalida
        case jugadores
        case strokes
        case parejas
        case strokesParejas
        case apuestas

        var title: String {
            switch self {
            case .campo: return "Campo"
            case .hoyoSalida: return "Hoyo de salida"
            case .jugadores: return "Jugadores"
            case .strokes: return "Strokes individuales"
            case .parejas: return "Parejas y oponentes"
            case .strokesParejas: return "Strokes en parejas"
            case .apuestas: return "Apuestas"
            }
        }

        var prompt: String {
            switch self {
            case .campo: return "¿Qué campo? (Ej: CGM)"
            case .hoyoSalida: return "¿Por qué hoyo inician? (Ej: Hoyo 10)"
            case .jugadores: return "¿Qué jugadores? (Ej: Roberto Ricardo Diego)"
            case .strokes: return "Ajusta strokes por jugador con botones - / +."
            case .parejas: return "Dicta parejas u oponentes. (Ej: Roberto y Anselmo contra Diego y Juan)"
            case .strokesParejas: return "Ajusta strokes por pareja y quién los recibe."
            case .apuestas: return "Configura conteos por apuesta (individual o parejas)."
            }
        }

        var usesTextInput: Bool {
            switch self {
            case .hoyoSalida:
                return true
            case .strokes, .parejas, .strokesParejas, .apuestas:
                return false
            case .campo, .jugadores:
                return true
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager
    @StateObject private var setupRecorder = VoiceRecorder()
    @State private var setupText = ""
    @State private var setupStatus = ""
    @State private var isSetupTranscribing = false
    @State private var isSetupValidating = false
    @State private var selectedStep: SetupStep = .campo
    @State private var selectedPairBase: [String] = []

    private var step: SetupStep { selectedStep }
    private let appleConfidenceThreshold = 0.55
    private let useLLMNameFilter = true

    var body: some View {
        NavigationView {
            List {
                Section("Categorías") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SetupStep.allCases, id: \.self) { item in
                                Button(action: {
                                    selectedStep = item
                                    setupText = ""
                                    setupStatus = ""
                                }) {
                                    Text(item.title)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(item == selectedStep ? Color.green.opacity(0.25) : Color(.secondarySystemBackground))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(step.title) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.prompt)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            if step.usesTextInput {
                                Button(action: toggleDictation) {
                                    Image(systemName: setupRecorder.isRecording ? "stop.fill" : "mic.fill")
                                        .foregroundColor(setupRecorder.isRecording ? .red : .blue)
                                        .font(.title3)
                                }
                                .disabled(isSetupValidating)

                                Button(action: applyStep) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title3)
                                }
                                .disabled(setupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSetupValidating || isSetupTranscribing)
                            } else {
                                if step == .apuestas {
                                    Button("Reiniciar conteos") {
                                        matchManager.resetBetCounts()
                                    }
                                    .font(.caption)
                                }
                            }

                            if step.usesTextInput {
                                Button("Limpiar") {
                                    setupText = ""
                                }
                                .font(.caption)
                                .disabled(isSetupValidating || isSetupTranscribing)
                            }
                        }

                        if step.usesTextInput {
                            TextField("Texto detectado (corrige aquí)", text: $setupText)
                                .textInputAutocapitalization(.words)
                                .disabled(isSetupTranscribing || isSetupValidating)
                        } else {
                            switch step {
                            case .hoyoSalida:
                                startHoleButtonsView
                            case .strokes:
                                individualStrokesEditorView
                            case .parejas:
                                pairSelectionView
                            case .strokesParejas:
                                pairStrokesEditorView
                            case .apuestas:
                                betsMatrixView
                            default:
                                EmptyView()
                            }
                        }

                        if step == .hoyoSalida {
                            startHoleButtonsView
                        }
                    }

                    if !setupStatus.isEmpty {
                        Text(setupStatus)
                            .font(.caption2)
                            .foregroundColor(setupStatus.contains("✅") ? .green : .red)
                    }
                }

                Section("Resumen") {
                    MatchSummaryView(matchManager: matchManager)
                }
            }
            .navigationTitle("Configuración")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedPairBase.isEmpty, !matchManager.baseTeamAliases.isEmpty {
                    selectedPairBase = Array(matchManager.baseTeamAliases.prefix(2))
                }
            }
            .onChange(of: selectedStep) { _ in
                if step == .parejas,
                   selectedPairBase.isEmpty,
                   !matchManager.baseTeamAliases.isEmpty {
                    selectedPairBase = Array(matchManager.baseTeamAliases.prefix(2))
                }
            }
            .onDisappear {
                if setupRecorder.isRecording {
                    _ = setupRecorder.stopRecording()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .disabled(isSetupValidating || isSetupTranscribing)
                }
            }
        }
    }

    private func toggleDictation() {
        if setupRecorder.isRecording {
            guard let url = setupRecorder.stopRecording() else { return }
            isSetupTranscribing = true
            setupStatus = "Transcribiendo..."
            Task {
                do {
                    var finalText = ""
                    do {
                        let apple = try await setupRecorder.transcribeWithApple(url: url)
                        let cleaned = apple.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            let nameCount = extractNamesFromText(cleaned).count
                            if apple.confidence >= appleConfidenceThreshold || nameCount >= 2 {
                                finalText = cleaned
                            }
                        }
                    } catch {
                        // Fallback to OpenAI
                    }
                    if finalText.isEmpty {
                        finalText = try await OpenAIService.shared.transcribeAudio(url: url)
                    }
                    await MainActor.run {
                        let cleaned = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if containsNoiseDictation(cleaned.lowercased()) {
                            setupText = ""
                            setupStatus = "No se detectó dictado. Repite."
                        } else {
                            setupText = cleaned
                            setupStatus = setupText.isEmpty ? "No se detectó dictado. Repite." : "Dictado listo. Puedes corregir."
                        }
                        isSetupTranscribing = false
                    }
                } catch {
                    await MainActor.run {
                        setupStatus = "No se pudo transcribir. Repite."
                        isSetupTranscribing = false
                    }
                }
            }
        } else {
            setupRecorder.requestPermissions()
            setupRecorder.startRecording()
            setupStatus = "Dictando..."
        }
    }

    private func applyStep() {
        let text = setupText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return }
        switch step {
        case .campo:
            if let course = matchCourse(in: text) {
                matchManager.setCourse(course)
                setupStatus = "✅ Campo: \(course.id)"
            } else {
                setupStatus = "❌ Campo fuera de catálogo. Repite."
            }
        case .hoyoSalida:
            if let h = MatchInterpreter.extractHole(from: text.lowercased()),
               matchManager.getHole(h) != nil {
                matchManager.updateStartHole(h)
                setupStatus = "✅ Hoyo de salida: \(h)"
            } else {
                setupStatus = "❌ Hoyo inválido para el campo. Repite."
            }
        case .jugadores:
            let names = extractNamesFromText(text).filter { isValidPlayerName($0) }
            if names.isEmpty {
                setupStatus = "❌ No entendí jugadores. Repite."
                return
            }
            let (unique, duplicates, existing) = dedupeNames(names)
            if !duplicates.isEmpty || !existing.isEmpty {
                let dupText = duplicates.isEmpty ? "" : "Duplicados: \(duplicates.joined(separator: ", ")). "
                let existText = existing.isEmpty ? "" : "Ya registrados: \(existing.joined(separator: ", "))."
                setupStatus = "❌ \(dupText)\(existText)"
                return
            }
            if matchManager.players.count + unique.count > 5 {
                setupStatus = "❌ Máximo 5 jugadores."
                return
            }
            if useLLMNameFilter {
                isSetupValidating = true
                setupStatus = "Validando nombres..."
                Task {
                    let confirmed = await confirmNamesWithLLM(candidates: unique, transcript: text)
                    await MainActor.run {
                        isSetupValidating = false
                        let finalNames = confirmed.isEmpty ? unique : confirmed
                        if finalNames.isEmpty {
                            setupStatus = "❌ No entendí jugadores. Repite."
                            return
                        }
                        var added: [String] = []
                        for name in finalNames {
                            if matchManager.addPlayer(name: name) {
                                added.append(name)
                            }
                        }
                        if added.isEmpty {
                            setupStatus = matchManager.players.count >= 5 ? "❌ Máximo 5 jugadores" : "❌ No pude agregar jugadores"
                        } else {
                            setupStatus = "✅ Agregados: \(added.joined(separator: ", "))"
                        }
                    }
                }
                return
            }
        case .strokes:
            let unknown = unknownNames(in: text)
            if !unknown.isEmpty {
                setupStatus = suggestionMessage(for: unknown)
                return
            }
            let updates = parseStrokeUpdatesSetup(text)
            if updates.isEmpty {
                setupStatus = "❌ No entendí strokes. Repite."
                return
            }
            for u in updates {
                matchManager.setStrokesVsBase(alias: u.alias, value: u.value)
            }
            let summary = updates
                .map { "\($0.alias) \($0.value >= 0 ? "+" : "")\($0.value)" }
                .joined(separator: ", ")
            setupStatus = "✅ Strokes interpretados: \(summary)"
        case .parejas:
            if matchManager.players.count < 4 {
                setupStatus = "❌ Faltan jugadores para parejas."
                return
            }
            let ok = applyPairsSelection()
            if !ok {
                setupStatus = "❌ Selecciona 2 jugadores base para formar parejas."
            }
        case .strokesParejas:
            let result = applyLaneStrokesFromText(text)
            setupStatus = result.ok ? "✅ Strokes de pareja actualizados" : (result.message ?? "❌ No entendí strokes de pareja.")
        case .apuestas:
            setupStatus = "✅ Apuestas actualizadas"
        }
        setupText = ""
    }

    private var startHoleButtonsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selecciona hoyo de salida")
                .font(.caption)
                .foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 28), spacing: 6), count: 6), spacing: 6) {
                ForEach(1...18, id: \.self) { hole in
                    Button("\(hole)") {
                        matchManager.updateStartHole(hole)
                        setupStatus = "✅ Hoyo de salida: \(hole)"
                    }
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(matchManager.startHole == hole ? Color.green.opacity(0.24) : Color(.secondarySystemBackground))
                    .cornerRadius(6)
                }
            }
        }
    }

    private var pairSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if matchManager.players.count < 4 {
                Text("Se necesitan al menos 4 jugadores para formar parejas.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Selecciona una pareja base (2 jugadores).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                WrapGrid(items: matchManager.players.map { $0.alias }) { alias in
                    Button(action: {
                        togglePairBase(alias)
                    }) {
                        Text(alias)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(selectedPairBase.contains(alias) ? Color.green.opacity(0.2) : Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
                let base = selectedPairBase
                let opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
                Text("Base: \(base.isEmpty ? "—" : base.joined(separator: " + "))")
                    .font(.caption2)
                Text("Oponentes automáticos: \(opp.isEmpty ? "—" : opp.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var individualStrokesEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if matchManager.players.isEmpty {
                Text("Agrega jugadores primero.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(matchManager.players, id: \.alias) { player in
                    HStack {
                        Text("\(player.alias) (\(player.name))")
                            .font(.caption)
                        Spacer()
                        Button(action: {
                            if player.alias != matchManager.yoAlias {
                                matchManager.setStrokesVsBase(alias: player.alias, value: player.strokesVsBase - 1)
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                        }
                        .disabled(player.alias == matchManager.yoAlias)
                        Text(player.strokesVsBase >= 0 ? "+\(player.strokesVsBase)" : "\(player.strokesVsBase)")
                            .font(.caption.bold())
                            .frame(minWidth: 42)
                        Button(action: {
                            if player.alias != matchManager.yoAlias {
                                matchManager.setStrokesVsBase(alias: player.alias, value: player.strokesVsBase + 1)
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(player.alias == matchManager.yoAlias)
                    }
                    .padding(.vertical, 2)
                }
                Text("Tip: usa valores enteros. Negativo = da golpes, positivo = recibe.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var pairStrokesEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if matchManager.lanes.isEmpty {
                Text("Define parejas primero.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(matchManager.lanes) { lane in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))")
                            .font(.caption.bold())
                        HStack {
                            Button(action: {
                                matchManager.setLaneStrokes(id: lane.id, value: lane.strokes - 1)
                            }) {
                                Image(systemName: "minus.circle.fill")
                            }
                            Text("\(lane.strokes)")
                                .font(.caption.bold())
                                .frame(minWidth: 24)
                            Button(action: {
                                matchManager.setLaneStrokes(id: lane.id, value: lane.strokes + 1)
                            }) {
                                Image(systemName: "plus.circle.fill")
                            }
                            Spacer()
                            Menu {
                                Button("Sin asignar") {
                                    matchManager.setLaneCarrier(id: lane.id, carrier: nil)
                                }
                                ForEach(lane.base + lane.opp, id: \.self) { alias in
                                    Button(alias) {
                                        matchManager.setLaneCarrier(id: lane.id, carrier: alias)
                                    }
                                }
                            } label: {
                                Text(lane.strokeCarrier ?? "Quién recibe")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Text("Define strokes enteros por pareja y quién los recibe.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @discardableResult
    private func applyPairsSelection() -> Bool {
        let base = selectedPairBase.filter { alias in
            matchManager.players.contains(where: { $0.alias == alias })
        }
        guard matchManager.players.count >= 4 else { return false }
        guard base.count == 2 else { return false }
        let opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
        let ok = matchManager.setBaseTeam(base, opponentsOverride: opp)
        if ok {
            setupStatus = "✅ Parejas actualizadas: \(base.joined(separator: " + "))"
        }
        return ok
    }

    private func togglePairBase(_ alias: String) {
        if let idx = selectedPairBase.firstIndex(of: alias) {
            selectedPairBase.remove(at: idx)
            return
        }
        if selectedPairBase.count < 2 {
            selectedPairBase.append(alias)
        } else {
            selectedPairBase.removeFirst()
            selectedPairBase.append(alias)
        }
        if selectedPairBase.count == 2 {
            _ = applyPairsSelection()
        }
    }

    private var betsMatrixView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                compactMetric(title: "Celdas activas", value: "\(setupActiveBetCells)")
                compactMetric(title: "Total (estimado)", value: "\(setupEstimatedAmount)")
            }

            if !individualBets.isEmpty {
                betsSectionCard(
                    title: "Apuestas individuales",
                    subtitle: "Activa por jugador",
                    bets: individualBets,
                    columns: individualBetColumns
                )
            }
            if !pairBets.isEmpty {
                if pairBetColumns.isEmpty {
                    Text("Define primero las parejas para capturar apuestas por parejas.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    betsSectionCard(
                        title: "Apuestas por parejas",
                        subtitle: "Activa por enfrentamiento",
                        bets: pairBets,
                        columns: pairBetColumns
                    )
                }
            }
        }
    }

    private func betsSectionCard(title: String, subtitle: String, bets: [BetDefinition], columns: [BetColumn]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
            betsTable(bets: bets, columns: columns)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func betsTable(bets: [BetDefinition], columns: [BetColumn]) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Apuesta")
                        .font(.caption2.bold())
                        .frame(width: 120, alignment: .leading)
                    Text("Activa")
                        .font(.caption2.bold())
                        .frame(width: 50)
                    Text("Valor")
                        .font(.caption2.bold())
                        .frame(width: 90)
                    ForEach(columns) { col in
                        Text(col.label)
                            .font(.caption2.bold())
                            .frame(width: 74)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                ForEach(bets) { bet in
                    HStack(spacing: 8) {
                        Text("\(bet.tag) \(bet.units)u")
                            .font(.caption)
                            .frame(width: 120, alignment: .leading)
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { isRowActive(bet: bet, columns: columns) },
                                set: { setRowActive(bet: bet, columns: columns, active: $0) }
                            )
                        )
                        .labelsHidden()
                        .frame(width: 50)
                        Text("\(bet.units)u / \(bet.units * max(0, matchManager.unitValue))")
                            .font(.caption2)
                            .frame(width: 90)
                        ForEach(columns) { col in
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { matchManager.isBetActive(betId: bet.id, targetKey: col.key) },
                                    set: { matchManager.setBetActive(betId: bet.id, targetKey: col.key, active: $0) }
                                )
                            )
                            .labelsHidden()
                            .frame(width: 74)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(isRowActive(bet: bet, columns: columns) ? Color.green.opacity(0.10) : Color.clear)
                    .cornerRadius(8)
                }
            }
        }
    }

    private var individualBets: [BetDefinition] {
        matchManager.betCatalog.filter { $0.type == .individual }
    }

    private var pairBets: [BetDefinition] {
        matchManager.betCatalog.filter { $0.type == .parejas }
    }

    private var individualBetColumns: [BetColumn] {
        matchManager.players.map { BetColumn(key: $0.alias, label: $0.alias) }
    }

    private var pairBetColumns: [BetColumn] {
        matchManager.lanes.map { lane in
            let base = lane.base.joined(separator: "+")
            let opp = lane.opp.joined(separator: "+")
            let key = matchManager.laneTargetKey(base: lane.base, opp: lane.opp)
            return BetColumn(key: key, label: "\(base)vs\(opp)")
        }
    }

    private struct BetColumn: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    private func isRowActive(bet: BetDefinition, columns: [BetColumn]) -> Bool {
        columns.contains { col in
            matchManager.isBetActive(betId: bet.id, targetKey: col.key)
        }
    }

    private func setRowActive(bet: BetDefinition, columns: [BetColumn], active: Bool) {
        for col in columns {
            matchManager.setBetActive(betId: bet.id, targetKey: col.key, active: active)
        }
    }

    private var setupActiveBetCells: Int {
        let individualTargets = Set(matchManager.players.map { $0.alias })
        let pairTargets = Set(matchManager.lanes.map { matchManager.laneTargetKey(base: $0.base, opp: $0.opp) })
        var total = 0
        for bet in matchManager.betCatalog {
            let targets = bet.type == .individual ? individualTargets : pairTargets
            for target in targets {
                if matchManager.isBetActive(betId: bet.id, targetKey: target) {
                    total += 1
                }
            }
        }
        return total
    }

    private var setupEstimatedAmount: Int {
        let individualTargets = Set(matchManager.players.map { $0.alias })
        let pairTargets = Set(matchManager.lanes.map { matchManager.laneTargetKey(base: $0.base, opp: $0.opp) })
        var units = 0
        for bet in matchManager.betCatalog {
            let targets = bet.type == .individual ? individualTargets : pairTargets
            for target in targets {
                if matchManager.isBetActive(betId: bet.id, targetKey: target) {
                    units += matchManager.betCount(betId: bet.id, targetKey: target) * bet.units
                }
            }
        }
        return units * max(0, matchManager.unitValue)
    }

    private func confirmNamesWithLLM(candidates: [String], transcript: String) async -> [String] {
        do {
            let result = try await OpenAIService.shared.confirmPlayerNames(candidates: candidates, transcript: transcript)
            return result.accepted
        } catch {
            return candidates
        }
    }

    private func matchCourse(in text: String) -> CourseModel? {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        for course in CourseCatalog.all {
            let id = course.id.lowercased()
            let name = matchManager.normalizePlayerKey(course.name).lowercased()
            if normalized.contains(id) || (!name.isEmpty && normalized.contains(name)) {
                return course
            }
        }
        return nil
    }

    private func dedupeNames(_ names: [String]) -> (unique: [String], duplicates: [String], existing: [String]) {
        var seen = Set<String>()
        var unique: [String] = []
        var duplicates: [String] = []
        var existing: [String] = []
        for name in names {
            let key = matchManager.normalizePlayerKey(name).lowercased()
            if seen.contains(key) {
                duplicates.append(name)
                continue
            }
            seen.insert(key)
            if matchManager.normalizeAlias(name) != nil {
                existing.append(name)
                continue
            }
            unique.append(name)
        }
        return (unique, duplicates, existing)
    }

    private func unknownNames(in text: String) -> [String] {
        let candidates = extractNamesFromText(text)
        if candidates.isEmpty { return [] }
        var unknown: [String] = []
        for c in candidates {
            if matchManager.normalizeAlias(c) == nil && aliasesMatchedByName(c).isEmpty {
                unknown.append(c)
            }
        }
        return unknown
    }

    private func strictUnknownNamesSetup(in text: String) -> [String] {
        let candidates = extractNamesFromText(text)
        if candidates.isEmpty { return [] }
        var unknown: [String] = []
        for c in candidates {
            if matchManager.normalizeAlias(c) == nil && aliasesMatchedByName(c).isEmpty {
                unknown.append(c)
            }
        }
        return unknown
    }

    private func invalidNamesMessageSetup(_ names: [String]) -> String {
        let valid = matchManager.players.map { "\($0.alias) (\($0.name))" }.joined(separator: ", ")
        let unknown = names.joined(separator: ", ")
        return "❌ Jugador no parte de este match: \(unknown). Válidos: \(valid)."
    }

    private func suggestionMessage(for names: [String]) -> String {
        var suggestions: [String] = []
        for name in names {
            let candidates = matchManager.fuzzyCandidates(for: name, limit: 2)
            if let best = candidates.first {
                suggestions.append("¿Quisiste decir \(best.alias)?")
            } else {
                suggestions.append("Nombre no válido: \(name)")
            }
        }
        return "❌ " + suggestions.joined(separator: " ")
    }

    private func parseStrokeUpdatesSetup(_ text: String) -> [(alias: String, value: Int)] {
        let separators = [",", ";", " y ", " e "]
        var parts: [String] = [text]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        var updates: [(alias: String, value: Int)] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = parseStrokeUpdateSetup(trimmed) {
                updates.append(u)
            }
        }
        return updates
    }

    private func parseStrokeUpdateSetup(_ text: String) -> (alias: String, value: Int)? {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let num = extractFirstNumber(from: text) else { return nil }
        let hasReceive = hasWord(t, "recibe") || hasWord(t, "recibo") || hasWord(t, "recibes") || hasWord(t, "reciben") ||
            t.contains("le dan") || t.contains("le da") ||
            hasWord(t, "tengo") || hasWord(t, "tiene") || hasWord(t, "tienen") ||
            hasWord(t, "lleva") || hasWord(t, "llevo") || hasWord(t, "llevan")
        let hasGive = hasWord(t, "da") || hasWord(t, "doy") || hasWord(t, "das") || hasWord(t, "dame") || hasWord(t, "dan") || hasWord(t, "damos")
        let hasSpeakerGive = hasWord(t, "doy") || hasWord(t, "damos")
        let hasMeDa = t.contains("me da") || t.contains("me dan")
        let hasToCue = t.contains(" a ") || t.contains(" para ")
        if !hasReceive && !hasGive { return nil }
        var aliases = aliasesMatchedByName(text)
        if aliases.isEmpty {
            aliases = extractAliasesFromText(text)
        }
        if aliases.isEmpty { return nil }
        let named = aliases.filter { $0 != matchManager.yoAlias }
        let target = named.first ?? aliases.first!

        // Examples:
        // "Anselmo doy 5" -> Anselmo +5 (yo doy, él recibe)
        // "Roberto me da 10" -> Roberto -10 (él da, yo recibo)
        if hasSpeakerGive {
            return (target, num)
        }
        if hasMeDa {
            return (target, -num)
        }
        let receiverMode = hasReceive || hasToCue
        let value = receiverMode ? num : -num
        return (target, value)
    }

    private func applyPairsFromText(_ text: String) -> (ok: Bool, message: String?) {
        let trimmed = stripStrokeClause(text)
        let unknown = strictUnknownNamesSetup(in: trimmed)
        if !unknown.isEmpty { return (false, invalidNamesMessageSetup(unknown)) }
        if let split = splitMatchup(trimmed) {
            var base = extractAliasesPreferNames(split.left)
            let opp = extractAliasesPreferNames(split.right)
            let t = matchManager.normalizePlayerKey(split.left).lowercased()
            if t.contains("yo") || t.contains("mi") || t.contains("mis") {
                if !base.contains(matchManager.yoAlias) { base.insert(matchManager.yoAlias, at: 0) }
            }
            if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
            if !disjointTeams(base, opp) { return (false, "❌ Un jugador aparece en ambos lados.") }
            return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil)
        }
        let ordered = orderedAliasesFromText(trimmed)
        if ordered.count == 4 {
            let base = Array(ordered.prefix(2))
            let opp = Array(ordered.suffix(2))
            if disjointTeams(base, opp) {
                return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil)
            }
        }
        var base: [String] = []
        var opp: [String] = []
        if let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcompañeros?\b\s*(son|es|:)?\s*"#) {
            base = extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcompaneros?\b\s*(son|es|:)?\s*"#) {
            base = extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcon\b"#) {
            base = extractAliasesPreferNames(after)
        }
        if let oppAfter = substringAfterPattern(trimmed, pattern: #"(?i)\boponentes?\b\s*(son|es|:)?\s*"#) {
            opp = extractAliasesPreferNames(oppAfter)
        }
        let t = matchManager.normalizePlayerKey(trimmed).lowercased()
        if (t.contains("yo") || t.contains("mi") || t.contains("mis")) && !base.contains(matchManager.yoAlias) {
            base.insert(matchManager.yoAlias, at: 0)
        }
        if base.isEmpty {
            base = extractAliasesPreferNames(trimmed)
        }
        if opp.isEmpty {
            opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
        }
        if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
        if !disjointTeams(base, opp) { return (false, "❌ Un jugador aparece en ambos lados.") }
        return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil)
    }

    private func applyLaneStrokesFromText(_ text: String) -> (ok: Bool, message: String?) {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        let unknown = strictUnknownNamesSetup(in: text)
        if !unknown.isEmpty { return (false, invalidNamesMessageSetup(unknown)) }
        if let split = splitMatchup(text) {
            let base = extractAliasesPreferNames(split.left)
            let opp = extractAliasesPreferNames(split.right)
            if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
            let applied = applyCarrierFromText(text, base: base, opp: opp)
            return applied
                ? (true, nil)
                : (false, "❌ Indica quién los lleva o cuántos strokes de pareja.")
        }
        if matchManager.lanes.count == 1 {
            let lane = matchManager.lanes[0]
            let applied = applyCarrierFromText(text, base: lane.base, opp: lane.opp)
            return applied
                ? (true, nil)
                : (false, "❌ Indica quién los lleva o cuántos strokes de pareja.")
        }
        if t.contains("lleva") || t.contains("llev") {
            if matchManager.lanes.count > 1 {
                return (false, "❌ Especifica el enfrentamiento: BASE contra OPP.")
            }
            if let carrier = extractAliasesPreferNames(text).first, matchManager.lanes.count == 1 {
                let lane = matchManager.lanes[0]
                matchManager.setLaneCarrierForMatch(base: lane.base, opp: lane.opp, carrier: carrier)
                return (true, nil)
            }
        }
        return (false, "❌ No entendí strokes de pareja.")
    }

    private func disjointTeams(_ a: [String], _ b: [String]) -> Bool {
        let sa = Set(a)
        let sb = Set(b)
        return sa.intersection(sb).isEmpty
    }

    private func orderedAliasesFromText(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        var hits: [(alias: String, idx: Int)] = []
        for p in matchManager.players {
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey),
               let range = normalized.range(of: aliasKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
            }
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if !nameKey.isEmpty, let range = normalized.range(of: nameKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
            }
        }
        let sorted = hits.sorted { $0.idx < $1.idx }
        var seen = Set<String>()
        var out: [String] = []
        for hit in sorted {
            if seen.contains(hit.alias) { continue }
            seen.insert(hit.alias)
            out.append(hit.alias)
        }
        return out
    }

    private func applyCarrierFromText(_ text: String, base: [String]?, opp: [String]?) -> Bool {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let b = base, let o = opp, !b.isEmpty, !o.isEmpty else { return false }
        let orderedAliases = orderedAliasesFromText(text)
        let receiverWords = ["recibe","recibo","reciben","recibir","lleva","llevo","llevas","llevan"]
        let giverWords = ["da","doy","das","dan","damos"]
        let receiverMode = hasAnyWord(t, receiverWords) ||
            t.contains("le dan") || t.contains("les dan") || t.contains("nos dan") ||
            t.contains("le llevan") || t.contains("les llevan") || t.contains("nos llevan")
        let giverMode = !receiverMode && (hasAnyWord(t, giverWords) || t.contains("le da") || t.contains("les da") || t.contains("nos da"))

        var applied = false
        var carrier: String? = nil
        if receiverMode {
            carrier = orderedAliases.last
            if carrier == nil, t.contains("nos") || t.contains("nosotros") {
                carrier = b.contains(matchManager.yoAlias) ? matchManager.yoAlias : b.first
            }
        } else if giverMode {
            if let giver = orderedAliases.last {
                if b.contains(giver) {
                    carrier = o.contains(matchManager.yoAlias) ? matchManager.yoAlias : o.first
                } else if o.contains(giver) {
                    carrier = b.contains(matchManager.yoAlias) ? matchManager.yoAlias : b.first
                }
            }
        } else if t.contains("lleva") || t.contains("llev") {
            carrier = orderedAliases.last
        }

        if let carrier = carrier {
            matchManager.setLaneCarrierForMatch(base: b, opp: o, carrier: carrier)
            applied = true
        }

        if let strokes = extractFirstNumber(from: text) {
            let hasStrokeWord = t.contains("stroke") || t.contains("strokes") || t.contains("golpe") || t.contains("golpes")
            if receiverMode || giverMode || hasStrokeWord || t.contains("lleva") || t.contains("llev") {
                matchManager.setLaneStrokesForMatch(base: b, opp: o, value: strokes)
                applied = true
            }
        }
        return applied
    }

    private func hasAnyWord(_ text: String, _ words: [String]) -> Bool {
        for w in words {
            if hasWord(text, w) { return true }
        }
        return false
    }

    private func extractAliasesFromText(_ text: String) -> [String] {
        var result: [String] = []
        let t = matchManager.normalizePlayerKey(text).lowercased()
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey) && containsWholePhrase(t, phrase: aliasKey) {
                result.append(p.alias)
            }
            if !nameKey.isEmpty && containsWholePhrase(t, phrase: nameKey) {
                result.append(p.alias)
            }
        }
        let tokens = t.split(separator: " ").map { String($0) }
        for token in tokens {
            if matchManager.isAmbiguousAliasToken(token) { continue }
            if let a = matchManager.normalizeAlias(token) {
                result.append(a)
            }
        }
        if t.contains("yo") {
            result.append(matchManager.yoAlias)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private func extractAliasesPreferNames(_ text: String) -> [String] {
        let byName = aliasesMatchedByName(text)
        if !byName.isEmpty { return byName }
        return extractAliasesFromText(text)
    }

    private func aliasesMatchedByName(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        if normalized.isEmpty { return [] }
        var hits: [String] = []
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if nameKey.isEmpty { continue }
            if containsWholePhrase(normalized, phrase: nameKey) {
                hits.append(p.alias)
            }
        }
        if !hits.isEmpty {
            var seen = Set<String>()
            return hits.filter { seen.insert($0).inserted }
        }
        let uniqueFirst = uniqueFirstNameMap()
        let tokens = normalized.split(separator: " ").map { String($0) }
        for token in tokens {
            if let alias = uniqueFirst[token] {
                hits.append(alias)
            }
        }
        var seen = Set<String>()
        return hits.filter { seen.insert($0).inserted }
    }

    private func uniqueFirstNameMap() -> [String: String] {
        var buckets: [String: [String]] = [:]
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            guard let first = nameKey.split(separator: " ").first.map(String.init),
                  !first.isEmpty else { continue }
            buckets[first, default: []].append(p.alias)
        }
        var unique: [String: String] = [:]
        for (first, aliases) in buckets where aliases.count == 1 {
            unique[first] = aliases[0]
        }
        return unique
    }

    private func containsWholePhrase(_ text: String, phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)\b\#(escaped)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func extractNamesFromText(_ text: String) -> [String] {
        let lower = matchManager.normalizePlayerKey(text).lowercased()
        let hasListCue = lower.contains("juegan") || lower.contains("juega") ||
            lower.contains("jugadores") || lower.contains("son") || lower.contains("somos") ||
            lower.contains("jugamos") || lower.contains("agrego") || lower.contains("agrega") ||
            lower.contains("agregar") || lower.contains("añado") || lower.contains("añade")
        let proper = properNames(from: text)
        if proper.count >= 2 {
            return proper
        }
        if proper.count == 1, hasListCue || text.contains(",") || text.contains(";") || lower.contains(" y ") || lower.contains(" e ") {
            let list = extractNamesFromList(text)
            return list.isEmpty ? proper : list
        }
        let list = extractNamesFromList(text)
        if !list.isEmpty { return list }
        return proper
    }

    private func extractNamesFromList(_ text: String) -> [String] {
        var cleaned = text
        let removePattern = #"(?i)\b(agrega|agregar|agrego|agregue|agregué|agregamos|agregan|añade|añadir|añado|nuevo|jugador|jugadores|soy|somos|compañero|compañeros|companero|companeros|mi|mis|yo|base|contra|vs|versus|pareja|juegan|jugamos|los|lleva|llevo|llevas|llevan|strokes|golpes|recibe|recibo|da|doy|subtitulo|subtitulos|subtítulos|realizado|realizados|comunidad|amara|org|caption|subtitles|de|del|la|el|los|las|por|para|muy)\b"#
        cleaned = cleaned.replacingOccurrences(of: removePattern, with: " ", options: .regularExpression)
        let separators = [" y ", " e ", ",", ";", "&", "+", " con "]
        for s in separators {
            cleaned = cleaned.replacingOccurrences(of: s, with: ",")
        }
        let parts = cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return [] }
        var out: [String] = []
        for part in parts {
            let tokens = part.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            var i = 0
            while i < tokens.count {
                let t = tokens[i]
                if i + 1 < tokens.count,
                   isCompoundNamePair(first: t, second: tokens[i + 1]) {
                    let combined = "\(t) \(tokens[i + 1])"
                    if isValidPlayerName(combined) {
                        out.append(combined)
                        i += 2
                        continue
                    }
                }
                if isValidPlayerName(t) {
                    out.append(t)
                }
                i += 1
            }
        }
        return out
    }

    private func properNames(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: [String] = []
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName {
                let name = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidPlayerName(name) {
                    names.append(name)
                }
            }
            return true
        }
        return names
    }

    private func isCompoundNamePair(first: String, second: String) -> Bool {
        let f = matchManager.normalizePlayerKey(first).lowercased()
        let s = matchManager.normalizePlayerKey(second).lowercased()
        return compoundNamePairs.contains("\(f) \(s)")
    }

    private var compoundNamePairs: Set<String> {
        return [
            "juan carlos",
            "juan pablo",
            "juan manuel",
            "juan jose",
            "juan luis",
            "juan diego",
            "jose luis",
            "jose maria",
            "jose manuel",
            "jose antonio",
            "maria jose",
            "maria carmen",
            "maria fernanda",
            "maria angeles",
            "ana maria",
            "ana sofia"
        ]
    }

    private func isValidPlayerName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let lower = matchManager.normalizePlayerKey(trimmed).lowercased()
        if containsNoiseDictation(lower) { return false }
        if trimmed.count > 30 { return false }
        let tokens = lower.split(separator: " ").map { String($0) }
        if tokens.isEmpty || tokens.count > 3 { return false }
        if tokens.contains(where: { bannedNameTokens.contains($0) }) { return false }
        if tokens.contains(where: { $0.count < 2 }) { return false }
        if trimmed.range(of: #"\d"#, options: .regularExpression) != nil { return false }
        let letters = trimmed.filter { $0.isLetter }
        if letters.isEmpty { return false }
        return true
    }

    private var bannedNameTokens: Set<String> {
        return [
            "el","la","los","las","un","una","unos","unas","de","del","al","por","para","con","sin","y","e","o","u",
            "yo","mi","mis","mio","mia","tu","tus","su","sus","nosotros","ustedes",
            "soy","somos","ser","estar","estoy","estas","esta","estan","juego","juega","juegan","jugamos","jugar",
            "companero","companeros","compañero","compañeros","pareja","parejas",
            "contra","vs","versus",
            "recibe","recibo","recibes","da","doy","das","dame",
            "lleva","llevo","llevas","llevan","strokes","golpe","golpes",
            "muy","bueno","malo","grande","pequeno","pequeño","nuevo","viejo","ultimo","último","primer","primero",
            "subtitulo","subtitulos","subtítulos","caption","subtitles","amara","org",
            "agrega","agregar","agrego","agregue","agregué","agregamos","agregan","añade","añadir","añado",
            "dictado","transcribe","transcribir","nombres","propios","numeros","precisión","precision",
            "palabras","clave","inventes","texto","golf"
        ]
    }

    private func containsNoiseDictation(_ text: String) -> Bool {
        return hasWord(text, "subtitulo") ||
            hasWord(text, "subtitulos") ||
            text.contains("subtitles") ||
            text.contains("caption") ||
            text.contains("amara") ||
            hasWord(text, "dictado") ||
            hasWord(text, "transcribe") ||
            hasWord(text, "transcribir") ||
            hasWord(text, "nombres") ||
            hasWord(text, "propios") ||
            hasWord(text, "numeros") ||
            hasWord(text, "precisión") ||
            hasWord(text, "precision") ||
            hasWord(text, "palabras") ||
            hasWord(text, "clave") ||
            hasWord(text, "inventes") ||
            hasWord(text, "texto") ||
            hasWord(text, "golf")
    }

    private func hasWord(_ text: String, _ word: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = #"(?i)\b\#(escaped)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func extractFirstNumber(from text: String) -> Int? {
        let pattern = #"(?i)\b(\d{1,2})\b"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let match = String(text[range])
            return Int(match)
        }
        return nil
    }

    private func stripStrokeClause(_ text: String) -> String {
        let pattern = #"(?i)\b(recibe|recibo|da|doy|lleva|llevo|llevas|llevan)\b.*$"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func splitMatchup(_ text: String) -> (left: String, right: String)? {
        let pattern = #"(?i)\b(versus|contra|vs|v\.s\.)\b"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let left = String(text[..<range.lowerBound])
        let right = String(text[range.upperBound...])
        return (left: left, right: right)
    }

    private func substringAfterPattern(_ text: String, pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return after.isEmpty ? nil : after
    }
}

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }

    private var clockView: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            Text(timeFormatter.string(from: context.date))
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
        }
    }
    
    private var voiceRecordingSection: some View {
        VStack(spacing: 8) {
            recordButton
            Text(voiceRecorder.isRecording ? "Toca para terminar" : "Toca para grabar")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
    
    private var bottomControls: some View {
        VStack(spacing: 8) {
            if pendingEntities != nil {
                pendingActionBar
            } else {
                voiceRecordingSection
            }
            
            if isProcessing {
                HStack {
                    ProgressView()
                    Text("Procesando...")
                        .font(.caption)
                }
                .padding(.bottom, 4)
            }

        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var recordButton: some View {
        Button(action: {
            toggleRecording()
        }) {
            ZStack {
                Circle()
                    .fill(voiceRecorder.isRecording ? Color.red : Color.blue)
                Image(systemName: voiceRecorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .frame(width: 60, height: 60)
        }
        .disabled(isProcessing)
        .accessibilityLabel(voiceRecorder.isRecording ? "Detener grabación" : "Iniciar grabación")
    }

    private func toggleRecording() {
        if !isSetupComplete {
            statusMessage = "Completa setup: \(missingSetupList().joined(separator: ", "))."
        }
        if showRoundSetup {
            statusMessage = "Cierra Configuración para dictar en principal."
            return
        }
        if pendingTranscriptToParse != nil && !voiceRecorder.isRecording {
            statusMessage = "Confirma o cancela el dictado antes de grabar de nuevo."
            return
        }
        if voiceRecorder.isRecording {
            stopAndProcess()
        } else {
            voiceRecorder.requestPermissions()
            voiceRecorder.startRecording()
        }
    }

    private var isSetupComplete: Bool {
        missingSetupList().isEmpty
    }

    private func missingSetupList() -> [String] {
        var missing: [String] = []
        if matchManager.players.count < 2 {
            missing.append("al menos 2 jugadores")
        }
        if matchManager.courseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("campo")
        }
        if matchManager.startHole < 1 || matchManager.startHole > 18 {
            missing.append("hoyo de salida")
        }
        return missing
    }

    private func appendCardStatus(_ base: String, currentHole: Int?) -> String {
        var parts: [String] = []
        if let inc = matchManager.firstIncompleteHole() {
            let missing = matchManager.missingPlayersForHole(inc)
            let miss = missing.isEmpty ? "" : " (\(missing.joined(separator: ", ")))"
            parts.append("Incompleto: Hoyo \(inc)\(miss)")
        }
        let expected = matchManager.expectedNextHole()
        if let h = currentHole, h != expected {
            parts.append("Hoyo esperado: \(expected)")
        }
        if parts.isEmpty { return base }
        return base + " · " + parts.joined(separator: " · ")
    }

    private func handleSetupTranscript(_ transcript: String) async -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }
        let t = matchManager.normalizePlayerKey(text).lowercased()
        if containsNoiseDictation(t) {
            await MainActor.run {
                statusMessage = "❌ No entendí. Repite."
            }
            return true
        }

        let hasHoleMention = MatchInterpreter.extractHole(from: t) != nil || hasWord(t, "hoyo") || hasWord(t, "oyo")
        let isStartCue = t.contains("salida") || t.contains("inicio") || t.contains("iniciamos") || t.contains("empezamos") || t.contains("arrancamos")
        if isStartCue, let h = MatchInterpreter.extractHole(from: t) {
            await MainActor.run {
                matchManager.updateStartHole(h)
                statusMessage = "✅ Hoyo de salida: \(h)"
            }
            return true
        }

        if t.contains("campo") || t.contains("cgm") {
            await MainActor.run {
                matchManager.setCourse(CourseCatalog.cgm)
                statusMessage = "✅ Campo: CGM"
            }
            return true
        }

        let baseCues = t.contains("companero") || t.contains("companeros") ||
            t.contains("compañero") || t.contains("compañeros") ||
            t.contains("oponente") || t.contains("oponentes") ||
            t.contains("pareja") || t.contains("parejas") ||
            t.contains("contra") || t.contains("vs") || t.contains("versus") ||
            hasWord(t, "con")

        if baseCues && !hasHoleMention {
            let unknown = strictUnknownNames(in: text)
            if !unknown.isEmpty {
                await MainActor.run {
                    statusMessage = invalidNamesMessage(unknown)
                }
                return true
            }
            let ok = applyBaseFromText(text)
            await MainActor.run {
                statusMessage = ok ? "✅ Parejas actualizadas" : "❌ No entendí parejas. Repite."
            }
            return true
        }

        if !hasHoleMention {
            let updates = parseStrokeUpdatesSetup(text)
            if !updates.isEmpty {
                await MainActor.run {
                    for u in updates {
                        matchManager.setStrokesVsBase(alias: u.alias, value: u.value)
                    }
                    let summary = updates.map { "\($0.alias) \($0.value > 0 ? "+" : "")\($0.value)" }.joined(separator: ", ")
                    statusMessage = "✅ Strokes: \(summary)"
                }
                return true
            }
        }

        let names = extractNamesFromSetupText(text).filter { isValidPlayerName($0) }
        if !names.isEmpty && !hasHoleMention {
            let filtered = await confirmNamesWithLLM(candidates: names, transcript: text)
            let finalNames = filtered.isEmpty ? names : filtered
            if finalNames.isEmpty {
                await MainActor.run {
                    statusMessage = "❌ No entendí el nombre. Repite."
                }
                return true
            }
            await MainActor.run {
                var added: [String] = []
                for name in finalNames {
                    if matchManager.addPlayer(name: name) {
                        added.append(name)
                    }
                }
                if added.isEmpty {
                    statusMessage = matchManager.players.count >= 5 ? "❌ Máximo 5 jugadores" : "❌ No pude agregar jugadores"
                } else {
                    statusMessage = "✅ Agregados: \(added.joined(separator: ", "))"
                }
            }
            return true
        }

        return false
    }

    private func confirmNamesWithLLM(candidates: [String], transcript: String) async -> [String] {
        do {
            let result = try await OpenAIService.shared.confirmPlayerNames(candidates: candidates, transcript: transcript)
            return result.accepted
        } catch {
            return candidates
        }
    }

    private func applyBaseFromText(_ text: String) -> Bool {
        let trimmed = stripStrokeClause(text)
        let unknown = strictUnknownNames(in: trimmed)
        if !unknown.isEmpty { return false }
        if let split = splitMatchup(trimmed) {
            var base = extractAliasesPreferNames(split.left)
            let opp = extractAliasesPreferNames(split.right)
            let t = matchManager.normalizePlayerKey(split.left).lowercased()
            if t.contains("yo") || t.contains("mi") || t.contains("mis") {
                if !base.contains(matchManager.yoAlias) { base.insert(matchManager.yoAlias, at: 0) }
            }
            if base.count < 2 || opp.count < 2 { return false }
            return matchManager.setBaseTeam(base, opponentsOverride: opp)
        }

        let ordered = orderedAliasesFromText(trimmed)
        if ordered.count == 4 {
            let base = Array(ordered.prefix(2))
            let opp = Array(ordered.suffix(2))
            if disjointTeams(base, opp) {
                return matchManager.setBaseTeam(base, opponentsOverride: opp)
            }
        }

        var base: [String] = []
        var opp: [String] = []
        if let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcompañeros?\b\s*(son|es|:)?\s*"#) {
            base = extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcompaneros?\b\s*(son|es|:)?\s*"#) {
            base = extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcon\b"#) {
            base = extractAliasesPreferNames(after)
        }
        if let oppAfter = substringAfterPattern(trimmed, pattern: #"(?i)\boponentes?\b\s*(son|es|:)?\s*"#) {
            opp = extractAliasesPreferNames(oppAfter)
        }
        let t = matchManager.normalizePlayerKey(trimmed).lowercased()
        if (t.contains("yo") || t.contains("mi") || t.contains("mis")) && !base.contains(matchManager.yoAlias) {
            base.insert(matchManager.yoAlias, at: 0)
        }
        if base.isEmpty {
            base = extractAliasesPreferNames(trimmed)
        }
        if opp.isEmpty {
            opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
        }
        if base.count < 2 || opp.count < 2 { return false }
        return matchManager.setBaseTeam(base, opponentsOverride: opp)
    }

    private func disjointTeams(_ a: [String], _ b: [String]) -> Bool {
        let sa = Set(a)
        let sb = Set(b)
        return sa.intersection(sb).isEmpty
    }

    private func parseStrokeUpdatesSetup(_ text: String) -> [(alias: String, value: Int)] {
        let separators = [",", ";", " y ", " e "]
        var parts: [String] = [text]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        var updates: [(alias: String, value: Int)] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = parseStrokeUpdateSetup(trimmed) {
                updates.append(u)
            }
        }
        return updates
    }

    private func parseStrokeUpdateSetup(_ text: String) -> (alias: String, value: Int)? {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let num = extractFirstNumber(from: text) else { return nil }
        let hasReceive = hasWord(t, "recibe") || hasWord(t, "recibo") || hasWord(t, "recibes") || hasWord(t, "reciben") ||
            t.contains("le dan") || t.contains("le da") ||
            hasWord(t, "tengo") || hasWord(t, "tiene") || hasWord(t, "tienen") ||
            hasWord(t, "lleva") || hasWord(t, "llevo") || hasWord(t, "llevan")
        let hasGive = hasWord(t, "da") || hasWord(t, "doy") || hasWord(t, "das") || hasWord(t, "dame") || hasWord(t, "dan") || hasWord(t, "damos")
        let hasSpeakerGive = hasWord(t, "doy") || hasWord(t, "damos")
        let hasMeDa = t.contains("me da") || t.contains("me dan")
        let hasToCue = t.contains(" a ") || t.contains(" para ")
        if !hasReceive && !hasGive { return nil }
        var aliases = aliasesMatchedByName(text)
        if aliases.isEmpty {
            aliases = extractAliasesFromText(text)
        }
        if aliases.isEmpty { return nil }
        let named = aliases.filter { $0 != matchManager.yoAlias }
        let target = named.first ?? aliases.first!

        // Examples:
        // "Anselmo doy 5" -> Anselmo +5 (yo doy, él recibe)
        // "Roberto me da 10" -> Roberto -10 (él da, yo recibo)
        if hasSpeakerGive {
            return (target, num)
        }
        if hasMeDa {
            return (target, -num)
        }
        let receiverMode = hasReceive || hasToCue
        let value = receiverMode ? num : -num
        return (target, value)
    }

    private func extractAliasesFromText(_ text: String) -> [String] {
        var result: [String] = []
        let t = matchManager.normalizePlayerKey(text).lowercased()
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey) && containsWholePhrase(t, phrase: aliasKey) {
                result.append(p.alias)
            }
            if !nameKey.isEmpty && containsWholePhrase(t, phrase: nameKey) {
                result.append(p.alias)
            }
        }
        let tokens = t.split(separator: " ").map { String($0) }
        for token in tokens {
            if matchManager.isAmbiguousAliasToken(token) { continue }
            if let a = matchManager.normalizeAlias(token) {
                result.append(a)
            }
        }
        if t.contains("yo") {
            result.append(matchManager.yoAlias)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private func extractAliasesPreferNames(_ text: String) -> [String] {
        let byName = aliasesMatchedByName(text)
        if !byName.isEmpty { return byName }
        return extractAliasesFromText(text)
    }

    private func aliasesMatchedByName(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        if normalized.isEmpty { return [] }
        var hits: [String] = []
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if nameKey.isEmpty { continue }
            if containsWholePhrase(normalized, phrase: nameKey) {
                hits.append(p.alias)
            }
        }
        if !hits.isEmpty {
            var seen = Set<String>()
            return hits.filter { seen.insert($0).inserted }
        }
        let uniqueFirst = uniqueFirstNameMap()
        let tokens = normalized.split(separator: " ").map { String($0) }
        for token in tokens {
            if let alias = uniqueFirst[token] {
                hits.append(alias)
            }
        }
        var seen = Set<String>()
        return hits.filter { seen.insert($0).inserted }
    }

    private func uniqueFirstNameMap() -> [String: String] {
        var buckets: [String: [String]] = [:]
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            guard let first = nameKey.split(separator: " ").first.map(String.init),
                  !first.isEmpty else { continue }
            buckets[first, default: []].append(p.alias)
        }
        var unique: [String: String] = [:]
        for (first, aliases) in buckets where aliases.count == 1 {
            unique[first] = aliases[0]
        }
        return unique
    }

    private func containsWholePhrase(_ text: String, phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)\b\#(escaped)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func orderedAliasesFromText(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        var hits: [(alias: String, idx: Int)] = []
        for p in matchManager.players {
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey),
               let range = normalized.range(of: aliasKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
            }
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if !nameKey.isEmpty, let range = normalized.range(of: nameKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
            }
        }
        let sorted = hits.sorted { $0.idx < $1.idx }
        var seen = Set<String>()
        var out: [String] = []
        for hit in sorted {
            if seen.contains(hit.alias) { continue }
            seen.insert(hit.alias)
            out.append(hit.alias)
        }
        return out
    }

    private func strictUnknownNames(in text: String) -> [String] {
        let candidates = extractNamesFromSetupText(text)
        if candidates.isEmpty { return [] }
        var unknown: [String] = []
        for c in candidates {
            if matchManager.normalizeAlias(c) == nil && aliasesMatchedByName(c).isEmpty {
                unknown.append(c)
            }
        }
        return unknown
    }

    private func invalidNamesMessage(_ names: [String]) -> String {
        let valid = matchManager.players.map { "\($0.alias) (\($0.name))" }.joined(separator: ", ")
        let unknown = names.joined(separator: ", ")
        return "❌ Jugador no parte de este match: \(unknown). Válidos: \(valid)."
    }

    private func extractNamesFromSetupText(_ text: String) -> [String] {
        let lower = matchManager.normalizePlayerKey(text).lowercased()
        let hasListCue = lower.contains("juegan") || lower.contains("juega") ||
            lower.contains("jugadores") || lower.contains("son") || lower.contains("somos") ||
            lower.contains("jugamos") || lower.contains("agrego") || lower.contains("agrega") ||
            lower.contains("agregar") || lower.contains("añado") || lower.contains("añade")
        let listNames = extractNamesFromList(text)
        if hasListCue && listNames.count >= 2 {
            return listNames
        }
        return extractNamesFromList(text)
    }

    private func extractNamesFromList(_ text: String) -> [String] {
        var cleaned = text
        let removePattern = #"(?i)\b(agrega|agregar|agrego|agregue|agregué|agregamos|agregan|añade|añadir|añado|nuevo|jugador|jugadores|soy|somos|compañero|compañeros|companero|companeros|mi|mis|yo|base|contra|vs|versus|pareja|juegan|jugamos|los|lleva|llevo|llevas|llevan|strokes|golpes|recibe|recibo|da|doy|subtitulo|subtitulos|subtítulos|realizado|realizados|comunidad|amara|org|caption|subtitles|de|del|la|el|los|las|por|para|muy)\b"#
        cleaned = cleaned.replacingOccurrences(of: removePattern, with: " ", options: .regularExpression)
        let separators = [" y ", " e ", ",", ";", "&", "+", " con "]
        for s in separators {
            cleaned = cleaned.replacingOccurrences(of: s, with: ",")
        }
        let parts = cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return [] }
        var out: [String] = []
        for part in parts {
            let tokens = part.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            var i = 0
            while i < tokens.count {
                let t = tokens[i]
                if i + 1 < tokens.count,
                   isCompoundNamePair(first: t, second: tokens[i + 1]) {
                    let combined = "\(t) \(tokens[i + 1])"
                    if isValidPlayerName(combined) {
                        out.append(combined)
                        i += 2
                        continue
                    }
                }
                if isValidPlayerName(t) {
                    out.append(t)
                }
                i += 1
            }
        }
        return out
    }

    private func isCompoundNamePair(first: String, second: String) -> Bool {
        let f = matchManager.normalizePlayerKey(first).lowercased()
        let s = matchManager.normalizePlayerKey(second).lowercased()
        return compoundNamePairs.contains("\(f) \(s)")
    }

    private var compoundNamePairs: Set<String> {
        return [
            "juan carlos",
            "juan pablo",
            "juan manuel",
            "juan jose",
            "juan luis",
            "juan diego",
            "jose luis",
            "jose maria",
            "jose manuel",
            "jose antonio",
            "maria jose",
            "maria carmen",
            "maria fernanda",
            "maria angeles",
            "ana maria",
            "ana sofia"
        ]
    }

    private func containsNoiseDictation(_ text: String) -> Bool {
        return hasWord(text, "subtitulo") ||
            hasWord(text, "subtitulos") ||
            text.contains("subtitles") ||
            text.contains("caption") ||
            text.contains("amara") ||
            hasWord(text, "dictado") ||
            hasWord(text, "transcribe") ||
            hasWord(text, "transcribir") ||
            hasWord(text, "nombres") ||
            hasWord(text, "propios") ||
            hasWord(text, "numeros") ||
            hasWord(text, "precisión") ||
            hasWord(text, "precision") ||
            hasWord(text, "palabras") ||
            hasWord(text, "clave") ||
            hasWord(text, "inventes") ||
            hasWord(text, "texto") ||
            hasWord(text, "golf")
    }

    private func isValidPlayerName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let lower = matchManager.normalizePlayerKey(trimmed).lowercased()
        if containsNoiseDictation(lower) { return false }
        if trimmed.count > 30 { return false }
        let tokens = lower.split(separator: " ").map { String($0) }
        if tokens.isEmpty || tokens.count > 3 { return false }
        if tokens.contains(where: { bannedNameTokens.contains($0) }) { return false }
        if tokens.contains(where: { $0.count < 2 }) { return false }
        if trimmed.range(of: #"\\d"#, options: .regularExpression) != nil { return false }
        let letters = trimmed.filter { $0.isLetter }
        if letters.isEmpty { return false }
        return true
    }

    private var bannedNameTokens: Set<String> {
        return [
            "el","la","los","las","un","una","unos","unas","de","del","al","por","para","con","sin","y","e","o","u",
            "yo","mi","mis","mio","mia","tu","tus","su","sus","nosotros","ustedes",
            "soy","somos","ser","estar","estoy","estas","esta","estan","juego","juega","juegan","jugamos","jugar",
            "base","companero","companeros","compañero","compañeros","pareja","parejas",
            "contra","vs","versus",
            "recibe","recibo","recibes","da","doy","das","dame",
            "lleva","llevo","llevas","llevan","strokes","golpe","golpes",
            "muy","bueno","malo","grande","pequeno","pequeño","nuevo","viejo","ultimo","último","primer","primero",
            "subtitulo","subtitulos","subtítulos","caption","subtitles","amara","org",
            "agrega","agregar","agrego","agregue","agregué","agregamos","agregan","añade","añadir","añado",
            "dictado","transcribe","transcribir","nombres","propios","numeros","precisión","precision",
            "palabras","clave","inventes","texto","golf"
        ]
    }

    private func stripStrokeClause(_ text: String) -> String {
        let pattern = #"(?i)\b(recibe|recibo|da|doy|lleva|llevo|llevas|llevan)\b.*$"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func splitMatchup(_ text: String) -> (left: String, right: String)? {
        let pattern = #"(?i)\b(versus|contra|vs|v\.s\.)\b"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let left = String(text[..<range.lowerBound])
        let right = String(text[range.upperBound...])
        return (left: left, right: right)
    }

    private func substringAfterPattern(_ text: String, pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return after.isEmpty ? nil : after
    }

    private func transcriptSignalScore(_ text: String) -> Int {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        var score = 0
        let aliases = detectAliases(in: normalized)
        score += aliases.count * 3
        if MatchInterpreter.extractHole(from: normalized) != nil { score += 2 }
        if extractFirstNumber(from: normalized) != nil { score += 1 }
        if normalized.contains("putt") || normalized.contains("putts") { score += 1 }
        return score
    }

    private func detectAliases(in normalizedText: String) -> Set<String> {
        var out = Set<String>()
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if normalizedText.contains(p.alias.lowercased()) || (!nameKey.isEmpty && normalizedText.contains(nameKey)) {
                out.insert(p.alias)
            }
        }
        if normalizedText.contains("yo") || normalizedText.contains("mi") || normalizedText.contains("mio") || normalizedText.contains("mia") {
            out.insert(matchManager.yoAlias)
        }
        let tokens = normalizedText.split(separator: " ").map { String($0) }
        for token in tokens {
            if let alias = matchManager.normalizeAlias(token) {
                out.insert(alias)
            }
        }
        return out
    }

    private func extractFirstNumber(from text: String) -> Int? {
        let pattern = #"(?i)\b(\d{1,2})\b"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let match = String(text[range])
            return Int(match)
        }
        return nil
    }
    
    private var statusDisplayView: some View {
        VStack(alignment: .leading, spacing: 8) {
                if !voiceRecorder.transcript.isEmpty {
                    VStack(spacing: 8) {
                        Text(voiceRecorder.transcript)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 14)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.yellow.opacity(0.6), lineWidth: 2)
                )
            }
            
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(statusMessage.contains("✅") ? .green :
                                   statusMessage.contains("❌") ? .red : .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal, 12)
    }

    private var transcriptConfirmView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Confirmar dictado")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            TextEditor(text: $editableTranscript)
                .frame(minHeight: 90, maxHeight: 140)
                .padding(8)
                .background(Color(.systemBackground))
                .cornerRadius(8)

            HStack(spacing: 12) {
                Button("Cancelar") {
                    pendingTranscriptToParse = nil
                    editableTranscript = ""
                    statusMessage = "Dictado cancelado."
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)

                Button("Analizar") {
                    analyzePendingTranscript()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || editableTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func confirmationCard(_ entities: ScoreEntities, transcript: String) -> some View {
        let holeNumber = entities.hoyo ?? 0
        let hole = matchManager.getHole(holeNumber)
        let par = hole?.par ?? 0
        let si = hole?.si ?? 0
        let scores = entities.scores ?? []
        let sideLabel = "Vuelta"
        let filled = filledHolesForSide(holeNumber)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Confirmación · Hoyo \(holeNumber)")
                    .font(.headline)
                Spacer()
                Text(sideLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
            }

            if !transcript.isEmpty {
                Text("“\(transcript)”")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }

            horizontalCard(hole: holeNumber, par: par, si: si, scores: scores)

            Button(showPuttsDetail ? "Ocultar putts" : "Ver putts") {
                showPuttsDetail.toggle()
            }
            .font(.caption)

            if showPuttsDetail {
                VStack(spacing: 6) {
                    ForEach(scores.indices, id: \.self) { idx in
                        let s = scores[idx]
                        if let p = s.putts {
                            row(label: "\(s.jugador.uppercased()) putts", value: "\(p)")
                        }
                    }
                }
            }

            if !filled.isEmpty {
                Text("Ya registrados en esta vuelta")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                ForEach(filled, id: \.hole) { item in
                    row(label: "Hoyo \(item.hole)", value: item.summary)
                }
            }

            // Botones moved to pendingActionBar for easier access
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.bold())
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    private func horizontalCard(hole: Int, par: Int, si: Int, scores: [PlayerScore]) -> some View {
        let columns: [(String, String)] = {
            var items: [(String, String)] = [("Hoyo", "\(hole)")]
            if par > 0 { items.append(("Par", "\(par)")) }
            if si > 0 { items.append(("SI", "\(si)")) }
            for s in scores {
                items.append((s.jugador.uppercased(), "\(s.gross)"))
            }
            return items
        }()

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<columns.count, id: \.self) { idx in
                    let col = columns[idx]
                    VStack(spacing: 6) {
                        Text(col.0)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(col.1)
                            .font(.headline)
                    }
                    .frame(width: 90)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func filledHolesForSide(_ holeNumber: Int) -> [(hole: Int, summary: String)] {
        let range = currentNineHoles(start: matchManager.startHole)
        var results: [(Int, String)] = []
        for hole in range {
            var parts: [String] = []
            for player in matchManager.players {
                let score = matchManager.getScore(hole: hole, player: player.alias)
                if score > 0 {
                    parts.append("\(player.alias) \(score)")
                }
            }
            if !parts.isEmpty {
                results.append((hole, parts.joined(separator: " | ")))
            }
        }
        return results
    }
    
    private var scorecardView: some View {
        let holesToShow = currentNineHoles(start: matchManager.startHole)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Hoyo").frame(width: 60).font(.caption.bold())
                Text("Par").frame(width: 50).font(.caption.bold())
                ForEach(matchManager.players) { player in
                    Text(player.alias)
                        .font(.caption.bold())
                        .frame(minWidth: 70)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            
            ForEach(holesToShow, id: \.self) { holeNumber in
                holeRow(holeNumber: holeNumber)
            }
        }
        .cornerRadius(12)
        .padding()
    }

    private func currentNineHoles(start: Int) -> [Int] {
        let s = max(1, min(18, start))
        var holes: [Int] = []
        for i in 0..<9 {
            let h = ((s - 1 + i) % 18) + 1
            holes.append(h)
        }
        return holes
    }
    
    private func holeRow(holeNumber: Int) -> some View {
        let isIncomplete = matchManager.firstIncompleteHole() == holeNumber
        let isLastComplete = matchManager.lastCompleteHole() == holeNumber
        return HStack(spacing: 0) {
            Text("\(holeNumber)")
                .frame(width: 60)
                .font(.headline)
            
            Text("\(matchManager.getHole(holeNumber)?.par ?? 4)")
                .frame(width: 50)
                .foregroundColor(.secondary)
            
            ForEach(matchManager.players) { player in
                let score = matchManager.getScore(hole: holeNumber, player: player.alias)
                let putts = matchManager.getPutts(hole: holeNumber, player: player.alias)
                
                VStack(spacing: 2) {
                    Text(score > 0 ? "\(score)" : "—")
                        .font(.headline)
                        .foregroundColor(scoreColor(score: score, par: matchManager.getHole(holeNumber)?.par ?? 4))
                    
                    if putts > 0 {
                        Text("(\(putts)p)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 70)
            }
        }
        .padding(.vertical, 12)
        .background(rowBackground(isIncomplete: isIncomplete, isLastComplete: isLastComplete, holeNumber: holeNumber))
    }

    private func rowBackground(isIncomplete: Bool, isLastComplete: Bool, holeNumber: Int) -> Color {
        if isIncomplete {
            return Color.orange.opacity(0.15)
        }
        if isLastComplete {
            return Color.green.opacity(0.12)
        }
        return holeNumber % 2 == 0 ? Color(.systemBackground) : Color(.secondarySystemBackground)
    }
    
    private func scoreColor(score: Int, par: Int) -> Color {
        if score == 0 { return .secondary }
        if score < par { return .green }
        if score == par { return .primary }
        return .red
    }

    private func isMissingApiKeyError(_ error: Error) -> Bool {
        let message = (error as NSError).localizedDescription
        return message.localizedCaseInsensitiveContains("OPENAI_API_KEY")
    }
    
    private func stopAndProcess() {
        guard let audioURL = voiceRecorder.stopRecording() else { return }
        
        isProcessing = true
        statusMessage = "🎤 Transcribiendo..."
        pendingAudioFilename = saveAudioCopy(from: audioURL)
        
        Task {
            do {
                var transcriptSource = "OPENAI"
                var transcript = ""
                var appleText = ""
                var appleConfidence = 0.0
                do {
                    let apple = try await voiceRecorder.transcribeWithApple(url: audioURL)
                    appleText = apple.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    appleConfidence = apple.confidence
                } catch {
                    // ignore, fallback to OpenAI
                }
                if !appleText.isEmpty {
                    let appleScore = transcriptSignalScore(appleText) + (appleConfidence >= appleConfidenceThreshold ? 1 : 0)
                    if appleScore >= 4 {
                        transcript = appleText
                        transcriptSource = "APPLE"
                    }
                }
                if transcript.isEmpty {
                    do {
                        let rawTranscript = try await OpenAIService.shared.transcribeAudio(url: audioURL)
                        transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                        transcriptSource = "OPENAI"
                    } catch {
                        if isMissingApiKeyError(error) {
                            if !appleText.isEmpty {
                                transcript = appleText
                                transcriptSource = "APPLE"
                            } else {
                                await MainActor.run {
                                    statusMessage = "❌ Falta OPENAI_API_KEY en Info.plist."
                                    logEvent(
                                        action: "Error",
                                        tag: "ERROR",
                                        status: "CONFIG",
                                        transcript: "",
                                        hole: pendingEntities?.hoyo ?? 0,
                                        scores: pendingEntities?.scores ?? [],
                                        error: error.localizedDescription,
                                        audioFilename: pendingAudioFilename
                                    )
                                    isProcessing = false
                                }
                                return
                            }
                        } else {
                            throw error
                        }
                    }
                }
                transcript = normalizeTranscript(transcript)
                if containsNoiseDictation(transcript.lowercased()) {
                    transcript = ""
                }
                let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTranscript.isEmpty {
                    await MainActor.run {
                        voiceRecorder.transcript = ""
                        statusMessage = "❌ No se detectó dictado. Repite."
                        logEvent(
                            action: "Ruido",
                            tag: "ERROR",
                            status: "NO_DICTATION",
                            transcript: "",
                            hole: 0,
                            scores: [],
                            error: "EMPTY_TRANSCRIPT",
                            audioFilename: pendingAudioFilename
                        )
                        isProcessing = false
                    }
                    return
                }
                
                await MainActor.run {
                    voiceRecorder.transcript = transcript
                    logEvent(
                        action: "Transcripción",
                        tag: "\(classifyTag(transcript))_\(transcriptSource)",
                        status: "CAPTURADO",
                        transcript: transcript,
                        hole: pendingEntities?.hoyo ?? 0,
                        scores: pendingEntities?.scores ?? [],
                        audioFilename: pendingAudioFilename
                    )
                }

                if let pending = pendingEntities, isVoiceConfirm(transcript) {
                    await MainActor.run {
                        let missing = missingInfoList(pending)
                        if !missing.isEmpty {
                            statusMessage = "❌ \(missingInfoStatus(pending))"
                            isProcessing = false
                            return
                        }
                        if needsOverwrite(pending) && !pendingOverwrite {
                            pendingOverwrite = true
                            statusMessage = "⚠️ Hoyo \(pending.hoyo ?? 0) ya tiene datos. Di \"confirmar\" otra vez para sobrescribir."
                            isProcessing = false
                            return
                        }
                        let result = matchManager.applyScores(pending)
                        statusMessage = "✅ Confirmado por voz. \(applyStatusText(result)): Hoyo \(pending.hoyo ?? 0)"
                        lastConfirmedEntities = pending
                        lastConfirmedTranscript = pendingTranscript
                        logEvent(
                            action: "Confirmado por voz",
                            tag: "CONFIRM",
                            status: "GUARDADO",
                            transcript: transcript,
                            hole: pending.hoyo ?? 0,
                            scores: pending.scores ?? []
                        )
                        pendingEntities = nil
                        pendingTranscript = nil
                        currentHole = nil
                        pendingOverwrite = false
                        isProcessing = false
                    }
                    return
                }

                if pendingEntities != nil, isVoiceCorrection(transcript) {
                    await MainActor.run {
                        statusMessage = "✍️ Corrige y vuelve a dictar."
                        logEvent(
                            action: "Corregir por voz",
                            tag: "CORRECT",
                            status: "DESCARTADO",
                            transcript: transcript,
                            hole: pendingEntities?.hoyo ?? 0,
                            scores: pendingEntities?.scores ?? []
                        )
                        pendingEntities = nil
                        pendingTranscript = nil
                        currentHole = nil
                        pendingOverwrite = false
                        isProcessing = false
                    }
                    return
                }

                await MainActor.run {
                    pendingTranscriptToParse = transcript
                    editableTranscript = transcript
                    statusMessage = "📝 Revisa el dictado y toca Analizar."
                    isProcessing = false
                }
                return
                
            } catch {
                await MainActor.run {
                    statusMessage = "❌ Error al procesar audio. Intenta de nuevo."
                    logEvent(
                        action: "Error",
                        tag: "ERROR",
                        status: "AUDIO",
                        transcript: voiceRecorder.transcript,
                        hole: pendingEntities?.hoyo ?? 0,
                        scores: pendingEntities?.scores ?? [],
                        error: error.localizedDescription,
                        audioFilename: pendingAudioFilename
                    )
                    isProcessing = false
                }
            }
        }
    }

    private func analyzePendingTranscript() {
        let text = editableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            statusMessage = "❌ El dictado está vacío."
            return
        }
        pendingTranscriptToParse = nil
        isProcessing = true
        statusMessage = "🧠 Analizando..."
        Task {
            await processTranscript(text)
        }
    }

    private func processTranscript(_ transcript: String) async {
        do {
            let result = try await OpenAIService.shared.parseScore(
                transcript: transcript,
                matchState: matchManager.exportState()
            )

            await MainActor.run {
                let interpreted = MatchInterpreter.apply(
                    transcript: transcript,
                    entities: result.entities,
                    match: matchManager
                )
                if let err = interpreted.error {
                    if err == "NOISE" {
                        statusMessage = "❌ No entendí. Di: \"Hoyo 5 Roberto 6\"."
                        logEvent(
                            action: "Ruido",
                            tag: "ERROR",
                            status: "NOISE",
                            transcript: transcript,
                            hole: 0,
                            scores: [],
                            error: "NOISE",
                            audioFilename: pendingAudioFilename
                        )
                    } else {
                        statusMessage = "❌ \(friendlyInterpreterError(err, entities: interpreted.entities))"
                        logEvent(
                            action: "Error",
                            tag: "ERROR",
                            status: "INCOMPLETO",
                            transcript: transcript,
                            hole: interpreted.entities.hoyo ?? 0,
                            scores: interpreted.entities.scores ?? [],
                            error: err,
                            audioFilename: pendingAudioFilename
                        )
                    }
                    isProcessing = false
                    return
                }

                let hasData = interpreted.entities.hoyo != nil && (interpreted.entities.scores?.isEmpty == false)
                if interpreted.usedFuzzy, let scores = interpreted.entities.scores, !scores.isEmpty {
                    fuzzyReviewScores = scores.map { ReviewScore(alias: $0.jugador, gross: $0.gross, putts: $0.putts) }
                    fuzzyReviewHole = interpreted.entities.hoyo
                    fuzzyReviewTranscript = transcript
                    showFuzzyReview = true
                    isProcessing = false
                    return
                }

                if result.ok || hasData {
                    handleParsedEntities(interpreted.entities, transcript: transcript, showFuzzyNotice: interpreted.usedFuzzy)
                } else {
                    let missing = missingInfoStatus(interpreted.entities)
                    let fuzzyNotice = interpreted.usedFuzzy ? " ⚠️ Nombres aproximados. Si está mal, repite con nombre completo." : ""
                    statusMessage = (missing.isEmpty ? "❌ Falta información." : "❌ \(missing)") + fuzzyNotice
                    logEvent(
                        action: "Error",
                        tag: "ERROR",
                        status: "INCOMPLETO",
                        transcript: transcript,
                        hole: interpreted.entities.hoyo ?? 0,
                        scores: interpreted.entities.scores ?? [],
                        error: result.error ?? "Desconocido",
                        audioFilename: pendingAudioFilename
                    )
                }
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                if isMissingApiKeyError(error) {
                    statusMessage = "❌ Falta OPENAI_API_KEY en Info.plist."
                } else {
                    statusMessage = "❌ Error al analizar dictado."
                }
                logEvent(
                    action: "Error",
                    tag: "ERROR",
                    status: "ANALYZE",
                    transcript: transcript,
                    hole: pendingEntities?.hoyo ?? 0,
                    scores: pendingEntities?.scores ?? [],
                    error: error.localizedDescription,
                    audioFilename: pendingAudioFilename
                )
                isProcessing = false
            }
        }
    }

    @MainActor
    private func handleParsedEntities(_ entities: ScoreEntities, transcript: String, showFuzzyNotice: Bool) {
        let fuzzyNotice = showFuzzyNotice ? " ⚠️ Nombres aproximados. Si está mal, repite con nombre completo." : ""
        if let pending = pendingEntities,
           !missingInfoList(pending).isEmpty,
           let pendingHole = pending.hoyo,
           let incomingHole = entities.hoyo,
           incomingHole != pendingHole {
            statusMessage = "❌ Falta completar Hoyo \(pendingHole). Di los jugadores que faltan."
            return
        }

        let merged = mergeEntities(pendingEntities, entities)
        pendingEntities = merged
        pendingTranscript = transcript
        currentHole = merged.hoyo
        pendingOverwrite = false

        let missing = missingInfoList(merged)
        if !missing.isEmpty {
            statusMessage = "⚠️ Resultado parcial guardado. \(missingInfoStatus(merged))" + fuzzyNotice
        } else {
            if needsOverwrite(merged) {
                statusMessage = "⚠️ Hoyo \(merged.hoyo ?? 0) ya tiene datos. Confirma para sobrescribir." + fuzzyNotice
            } else {
                statusMessage = "✅ Entendido. Confirma o di \"corregir\". \(pendingUpdateSummary(merged))" + fuzzyNotice
            }
        }
        statusMessage = appendCardStatus(statusMessage, currentHole: merged.hoyo)
        logEvent(
            action: "Entendido",
            tag: "HOLE_ENTRY",
            status: "PENDIENTE",
            transcript: transcript,
            hole: merged.hoyo ?? 0,
            scores: merged.scores ?? []
        )
    }

    private func isVoiceConfirm(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("confirmar") || t.contains("confirmo") || t.contains("correcto") || t == "ok" || t.contains("ok")
    }

    private func isVoiceCorrection(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("corregir") || t.contains("corrige") || t.contains("no") || t.contains("incorrecto")
    }

    private func normalizeTranscript(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(
            of: #"(?i)\b(agujero|ahujero|hueco|oyo|ollo)\b"#,
            with: "hoyo",
            options: .regularExpression
        )
        t = t.replacingOccurrences(
            of: #"(?i)\b(gouey|guey|güey|wey|boi)\b"#,
            with: "",
            options: .regularExpression
        )
        t = t.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runMockHoleEntry() {
        let mock = ScoreEntities(
            hoyo: 12,
            scores: [
                PlayerScore(jugador: "RIC", gross: 5, putts: 2)
            ]
        )
        pendingEntities = mock
        pendingTranscript = "Hoyo 12 Ricardo hizo 5 con 2 putts."
        currentHole = 12
        statusMessage = "✅ Entendido. Confirma para guardar."
    }
    
    private func missingInfoList(_ entities: ScoreEntities) -> [String] {
        var missing: [String] = []
        if entities.hoyo == nil || entities.hoyo == 0 {
            missing.append("hoyo")
        }
        let scores = entities.scores ?? []
        if scores.isEmpty {
            missing.append("golpes")
            return missing
        }
        let provided = Set(scores.map { $0.jugador.uppercased() })
        let allPlayers = matchManager.players.map { $0.alias }
        let missingPlayers = allPlayers.filter { !provided.contains($0) }
        if !missingPlayers.isEmpty {
            missing.append("jugadores: \(missingPlayers.joined(separator: ", "))")
        }
        return missing
    }

    private func needsOverwrite(_ entities: ScoreEntities) -> Bool {
        guard let hole = entities.hoyo, hole > 0 else { return false }
        let scores = entities.scores ?? []
        if scores.isEmpty { return false }
        for s in scores {
            let alias = matchManager.normalizeAlias(s.jugador) ?? s.jugador
            let existing = matchManager.getScore(hole: hole, player: alias)
            if existing > 0 { return true }
        }
        return false
    }
    
    private func mergeEntities(_ base: ScoreEntities?, _ incoming: ScoreEntities) -> ScoreEntities {
        let hole = incoming.hoyo ?? base?.hoyo
        var map: [String: PlayerScore] = [:]
        for s in (base?.scores ?? []) {
            map[s.jugador.uppercased()] = s
        }
        for s in (incoming.scores ?? []) {
            map[s.jugador.uppercased()] = s
        }
        var ordered: [PlayerScore] = []
        for p in matchManager.players {
            if let s = map[p.alias] {
                ordered.append(s)
            }
        }
        for s in map.values where !ordered.contains(where: { $0.jugador.uppercased() == s.jugador.uppercased() }) {
            ordered.append(s)
        }
        let scores = ordered.isEmpty ? nil : ordered
        return ScoreEntities(hoyo: hole, scores: scores)
    }
    
    private func missingInfoStatus(_ entities: ScoreEntities) -> String {
        let missing = missingInfoList(entities)
        if missing.isEmpty { return "" }
        var tips: [String] = []
        if missing.contains("hoyo") {
            tips.append("Di el hoyo (ej: \"Hoyo 7\")")
        }
        if missing.contains("golpes") {
            tips.append("Di golpes por jugador (ej: \"DAN 5, DIE 6\")")
        }
        if let playersPart = missing.first(where: { $0.starts(with: "jugadores:") }) {
            tips.append("Faltan \(playersPart.replacingOccurrences(of: "jugadores: ", with: ""))")
            tips.append("Di el nombre completo si hay confusión")
        }
        let base = "Falta información: \(missing.joined(separator: ", ")). " + tips.joined(separator: " · ")
        return base + " · Puedes grabar para completar."
    }
    
    private func pendingUpdateSummary(_ entities: ScoreEntities) -> String {
        guard let hole = entities.hoyo else { return "" }
        let scores = entities.scores ?? []
        if scores.isEmpty { return "" }
        let segment = matchManager.segmentForHole(hole)
        let segText = segment.isEmpty ? "" : " (\(segment))"
        let names = scores.map { $0.jugador.uppercased() }
        let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
        if unique.count == 1 {
            return "Se actualizará \(unique[0]) en Hoyo \(hole)\(segText)."
        }
        return "Se actualizarán \(unique.joined(separator: ", ")) en Hoyo \(hole)\(segText)."
    }
    
    private func friendlyInterpreterError(_ error: String, entities: ScoreEntities) -> String {
        if error == "NOISE" {
            return "No entendí. Di: \"Hoyo 5 Roberto 6\"."
        }
        if error.contains("perdio el hoyo") || error.contains("perdió el hoyo") {
            return "Falta jugador para \"perdió el hoyo\". Di: \"Hoyo 5 RIC perdió el hoyo\"."
        }
        if error.contains("Faltan scores de los demas") || error.contains("Faltan scores de los demás") {
            return "Faltan golpes de los demás jugadores para calcular \"perdió el hoyo\"."
        }
        if error.contains("Faltan scores de otros jugadores") {
            return "Faltan golpes de otros jugadores."
        }
        let missing = missingInfoStatus(entities)
        if !missing.isEmpty { return missing }
        return "Falta información. Di: \"Hoyo 5 DAN 5 putts 2\"."
    }
    
    private func applyStatusText(_ result: (added: Int, updated: Int)) -> String {
        if result.added > 0 && result.updated > 0 {
            return "Agregado y actualizado"
        }
        if result.updated > 0 {
            return "Actualizado"
        }
        return "Agregado"
    }

    private func logEvent(
        action: String,
        tag: String,
        status: String,
        transcript: String,
        hole: Int,
        scores: [PlayerScore],
        error: String? = nil,
        audioFilename: String? = nil
    ) {
        let date = ISO8601DateFormatter().string(from: Date())
        let players = scores.map { s in
            if let p = s.putts {
                return "\(s.jugador.uppercased()): \(s.gross) golpes, \(p) putts"
            }
            return "\(s.jugador.uppercased()): \(s.gross) golpes"
        }.joined(separator: " | ")
        var line = "[\(date)] \(action) | Tag: \(tag) | Estado: \(status) | Match: \(matchManager.roundId). Transcripción: \"\(transcript)\". Hoyo \(hole). \(players)"
        if let audioFilename = audioFilename {
            line += ". Audio: \(audioFilename)"
        }
        if let error = error {
            line += ". Error: \(error)"
        }
        line += "\n"

        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("llm_log.txt") else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Silently ignore logging errors in MVP
        }
    }

    private func classifyTag(_ text: String) -> String {
        let t = text.lowercased()
        if hasWord(t, "hoyo") || hasWord(t, "oyo") || hasWord(t, "golpes") || hasWord(t, "putts") || hasWord(t, "puts") || hasWord(t, "putt") || hasWord(t, "put") {
            return "HOLE_ENTRY"
        }
        if hasWord(t, "confirmar") || hasWord(t, "confirmo") || hasWord(t, "correcto") || t == "ok" || hasWord(t, "ok") {
            return "CONFIRM"
        }
        if hasWord(t, "corrige") || hasWord(t, "corregir") || hasWord(t, "incorrecto") || t == "no" {
            return "CORRECT"
        }
        if hasWord(t, "unidad") || hasWord(t, "unidades") || hasWord(t, "apuesta") || hasWord(t, "apuestas") {
            return "UNITS"
        }
        if hasWord(t, "press") || hasWord(t, "carry") || hasWord(t, "ajuste") || hasWord(t, "ajustes") {
            return "BETTING"
        }
        if hasWord(t, "jugador") || hasWord(t, "jugadores") {
            return "PLAYERS"
        }
        if t.contains("qué hizo") || hasWord(t, "resultado") || hasWord(t, "cuánto") || hasWord(t, "quién") {
            return "QUERY"
        }
        return "UNKNOWN"
    }

    private func hasWord(_ text: String, _ word: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = #"(?i)\b\#(escaped)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func saveAudioCopy(from url: URL) -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = docs.appendingPathComponent("llm_audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let filename = "audio_\(Int(Date().timeIntervalSince1970)).m4a"
        let dest = dir.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            return filename
        } catch {
            return nil
        }
    }

    private func exportLog() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            statusMessage = "❌ No se pudo acceder a Documentos."
            return
        }
        let logURL = docs.appendingPathComponent("llm_log.txt")
        let jsonURL = docs.appendingPathComponent("scorecard.json")
        do {
            let snapshot = matchManager.scorecardSnapshot()
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted])
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            statusMessage = "❌ No se pudo crear JSON de tarjeta."
            return
        }

        if FileManager.default.fileExists(atPath: logURL.path) {
            shareItems = [logURL, jsonURL]
        } else {
            shareItems = [jsonURL]
        }
        showShareSheet = true
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ReviewScore: Identifiable {
    let id = UUID()
    var alias: String
    var gross: Int
    var putts: Int?
}

struct FuzzyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let hole: Int?
    let transcript: String
    let players: [PlayerModel]
    let onConfirm: ([ReviewScore]) -> Void
    let onCancel: () -> Void
    @State private var scores: [ReviewScore]

    init(
        hole: Int?,
        transcript: String,
        scores: [ReviewScore],
        players: [PlayerModel],
        onConfirm: @escaping ([ReviewScore]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.hole = hole
        self.transcript = transcript
        self.players = players
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _scores = State(initialValue: scores)
    }

    var body: some View {
        NavigationView {
            List {
                Section("Revisión") {
                    if let h = hole {
                        Text("Hoyo \(h)")
                            .font(.headline)
                    }
                    if !transcript.isEmpty {
                        Text(transcript)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section("Jugadores") {
                    ForEach(scores.indices, id: \.self) { i in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Golpes \(scores[i].gross)")
                                    .font(.headline)
                                if let p = scores[i].putts {
                                    Text("Putts \(p)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Picker(
                                "Jugador",
                                selection: Binding(
                                    get: { scores[i].alias },
                                    set: { scores[i].alias = $0 }
                                )
                            ) {
                                ForEach(players, id: \.alias) { p in
                                    Text("\(p.alias) (\(p.name))").tag(p.alias)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .navigationTitle("Confirmar jugadores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirmar") {
                        onConfirm(scores)
                        dismiss()
                    }
                    .disabled(scores.isEmpty)
                }
            }
        }
    }
}
```

## GuidedSetupView

```swift
struct GuidedSetupView: View {
    enum Step: Int, CaseIterable {
        case campo
        case hoyoSalida
        case jugadores
        case strokes
        case parejas
        case strokesParejas
        case apuestas

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
    @State private var strokesByAlias: [String: Int] = [:]
    @State private var base1: String = ""
    @State private var base2: String = ""
    @State private var laneStrokes: [String: Int] = [:]
    @State private var laneCarrierByMatch: [String: String] = [:]
    @State private var vueltaValueText: String = ""
    @State private var presionValueText: String = ""
    @State private var matchValueText: String = ""
    @State private var carryB9ValueText: String = ""
    @State private var presionB9ValueText: String = ""
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
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    case .hoyoSalida:
                        HStack {
                            Stepper(value: $startHole, in: 1...18) {
                                Text("Hoyo \(startHole)")
                            }
                        }
                    case .jugadores:
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Nombre jugador", text: $newPlayerName)
                                    .textInputAutocapitalization(.words)
                                Button("Agregar") {
                                    addPlayerName()
                                }
                                .disabled(newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || playerNames.count >= 5)
                            }
                            if playerNames.isEmpty {
                                Text("Agrega hasta 5 jugadores (incluyéndote).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        ForEach(playerNames.indices, id: \.self) { idx in
                            HStack {
                                Text("\(playerAliases[idx].alias) (\(playerAliases[idx].name))")
                                Spacer()
                                Button("Eliminar") {
                                    playerNames.remove(at: idx)
                                    syncStrokes()
                                    syncBaseDefaults()
                                }
                                .foregroundColor(.red)
                            }
                        }
                    case .strokes:
                        if playerAliases.isEmpty {
                            Text("Primero agrega jugadores.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(playerAliases, id: \.alias) { p in
                                if p.alias == matchManager.yoAlias {
                                    HStack {
                                        Text("\(p.alias) (YO)")
                                        Spacer()
                                        Text("0")
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Stepper(
                                        value: Binding(
                                            get: { strokesByAlias[p.alias] ?? 0 },
                                            set: { strokesByAlias[p.alias] = $0 }
                                        ),
                                        in: -20...20
                                    ) {
                                        let v = strokesByAlias[p.alias] ?? 0
                                        Text("\(p.alias) \(v >= 0 ? "+" : "")\(v)")
                                    }
                                }
                            }
                        }
                    case .parejas:
                        if playerAliases.count < 4 {
                            Text("Se necesitan al menos 4 jugadores.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Selecciona tu base (2 jugadores)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                WrapGrid(items: playerAliases.map { $0.alias }) { alias in
                                    Button(action: { toggleBase(alias) }) {
                                        Text(alias)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(isBase(alias) ? Color.green.opacity(0.2) : Color(.secondarySystemBackground))
                                            .cornerRadius(8)
                                    }
                                }
                                if base1.isEmpty || base2.isEmpty || base1 == base2 {
                                    Text("Selecciona 2 jugadores distintos.")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                let opp = opponentsForBase()
                                Text("Oponentes: \(opp.isEmpty ? "—" : opp.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                let lanes = buildLocalLanes()
                                if !lanes.isEmpty {
                                    Text("Parejas generadas:")
                                        .font(.caption.bold())
                                    ForEach(lanes, id: \.id) { lane in
                                        Text("\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    case .strokesParejas:
                        let lanes = buildLocalLanes()
                        if lanes.isEmpty {
                            Text("Define primero las parejas.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("El stroke de pareja es positivo y aplica para toda la vuelta (18 hoyos).")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            ForEach(lanes, id: \.id) { lane in
                                let key = lane.id
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))")
                                        .font(.caption.bold())
                                    HStack(spacing: 12) {
                                        Stepper(
                                            value: Binding(
                                                get: { max(0, laneStrokes[key] ?? 0) },
                                                set: { laneStrokes[key] = max(0, $0) }
                                            ),
                                            in: 0...20
                                        ) {
                                            Text("Strokes: \(laneStrokes[key] ?? 0)")
                                                .font(.caption)
                                        }
                                        Spacer()
                                        Menu {
                                            Button("Sin asignar") {
                                                laneCarrierByMatch.removeValue(forKey: key)
                                            }
                                            ForEach(lane.base + lane.opp, id: \.self) { alias in
                                                Button(alias) {
                                                    laneCarrierByMatch[key] = alias
                                                }
                                            }
                                        } label: {
                                            Text(laneCarrierByMatch[key] ?? "Quién los lleva")
                                                .font(.caption)
                                                .foregroundColor(.primary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.secondarySystemBackground))
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                        }
                    case .apuestas:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Valor")
                                .font(.caption.bold())
                            TextField("Valor vuelta", text: $vueltaValueText)
                                .keyboardType(.numberPad)
                            Text("Unidad: \(unitValueFromText())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Regla: unidad = mitad del valor de la vuelta")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("Presión", text: $presionValueText)
                                .keyboardType(.numberPad)
                            TextField("Match", text: $matchValueText)
                                .keyboardType(.numberPad)
                            TextField("Carry B9", text: $carryB9ValueText)
                                .keyboardType(.numberPad)
                            TextField("Presión B9", text: $presionB9ValueText)
                                .keyboardType(.numberPad)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apuestas individuales")
                                .font(.caption.bold())
                            ForEach(matchManager.betCatalog.filter { $0.type == .individual }) { bet in
                                betRow(bet)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apuestas por parejas")
                                .font(.caption.bold())
                            ForEach(matchManager.betCatalog.filter { $0.type == .parejas }) { bet in
                                betRow(bet)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Setup guiado")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadDefaults()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Atrás") {
                        stepIndex = max(0, stepIndex - 1)
                    }
                    .disabled(stepIndex == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(stepIndex == Step.allCases.count - 1 ? "Guardar" : "Siguiente") {
                        if stepIndex == Step.allCases.count - 1 {
                            applySetup()
                            dismiss()
                        } else {
                            stepIndex = min(Step.allCases.count - 1, stepIndex + 1)
                        }
                    }
                    .disabled(!canAdvance())
                }
            }
        }
    }

    private var playerAliases: [(alias: String, name: String)] {
        buildAliases(from: playerNames)
    }

    private func loadDefaults() {
        if !selectedCourseId.isEmpty { return }
        selectedCourseId = matchManager.courseId.isEmpty ? CourseCatalog.default.id : matchManager.courseId
        startHole = matchManager.startHole
        playerNames = matchManager.players.map { $0.name }
        if playerNames.isEmpty {
            playerNames = ["Daniel"]
        }
        syncStrokes()
        if let first = playerAliases.first?.alias {
            base1 = first
        }
        if playerAliases.count > 1 {
            base2 = playerAliases[1].alias
        }
        vueltaValueText = matchManager.vueltaValue > 0 ? "\(matchManager.vueltaValue)" : ""
        presionValueText = matchManager.presionValue > 0 ? "\(matchManager.presionValue)" : ""
        matchValueText = matchManager.matchValue > 0 ? "\(matchManager.matchValue)" : ""
        carryB9ValueText = matchManager.carryB9Value > 0 ? "\(matchManager.carryB9Value)" : ""
        presionB9ValueText = matchManager.presionB9Value > 0 ? "\(matchManager.presionB9Value)" : ""
        selectedBetIds = Set(matchManager.activeBets.map { $0.definition.id })
        for bet in matchManager.activeBets {
            if let tag = bet.tagOverride {
                betTagOverrides[bet.definition.id] = tag
            }
        }
        for lane in matchManager.lanes {
            let key = laneKey(base: lane.base, opp: lane.opp)
            laneStrokes[key] = max(0, lane.strokes)
            if let carrier = lane.strokeCarrier {
                laneCarrierByMatch[key] = carrier
            }
        }
    }

    private func addPlayerName() {
        let clean = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, playerNames.count < 5 else { return }
        playerNames.append(clean)
        newPlayerName = ""
        syncStrokes()
        syncBaseDefaults()
    }

    private func syncStrokes() {
        let aliases = playerAliases.map { $0.alias }
        for a in aliases where strokesByAlias[a] == nil {
            strokesByAlias[a] = 0
        }
        for key in strokesByAlias.keys where !aliases.contains(key) {
            strokesByAlias.removeValue(forKey: key)
        }
    }

    private func syncBaseDefaults() {
        if base1.isEmpty, let first = playerAliases.first?.alias {
            base1 = first
        }
        if base2.isEmpty, playerAliases.count > 1 {
            base2 = playerAliases[1].alias
        }
    }

    private func opponentsForBase() -> [String] {
        let base = [base1, base2].filter { !$0.isEmpty }
        let all = playerAliases.map { $0.alias }
        return all.filter { !base.contains($0) }
    }

    private func buildLocalLanes() -> [LocalLane] {
        let base = [base1, base2].filter { !$0.isEmpty }
        let all = playerAliases.map { $0.alias }
        if base.count < 2 { return [] }
        let opp = all.filter { !base.contains($0) }
        if opp.count == 2 {
            return [LocalLane(base: base, opp: opp)]
        }
        if opp.count == 3 {
            let combos = [
                [opp[0], opp[1]],
                [opp[0], opp[2]],
                [opp[1], opp[2]]
            ]
            return combos.map { LocalLane(base: base, opp: $0) }
        }
        if base.count == 3 && opp.count == 2 {
            return [LocalLane(base: base, opp: opp)]
        }
        return []
    }

    private func laneKey(base: [String], opp: [String]) -> String {
        (base.sorted() + ["vs"] + opp.sorted()).joined(separator: "-")
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
                set: { on in
                    if on { selectedBetIds.insert(bet.id) } else { selectedBetIds.remove(bet.id) }
                }
            )) {
                Text("\(bet.name) · \(bet.units)u · \(bet.mode == .calculado ? "calc" : "manual")")
            }
            if isOn {
                TextField("Tag (default \(bet.tag)-ALIAS)", text: Binding(
                    get: { betTagOverrides[bet.id] ?? "" },
                    set: { betTagOverrides[bet.id] = $0 }
                ))
                .textInputAutocapitalization(.characters)
            }
        }
    }

    private func canAdvance() -> Bool {
        switch step {
        case .campo:
            return !selectedCourseId.isEmpty
        case .hoyoSalida:
            return startHole >= 1 && startHole <= 18
        case .jugadores:
            return playerNames.count >= 2 && playerNames.count <= 5
        case .strokes:
            return !playerAliases.isEmpty
        case .parejas:
            return playerAliases.count < 4 || (base1 != base2 && !base1.isEmpty && !base2.isEmpty)
        case .strokesParejas:
            return true
        case .apuestas:
            return true
        }
    }

    private func applySetup() {
        if let course = CourseCatalog.all.first(where: { $0.id == selectedCourseId }) {
            matchManager.setCourse(course)
        }
        matchManager.updateStartHole(startHole)
        matchManager.setPlayers(names: playerNames)
        for p in matchManager.players {
            let v = strokesByAlias[p.alias] ?? 0
            matchManager.setStrokesVsBase(alias: p.alias, value: v)
        }
        let base = [base1, base2].filter { !$0.isEmpty }
        if base.count >= 2 {
            let opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
            _ = matchManager.setBaseTeam(base, opponentsOverride: opp)
            let lanes = buildLocalLanes()
            for lane in lanes {
                let key = lane.id
                let v = max(0, laneStrokes[key] ?? 0)
                matchManager.setLaneStrokesForMatch(base: lane.base, opp: lane.opp, value: v)
                matchManager.setLaneCarrierForMatch(base: lane.base, opp: lane.opp, carrier: laneCarrierByMatch[key])
            }
        }
        if let v = Int(vueltaValueText) {
            matchManager.setVueltaValue(v)
        }
        if let v = Int(presionValueText) {
            matchManager.setPresionValue(v)
        }
        if let v = Int(matchValueText) {
            matchManager.setMatchValue(v)
        }
        if let v = Int(carryB9ValueText) {
            matchManager.setCarryB9Value(v)
        }
        if let v = Int(presionB9ValueText) {
            matchManager.setPresionB9Value(v)
        }
        let active = matchManager.betCatalog
            .filter { selectedBetIds.contains($0.id) }
            .map { def in
                ActiveBet(definition: def, tagOverride: tagOverridesValue(for: def.id))
            }
        matchManager.setActiveBets(active)
    }

    private func tagOverridesValue(for id: UUID) -> String? {
        guard let raw = betTagOverrides[id]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    private func isBase(_ alias: String) -> Bool {
        return alias == base1 || alias == base2
    }

    private func toggleBase(_ alias: String) {
        if base1 == alias {
            base1 = ""
            return
        }
        if base2 == alias {
            base2 = ""
            return
        }
        if base1.isEmpty {
            base1 = alias
        } else if base2.isEmpty {
            base2 = alias
        } else {
            base1 = alias
            base2 = ""
        }
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
        let base = String(letters.prefix(3))
        var alias = base
        var counter = 1
        while existing.contains(alias) {
            alias = base + String(counter)
            counter += 1
        }
        return alias
    }

    private struct LocalLane: Identifiable {
        let id: String
        let base: [String]
        let opp: [String]

        init(base: [String], opp: [String]) {
            self.base = base
            self.opp = opp
            self.id = (base.sorted() + ["vs"] + opp.sorted()).joined(separator: "-")
        }
    }
}
```

## Setup Parsing Helpers (matchCourse..before containsNoiseDictation)

```swift


    private func matchCourse(in text: String) -> CourseModel? {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        for course in CourseCatalog.all {
            let id = course.id.lowercased()
            let name = matchManager.normalizePlayerKey(course.name).lowercased()
            if normalized.contains(id) || (!name.isEmpty && normalized.contains(name)) {
                return course
            }
        }
        return nil
    }

    private func dedupeNames(_ names: [String]) -> (unique: [String], duplicates: [String], existing: [String]) {
        var seen = Set<String>()
        var unique: [String] = []
        var duplicates: [String] = []
        var existing: [String] = []
        for name in names {
            let key = matchManager.normalizePlayerKey(name).lowercased()
            if seen.contains(key) {
                duplicates.append(name)
                continue
            }
            seen.insert(key)
            if matchManager.normalizeAlias(name) != nil {
                existing.append(name)
                continue
            }
            unique.append(name)
        }
        return (unique, duplicates, existing)
    }

    private func unknownNames(in text: String) -> [String] {
        let candidates = extractNamesFromText(text)
        if candidates.isEmpty { return [] }
        var unknown: [String] = []
        for c in candidates {
            if matchManager.normalizeAlias(c) == nil && aliasesMatchedByName(c).isEmpty {
                unknown.append(c)
            }
        }
        return unknown
    }

    private func strictUnknownNamesSetup(in text: String) -> [String] {
        let candidates = extractNamesFromText(text)
        if candidates.isEmpty { return [] }
        var unknown: [String] = []
        for c in candidates {
            if matchManager.normalizeAlias(c) == nil && aliasesMatchedByName(c).isEmpty {
                unknown.append(c)
            }
        }
        return unknown
    }

    private func invalidNamesMessageSetup(_ names: [String]) -> String {
        let valid = matchManager.players.map { "\($0.alias) (\($0.name))" }.joined(separator: ", ")
        let unknown = names.joined(separator: ", ")
        return "❌ Jugador no parte de este match: \(unknown). Válidos: \(valid)."
    }

    private func suggestionMessage(for names: [String]) -> String {
        var suggestions: [String] = []
        for name in names {
            let candidates = matchManager.fuzzyCandidates(for: name, limit: 2)
            if let best = candidates.first {
                suggestions.append("¿Quisiste decir \(best.alias)?")
            } else {
                suggestions.append("Nombre no válido: \(name)")
            }
        }
        return "❌ " + suggestions.joined(separator: " ")
    }

    private func parseStrokeUpdatesSetup(_ text: String) -> [(alias: String, value: Int)] {
        let separators = [",", ";", " y ", " e "]
        var parts: [String] = [text]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        var updates: [(alias: String, value: Int)] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = parseStrokeUpdateSetup(trimmed) {
                updates.append(u)
            }
        }
        return updates
    }

    private func parseStrokeUpdateSetup(_ text: String) -> (alias: String, value: Int)? {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let num = extractFirstNumber(from: text) else { return nil }
        let hasReceive = hasWord(t, "recibe") || hasWord(t, "recibo") || hasWord(t, "recibes") || hasWord(t, "reciben") ||
            t.contains("le dan") || t.contains("le da") ||
            hasWord(t, "tengo") || hasWord(t, "tiene") || hasWord(t, "tienen") ||
            hasWord(t, "lleva") || hasWord(t, "llevo") || hasWord(t, "llevan")
        let hasGive = hasWord(t, "da") || hasWord(t, "doy") || hasWord(t, "das") || hasWord(t, "dame") || hasWord(t, "dan") || hasWord(t, "damos")
        let hasSpeakerGive = hasWord(t, "doy") || hasWord(t, "damos")
        let hasMeDa = t.contains("me da") || t.contains("me dan")
        let hasToCue = t.contains(" a ") || t.contains(" para ")
        if !hasReceive && !hasGive { return nil }
        var aliases = aliasesMatchedByName(text)
        if aliases.isEmpty {
            aliases = extractAliasesFromText(text)
        }
        if aliases.isEmpty { return nil }
        let named = aliases.filter { $0 != matchManager.yoAlias }
        let target = named.first ?? aliases.first!

        // Examples:
        // "Anselmo doy 5" -> Anselmo +5 (yo doy, él recibe)
        // "Roberto me da 10" -> Roberto -10 (él da, yo recibo)
        if hasSpeakerGive {
            return (target, num)
        }
        if hasMeDa {
            return (target, -num)
        }
        let receiverMode = hasReceive || hasToCue
        let value = receiverMode ? num : -num
        return (target, value)
    }

    private func applyPairsFromText(_ text: String) -> (ok: Bool, message: String?) {
        let trimmed = stripStrokeClause(text)
        let unknown = strictUnknownNamesSetup(in: trimmed)
        if !unknown.isEmpty { return (false, invalidNamesMessageSetup(unknown)) }
        if let split = splitMatchup(trimmed) {
            var base = extractAliasesPreferNames(split.left)
            let opp = extractAliasesPreferNames(split.right)
            let t = matchManager.normalizePlayerKey(split.left).lowercased()
            if t.contains("yo") || t.contains("mi") || t.contains("mis") {
                if !base.contains(matchManager.yoAlias) { base.insert(matchManager.yoAlias, at: 0) }
            }
            if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
            if !disjointTeams(base, opp) { return (false, "❌ Un jugador aparece en ambos lados.") }
            return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil)
        }
        let ordered = orderedAliasesFromText(trimmed)
        if ordered.count == 4 {
            let base = Array(ordered.prefix(2))
            let opp = Array(ordered.suffix(2))
            if disjointTeams(base, opp) {
                return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil)
            }
        }
        var base: [String] = []
        var opp: [String] = []
        if let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcompañeros?\b\s*(son|es|:)?\s*"#) {
            base = extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcompaneros?\b\s*(son|es|:)?\s*"#) {
            base = extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcon\b"#) {
            base = extractAliasesPreferNames(after)
        }
        if let oppAfter = substringAfterPattern(trimmed, pattern: #"(?i)\boponentes?\b\s*(son|es|:)?\s*"#) {
            opp = extractAliasesPreferNames(oppAfter)
        }
        let t = matchManager.normalizePlayerKey(trimmed).lowercased()
        if (t.contains("yo") || t.contains("mi") || t.contains("mis")) && !base.contains(matchManager.yoAlias) {
            base.insert(matchManager.yoAlias, at: 0)
        }
        if base.isEmpty {
            base = extractAliasesPreferNames(trimmed)
        }
        if opp.isEmpty {
            opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
        }
        if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
        if !disjointTeams(base, opp) { return (false, "❌ Un jugador aparece en ambos lados.") }
        return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil)
    }

    private func applyLaneStrokesFromText(_ text: String) -> (ok: Bool, message: String?) {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        let unknown = strictUnknownNamesSetup(in: text)
        if !unknown.isEmpty { return (false, invalidNamesMessageSetup(unknown)) }
        if let split = splitMatchup(text) {
            let base = extractAliasesPreferNames(split.left)
            let opp = extractAliasesPreferNames(split.right)
            if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
            let applied = applyCarrierFromText(text, base: base, opp: opp)
            return applied
                ? (true, nil)
                : (false, "❌ Indica quién los lleva o cuántos strokes de pareja.")
        }
        if matchManager.lanes.count == 1 {
            let lane = matchManager.lanes[0]
            let applied = applyCarrierFromText(text, base: lane.base, opp: lane.opp)
            return applied
                ? (true, nil)
                : (false, "❌ Indica quién los lleva o cuántos strokes de pareja.")
        }
        if t.contains("lleva") || t.contains("llev") {
            if matchManager.lanes.count > 1 {
                return (false, "❌ Especifica el enfrentamiento: BASE contra OPP.")
            }
            if let carrier = extractAliasesPreferNames(text).first, matchManager.lanes.count == 1 {
                let lane = matchManager.lanes[0]
                matchManager.setLaneCarrierForMatch(base: lane.base, opp: lane.opp, carrier: carrier)
                return (true, nil)
            }
        }
        return (false, "❌ No entendí strokes de pareja.")
    }

    private func disjointTeams(_ a: [String], _ b: [String]) -> Bool {
        let sa = Set(a)
        let sb = Set(b)
        return sa.intersection(sb).isEmpty
    }

    private func orderedAliasesFromText(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        var hits: [(alias: String, idx: Int)] = []
        for p in matchManager.players {
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey),
               let range = normalized.range(of: aliasKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
            }
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if !nameKey.isEmpty, let range = normalized.range(of: nameKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
            }
        }
        let sorted = hits.sorted { $0.idx < $1.idx }
        var seen = Set<String>()
        var out: [String] = []
        for hit in sorted {
            if seen.contains(hit.alias) { continue }
            seen.insert(hit.alias)
            out.append(hit.alias)
        }
        return out
    }

    private func applyCarrierFromText(_ text: String, base: [String]?, opp: [String]?) -> Bool {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let b = base, let o = opp, !b.isEmpty, !o.isEmpty else { return false }
        let orderedAliases = orderedAliasesFromText(text)
        let receiverWords = ["recibe","recibo","reciben","recibir","lleva","llevo","llevas","llevan"]
        let giverWords = ["da","doy","das","dan","damos"]
        let receiverMode = hasAnyWord(t, receiverWords) ||
            t.contains("le dan") || t.contains("les dan") || t.contains("nos dan") ||
            t.contains("le llevan") || t.contains("les llevan") || t.contains("nos llevan")
        let giverMode = !receiverMode && (hasAnyWord(t, giverWords) || t.contains("le da") || t.contains("les da") || t.contains("nos da"))

        var applied = false
        var carrier: String? = nil
        if receiverMode {
            carrier = orderedAliases.last
            if carrier == nil, t.contains("nos") || t.contains("nosotros") {
                carrier = b.contains(matchManager.yoAlias) ? matchManager.yoAlias : b.first
            }
        } else if giverMode {
            if let giver = orderedAliases.last {
                if b.contains(giver) {
                    carrier = o.contains(matchManager.yoAlias) ? matchManager.yoAlias : o.first
                } else if o.contains(giver) {
                    carrier = b.contains(matchManager.yoAlias) ? matchManager.yoAlias : b.first
                }
            }
        } else if t.contains("lleva") || t.contains("llev") {
            carrier = orderedAliases.last
        }

        if let carrier = carrier {
            matchManager.setLaneCarrierForMatch(base: b, opp: o, carrier: carrier)
            applied = true
        }

        if let strokes = extractFirstNumber(from: text) {
            let hasStrokeWord = t.contains("stroke") || t.contains("strokes") || t.contains("golpe") || t.contains("golpes")
            if receiverMode || giverMode || hasStrokeWord || t.contains("lleva") || t.contains("llev") {
                matchManager.setLaneStrokesForMatch(base: b, opp: o, value: strokes)
                applied = true
            }
        }
        return applied
    }

    private func hasAnyWord(_ text: String, _ words: [String]) -> Bool {
        for w in words {
            if hasWord(text, w) { return true }
        }
        return false
    }

    private func extractAliasesFromText(_ text: String) -> [String] {
        var result: [String] = []
        let t = matchManager.normalizePlayerKey(text).lowercased()
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey) && containsWholePhrase(t, phrase: aliasKey) {
                result.append(p.alias)
            }
            if !nameKey.isEmpty && containsWholePhrase(t, phrase: nameKey) {
                result.append(p.alias)
            }
        }
        let tokens = t.split(separator: " ").map { String($0) }
        for token in tokens {
            if matchManager.isAmbiguousAliasToken(token) { continue }
            if let a = matchManager.normalizeAlias(token) {
                result.append(a)
            }
        }
        if t.contains("yo") {
            result.append(matchManager.yoAlias)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private func extractAliasesPreferNames(_ text: String) -> [String] {
        let byName = aliasesMatchedByName(text)
        if !byName.isEmpty { return byName }
        return extractAliasesFromText(text)
    }

    private func aliasesMatchedByName(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        if normalized.isEmpty { return [] }
        var hits: [String] = []
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if nameKey.isEmpty { continue }
            if containsWholePhrase(normalized, phrase: nameKey) {
                hits.append(p.alias)
            }
        }
        if !hits.isEmpty {
            var seen = Set<String>()
            return hits.filter { seen.insert($0).inserted }
        }
        let uniqueFirst = uniqueFirstNameMap()
        let tokens = normalized.split(separator: " ").map { String($0) }
        for token in tokens {
            if let alias = uniqueFirst[token] {
                hits.append(alias)
            }
        }
        var seen = Set<String>()
        return hits.filter { seen.insert($0).inserted }
    }

    private func uniqueFirstNameMap() -> [String: String] {
        var buckets: [String: [String]] = [:]
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            guard let first = nameKey.split(separator: " ").first.map(String.init),
                  !first.isEmpty else { continue }
            buckets[first, default: []].append(p.alias)
        }
        var unique: [String: String] = [:]
        for (first, aliases) in buckets where aliases.count == 1 {
            unique[first] = aliases[0]
        }
        return unique
    }

    private func containsWholePhrase(_ text: String, phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)\b\#(escaped)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func extractNamesFromText(_ text: String) -> [String] {
        let lower = matchManager.normalizePlayerKey(text).lowercased()
        let hasListCue = lower.contains("juegan") || lower.contains("juega") ||
            lower.contains("jugadores") || lower.contains("son") || lower.contains("somos") ||
            lower.contains("jugamos") || lower.contains("agrego") || lower.contains("agrega") ||
            lower.contains("agregar") || lower.contains("añado") || lower.contains("añade")
        let proper = properNames(from: text)
        if proper.count >= 2 {
            return proper
        }
        if proper.count == 1, hasListCue || text.contains(",") || text.contains(";") || lower.contains(" y ") || lower.contains(" e ") {
            let list = extractNamesFromList(text)
            return list.isEmpty ? proper : list
        }
        let list = extractNamesFromList(text)
        if !list.isEmpty { return list }
        return proper
    }

    private func extractNamesFromList(_ text: String) -> [String] {
        var cleaned = text
        let removePattern = #"(?i)\b(agrega|agregar|agrego|agregue|agregué|agregamos|agregan|añade|añadir|añado|nuevo|jugador|jugadores|soy|somos|compañero|compañeros|companero|companeros|mi|mis|yo|base|contra|vs|versus|pareja|juegan|jugamos|los|lleva|llevo|llevas|llevan|strokes|golpes|recibe|recibo|da|doy|subtitulo|subtitulos|subtítulos|realizado|realizados|comunidad|amara|org|caption|subtitles|de|del|la|el|los|las|por|para|muy)\b"#
        cleaned = cleaned.replacingOccurrences(of: removePattern, with: " ", options: .regularExpression)
        let separators = [" y ", " e ", ",", ";", "&", "+", " con "]
        for s in separators {
            cleaned = cleaned.replacingOccurrences(of: s, with: ",")
        }
        let parts = cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return [] }
        var out: [String] = []
        for part in parts {
            let tokens = part.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            var i = 0
            while i < tokens.count {
                let t = tokens[i]
                if i + 1 < tokens.count,
                   isCompoundNamePair(first: t, second: tokens[i + 1]) {
                    let combined = "\(t) \(tokens[i + 1])"
                    if isValidPlayerName(combined) {
                        out.append(combined)
                        i += 2
                        continue
                    }
                }
                if isValidPlayerName(t) {
                    out.append(t)
                }
                i += 1
            }
        }
        return out
    }

    private func properNames(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: [String] = []
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if tag == .personalName {
                let name = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidPlayerName(name) {
                    names.append(name)
                }
            }
            return true
        }
        return names
    }

    private func isCompoundNamePair(first: String, second: String) -> Bool {
        let f = matchManager.normalizePlayerKey(first).lowercased()
        let s = matchManager.normalizePlayerKey(second).lowercased()
        return compoundNamePairs.contains("\(f) \(s)")
    }

    private var compoundNamePairs: Set<String> {
        return [
            "juan carlos",
            "juan pablo",
            "juan manuel",
            "juan jose",
            "juan luis",
            "juan diego",
            "jose luis",
            "jose maria",
            "jose manuel",
            "jose antonio",
            "maria jose",
            "maria carmen",
            "maria fernanda",
            "maria angeles",
            "ana maria",
            "ana sofia"
        ]
    }

    private func isValidPlayerName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let lower = matchManager.normalizePlayerKey(trimmed).lowercased()
        if containsNoiseDictation(lower) { return false }
        if trimmed.count > 30 { return false }
        let tokens = lower.split(separator: " ").map { String($0) }
        if tokens.isEmpty || tokens.count > 3 { return false }
        if tokens.contains(where: { bannedNameTokens.contains($0) }) { return false }
        if tokens.contains(where: { $0.count < 2 }) { return false }
        if trimmed.range(of: #"\d"#, options: .regularExpression) != nil { return false }
        let letters = trimmed.filter { $0.isLetter }
        if letters.isEmpty { return false }
        return true
    }

    private var bannedNameTokens: Set<String> {
        return [
            "el","la","los","las","un","una","unos","unas","de","del","al","por","para","con","sin","y","e","o","u",
            "yo","mi","mis","mio","mia","tu","tus","su","sus","nosotros","ustedes",
            "soy","somos","ser","estar","estoy","estas","esta","estan","juego","juega","juegan","jugamos","jugar",
            "companero","companeros","compañero","compañeros","pareja","parejas",
            "contra","vs","versus",
            "recibe","recibo","recibes","da","doy","das","dame",
            "lleva","llevo","llevas","llevan","strokes","golpe","golpes",
            "muy","bueno","malo","grande","pequeno","pequeño","nuevo","viejo","ultimo","último","primer","primero",
            "subtitulo","subtitulos","subtítulos","caption","subtitles","amara","org",
            "agrega","agregar","agrego","agregue","agregué","agregamos","agregan","añade","añadir","añado",
            "dictado","transcribe","transcribir","nombres","propios","numeros","precisión","precision",
            "palabras","clave","inventes","texto","golf"
        ]
    }
```

## Setup Voice Helpers (handleSetupTranscript..before containsNoiseDictation)

```swift


    private func handleSetupTranscript(_ transcript: String) async -> Bool {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }
        let t = matchManager.normalizePlayerKey(text).lowercased()
        if containsNoiseDictation(t) {
            await MainActor.run {
                statusMessage = "❌ No entendí. Repite."
            }
            return true
        }

        let hasHoleMention = MatchInterpreter.extractHole(from: t) != nil || hasWord(t, "hoyo") || hasWord(t, "oyo")
        let isStartCue = t.contains("salida") || t.contains("inicio") || t.contains("iniciamos") || t.contains("empezamos") || t.contains("arrancamos")
        if isStartCue, let h = MatchInterpreter.extractHole(from: t) {
            await MainActor.run {
                matchManager.updateStartHole(h)
                statusMessage = "✅ Hoyo de salida: \(h)"
            }
            return true
        }

        if t.contains("campo") || t.contains("cgm") {
            await MainActor.run {
                matchManager.setCourse(CourseCatalog.cgm)
                statusMessage = "✅ Campo: CGM"
            }
            return true
        }

        let baseCues = t.contains("companero") || t.contains("companeros") ||
            t.contains("compañero") || t.contains("compañeros") ||
            t.contains("oponente") || t.contains("oponentes") ||
            t.contains("pareja") || t.contains("parejas") ||
            t.contains("contra") || t.contains("vs") || t.contains("versus") ||
            hasWord(t, "con")

        if baseCues && !hasHoleMention {
            let unknown = strictUnknownNames(in: text)
            if !unknown.isEmpty {
                await MainActor.run {
                    statusMessage = invalidNamesMessage(unknown)
                }
                return true
            }
            let ok = applyBaseFromText(text)
            await MainActor.run {
                statusMessage = ok ? "✅ Parejas actualizadas" : "❌ No entendí parejas. Repite."
            }
            return true
        }

        if !hasHoleMention {
            let updates = parseStrokeUpdatesSetup(text)
            if !updates.isEmpty {
                await MainActor.run {
                    for u in updates {
                        matchManager.setStrokesVsBase(alias: u.alias, value: u.value)
                    }
                    let summary = updates.map { "\($0.alias) \($0.value > 0 ? "+" : "")\($0.value)" }.joined(separator: ", ")
                    statusMessage = "✅ Strokes: \(summary)"
                }
                return true
            }
        }

        let names = extractNamesFromSetupText(text).filter { isValidPlayerName($0) }
        if !names.isEmpty && !hasHoleMention {
            let filtered = await confirmNamesWithLLM(candidates: names, transcript: text)
            let finalNames = filtered.isEmpty ? names : filtered
            if finalNames.isEmpty {
                await MainActor.run {
                    statusMessage = "❌ No entendí el nombre. Repite."
                }
                return true
            }
            await MainActor.run {
                var added: [String] = []
                for name in finalNames {
                    if matchManager.addPlayer(name: name) {
                        added.append(name)
                    }
                }
                if added.isEmpty {
                    statusMessage = matchManager.players.count >= 5 ? "❌ Máximo 5 jugadores" : "❌ No pude agregar jugadores"
                } else {
                    statusMessage = "✅ Agregados: \(added.joined(separator: ", "))"
                }
            }
            return true
        }

        return false
    }

    private func confirmNamesWithLLM(candidates: [String], transcript: String) async -> [String] {
        do {
            let result = try await OpenAIService.shared.confirmPlayerNames(candidates: candidates, transcript: transcript)
            return result.accepted
        } catch {
            return candidates
        }
    }

    private func applyBaseFromText(_ text: String) -> Bool {
        let trimmed = stripStrokeClause(text)
        let unknown = strictUnknownNames(in: trimmed)
        if !unknown.isEmpty { return false }
        if let split = splitMatchup(trimmed) {
            var base = extractAliasesPreferNames(split.left)
            let opp = extractAliasesPreferNames(split.right)
            let t = matchManager.normalizePlayerKey(split.left).lowercased()
            if t.contains("yo") || t.contains("mi") || t.contains("mis") {
                if !base.contains(matchManager.yoAlias) { base.insert(matchManager.yoAlias, at: 0) }
            }
            if base.count < 2 || opp.count < 2 { return false }
            return matchManager.setBaseTeam(base, opponentsOverride: opp)
        }

        let ordered = orderedAliasesFromText(trimmed)
        if ordered.count == 4 {
            let base = Array(ordered.prefix(2))
            let opp = Array(ordered.suffix(2))
            if disjointTeams(base, opp) {
                return matchManager.setBaseTeam(base, opponentsOverride: opp)
            }
        }

        var base: [String] = []
        var opp: [String] = []
        if let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcompañeros?\b\s*(son|es|:)?\s*"#) {
            base = extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcompaneros?\b\s*(son|es|:)?\s*"#) {
            base = extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = substringAfterPattern(trimmed, pattern: #"(?i)\bcon\b"#) {
            base = extractAliasesPreferNames(after)
        }
        if let oppAfter = substringAfterPattern(trimmed, pattern: #"(?i)\boponentes?\b\s*(son|es|:)?\s*"#) {
            opp = extractAliasesPreferNames(oppAfter)
        }
        let t = matchManager.normalizePlayerKey(trimmed).lowercased()
        if (t.contains("yo") || t.contains("mi") || t.contains("mis")) && !base.contains(matchManager.yoAlias) {
            base.insert(matchManager.yoAlias, at: 0)
        }
        if base.isEmpty {
            base = extractAliasesPreferNames(trimmed)
        }
        if opp.isEmpty {
            opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
        }
        if base.count < 2 || opp.count < 2 { return false }
        return matchManager.setBaseTeam(base, opponentsOverride: opp)
    }

    private func disjointTeams(_ a: [String], _ b: [String]) -> Bool {
        let sa = Set(a)
        let sb = Set(b)
        return sa.intersection(sb).isEmpty
    }

    private func parseStrokeUpdatesSetup(_ text: String) -> [(alias: String, value: Int)] {
        let separators = [",", ";", " y ", " e "]
        var parts: [String] = [text]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        var updates: [(alias: String, value: Int)] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = parseStrokeUpdateSetup(trimmed) {
                updates.append(u)
            }
        }
        return updates
    }

    private func parseStrokeUpdateSetup(_ text: String) -> (alias: String, value: Int)? {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let num = extractFirstNumber(from: text) else { return nil }
        let hasReceive = hasWord(t, "recibe") || hasWord(t, "recibo") || hasWord(t, "recibes") || hasWord(t, "reciben") ||
            t.contains("le dan") || t.contains("le da") ||
            hasWord(t, "tengo") || hasWord(t, "tiene") || hasWord(t, "tienen") ||
            hasWord(t, "lleva") || hasWord(t, "llevo") || hasWord(t, "llevan")
        let hasGive = hasWord(t, "da") || hasWord(t, "doy") || hasWord(t, "das") || hasWord(t, "dame") || hasWord(t, "dan") || hasWord(t, "damos")
        let hasSpeakerGive = hasWord(t, "doy") || hasWord(t, "damos")
        let hasMeDa = t.contains("me da") || t.contains("me dan")
        let hasToCue = t.contains(" a ") || t.contains(" para ")
        if !hasReceive && !hasGive { return nil }
        var aliases = aliasesMatchedByName(text)
        if aliases.isEmpty {
            aliases = extractAliasesFromText(text)
        }
        if aliases.isEmpty { return nil }
        let named = aliases.filter { $0 != matchManager.yoAlias }
        let target = named.first ?? aliases.first!

        // Examples:
        // "Anselmo doy 5" -> Anselmo +5 (yo doy, él recibe)
        // "Roberto me da 10" -> Roberto -10 (él da, yo recibo)
        if hasSpeakerGive {
            return (target, num)
        }
        if hasMeDa {
            return (target, -num)
        }
        let receiverMode = hasReceive || hasToCue
        let value = receiverMode ? num : -num
        return (target, value)
    }

    private func extractAliasesFromText(_ text: String) -> [String] {
        var result: [String] = []
        let t = matchManager.normalizePlayerKey(text).lowercased()
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey) && containsWholePhrase(t, phrase: aliasKey) {
                result.append(p.alias)
            }
            if !nameKey.isEmpty && containsWholePhrase(t, phrase: nameKey) {
                result.append(p.alias)
            }
        }
        let tokens = t.split(separator: " ").map { String($0) }
        for token in tokens {
            if matchManager.isAmbiguousAliasToken(token) { continue }
            if let a = matchManager.normalizeAlias(token) {
                result.append(a)
            }
        }
        if t.contains("yo") {
            result.append(matchManager.yoAlias)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    private func extractAliasesPreferNames(_ text: String) -> [String] {
        let byName = aliasesMatchedByName(text)
        if !byName.isEmpty { return byName }
        return extractAliasesFromText(text)
    }

    private func aliasesMatchedByName(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        if normalized.isEmpty { return [] }
        var hits: [String] = []
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if nameKey.isEmpty { continue }
            if containsWholePhrase(normalized, phrase: nameKey) {
                hits.append(p.alias)
            }
        }
        if !hits.isEmpty {
            var seen = Set<String>()
            return hits.filter { seen.insert($0).inserted }
        }
        let uniqueFirst = uniqueFirstNameMap()
        let tokens = normalized.split(separator: " ").map { String($0) }
        for token in tokens {
            if let alias = uniqueFirst[token] {
                hits.append(alias)
            }
        }
        var seen = Set<String>()
        return hits.filter { seen.insert($0).inserted }
    }

    private func uniqueFirstNameMap() -> [String: String] {
        var buckets: [String: [String]] = [:]
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            guard let first = nameKey.split(separator: " ").first.map(String.init),
                  !first.isEmpty else { continue }
            buckets[first, default: []].append(p.alias)
        }
        var unique: [String: String] = [:]
        for (first, aliases) in buckets where aliases.count == 1 {
            unique[first] = aliases[0]
        }
        return unique
    }

    private func containsWholePhrase(_ text: String, phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)\b\#(escaped)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private func orderedAliasesFromText(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        var hits: [(alias: String, idx: Int)] = []
        for p in matchManager.players {
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey),
               let range = normalized.range(of: aliasKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
            }
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if !nameKey.isEmpty, let range = normalized.range(of: nameKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: range.lowerBound)))
            }
        }
        let sorted = hits.sorted { $0.idx < $1.idx }
        var seen = Set<String>()
        var out: [String] = []
        for hit in sorted {
            if seen.contains(hit.alias) { continue }
            seen.insert(hit.alias)
            out.append(hit.alias)
        }
        return out
    }

    private func strictUnknownNames(in text: String) -> [String] {
        let candidates = extractNamesFromSetupText(text)
        if candidates.isEmpty { return [] }
        var unknown: [String] = []
        for c in candidates {
            if matchManager.normalizeAlias(c) == nil && aliasesMatchedByName(c).isEmpty {
                unknown.append(c)
            }
        }
        return unknown
    }

    private func invalidNamesMessage(_ names: [String]) -> String {
        let valid = matchManager.players.map { "\($0.alias) (\($0.name))" }.joined(separator: ", ")
        let unknown = names.joined(separator: ", ")
        return "❌ Jugador no parte de este match: \(unknown). Válidos: \(valid)."
    }

    private func extractNamesFromSetupText(_ text: String) -> [String] {
        let lower = matchManager.normalizePlayerKey(text).lowercased()
        let hasListCue = lower.contains("juegan") || lower.contains("juega") ||
            lower.contains("jugadores") || lower.contains("son") || lower.contains("somos") ||
            lower.contains("jugamos") || lower.contains("agrego") || lower.contains("agrega") ||
            lower.contains("agregar") || lower.contains("añado") || lower.contains("añade")
        let listNames = extractNamesFromList(text)
        if hasListCue && listNames.count >= 2 {
            return listNames
        }
        return extractNamesFromList(text)
    }

    private func extractNamesFromList(_ text: String) -> [String] {
        var cleaned = text
        let removePattern = #"(?i)\b(agrega|agregar|agrego|agregue|agregué|agregamos|agregan|añade|añadir|añado|nuevo|jugador|jugadores|soy|somos|compañero|compañeros|companero|companeros|mi|mis|yo|base|contra|vs|versus|pareja|juegan|jugamos|los|lleva|llevo|llevas|llevan|strokes|golpes|recibe|recibo|da|doy|subtitulo|subtitulos|subtítulos|realizado|realizados|comunidad|amara|org|caption|subtitles|de|del|la|el|los|las|por|para|muy)\b"#
        cleaned = cleaned.replacingOccurrences(of: removePattern, with: " ", options: .regularExpression)
        let separators = [" y ", " e ", ",", ";", "&", "+", " con "]
        for s in separators {
            cleaned = cleaned.replacingOccurrences(of: s, with: ",")
        }
        let parts = cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return [] }
        var out: [String] = []
        for part in parts {
            let tokens = part.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            var i = 0
            while i < tokens.count {
                let t = tokens[i]
                if i + 1 < tokens.count,
                   isCompoundNamePair(first: t, second: tokens[i + 1]) {
                    let combined = "\(t) \(tokens[i + 1])"
                    if isValidPlayerName(combined) {
                        out.append(combined)
                        i += 2
                        continue
                    }
                }
                if isValidPlayerName(t) {
                    out.append(t)
                }
                i += 1
            }
        }
        return out
    }

    private func isCompoundNamePair(first: String, second: String) -> Bool {
        let f = matchManager.normalizePlayerKey(first).lowercased()
        let s = matchManager.normalizePlayerKey(second).lowercased()
        return compoundNamePairs.contains("\(f) \(s)")
    }

    private var compoundNamePairs: Set<String> {
        return [
            "juan carlos",
            "juan pablo",
            "juan manuel",
            "juan jose",
            "juan luis",
            "juan diego",
            "jose luis",
            "jose maria",
            "jose manuel",
            "jose antonio",
            "maria jose",
            "maria carmen",
            "maria fernanda",
            "maria angeles",
            "ana maria",
            "ana sofia"
        ]
    }
```

