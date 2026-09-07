import SwiftUI

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

    init(hole: Int?, transcript: String, scores: [ReviewScore], players: [PlayerModel],
         onConfirm: @escaping ([ReviewScore]) -> Void, onCancel: @escaping () -> Void) {
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
                    if let h = hole { Text("Hoyo \(h)").font(.headline) }
                    if !transcript.isEmpty {
                        Text(transcript).font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("Jugadores") {
                    ForEach(scores.indices, id: \.self) { i in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Golpes \(scores[i].gross)").font(.headline)
                                if let p = scores[i].putts {
                                    Text("Putts \(p)").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Picker("Jugador", selection: Binding(
                                get: { scores[i].alias },
                                set: { scores[i].alias = $0 }
                            )) {
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
                    Button("Cancelar") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirmar") { onConfirm(scores); dismiss() }
                        .disabled(scores.isEmpty)
                }
            }
        }
    }
}
