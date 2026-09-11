import SwiftUI
import AVFoundation
import Combine
import NaturalLanguage
import AppIntents

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
    @State private var showIntentTestSheet = false
    
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
        .sheet(isPresented: $showIntentTestSheet) {
            IntentTestView()
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
                        icon: "waveform.badge.plus",
                        title: "Anotar",
                        action: { showIntentTestSheet = true }
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
