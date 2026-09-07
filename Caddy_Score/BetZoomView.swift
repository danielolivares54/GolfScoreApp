import SwiftUI

struct BetZoomStatusCard: View {
    @ObservedObject var matchManager: MatchManager
    let onOpenZoom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estado apuestas")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            HStack {
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Ver zoom") { onOpenZoom() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var statusText: String {
        if let h = matchManager.lastCompleteHole() {
            return "\(matchManager.segmentForHole(h)) · Hoyo \(h)"
        }
        return "Sin hoyos completos"
    }
}

struct BetZoomCard: View {
    enum ZoomTarget: Identifiable {
        case individual(String)
        case parejas(UUID)
        case unidades
        var id: String {
            switch self {
            case .individual(let opp): return "ind-\(opp)"
            case .parejas(let id): return "pair-\(id.uuidString)"
            case .unidades: return "units"
            }
        }
    }

    struct SummaryLine: Identifiable {
        let id = UUID()
        let label: String
        let strokesText: String
        let strokesColor: Color
        let vpText: String
        let puttsText: String
        let unitsText: String
        let target: ZoomTarget
    }

    @ObservedObject var matchManager: MatchManager
    @State private var zoomTarget: ZoomTarget?
    @State private var selectedSegment: String = "F9"
    @State private var unitsScopeFilter: String = "Todos"
    private let fairwayDark = Color(red: 0.10, green: 0.13, blue: 0.12)
    private let fairwayMid = Color(red: 0.15, green: 0.20, blue: 0.18)
    private let clubGold = Color(red: 0.85, green: 0.72, blue: 0.32)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Golf Scorecard Tracker")
                    .font(.custom("Playfair Display", size: 18))
                    .foregroundColor(clubGold)
                Spacer()
                Text(headerText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.8))
            }

            if availableSegments.count > 1 {
                Picker("Vuelta", selection: $selectedSegment) {
                    ForEach(availableSegments, id: \.self) { seg in Text(seg).tag(seg) }
                }
                .pickerStyle(.segmented)
            }

            if summaryLines.isEmpty {
                Text("Sin apuestas para mostrar.")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.7))
            } else {
                if !individualSummaryLines.isEmpty {
                    sectionTitle("Individuales")
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                headerCell("Apuesta", 132, color: clubGold)
                                headerCell("Strokes", 96, color: clubGold)
                                headerCell("Vta Pres", 92, color: clubGold)
                                headerCell("Unid", 36, color: clubGold)
                                headerCell("Putts", 52, color: clubGold)
                                if selectedSegment == "B9" { headerCell("Carry", 56, color: clubGold) }
                            }
                            ForEach(individualSummaryLines.prefix(8)) { line in
                                HStack(spacing: 8) {
                                    zoomNameCell(line: line, width: 132)
                                    strokeCell(line.strokesText, 96, color: line.strokesColor)
                                    dataCell(line.vpText, 92)
                                    dataCell(line.unitsText, 36)
                                    dataCell(line.puttsText, 52)
                                    if selectedSegment == "B9" { carryToggleCell(line: line, width: 56) }
                                }
                            }
                        }
                        .frame(minWidth: selectedSegment == "B9" ? 506 : 442, alignment: .leading)
                    }
                }
                if !pairSummaryLines.isEmpty {
                    Divider().overlay(clubGold.opacity(0.7))
                    sectionTitle("Twosomes")
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                headerCell("Pareja", 132, color: clubGold)
                                headerCell("Strokes", 96, color: clubGold)
                                headerCell("Vta Pres", 92, color: clubGold)
                                headerCell("Unid", 44, color: clubGold)
                                if selectedSegment == "B9" { headerCell("Carry", 56, color: clubGold) }
                            }
                            ForEach(pairSummaryLines.prefix(8)) { line in
                                HStack(spacing: 8) {
                                    zoomNameCell(line: line, width: 132)
                                    strokeCell(line.strokesText, 96, color: line.strokesColor)
                                    dataCell(line.vpText, 92)
                                    dataCell(line.unitsText, 44)
                                    if selectedSegment == "B9" { carryToggleCell(line: line, width: 56) }
                                }
                            }
                        }
                        .frame(minWidth: selectedSegment == "B9" ? 444 : 380, alignment: .leading)
                    }
                }
                if let unitLine {
                    Divider().overlay(clubGold.opacity(0.7))
                    sectionTitle("Unidades")
                    HStack(spacing: 8) {
                        zoomNameCell(line: unitLine, width: 132)
                        strokeCell(unitLine.strokesText, 96, color: unitLine.strokesColor)
                        dataCell(unitLine.vpText, 92)
                        dataCell(unitLine.unitsText, 38)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(LinearGradient(colors: [fairwayMid, fairwayDark], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(clubGold.opacity(0.35), lineWidth: 1))
        .sheet(item: $zoomTarget) { target in
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(zoomSheetHeader(target: target))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        switch target {
                        case .individual(let opp):
                            individualTable(opponent: opp, rows: matchManager.individualZoomRows(opponentAlias: opp, segmentOverride: selectedSegment))
                        case .parejas(let laneId):
                            pairTable(rows: matchManager.pairZoomRows(laneId: laneId, segmentOverride: selectedSegment))
                        case .unidades:
                            unitsTable(entries: unitLogEntries)
                        }
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
                .navigationTitle("Detalle \(selectedSegment)")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            if let h = uptoHole {
                let current = matchManager.segmentForHole(h)
                if availableSegments.contains(current) { selectedSegment = current }
                else if let first = availableSegments.first { selectedSegment = first }
            }
        }
    }

    private var uptoHole: Int? { matchManager.lastCompleteHole() }

    private var headerText: String {
        if let h = matchManager.lastHoleForZoom(segment: selectedSegment) { return "\(selectedSegment) · Hoyo \(h)" }
        return "Sin hoyos completos"
    }

    private var availableSegments: [String] {
        let segs = matchManager.availableZoomSegments()
        return segs.isEmpty ? ["F9"] : segs
    }

    private var summaryLines: [SummaryLine] {
        var out: [SummaryLine] = []
        let opps = matchManager.players.map(\.alias).filter { $0 != matchManager.yoAlias }
        for opp in opps {
            let rows = matchManager.individualZoomRows(opponentAlias: opp, segmentOverride: selectedSegment)
            guard let last = rows.last else { continue }
            let pres = pressureText(last.openPressures)
            var vp = "\(resultText(last.vueltaAccum)) \(pres)"
            if selectedSegment == "B9" { vp += " C\(resultText(matchManager.individualCarryResultB9(opponentAlias: opp)))" }
            let putts = "\(last.yoPuttsAccum) \(last.oppPuttsAccum)"
            let yoBase = matchManager.players.first(where: { $0.alias == matchManager.yoAlias })?.strokesVsBase ?? 0
            let oppBase = matchManager.players.first(where: { $0.alias == opp })?.strokesVsBase ?? 0
            let relative = oppBase - yoBase
            let strokes = signedStroke(relative)
            let strokeColor: Color = relative > 0.001 ? .red : (relative < -0.001 ? .green : Color.white.opacity(0.92))
            let units = "\(resultText(matchManager.unitStakeForIndividual(opponentAlias: opp, segmentOverride: selectedSegment)))u"
            out.append(SummaryLine(label: "vs \(opp)", strokesText: strokes, strokesColor: strokeColor, vpText: vp, puttsText: putts, unitsText: units, target: .individual(opp)))
        }
        for lane in matchManager.lanes.prefix(3) {
            let rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: selectedSegment)
            guard let last = rows.last else { continue }
            let pres = pressureText(last.openPressures)
            var vp = "\(resultText(last.vueltaAccum)) \(pres)"
            if selectedSegment == "B9" { vp += " C\(resultText(matchManager.pairCarryResultB9(laneId: lane.id)))" }
            let carrier = lane.strokeCarrier ?? "—"
            let strokes = "\(formatStroke(lane.strokes)) \(carrier)"
            let units = "\(resultText(matchManager.unitStakeForPair(laneId: lane.id, segmentOverride: selectedSegment)))u"
            out.append(SummaryLine(label: "\(lane.base.joined(separator: "+"))/\(lane.opp.joined(separator: "+"))", strokesText: strokes, strokesColor: Color.white.opacity(0.92), vpText: vp, puttsText: "—", unitsText: units, target: .parejas(lane.id)))
        }
        let logs = matchManager.unitLogEntriesForZoom(segmentOverride: selectedSegment, includeIndividual: true, includePair: true)
        if !logs.isEmpty {
            let net = logs.reduce(0) { $0 + $1.units }
            out.append(SummaryLine(label: "Unidades", strokesText: "—", strokesColor: Color.white.opacity(0.92), vpText: "\(selectedSegment)", puttsText: "\(logs.count)", unitsText: "\(resultText(net))u", target: .unidades))
        }
        return out
    }

    private var unitLogEntries: [UnitLogEntry] {
        switch unitsScopeFilter {
        case "Individual": return matchManager.unitLogEntriesForZoom(segmentOverride: selectedSegment, includeIndividual: true, includePair: false)
        case "Pareja": return matchManager.unitLogEntriesForZoom(segmentOverride: selectedSegment, includeIndividual: false, includePair: true)
        default: return matchManager.unitLogEntriesForZoom(segmentOverride: selectedSegment, includeIndividual: true, includePair: true)
        }
    }

    private var individualSummaryLines: [SummaryLine] {
        summaryLines.filter { if case .individual = $0.target { return true }; return false }
    }

    private var pairSummaryLines: [SummaryLine] {
        summaryLines.filter { if case .parejas = $0.target { return true }; return false }
    }

    private var unitLine: SummaryLine? {
        summaryLines.first { if case .unidades = $0.target { return true }; return false }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.custom("Playfair Display", size: 14)).foregroundColor(clubGold)
    }

    private func pressureText(_ values: [Int]) -> String {
        values.isEmpty ? "0" : values.map { "\($0)" }.joined(separator: " ")
    }

    private func pressureInfoText(vuelta: Int, pressures: [Int]) -> String {
        "\(resultText(vuelta)) | \(pressureText(pressures))"
    }

    private func resultText(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    @ViewBuilder
    private func gnCell(g: Int, s: Double, n: Double) -> some View {
        let strokeApplied = s > 0.001
        Text("\(g)/\(formatStroke(n))")
            .font(.caption.monospacedDigit())
            .foregroundColor(strokeApplied ? .red : .primary)
            .frame(width: 92, alignment: .leading)
    }

    private func pairGrossCell(ball: PairBallLine, carrierAlias: String?, teamColor: Color) -> some View {
        let totalStroke = ball.individualStrokes + ball.laneStrokes
        let receivesStroke = totalStroke > 0.001
        let strokeText = receivesStroke ? " (\(formatStroke(totalStroke)))" : ""
        return Text("\(ball.gross)\(strokeText)")
            .font(.caption.monospacedDigit())
            .foregroundColor(receivesStroke ? .red : teamColor)
            .frame(width: 58, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
            .background(teamColor.opacity(0.08))
            .cornerRadius(4)
    }

    private func individualTable(opponent: String, rows: [IndividualZoomRow]) -> some View {
        let yoStrokeTotal = rows.reduce(0.0) { $0 + $1.yoStrokes }
        let oppStrokeTotal = rows.reduce(0.0) { $0 + $1.oppStrokes }
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        zoomHeaderCell("H", 26); zoomHeaderCell("Par", 32); zoomHeaderCell("SI", 28)
                        zoomHeaderCell("\(matchManager.yoAlias) S\(formatStroke(yoStrokeTotal)) G/N", 128)
                        zoomHeaderCell("\(opponent) S\(formatStroke(oppStrokeTotal)) G/N", 128)
                        zoomHeaderCell("Res", 36); zoomHeaderCell("U", 18); zoomHeaderCell("Presión (Vta)", 168)
                    }
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            zoomDataCell("\(row.hole)", 26); zoomDataCell("\(row.par)", 32); zoomDataCell("\(row.si)", 28)
                            gnCell(g: row.yoGross, s: row.yoStrokes, n: row.yoNet)
                            gnCell(g: row.oppGross, s: row.oppStrokes, n: row.oppNet)
                            zoomDataCell(resultText(row.result), 36)
                            zoomDataCell(matchManager.unitCountForHole(row.hole) > 0 ? "•" : "", 18)
                            zoomDataCell(pressureInfoText(vuelta: row.vueltaAccum, pressures: row.openPressures), 168)
                        }
                    }
                }
            }
            individualFooter(opponent: opponent, rows: rows)
        }
    }

    private func pairTable(rows: [PairZoomRow]) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    let aliases: [String] = {
                        guard let first = rows.first else { return ["A", "B", "C", "D"] }
                        return first.basePlayers.map { $0.alias } + first.oppPlayers.map { $0.alias }
                    }()
                    let strokeTotals = pairStrokeTotals(rows: rows)
                    HStack(spacing: 8) {
                        zoomHeaderCell("H", 26); zoomHeaderCell("Par", 32); zoomHeaderCell("SI", 28)
                        zoomHeaderCell(pairHeaderText(alias: aliases.count > 0 ? aliases[0] : "A", totals: strokeTotals), 74, color: .blue)
                        zoomHeaderCell(pairHeaderText(alias: aliases.count > 1 ? aliases[1] : "B", totals: strokeTotals), 74, color: .blue)
                        zoomHeaderCell(pairHeaderText(alias: aliases.count > 2 ? aliases[2] : "C", totals: strokeTotals), 74, color: .green)
                        zoomHeaderCell(pairHeaderText(alias: aliases.count > 3 ? aliases[3] : "D", totals: strokeTotals), 74, color: .green)
                        zoomHeaderCell("Res", 36); zoomHeaderCell("U", 18); zoomHeaderCell("Presión (Vta)", 168)
                    }
                    ForEach(rows) { row in
                        let left0 = row.basePlayers.count > 0 ? row.basePlayers[0] : PairBallLine(alias: "-", gross: 0, individualStrokes: 0, laneStrokes: 0, net: 0)
                        let left1 = row.basePlayers.count > 1 ? row.basePlayers[1] : PairBallLine(alias: "-", gross: 0, individualStrokes: 0, laneStrokes: 0, net: 0)
                        let right0 = row.oppPlayers.count > 0 ? row.oppPlayers[0] : PairBallLine(alias: "-", gross: 0, individualStrokes: 0, laneStrokes: 0, net: 0)
                        let right1 = row.oppPlayers.count > 1 ? row.oppPlayers[1] : PairBallLine(alias: "-", gross: 0, individualStrokes: 0, laneStrokes: 0, net: 0)
                        HStack(spacing: 8) {
                            zoomDataCell("\(row.hole)", 26); zoomDataCell("\(row.par)", 32); zoomDataCell("\(row.si)", 28)
                            pairGrossCell(ball: left0, carrierAlias: row.carrierAlias, teamColor: .blue)
                            pairGrossCell(ball: left1, carrierAlias: row.carrierAlias, teamColor: .blue)
                            pairGrossCell(ball: right0, carrierAlias: row.carrierAlias, teamColor: .green)
                            pairGrossCell(ball: right1, carrierAlias: row.carrierAlias, teamColor: .green)
                            zoomDataCell(resultText(row.result), 36)
                            zoomDataCell(matchManager.unitCountForHole(row.hole) > 0 ? "•" : "", 18)
                            zoomDataCell(pressureInfoText(vuelta: row.vueltaAccum, pressures: row.openPressures), 168)
                        }
                    }
                }
            }
            pairFooter(rows: rows)
        }
    }

    private func unitsTable(entries: [UnitLogEntry]) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            Picker("VS", selection: $unitsScopeFilter) {
                Text("Todos").tag("Todos"); Text("Individual").tag("Individual"); Text("Pareja").tag("Pareja")
            }
            .pickerStyle(.segmented)
            if entries.isEmpty {
                Text("Sin unidades en esta vuelta.").font(.caption).foregroundColor(.secondary)
            } else {
                HStack(spacing: 8) {
                    zoomHeaderCell("H", 30); zoomHeaderCell("Jugador", 72); zoomHeaderCell("Tipo", 78)
                    zoomHeaderCell("VS", 72); zoomHeaderCell("u", 24); zoomHeaderCell("Detalle", 120)
                }
                ForEach(entries) { e in
                    HStack(spacing: 8) {
                        zoomDataCell("\(e.hole)", 30); zoomDataCell(e.player, 72); zoomDataCell(e.type, 78)
                        zoomDataCell(e.vs ?? "—", 72); zoomDataCell(resultText(e.units), 24); zoomDataCell(e.detail ?? "—", 120)
                    }
                }
            }
        }
    }

    private func individualFooter(opponent: String, rows: [IndividualZoomRow]) -> some View {
        guard let last = rows.last else { return AnyView(EmptyView()) }
        let seg = matchManager.segmentForHole(last.hole)
        let yoPutts = matchManager.puttsSplit(alias: matchManager.yoAlias, uptoHole: last.hole)
        let oppPutts = matchManager.puttsSplit(alias: opponent, uptoHole: last.hole)
        return AnyView(VStack(alignment: .leading, spacing: 4) {
            Text("Resumen acumulado (\(seg))").font(.caption.bold())
            Text("Vuelta: \(resultText(last.vueltaAccum))").font(.caption.monospacedDigit())
            if seg == "B9" {
                Text("Carry: \(resultText(matchManager.individualCarryResultB9(opponentAlias: opponent)))").font(.caption.monospacedDigit())
                Text("Match: \(resultText(last.matchAccum))").font(.caption.monospacedDigit())
            }
            Text("Putts 1: F9 \(yoPutts.f9) B9 \(yoPutts.b9) Total \(yoPutts.total)").font(.caption.monospacedDigit())
            Text("Putts 2: F9 \(oppPutts.f9) B9 \(oppPutts.b9) Total \(oppPutts.total)").font(.caption.monospacedDigit())
        }.foregroundColor(.secondary))
    }

    private func pairFooter(rows: [PairZoomRow]) -> some View {
        guard let last = rows.last else { return AnyView(EmptyView()) }
        let seg = matchManager.segmentForHole(last.hole)
        let carryText: String? = {
            guard seg == "B9", let first = rows.first else { return nil }
            let aliases = Set(first.basePlayers.map(\.alias) + first.oppPlayers.map(\.alias))
            guard let lane = matchManager.lanes.first(where: { Set($0.base + $0.opp) == aliases }) else { return nil }
            return resultText(matchManager.pairCarryResultB9(laneId: lane.id))
        }()
        return AnyView(VStack(alignment: .leading, spacing: 4) {
            Text("Resumen acumulado (\(seg))").font(.caption.bold())
            Text("Vuelta: \(resultText(last.vueltaAccum))").font(.caption.monospacedDigit())
            if seg == "B9" {
                if let c = carryText { Text("Carry: \(c)").font(.caption.monospacedDigit()) }
                Text("Match: \(resultText(last.matchAccum))").font(.caption.monospacedDigit())
            }
        }.foregroundColor(.secondary))
    }

    private func headerCell(_ text: String, _ width: CGFloat, color: Color = .secondary) -> some View {
        Text(text).font(.caption2.bold()).foregroundColor(color).frame(width: width, alignment: .leading)
    }

    private func dataCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(.caption.monospacedDigit()).foregroundColor(Color.white.opacity(0.92)).frame(width: width, alignment: .leading)
    }

    private func strokeCell(_ text: String, _ width: CGFloat, color: Color) -> some View {
        Text(text).font(.caption.monospacedDigit()).foregroundColor(color).frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func carryToggleCell(line: SummaryLine, width: CGFloat) -> some View {
        switch line.target {
        case .individual(let opp):
            let active = matchManager.isIndividualCarryActive(opponentAlias: opp)
            let eligible = matchManager.individualCarryEligibleRequester(opponentAlias: opp)
            Button(active ? "ON" : "OFF") {
                if active { matchManager.clearIndividualCarryRequest(opponentAlias: opp) }
                else if let req = eligible { matchManager.setIndividualCarryRequest(opponentAlias: opp, requesterAlias: req) }
            }
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.25) : Color(.secondarySystemBackground).opacity(0.7))
            .cornerRadius(8).disabled(eligible == nil).frame(width: width, alignment: .leading)
        case .parejas(let laneId):
            let active = matchManager.isPairCarryActive(laneId: laneId)
            let eligible = matchManager.pairCarryEligibleRequester(laneId: laneId)
            Button(active ? "ON" : "OFF") {
                if active { matchManager.clearPairCarryRequest(laneId: laneId) }
                else if let req = eligible { matchManager.setPairCarryRequest(laneId: laneId, requesterAlias: req) }
            }
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(active ? Color.green.opacity(0.25) : Color(.secondarySystemBackground).opacity(0.7))
            .cornerRadius(8).disabled(eligible == nil).frame(width: width, alignment: .leading)
        case .unidades:
            Text("—").font(.caption2).frame(width: width, alignment: .leading)
        }
    }

    private func zoomHeaderCell(_ text: String, _ width: CGFloat, color: Color = .secondary) -> some View {
        Text(text).font(.caption2.bold()).foregroundColor(color).frame(width: width, alignment: .leading)
    }

    private func zoomDataCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(.caption.monospacedDigit()).foregroundColor(.primary).frame(width: width, alignment: .leading)
    }

    private func zoomNameCell(line: SummaryLine, width: CGFloat) -> some View {
        Button(action: { zoomTarget = line.target }) {
            HStack(spacing: 4) {
                Text(line.label).font(.caption.monospacedDigit()).foregroundColor(.white).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "magnifyingglass").font(.caption2).foregroundColor(clubGold).frame(width: 14, alignment: .trailing)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func formatStroke(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    private func signedStroke(_ value: Double) -> String {
        let raw = formatStroke(abs(value))
        if value > 0.001 { return "+\(raw)" }
        if value < -0.001 { return "-\(raw)" }
        return "0"
    }

    private func pairStrokeTotals(rows: [PairZoomRow]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for row in rows {
            for ball in row.basePlayers + row.oppPlayers { totals[ball.alias, default: 0] += (ball.individualStrokes + ball.laneStrokes) }
        }
        return totals
    }

    private func pairHeaderText(alias: String, totals: [String: Double]) -> String {
        "\(alias) S\(formatStroke(totals[alias] ?? 0))"
    }

    private func zoomSheetHeader(target: ZoomTarget) -> String {
        let holeText: String = matchManager.lastHoleForZoom(segment: selectedSegment).map { "Hoyo \($0)" } ?? "Sin hoyos"
        switch target {
        case .individual(let opp):
            return "\(selectedSegment) · \(holeText) · \(matchManager.yoAlias) vs \(opp)"
        case .parejas(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return "\(selectedSegment) · \(holeText) · Pareja" }
            let matchup = "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
            let carry = (lane.strokeCarrier?.isEmpty == false) ? " · Lleva \(lane.strokeCarrier!)" : ""
            return "\(selectedSegment) · \(holeText) · \(matchup) · Strokes \(formatStroke(lane.strokes))\(carry)"
        case .unidades:
            return "\(selectedSegment) · \(holeText) · Detalle de Unidades"
        }
    }
}
