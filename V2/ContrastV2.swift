//
//  ContrastV2.swift
//  Caddie Score — contrastar la tarjeta de un jugador por vuelta (y corregir)
//
//  "Del F9 dame los golpes, los putts y los strokes de Rob" / "del hoyo 3 al 7 de Daniel": una lista hoyo por hoyo
//  de UN jugador (golpes, putts, quién le da stroke, si se levantó) para compararla con la tarjeta de papel, con el total
//  de la vuelta, y cada hoyo se puede leer en voz alta o corregir. Mismos números que la Tarjeta y Resultados.
//

import SwiftUI

struct PlayerHoleLineV2: Equatable {
    let hole: Int
    let par: Int
    let gross: Int?
    let putts: Int?
    /// Quién le da stroke en ese hoyo y cuánto (puede ser medio).
    let strokes: [(from: String, amount: Double)]
    let lost: Bool

    static func == (a: PlayerHoleLineV2, b: PlayerHoleLineV2) -> Bool {
        a.hole == b.hole && a.par == b.par && a.gross == b.gross && a.putts == b.putts && a.lost == b.lost
            && a.strokes.map(\.from) == b.strokes.map(\.from) && a.strokes.map(\.amount) == b.strokes.map(\.amount)
    }
}

extension MatchManager {
    /// Los hoyos de "F9", "B9" o todos, en el orden de juego del Setup.
    func holesForNineV2(_ segment: String?) -> [Int] {
        let order = playOrder()
        switch segment?.uppercased() {
        case "F9": return Array(order.prefix(9))
        case "B9": return Array(order.suffix(9))
        default: return order
        }
    }

    private func wrapRange(_ from: Int, _ to: Int) -> [Int] {
        guard (1...18).contains(from), (1...18).contains(to) else { return [] }
        var out = [from]; var h = from
        while h != to { h = h % 18 + 1; out.append(h) }
        return out
    }

