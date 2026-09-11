import SwiftUI

struct IntentTestView: View {
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAlias = ""
    @State private var hole = 1
    @State private var strokes = 4
    @State private var putts = 0
    @State private var resultMessage = ""
    @State private var isRunning = false

    var body: some View {
        NavigationView {
            Form {
                Section("Jugador") {
                    if matchManager.players.isEmpty {
                        Text("Sin jugadores — configura en ⚙️ Setup")
                            .foregroundColor(.secondary).font(.caption)
                    } else {
                        Picker("Jugador", selection: $selectedAlias) {
                            ForEach(matchManager.players, id: \.alias) {
                                Text("\($0.alias) · \($0.name)").tag($0.alias)
                            }
                        }
                    }
                }
                Section("Datos del hoyo") {
                    Stepper("Hoyo: \(hole)", value: $hole, in: 1...18)
                    Stepper("Golpes: \(strokes)", value: $strokes, in: 1...15)
                    Stepper("Putts: \(putts)", value: $putts, in: 0...10)
                }
                if !resultMessage.isEmpty {
                    Section("Resultado") {
                        Text(resultMessage)
                            .foregroundColor(resultMessage.hasPrefix("✅") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Probar Intent")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedAlias.isEmpty, let first = matchManager.players.first {
                    selectedAlias = first.alias
                    hole = matchManager.startHole
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isRunning ? "Anotando…" : "Anotar") { runIntent() }
                        .disabled(selectedAlias.isEmpty || isRunning)
                }
            }
        }
    }

    private func runIntent() {
        isRunning = true
        resultMessage = ""

        let playerName = matchManager.players
            .first(where: { $0.alias == selectedAlias })?.name ?? selectedAlias

        let record = GolfScoreRecord(
            player: playerName,
            hole: hole,
            strokes: strokes,
            putts: putts,
            penalties: 0,
            specialMark: .none
        )
        let success = ScoreManager.shared.saveScore(record: record)
        if success {
            NotificationCenter.default.post(name: .siriRecordPending, object: nil)
            resultMessage = "✅ \(selectedAlias) · H\(hole) · \(strokes) golpes"
        } else {
            resultMessage = "❌ No se pudo guardar el puntaje"
        }
        isRunning = false
    }
}
