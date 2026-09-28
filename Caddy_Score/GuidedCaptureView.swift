import SwiftUI
import AVFoundation
import Speech
import Combine

// MARK: - Corpus

private struct CorpusTurn: Codable {
    let seq: Int; let question: String; let answer: String
}
private struct CorpusSession: Codable {
    let date: String; let players: [String]; let turns: [CorpusTurn]
}

// MARK: - Step queue

private enum GStep: Identifiable {
    case strokes(hole: Int, alias: String, name: String)
    case putts(hole: Int, alias: String, name: String)
    case oyes(hole: Int, par: Int)
    case confirm

    var id: String {
        switch self {
        case .strokes(let h, let a, _): return "str-\(h)-\(a)"
        case .putts(let h, let a, _):   return "ptt-\(h)-\(a)"
        case .oyes(let h, _):           return "oyes-\(h)"
        case .confirm:                   return "confirm"
        }
    }
}

// MARK: - VoiceGuide (TTS + live STT)

class VoiceGuide: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var partialText = ""

    var onNumber: ((Int) -> Void)?
    var onSkip: (() -> Void)?
    var onAccept: (() -> Void)?
    var currentPar: Int = 4

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private var recRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recTask: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    // MARK: - STT (manual trigger — user taps mic button)

    func startListening() {
        guard !engine.isRunning else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            guard speechStatus == .authorized else { return }
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    guard granted else { return }
                    // Background thread: AVAudioSession.setActive can block the main thread on iOS 26
                    DispatchQueue.global(qos: .userInitiated).async { self?.setupAndStart() }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    guard granted else { return }
                    DispatchQueue.global(qos: .userInitiated).async { self?.setupAndStart() }
                }
            }
        }
    }

    private func setupAndStart() {
        let session = AVAudioSession.sharedInstance()
        do {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)   // may block; safe on background thread
        } catch { return }

        guard let rec = recognizer, rec.isAvailable else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        recRequest = req

        recTask = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.partialText = text }
                if self.isSkip(text)   { self.stopListening(); DispatchQueue.main.async { self.onSkip?() };    return }
                if self.isAccept(text) { self.stopListening(); DispatchQueue.main.async { self.onAccept?() };  return }
                if let n = self.parseNumber(text) { self.stopListening(); DispatchQueue.main.async { self.onNumber?(n) }; return }
            }
            if error != nil { self.stopListening() }
        }

        // inputNode is safe on background once session is active and mic permission is granted
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            recRequest?.endAudio(); recTask?.cancel(); recRequest = nil; recTask = nil
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.recRequest?.append(buf)
        }
        engine.prepare()
        do {
            try engine.start()
            DispatchQueue.main.async { self.isListening = true; self.partialText = "" }
        } catch {
            inputNode.removeTap(onBus: 0)
            recRequest?.endAudio(); recTask?.cancel(); recRequest = nil; recTask = nil
        }
    }

    func stopListening() {
        guard engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        recRequest?.endAudio()
        recTask?.cancel()
        recRequest = nil
        recTask = nil
        DispatchQueue.main.async { self.isListening = false; self.partialText = "" }
    }

    func stopAll() {
        stopListening()
    }

    // MARK: - Parsing

    func parseNumber(_ text: String) -> Int? {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        let parts = t.components(separatedBy: .whitespaces)

        for p in parts { if let n = Int(p) { return n } }

        let map: [String: Int] = [
            "cero": 0, "un": 1, "uno": 1, "una": 1,
            "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
            "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
            "diez": 10, "once": 11, "doce": 12,
            "trece": 13, "catorce": 14, "quince": 15,
            "dieciséis": 16, "dieciseis": 16,
            "diecisiete": 17, "dieciocho": 18
        ]
        for p in parts { if let n = map[p] { return n } }

        // Slang mexicano del CGM (valor absoluto)
        if t.contains("lorena") { return 8 }

        // Términos de golf relativos al par del hoyo actual
        if t.contains("hoyo en uno") || t.contains("ace") || t.contains("se fue") { return 1 }
        if t.contains("albatros") || t.contains("double eagle") { return max(1, currentPar - 3) }
        if t.contains("águila") || t.contains("aguila") || t.contains("eagle") { return max(1, currentPar - 2) }
        if t.contains("pájaro") || t.contains("pajaro") || t.contains("birdie") { return currentPar - 1 }
        if t.contains("zopilote") { return currentPar + 2 }
        if t.contains("doble bogey") || (t.contains("doble") && t.contains("bogey")) { return currentPar + 2 }
        if t.contains("triple bogey") || (t.contains("triple") && t.contains("bogey")) { return currentPar + 3 }
        if t.contains("bogey") { return currentPar + 1 }
        if t.contains("par") { return currentPar }

        return nil
    }

    private func isSkip(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["saltar", "skip", "no sé", "no se", "siguiente", "después", "no tengo"].contains { t.contains($0) }
    }

    private func isAccept(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["acepto", "aceptar", "correcto", "confirmo", "listo", "sí listo", "si listo"].contains { t.contains($0) }
    }
}