    /// Hoyo por hoyo de un jugador: golpes, putts y strokes que recibe (con los strokes de cada match con yo).
    func playerHolesV2(alias: String, holes: [Int]) -> [PlayerHoleLineV2] {
        holes.map { hole in
            let gross = getScore(hole: hole, player: alias)
            let putts = getPutts(hole: hole, player: alias)
            var strokes: [(from: String, amount: Double)] = []
            for other in players.map(\.alias) where other != alias {
                let isMe = alias == yoAlias
                guard isMe || other == yoAlias else { continue }          // los strokes son contra yo
                let rival = isMe ? other : alias
                let st = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: rival, hole: hole, carryAlias: nil)
                let mine = isMe ? st.yo : st.opp
                if mine > 0 { strokes.append((other, mine)) }
            }
            return PlayerHoleLineV2(hole: hole, par: getHole(hole)?.par ?? 4, gross: gross > 0 ? gross : nil,
                                    putts: putts > 0 ? putts : nil, strokes: strokes,
                                    lost: cellOverride(alias: alias, hole: hole) == .lostHole)
        }
    }

    private func strokeAmountText(_ a: Double) -> String {
        let whole = Int(a)
        return abs(a - Double(whole)) > 0.01 ? (whole == 0 ? "medio stroke" : "\(whole) y medio strokes") : (whole == 1 ? "un stroke" : "\(whole) strokes")
    }

    /// Una línea hablada de un hoyo: "Hoyo 5, par 4: 6 golpes, 2 putts, recibe un stroke de Roberto."
    func playerHoleSpokenV2(_ line: PlayerHoleLineV2) -> String {
        guard let g = line.gross else { return "Hoyo \(line.hole), par \(line.par): sin anotar." }
        var text = "Hoyo \(line.hole), par \(line.par): \(g) golpes"
        if let p = line.putts { text += ", \(p) putt\(p == 1 ? "" : "s")" }
        if line.lost { text += ", se levantó, hoyo perdido" }
        else if !line.strokes.isEmpty {
            text += ", recibe " + spokenList(line.strokes.map { "\(strokeAmountText($0.amount)) de \(spokenName($0.from))" })
        }
        return text + "."
    }

    /// Totales de un grupo de hoyos: golpes, putts, sobre/bajo par y strokes.
    func playerTotalsV2(_ lines: [PlayerHoleLineV2]) -> (gross: Int, putts: Int, holes: Int, versusPar: Int, strokes: Double) {
        let played = lines.filter { $0.gross != nil }
        let gross = played.reduce(0) { $0 + ($1.gross ?? 0) }
        return (gross, lines.reduce(0) { $0 + ($1.putts ?? 0) }, played.count,
                gross - played.reduce(0) { $0 + $1.par }, lines.reduce(0) { $0 + $1.strokes.reduce(0) { $0 + $1.amount } })
    }

    /// Todo lo de un jugador en un grupo de hoyos, para leerlo y compararlo con la tarjeta de papel.
    func playerCardReadbackV2(alias: String, holes: [Int], label: String, detail: Bool = true) -> String {
        let lines = playerHolesV2(alias: alias, holes: holes)
        let t = playerTotalsV2(lines)
        if !detail {
            // Resumen: los golpes en fila, el total y en qué hoyos recibe stroke.
            let row = lines.map { $0.gross.map(String.init) ?? "sin anotar" }.joined(separator: ", ")
            var short = "\(spokenName(alias)), \(label): \(row)."
            if t.holes > 0 {
                short += " Total \(t.gross) golpes, " + (t.versusPar == 0 ? "par del campo" : t.versusPar > 0 ? "\(t.versusPar) sobre par" : "\(-t.versusPar) bajo par")
                if t.putts > 0 { short += ", \(t.putts) putts" }
                short += "."
            }
            let strokeHoles = lines.filter { !$0.strokes.isEmpty && !$0.lost }.map(\.hole)
            if !strokeHoles.isEmpty { short += " Recibe stroke en " + (strokeHoles.count == 1 ? "el hoyo \(strokeHoles[0])" : "los hoyos " + spokenList(strokeHoles.map(String.init))) + "." }
            return short
        }
        var parts = ["\(spokenName(alias)), \(label)."] + lines.map(playerHoleSpokenV2)
        if t.holes == 0 { parts.append("Todavía no hay golpes anotados.") }
        else {
            let rel = t.versusPar == 0 ? "par del campo" : t.versusPar > 0 ? "\(t.versusPar) sobre par" : "\(-t.versusPar) bajo par"
            var total = "Total \(label): \(t.gross) golpes en \(t.holes) hoyo\(t.holes == 1 ? "" : "s"), \(rel)"
            if t.putts > 0 { total += ", \(t.putts) putts" }
            if t.strokes > 0 { total += ", \(strokeAmountText(t.strokes)) recibidos" }
            parts.append(total + ".")
        }
        return parts.joined(separator: " ")
    }

    /// Pregunta hablada o de botón: de quién, de qué nueve o qué hoyos.
    func playerCardAnswerV2(alias: String?, segment: String?, from: Int?, to: Int?, currentHole: Int, detail: Bool = true) -> String {
        let p = alias ?? yoAlias
        if let from {
            let holes = wrapRange(from, to ?? from)
            guard !holes.isEmpty else { return "No entendí de qué hoyos hablas." }
            return playerCardReadbackV2(alias: p, holes: holes, label: holes.count == 1 ? "hoyo \(holes[0])" : "hoyos \(holes[0]) al \(holes[holes.count - 1])", detail: detail || holes.count == 1)
        }
        let seg = segment?.uppercased()
        let label = seg == "F9" ? "F9" : seg == "B9" ? "B9" : "los 18 hoyos"
        return playerCardReadbackV2(alias: p, holes: holesForNineV2(seg), label: label, detail: detail)
    }
}

// MARK: - Pantalla

struct ContrastSheetV2: View {
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    @State private var alias: String
    @State private var segment: String
    /// Hoyo que se estaba revisando (viene de una lectura): su fila se resalta y la lista se desplaza a él.
    let focusHole: Int?
    @State private var correction: CorrectionTargetV2?
    @State private var speech = SpeechReadbackV2()

