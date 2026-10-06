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
            summaryRow("Strokes", text: strokesSummaryText)
            summaryRow("Parejas", text: teamsSummaryText)
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

    // Mismo contenido que strokesSummary, pero el valor del stroke va en negritas — el caddie
    // necesita distinguir de un vistazo el número de strokes dentro de la frase, no solo leerlo
    // mezclado con el alias en el mismo peso de fuente.
    private var strokesSummaryText: Text {
        if matchManager.players.isEmpty { return Text("—") }
        return matchManager.players.enumerated().reduce(Text("")) { acc, item in
            let (idx, p) = item
            let piece = Text("\(p.alias) ") + Text(formatSignedStroke(p.strokesVsBase)).fontWeight(.bold)
            return idx == 0 ? piece : acc + Text(", ") + piece
        }
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

    // Igual que teamsSummary, pero con los strokes de cada pareja en negritas (misma razón que
    // strokesSummaryText: distinguir el número dentro de la frase "base vs opp · Strokes N").
    private var teamsSummaryText: Text {
        if !matchManager.lanes.isEmpty {
            return matchManager.lanes.enumerated().reduce(Text("")) { acc, item in
                let (idx, lane) = item
                let base = lane.base.joined(separator: "+")
                let opp = lane.opp.joined(separator: "+")
                var line = Text("\(base) vs \(opp) · Strokes ") + Text(formatStroke(lane.strokes)).fontWeight(.bold)
                if let carrier = lane.strokeCarrier { line = line + Text(" · Lleva \(carrier)") }
                return idx == 0 ? line : acc + Text("\n") + line
            }
        }
        if !matchManager.baseTeamAliases.isEmpty {
            let base = matchManager.baseTeamAliases.joined(separator: "+")
            let opp = matchManager.players.map { $0.alias }.filter { !matchManager.baseTeamAliases.contains($0) }
            return Text("\(base) vs \(opp.isEmpty ? "—" : opp.joined(separator: "+"))")
        }
        return Text("—")
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

    // Overload para filas cuyo valor mezcla texto normal con segmentos en negritas (ej. Strokes) —
    // Text concatenado ya trae su propio peso por segmento, por eso no se aplica .font(.caption)
    // encima (pisaría el .bold de los segmentos); el tamaño caption se fija por separado.
    private func summaryRow(_ label: String, text: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.bold())
            text.font(.caption).foregroundColor(.secondary)
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
