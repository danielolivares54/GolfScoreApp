//
//  HistorialV2.swift
//  Caddie Score — Vista v2, Paso 9: historial de rondas cerradas
//
//  Mismos datos que RoundHistoryView (closed_rounds/*.json): fecha, campo, hoyo de salida, total, y por rival el
//  dinero, F9/B9, resultado del match y los strokes de esa ronda. Decisión de Daniel (21-oct): sin la insignia
//  "VIGENTE" ni el cuadro beige "Strokes esa ronda"; esa información pasa a una línea azul
//  ("DAN recibe 8 → próximo: recibe 7") que solo aparece en la ronda más reciente contra cada rival.
//

import SwiftUI

struct HistorialV2: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var directory = PlayerDirectoryStore.shared
    @State private var rounds: [RoundResultFile] = []
    @State private var selectedPlayerName: String
    @State private var showStats = false
    @State private var showPicker = false

    /// Solo para vistas previas: rondas de muestra en lugar de leer closed_rounds del disco.
    private let sampleRounds: [RoundResultFile]?

    init(initialPlayerName: String = "Todos", sampleRounds: [RoundResultFile]? = nil) {
        _selectedPlayerName = State(initialValue: initialPlayerName)
        self.sampleRounds = sampleRounds
    }

    // MARK: Datos (mismas reglas que la v1)

    private func name(for round: RoundResultFile, alias: String?) -> String? {
        guard let alias else { return nil }
        return round.players.first { $0.alias == alias }?.name
    }

    private var playerNames: [String] {
        var names = Set<String>()
        for round in rounds {
            for line in round.lines where line.scope == "individual" {
                if let n = name(for: round, alias: line.opponentAlias) { names.insert(n) }
            }
        }
        for entry in directory.entries where entry.active { names.insert(entry.name) }
        return ["Todos"] + names.sorted()
    }

    private var filteredRounds: [RoundResultFile] {
        guard selectedPlayerName != "Todos" else { return rounds }
        return rounds.filter { round in
            round.lines.contains { $0.scope == "individual" && name(for: round, alias: $0.opponentAlias) == selectedPlayerName }
        }
    }

    /// La ronda más reciente contra cada rival define el stroke del próximo match (rounds viene de más nueva a más vieja).
    private var mostRecentRoundIdByName: [String: String] {
        var out: [String: String] = [:]
        for round in rounds {
            for line in round.lines where line.scope == "individual" {
                if let n = name(for: round, alias: line.opponentAlias), out[n] == nil { out[n] = round.roundId }
            }
        }
        return out
    }

    // MARK: Cuerpo

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: CSV2.s2) {
                        if filteredRounds.isEmpty {
                            Text("Sin rondas cerradas todavía").font(.v2Body).foregroundStyle(CSV2.secondary)
                                .frame(maxWidth: .infinity).padding(CSV2.s3)
                        }
                        ForEach(filteredRounds, id: \.roundId) { roundCard($0) }
                    }
                    .padding(CSV2.s2)
                }
            }
        }
        .onAppear { rounds = sampleRounds ?? RoundResultFile.loadAll() }
        .sheet(isPresented: $showPicker) { playerPicker }
        .sheet(isPresented: $showStats) { MyHistoryV2(sampleRounds: sampleRounds) }
    }

    private var header: some View {
        HStack(spacing: CSV2.s1) {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text("Volver").font(.v2Body)
                }
                .foregroundStyle(CSV2.ink).frame(minHeight: CSV2.minTap)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Historial").font(.v2Name).foregroundStyle(CSV2.ink)
            Spacer()
            Button { showPicker = true } label: {
                HStack(spacing: 4) {
                    Text(selectedPlayerName).font(.v2Body).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(CSV2.green).frame(minHeight: CSV2.minTap)
            }
            .buttonStyle(.plain)
            Button { showStats = true } label: {
                Image(systemName: "chart.bar.fill").font(.system(size: 20)).foregroundStyle(CSV2.green)
                    .frame(width: CSV2.minTap, height: CSV2.minTap)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mi historial")
        }
        .padding(.horizontal, CSV2.s2)
    }

    private var playerPicker: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Filtrar por rival").font(.v2Name).foregroundStyle(CSV2.ink)
                    Spacer()
                    PrimaryButtonV2(title: "Cerrar") { showPicker = false }
                }
                .padding(CSV2.s2)
                ScrollView {
                    CardV2 {
                        VStack(spacing: 0) {
                            ForEach(Array(playerNames.enumerated()), id: \.offset) { index, name in
                                if index > 0 { Rectangle().fill(CSV2.rowLine).frame(height: 1) }
                                Button {
                                    selectedPlayerName = name
                                    showPicker = false
                                } label: {
                                    HStack {
                                        Text(name).font(.v2Body).foregroundStyle(CSV2.ink)
                                        Spacer()
                                        if name == selectedPlayerName {
                                            Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(CSV2.green)
                                        }
                                    }
                                    .padding(.horizontal, CSV2.s2).frame(minHeight: 56).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, CSV2.s2)
                }
            }
        }
    }

    // MARK: Tarjeta de ronda

    private func roundCard(_ round: RoundResultFile) -> some View {
        let shown = round.lines.filter { line in
            guard line.scope == "individual" else { return false }
            return selectedPlayerName == "Todos" || name(for: round, alias: line.opponentAlias) == selectedPlayerName
        }
        return CardV2 {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(round.date) · \(round.courseName)").font(.v2Name).foregroundStyle(CSV2.ink)
                        Text("Sale H\(round.startHole)").font(.v2Label).foregroundStyle(CSV2.secondary)
                    }
                    Spacer()
                    MoneyTextV2(amount: round.totalMoney, size: 22, weight: .semibold)
                }
                .padding(.horizontal, CSV2.s2).padding(.vertical, 12)
                ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                    Rectangle().fill(CSV2.rowLine).frame(height: 1)
                    rivalRow(round: round, line: line)
                }
            }
        }
    }

    private func rivalRow(round: RoundResultFile, line: RoundResultLine) -> some View {
        let rivalName = name(for: round, alias: line.opponentAlias)
        let yoAlias = round.players.first?.alias ?? "DAN"
        let strokes = round.players.first { $0.alias == line.opponentAlias }?.strokesVsBase ?? 0
        let isLatest = rivalName.map { mostRecentRoundIdByName[$0] == round.roundId } ?? false
        let live = rivalName.flatMap { n in directory.entries.first { $0.name == n }?.strokesVsBase }
        let rival = line.opponentAlias ?? "—"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rivalName ?? rival).font(.v2Body).foregroundStyle(CSV2.ink)
                Spacer()
                MoneyTextV2(amount: line.totalMoney, size: 17, weight: .semibold)
            }
            resultLine(line)
            HStack(spacing: 6) {
                Circle().fill(CSV2.stroke).frame(width: 9, height: 9).opacity(abs(strokes) > 0.001 ? 1 : 0.35)
                Text(strokesLine(strokes: strokes, rival: rival, yo: yoAlias, latest: isLatest, live: live))
                    .font(.v2Label).foregroundStyle(CSV2.stroke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, CSV2.s2).padding(.vertical, 12)
    }

    /// "F9 2↑ · B9 1↓ · match ganado"
    private func resultLine(_ line: RoundResultLine) -> Text {
        func nine(_ label: String, _ points: Int?) -> Text {
            let value: Text
            if let p = points {
                value = p > 0 ? Text("\(p)↑").foregroundStyle(CSV2.green)
                    : p < 0 ? Text("\(-p)↓").foregroundStyle(CSV2.red) : Text("E").foregroundStyle(CSV2.secondary)
            } else {
                value = Text("—").foregroundStyle(CSV2.secondary)
            }
            return Text("\(label) ").foregroundStyle(CSV2.secondary) + value
        }
        let match = line.matchPoints > 0 ? "match ganado" : line.matchPoints < 0 ? "match perdido" : "match empatado"
        let color = line.matchPoints > 0 ? CSV2.green : line.matchPoints < 0 ? CSV2.red : CSV2.secondary
        return (nine("F9", line.f9Points) + Text("  ·  ").foregroundStyle(CSV2.secondary)
                + nine("B9", line.b9Points) + Text("  ·  ").foregroundStyle(CSV2.secondary)
                + Text(match).foregroundStyle(color))
            .font(.v2Label)
    }

    /// "DAN recibe 8 → próximo: recibe 7" (la parte de "próximo" solo en la ronda más reciente contra ese rival).
    private func strokesLine(strokes: Double, rival: String, yo: String, latest: Bool, live: Double?) -> String {
        func phrase(_ value: Double) -> String {
            guard abs(value) > 0.001 else { return "sin strokes" }
            return "\(value > 0 ? rival : yo) recibe \(strokesTextV2(value))"
        }
        var text = phrase(strokes)
        if latest, let live {
            // Misma redacción corta: si no cambia quién recibe basta con la cantidad.
            let sameSide = (live > 0) == (strokes > 0) && abs(live) > 0.001 && abs(strokes) > 0.001
            text += " → próximo: " + (sameSide ? "recibe \(strokesTextV2(live))" : phrase(live))
        }
        return text
    }
}

