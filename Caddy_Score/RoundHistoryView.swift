import SwiftUI

// MARK: - Design tokens (mismos valores que HoleAuditView/ContentView)

private extension Color {
    static let cBg      = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let cSurface = Color.white
    static let cBorder  = Color(red: 0.890, green: 0.875, blue: 0.824)
    static let cRowDiv  = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let cInk     = Color(red: 0.110, green: 0.137, blue: 0.129)
    static let cMuted   = Color(red: 0.431, green: 0.416, blue: 0.361)
    static let cFairway = Color(red: 0.114, green: 0.627, blue: 0.310)
    static let cBrick   = Color(red: 0.659, green: 0.275, blue: 0.184)
    static let cGold    = Color(red: 0.784, green: 0.608, blue: 0.235)
    static let cDisabled = Color(red: 0.855, green: 0.835, blue: 0.769)
    static let cErrBg   = Color(red: 0.992, green: 0.910, blue: 0.894)
}

// MARK: - Historial de rondas cerradas
//
// Lee closed_rounds/*.json (App Group) — cada ronda cerrada queda archivada ahí desde que se
// implementó "Cerrar Ronda" (CAMBIOS_CADDIE_v2.md #6), pero hasta ahora nada en la app los leía
// de vuelta. Esta pantalla filtra por rival individual y muestra los strokes vigentes en esa
// ronda, resaltados — si alguno salió en 0 debe notarse a simple vista, no perderse en el gris.

struct RoundHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rounds: [RoundResultFile] = []
    @State private var selectedOpponent: String = "Todos"

    private var opponents: [String] {
        let all = rounds.flatMap { round in
            round.lines.filter { $0.scope == "individual" }.compactMap { $0.opponentAlias }
        }
        return ["Todos"] + Array(Set(all)).sorted()
    }

    private var filteredRounds: [RoundResultFile] {
        guard selectedOpponent != "Todos" else { return rounds }
        return rounds.filter { round in
            round.lines.contains { $0.scope == "individual" && $0.opponentAlias == selectedOpponent }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    opponentFilter
                    if filteredRounds.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(filteredRounds, id: \.roundId) { round in
                                    roundCard(round)
                                }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 14)
                        }
                    }
                }
            }
            .navigationTitle("Historial de Rondas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onAppear { rounds = RoundResultFile.loadAll() }
    }

    // MARK: Filtro por rival

    private var opponentFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(opponents, id: \.self) { alias in
                    let sel = selectedOpponent == alias
                    Button { selectedOpponent = alias } label: {
                        Text(alias)
                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                            .foregroundColor(sel ? .white : .cInk)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(sel ? Color.cFairway : Color.cSurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(sel ? Color.cFairway : Color.cBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52)).foregroundColor(.cDisabled)
            Text("Sin rondas cerradas todavía")
                .font(.system(size: 15)).foregroundColor(.cMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Round card

    private func roundCard(_ round: RoundResultFile) -> some View {
        let shownLines = round.lines.filter { line in
            line.scope == "individual" && (selectedOpponent == "Todos" || line.opponentAlias == selectedOpponent)
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(round.date)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.cInk)
                    Text("\(round.courseName) · Sale H\(round.startHole)")
                        .font(.system(size: 11.5)).foregroundColor(.cMuted)
                }
                Spacer()
                Text(caddyMoneyStr(round.totalMoney))
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(round.totalMoney >= 0 ? .cFairway : .cBrick)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Color.cRowDiv.frame(height: 1)

            ForEach(Array(shownLines.enumerated()), id: \.offset) { idx, line in
                opponentRow(round: round, line: line)
                if idx < shownLines.count - 1 { Color.cRowDiv.frame(height: 1).padding(.leading, 14) }
            }
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
    }

    // MARK: Fila por rival — resultado + strokes vigentes esa ronda, resaltados

    private func opponentRow(round: RoundResultFile, line: RoundResultLine) -> some View {
        let strokes = round.players.first { $0.alias == line.opponentAlias }?.strokesVsBase ?? 0
        let isZero = abs(strokes) < 0.001
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.opponentAlias ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
                Text("Vuelta \(line.vueltaPoints >= 0 ? "+" : "")\(line.vueltaPoints) · Match \(line.matchPoints >= 0 ? "+" : "")\(line.matchPoints)")
                    .font(.system(size: 11)).foregroundColor(.cMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Strokes")
                    .font(.system(size: 9, weight: .semibold)).foregroundColor(.cMuted)
                Text(strokeStr(strokes))
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(isZero ? .cBrick : .cGold)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(isZero ? Color.cErrBg : Color.cGold.opacity(0.12))
            .cornerRadius(8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func strokeStr(_ v: Double) -> String {
        let sign = v > 0 ? "+" : ""
        return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(sign)\(Int(v))" : String(format: "%@%.1f", sign, v)
    }

    private func caddyMoneyStr(_ v: Int) -> String {
        (v >= 0 ? "+$" : "-$") + "\(abs(v))"
    }
}