// MARK: - Main View

struct GuidedCaptureView: View {
    @ObservedObject var matchManager: MatchManager
    var targetHole: Int? = nil
    var forceAlias: String? = nil   // corrección: sobreescribe score aunque ya exista
    @Environment(\.dismiss) private var dismiss

    @StateObject private var voice = VoiceGuide()

    @State private var steps: [GStep] = []
    @State private var stepIdx = 0
    @State private var done = false

    @State private var numInput = ""          // still used by voice fallback
    @FocusState private var numFieldFocused: Bool
    @State private var stepperScore: Int = 4  // manual score stepper value
    @State private var stepperPutts: Int = 2  // manual putts stepper value
    @State private var oyesRanks: [String: Int] = [:]
    @State private var oyesDupError = false

    @State private var pendingStrokes: [String: [Int: Int]] = [:]
    @State private var pendingPutts:   [String: [Int: Int]] = [:]
    @State private var log: [(q: String, a: String)] = []

    private var puttsBetActive: Bool { true }
    private var currentStep: GStep? { steps.indices.contains(stepIdx) ? steps[stepIdx] : nil }

    private var captureTitle: String {
        guard let step = currentStep else { return "Guided Caddy" }
        switch step {
        case .strokes(let h, _, _), .putts(let h, _, _), .oyes(let h, _): return "Hoyo \(h)"
        case .confirm: return "Confirmar"
        }
    }

    private var pendingNotice: String? {
        let audited = HoleAudit.playedHoles(manager: matchManager)
        let incomplete = audited.filter { !$0.missingScores.isEmpty }
        guard !incomplete.isEmpty else { return nil }
        let total = incomplete.reduce(0) { $0 + $1.missingScores.count }
        let holes = incomplete.map { "H\($0.hole)" }.joined(separator: ", ")
        return "\(total) score(s) sin registrar: \(holes)"
    }

    private struct SaveRow: Identifiable {
        let id: String; let alias: String; let hole: Int; let strokes: Int; let putts: Int
    }
    private var saveRows: [SaveRow] {
        pendingStrokes
            .sorted { $0.key < $1.key }
            .flatMap { alias, holeMap in
                holeMap.sorted { $0.key < $1.key }.map { hole, strokes in
                    SaveRow(id: "\(alias)-\(hole)", alias: alias, hole: hole,
                            strokes: strokes, putts: pendingPutts[alias]?[hole] ?? 0)
                }
            }
    }

    // Último hoyo con todos los jugadores anotados — contexto para el caddy
    private struct LastHolePreview {
        let hole: Int; let par: Int
        let scores: [(alias: String, score: Int, vsPar: Int)]
    }
    private var lastHolePreview: LastHolePreview? {
        let played = HoleAudit.playedHoles(manager: matchManager)
        guard let last = played.last(where: { $0.missingScores.isEmpty }) else { return nil }
        let par = matchManager.getHole(last.hole)?.par ?? 4
        let scores: [(alias: String, score: Int, vsPar: Int)] = matchManager.players.compactMap {
            let s = matchManager.getScore(hole: last.hole, player: $0.alias)
            guard s > 0 else { return nil }
            return ($0.alias, s, s - par)
        }
        guard !scores.isEmpty else { return nil }
        return LastHolePreview(hole: last.hole, par: par, scores: scores)
    }