#if DEBUG
/// Rondas de muestra (CGM) para las vistas previas: una del 20 oct saliendo en el 10 y una del 13 oct.
enum HistorySamplesV2 {
    static var rounds: [RoundResultFile] {
        let course = CourseCatalog.default
        func scores(extra: Int) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: course.holes.map { ("\($0.number)", $0.par + ($0.number >= 10 ? extra : 0)) })
        }
        func putts() -> [String: Int] { Dictionary(uniqueKeysWithValues: course.holes.map { ("\($0.number)", 2) }) }
        func line(_ rival: String, _ f9: Int, _ b9: Int, _ match: Int, _ money: Int) -> RoundResultLine {
            RoundResultLine(label: rival, scope: "individual", opponentAlias: rival, vueltaPoints: f9 + b9, presionPoints: 0,
                            carryPoints: 0, carryActive: false, matchPoints: match, unitsPoints: 0, vueltaMoney: 0,
                            presionMoney: 0, carryMoney: 0, matchMoney: 0, unitsMoney: 0, totalMoney: money,
                            f9Points: f9, b9Points: b9)
        }
        func round(_ id: String, _ date: String, start: Int, rob: Double, fer: Double, closed: TimeInterval) -> RoundResultFile {
            RoundResultFile(
                roundId: id, date: date, courseId: course.id, courseName: course.name, startHole: start,
                players: [
                    RoundResultPlayer(alias: "DAN", name: "Daniel", strokesVsBase: 0, scores: scores(extra: 1), putts: putts()),
                    RoundResultPlayer(alias: "ROB", name: "Roberto", strokesVsBase: rob, scores: scores(extra: 0), putts: [:]),
                    RoundResultPlayer(alias: "FER", name: "Fernando", strokesVsBase: fer, scores: scores(extra: 1), putts: [:]),
                ],
                lines: [line("ROB", 2, -1, 1, 425), line("FER", -1, -2, -1, -300)],
                totalMoney: 125, closedAt: Date(timeIntervalSinceNow: closed), oyesWinsByAlias: ["DAN": 2])
        }
        return [round("a", "20 oct", start: 10, rob: -8, fer: 3, closed: -86_400),
                round("b", "13 oct", start: 1, rob: -9, fer: 0, closed: -7 * 86_400)]
    }
}

#Preview("HistorialV2 · rondas de muestra") {
    HistorialV2(sampleRounds: HistorySamplesV2.rounds)
}
#endif
