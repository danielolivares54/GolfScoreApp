import SwiftUI

struct MatchSummaryCard: View {
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resumen")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            MatchSummaryView(matchManager: matchManager)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct MatchSummaryView: View {
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow("Campo", value: matchManager.courseId.isEmpty ? "—" : matchManager.courseId)
            summaryRow("Hoyo salida", value: "\(matchManager.startHole)")
            summaryRow("Jugadores", value: playersSummary)
            summaryRow("Strokes", value: strokesSummary)
            summaryRow("Parejas", value: teamsSummary)
            summaryRow("F9/B9/Match", value: betResultsSummary)
            summaryRow("Unidad", value: unitSummary)
            summaryRow("Apuestas", value: betsSummary)
        }
    }

    private var playersSummary: String {
        if matchManager.players.isEmpty { return "—" }
        return matchManager.players.map { "\($0.alias) (\($0.name))" }.joined(separator: ", ")
    }

    private var strokesSummary: String {
        if matchManager.players.isEmpty { return "—" }
        return matchManager.players.map { p in
            "\(p.alias) \(formatSignedStroke(p.strokesVsBase))"
        }.joined(separator: ", ")
    }

    private var teamsSummary: String {
        if !matchManager.lanes.isEmpty {
            return matchManager.lanes.map { lane in
                let base = lane.base.joined(separator: "+")
                let opp = lane.opp.joined(separator: "+")
                var line = "\(base) vs \(opp) · Strokes \(formatStroke(lane.strokes))"
                if let carrier = lane.strokeCarrier { line += " · Lleva \(carrier)" }
                return line
            }.joined(separator: "\n")
        }
        if !matchManager.baseTeamAliases.isEmpty {
            let base = matchManager.baseTeamAliases.joined(separator: "+")
            let opp = matchManager.players.map { $0.alias }.filter { !matchManager.baseTeamAliases.contains($0) }
            return "\(base) vs \(opp.isEmpty ? "—" : opp.joined(separator: "+"))"
        }
        return "—"
    }

    private var unitSummary: String {
        if matchManager.vueltaValue <= 0 { return "—" }
        return "Vuelta \(matchManager.vueltaValue) · Unidad \(matchManager.unitValue)"
    }

    private var betResultsSummary: String {
        let ind = matchManager.individualBetSummaryLines()
        let pair = matchManager.pairBetSummaryLines()
        let oyesInd = matchManager.oyesIndividualSummaryLines()
        let oyesPair = matchManager.oyesPairSummaryLines()
        var sections: [String] = []
        if !ind.isEmpty { sections.append("Individuales:\n" + ind.joined(separator: "\n")) }
        if !pair.isEmpty { sections.append("Parejas:\n" + pair.joined(separator: "\n")) }
        if !oyesInd.isEmpty { sections.append("OYES Individual:\n" + oyesInd.joined(separator: "\n")) }
        if !oyesPair.isEmpty { sections.append("OYES Parejas:\n" + oyesPair.joined(separator: "\n")) }
        return sections.isEmpty ? "—" : sections.joined(separator: "\n")
    }

    private var betsSummary: String {
        if matchManager.activeBets.isEmpty { return "—" }
        return matchManager.activeBets.map { bet in
            let tag = bet.tagOverride?.isEmpty == false ? bet.tagOverride! : "\(bet.definition.tag)-ALIAS"
            return "\(bet.definition.name) (\(tag))"
        }.joined(separator: ", ")
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.bold())
            Text(value).font(.caption).foregroundColor(.secondary)
                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatStroke(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    private func formatSignedStroke(_ value: Double) -> String {
        (value > 0 ? "+" : "") + formatStroke(value)
    }
}