    private func vsParColor(_ vsPar: Int) -> Color {
        switch vsPar {
        case ..<(-1): return Color(red: 0.77, green: 0.12, blue: 0.12)
        case -1:      return Color(red: 0.88, green: 0.19, blue: 0.19)
        case 0:       return Color(red: 0.11, green: 0.48, blue: 0.24)
        case 1:       return .primary
        default:      return .secondary
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                chatArea
                voiceBar
                Divider()
                inputArea
            }
            .navigationTitle(captureTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { voice.stopAll(); dismiss() }
                }
            }
            .onAppear {
                buildQueue()
                voice.onNumber = { [self] n in handleNumber(n) }
                voice.onSkip   = { [self] in skipCurrent() }
                voice.onAccept = { [self] in
                    if case .confirm = currentStep { applyAll() }
                }
                updateVoicePar()
                // Auto-arrancar escucha al abrir el sheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    voice.startListening()
                }
            }
            .onChange(of: stepIdx) { _, _ in
                updateVoicePar()
                if let step = currentStep {
                    syncSteppers(step: step)
                    // Auto-reiniciar escucha para el siguiente step
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        voice.startListening()
                    }
                }
            }
            .onDisappear { voice.stopAll() }
        }
    }

    // MARK: - Chat

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let prev = lastHolePreview {
                        lastHoleCard(prev)
                    }
                    if let notice = pendingNotice {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(notice).font(.caption).foregroundColor(.orange)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.10))
                        .cornerRadius(8)
                    }
                    ForEach(log.indices, id: \.self) { i in
                        logBubble(log[i])
                    }
                    if let step = currentStep {
                        activeBubble(step).id("active")
                    }
                    if done { successBubble.id("done") }
                }
                .padding(16)
            }
            .onChange(of: stepIdx) { _, _ in
                withAnimation { proxy.scrollTo("active", anchor: .bottom) }
            }
            .onChange(of: done) { _, _ in
                withAnimation { proxy.scrollTo("done", anchor: .bottom) }
            }
        }
    }

    private func lastHoleCard(_ prev: LastHolePreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("H\(prev.hole)").font(.caption.bold()).foregroundColor(.secondary)
                Text("· par \(prev.par)").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("último anotado").font(.caption2).foregroundColor(Color(.tertiaryLabel))
            }
            HStack(spacing: 12) {
                ForEach(prev.scores, id: \.alias) { item in
                    VStack(spacing: 2) {
                        Text(item.alias)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("\(item.score)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(vsParColor(item.vsPar))
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private func logBubble(_ e: (q: String, a: String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.q).font(.caption).foregroundColor(.secondary)
            Text(e.a)
                .font(.subheadline.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
        }
    }

    @ViewBuilder
    private func activeBubble(_ step: GStep) -> some View {
        if case .confirm = step {
            confirmPreviewBubble
        } else {
            Text(label(for: step))
                .font(.subheadline.bold())
                .padding(12)
                .background(Color.blue.opacity(0.13))
                .cornerRadius(12)
        }
    }

    private var confirmPreviewBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Guardar:").font(.caption.bold()).foregroundColor(.secondary)
            if saveRows.isEmpty {
                Text("Sin cambios nuevos").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(saveRows) { row in
                    HStack {
                        Text("H\(row.hole) · \(row.alias)").font(.subheadline.bold())
                        Spacer()
                        Text("\(row.strokes)\(row.putts > 0 ? "  ·  \(row.putts)P" : "")")
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
            Divider()
            Text("¿Confirmar?").font(.caption).foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.green.opacity(0.10))
        .cornerRadius(12)
    }

    private var successBubble: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48)).foregroundColor(.green)
                Text("Tarjeta actualizada").font(.title3.bold())
            }
            Spacer()
        }
        .padding(.top, 24)
    }

    // MARK: - Voice bar

    private var voiceBar: some View {
        HStack(spacing: 10) {
            if voice.isListening {
                Image(systemName: "mic.fill").foregroundColor(.red)
                Text(voice.partialText.isEmpty ? "Escuchando…" : "\"\(voice.partialText)\"")
                    .font(.caption)
                    .foregroundColor(voice.partialText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            } else {
                Image(systemName: "mic.slash").foregroundColor(.secondary)
                Text("Toca mic o escribe abajo").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            // Manual mic toggle
            Button {
                if voice.isListening { voice.stopListening() }
                else { voice.startListening() }
            } label: {
                Image(systemName: voice.isListening ? "mic.fill" : "mic")
                    .padding(8)
                    .background(voice.isListening ? Color.red.opacity(0.12) : Color.clear)
                    .clipShape(Circle())
                    .foregroundColor(voice.isListening ? .red : .primary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Input area

    @ViewBuilder
    private var inputArea: some View {
        if done { EmptyView() }
        else if let step = currentStep {
            switch step {
            case .strokes, .putts:
                numericBar(step: step)
            case .oyes(let h, _):
                oyesBar(hole: h)
            case .confirm:
                confirmBar
            }
        }
    }

    // MARK: - Dual stepper bar (Score + Putts side by side)

    private func numericBar(step: GStep) -> some View {
        let hole: Int = {
            switch step { case .strokes(let h, _, _), .putts(let h, _, _): return h; default: return 1 }
        }()
        let par = matchManager.getHole(hole)?.par ?? 4
        let isPuttsStep: Bool = { if case .putts = step { return true }; return false }()
        let alias: String = {
            switch step { case .strokes(_, let a, _), .putts(_, let a, _): return a; default: return "" }
        }()
        let scoreVsPar = stepperScore - par

        return VStack(spacing: 0) {
            // — Steppers row —
            HStack(spacing: 0) {
                if !isPuttsStep {
                    // Score column
                    stepperColumn(
                        label: "Score",
                        value: stepperScore,
                        color: vsParColor(scoreVsPar),
                        range: 1...15,
                        onDecrement: { stepperScore = max(1, stepperScore - 1) },
                        onIncrement: { stepperScore = min(15, stepperScore + 1) }
                    )
                    Divider().frame(height: 120)
                }
                // Putts column
                stepperColumn(
                    label: "Putts",
                    value: stepperPutts,
                    color: .primary,
                    range: 0...6,
                    onDecrement: { stepperPutts = max(0, stepperPutts - 1) },
                    onIncrement: { stepperPutts = min(6, stepperPutts + 1) }
                )
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))

            // — Bottom row: Skip + Enter —
            HStack(spacing: 12) {
                Button("Saltar") { skipCurrent() }
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)

                Button {
                    submitStepper(step: step, alias: alias, hole: hole)
                } label: {
                    Text("Guardar")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(red: 0.122, green: 0.239, blue: 0.169))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
        }
        .onAppear { syncSteppers(step: step) }
    }

    private func stepperColumn(
        label: String,
        value: Int,
        color: Color,
        range: ClosedRange<Int>,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .kerning(0.5)

            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }

            Text("\(value)")
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .frame(minWidth: 52)
                .animation(.easeInOut(duration: 0.12), value: value)

            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            .disabled(value <= range.lowerBound)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private func syncSteppers(step: GStep) {
        switch step {
        case .strokes(let h, let a, _):
            let par = matchManager.getHole(h)?.par ?? 4
            stepperScore = pendingStrokes[a]?[h] ?? par
            stepperPutts = pendingPutts[a]?[h] ?? 2
        case .putts(let h, let a, _):
            stepperPutts = pendingPutts[a]?[h] ?? 2
        default: break
        }
    }

    private func submitStepper(step: GStep, alias: String, hole: Int) {
        switch step {
        case .strokes:
            pendingStrokes[alias, default: [:]][hole] = stepperScore
            pendingPutts[alias, default: [:]][hole] = stepperPutts
            log.append((q: label(for: step), a: "\(stepperScore)G · \(stepperPutts)P"))
            advance()
            // Skip the immediately-following putts step for the same hole+player
            if let next = currentStep, case .putts(let nh, let na, _) = next, nh == hole, na == alias {
                advance()
            }
        case .putts:
            pendingPutts[alias, default: [:]][hole] = stepperPutts
            log.append((q: label(for: step), a: "\(stepperPutts) putts"))
            advance()
        default: break
        }
    }

    private func oyesBar(hole: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if oyesDupError {
                Text("Sin posiciones duplicadas").font(.caption).foregroundColor(.red)
            }
            ForEach(matchManager.players) { player in
                HStack {
                    Text(player.alias).font(.caption.bold()).frame(width: 40, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { oyesRanks[player.alias] ?? 0 },
                        set: { v in oyesRanks[player.alias] = v; oyesDupError = false }
                    )) {
                        Text("—").tag(0)
                        ForEach(matchManager.players.isEmpty ? [] : Array(1...matchManager.players.count), id: \.self) { r in
                            Text("\(r)°").tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            HStack {
                Button("Guardar Oyes") { submitOyes(hole: hole) }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Saltar") { oyesRanks = [:]; skipCurrent() }
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    private var confirmBar: some View {
        HStack(spacing: 20) {
            Button("Aceptar") { applyAll() }
                .buttonStyle(.borderedProminent)
            Button("Reiniciar") {
                stepIdx = 0; log = []; numInput = ""
                pendingStrokes = [:]; pendingPutts = [:]
            }
            .foregroundColor(.orange)
        }
        .padding()
    }

    // MARK: - Queue builder

    private func buildQueue() {
        var q: [GStep] = []
        let audited = HoleAudit.playedHoles(manager: matchManager)

        if let target = targetHole {
            let par = matchManager.getHole(target)?.par ?? 4
            let status = audited.first { $0.hole == target }
            let allAliases = matchManager.players.map { $0.alias }
            let missScores = status?.missingScores ?? allAliases
            let missPutts  = puttsBetActive ? (status?.missingPutts ?? []) : []
            for alias in missScores {
                q.append(.strokes(hole: target, alias: alias, name: displayName(alias)))
                if puttsBetActive { q.append(.putts(hole: target, alias: alias, name: displayName(alias))) }
            }
            for alias in missPutts { q.append(.putts(hole: target, alias: alias, name: displayName(alias))) }
            if par == 3 && matchManager.oyesRanksByHole[target] == nil {
                q.append(.oyes(hole: target, par: par))
            }
        } else {
            for status in audited {
                for alias in status.missingScores {
                    q.append(.strokes(hole: status.hole, alias: alias, name: displayName(alias)))
                    if puttsBetActive { q.append(.putts(hole: status.hole, alias: alias, name: displayName(alias))) }
                }
                if puttsBetActive {
                    for alias in status.missingPutts {
                        q.append(.putts(hole: status.hole, alias: alias, name: displayName(alias)))
                    }
                }
                if status.par == 3 && matchManager.oyesRanksByHole[status.hole] == nil {
                    q.append(.oyes(hole: status.hole, par: status.par))
                }
            }
            let nextHole = matchManager.expectedNextHole()
            let nextPar  = matchManager.getHole(nextHole)?.par ?? 4
            for player in matchManager.players {
                if matchManager.getScore(hole: nextHole, player: player.alias) == 0 {
                    q.append(.strokes(hole: nextHole, alias: player.alias, name: player.name))
                    if puttsBetActive { q.append(.putts(hole: nextHole, alias: player.alias, name: player.name)) }
                }
            }
            if nextPar == 3 && matchManager.oyesRanksByHole[nextHole] == nil {
                q.append(.oyes(hole: nextHole, par: nextPar))
            }
        }

        if q.isEmpty { done = true; return }
        q.append(.confirm)
        steps = q
    }

    // MARK: - Handlers

    private func handleNumber(_ n: Int) {
        guard let step = currentStep else { return }
        switch step {
        case .strokes(let h, let a, _):
            pendingStrokes[a, default: [:]][h] = n
            stepperScore = n
            log.append((q: label(for: step), a: "\(n) golpes"))
        case .putts(let h, let a, _):
            pendingPutts[a, default: [:]][h] = n
            stepperPutts = n
            log.append((q: label(for: step), a: "\(n) putts"))
        default: break
        }
        advance()
    }

    private func submitTyped(step: GStep) {
        guard let n = Int(numInput.trimmingCharacters(in: .whitespaces)) else { return }
        numFieldFocused = false   // dismiss keyboard
        numInput = ""
        handleNumber(n)
    }

    private func submitOyes(hole: Int) {
        let assigned = oyesRanks.values.filter { $0 > 0 }
        guard Set(assigned).count == assigned.count else { oyesDupError = true; return }
        let par = matchManager.getHole(hole)?.par ?? 3
        let summary = oyesRanks.filter { $0.value > 0 }
            .sorted { $0.value < $1.value }
            .map { "\($0.key):\($0.value)°" }.joined(separator: " ")
        log.append((q: label(for: .oyes(hole: hole, par: par)), a: summary.isEmpty ? "—" : summary))
        var ranks: [String: Int] = [:]
        for (alias, rank) in oyesRanks where rank > 0 { ranks[alias] = rank }
        if !ranks.isEmpty { matchManager.oyesRanksByHole[hole] = ranks }
        oyesRanks = [:]
        advance()
    }

    private func skipCurrent() {
        if let step = currentStep { log.append((q: label(for: step), a: "⚠ pendiente")) }
        advance()
    }

    private func advance() {
        stepIdx += 1
        numInput = ""
        if stepIdx >= steps.count { done = true; return }
    }

    private func applyAll() {
        voice.stopAll()
        for (alias, holeMap) in pendingStrokes {
            for (hole, strokes) in holeMap {
                let putts = pendingPutts[alias]?[hole] ?? 0
                matchManager.applyHoleEntry(HoleEntryData(
                    hole_number: hole, player_alias: alias,
                    strokes: strokes, putts: putts, units: nil, tags: nil
                ))
                // Espejo a ScoreManager (persistencia real) — sin esto, dictar
                // varios hoyos y que la app se cierre antes de "Cerrar Ronda" pierde todo.
                _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(
                    player: alias, hole: hole, strokes: strokes, putts: putts
                ))
            }
        }
        saveCorpus()

        // Reset state and rebuild queue for next hole
        pendingStrokes = [:]
        pendingPutts   = [:]
        log            = []
        stepIdx        = 0
        done           = false
        oyesRanks      = [:]
        oyesDupError   = false
        buildQueue()

        // buildQueue sets done=true when there's nothing left to capture
        if done {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
        }
    }

    // MARK: - Helpers

    private func label(for step: GStep) -> String {
        switch step {
        case .strokes(let h, let a, let n):
            let par = matchManager.getHole(h)?.par ?? 4
            let stroke = playerGetsStroke(alias: a, hole: h) ? " ⬇" : ""
            return "H\(h) · par \(par)\(stroke) — ¿Golpes de \(n)?"
        case .putts(let h, _, let n):
            return "H\(h) — ¿Putts de \(n)? [P]"
        case .oyes(let h, _):
            return "H\(h) (par 3) — Oyes: posición 1 a \(matchManager.players.count)"
        case .confirm:
            return "¿Todo correcto? Acepta para guardar."
        }
    }

    private func displayName(_ alias: String) -> String {
        matchManager.players.first { $0.alias == alias }?.name ?? alias
    }

    private func updateVoicePar() {
        guard let step = currentStep else { return }
        if case .strokes(let h, _, _) = step {
            voice.currentPar = matchManager.getHole(h)?.par ?? 4
        }
    }

    private func playerGetsStroke(alias: String, hole: Int) -> Bool {
        guard let player = matchManager.players.first(where: { $0.alias == alias }) else { return false }
        return matchManager.distributedStrokes(total: player.strokesVsBase, hole: hole) > 0
    }

    // MARK: - Corpus

    private func saveCorpus() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd_HHmmss"
        let fname = "corpus_\(fmt.string(from: Date())).json"
        let session = CorpusSession(
            date: ISO8601DateFormatter().string(from: Date()),
            players: matchManager.players.map { "\($0.alias)=\($0.name)" },
            turns: log.enumerated().map { CorpusTurn(seq: $0.offset, question: $0.element.q, answer: $0.element.a) }
        )
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                .first?.appendingPathComponent(fname),
              let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url)
    }
}
