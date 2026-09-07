import SwiftUI

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
    private var utils: TextUtils { TextUtils(matchManager: matchManager) }

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
                                Button("Omitir") { advanceStep() }
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
                if setupRecorder.isRecording { _ = setupRecorder.stopRecording() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if stepIndex > 0 {
                        Button("Atrás") { stepIndex = max(0, stepIndex - 1) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(stepIndex == SetupStep.allCases.count - 1 ? "Cerrar" : "Siguiente") {
                        if stepIndex == SetupStep.allCases.count - 1 { dismiss() } else { advanceStep() }
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
                            let nameCount = utils.extractNamesFromText(cleaned).count
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
                        if TextUtils.containsNoiseDictation(cleaned.lowercased()) {
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
            let names = utils.extractNamesFromText(text).filter { utils.isValidPlayerName($0) }
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
                            if matchManager.addPlayer(name: name) { added.append(name) }
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
            if !unknown.isEmpty { setupStatus = suggestionMessage(for: unknown); return }
            let updates = utils.parseStrokeUpdates(text)
            if updates.isEmpty { setupStatus = "❌ No entendí strokes. Repite."; return }
            for u in updates {
                if u.alias == matchManager.yoAlias { continue }
                matchManager.setStrokesVsBase(alias: u.alias, value: u.value)
            }
            setupStatus = "✅ Strokes actualizados"
            advanceStep()
        case .parejas:
            if matchManager.players.count < 4 { setupStatus = "❌ Faltan jugadores para parejas."; return }
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
        if setupRecorder.isRecording { _ = setupRecorder.stopRecording() }
        if stepIndex < SetupStep.allCases.count - 1 { stepIndex += 1 }
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
            if normalized.contains(id) || (!name.isEmpty && normalized.contains(name)) { return course }
        }
        return nil
    }

    private func dedupeNames(_ names: [String]) -> (unique: [String], duplicates: [String], existing: [String]) {
        var seen = Set<String>(); var unique: [String] = []; var duplicates: [String] = []; var existing: [String] = []
        for name in names {
            let key = matchManager.normalizePlayerKey(name).lowercased()
            if seen.contains(key) { duplicates.append(name); continue }
            seen.insert(key)
            if matchManager.normalizeAlias(name) != nil { existing.append(name); continue }
            unique.append(name)
        }
        return (unique, duplicates, existing)
    }

    private func unknownNames(in text: String) -> [String] {
        let candidates = utils.extractNamesFromText(text)
        if candidates.isEmpty { return [] }
        return candidates.filter { matchManager.normalizeAlias($0) == nil && utils.aliasesMatchedByName($0).isEmpty }
    }

    private func suggestionMessage(for names: [String]) -> String {
        let suggestions = names.map { name -> String in
            let candidates = matchManager.fuzzyCandidates(for: name, limit: 2)
            return candidates.first.map { "¿Quisiste decir \($0.alias)?" } ?? "Nombre no válido: \(name)"
        }
        return "❌ " + suggestions.joined(separator: " ")
    }

    private func applyPairsFromText(_ text: String) -> (ok: Bool, message: String?) {
        let trimmed = TextUtils.stripStrokeClause(text)
        let unknown = unknownNames(in: trimmed)
        if !unknown.isEmpty { return (false, suggestionMessage(for: unknown)) }
        if let split = TextUtils.splitMatchup(trimmed) {
            var base = utils.extractAliasesPreferNames(split.left)
            let opp = utils.extractAliasesPreferNames(split.right)
            let t = matchManager.normalizePlayerKey(split.left).lowercased()
            if t.contains("yo") || t.contains("mi") || t.contains("mis") {
                if !base.contains(matchManager.yoAlias) { base.insert(matchManager.yoAlias, at: 0) }
            }
            if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
            if !TextUtils.disjointTeams(base, opp) { return (false, "❌ Un jugador aparece en ambos lados.") }
            return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil)
        }
        let ordered = utils.orderedAliasesFromText(trimmed)
        if ordered.count == 4 {
            let base = Array(ordered.prefix(2))
            let opp = Array(ordered.suffix(2))
            if TextUtils.disjointTeams(base, opp) { return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil) }
        }
        var base: [String] = []
        var opp: [String] = []
        if let after = TextUtils.substringAfterPattern(trimmed, pattern: #"(?i)\bcompañeros?\b\s*(son|es|:)?\s*"#) {
            base = utils.extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = TextUtils.substringAfterPattern(trimmed, pattern: #"(?i)\bcompaneros?\b\s*(son|es|:)?\s*"#) {
            base = utils.extractAliasesPreferNames(after)
        }
        if base.isEmpty, let after = TextUtils.substringAfterPattern(trimmed, pattern: #"(?i)\bcon\b"#) {
            base = utils.extractAliasesPreferNames(after)
        }
        if let oppAfter = TextUtils.substringAfterPattern(trimmed, pattern: #"(?i)\boponentes?\b\s*(son|es|:)?\s*"#) {
            opp = utils.extractAliasesPreferNames(oppAfter)
        }
        let t = matchManager.normalizePlayerKey(trimmed).lowercased()
        if (t.contains("yo") || t.contains("mi") || t.contains("mis")) && !base.contains(matchManager.yoAlias) {
            base.insert(matchManager.yoAlias, at: 0)
        }
        if base.isEmpty { base = utils.extractAliasesPreferNames(trimmed) }
        if opp.isEmpty { opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) } }
        if base.count < 2 || opp.count < 2 { return (false, "❌ Faltan jugadores en una pareja.") }
        if !TextUtils.disjointTeams(base, opp) { return (false, "❌ Un jugador aparece en ambos lados.") }
        return (matchManager.setBaseTeam(base, opponentsOverride: opp), nil)
    }

    private func applyLaneStrokesFromText(_ text: String) -> (ok: Bool, message: String?) {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        let unknown = unknownNames(in: text)
        if !unknown.isEmpty { return (false, suggestionMessage(for: unknown)) }
        if let split = TextUtils.splitMatchup(text) {
            let base = utils.extractAliasesPreferNames(split.left)
            let opp = utils.extractAliasesPreferNames(split.right)
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
            if let carrier = utils.extractAliasesPreferNames(text).first, matchManager.lanes.count > 0 {
                matchManager.setLaneCarrierForAlias(carrier)
                return (true, nil)
            }
        }
        return (false, "❌ No entendí strokes de pareja.")
    }

    private func applyCarrierFromText(_ text: String, base: [String]?, opp: [String]?) {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let b = base, let o = opp, !b.isEmpty, !o.isEmpty else { return }
        let orderedAliases = utils.orderedAliasesFromText(text)
        let receiverWords = ["recibe","recibo","reciben","recibir","lleva","llevo","llevas","llevan"]
        let giverWords = ["da","doy","das","dan","damos"]
        let receiverMode = TextUtils.hasAnyWord(t, receiverWords) ||
            t.contains("le dan") || t.contains("les dan") || t.contains("nos dan") ||
            t.contains("le llevan") || t.contains("les llevan") || t.contains("nos llevan")
        let giverMode = !receiverMode && (TextUtils.hasAnyWord(t, giverWords) || t.contains("le da") || t.contains("les da") || t.contains("nos da"))

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

        if let carrier = carrier { matchManager.setLaneCarrierForMatch(base: b, opp: o, carrier: carrier) }

        if let strokes = TextUtils.extractFirstNumberDecimal(from: text) {
            let hasStrokeWord = t.contains("stroke") || t.contains("strokes") || t.contains("golpe") || t.contains("golpes")
            if receiverMode || giverMode || hasStrokeWord || t.contains("lleva") || t.contains("llev") {
                matchManager.setLaneStrokesForMatch(base: b, opp: o, value: strokes)
            }
        }
    }
}
