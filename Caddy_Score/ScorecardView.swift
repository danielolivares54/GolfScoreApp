import SwiftUI

// MARK: - ScorecardView (pendingEntities review flow — unchanged)

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

// MARK: - CardView (pending entities card — unchanged)

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
                if !segment.isEmpty { chip(segment) }
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

// MARK: - ScorecardGrid  (Bloque 2: jugadores = filas, hoyos = columnas)

struct ScorecardGrid: View {
    @ObservedObject var matchManager: MatchManager

    private let cellW: CGFloat   = 40
    private let labelW: CGFloat  = 44
    private let headerH: CGFloat = 44
    private let minRowH: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let playerCount = max(1, matchManager.players.count)
            let rowH = max(minRowH,
                (geo.size.height - headerH - 1) / CGFloat(playerCount))

            HStack(spacing: 0) {
                // STICKY LEFT COLUMN — nunca entra al ScrollView
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOYO").font(.caption2.bold())
                        Text("Par").font(.caption2).foregroundColor(.secondary)
                        Text("HC").font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(width: labelW, height: headerH, alignment: .leading)
                    .padding(.horizontal, 4)

                    Divider()

                    if matchManager.players.isEmpty {
                        Spacer()
                    } else {
                        ForEach(Array(matchManager.players.enumerated()), id: \.element.id) { idx, player in
                            Text(player.alias)
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .frame(width: labelW, height: rowH, alignment: .leading)
                                .padding(.horizontal, 4)
                            if idx < matchManager.players.count - 1 {
                                Divider()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: labelW, height: geo.size.height, alignment: .top)
                .background(Color(.secondarySystemBackground))

                // Separador visual sticky/scroll
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 0.5)

                // SCROLLING HOLES — solo columnas de hoyos
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Encabezado de hoyos
                        HStack(spacing: 0) {
                            ForEach(Array(holeOrder.enumerated()), id: \.offset) { colIdx, hole in
                                let hd = matchManager.getHole(hole)
                                VStack(spacing: 2) {
                                    Text("\(hole)").font(.caption2.bold())
                                    Text("\(hd?.par ?? 4)").font(.caption2).foregroundColor(parLabelColor(hd?.par ?? 4))
                                    Text("\(hd?.si ?? 0)").font(.caption2).foregroundColor(.secondary)
                                }
                                .frame(width: cellW, height: headerH)
                                .background(colIdx % 2 == 0
                                    ? Color(.secondarySystemBackground)
                                    : Color(.systemGray4))
                            }
                        }

                        Divider()

                        if matchManager.players.isEmpty {
                            Text("Sin jugadores · configura en Setup")
                                .font(.caption).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity).padding()
                        } else {
                            ForEach(Array(matchManager.players.enumerated()), id: \.element.id) { idx, player in
                                ScorecardRow(
                                    matchManager: matchManager,
                                    player: player,
                                    holeOrder: holeOrder,
                                    cellW: cellW,
                                    rowH: rowH,
                                    isEven: idx % 2 == 0
                                )
                                if idx < matchManager.players.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geo.size.height, alignment: .top)
                    .background(Color(.systemBackground))
                }
            }
            .background(Color(.systemBackground))
        }
    }

    // MARK: Helpers

    var holeOrder: [Int] {
        let s = max(1, min(18, matchManager.startHole))
        return (0..<9).map { ((s - 1 + $0) % 18) + 1 }
    }

    private func parLabelColor(_ par: Int) -> Color {
        switch par {
        case 3: return Color(red: 27/255, green: 122/255, blue: 61/255)
        case 5: return Color(red: 224/255, green: 48/255, blue: 48/255)
        default: return .primary
        }
    }
}

// MARK: - ScorecardRow  (Bloque 3: celda completa con badges, Cruz, diagonal)

struct ScorecardRow: View {
    @ObservedObject var matchManager: MatchManager
    let player: PlayerModel
    let holeOrder: [Int]
    let cellW: CGFloat
    let rowH: CGFloat
    let isEven: Bool

    // SOT color system (hex fijos — no modificar)
    private let eagleC  = Color(red: 196/255, green: 30/255,  blue: 30/255)   // #C41E1E
    private let birdieC = Color(red: 224/255, green: 48/255,  blue: 48/255)   // #E03030
    private let parC    = Color(red: 27/255,  green: 122/255, blue: 61/255)   // #1B7A3D
    private let bogeyC  = Color.black                                           // #000000
    private let d2C     = Color(red: 90/255,  green: 90/255,  blue: 90/255)   // #5A5A5A
    private let d3C     = Color(red: 44/255,  green: 44/255,  blue: 46/255)   // #2C2C2E
    private let oyesC   = Color(red: 212/255, green: 160/255, blue: 23/255)   // #D4A017

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(holeOrder.enumerated()), id: \.offset) { colIdx, hole in
                scoreCell(hole: hole, colIdx: colIdx)
            }
        }
        .background(isEven ? Color(.systemBackground) : Color(.systemBackground).opacity(0.97))
    }

    // MARK: Score cell

    private func scoreCell(hole: Int, colIdx: Int) -> some View {
        let holeData  = matchManager.getHole(hole)
        let par       = holeData?.par ?? 4
        let gross     = matchManager.getScore(hole: hole, player: player.alias)
        let putts     = matchManager.getPutts(hole: hole, player: player.alias)
        let dots      = matchManager.distributedStrokes(total: player.strokesVsBase, hole: hole)
        let isOyes    = matchManager.hasIndividualUnitWin(hole: hole, alias: player.alias)
                     || matchManager.hasPairUnitWin(hole: hole, alias: player.alias)
        let badges    = Array(matchManager.unitBadges(alias: player.alias, hole: hole).prefix(3))
        let ovr       = matchManager.cellOverride(alias: player.alias, hole: hole)

        return ZStack {
            // Alternating column stripe
            if colIdx % 2 != 0 {
                Color(.systemGray5)
            }

            // Content layer
            VStack(spacing: 1) {
                if gross > 0 {
                    Text("\(gross)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isOyes ? oyesC : scoreColor(gross: gross, par: par))
                    if putts > 0 {
                        Text("\(putts)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    if dots > 0 {
                        Text(dots >= 2 ? "●●" : dots == 1 ? "●" : "◐")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    if !badges.isEmpty {
                        Text(badges.joined(separator: " "))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 14))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }

            // Penalty diagonal (bottom-left → top-right across full cell)
            if ovr == .penaltyStroke {
                Canvas { ctx, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 4, y: size.height - 4))
                    path.addLine(to: CGPoint(x: size.width - 4, y: 4))
                    ctx.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 1.5)
                }
                .allowsHitTesting(false)
            }

            // Override cross ✕
            if ovr == .lostHole || ovr == .noShow || ovr == .disqualified || ovr == .conceded {
                Text("✕")
                    .font(.system(size: 22, weight: .thin))
                    .foregroundColor(.black.opacity(0.6))
            }
        }
        .frame(width: cellW, height: rowH)
    }

    // MARK: Helpers

    private func scoreColor(gross: Int, par: Int) -> Color {
        switch gross - par {
        case ..<(-1): return eagleC
        case -1:      return birdieC
        case 0:       return parC
        case 1:       return bogeyC
        case 2:       return d2C
        default:      return d3C
        }
    }
}