    init(matchManager: MatchManager, alias: String? = nil, segment: String? = nil, focusHole: Int? = nil) {
        self.matchManager = matchManager
        self.focusHole = focusHole
        _alias = State(initialValue: alias ?? matchManager.yoAlias)
        _segment = State(initialValue: segment?.uppercased() == "ALL" ? "ALL" : (segment?.uppercased() == "B9" ? "B9" : "F9"))
    }

    private var holes: [Int] { matchManager.holesForNineV2(segment == "ALL" ? nil : segment) }
    private var label: String { segment == "ALL" ? "los 18 hoyos" : segment }

    var body: some View {
        let lines = matchManager.playerHolesV2(alias: alias, holes: holes)
        let totals = matchManager.playerTotalsV2(lines)
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: CSV2.s1) {
                    HStack {
                        Text("Contrastar tarjeta").font(.v2Name).foregroundStyle(CSV2.ink)
                        Spacer()
                        Button("Listo") { speech.stop(); dismiss() }.font(.v2Body).foregroundStyle(CSV2.green).frame(minHeight: CSV2.minTap)
                    }
                    AliasChipRowV2(items: matchManager.players.map { ($0.alias, $0.name) }, selected: alias) { alias = $0 }
                    Picker("Vuelta", selection: $segment) {
                        Text("F9").tag("F9"); Text("B9").tag("B9"); Text("18").tag("ALL")
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        Button { speech.speak(matchManager.playerCardReadbackV2(alias: alias, holes: holes, label: label)) } label: {
                            Label("Leer \(label)", systemImage: "speaker.wave.2").font(.v2Label.weight(.semibold)).foregroundStyle(CSV2.green)
                                .padding(.horizontal, 12).frame(minHeight: 44).overlay(Capsule().stroke(CSV2.green.opacity(0.5)))
                        }.buttonStyle(.plain)
                        if speech.isSpeaking {
                            Button { speech.stop() } label: {
                                Label("Detener", systemImage: "stop.fill").font(.v2Label).foregroundStyle(CSV2.warning).frame(minHeight: 44)
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
                .padding(CSV2.s2)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(lines, id: \.hole) { line in
                                row(line).id(line.hole)
                                    .background(line.hole == focusHole ? CSV2.green.opacity(0.14) : Color.clear)
                                RowDividerV2()
                            }
                            totalsRow(totals)
                        }
                        .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
                        .padding(.horizontal, CSV2.s2).padding(.bottom, CSV2.s3)
                    }
                    .onAppear { if let focusHole { proxy.scrollTo(focusHole, anchor: .center) } }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(item: $correction) { target in
            CorrectionSheetV2(target: target, matchManager: matchManager).presentationDetents([.large])
        }
    }

    private func row(_ line: PlayerHoleLineV2) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("H\(line.hole)").font(.v2Name).foregroundStyle(CSV2.ink)
                Text("par \(line.par)").font(.v2Label).foregroundStyle(CSV2.secondary)
            }
            .frame(width: 56, alignment: .leading)
            ScoreMarkV2(gross: line.gross, par: line.par, size: 36,
                        strokeDots: line.lost ? 0 : (line.strokes.map(\.amount).max() ?? 0), lostHole: line.lost)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.putts.map { "\($0) putts" } ?? (line.gross == nil ? "sin anotar" : "sin putts"))
                    .font(.v2Body).foregroundStyle(line.gross == nil || line.putts == nil ? CSV2.warning : CSV2.ink)
                if line.lost { Text("se levantó").font(.v2Label).foregroundStyle(CSV2.red) }
                else if !line.strokes.isEmpty {
                    Text("stroke de " + line.strokes.map(\.from).joined(separator: ", "))
                        .font(.v2Label).foregroundStyle(CSV2.stroke)
                }
            }
            Spacer(minLength: 4)
            Button { speech.speak(matchManager.playerHoleSpokenV2(line)) } label: {
                Image(systemName: "speaker.wave.2").frame(width: CSV2.minTap, height: CSV2.minTap).foregroundStyle(CSV2.green)
            }
            .buttonStyle(.plain).accessibilityLabel("Leer el hoyo \(line.hole)")
            Button { openCorrection(line) } label: {
                Image(systemName: "pencil").frame(width: CSV2.minTap, height: CSV2.minTap).foregroundStyle(CSV2.ink)
            }
            .buttonStyle(.plain).accessibilityLabel("Corregir el hoyo \(line.hole)")
        }
        .padding(.horizontal, CSV2.s2).padding(.vertical, 4)
    }

    private func totalsRow(_ t: (gross: Int, putts: Int, holes: Int, versusPar: Int, strokes: Double)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total \(label)").capsStyleV2()
            Text("\(t.gross) golpes en \(t.holes) hoyo\(t.holes == 1 ? "" : "s")" +
                 (t.holes == 0 ? "" : t.versusPar == 0 ? " · par del campo" : t.versusPar > 0 ? " · \(t.versusPar) sobre par" : " · \(-t.versusPar) bajo par"))
                .font(.v2Name).foregroundStyle(CSV2.ink)
            Text("\(t.putts) putts" + (t.strokes > 0 ? " · \(String(format: t.strokes.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", t.strokes)) strokes recibidos" : ""))
                .font(.v2Label).foregroundStyle(CSV2.secondary)
        }
        .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openCorrection(_ line: PlayerHoleLineV2) {
        let name = matchManager.players.first { $0.alias == alias }?.name ?? alias
        correction = CorrectionTargetV2(hole: line.hole, par: line.par, alias: alias, playerName: name,
                                        score: line.gross ?? line.par, putts: line.putts ?? 2)
    }
}

