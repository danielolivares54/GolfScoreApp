import SwiftUI

struct RescueCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager
    var autoStart: Bool = false
    @StateObject private var recorder = VoiceRecorder()

    @State private var phase: Phase = .idle
    @State private var transcript = ""
    @State private var detectedHole: Int? = nil
    @State private var reviewScores: [ReviewScore] = []
    @State private var errorText = ""
    @State private var showReview = false
    @State private var auditWarnings: [String] = []

    enum Phase: Equatable { case idle, recording, processing, done, error }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Spacer()
                phaseContent
                Spacer()
                if !transcript.isEmpty && phase != .idle {
                    Text("\"\(transcript)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Caddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear { if autoStart { startRecording() } }
            .sheet(isPresented: $showReview) {
                FuzzyReviewView(
                    hole: detectedHole,
                    transcript: transcript,
                    scores: reviewScores,
                    players: matchManager.players,
                    onConfirm: applyScores,
                    onCancel: { phase = .idle }
                )
            }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .idle:
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Toca para grabar").font(.title2.bold())
                    Text("Di: \"Hoyo 5, Daniel cuatro, Roberto cinco\"")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
                Button { startRecording() } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 88)).foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

        case .recording:
            VStack(spacing: 24) {
                Text("Grabando…").font(.title2.bold()).foregroundColor(.red)
                Button { stopAndProcess() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 88)).foregroundColor(.red)
                }
                .buttonStyle(.plain)
                Text("Toca para detener").font(.caption).foregroundColor(.secondary)
            }

        case .processing:
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4)
                Text("Procesando…").font(.subheadline).foregroundColor(.secondary)
            }

        case .done:
            VStack(spacing: 16) {
                Image(systemName: auditWarnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(auditWarnings.isEmpty ? .green : .orange)
                Text(auditWarnings.isEmpty ? "Score anotado" : "Score anotado — hoyo incompleto")
                    .font(.title2.bold())
                if !auditWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(auditWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 32)
                    Button("Grabar de nuevo") { auditWarnings = []; phase = .idle }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .padding(.top, 4)
                }
            }

        case .error:
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56)).foregroundColor(.orange)
                Text(errorText)
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Button("Reintentar") { phase = .idle }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func startRecording() {
        transcript = ""
        recorder.requestMicrophoneAndStart { [self] granted in
            if granted {
                phase = .recording
            } else {
                errorText = "Permiso de micrófono denegado. Actívalo en Ajustes."
                phase = .error
            }
        }
    }

    private func stopAndProcess() {
        guard let audioURL = recorder.stopRecording() else {
            errorText = "No se pudo grabar. Intenta de nuevo."
            phase = .error
            return
        }
        phase = .processing
        Task { await process(audioURL: audioURL) }
    }

    private func process(audioURL: URL) async {
        // Step 1: Transcribe with Whisper
        let text: String
        do {
            text = try await OpenAIService.shared.transcribeAudio(url: audioURL)
        } catch let err {
            await MainActor.run {
                errorText = "No se pudo transcribir: \(err.localizedDescription)"
                phase = .error
            }
            return
        }

        await MainActor.run { transcript = text }

        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            await MainActor.run {
                errorText = "No detecté voz. Habla más cerca del micrófono."
                phase = .error
            }
            return
        }

        // Step 2: Parse with GPT
        let matchState: [String: Any] = [
            "jugadores": matchManager.players.map { $0.alias },
            "yo_alias": matchManager.yoAlias,
            "hoyo_actual": matchManager.expectedNextHole()
        ]

        do {
            let result = try await OpenAIService.shared.parseScore(transcript: text, matchState: matchState)

            guard result.ok else {
                await MainActor.run {
                    errorText = result.error ?? "No se pudo interpretar el score."
                    phase = .error
                }
                return
            }

            // Step 3: Interpreter normalizes player aliases
            let interpreted = MatchInterpreter.apply(transcript: text, entities: result.entities, match: matchManager)

            if interpreted.error == "NOISE" {
                await MainActor.run {
                    errorText = "No entendí. Di: \"Hoyo 5, Daniel cuatro golpes\""
                    phase = .error
                }
                return
            }

            guard let hole = interpreted.entities.hoyo else {
                await MainActor.run {
                    errorText = "No detecté el hoyo. Di: \"Hoyo 5, Daniel cuatro golpes\""
                    phase = .error
                }
                return
            }

            let scores = (interpreted.entities.scores ?? []).map {
                ReviewScore(alias: $0.jugador, gross: $0.gross, putts: $0.putts)
            }

            guard !scores.isEmpty else {
                await MainActor.run {
                    errorText = "No detecté golpes. Menciona al jugador y sus golpes."
                    phase = .error
                }
                return
            }

            await MainActor.run {
                detectedHole = hole
                reviewScores = scores
                phase = .idle
                showReview = true
            }

        } catch let err {
            await MainActor.run {
                errorText = "Error: \(err.localizedDescription)"
                phase = .error
            }
        }
    }

    private func applyScores(_ confirmed: [ReviewScore]) {
        guard let hole = detectedHole else { return }
        for s in confirmed {
            matchManager.applyHoleEntry(HoleEntryData(
                hole_number: hole,
                player_alias: s.alias,
                strokes: s.gross,
                putts: s.putts ?? 0,
                units: nil,
                tags: nil
            ))
        }

        // Audit check: report any data quality issues for this hole
        let missScores = matchManager.players
            .filter { matchManager.getScore(hole: hole, player: $0.alias) == 0 }
            .map { $0.alias }
        let missPutts = matchManager.players
            .filter {
                matchManager.getScore(hole: hole, player: $0.alias) > 0 &&
                matchManager.getPutts(hole: hole, player: $0.alias) == 0
            }
            .map { $0.alias }
        var warnings: [String] = []
        if !missScores.isEmpty { warnings.append("Sin score: \(missScores.joined(separator: " · "))") }
        if !missPutts.isEmpty  { warnings.append("Sin putts: \(missPutts.joined(separator: " · "))") }
        auditWarnings = warnings

        phase = .done
        let delay: Double = auditWarnings.isEmpty ? 1.2 : 4.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if auditWarnings.isEmpty { dismiss() }
        }
    }
}
