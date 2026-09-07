import SwiftUI
import AVFoundation
import Combine
import NaturalLanguage

struct ContentView: View {
    @StateObject private var voiceRecorder = VoiceRecorder()
    @StateObject private var matchManager = MatchManager()
    @State private var isProcessing = false
    @State private var statusMessage = ""
    @State private var pendingEntities: ScoreEntities?
    @State private var pendingTranscript: String?
    @State private var showPuttsDetail = false
    @State private var pendingAudioFilename: String?
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showBetZoom = false
    @State private var showMoneyTracker = false
    @State private var currentHole: Int?
    @State private var lastConfirmedEntities: ScoreEntities?
    @State private var lastConfirmedTranscript: String?
    @State private var showCoursePicker = false
    @State private var showStartHolePicker = false
    @State private var showGuidedSetup = false
    @State private var pendingOverwrite = false
    @State private var pendingTranscriptToParse: String?
    @State private var editableTranscript = ""
    @State private var showFuzzyReview = false
    @State private var fuzzyReviewScores: [ReviewScore] = []
    @State private var fuzzyReviewHole: Int?
    @State private var fuzzyReviewTranscript: String = ""
    
    private let appleConfidenceThreshold = 0.55
    private let appBgTop = Color(red: 0.03, green: 0.12, blue: 0.08)
    private let appBgBottom = Color(red: 0.02, green: 0.08, blue: 0.06)
    private var isV2TFocusMode: Bool {
        voiceRecorder.isRecording || isProcessing || pendingTranscriptToParse != nil || pendingEntities != nil
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 6) {
                headerView
                
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 8) {
                            if pendingTranscriptToParse != nil {
                                transcriptConfirmView
                                    .padding(.horizontal, 12)
                            }

                            if !statusMessage.isEmpty {
                                statusDisplayView
                            }

                            if let pending = pendingEntities {
                                confirmationCard(pending, transcript: pendingTranscript ?? "")
                            }
                            if isV2TFocusMode && pendingEntities == nil {
                                manualEntryCard
                                    .padding(.horizontal, 12)
                            }

                            if !isV2TFocusMode {
                                BetZoomCard(matchManager: matchManager)
                                    .padding(.horizontal)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                        .padding(.bottom, 8)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomControls
            }
            .background(
                LinearGradient(
                    colors: [appBgTop, appBgBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: voiceRecorder.lastError) { err in
            if let err = err, !err.isEmpty {
                statusMessage = "❌ \(err)"
            }
        }
        .sheet(isPresented: $showCoursePicker) {
            CoursePickerView(matchManager: matchManager)
        }
        .sheet(isPresented: $showStartHolePicker) {
            StartHolePickerView(matchManager: matchManager)
        }
        .sheet(isPresented: $showGuidedSetup) {
            GuidedSetupView(matchManager: matchManager)
                .caddySheetDetents()
        }
        .sheet(isPresented: $showBetZoom) {
            NavigationView {
                ScrollView {
                    BetZoomCard(matchManager: matchManager)
                        .padding()
                }
                .navigationTitle("Resultados Zoom")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showMoneyTracker) {
            NavigationView {
                MoneyTrackerView(matchManager: matchManager)
            }
        }
        .sheet(isPresented: $showFuzzyReview) {
            FuzzyReviewView(
                hole: fuzzyReviewHole,
                transcript: fuzzyReviewTranscript,
                scores: fuzzyReviewScores,
                players: matchManager.players,
                onConfirm: { reviewed in
                    let transcript = fuzzyReviewTranscript
                    let scores = reviewed.map {
                        PlayerScore(jugador: $0.alias, gross: $0.gross, putts: $0.putts)
                    }
                    let entities = ScoreEntities(hoyo: fuzzyReviewHole, scores: scores.isEmpty ? nil : scores)
                    showFuzzyReview = false
                    fuzzyReviewScores = []
                    fuzzyReviewHole = nil
                    fuzzyReviewTranscript = ""
                    Task { @MainActor in
                        handleParsedEntities(entities, transcript: transcript, showFuzzyNotice: false)
                    }
                },
                onCancel: {
                    showFuzzyReview = false
                    fuzzyReviewScores = []
                    fuzzyReviewHole = nil
                    fuzzyReviewTranscript = ""
                    statusMessage = "✍️ Corrige y vuelve a dictar."
                }
            )
        }
    }

    private var pendingActionBar: some View {
        HStack(spacing: 12) {
            Button("Dictar") {
                toggleRecording()
            }
            .buttonStyle(.bordered)

            Button("Modificar") {
                editableTranscript = pendingTranscript ?? ""
                pendingTranscriptToParse = pendingTranscript ?? ""
                statusMessage = "✍️ Modifica y vuelve a analizar."
            }
            .buttonStyle(.bordered)

            Button("Confirmar") {
                guard let entities = pendingEntities else { return }
                let missing = missingInfoList(entities)
                if !missing.isEmpty {
                    statusMessage = "❌ \(missingInfoStatus(entities))"
                    return
                }
                if needsOverwrite(entities) && !pendingOverwrite {
                    pendingOverwrite = true
                    statusMessage = "⚠️ Hoyo \(entities.hoyo ?? 0) ya tiene datos. Confirma otra vez para sobrescribir."
                    return
                }
                let result = matchManager.applyScores(entities)
                statusMessage = "✅ Confirmado. \(applyStatusText(result)): Hoyo \(entities.hoyo ?? 0)"
                lastConfirmedEntities = entities
                lastConfirmedTranscript = pendingTranscript
                logEvent(
                    action: "Confirmado",
                    tag: "CONFIRM",
                    status: "GUARDADO",
                    transcript: pendingTranscript ?? "",
                    hole: entities.hoyo ?? 0,
                    scores: entities.scores ?? []
                )
                pendingEntities = nil
                pendingTranscript = nil
                currentHole = nil
                pendingOverwrite = false
            }
            .buttonStyle(.borderedProminent)

            Button("Cancelar") {
                statusMessage = "✍️ Corrige y vuelve a dictar."
                logEvent(
                    action: "Cancelar",
                    tag: "CANCEL",
                    status: "DESCARTADO",
                    transcript: pendingTranscript ?? "",
                    hole: pendingEntities?.hoyo ?? 0,
                    scores: pendingEntities?.scores ?? []
                )
                pendingEntities = nil
                pendingTranscript = nil
                currentHole = nil
                pendingOverwrite = false
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
    
    private var headerView: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Inicio \(startTimeFormatter.string(from: matchManager.gameStartTime))")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    Button(action: { showCoursePicker = true }) {
                        HStack(spacing: 6) {
                            Image("CGMLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                            Text(matchManager.courseId)
                                .font(.subheadline.bold())
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(action: { showStartHolePicker = true }) {
                        Text("Hoyo \(matchManager.startHole)")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let h = currentHole {
                        Text("Grabando: Hoyo \(h)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let lastComplete = matchManager.lastCompleteHole() {
                        Text("Último completo: Hoyo \(lastComplete)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let incomplete = matchManager.firstIncompleteHole() {
                        let missing = matchManager.missingPlayersForHole(incomplete)
                        let missingText = missing.isEmpty ? "" : " (\(missing.joined(separator: ", ")))"
                        Text("Incompleto: Hoyo \(incomplete)\(missingText)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if let last = lastConfirmedEntities?.hoyo {
                        Text("Último: Hoyo \(last)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            if !isV2TFocusMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matchManager.players) { p in
                            Text(p.alias)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color(.systemBackground))
    }

struct CoursePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        NavigationView {
            List {
                ForEach(CourseCatalog.all, id: \.id) { course in
                    Button(action: {
                        matchManager.setCourse(course)
                        dismiss()
                    }) {
                        HStack {
                            Image("CGMLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name)
                                    .font(.headline)
                                Text("ID: \(course.id)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if course.id == matchManager.courseId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Selecciona campo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

struct StartHolePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        NavigationView {
            List {
                ForEach(1...18, id: \.self) { hole in
                    Button(action: {
                        matchManager.updateStartHole(hole)
                        dismiss()
                    }) {
                        HStack {
                            Text("Hoyo \(hole)")
                                .font(.headline)
                            Spacer()
                            if hole == matchManager.startHole {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Hoyo inicial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}


struct SetupWizardView: View {
    enum SetupStep: Int, CaseIterable {
        case campo
        case hoyoSalida
        case jugadores
        case strokes
        case parejas
        case strokesParejas

        var title: String {
            switch self {
            case .campo: return "Campo"
            case .hoyoSalida: return "Hoyo de salida"
            case .jugadores: return "Jugadores"
            case .strokes: return "Strokes individuales"
            case .parejas: return "Parejas y oponentes"
            case .strokesParejas: return "Strokes en parejas"
            }
        }

        var prompt: String {
            switch self {
            case .campo: return "¿Qué campo? (Ej: CGM)"
            case .hoyoSalida: return "¿Por qué hoyo inician? (Ej: Hoyo 10)"
            case .jugadores: return "¿Qué jugadores? (Ej: Roberto Ricardo Diego)"
            case .strokes: return "Strokes por jugador. (Ej: Anselmo recibe 5)"
            case .parejas: return "Dicta parejas u oponentes. (Ej: Roberto y Anselmo contra Diego y Juan)"
            case .strokesParejas: return "Strokes de pareja. (Ej: Roberto y Anselmo contra Diego y Juan, los lleva Juan 2)"
            }
        }

        var isOptional: Bool {
            switch self {
            case .strokes, .parejas, .strokesParejas:
                return true
            default:
                return false
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
    @State private var stepIndex = 0

    private var step: SetupStep { SetupStep.allCases[stepIndex] }
    private let appleConfidenceThreshold = 0.55
    private let useLLMNameFilter = true

    var body: some View {
        NavigationView {
            List {
                Section("Inicio") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paso \(stepIndex + 1)/\(SetupStep.allCases.count): \(step.title)")
                            .font(.headline)
                        Text(step.prompt)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: toggleDictation) {
                                HStack(spacing: 6) {
                                    Image(systemName: setupRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    Text(setupRecorder.isRecording ? "Detener" : "Dictar")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                            }
                            .disabled(isSetupTranscribing || isSetupValidating)

                            Button(action: applyStep) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                            }
                            .disabled(setupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSetupValidating || isSetupTranscribing)

                            if step.isOptional {
                                Button("Omitir") {
                                    advanceStep()
                                }
                                .font(.caption)
                            }
                        }

                        TextField("Texto detectado (corrige aquí)", text: $setupText)
                            .textInputAutocapitalization(.words)
                            .disabled(isSetupTranscribing || isSetupValidating)
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
            .navigationTitle("Inicio")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                if setupRecorder.isRecording {
                    _ = setupRecorder.stopRecording()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if stepIndex > 0 {
                        Button("Atrás") { stepIndex = max(0, stepIndex - 1) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(stepIndex == SetupStep.allCases.count - 1 ? "Cerrar" : "Siguiente") {
                        if stepIndex == SetupStep.allCases.count - 1 {
                            dismiss()
                        } else {
                            advanceStep()
                        }
                    }
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
                advanceStep()
            } else {
                setupStatus = "❌ Campo fuera de catálogo. Repite."
            }
        case .hoyoSalida:
            if let h = MatchInterpreter.extractHole(from: text.lowercased()),
               matchManager.getHole(h) != nil {
                matchManager.updateStartHole(h)
                setupStatus = "✅ Hoyo de salida: \(h)"
                advanceStep()
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
                            advanceStep()
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
                if u.alias == matchManager.yoAlias { continue }
                matchManager.setStrokesVsBase(alias: u.alias, value: Double(u.value))
            }
            setupStatus = "✅ Strokes actualizados"
            advanceStep()
        case .parejas:
            if matchManager.players.count < 4 {
                setupStatus = "❌ Faltan jugadores para parejas."
                return
            }
            let result = applyPairsFromText(text)
            setupStatus = result.ok ? "✅ Parejas actualizadas" : (result.message ?? "❌ No entendí parejas. Repite.")
            if result.ok { advanceStep() }
        case .strokesParejas:
            let result = applyLaneStrokesFromText(text)
            setupStatus = result.ok ? "✅ Strokes de pareja actualizados" : (result.message ?? "❌ No entendí strokes de pareja.")
            if result.ok { advanceStep() }
        }
        setupText = ""
    }

    private func advanceStep() {
        if setupRecorder.isRecording {
            _ = setupRecorder.stopRecording()
        }
        if stepIndex < SetupStep.allCases.count - 1 {
            stepIndex += 1
        }
        setupText = ""
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

    private func parseStrokeUpdatesSetup(_ text: String) -> [(alias: String, value: Double)] {
        let separators = [",", ";", " y ", " e "]
        var parts: [String] = [text]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        var updates: [(alias: String, value: Double)] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = parseStrokeUpdateSetup(trimmed) {
                updates.append(u)
            }
        }
        return updates
    }

    private func parseStrokeUpdateSetup(_ text: String) -> (alias: String, value: Double)? {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let num = extractFirstNumberDecimal(from: text) else { return nil }
        let hasReceive = hasWord(t, "recibe") || hasWord(t, "recibo") || hasWord(t, "recibes") ||
            t.contains("le dan") || t.contains("le da") ||
            hasWord(t, "tengo") || hasWord(t, "tiene") || hasWord(t, "tienen") ||
            hasWord(t, "lleva") || hasWord(t, "llevo") || hasWord(t, "llevan")
        let hasGive = hasWord(t, "da") || hasWord(t, "doy") || hasWord(t, "das") || hasWord(t, "dame") || hasWord(t, "dan")
        if !hasReceive && !hasGive { return nil }
        var aliases = aliasesMatchedByName(text)
        if aliases.isEmpty {
            aliases = extractAliasesFromText(text)
        }
        if aliases.isEmpty { return nil }
        let hasMe = hasWord(t, "me") || hasWord(t, "yo") || hasWord(t, "mi")
        var target = aliases.first!
        if hasMe {
            if let other = aliases.first(where: { $0 != matchManager.yoAlias }) {
                target = other
            }
        }
        let receiverMode = hasReceive || t.contains(" a ") || t.contains(" para ")
        let value = receiverMode ? num : -num
        return (target, value)
    }

    private func applyPairsFromText(_ text: String) -> (ok: Bool, message: String?) {
        let trimmed = stripStrokeClause(text)
        let unknown = unknownNames(in: trimmed)
        if !unknown.isEmpty { return (false, suggestionMessage(for: unknown)) }
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
        let unknown = unknownNames(in: text)
        if !unknown.isEmpty { return (false, suggestionMessage(for: unknown)) }
        if let split = splitMatchup(text) {
            let base = extractAliasesPreferNames(split.left)
            let opp = extractAliasesPreferNames(split.right)
            if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
            applyCarrierFromText(text, base: base, opp: opp)
            return (true, nil)
        }
        if matchManager.lanes.count == 1 {
            let lane = matchManager.lanes[0]
            applyCarrierFromText(text, base: lane.base, opp: lane.opp)
            return (true, nil)
        }
        if t.contains("lleva") || t.contains("llev") {
            if let carrier = extractAliasesPreferNames(text).first, matchManager.lanes.count > 0 {
                matchManager.setLaneCarrierForAlias(carrier)
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

    private func applyCarrierFromText(_ text: String, base: [String]?, opp: [String]?) {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let b = base, let o = opp, !b.isEmpty, !o.isEmpty else { return }
        let orderedAliases = orderedAliasesFromText(text)
        let receiverWords = ["recibe","recibo","reciben","recibir","lleva","llevo","llevas","llevan"]
        let giverWords = ["da","doy","das","dan","damos"]
        let receiverMode = hasAnyWord(t, receiverWords) ||
            t.contains("le dan") || t.contains("les dan") || t.contains("nos dan") ||
            t.contains("le llevan") || t.contains("les llevan") || t.contains("nos llevan")
        let giverMode = !receiverMode && (hasAnyWord(t, giverWords) || t.contains("le da") || t.contains("les da") || t.contains("nos da"))

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
        }

        if let strokes = extractFirstNumberDecimal(from: text) {
            let hasStrokeWord = t.contains("stroke") || t.contains("strokes") || t.contains("golpe") || t.contains("golpes")
            if receiverMode || giverMode || hasStrokeWord || t.contains("lleva") || t.contains("llev") {
                matchManager.setLaneStrokesForMatch(base: b, opp: o, value: strokes)
            }
        }
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
            hasWord(text, "golf") ||
            text.contains("strokes, golpes, base, contra, versus, putts")
    }

    private func hasWord(_ text: String, _ word: String) -> Bool {
        return text.range(of: #"\\b\#(word)\\b"#, options: .regularExpression) != nil
    }

    private func extractFirstNumber(from text: String) -> Int? {
        let pattern = #"(?i)\b(\d{1,2})\b"#
        if let range = text.range(of: pattern, options: .regularExpression) {
            let match = String(text[range])
            return Int(match)
        }
        return nil
    }

    private func extractFirstNumberDecimal(from text: String) -> Double? {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: ".")
        let decimalPattern = #"(?i)\b(\d{1,2}(?:\.5)?)\b"#
        if let range = normalized.range(of: decimalPattern, options: .regularExpression) {
            let match = String(normalized[range])
            if let value = Double(match) {
                return value
            }
        }
        if normalized.contains("medio") || normalized.contains("media") || normalized.contains("punto cinco") {
            if let base = extractFirstNumber(from: normalized) {
                return Double(base) + 0.5
            }
            return 0.5
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

    private var startTimeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    smallActionButton(
                        icon: voiceRecorder.isRecording ? "stop.fill" : "mic.fill",
                        title: voiceRecorder.isRecording ? "Detener" : "Dicta",
                        action: { toggleRecording() }
                    )

                    smallActionButton(
                        icon: "list.bullet.rectangle",
                        title: "Setup",
                        action: { showGuidedSetup = true }
                    )

                    smallActionButton(
                        icon: "magnifyingglass",
                        title: "F9/B9",
                        action: { showBetZoom = true }
                    )

                    smallActionButton(
                        icon: "dollarsign.circle",
                        title: "Money",
                        action: { showMoneyTracker = true }
                    )

                    NavigationLink(destination: ScorecardView(
                        matchManager: matchManager,
                        pendingEntities: pendingEntities,
                        pendingTranscript: pendingTranscript ?? ""
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                                .font(.caption)
                            Text("Tarjeta")
                                .font(.caption2.bold())
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }

            if pendingEntities != nil {
                pendingActionBar
            } else {
                EmptyView()
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

    private func smallActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption2.bold())
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
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
        if matchManager.players.count != 5 {
            missing.append("5 jugadores")
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
                        if u.alias == matchManager.yoAlias { continue }
                        matchManager.setStrokesVsBase(alias: u.alias, value: Double(u.value))
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

    private func parseStrokeUpdatesSetup(_ text: String) -> [(alias: String, value: Double)] {
        let separators = [",", ";", " y ", " e "]
        var parts: [String] = [text]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        var updates: [(alias: String, value: Double)] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = parseStrokeUpdateSetup(trimmed) {
                updates.append(u)
            }
        }
        return updates
    }

    private func parseStrokeUpdateSetup(_ text: String) -> (alias: String, value: Double)? {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let num = extractFirstNumberDecimal(from: text) else { return nil }
        let hasReceive = hasWord(t, "recibe") || hasWord(t, "recibo") || hasWord(t, "recibes") ||
            t.contains("le dan") || t.contains("le da") ||
            hasWord(t, "tengo") || hasWord(t, "tiene") || hasWord(t, "tienen") ||
            hasWord(t, "lleva") || hasWord(t, "llevo") || hasWord(t, "llevan")
        let hasGive = hasWord(t, "da") || hasWord(t, "doy") || hasWord(t, "das") || hasWord(t, "dame") || hasWord(t, "dan")
        if !hasReceive && !hasGive { return nil }
        var aliases = aliasesMatchedByName(text)
        if aliases.isEmpty {
            aliases = extractAliasesFromText(text)
        }
        if aliases.isEmpty { return nil }
        let hasMe = hasWord(t, "me") || hasWord(t, "yo") || hasWord(t, "mi")
        var target = aliases.first!
        if hasMe {
            if let other = aliases.first(where: { $0 != matchManager.yoAlias }) {
                target = other
            }
        }
        let receiverMode = hasReceive || t.contains(" a ") || t.contains(" para ")
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
            hasWord(text, "golf") ||
            text.contains("strokes, golpes, base, contra, versus, putts")
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

    private func extractFirstNumberDecimal(from text: String) -> Double? {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: ".")
        let decimalPattern = #"(?i)\b(\d{1,2}(?:\.5)?)\b"#
        if let range = normalized.range(of: decimalPattern, options: .regularExpression) {
            let match = String(normalized[range])
            if let value = Double(match) {
                return value
            }
        }
        if normalized.contains("medio") || normalized.contains("media") || normalized.contains("punto cinco") {
            if let base = extractFirstNumber(from: normalized) {
                return Double(base) + 0.5
            }
            return 0.5
        }
        return nil
    }
    
    private var statusDisplayView: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            editablePlayerRows(hole: holeNumber, par: par, si: si)

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

    private var manualEntryCard: some View {
        let hole = pendingEntities?.hoyo ?? currentHole ?? matchManager.firstIncompleteHole() ?? matchManager.startHole
        let par = matchManager.getHole(hole)?.par ?? 4
        let si = matchManager.getHole(hole)?.si ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Captura manual · Hoyo \(hole)")
                .font(.headline)
            editablePlayerRows(hole: hole, par: par, si: si)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
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

    private func editablePlayerRows(hole: Int, par: Int, si: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                row(label: "Hoyo", value: "\(hole)")
                row(label: "Par", value: "\(par)")
                row(label: "SI", value: "\(si)")
            }
            ForEach(matchManager.players) { player in
                HStack {
                    Text(player.alias)
                        .font(.subheadline.bold())
                        .frame(width: 54, alignment: .leading)
                    Spacer()
                    Button(action: { adjustPendingGross(alias: player.alias, delta: -1, par: par, hole: hole) }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    let value = pendingGross(alias: player.alias, fallbackPar: par)
                    Text("\(value)")
                        .font(.title3.monospacedDigit())
                        .frame(width: 46)
                    Button(action: { adjustPendingGross(alias: player.alias, delta: 1, par: par, hole: hole) }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
    }

    private func pendingGross(alias: String, fallbackPar: Int) -> Int {
        guard let entities = pendingEntities else { return max(1, fallbackPar) }
        let score = entities.scores?.first(where: { $0.jugador == alias })?.gross
        return max(1, score ?? fallbackPar)
    }

    private func adjustPendingGross(alias: String, delta: Int, par: Int, hole: Int) {
        let current = pendingEntities
        var scores = current?.scores ?? []
        if let idx = scores.firstIndex(where: { $0.jugador == alias }) {
            let next = max(1, scores[idx].gross + delta)
            scores[idx] = PlayerScore(jugador: alias, gross: next, putts: scores[idx].putts)
        } else {
            let next = max(1, par + delta)
            scores.append(PlayerScore(jugador: alias, gross: next, putts: nil))
        }
        let updated = ScoreEntities(hoyo: current?.hoyo ?? hole, scores: scores)
        pendingEntities = updated
        currentHole = current?.hoyo ?? hole
        if pendingTranscript == nil {
            pendingTranscript = "captura manual"
        }
        let missing = missingInfoList(updated)
        statusMessage = missing.isEmpty ? "✅ Listo para confirmar." : "⚠️ \(missingInfoStatus(updated))"
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
                    let rawTranscript = try await OpenAIService.shared.transcribeAudio(url: audioURL)
                    transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    transcriptSource = "OPENAI"
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
        let carryHandled = await MainActor.run {
            handleCarryTranscriptIfNeeded(transcript)
        }
        if carryHandled {
            return
        }

        let unitOnlyHandled = await MainActor.run {
            handleUnitTranscriptIfNeeded(transcript)
        }
        if unitOnlyHandled {
            return
        }

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
                statusMessage = "❌ Error al analizar dictado."
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

    @MainActor
    private func handleCarryTranscriptIfNeeded(_ transcript: String) -> Bool {
        let t = transcript.lowercased()
        guard t.contains("carry") else { return false }

        let mentioned = extractAliasesInMentionOrder(from: transcript)
        let isPair = t.contains("pareja") || t.contains("parejas") || t.contains("twosome")

        if isPair {
            guard let lane = matchManager.lanes.first(where: { lane in
                let set = Set(lane.base + lane.opp)
                let count = mentioned.filter { set.contains($0) }.count
                return count >= 2
            }) else {
                statusMessage = "❌ Indica la pareja para Carry. Ej: \"carry pareja DAN ROB\"."
                return true
            }

            if t.contains("quitar carry") || t.contains("sin carry") || t.contains("cancelar carry") {
                matchManager.clearPairCarryRequest(laneId: lane.id)
                statusMessage = "✅ Carry de pareja removido."
                return true
            }

            let explicitRequester: String? = {
                if let tail = substringAfterPattern(transcript, pattern: #"(?i)\b(lleva|solicita|pide)\b"#) {
                    return extractAliasesInMentionOrder(from: tail).first
                }
                return mentioned.first
            }()

            guard let eligible = matchManager.pairCarryEligibleRequester(laneId: lane.id) else {
                statusMessage = "❌ No hay perdedor definido en F9 para activar Carry de pareja."
                return true
            }

            let requester = explicitRequester ?? eligible
            matchManager.setPairCarryRequest(laneId: lane.id, requesterAlias: requester)
            if !matchManager.isPairCarryActive(laneId: lane.id) {
                statusMessage = "❌ El solicitante debe ser de la pareja perdedora del F9. Perdedor actual: \(eligible)."
                return true
            }
            let f9 = abs(matchManager.pairF9Vuelta(laneId: lane.id))
            let carry = matchManager.pairCarryResultB9(laneId: lane.id)
            statusMessage = "✅ Carry pareja activo. Perdedor F9 (\(f9)) solicita \(requester). Carry B9: \(carry)."
            return true
        }

        let opp = mentioned.first(where: { $0 != matchManager.yoAlias })
        guard let opponent = opp else {
            statusMessage = "❌ Indica rival para Carry. Ej: \"Carry vs ROB\"."
            return true
        }

        if t.contains("quitar carry") || t.contains("sin carry") || t.contains("cancelar carry") {
            matchManager.clearIndividualCarryRequest(opponentAlias: opponent)
            statusMessage = "✅ Carry removido vs \(opponent)."
            return true
        }

        guard let eligible = matchManager.individualCarryEligibleRequester(opponentAlias: opponent) else {
            statusMessage = "❌ No hay perdedor definido en F9 para activar Carry vs \(opponent)."
            return true
        }

        let explicitRequester: String? = {
            if let tail = substringAfterPattern(transcript, pattern: #"(?i)\b(lleva|solicita|pide)\b"#) {
                return extractAliasesInMentionOrder(from: tail).first
            }
            return nil
        }()
        let requester = explicitRequester ?? eligible
        matchManager.setIndividualCarryRequest(opponentAlias: opponent, requesterAlias: requester)
        if !matchManager.isIndividualCarryActive(opponentAlias: opponent) {
            statusMessage = "❌ El solicitante debe ser el perdedor del F9. Perdedor actual: \(eligible)."
            return true
        }

        let f9 = abs(matchManager.individualF9Vuelta(opponentAlias: opponent))
        let carry = matchManager.individualCarryResultB9(opponentAlias: opponent)
        let who = requester == matchManager.yoAlias ? "yo" : requester
        statusMessage = "✅ Carry activo vs \(opponent). Perdedor F9 (\(f9)) = \(who). Carry B9: \(carry)."
        return true
    }

    @MainActor
    private func handleUnitTranscriptIfNeeded(_ transcript: String) -> Bool {
        let t = transcript.lowercased()
        let isOyesIntent = t.contains("oyes") || t.contains("oyeses") || t.contains("rank") || t.contains("ranking") || t.contains("orden")
        let isUnitIntent = t.contains("unidad") || t.contains("unidades") || t.contains("sandy") || t.contains("tripote") || t.contains("cuatripot") || t.contains("cuatro putt") || isOyesIntent
        if !isUnitIntent { return false }

        guard let hole = (MatchInterpreter.extractHole(from: t) ?? currentHole ?? matchManager.firstIncompleteHole()) else {
            statusMessage = "❌ Falta hoyo para registrar unidades."
            return true
        }

        if isOyesIntent {
            guard matchManager.getHole(hole)?.par == 3 else {
                statusMessage = "❌ OYES rank solo aplica en par 3. Hoyo \(hole) no es par 3."
                return true
            }
            let ranksByAlias = parseOyesRanks(from: transcript)
            if ranksByAlias.count < 2 {
                statusMessage = "❌ Faltan jugadores para OYES rank. Di el orden: DAN ROB ANS..."
                return true
            }
            matchManager.setOyesRanks(hole: hole, ranksByAlias: ranksByAlias)
            let orderText = ranksByAlias
                .sorted { $0.value < $1.value }
                .map { "\($0.key) \($0.value)" }
                .joined(separator: " · ")
            statusMessage = "✅ OYES rank guardado en Hoyo \(hole): \(orderText)"
            logEvent(
                action: "Unidad OYES",
                tag: "UNITS_OYES",
                status: "GUARDADO",
                transcript: transcript,
                hole: hole,
                scores: []
            )
            return true
        }

        let aliases = extractAliasesInMentionOrder(from: transcript)
        let targets = aliases.isEmpty ? [matchManager.yoAlias] : aliases

        if t.contains("sandy") {
            let units = betUnits(tag: "SANDY", fallback: 1)
            for alias in targets {
                matchManager.upsertUnitEvent(hole: hole, alias: alias, code: "SANDY_PAR", units: units, note: "Sandy par")
            }
            statusMessage = "✅ Sandy par registrado en Hoyo \(hole): \(targets.joined(separator: ", "))"
            return true
        }
        if t.contains("tripote") || t.contains("tres putt") {
            for alias in targets {
                matchManager.upsertUnitEvent(hole: hole, alias: alias, code: "3P", units: 0, note: "Tripoteo")
            }
            statusMessage = "✅ Tripoteo registrado en Hoyo \(hole): \(targets.joined(separator: ", "))"
            return true
        }
        if t.contains("cuatripot") || t.contains("cuatro putt") {
            for alias in targets {
                matchManager.upsertUnitEvent(hole: hole, alias: alias, code: "4P", units: 0, note: "Cuatripoteo")
            }
            statusMessage = "✅ Cuatripoteo registrado en Hoyo \(hole): \(targets.joined(separator: ", "))"
            return true
        }

        return false
    }

    private func parseOyesRanks(from transcript: String) -> [String: Int] {
        let normalized = matchManager.normalizePlayerKey(transcript)
        let tokens = normalized.split(separator: " ").map { String($0) }
        var explicit: [String: Int] = [:]
        if tokens.count >= 2 {
            for i in 0..<(tokens.count - 1) {
                guard let alias = matchManager.exactAlias(for: tokens[i]) else { continue }
                guard let rank = rankFromToken(tokens[i + 1]), rank > 0 else { continue }
                explicit[alias] = rank
            }
        }
        if explicit.count >= 2 {
            return explicit
        }

        let ordered = extractAliasesInMentionOrder(from: transcript)
        var ranks: [String: Int] = [:]
        for (idx, alias) in ordered.enumerated() {
            ranks[alias] = idx + 1
        }
        return ranks
    }

    private func extractAliasesInMentionOrder(from transcript: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(transcript)
        let tokens = normalized.split(separator: " ").map { String($0) }
        var out: [String] = []
        var used: Set<String> = []
        var i = 0
        while i < tokens.count {
            if i + 1 < tokens.count {
                let bigram = tokens[i] + " " + tokens[i + 1]
                if let alias = matchManager.exactAlias(for: bigram), !used.contains(alias) {
                    out.append(alias)
                    used.insert(alias)
                    i += 2
                    continue
                }
            }
            if let alias = matchManager.exactAlias(for: tokens[i]), !used.contains(alias) {
                out.append(alias)
                used.insert(alias)
            }
            i += 1
        }
        return out
    }

    private func rankFromToken(_ token: String) -> Int? {
        if let n = Int(token), n > 0 { return n }
        let words: [String: Int] = [
            "UNO": 1, "DOS": 2, "TRES": 3, "CUATRO": 4, "CINCO": 5,
            "SEIS": 6, "SIETE": 7, "OCHO": 8, "NUEVE": 9, "DIEZ": 10
        ]
        return words[token.uppercased()]
    }

    private func betUnits(tag: String, fallback: Int) -> Int {
        if let value = matchManager.betCatalog.first(where: { $0.tag.uppercased() == tag.uppercased() })?.units {
            return value
        }
        return fallback
    }

    private func hasWord(_ text: String, _ word: String) -> Bool {
        return text.range(of: #"\\b\#(word)\\b"#, options: .regularExpression) != nil
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
                            let rivals = playerAliases.filter { $0.alias != matchManager.yoAlias }
                            if rivals.isEmpty {
                                Text("No hay rivales para asignar strokes.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(rivals, id: \.alias) { p in
                                    HStack(spacing: 8) {
                                        Text(p.alias)
                                            .font(.subheadline.bold())
                                            .frame(width: 54, alignment: .leading)
                                        Button("-") {
                                            adjustStroke(alias: p.alias, delta: -1.0)
                                        }
                                        .buttonStyle(.bordered)
                                        Text(formatSignedStroke(strokesByAlias[p.alias] ?? 0))
                                            .font(.body.monospacedDigit())
                                            .frame(width: 68)
                                        Button("+") {
                                            adjustStroke(alias: p.alias, delta: 1.0)
                                        }
                                        .buttonStyle(.bordered)
                                        Button(".5") {
                                            adjustStroke(alias: p.alias, delta: 0.5)
                                        }
                                        .buttonStyle(.borderedProminent)
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
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                let opp = opponentsForBase()
                                Text("Oponentes: \(opp.isEmpty ? "—" : opp.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    case .strokesParejas:
                        let lanes = buildLocalLanes()
                        if lanes.isEmpty {
                            Text("Define primero las parejas.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(lanes, id: \.id) { lane in
                                let key = lane.id
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text("\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))")
                                            .font(.caption)
                                            .lineLimit(1)
                                        Spacer()
                                        Button("-") {
                                            adjustLaneStroke(key: key, delta: -1.0)
                                        }
                                        .buttonStyle(.bordered)
                                        Text(formatStroke(laneStrokes[key] ?? 0))
                                            .font(.body.monospacedDigit())
                                            .frame(width: 42)
                                        Button("+") {
                                            adjustLaneStroke(key: key, delta: 1.0)
                                        }
                                        .buttonStyle(.bordered)
                                        Button(".5") {
                                            adjustLaneStroke(key: key, delta: 0.5)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    HStack(spacing: 8) {
                                        Text("Lleva")
                                            .font(.caption2.bold())
                                            .foregroundColor(.secondary)
                                        Picker("Lleva", selection: Binding(
                                            get: { laneCarrierByKey[key] ?? "" },
                                            set: { laneCarrierByKey[key] = $0 }
                                        )) {
                                            Text("—").tag("")
                                            ForEach(lane.base + lane.opp, id: \.self) { alias in
                                                Text(alias).tag(alias)
                                            }
                                        }
                                        .pickerStyle(.menu)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Activación por partido (Individual)")
                                .font(.caption.bold())
                            let rivals = playerAliases.filter { $0.alias != matchManager.yoAlias }
                            if rivals.isEmpty {
                                Text("No hay rivales.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
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
                            Text("Activación por partido (Parejas)")
                                .font(.caption.bold())
                            let lanes = matchManager.lanes.prefix(3)
                            if lanes.isEmpty {
                                Text("Define parejas para activar apuestas por match.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
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
            .onAppear {
                loadDefaults()
                syncLaneSetupState()
            }
            .onChange(of: base1) { _ in
                syncLaneSetupState()
            }
            .onChange(of: base2) { _ in
                syncLaneSetupState()
            }
            .onChange(of: playerNames) { _ in
                syncLaneSetupState()
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
        syncLaneSetupState()
        vueltaValueText = matchManager.vueltaValue > 0 ? "\(matchManager.vueltaValue)" : ""
        selectedBetIds = Set(matchManager.activeBets.map { $0.definition.id })
        for bet in matchManager.activeBets {
            if let tag = bet.tagOverride {
                betTagOverrides[bet.definition.id] = tag
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
        let aliases = playerAliases.map { $0.alias }.filter { $0 != matchManager.yoAlias }
        for a in aliases {
            if strokesByAlias[a] == nil {
                let current = matchManager.players.first(where: { $0.alias == a })?.strokesVsBase ?? 0
                strokesByAlias[a] = current
            }
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

    private func perMatchToggleRow(
        label: String,
        switches: MatchBetSwitches,
        onChange: @escaping (MatchBetSwitches) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            toggleChip("V", isOn: switches.vuelta) {
                var next = switches
                next.vuelta.toggle()
                onChange(next)
            }
            toggleChip("P", isOn: switches.presion) {
                var next = switches
                next.presion.toggle()
                onChange(next)
            }
            toggleChip("C", isOn: switches.carry) {
                var next = switches
                next.carry.toggle()
                onChange(next)
            }
            toggleChip("M", isOn: switches.match) {
                var next = switches
                next.match.toggle()
                onChange(next)
            }
            toggleChip("U", isOn: switches.units) {
                var next = switches
                next.units.toggle()
                onChange(next)
            }
            Spacer(minLength: 0)
        }
    }

    private func toggleChip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.bold())
                .foregroundColor(isOn ? .white : .primary)
                .frame(width: 24, height: 24)
                .background(isOn ? Color.green : Color(.secondarySystemBackground))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
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
            matchManager.setCourse(course, resetScores: false)
        }
        matchManager.updateStartHole(startHole, resetScores: false)
        matchManager.setPlayers(names: playerNames, preserveScores: true)
        for p in matchManager.players {
            if p.alias == matchManager.yoAlias { continue }
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
                let v = laneStrokes[key] ?? 0
                matchManager.setLaneStrokesForMatch(base: lane.base, opp: lane.opp, value: v)
                if let carrier = laneCarrierByKey[key], !carrier.isEmpty {
                    matchManager.setLaneCarrierForMatch(base: lane.base, opp: lane.opp, carrier: carrier)
                }
            }
        }
        if let v = Int(vueltaValueText) {
            matchManager.setVueltaValue(v)
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

    private func formatStroke(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private func formatSignedStroke(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + formatStroke(value)
    }

    private func adjustStroke(alias: String, delta: Double) {
        let current = strokesByAlias[alias] ?? 0
        let next = max(-20, min(20, current + delta))
        strokesByAlias[alias] = (next * 2).rounded() / 2
    }

    private func adjustLaneStroke(key: String, delta: Double) {
        let current = laneStrokes[key] ?? 0
        let next = max(0, min(20, current + delta))
        laneStrokes[key] = (next * 2).rounded() / 2
    }

    private func syncLaneSetupState() {
        let lanes = buildLocalLanes()
        let keys = Set(lanes.map { $0.id })
        for lane in lanes {
            let key = lane.id
            if laneStrokes[key] == nil {
                if let existing = matchManager.lanes.first(where: {
                    Set($0.base) == Set(lane.base) && Set($0.opp) == Set(lane.opp)
                }) {
                    laneStrokes[key] = existing.strokes
                    laneCarrierByKey[key] = existing.strokeCarrier ?? ""
                } else {
                    laneStrokes[key] = 0
                    laneCarrierByKey[key] = ""
                }
            } else if laneCarrierByKey[key] == nil {
                laneCarrierByKey[key] = ""
            }
        }
        for key in laneStrokes.keys where !keys.contains(key) {
            laneStrokes.removeValue(forKey: key)
        }
        for key in laneCarrierByKey.keys where !keys.contains(key) {
            laneCarrierByKey.removeValue(forKey: key)
        }
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

extension View {
    @ViewBuilder
    func caddySheetDetents() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.large])
        } else {
            self
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct ScorecardView: View {
    @ObservedObject var matchManager: MatchManager
    let pendingEntities: ScoreEntities?
    let pendingTranscript: String
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let pending = pendingEntities {
                    CardView(
                        matchManager: matchManager,
                        entities: pending,
                        transcript: pendingTranscript
                    )
                } else {
                    Text("No hay tarjeta pendiente.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                ScorecardGrid(matchManager: matchManager)
            }
            .padding()
        }
        .navigationTitle("Tarjeta")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MatchSummaryCard: View {
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resumen")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            MatchSummaryView(matchManager: matchManager)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct BetZoomStatusCard: View {
    @ObservedObject var matchManager: MatchManager
    let onOpenZoom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estado apuestas")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            HStack {
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Ver zoom") {
                    onOpenZoom()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var statusText: String {
        if let h = matchManager.lastCompleteHole() {
            return "\(matchManager.segmentForHole(h)) · Hoyo \(h)"
        }
        return "Sin hoyos completos"
    }
}

private enum MoneyUnitsScope: String, CaseIterable, Identifiable {
    case individual = "Individual"
    case parejas = "Parejas"

    var id: String { rawValue }
}

private enum MoneyUnitTarget: Identifiable {
    case individual(String)
    case parejas(UUID)

    var id: String {
        switch self {
        case .individual(let alias): return "IND-\(alias)"
        case .parejas(let laneId): return "PAR-\(laneId.uuidString)"
        }
    }
}

private struct MoneyUnitRow: Identifiable {
    let id = UUID()
    let label: String
    let f9: Int
    let b9: Int
    let total: Int
    let amount: Int
    let target: MoneyUnitTarget
}

struct MoneyTrackerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    @State private var scope: MoneyUnitsScope = .individual
    @State private var vueltaValueText: String = ""
    @State private var presionValueText: String = ""
    @State private var matchValueText: String = ""
    @State private var unitValueText: String = ""
    @State private var puttsUnitsText: String = ""
    @State private var puttsMode: PuttsBetMode = .hole18
    @State private var zoomTarget: MoneyUnitTarget?
    @State private var walletConfigTarget: MoneyUnitTarget?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Apuestas")
                    .font(.caption.bold())
                    .frame(width: 64, alignment: .leading)
                tinyValueField("V", text: $vueltaValueText, width: 52)
                tinyValueField("P", text: $presionValueText, width: 52)
                tinyValueField("M", text: $matchValueText, width: 52)
                Button("Aplicar") { applyApuestaValues() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Valor unidad")
                    .font(.caption.bold())
                    .frame(width: 88, alignment: .leading)
                tinyValueField("U", text: $unitValueText, width: 52)
                Button("Aplicar") { applyUnitValue() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Putts")
                    .font(.caption.bold())
                    .frame(width: 64, alignment: .leading)
                Picker("Putts", selection: $puttsMode) {
                    Text("H18").tag(PuttsBetMode.hole18)
                    Text("Vuelta").tag(PuttsBetMode.byRound)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                tinyValueField("u", text: $puttsUnitsText, width: 52)
                Button("Aplicar") { applyPuttsValues() }
                    .buttonStyle(.bordered)
                Spacer()
            }

            Picker("Scope", selection: $scope) {
                ForEach(MoneyUnitsScope.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if rows.isEmpty {
                Spacer()
                Text("Sin datos de unidades para mostrar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            moneyHeaderCell("Rival/Pareja", 160)
                            moneyHeaderCell("F9", 40)
                            moneyHeaderCell("B9", 40)
                            moneyHeaderCell("Tot", 40)
                            moneyHeaderCell("$", 58)
                            moneyHeaderCell("Zoom", 42)
                        }
                        ForEach(rows) { row in
                            HStack(spacing: 8) {
                                moneyDataCell(row.label, 160)
                                moneyDataCell(signed(row.f9), 40)
                                moneyDataCell(signed(row.b9), 40)
                                moneyDataCell(signed(row.total), 40)
                                moneyDataCell(signed(row.amount), 58)
                                Button(action: { zoomTarget = row.target }) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 42, alignment: .leading)
                            }
                        }
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Wallet (Apuestas)")
                    .font(.caption.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            moneyHeaderCell("Rival/Pareja", 160)
                            moneyHeaderCell("V", 28)
                            moneyHeaderCell("P", 28)
                            moneyHeaderCell("C", 28)
                            moneyHeaderCell("M", 28)
                            moneyHeaderCell("U", 28)
                            moneyHeaderCell("ON", 62)
                            moneyHeaderCell("Cfg", 38)
                            moneyHeaderCell("Total", 70)
                        }
                        ForEach(wallet.lines) { line in
                            HStack(spacing: 8) {
                                moneyDataCell(line.label, 160)
                                moneyDataCell(signed(line.vueltaMoney), 28)
                                moneyDataCell(signed(line.presionMoney), 28)
                                moneyDataCell(signed(line.carryMoney), 28)
                                moneyDataCell(signed(line.matchMoney), 28)
                                moneyDataCell(signed(line.unitsMoney), 28)
                                moneyDataCell(line.activationSummary, 62)
                                Button(action: {
                                    walletConfigTarget = walletTarget(for: line)
                                }) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 38, alignment: .leading)
                                moneyDataCell(signed(line.totalMoney), 70)
                            }
                        }
                        HStack(spacing: 8) {
                            moneyHeaderCell("TOTAL", 160)
                            moneyHeaderCell("", 28)
                            moneyHeaderCell("", 28)
                            moneyHeaderCell("", 28)
                            moneyHeaderCell("", 28)
                            moneyHeaderCell("", 28)
                            moneyHeaderCell("", 62)
                            moneyHeaderCell("", 38)
                            moneyHeaderCell(signed(wallet.totalMoney), 70)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Money Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cerrar") { dismiss() }
            }
        }
        .onAppear {
            if matchManager.vueltaValue <= 0 || matchManager.presionValue <= 0 || matchManager.matchValue <= 0 {
                matchManager.setApuestaValues(
                    vuelta: 50,
                    presion: 50,
                    match: 50
                )
                if matchManager.unitValue <= 0 {
                    matchManager.setUnitValue(25)
                }
            }
            vueltaValueText = "\(matchManager.vueltaValue > 0 ? matchManager.vueltaValue : 50)"
            presionValueText = "\(matchManager.presionValue > 0 ? matchManager.presionValue : 50)"
            matchValueText = "\(matchManager.matchValue > 0 ? matchManager.matchValue : 50)"
            unitValueText = "\(matchManager.unitValue > 0 ? matchManager.unitValue : 25)"
            puttsUnitsText = "\(matchManager.puttsBetUnits > 0 ? matchManager.puttsBetUnits : 2)"
            puttsMode = matchManager.puttsBetMode
        }
        .sheet(item: $zoomTarget) { target in
            NavigationView {
                UnitLogDetailView(
                    title: zoomTitle(target),
                    entries: detailEntries(target)
                )
            }
        }
        .sheet(item: $walletConfigTarget) { target in
            NavigationView {
                WalletMatchConfigView(matchManager: matchManager, target: target)
            }
        }
    }

    private var rows: [MoneyUnitRow] {
        switch scope {
        case .individual:
            let value = parsedUnitValue()
            let opps = matchManager.players.map(\.alias).filter { $0 != matchManager.yoAlias }
            return opps.map { opp in
                let f9 = matchManager.unitStakeForIndividual(opponentAlias: opp, segmentOverride: "F9")
                let b9 = matchManager.unitStakeForIndividual(opponentAlias: opp, segmentOverride: "B9")
                let total = f9 + b9
                return MoneyUnitRow(
                    label: "vs \(opp)",
                    f9: f9,
                    b9: b9,
                    total: total,
                    amount: total * value,
                    target: .individual(opp)
                )
            }
        case .parejas:
            let value = parsedUnitValue()
            return matchManager.lanes.prefix(3).map { lane in
                let f9 = matchManager.unitStakeForPair(laneId: lane.id, segmentOverride: "F9")
                let b9 = matchManager.unitStakeForPair(laneId: lane.id, segmentOverride: "B9")
                let total = f9 + b9
                return MoneyUnitRow(
                    label: "\(lane.base.joined(separator: "+"))/\(lane.opp.joined(separator: "+"))",
                    f9: f9,
                    b9: b9,
                    total: total,
                    amount: total * value,
                    target: .parejas(lane.id)
                )
            }
        }
    }

    private var wallet: WalletSnapshot {
        matchManager.walletSnapshot()
    }

    private func parsedUnitValue() -> Int {
        max(0, Int(unitValueText) ?? matchManager.unitValue)
    }

    private func parsedVueltaValue() -> Int {
        max(0, Int(vueltaValueText) ?? matchManager.vueltaValue)
    }

    private func parsedPresionValue() -> Int {
        max(0, Int(presionValueText) ?? matchManager.presionValue)
    }

    private func parsedMatchValue() -> Int {
        max(0, Int(matchValueText) ?? matchManager.matchValue)
    }

    private func parsedPuttsUnits() -> Int {
        max(0, Int(puttsUnitsText) ?? matchManager.puttsBetUnits)
    }

    private func applyApuestaValues() {
        matchManager.setApuestaValues(
            vuelta: parsedVueltaValue(),
            presion: parsedPresionValue(),
            match: parsedMatchValue()
        )
    }

    private func applyUnitValue() {
        matchManager.setUnitValue(parsedUnitValue())
    }

    private func applyPuttsValues() {
        matchManager.setPuttsBet(mode: puttsMode, units: parsedPuttsUnits())
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func tinyValueField(_ placeholder: String, text: Binding<String>, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
    }

    private func moneyHeaderCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func moneyDataCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundColor(.primary)
            .frame(width: width, alignment: .leading)
    }

    private func zoomTitle(_ target: MoneyUnitTarget) -> String {
        switch target {
        case .individual(let opp):
            return "\(matchManager.yoAlias) vs \(opp)"
        case .parejas(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return "Pareja" }
            return "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
        }
    }

    private func walletTarget(for line: WalletLine) -> MoneyUnitTarget? {
        if let opp = line.opponentAlias {
            return .individual(opp)
        }
        if let laneId = line.laneId {
            return .parejas(laneId)
        }
        return nil
    }

    private func detailEntries(_ target: MoneyUnitTarget) -> [UnitLogEntry] {
        switch target {
        case .individual(let opp):
            return matchManager
                .unitLogEntriesForZoom(segmentOverride: nil, includeIndividual: true, includePair: false)
                .filter { $0.scope == .individual && $0.vs == opp }
        case .parejas(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return [] }
            let player = lane.base.joined(separator: "+")
            let vs = lane.opp.joined(separator: "+")
            return matchManager
                .unitLogEntriesForZoom(segmentOverride: nil, includeIndividual: false, includePair: true)
                .filter { $0.scope == .parejas && $0.player == player && $0.vs == vs }
        }
    }
}

private struct WalletMatchConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager
    let target: MoneyUnitTarget

    var body: some View {
        Form {
            Section("Apuesta activa en este match") {
                Toggle("Vuelta", isOn: binding(\.vuelta))
                Toggle("Presión", isOn: binding(\.presion))
                Toggle("Carry B9", isOn: binding(\.carry))
                Toggle("Match", isOn: binding(\.match))
                Toggle("Unidades", isOn: binding(\.units))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cerrar") { dismiss() }
            }
        }
    }

    private var title: String {
        switch target {
        case .individual(let opp):
            return "\(matchManager.yoAlias) vs \(opp)"
        case .parejas(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return "Pareja" }
            return "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
        }
    }

    private func currentSwitches() -> MatchBetSwitches {
        switch target {
        case .individual(let opp):
            return matchManager.betSwitchesForIndividual(opponentAlias: opp)
        case .parejas(let laneId):
            return matchManager.betSwitchesForPair(laneId: laneId)
        }
    }

    private func saveSwitches(_ switches: MatchBetSwitches) {
        switch target {
        case .individual(let opp):
            matchManager.setBetSwitchesForIndividual(opponentAlias: opp, switches: switches)
        case .parejas(let laneId):
            matchManager.setBetSwitchesForPair(laneId: laneId, switches: switches)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<MatchBetSwitches, Bool>) -> Binding<Bool> {
        Binding<Bool>(
            get: { currentSwitches()[keyPath: keyPath] },
            set: { newValue in
                var next = currentSwitches()
                next[keyPath: keyPath] = newValue
                saveSwitches(next)
            }
        )
    }
}

struct UnitLogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let entries: [UnitLogEntry]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    detailHeader("H", 30)
                    detailHeader("Jugador", 76)
                    detailHeader("Tipo", 88)
                    detailHeader("VS", 78)
                    detailHeader("u", 24)
                    detailHeader("Detalle", 140)
                }
                ForEach(entries) { e in
                    HStack(spacing: 8) {
                        detailData("\(e.hole)", 30)
                        detailData(e.player, 76)
                        detailData(e.type, 88)
                        detailData(e.vs ?? "—", 78)
                        detailData(e.units > 0 ? "+\(e.units)" : "\(e.units)", 24)
                        detailData(e.detail ?? "—", 140)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cerrar") { dismiss() }
            }
        }
    }

    private func detailHeader(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func detailData(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .frame(width: width, alignment: .leading)
    }
}

struct BetZoomCard: View {
    enum ZoomTarget: Identifiable {
        case individual(String)
        case parejas(UUID)
        case unidades
        var id: String {
            switch self {
            case .individual(let opp):
                return "ind-\(opp)"
            case .parejas(let id):
                return "pair-\(id.uuidString)"
            case .unidades:
                return "units"
            }
        }
    }

    struct SummaryLine: Identifiable {
        let id = UUID()
        let label: String
        let strokesText: String
        let strokesColor: Color
        let vpText: String
        let puttsText: String
        let unitsText: String
        let target: ZoomTarget
    }

    @ObservedObject var matchManager: MatchManager
    @State private var zoomTarget: ZoomTarget?
    @State private var selectedSegment: String = "F9"
    @State private var unitsScopeFilter: String = "Todos"
    private let fairwayDark = Color(red: 0.10, green: 0.13, blue: 0.12)
    private let fairwayMid = Color(red: 0.15, green: 0.20, blue: 0.18)
    private let clubGold = Color(red: 0.85, green: 0.72, blue: 0.32)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Golf Scorecard Tracker")
                    .font(.custom("Playfair Display", size: 18))
                    .foregroundColor(clubGold)
                Spacer()
                Text(headerText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.8))
            }

            if availableSegments.count > 1 {
                Picker("Vuelta", selection: $selectedSegment) {
                    ForEach(availableSegments, id: \.self) { seg in
                        Text(seg).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
            }

            if summaryLines.isEmpty {
                Text("Sin apuestas para mostrar.")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.7))
            } else {
                if !individualSummaryLines.isEmpty {
                    sectionTitle("Individuales")
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                headerCell("Apuesta", 132, color: clubGold)
                                headerCell("Strokes", 96, color: clubGold)
                                headerCell("Vta Pres", 92, color: clubGold)
                                headerCell("Unid", 36, color: clubGold)
                                headerCell("Putts", 52, color: clubGold)
                                if selectedSegment == "B9" {
                                    headerCell("Carry", 56, color: clubGold)
                                }
                            }
                            ForEach(individualSummaryLines.prefix(8)) { line in
                                HStack(spacing: 8) {
                                    zoomNameCell(line: line, width: 132)
                                    strokeCell(line.strokesText, 96, color: line.strokesColor)
                                    dataCell(line.vpText, 92)
                                    dataCell(line.unitsText, 36)
                                    dataCell(line.puttsText, 52)
                                    if selectedSegment == "B9" {
                                        carryToggleCell(line: line, width: 56)
                                    }
                                }
                            }
                        }
                        .frame(minWidth: selectedSegment == "B9" ? 506 : 442, alignment: .leading)
                    }
                }
                if !pairSummaryLines.isEmpty {
                    Divider().overlay(clubGold.opacity(0.7))
                    sectionTitle("Twosomes")
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                headerCell("Pareja", 132, color: clubGold)
                                headerCell("Strokes", 96, color: clubGold)
                                headerCell("Vta Pres", 92, color: clubGold)
                                headerCell("Unid", 44, color: clubGold)
                                if selectedSegment == "B9" {
                                    headerCell("Carry", 56, color: clubGold)
                                }
                            }
                            ForEach(pairSummaryLines.prefix(8)) { line in
                                HStack(spacing: 8) {
                                    zoomNameCell(line: line, width: 132)
                                    strokeCell(line.strokesText, 96, color: line.strokesColor)
                                    dataCell(line.vpText, 92)
                                    dataCell(line.unitsText, 44)
                                    if selectedSegment == "B9" {
                                        carryToggleCell(line: line, width: 56)
                                    }
                                }
                            }
                        }
                        .frame(minWidth: selectedSegment == "B9" ? 444 : 380, alignment: .leading)
                    }
                }
                if let unitLine {
                    Divider().overlay(clubGold.opacity(0.7))
                    sectionTitle("Unidades")
                    HStack(spacing: 8) {
                        zoomNameCell(line: unitLine, width: 132)
                        strokeCell(unitLine.strokesText, 96, color: unitLine.strokesColor)
                        dataCell(unitLine.vpText, 92)
                        dataCell(unitLine.unitsText, 38)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [fairwayMid, fairwayDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(clubGold.opacity(0.35), lineWidth: 1)
        )
        .sheet(item: $zoomTarget) { target in
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(zoomSheetHeader(target: target))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        switch target {
                        case .individual(let opp):
                            individualTable(opponent: opp, rows: matchManager.individualZoomRows(opponentAlias: opp, segmentOverride: selectedSegment))
                        case .parejas(let laneId):
                            pairTable(rows: matchManager.pairZoomRows(laneId: laneId, segmentOverride: selectedSegment))
                        case .unidades:
                            unitsTable(entries: unitLogEntries)
                        }
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
                .navigationTitle("Detalle \(selectedSegment)")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            if let h = uptoHole {
                let current = matchManager.segmentForHole(h)
                if availableSegments.contains(current) {
                    selectedSegment = current
                } else if let first = availableSegments.first {
                    selectedSegment = first
                }
            }
        }
    }

    private var uptoHole: Int? {
        matchManager.lastCompleteHole()
    }

    private var headerText: String {
        if let h = matchManager.lastHoleForZoom(segment: selectedSegment) {
            return "\(selectedSegment) · Hoyo \(h)"
        }
        return "Sin hoyos completos"
    }

    private var availableSegments: [String] {
        let segs = matchManager.availableZoomSegments()
        return segs.isEmpty ? ["F9"] : segs
    }

    private var summaryLines: [SummaryLine] {
        var out: [SummaryLine] = []
        let opps = matchManager.players.map(\.alias).filter { $0 != matchManager.yoAlias }
        for opp in opps {
            let rows = matchManager.individualZoomRows(opponentAlias: opp, segmentOverride: selectedSegment)
            guard let last = rows.last else { continue }
            let pres = pressureText(last.openPressures)
            var vp = "\(resultText(last.vueltaAccum)) \(pres)"
            if selectedSegment == "B9" {
                let carry = matchManager.individualCarryResultB9(opponentAlias: opp)
                vp += " C\(resultText(carry))"
            }
            let putts = "\(last.yoPuttsAccum) \(last.oppPuttsAccum)"
            let yoBase = matchManager.players.first(where: { $0.alias == matchManager.yoAlias })?.strokesVsBase ?? 0
            let oppBase = matchManager.players.first(where: { $0.alias == opp })?.strokesVsBase ?? 0
            let relative = oppBase - yoBase
            let strokes = signedStroke(relative)
            let strokeColor: Color = relative > 0.001 ? .red : (relative < -0.001 ? .green : Color.white.opacity(0.92))
            let units = "\(resultText(matchManager.unitStakeForIndividual(opponentAlias: opp, segmentOverride: selectedSegment)))u"
            out.append(
                SummaryLine(
                    label: "vs \(opp)",
                    strokesText: strokes,
                    strokesColor: strokeColor,
                    vpText: vp,
                    puttsText: putts,
                    unitsText: units,
                    target: .individual(opp)
                )
            )
        }
        for lane in matchManager.lanes.prefix(3) {
            let rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: selectedSegment)
            guard let last = rows.last else { continue }
            let pres = pressureText(last.openPressures)
            var vp = "\(resultText(last.vueltaAccum)) \(pres)"
            if selectedSegment == "B9" {
                let carry = matchManager.pairCarryResultB9(laneId: lane.id)
                vp += " C\(resultText(carry))"
            }
            let carrier = lane.strokeCarrier ?? "—"
            let strokes = "\(formatStroke(lane.strokes)) \(carrier)"
            let units = "\(resultText(matchManager.unitStakeForPair(laneId: lane.id, segmentOverride: selectedSegment)))u"
            out.append(
                SummaryLine(
                    label: "\(lane.base.joined(separator: "+"))/\(lane.opp.joined(separator: "+"))",
                    strokesText: strokes,
                    strokesColor: Color.white.opacity(0.92),
                    vpText: vp,
                    puttsText: "—",
                    unitsText: units,
                    target: .parejas(lane.id)
                )
            )
        }
        let logs = matchManager.unitLogEntriesForZoom(segmentOverride: selectedSegment, includeIndividual: true, includePair: true)
        if !logs.isEmpty {
            let net = logs.reduce(0) { $0 + $1.units }
            out.append(
                SummaryLine(
                    label: "Unidades",
                    strokesText: "—",
                    strokesColor: Color.white.opacity(0.92),
                    vpText: "\(selectedSegment)",
                    puttsText: "\(logs.count)",
                    unitsText: "\(resultText(net))u",
                    target: .unidades
                )
            )
        }
        return out
    }

    private var unitLogEntries: [UnitLogEntry] {
        switch unitsScopeFilter {
        case "Individual":
            return matchManager.unitLogEntriesForZoom(segmentOverride: selectedSegment, includeIndividual: true, includePair: false)
        case "Pareja":
            return matchManager.unitLogEntriesForZoom(segmentOverride: selectedSegment, includeIndividual: false, includePair: true)
        default:
            return matchManager.unitLogEntriesForZoom(segmentOverride: selectedSegment, includeIndividual: true, includePair: true)
        }
    }

    private var individualSummaryLines: [SummaryLine] {
        summaryLines.filter {
            if case .individual = $0.target { return true }
            return false
        }
    }

    private var pairSummaryLines: [SummaryLine] {
        summaryLines.filter {
            if case .parejas = $0.target { return true }
            return false
        }
    }

    private var unitLine: SummaryLine? {
        summaryLines.first {
            if case .unidades = $0.target { return true }
            return false
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.custom("Playfair Display", size: 14))
            .foregroundColor(clubGold)
    }

    private func pressureText(_ values: [Int]) -> String {
        if values.isEmpty { return "0" }
        return values.map { "\($0)" }.joined(separator: " ")
    }

    private func pressureInfoText(vuelta: Int, pressures: [Int]) -> String {
        "\(resultText(vuelta)) | \(pressureText(pressures))"
    }

    private func resultText(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        return "\(value)"
    }

    @ViewBuilder
    private func gnCell(g: Int, s: Double, n: Double) -> some View {
        let strokeApplied = s > 0.001
        let color: Color = strokeApplied ? .red : .primary
        Text("\(g)/\(formatStroke(n))")
            .font(.caption.monospacedDigit())
            .foregroundColor(color)
            .frame(width: 92, alignment: .leading)
    }

    private func pairGrossCell(ball: PairBallLine, carrierAlias: String?, teamColor: Color) -> some View {
        let totalStroke = ball.individualStrokes + ball.laneStrokes
        let receivesStroke = totalStroke > 0.001
        let strokeText = receivesStroke ? " (\(formatStroke(totalStroke)))" : ""
        return Text("\(ball.gross)\(strokeText)")
            .font(.caption.monospacedDigit())
            .foregroundColor(receivesStroke ? .red : teamColor)
            .frame(width: 58, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
            .background(teamColor.opacity(0.08))
            .cornerRadius(4)
    }

    private func individualTable(opponent: String, rows: [IndividualZoomRow]) -> some View {
        let yoStrokeTotal = rows.reduce(0.0) { $0 + $1.yoStrokes }
        let oppStrokeTotal = rows.reduce(0.0) { $0 + $1.oppStrokes }
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        zoomHeaderCell("H", 26)
                        zoomHeaderCell("Par", 32)
                        zoomHeaderCell("SI", 28)
                        zoomHeaderCell("\(matchManager.yoAlias) S\(formatStroke(yoStrokeTotal)) G/N", 128)
                        zoomHeaderCell("\(opponent) S\(formatStroke(oppStrokeTotal)) G/N", 128)
                        zoomHeaderCell("Res", 36)
                        zoomHeaderCell("U", 18)
                        zoomHeaderCell("Presión (Vta)", 168)
                    }
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            zoomDataCell("\(row.hole)", 26)
                            zoomDataCell("\(row.par)", 32)
                            zoomDataCell("\(row.si)", 28)
                            gnCell(g: row.yoGross, s: row.yoStrokes, n: row.yoNet)
                            gnCell(g: row.oppGross, s: row.oppStrokes, n: row.oppNet)
                            zoomDataCell(resultText(row.result), 36)
                            zoomDataCell(matchManager.unitCountForHole(row.hole) > 0 ? "•" : "", 18)
                            zoomDataCell(pressureInfoText(vuelta: row.vueltaAccum, pressures: row.openPressures), 168)
                        }
                    }
                }
            }
            individualFooter(opponent: opponent, rows: rows)
        }
    }

    private func pairTable(rows: [PairZoomRow]) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    let aliases: [String] = {
                        guard let first = rows.first else { return ["A", "B", "C", "D"] }
                        let left = first.basePlayers.map { $0.alias }
                        let right = first.oppPlayers.map { $0.alias }
                        return left + right
                    }()
                    let strokeTotals = pairStrokeTotals(rows: rows)
                    HStack(spacing: 8) {
                        zoomHeaderCell("H", 26)
                        zoomHeaderCell("Par", 32)
                        zoomHeaderCell("SI", 28)
                        zoomHeaderCell(pairHeaderText(alias: aliases.count > 0 ? aliases[0] : "A", totals: strokeTotals), 74, color: .blue)
                        zoomHeaderCell(pairHeaderText(alias: aliases.count > 1 ? aliases[1] : "B", totals: strokeTotals), 74, color: .blue)
                        zoomHeaderCell(pairHeaderText(alias: aliases.count > 2 ? aliases[2] : "C", totals: strokeTotals), 74, color: .green)
                        zoomHeaderCell(pairHeaderText(alias: aliases.count > 3 ? aliases[3] : "D", totals: strokeTotals), 74, color: .green)
                        zoomHeaderCell("Res", 36)
                        zoomHeaderCell("U", 18)
                        zoomHeaderCell("Presión (Vta)", 168)
                    }
                    ForEach(rows) { row in
                        let left0 = row.basePlayers.count > 0 ? row.basePlayers[0] : PairBallLine(alias: "-", gross: 0, individualStrokes: 0, laneStrokes: 0, net: 0)
                        let left1 = row.basePlayers.count > 1 ? row.basePlayers[1] : PairBallLine(alias: "-", gross: 0, individualStrokes: 0, laneStrokes: 0, net: 0)
                        let right0 = row.oppPlayers.count > 0 ? row.oppPlayers[0] : PairBallLine(alias: "-", gross: 0, individualStrokes: 0, laneStrokes: 0, net: 0)
                        let right1 = row.oppPlayers.count > 1 ? row.oppPlayers[1] : PairBallLine(alias: "-", gross: 0, individualStrokes: 0, laneStrokes: 0, net: 0)
                        HStack(spacing: 8) {
                            zoomDataCell("\(row.hole)", 26)
                            zoomDataCell("\(row.par)", 32)
                            zoomDataCell("\(row.si)", 28)
                            pairGrossCell(ball: left0, carrierAlias: row.carrierAlias, teamColor: .blue)
                            pairGrossCell(ball: left1, carrierAlias: row.carrierAlias, teamColor: .blue)
                            pairGrossCell(ball: right0, carrierAlias: row.carrierAlias, teamColor: .green)
                            pairGrossCell(ball: right1, carrierAlias: row.carrierAlias, teamColor: .green)
                            zoomDataCell(resultText(row.result), 36)
                            zoomDataCell(matchManager.unitCountForHole(row.hole) > 0 ? "•" : "", 18)
                            zoomDataCell(pressureInfoText(vuelta: row.vueltaAccum, pressures: row.openPressures), 168)
                        }
                    }
                }
            }
            pairFooter(rows: rows)
        }
    }

    private func unitsTable(entries: [UnitLogEntry]) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            Picker("VS", selection: $unitsScopeFilter) {
                Text("Todos").tag("Todos")
                Text("Individual").tag("Individual")
                Text("Pareja").tag("Pareja")
            }
            .pickerStyle(.segmented)

            if entries.isEmpty {
                Text("Sin unidades en esta vuelta.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    zoomHeaderCell("H", 30)
                    zoomHeaderCell("Jugador", 72)
                    zoomHeaderCell("Tipo", 78)
                    zoomHeaderCell("VS", 72)
                    zoomHeaderCell("u", 24)
                    zoomHeaderCell("Detalle", 120)
                }
                ForEach(entries) { e in
                    HStack(spacing: 8) {
                        zoomDataCell("\(e.hole)", 30)
                        zoomDataCell(e.player, 72)
                        zoomDataCell(e.type, 78)
                        zoomDataCell(e.vs ?? "—", 72)
                        zoomDataCell(resultText(e.units), 24)
                        zoomDataCell(e.detail ?? "—", 120)
                    }
                }
            }
        }
    }

    private func individualFooter(opponent: String, rows: [IndividualZoomRow]) -> some View {
        guard let last = rows.last else {
            return AnyView(EmptyView())
        }
        let seg = matchManager.segmentForHole(last.hole)
        let yoPutts = matchManager.puttsSplit(alias: matchManager.yoAlias, uptoHole: last.hole)
        let oppPutts = matchManager.puttsSplit(alias: opponent, uptoHole: last.hole)
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("Resumen acumulado (\(seg))")
                    .font(.caption.bold())
                Text("Vuelta: \(resultText(last.vueltaAccum))")
                    .font(.caption.monospacedDigit())
                if seg == "B9" {
                    Text("Carry: \(resultText(matchManager.individualCarryResultB9(opponentAlias: opponent)))")
                        .font(.caption.monospacedDigit())
                    Text("Match: \(resultText(last.matchAccum))")
                        .font(.caption.monospacedDigit())
                }
                Text("Putts 1: F9 \(yoPutts.f9) B9 \(yoPutts.b9) Total \(yoPutts.total)")
                    .font(.caption.monospacedDigit())
                Text("Putts 2: F9 \(oppPutts.f9) B9 \(oppPutts.b9) Total \(oppPutts.total)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundColor(.secondary)
        )
    }

    private func pairFooter(rows: [PairZoomRow]) -> some View {
        guard let last = rows.last else {
            return AnyView(EmptyView())
        }
        let seg = matchManager.segmentForHole(last.hole)
        let carryText: String? = {
            guard seg == "B9",
                  let first = rows.first else { return nil }
            let aliases = Set(first.basePlayers.map(\.alias) + first.oppPlayers.map(\.alias))
            guard let lane = matchManager.lanes.first(where: { Set($0.base + $0.opp) == aliases }) else { return nil }
            return resultText(matchManager.pairCarryResultB9(laneId: lane.id))
        }()
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text("Resumen acumulado (\(seg))")
                    .font(.caption.bold())
                Text("Vuelta: \(resultText(last.vueltaAccum))")
                    .font(.caption.monospacedDigit())
                if seg == "B9" {
                    if let c = carryText {
                        Text("Carry: \(c)")
                            .font(.caption.monospacedDigit())
                    }
                    Text("Match: \(resultText(last.matchAccum))")
                        .font(.caption.monospacedDigit())
                }
            }
            .foregroundColor(.secondary)
        )
    }

    private func headerCell(_ text: String, _ width: CGFloat, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(color)
            .frame(width: width, alignment: .leading)
    }

    private func dataCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundColor(Color.white.opacity(0.92))
            .frame(width: width, alignment: .leading)
    }

    private func strokeCell(_ text: String, _ width: CGFloat, color: Color) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundColor(color)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func carryToggleCell(line: SummaryLine, width: CGFloat) -> some View {
        switch line.target {
        case .individual(let opp):
            let active = matchManager.isIndividualCarryActive(opponentAlias: opp)
            let eligible = matchManager.individualCarryEligibleRequester(opponentAlias: opp)
            Button(active ? "ON" : "OFF") {
                if active {
                    matchManager.clearIndividualCarryRequest(opponentAlias: opp)
                } else if let req = eligible {
                    matchManager.setIndividualCarryRequest(opponentAlias: opp, requesterAlias: req)
                }
            }
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.25) : Color(.secondarySystemBackground).opacity(0.7))
            .cornerRadius(8)
            .disabled(eligible == nil)
            .frame(width: width, alignment: .leading)
        case .parejas(let laneId):
            let active = matchManager.isPairCarryActive(laneId: laneId)
            let eligible = matchManager.pairCarryEligibleRequester(laneId: laneId)
            Button(active ? "ON" : "OFF") {
                if active {
                    matchManager.clearPairCarryRequest(laneId: laneId)
                } else if let req = eligible {
                    matchManager.setPairCarryRequest(laneId: laneId, requesterAlias: req)
                }
            }
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.25) : Color(.secondarySystemBackground).opacity(0.7))
            .cornerRadius(8)
            .disabled(eligible == nil)
            .frame(width: width, alignment: .leading)
        case .unidades:
            Text("—")
                .font(.caption2)
                .frame(width: width, alignment: .leading)
        }
    }

    private func zoomHeaderCell(_ text: String, _ width: CGFloat, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(color)
            .frame(width: width, alignment: .leading)
    }

    private func zoomDataCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundColor(.primary)
            .frame(width: width, alignment: .leading)
    }

    private func zoomNameCell(line: SummaryLine, width: CGFloat) -> some View {
        Button(action: {
            zoomTarget = line.target
        }) {
            HStack(spacing: 4) {
                Text(line.label)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundColor(clubGold)
                    .frame(width: 14, alignment: .trailing)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func formatStroke(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private func signedStroke(_ value: Double) -> String {
        let raw = formatStroke(abs(value))
        if value > 0.001 { return "+\(raw)" }
        if value < -0.001 { return "-\(raw)" }
        return "0"
    }

    private func pairStrokeTotals(rows: [PairZoomRow]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for row in rows {
            for ball in row.basePlayers + row.oppPlayers {
                totals[ball.alias, default: 0] += (ball.individualStrokes + ball.laneStrokes)
            }
        }
        return totals
    }

    private func pairHeaderText(alias: String, totals: [String: Double]) -> String {
        let t = totals[alias] ?? 0
        return "\(alias) S\(formatStroke(t))"
    }


    private func zoomSheetHeader(target: ZoomTarget) -> String {
        let holeText: String = {
            if let h = matchManager.lastHoleForZoom(segment: selectedSegment) {
                return "Hoyo \(h)"
            }
            return "Sin hoyos"
        }()
        switch target {
        case .individual(let opp):
            return "\(selectedSegment) · \(holeText) · \(matchManager.yoAlias) vs \(opp)"
        case .parejas(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else {
                return "\(selectedSegment) · \(holeText) · Pareja"
            }
            let matchup = "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
            let carry = (lane.strokeCarrier?.isEmpty == false) ? " · Lleva \(lane.strokeCarrier!)" : ""
            return "\(selectedSegment) · \(holeText) · \(matchup) · Strokes \(formatStroke(lane.strokes))\(carry)"
        case .unidades:
            return "\(selectedSegment) · \(holeText) · Detalle de Unidades"
        }
    }
}

struct MatchSummaryView: View {
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("Campo", value: matchManager.courseId.isEmpty ? "—" : matchManager.courseId)
            summaryRow("Hoyo salida", value: "\(matchManager.startHole)")
            summaryRow("Jugadores", value: playersSummary)
            summaryRow("Strokes", value: strokesSummary)
            summaryRow("Parejas", value: teamsSummary)
            summaryRow("F9/B9/Match", value: betResultsSummary)
            summaryRow("Unidad", value: unitSummary)
            summaryRow("Apuestas", value: betsSummary)
        }
    }

    private var playersSummary: String {
        if matchManager.players.isEmpty { return "—" }
        return matchManager.players.map { "\($0.alias) (\($0.name))" }.joined(separator: ", ")
    }

    private var strokesSummary: String {
        if matchManager.players.isEmpty { return "—" }
        return matchManager.players.map { player in
            let value = player.strokesVsBase
            return "\(player.alias) \(formatSignedStroke(value))"
        }.joined(separator: ", ")
    }

    private var teamsSummary: String {
        if !matchManager.lanes.isEmpty {
            let lines = matchManager.lanes.map { lane in
                let base = lane.base.joined(separator: "+")
                let opp = lane.opp.joined(separator: "+")
                var line = "\(base) vs \(opp) · Strokes \(formatStroke(lane.strokes))"
                if let carrier = lane.strokeCarrier {
                    line += " · Lleva \(carrier)"
                }
                return line
            }
            return lines.joined(separator: "\n")
        }
        if !matchManager.baseTeamAliases.isEmpty {
            let base = matchManager.baseTeamAliases.joined(separator: "+")
            let opp = matchManager.players.map { $0.alias }.filter { !matchManager.baseTeamAliases.contains($0) }
            let oppText = opp.isEmpty ? "—" : opp.joined(separator: "+")
            return "\(base) vs \(oppText)"
        }
        return "—"
    }

    private var unitSummary: String {
        if matchManager.vueltaValue <= 0 { return "—" }
        return "Vuelta \(matchManager.vueltaValue) · Unidad \(matchManager.unitValue)"
    }

    private var betResultsSummary: String {
        let ind = matchManager.individualBetSummaryLines()
        let pair = matchManager.pairBetSummaryLines()
        let oyesInd = matchManager.oyesIndividualSummaryLines()
        let oyesPair = matchManager.oyesPairSummaryLines()
        var sections: [String] = []
        if !ind.isEmpty {
            sections.append("Individuales:\n" + ind.joined(separator: "\n"))
        }
        if !pair.isEmpty {
            sections.append("Parejas:\n" + pair.joined(separator: "\n"))
        }
        if !oyesInd.isEmpty {
            sections.append("OYES Individual:\n" + oyesInd.joined(separator: "\n"))
        }
        if !oyesPair.isEmpty {
            sections.append("OYES Parejas:\n" + oyesPair.joined(separator: "\n"))
        }
        if sections.isEmpty { return "—" }
        return sections.joined(separator: "\n")
    }

    private var betsSummary: String {
        if matchManager.activeBets.isEmpty { return "—" }
        return matchManager.activeBets.map { bet in
            let tag = bet.tagOverride?.isEmpty == false ? bet.tagOverride! : "\(bet.definition.tag)-ALIAS"
            return "\(bet.definition.name) (\(tag))"
        }.joined(separator: ", ")
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatStroke(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private func formatSignedStroke(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + formatStroke(value)
    }
}

struct CardView: View {
    @ObservedObject var matchManager: MatchManager
    let entities: ScoreEntities
    let transcript: String
    
    var body: some View {
        let holeNumber = entities.hoyo ?? 0
        let hole = matchManager.getHole(holeNumber)
        let par = hole?.par ?? 0
        let si = hole?.si ?? 0
        let segment = matchManager.segmentForHole(holeNumber)
        let scores = entities.scores ?? []
        
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(holeNumber > 0 ? "Hoyo \(holeNumber)" : "Hoyo —")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !segment.isEmpty {
                    Text(segment)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(6)
                }
                Text("SI \(si)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
            }
            
            if !transcript.isEmpty {
                Text("“\(transcript)”")
                    .font(.subheadline)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    statBox(title: "Hoyo", value: holeNumber > 0 ? "\(holeNumber)" : "—")
                    if par > 0 { statBox(title: "Par", value: "\(par)") }
                    ForEach(scores, id: \.jugador) { s in
                        statBox(title: s.jugador.uppercased(), value: "\(s.gross)")
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func statBox(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(width: 80)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .cornerRadius(10)
    }
}

struct ScorecardGrid: View {
    @ObservedObject var matchManager: MatchManager
    
    var body: some View {
        let holesToShow = currentNineHoles(start: matchManager.startHole)
        
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 64)
                    ForEach(matchManager.players) { player in
                        VStack(spacing: 1) {
                            ForEach(Array(player.alias.uppercased()), id: \.self) { ch in
                                Text(String(ch))
                            }
                        }
                        .font(.caption2.weight(.semibold))
                        .frame(width: 20, height: 58)
                        .fixedSize()
                        .frame(minWidth: 58)
                        .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                
                ForEach(holesToShow, id: \.self) { holeNumber in
                    ScorecardRow(matchManager: matchManager, holeNumber: holeNumber)
                }
            }
            .cornerRadius(12)
        }
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
}

struct ScorecardRow: View {
    @ObservedObject var matchManager: MatchManager
    let holeNumber: Int
    
    var body: some View {
        HStack(spacing: 0) {
            let hole = matchManager.getHole(holeNumber)
            let par = hole?.par ?? 4
            let si = hole?.si ?? 0
            VStack(spacing: 2) {
                Text("\(holeNumber)")
                Text("\(par)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(parColor(par))
                Text("\(si)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(siColor(si))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(siColor(si).opacity(0.15))
                    .cornerRadius(4)
            }
            .frame(width: 64)
            .font(.caption2.weight(.semibold))
            
            ForEach(matchManager.players) { player in
                let score = matchManager.getScore(hole: holeNumber, player: player.alias)
                let putts = matchManager.getPutts(hole: holeNumber, player: player.alias)
                let winsIndUnit = matchManager.hasIndividualUnitWin(hole: holeNumber, alias: player.alias)
                let winsPairUnit = matchManager.hasPairUnitWin(hole: holeNumber, alias: player.alias)
                
                VStack(spacing: 2) {
                    Text(score > 0 ? "\(score)" : "—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(scoreColor(score: score, par: matchManager.getHole(holeNumber)?.par ?? 4))
                    
                    if putts > 0 {
                        Text("(\(putts))")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .opacity(score > 0 ? 1 : 0.5)
                    }
                    HStack(spacing: 3) {
                        if winsIndUnit {
                            Text("I")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                        if winsPairUnit {
                            Text("P")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                    }
                }
                .frame(minWidth: 58)
                .padding(.vertical, 2)
                .background((winsIndUnit || winsPairUnit) ? Color.yellow.opacity(0.12) : Color.clear)
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 8)
        .background(holeNumber % 2 == 0 ? Color(.systemBackground) : Color(.secondarySystemBackground))
    }
    
    private func scoreColor(score: Int, par: Int) -> Color {
        if score == 0 { return .secondary }
        if score < par { return .green }
        if score == par { return .primary }
        return .red
    }
    
    private func siColor(_ si: Int) -> Color {
        let clamped = max(1, min(18, si))
        let t = Double(clamped - 1) / 17.0
        let r = 1.0 - t
        let g = t
        return Color(red: r, green: g, blue: 0)
    }
    
    private func parColor(_ par: Int) -> Color {
        switch par {
        case 3: return .green
        case 4: return .orange
        case 5: return .red
        default: return .secondary
        }
    }
}