/// Corregir UN hoyo de todos los jugadores: scores, putts, oyes y unidades (cada lápiz abre la hoja de corrección).
struct HoleCorrectionSheetV2: View {
    @ObservedObject var matchManager: MatchManager
    let hole: Int
    @Environment(\.dismiss) private var dismiss
    @State private var correction: CorrectionTargetV2?

    var body: some View {
        let par = matchManager.getHole(hole)?.par ?? 4
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: CSV2.s2) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Corregir hoyo \(hole)").font(.v2Name).foregroundStyle(CSV2.ink)
                        Text("par \(par)").font(.v2Label).foregroundStyle(CSV2.secondary)
                    }
                    Spacer()
                    Button("Listo") { dismiss() }.font(.v2Body).foregroundStyle(CSV2.green).frame(minHeight: CSV2.minTap)
                }
                VStack(spacing: 0) {
                    ForEach(matchManager.players) { player in
                        let g = matchManager.getScore(hole: hole, player: player.alias)
                        let p = matchManager.getPutts(hole: hole, player: player.alias)
                        HStack(spacing: 10) {
                            Text(player.alias).font(.v2Name).foregroundStyle(CSV2.ink).frame(width: 64, alignment: .leading)
                            ScoreMarkV2(gross: g > 0 ? g : nil, par: par, size: 36,
                                        lostHole: matchManager.cellOverride(alias: player.alias, hole: hole) == .lostHole)
                            Text(p > 0 ? "\(p) putts" : (g > 0 ? "sin putts" : "sin anotar")).font(.v2Body)
                                .foregroundStyle(g == 0 || p == 0 ? CSV2.warning : CSV2.ink)
                            Spacer()
                            Button {
                                correction = CorrectionTargetV2(hole: hole, par: par, alias: player.alias, playerName: player.name,
                                                                score: g > 0 ? g : par, putts: p > 0 ? p : 2)
                            } label: {
                                Image(systemName: "pencil").frame(width: CSV2.minTap, height: CSV2.minTap).foregroundStyle(CSV2.ink)
                            }
                            .buttonStyle(.plain).accessibilityLabel("Corregir a \(player.name) en el hoyo \(hole)")
                        }
                        .padding(.horizontal, CSV2.s2).padding(.vertical, 4)
                        RowDividerV2()
                    }
                }
                .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
                Spacer(minLength: 0)
            }
            .padding(CSV2.s2)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(item: $correction) { target in
            CorrectionSheetV2(target: target, matchManager: matchManager).presentationDetents([.large])
        }
    }
}

#if DEBUG
#Preview("ContrastSheetV2 · DAN F9") {
    let manager = MatchManager()
    manager.loadDemo18()
    return ContrastSheetV2(matchManager: manager)
}
#endif
