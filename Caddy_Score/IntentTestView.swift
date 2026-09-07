import SwiftUI
import AppIntents

struct IntentTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = ""
    @State private var hole = 1
    @State private var strokes = 4
    @State private var putts = 0
    @State private var penalties = 0
    @State private var resultMessage = ""
    @State private var isRunning = false

    private var players: [String] { SiriMatchManager.shared.getPlayers() }

    var body: some View {
        NavigationView {
            Form {
                Section("Jugador") {
                    if players.isEmpty {
                        Text("No hay jugadores cargados (abre la app primero)")
                            .foregroundColor(.secondary).font(.caption)
                    } else {
                        Picker("Jugador", selection: $player) {
                            ForEach(players, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
                Section("Datos del hoyo") {
                    Stepper("Hoyo: \(hole)", value: $hole, in: 1...18)
                    Stepper("Golpes: \(strokes)", value: $strokes, in: 1...15)
                    Stepper("Putts: \(putts)", value: $putts, in: 0...10)
                    Stepper("Penalidades: \(penalties)", value: $penalties, in: 0...5)
                }
                if !resultMessage.isEmpty {
                    Section("Resultado") {
                        Text(resultMessage)
                            .foregroundColor(resultMessage.hasPrefix("✅") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Probar App Intent")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if player.isEmpty, let first = players.first { player = first } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isRunning ? "Anotando..." : "Anotar") { runIntent() }
                        .disabled(player.isEmpty || isRunning)
                }
            }
        }
    }

    private func runIntent() {
        isRunning = true
        resultMessage = ""
        Task {
            var intent = LogGolfScoreIntent()
            intent.player = player; intent.hole = hole
            intent.strokes = strokes; intent.putts = putts
            intent.penalties = penalties; intent.isEdit = false
            do {
                _ = try await intent.perform()
                await MainActor.run {
                    resultMessage = "✅ Anotado: \(player), hoyo \(hole), \(strokes) golpes"
                    isRunning = false
                }
            } catch {
                await MainActor.run { resultMessage = "❌ \(error.localizedDescription)"; isRunning = false }
            }
        }
    }
}
