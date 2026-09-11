import SwiftUI

struct ScorecardView: View {
    @ObservedObject var matchManager: MatchManager
    let pendingEntities: ScoreEntities?
    let pendingTranscript: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let pending = pendingEntities {
                    CardView(matchManager: matchManager, entities: pending, transcript: pendingTranscript)
                } else {
                    Text("No hay tarjeta pendiente.").font(.subheadline).foregroundColor(.secondary)
                }
                ScorecardGrid(matchManager: matchManager)
            }
            .padding()
        }
        .navigationTitle("Tarjeta")
        .navigationBarTitleDisplayMode(.inline)
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
                Text(holeNumber > 0 ? "Hoyo \(holeNumber)" : "Hoyo —").font(.subheadline.weight(.semibold))
                Spacer()
                if !segment.isEmpty {
                    chip(segment)
                }
                chip("SI \(si)")
            }
            if !transcript.isEmpty { Text("\"\(transcript)\"").font(.subheadline) }
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

    private func chip(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(.systemGray5)).cornerRadius(6)
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(width: 80).padding(.vertical, 6)
        .background(Color(.systemBackground)).cornerRadius(10)
    }
}

struct ScorecardGrid: View {
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("").frame(width: 64)
                    ForEach(matchManager.players) { player in
                        VStack(spacing: 1) {
                            ForEach(Array(player.alias.uppercased()), id: \.self) { ch in
                                Text(String(ch))
                            }
                        }
                        .font(.caption2.weight(.semibold))
                        .frame(width: 20, height: 58).fixedSize()
                        .frame(minWidth: 58).multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 6).background(Color(.secondarySystemBackground))

                ForEach(holeOrder, id: \.self) { holeNumber in
                    ScorecardRow(matchManager: matchManager, holeNumber: holeNumber)
                }
            }
            .cornerRadius(12)
        }
    }

    private var holeOrder: [Int] {
        let s = max(1, min(18, matchManager.startHole))
        return (0..<9).map { ((s - 1 + $0) % 18) + 1 }
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
                Text("\(par)").font(.caption2.weight(.bold)).foregroundColor(parColor(par))
                Text("\(si)").font(.caption2.weight(.bold)).foregroundColor(siColor(si))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(siColor(si).opacity(0.15)).cornerRadius(4)
            }
            .frame(width: 64).font(.caption2.weight(.semibold))

            ForEach(matchManager.players) { player in
                let score = matchManager.getScore(hole: holeNumber, player: player.alias)
                let putts = matchManager.getPutts(hole: holeNumber, player: player.alias)
                let winsInd = matchManager.hasIndividualUnitWin(hole: holeNumber, alias: player.alias)
                let winsPair = matchManager.hasPairUnitWin(hole: holeNumber, alias: player.alias)
                VStack(spacing: 2) {
                    Text(score > 0 ? "\(score)" : "—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(scoreColor(score: score, par: par))
                    if putts > 0 {
                        Text("(\(putts))").font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary).opacity(score > 0 ? 1 : 0.5)
                    }
                    HStack(spacing: 3) {
                        if winsInd {
                            unitBadge("I", color: .green)
                        }
                        if winsPair {
                            unitBadge("P", color: .blue)
                        }
                    }
                }
                .frame(minWidth: 58).padding(.vertical, 2)
                .background((winsInd || winsPair) ? Color.yellow.opacity(0.12) : Color.clear)
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 8)
        .background(holeNumber % 2 == 0 ? Color(.systemBackground) : Color(.secondarySystemBackground))
    }

    private func unitBadge(_ letter: String, color: Color) -> some View {
        Text(letter).font(.caption2.bold()).foregroundColor(.white)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color).cornerRadius(4)
    }

    private func scoreColor(score: Int, par: Int) -> Color {
        if score == 0 { return .secondary }
        return score < par ? .green : score == par ? .primary : .red
    }

    private func siColor(_ si: Int) -> Color {
        let t = Double(max(1, min(18, si)) - 1) / 17.0
        return Color(red: 1.0 - t, green: t, blue: 0)
    }

    private func parColor(_ par: Int) -> Color {
        switch par { case 3: return .green; case 4: return .orange; case 5: return .red; default: return .secondary }
    }
}
