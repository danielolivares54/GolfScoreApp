//
//  CardAnswersV2.swift
//  Caddie Score — v2t: respuestas de resultados (conteo primero, dinero después) y cómo quedó un hoyo contra el rival
//
//  Orden de toda respuesta de resultados: PRIMERO las apuestas por su conteo (vuelta, presión y match: hoyos arriba o
//  abajo) y DESPUÉS el dinero: el total y luego individuales y parejas.
//
//  "¿Cómo quedó el hoyo 8 de Daniel contra Roberto?" → qué tiró cada uno, quién lleva stroke en ese hoyo, si ganó,
//  perdió o empató, cuánto iba antes la vuelta y las presiones y cómo quedan ahora. Se puede pedir un hoyo, un grupo de
//  hoyos ("del 5 al 8") o el último. Todo sale de las mismas filas hoyo por hoyo que ve Resultados.
//

import Foundation

extension MatchManager {

    // MARK: Palabras para decir un conteo

    /// "2 arriba" / "1 abajo" / "parejos".
    func countWords(_ n: Int) -> String { n > 0 ? "\(n) arriba" : n < 0 ? "\(-n) abajo" : "parejos" }

    /// Número con signo desde el lado del usuario: "más 3", "menos 2", "cero" (más = va ganando).
    func signedWords(_ n: Int) -> String { n > 0 ? "más \(n)" : n < 0 ? "menos \(-n)" : "cero" }

    private func strokesWords(_ amount: Double) -> String {
        let whole = Int(amount)
        return abs(amount - Double(whole)) > 0.01 ? (whole == 0 ? "medio" : "\(whole) y medio") : "\(whole)"
    }

    private func nineOf(_ hole: Int) -> String { segmentForHole(hole) }

    private func holeRange(_ from: Int, _ to: Int) -> [Int] {
        guard (1...18).contains(from), (1...18).contains(to) else { return [] }
        var out = [from]; var h = from
        while h != to { h = h % 18 + 1; out.append(h) }
        return out
    }

    private func moneyWords(_ v: Int) -> String { v > 0 ? "ganando \(v) pesos" : v < 0 ? "perdiendo \(-v) pesos" : "a mano" }

    // MARK: Cómo vamos: conteo primero, dinero después

    /// Los conteos de cada match (F9, B9, match y presiones abiertas), sin dinero.
    func countsReadbackV2(detail: Bool = true) -> String {
        if !detail { return scoreboardReadbackV2(kind: "resumen", alias: nil, opponent: nil, segment: nil) }
        let rows = resultadoRowsV2()
        guard !rows.isEmpty else { return "Todavía no hay matches en la ronda." }
        func line(_ row: ResultadoRowV2) -> String {
            let name = row.isPair ? "pareja \(row.title)" + (row.rivalsText.map { " contra \($0)" } ?? "") : "contra " + spokenName(row.title)
            let match = row.f9Net + row.b9Net
            let open = row.f9Presiones.count + row.b9Presiones.count
            if !detail { return name + ": match \(countWords(match))" }
            var parts = ["F9 \(countWords(row.f9Net))", "B9 \(countWords(row.b9Net))", "match \(countWords(match))"]
            parts.append(open == 0 ? "sin presiones abiertas" : "\(open) presion\(open == 1 ? "" : "es") abierta\(open == 1 ? "" : "s")")
            return name + ": " + parts.joined(separator: ", ")
        }
        let individuals = rows.filter { !$0.isPair }.map(line)
        let pairs = rows.filter(\.isPair).map(line)
        var text = "Por conteo."
        if let n = pairsNoticeV2() { text += " Ojo: " + pairsNoticeTextV2(n) }
        if !individuals.isEmpty { text += " Individuales: " + individuals.joined(separator: "; ") + "." }
        if !pairs.isEmpty { text += " Parejas: " + pairs.joined(separator: "; ") + "." }
        return text
    }

    /// El dinero: primero el total y luego individuales y parejas.
    func moneyReadbackV2(detail: Bool = true) -> String {
        let rows = resultadoRowsV2()
        guard !rows.isEmpty else { return "Todavía no hay matches en la ronda." }
        func line(_ row: ResultadoRowV2) -> String {
            let name = row.isPair ? "con \(row.title.replacingOccurrences(of: "con ", with: ""))" + (row.rivalsText.map { " contra \($0)" } ?? "") : "contra " + spokenName(row.title)
            return "\(name), \(moneyWords(row.money))"
        }
        var text = "Dinero. En total, \(moneyWords(resultadoTotalV2()))."
        if let n = pairsNoticeV2() { text += " Ojo: " + pairsNoticeTextV2(n) }
        let individuals = rows.filter { !$0.isPair }, pairs = rows.filter(\.isPair)
        if !individuals.isEmpty {
            let sum = moneyWords(individuals.reduce(0) { $0 + $1.money })
            text += detail ? " Individuales, \(sum): " + individuals.map(line).joined(separator: "; ") + "." : " Individuales, \(sum)."
        }
        if !pairs.isEmpty {
            let sum = moneyWords(pairs.reduce(0) { $0 + $1.money })
            text += detail ? " Parejas, \(sum): " + pairs.map(line).joined(separator: "; ") + "." : " Parejas, \(sum)."
        }
        return text
    }

    // MARK: Cómo quedó un hoyo (o un grupo de hoyos) contra el rival

    /// `alias` = de quién se pregunta; `opponent` = contra quién (nil = todos sus matches).
    func holeResultsReadbackV2(alias: String?, opponent: String?, from: Int?, to: Int?, currentHole: Int, detail: Bool = true) -> String {
        let me = yoAlias
        let p = alias ?? me
        let holes = (from.map { f in holeRange(f, to ?? f) } ?? [currentHole])
        guard !holes.isEmpty else { return "No entendí de qué hoyos hablas." }
        var blocks: [String] = []

        // Individual: yo contra cada rival.
        for opp in players.map(\.alias) where opp != me {
            guard p == me || p == opp else { continue }
            if let opponent, opponent != (p == me ? opp : me) { continue }
            if let b = individualHoleBlock(perspective: p, opponent: opp, holes: holes, detail: detail) { blocks.append(b) }
        }
        // Parejas donde juega p (y, si se dijo, donde el rival está del otro lado).
        for lane in activeLanes where lane.base.contains(p) || lane.opp.contains(p) {
            if let opponent, !((lane.base.contains(p) ? lane.opp : lane.base).contains(opponent)) { continue }
            if let b = pairHoleBlock(perspective: p, lane: lane, holes: holes, detail: detail) { blocks.append(b) }
        }
        guard !blocks.isEmpty else { return "No encontré ese match." }
        var text = blocks.joined(separator: " ")
        if let n = pairsNoticeV2(hole: holes.count == 1 ? holes[0] : nil), opponent == nil { text += " Ojo: " + pairsNoticeTextV2(n) }
        return text
    }

    /// "¿Cómo voy contra Ricardo?": el último hoyo jugado de cada match (quién ganó, golpes brutos, strokes) y cómo va la vuelta. Siempre breve.
    func statusReadbackV2(alias: String?, opponent: String?, hole: Int? = nil) -> String {
        let me = yoAlias
        let p = alias ?? me
        let order = playOrder()
        func lastHole(_ holesWithRows: Set<Int>) -> Int? { order.last { holesWithRows.contains($0) } }
        var singles: [String] = [], pairs: [String] = []
        for opp in players.map(\.alias) where opp != me {
            guard p == me || p == opp else { continue }
            if let opponent, opponent != (p == me ? opp : me) { continue }
            let held = Set(["F9", "B9"].flatMap { individualZoomRows(opponentAlias: opp, segmentOverride: $0).map(\.hole) })
            if let h = hole ?? lastHole(held), let b = individualHoleBlock(perspective: p, opponent: opp, holes: [h], detail: false, totals: true) { singles.append(b) }
        }
        for lane in activeLanes where lane.base.contains(p) || lane.opp.contains(p) {
            if let opponent, !((lane.base.contains(p) ? lane.opp : lane.base).contains(opponent)) { continue }
            let held = Set(["F9", "B9"].flatMap { pairZoomRows(laneId: lane.id, segmentOverride: $0).map(\.hole) })
            if let h = hole ?? lastHole(held), let b = pairHoleBlock(perspective: p, lane: lane, holes: [h], detail: false, totals: true) { pairs.append(b) }
        }
        guard !(singles + pairs).isEmpty else { return "Todavía no hay hoyos completos para ese match." }
        // Primero los individuales y luego las parejas contrarias.
        var out: [String] = []
        if !singles.isEmpty { out.append(singles.joined(separator: " ")) }
        if !pairs.isEmpty { out.append(pairs.joined(separator: " ")) }
        return out.joined(separator: " ")
    }


    private func presionWords(_ open: [Int], sign: Int) -> String {
        "presión " + signedWords(open.reduce(0) { $0 + ($1 * sign > 0 ? 1 : $1 * sign < 0 ? -1 : 0) })
    }

    /// El match en ese hoyo: la vuelta de su nueve hasta ahí más la del otro nueve si ya se había jugado antes.
    private func matchAsOf<R>(_ hole: Int, nineRows: [R], otherNine: String, sign: Int, target: UnitLogTarget) -> Int {
        let order = playOrder()
        let idx = order.firstIndex(of: hole) ?? 0
        let current: Int
        let other: [(hole: Int, accum: Int)]
        switch target {
        case .individual(let opp):
            current = (nineRows as? [IndividualZoomRow])?.first { $0.hole == hole }?.vueltaAccum ?? 0
            other = individualZoomRows(opponentAlias: opp, segmentOverride: otherNine).map { ($0.hole, $0.vueltaAccum) }
        case .pair(let id):
            current = (nineRows as? [PairZoomRow])?.first { $0.hole == hole }?.vueltaAccum ?? 0
            other = pairZoomRows(laneId: id, segmentOverride: otherNine).map { ($0.hole, $0.vueltaAccum) }
        }
        let before = other.last { (order.firstIndex(of: $0.hole) ?? Int.max) < idx }?.accum ?? 0
        return (current + before) * sign
    }

    private func outcomeWords(_ r: Int, _ name: String) -> String { r > 0 ? "gana \(name)" : r < 0 ? "pierde \(name)" : "empatan" }

    /// Antes / ahora de la vuelta y las presiones, desde el lado de `sign`.
    private func beforeAfter(_ prev: (v: Int, p: [Int])?, _ cur: (v: Int, p: [Int]), sign: Int, nine: String) -> String {
        let beforeV = (prev?.v ?? 0) * sign, afterV = cur.v * sign
        let beforeP = prev?.p.count ?? 0, afterP = cur.p.count
        return "Vuelta \(nine): antes \(countWords(beforeV)), ahora \(countWords(afterV)). " +
            "Presiones abiertas: antes \(beforeP), ahora \(afterP)."
    }

    private func individualHoleBlock(perspective p: String, opponent opp: String, holes: [Int], detail: Bool = true, totals: Bool = false) -> String? {
        let me = yoAlias
        let sign = p == me ? 1 : -1
        let other = p == me ? opp : me
        var lines: [String] = []
        for hole in holes {
            let nine = nineOf(hole)
            let rows = individualZoomRows(opponentAlias: opp, segmentOverride: nine)
            guard let i = rows.firstIndex(where: { $0.hole == hole }) else {
                lines.append("Hoyo \(hole): todavía no hay scores de los dos.")
                continue
            }
            let r = rows[i]
            let prev = i > 0 ? (rows[i - 1].vueltaAccum, rows[i - 1].openPressures) : nil
            let myGross = sign == 1 ? r.yoGross : r.oppGross, hisGross = sign == 1 ? r.oppGross : r.yoGross
            let myStroke = sign == 1 ? r.yoStrokes : r.oppStrokes, hisStroke = sign == 1 ? r.oppStrokes : r.yoStrokes
            let myNet = sign == 1 ? r.yoNet : r.oppNet, hisNet = sign == 1 ? r.oppNet : r.yoNet
            let myName = spokenName(p), hisName = spokenName(other)
            var strokeText: String
            if myStroke > 0 { strokeText = "\(myName) recibe \(strokesWords(myStroke)) en este hoyo (neto \(Int(myNet.rounded(.down))) contra \(Int(hisNet.rounded(.down))))" }
            else if hisStroke > 0 { strokeText = "\(hisName) recibe \(strokesWords(hisStroke)) en este hoyo (neto \(Int(hisNet.rounded(.down))) contra \(Int(myNet.rounded(.down))))" }
            else { strokeText = "Sin strokes en este hoyo" }
            if cellOverride(alias: p, hole: hole) == .lostHole { strokeText += ". \(myName) se levantó" }
            else if cellOverride(alias: other, hole: hole) == .lostHole { strokeText += ". \(hisName) se levantó" }
            let ba = beforeAfter(prev.map { ($0.0, $0.1) }, (r.vueltaAccum, r.openPressures), sign: sign, nine: nine)
            if holes.count <= 3 && !detail {
                let briefStroke = myStroke > 0 ? ", ventaja de \(myName)" : hisStroke > 0 ? ", ventaja de \(hisName)" : ""
                lines.append("Hoyo \(hole): \(myGross) contra \(hisGross), \(outcomeWords(r.result * sign, myName))\(briefStroke). Vuelta \(nine) \(signedWords(r.vueltaAccum * sign))\(totals ? ", " + presionWords(r.openPressures, sign: sign) + ", match " + signedWords(matchAsOf(hole, nineRows: rows, otherNine: nine == "F9" ? "B9" : "F9", sign: sign, target: .individual(opp))) : "").")
            } else if holes.count <= 3 {
                lines.append("Hoyo \(hole): \(myName) tiró \(myGross) y \(hisName) \(hisGross). \(strokeText). \(outcomeWords(r.result * sign, myName).prefix(1).uppercased() + outcomeWords(r.result * sign, myName).dropFirst()). \(ba)")
            } else {
                lines.append("hoyo \(hole), \(myGross) contra \(hisGross), \(outcomeWords(r.result * sign, myName))")
            }
        }
        let head = detail || holes.count > 3 ? "\(spokenName(p)) contra \(spokenName(other))." : "\(spokenName(other)):"
        if holes.count <= 3 { return head + " " + lines.joined(separator: " ") }
        // Grupo de hoyos: una línea por hoyo y cómo queda la vuelta de cada nueve al final.
        var tail: [String] = []
        for nine in ["F9", "B9"] where holes.contains(where: { nineOf($0) == nine }) {
            let rows = individualZoomRows(opponentAlias: opp, segmentOverride: nine)
            if let last = rows.last { tail.append("Vuelta \(nine) ahora \(countWords(last.vueltaAccum * sign)), \(last.openPressures.count) presion\(last.openPressures.count == 1 ? "" : "es") abierta\(last.openPressures.count == 1 ? "" : "s")") }
        }
        return head + " " + lines.joined(separator: "; ") + ". " + tail.joined(separator: ". ") + "."
    }

    private func pairHoleBlock(perspective p: String, lane: LaneModel, holes: [Int], detail: Bool = true, totals: Bool = false) -> String? {
        let mine = lane.base.contains(p)
        let sign = mine ? 1 : -1
        let mySide = mine ? lane.base : lane.opp, hisSide = mine ? lane.opp : lane.base
        let fullHead = "Pareja \(mySide.map(spokenName).joined(separator: " y ")) contra \(hisSide.map(spokenName).joined(separator: " y "))."
        let head = detail || holes.count > 3 ? fullHead : ""
        var lines: [String] = []
        for hole in holes {
            let nine = nineOf(hole)
            let rows = pairZoomRows(laneId: lane.id, segmentOverride: nine)
            guard let i = rows.firstIndex(where: { $0.hole == hole }) else {
                lines.append("Hoyo \(hole): todavía no hay los cuatro scores.")
                continue
            }
            let r = rows[i]
            let prev = i > 0 ? (rows[i - 1].vueltaAccum, rows[i - 1].openPressures) : nil
            let myBalls = mine ? r.basePlayers : r.oppPlayers, hisBalls = mine ? r.oppPlayers : r.basePlayers
            func ball(_ b: PairBallLine) -> String { "\(spokenName(b.alias)) \(b.gross)" }
            let carriers = (r.basePlayers + r.oppPlayers).filter { $0.laneStrokes > 0 }
                .map { "\(spokenName($0.alias)) recibe \(strokesWords($0.laneStrokes))" }
            let stroke = carriers.isEmpty ? "Sin strokes en este hoyo" : spokenList(carriers) + " en este hoyo"
            let result = r.result * sign
            let word = result > 0 ? "gana la pareja (\(result))" : result < 0 ? "pierde la pareja (\(-result))" : "empatan"
            let ba = beforeAfter(prev.map { ($0.0, $0.1) }, (r.vueltaAccum, r.openPressures), sign: sign, nine: nine)
            if holes.count <= 3 && !detail {
                let advNames = (r.basePlayers + r.oppPlayers).filter { $0.laneStrokes > 0 }.map { spokenName($0.alias) }
                let briefAdv = advNames.isEmpty ? "" : ", ventaja de " + spokenList(advNames)
                let briefBalls = "\(myBalls.map(ball).joined(separator: " y ")) contra \(hisBalls.map(ball).joined(separator: " y "))"
                lines.append("Hoyo \(hole): \(briefBalls), \(word)\(briefAdv). Vuelta \(nine) \(signedWords(r.vueltaAccum * sign))\(totals ? ", " + presionWords(r.openPressures, sign: sign) + ", match " + signedWords(matchAsOf(hole, nineRows: rows, otherNine: nine == "F9" ? "B9" : "F9", sign: sign, target: .pair(lane.id))) : "").")
            } else if holes.count <= 3 {
                lines.append("Hoyo \(hole): tiraron \(spokenList(myBalls.map(ball))) contra \(spokenList(hisBalls.map(ball))). \(stroke). \(word.prefix(1).uppercased() + word.dropFirst()). \(ba)")
            } else {
                lines.append("hoyo \(hole), \(word)")
            }
        }
        return (head.isEmpty ? "" : head + " ") + lines.joined(separator: holes.count <= 3 ? " " : "; ") + (holes.count <= 3 ? "" : ".")
    }
}

// MARK: - Las apuestas de vuelta, presión y match, y el acumulado: leer lo que resultó y explicar por qué

extension MatchManager {

    /// Hoyos ganados, perdidos y empatados de un nueve (desde el lado de `sign`).
    private func wonLost(_ target: UnitLogTarget, nine: String, sign: Int) -> (won: [Int], lost: [Int], tied: [Int]) {
        var won: [Int] = [], lost: [Int] = [], tied: [Int] = []
        let rows: [(hole: Int, result: Int)]
        switch target {
        case .individual(let opp): rows = individualZoomRows(opponentAlias: opp, segmentOverride: nine).map { ($0.hole, $0.result) }
        case .pair(let id): rows = pairZoomRows(laneId: id, segmentOverride: nine).map { ($0.hole, $0.result) }
        }
        for r in rows { let v = r.result * sign; if v > 0 { won.append(r.hole) } else if v < 0 { lost.append(r.hole) } else { tied.append(r.hole) } }
        return (won, lost, tied)
    }

    private func holesPhrase(_ holes: [Int]) -> String { holes.count == 1 ? "el \(holes[0])" : "los " + spokenList(holes.map(String.init)) }

    /// "ganaste los hoyos 1 y 4, perdiste el 2 y empataron el 3".
    private func wonLostPhrase(_ w: (won: [Int], lost: [Int], tied: [Int]), me: Bool) -> String {
        var parts: [String] = []
        if !w.won.isEmpty { parts.append("\(me ? "ganaste" : "ganó") \(holesPhrase(w.won))") }
        if !w.lost.isEmpty { parts.append("\(me ? "perdiste" : "perdió") \(holesPhrase(w.lost))") }
        if !w.tied.isEmpty { parts.append("empataron \(holesPhrase(w.tied))") }
        return parts.isEmpty ? "todavía sin hoyos jugados" : spokenList(parts)
    }

    private func matchesFor(alias: String?, opponent: String?) -> [ResultadoRowV2] {
        resultadoRowsV2().filter { row in
            guard let alias else { return true }
            switch row.kind {
            case .individual(let a):
                if alias == yoAlias { return opponent == nil || opponent == a }
                return a == alias && (opponent == nil || opponent == yoAlias)
            case .pair(let id):
                guard let lane = lanes.first(where: { $0.id == id }) else { return false }
                guard lane.base.contains(alias) || lane.opp.contains(alias) else { return false }
                if let opponent { return (lane.base.contains(alias) ? lane.opp : lane.base).contains(opponent) }
                return true
            }
        }
    }

    private func signFor(_ row: ResultadoRowV2, alias: String?) -> Int {
        guard let alias, alias != yoAlias else { return 1 }
        switch row.kind {
        case .individual: return -1
        case .pair(let id): return lanes.first { $0.id == id }.map { $0.base.contains(alias) == $0.base.contains(yoAlias) ? 1 : -1 } ?? 1
        }
    }

    /// Etiqueta corta de un match, con nombres y no alias: "Roberto" o "con Fernando vs Roberto y Ricardo".
    func briefLabelV2(_ row: ResultadoRowV2) -> String {
        switch row.kind {
        case .individual(let a): return spokenName(a)
        case .pair:
            func names(_ text: String) -> String {
                text.replacingOccurrences(of: " – ", with: " y ").split(separator: " ").map { w in
                    players.contains { $0.alias == String(w) } ? spokenName(String(w)) : String(w)
                }.joined(separator: " ")
            }
            return names(row.title) + (row.rivalsText.map { " vs " + names($0) } ?? "")
        }
    }

    private func matchName(_ row: ResultadoRowV2) -> String {
        switch row.kind {
        case .individual(let a): return "contra \(spokenName(a))"
        case .pair: return "pareja \(row.title)" + (row.rivalsText.map { " contra \($0)" } ?? "")
        }
    }

    // MARK: Vuelta, presión y match

    /// Una apuesta concreta ("vuelta", "presion" o "match") de cada match: conteo, valor y, al final, lo que paga.
    func betKindAnswerV2(_ kind: String, alias: String?, opponent: String?) -> String {
        let rows = matchesFor(alias: alias, opponent: opponent)
        guard !rows.isEmpty else { return "No encontré ese match." }
        let lines = rows.map { row -> String in
            let sign = signFor(row, alias: alias)
            let values = betValuesV2(for: row.target)
            let switches = betSwitchesV2(for: row.target)
            let f9 = row.f9Net * sign, b9 = row.b9Net * sign
            switch kind {
            case "vuelta":
                let on = switches.vuelta ? "" : " Está apagada en este match."
                return "\(matchName(row)): vuelta F9 \(countWords(f9)), vuelta B9 \(countWords(b9)). Cada vuelta vale \(values.vueltaValue) pesos.\(on)"
            case "presion":
                let on = switches.presion ? "" : " Está apagada en este match."
                func pres(_ v: [Int]) -> String { v.isEmpty ? "sin presiones abiertas" : v.map { $0 * sign > 0 ? "a favor por \($0 * sign)" : $0 * sign < 0 ? "en contra por \(-$0 * sign)" : "empatada" }.joined(separator: ", ") }
                return "\(matchName(row)): F9, \(pres(row.f9Presiones)). B9, \(pres(row.b9Presiones)). Cada presión vale \(values.presionValue) pesos.\(on)"
            default:
                let on = switches.match ? "" : " Está apagado en este match."
                let total = f9 + b9
                let state = row.b9Played + row.f9Played >= 18 ? "ya se cobra" : "se cobra al terminar los 18 hoyos"
                return "\(matchName(row)): match \(countWords(total)). Vale \(values.matchValue) pesos y \(state).\(on)"
            }
        }
        return lines.joined(separator: " ")
    }


    // MARK: Marcador corto: solo conteos

    /// "Al hoyo 8, match: contra Roberto 3 arriba; contra Ricardo 1 abajo." Individuales primero y luego parejas contrarias;
    /// con varios individuales compara el mejor y el peor. Si preguntan por uno solo, contesta uno.
    func scoreboardReadbackV2(kind: String, alias: String?, opponent: String?, segment: String?) -> String {
        let rows = matchesFor(alias: alias, opponent: opponent)
        guard !rows.isEmpty else { return "No encontré ese match." }
        var held = Set<Int>()
        for a in players.map(\.alias) where a != yoAlias {
            for n in ["F9", "B9"] { individualZoomRows(opponentAlias: a, segmentOverride: n).forEach { held.insert($0.hole) } }
        }
        let last = playOrder().last { held.contains($0) }
        let nine = segment?.uppercased() ?? last.map(nineOf) ?? "F9"
        if kind == "resumen" { return compactStandingsV2(rows: rows, alias: alias, nine: nine, hole: last) }
        let label: String
        switch kind {
        case "presion": label = "presiones \(nine)"
        case "vuelta", "nueve": label = "vuelta \(nine)"
        case "resumen": label = "vuelta \(nine), presión, match y unidades"
        default: label = "match"
        }
        var values: [(row: ResultadoRowV2, value: Int, text: String)] = []
        for row in rows {
            let sign = signFor(row, alias: alias)
            switch kind {
            case "presion":
                let open = (nine == "B9" ? row.b9Presiones : row.f9Presiones)
                let mine = open.filter { $0 * sign > 0 }.count, theirs = open.filter { $0 * sign < 0 }.count
                values.append((row, mine - theirs, "\(briefLabelV2(row)) presión \(signedWords(mine - theirs))"))
            case "vuelta", "nueve":
                let v = (nine == "B9" ? row.b9Net : row.f9Net) * sign
                values.append((row, v, "\(briefLabelV2(row)) \(signedWords(v))"))
            case "resumen":
                // Cada número como se dice: vuelta, presión, match y unidades.
                let v = (nine == "B9" ? row.b9Net : row.f9Net) * sign
                let open = nine == "B9" ? row.b9Presiones : row.f9Presiones
                let net = open.reduce(0) { $0 + ($1 * sign > 0 ? 1 : $1 * sign < 0 ? -1 : 0) }
                let pres = "presión " + signedWords(net)
                let m = (row.f9Net + row.b9Net) * sign
                let u = (matchResumenV2(for: row.target)?.unidades.chips.first).flatMap { Int($0.replacingOccurrences(of: "+", with: "")) }.map { $0 * sign } ?? 0
                let units = "unidades \(signedWords(u))"
                values.append((row, m, "\(briefLabelV2(row)): vuelta \(signedWords(v)), \(pres), match \(signedWords(m)), \(units)"))
            default:
                let v = (row.f9Net + row.b9Net) * sign
                values.append((row, v, "\(briefLabelV2(row)) \(signedWords(v))"))
            }
        }
        let singles = values.filter { !$0.row.isPair }, pairs = values.filter { $0.row.isPair }
        var text = (last.map { "Hoyo \($0), " } ?? "") + label + ": "
        var parts: [String] = []
        if !singles.isEmpty { parts.append(singles.map(\.text).joined(separator: "; ")) }
        if !pairs.isEmpty { parts.append("Parejas: " + pairs.map(\.text).joined(separator: "; ")) }
        text += parts.joined(separator: ". ") + "."
        if let n = pairsNoticeV2() { text += " Ojo: " + pairsNoticeTextV2(n) }
        return text
    }

    /// "Cómo vamos" directo: el hoyo y la vuelta, y por jugador y pareja solo los números en un orden fijo
    /// (vuelta, presión, carry, match), siempre desde el lado de quien pregunta: más = va ganando, menos = va perdiendo.
    /// Sin hoyos completos, unidades ni dinero (eso tiene sus propios botones).
    func compactStandingsV2(rows: [ResultadoRowV2], alias: String?, nine: String, hole: Int?) -> String {
        func chipValues(_ chips: [String]) -> [Int] { chips.compactMap { Int($0.replacingOccurrences(of: "+", with: "")) } }
        func list(_ values: [Int]) -> String { values.map(signedWords).joined(separator: " y ") }
        var line: [String] = []
        for row in rows {
            let sign = signFor(row, alias: alias)
            let v = (nine == "B9" ? row.b9Net : row.f9Net) * sign
            // Cada presión abierta con su propio valor ("más 3 y más 1"); sin presiones abiertas se dice.
            let open = (nine == "B9" ? row.b9Presiones : row.f9Presiones).map { $0 * sign }
            let m = (row.f9Net + row.b9Net) * sign
            var parts = ["vuelta " + signedWords(v), open.isEmpty ? "sin presión" : "presión " + list(open)]
            if let r = matchResumenV2(for: row.target), r.carryActivo {
                let carry = chipValues(r.carry.chips).map { $0 * sign }
                if let first = carry.first { parts.append("carry " + signedWords(first) + (carry.count > 1 ? ", presión del carry " + list(Array(carry.dropFirst())) : "")) }
            }
            parts.append("match " + signedWords(m))
            let name = briefLabelV2(row)
            line.append(name + ": " + parts.joined(separator: ", "))
        }
        var text = (hole.map { "Hoyo \($0), " } ?? "") + nine + ". " + line.joined(separator: ". ") + "."
        if let n = pairsNoticeV2() { text += " Ojo: " + pairsNoticeTextV2(n) }
        return text
    }

    /// "Por qué" corto: cuántos hoyos se ganaron y perdieron en cada match y en cuáles hay stroke.
    func whyBriefV2(alias: String?, opponent: String?) -> String {
        let rows = matchesFor(alias: alias, opponent: opponent)
        guard !rows.isEmpty else { return "No encontré ese match." }
        func holesList(_ h: [Int]) -> String { h.count == 1 ? "el \(h[0])" : "los " + spokenList(h.map(String.init)) }
        let lines = rows.map { row -> String in
            let sign = signFor(row, alias: alias)
            let total = (row.f9Net + row.b9Net) * sign
            var results: [Int] = []
            var strokesMine: [Int] = [], strokesTheirs: [Int] = [], strokesAny: [Int] = []
            switch row.kind {
            case .individual(let opp):
                for nine in ["F9", "B9"] {
                    for r in individualZoomRows(opponentAlias: opp, segmentOverride: nine) {
                        results.append(r.result * sign)
                        let mine = sign == 1 ? r.yoStrokes : r.oppStrokes, his = sign == 1 ? r.oppStrokes : r.yoStrokes
                        if mine > 0 { strokesMine.append(r.hole) } else if his > 0 { strokesTheirs.append(r.hole) }
                    }
                }
            case .pair(let id):
                for nine in ["F9", "B9"] {
                    for r in pairZoomRows(laneId: id, segmentOverride: nine) {
                        results.append(r.result * sign)
                        if (r.basePlayers + r.oppPlayers).contains(where: { $0.laneStrokes > 0 }) { strokesAny.append(r.hole) }
                    }
                }
            }
            let won = results.filter { $0 > 0 }.count, lost = results.filter { $0 < 0 }.count, tied = results.filter { $0 == 0 }.count
            let isMe = sign == 1
            var text = "\(briefLabelV2(row).prefix(1).uppercased() + briefLabelV2(row).dropFirst()): \(signedWords(total)). "
            if results.isEmpty { return text + "Todavía sin hoyos jugados." }
            var counts = ["\(isMe ? "ganaste" : "ganó") \(won)", "\(isMe ? "perdiste" : "perdió") \(lost)"]
            if tied > 0 { counts.append("empataron \(tied)") }
            text += counts.joined(separator: ", ") + "."
            
            // Solo cuántos hoyos con stroke y de quién; los hoyos exactos salen con "Más detalle".
            if !strokesMine.isEmpty { text += " \(isMe ? "Tienes" : "Tiene") stroke en \(strokesMine.count)." }
            if !strokesTheirs.isEmpty { text += " Él tiene stroke en \(strokesTheirs.count)." }
            if !strokesAny.isEmpty { text += " Hay stroke en \(strokesAny.count)." }
            return text
        }
        return lines.joined(separator: " ")
    }

    // MARK: El acumulado y por qué resultó

    /// Explica cómo se llegó al resultado de cada match: hoyos ganados y perdidos, vuelta, presiones, match, strokes y unidades,
    /// y al final lo que suma. Todo con los mismos números de la tabla de conceptos de Resultados.
    func explainReadbackV2(alias: String?, opponent: String?, detail: Bool = true) -> String {
        let rows = matchesFor(alias: alias, opponent: opponent)
        guard !rows.isEmpty else { return "No encontré ese match." }
        if !detail { return whyBriefV2(alias: alias, opponent: opponent) }
        let blocks = rows.compactMap { row -> String? in
            guard let r = matchResumenV2(for: row.target) else { return nil }
            let sign = signFor(row, alias: alias)
            let me = sign == 1 && (alias == nil || alias == yoAlias || { if case .pair = row.kind { return true } else { return false } }())
            let money = row.money * sign
            var parts: [String] = []
            func concept(_ name: String, _ c: ConceptoMatch, nine: String?) {
                var text = name + ": "
                if let nine {
                    let w = wonLost(row.target, nine: nine, sign: sign)
                    text += wonLostPhrase(w, me: me)
                }
                let amount = c.monto * sign
                text += (nine != nil ? ". " : "") + (amount == 0 ? "no mueve dinero" : amount > 0 ? "deja \(amount) pesos a favor" : "deja \(-amount) pesos en contra")
                parts.append(text)
            }
            concept("F9", r.f9, nine: "F9")
            let b9Doble = r.dobleB9 ? " con Doble B9, todo de B9 vale el doble" : ""
            concept("B9", r.b9, nine: "B9")
            if !b9Doble.isEmpty { parts[parts.count - 1] += "," + b9Doble }
            let matchCount = (row.f9Net + row.b9Net) * sign
            parts.append("Match: \(countWords(matchCount)), " + (r.match.monto == 0 ? "todavía no se cobra" : "\(abs(r.match.monto)) pesos \(r.match.monto * sign > 0 ? "a favor" : "en contra")"))
            if r.carry.monto != 0 || r.carryActivo { parts.append("Carry: \(abs(r.carry.monto * sign)) pesos \(r.carry.monto * sign >= 0 ? "a favor" : "en contra")") }
            if let aj = r.ajuste { parts.append("Ajuste 50: \(abs(aj.monto * sign)) pesos \(aj.monto * sign >= 0 ? "a favor" : "en contra")") }
            parts.append("Unidades: " + (r.unidades.detalle.first ?? "sin unidades") + ", " +
                         (r.unidades.monto == 0 ? "sin dinero" : "\(abs(r.unidades.monto * sign)) pesos \(r.unidades.monto * sign > 0 ? "a favor" : "en contra")"))
            if let receiver = row.strokesReceiver, row.strokesAmount > 0 {
                parts.append("Strokes: \(spokenName(receiver)) recibe \(strokesWords(row.strokesAmount))")
            }
            return "\(matchName(row).prefix(1).uppercased() + matchName(row).dropFirst()), \(moneyWords(money)). " + parts.joined(separator: ". ") + "."
        }
        guard !blocks.isEmpty else { return "No encontré ese match." }
        var text = blocks.joined(separator: " ")
        if rows.count > 1 { text += " En total, \(moneyWords(rows.reduce(0) { $0 + $1.money * signFor($1, alias: alias) }))." }
        return text
    }
}

// MARK: - Respuestas cortas para el reloj

extension MatchManager {

    /// "3 -1": la vuelta y luego cada presión abierta, con su signo.
    private func numbersText(_ values: [Int]) -> String { values.map(String.init).joined(separator: " ") }

    private func toneOf(_ n: Int) -> Int { n > 0 ? 1 : n < 0 ? -1 : 0 }

    /// Un neto: entero, o con medio punto si hubo medio stroke ("9.5").
    private func netText(_ d: Double) -> String { d.rounded() == d ? String(Int(d)) : String(format: "%.1f", d) }

    /// Un número como se dice en voz alta, sin "más": "3", "menos 2", "cero".
    private func numberSpoken(_ n: Int) -> String { n < 0 ? "menos \(-n)" : n == 0 ? "cero" : "\(n)" }

    /// "3, menos 1": la vuelta y luego cada presión, separados por pausas.
    private func numbersSpoken(_ values: [Int]) -> String { values.map(numberSpoken).joined(separator: ", ") }

    /// El último hoyo del que ya hay scores de los dos (en el orden de juego).
    /// Todos los números de un match en una línea, con las mismas etiquetas en el reloj, el iPhone y el historial:
    /// "F9 2 (1 -1) · B9 -1 · Carry $50 · Strokes ROB 3 · Unid 2 · $300" (entre paréntesis, las presiones abiertas de esa nueve).
    func allNumbersLineV2(_ row: ResultadoRowV2, sign: Int) -> String {
        func nine(_ label: String, _ net: Int, _ played: Int, _ open: [Int]) -> String {
            guard played > 0 else { return "\(label) —" }
            let pres = open.isEmpty ? "" : " (" + open.map { String($0 * sign) }.joined(separator: " ") + ")"
            return "\(label) \(net * sign)\(pres)"
        }
        var parts = [nine("F9", row.f9Net, row.f9Played, row.f9Presiones), nine("B9", row.b9Net, row.b9Played, row.b9Presiones)]
        if row.carryActive { parts.append("Carry $\(row.carryMoney * sign)") }
        if let receiver = row.strokesReceiver, row.strokesAmount > 0 { parts.append("Strokes \(receiver) \(netText(row.strokesAmount))") }
        if row.unitsNet != 0 { parts.append("Unid \(row.unitsNet * sign)") }
        parts.append("$\(row.money * sign)")
        return parts.joined(separator: " · ")
    }

    /// El último hoyo del que ya hay scores de los dos (lo usan las respuestas y el reloj).
    func lastHoleHeldV2() -> Int? { lastHoleHeld() }

    private func lastHoleHeld() -> Int? {
        var held = Set<Int>()
        for a in players.map(\.alias) where a != yoAlias {
            for n in ["F9", "B9"] { individualZoomRows(opponentAlias: a, segmentOverride: n).forEach { held.insert($0.hole) } }
        }
        return playOrder().last { held.contains($0) }
    }

    /// Cómo se nombra un match: en pantalla el alias ("FER", "DAN+FER vs ROB+RIC"); en voz el nombre ("Fernando", "pareja con Fernando contra Roberto y Ricardo").
    private func matchLabelsV2(_ row: ResultadoRowV2, alias: String?) -> (label: String, name: String) {
        let me = yoAlias
        switch row.kind {
        case .individual(let a):
            // Desde el lado de otro jugador el rival es el usuario.
            let label = (alias == nil || alias == me) ? a : me
            return (label, spokenName(label))
        case .pair:
            let partner = row.title.replacingOccurrences(of: "con ", with: "").trimmingCharacters(in: .whitespaces)
            let rivals = (row.rivalsText ?? "").components(separatedBy: " – ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return ("\(me)+\(partner)" + (rivals.isEmpty ? "" : " vs " + rivals.joined(separator: "+")),
                    "pareja con \(spokenName(partner))" + (rivals.isEmpty ? "" : " contra " + spokenList(rivals.map(spokenName))))
        }
    }

    /// El detalle, como leer la tarjeta: por cada match, cada apuesta con su CONTEO (vuelta, presiones, match, carry, ajuste, unidades
    /// con campo y oyes) y su MONETIZACIÓN (lo que vale y lo que deja). En pantalla; en voz solo el total.
    /// Desde el lado de otro jugador no hay tarjeta de apuestas: ahí se usa la respuesta larga de siempre.
    func watchDetailV2(alias: String?, opponent: String?) -> WatchAnswerDTO {
        if let alias, alias != yoAlias { return .plain(explainReadbackV2(alias: alias, opponent: opponent, detail: true)) }
        let rows = detailRowsV2(alias: alias, opponent: opponent)
        guard !rows.isEmpty else { return .plain("No encontré ese match.") }
        func pesos(_ v: Int) -> String { v == 0 ? "$0" : v > 0 ? "+$\(v)" : "-$\(-v)" }
        func dinero(_ v: Int) -> String { v == 0 ? "sin dinero" : v > 0 ? "ganas $\(v)" : "pierdes $\(-v)" }
        var lines: [WatchAnswerDTO.Line] = []
        var total = 0
        for row in rows {
            guard let r = matchResumenV2(for: row.target) else { continue }
            let values = betValuesV2(for: row.target)
            total += row.money
            lines.append(.init(label: matchLabelsV2(row, alias: alias).label, value: pesos(row.money), tone: toneOf(row.money), header: true))
            for c in r.filas {
                var detail = dinero(c.monto)
                switch c.nombre {
                case "F9": detail += " · vuelta $\(values.vueltaValue) · presión $\(values.presionValue)"
                case let n where n.hasPrefix("B9"):
                    let mult = r.dobleB9 ? 2 : 1
                    detail += " · vuelta $\(values.vueltaValue * mult) · presión $\(values.presionValue * mult)" + (r.dobleB9 ? " (doble B9)" : "")
                case "Match": detail += " · vale $\(values.matchValue) · " + (c.detalle.last ?? "")
                case "Carry": detail += " · con la apuesta original"
                case "Unidades": detail += " · " + (c.detalle.first ?? "") + " · $\(values.unitValue) c/u"
                default: break
                }
                lines.append(.init(label: c.nombre, value: c.chips.joined(separator: " "), detail: detail, tone: toneOf(c.monto)))
            }
            if let receiver = row.strokesReceiver, row.strokesAmount > 0 {
                lines.append(.init(label: "Strokes", value: spokenName(receiver), detail: "recibe \(strokesWords(row.strokesAmount))", tone: 0))
            }
        }
        guard !lines.isEmpty else { return .plain("Todavía no hay matches en la ronda.") }
        return WatchAnswerDTO(title: "Detalle", lines: lines, spoken: "Detalle en pantalla. En total, \(moneyWords(total)).")
    }

    /// Los matches de una pregunta. Si nombraron un rival ("cómo voy con Rob") sin decir quién pregunta, pregunta el usuario:
    /// solo salen los matches contra ese rival, no todos.
    func detailRowsV2(alias: String?, opponent: String?) -> [ResultadoRowV2] {
        matchesFor(alias: alias ?? (opponent == nil ? nil : yoAlias), opponent: opponent)
    }

    /// "Cómo voy" en el reloj: una línea por match, el nombre y luego la vuelta y las presiones abiertas ("Rob 3 -1", "Ans 5 3 1").
    /// Más = va ganando, menos = va perdiendo. Sin dinero ni match: eso se pide aparte.
    func watchStandingsV2(alias: String?, opponent: String?) -> WatchAnswerDTO {
        let rows = detailRowsV2(alias: alias, opponent: opponent)
        guard !rows.isEmpty else { return .plain("No encontré ese match.") }
        let hole = lastHoleHeld()
        let nine = hole.map(nineOf) ?? "F9"
        var lines: [WatchAnswerDTO.Line] = [], spoken: [String] = []
        for row in rows {
            let sign = signFor(row, alias: alias)
            let v = (nine == "B9" ? row.b9Net : row.f9Net) * sign
            let open = (nine == "B9" ? row.b9Presiones : row.f9Presiones).map { $0 * sign }
            let (label, name) = matchLabelsV2(row, alias: alias)
            lines.append(.init(label: label, value: numbersText([v] + open), detail: allNumbersLineV2(row, sign: sign), tone: toneOf(v)))
            spoken.append("\(name) \(numbersSpoken([v] + open))")
        }
        var text = (hole.map { "Hoyo \($0). " } ?? "") + spoken.joined(separator: ". ") + "."
        if let n = pairsNoticeV2() { text += " Ojo: " + pairsNoticeTextV2(n) }
        return WatchAnswerDTO(title: (hole.map { "Hoyo \($0) · " } ?? "") + nine, lines: lines, spoken: text)
    }

    /// Cuántos hoyos explica el "por qué" corto: el último hoyo anotado (el mismo hasta el que llega "cómo voy") y los anteriores.
    /// Por defecto 3 (el anotado y los dos anteriores); se puede cambiar de 1 a 6 y se guarda en el teléfono.
    static var whyHolesV2: Int {
        get { min(max(UserDefaults.standard.object(forKey: "whyHolesV2") as? Int ?? 3, 1), 6) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 6), forKey: "whyHolesV2") }
    }

    /// "¿Por qué?" corto (reloj y iPhone): los últimos hoyos jugados de cada match. Por hoyo: si ganas o pierdes, qué tiró cada uno,
    /// el neto cuando alguien recibe stroke y cómo van la vuelta y las presiones después de ese hoyo.
    func watchWhyV2(alias: String?, opponent: String?) -> WatchAnswerDTO {
        let me = yoAlias, p = alias ?? me
        let order = playOrder()
        func index(_ hole: Int) -> Int { order.firstIndex(of: hole) ?? Int.max }
        let isMe = p == me
        var lines: [WatchAnswerDTO.Line] = [], spoken: [String] = []
        var shown: [Int] = []   // los hoyos que se explican, para decir "hasta el hoyo N"

        // En pantalla va el detalle de cada hoyo; en voz, una frase por match (como lo leerían tus ojos, pero hablado).
        for opp in players.map(\.alias) where opp != me {
            guard p == me || p == opp else { continue }
            if let opponent, opponent != (p == me ? opp : me) { continue }
            let sign = isMe ? 1 : -1
            let other = isMe ? opp : me
            let last = ["F9", "B9"].flatMap { individualZoomRows(opponentAlias: opp, segmentOverride: $0) }
                .sorted { index($0.hole) < index($1.hole) }.suffix(Self.whyHolesV2)
            guard let final = last.last else { continue }
            lines.append(.init(label: other, value: "", header: true))
            var parts: [String] = []
            for r in last {
                shown.append(r.hole)
                let myGross = sign == 1 ? r.yoGross : r.oppGross, hisGross = sign == 1 ? r.oppGross : r.yoGross
                let myStroke = sign == 1 ? r.yoStrokes : r.oppStrokes, hisStroke = sign == 1 ? r.oppStrokes : r.yoStrokes
                let myNet = netText(sign == 1 ? r.yoNet : r.oppNet), hisNet = netText(sign == 1 ? r.oppNet : r.yoNet)
                let result = r.result * sign
                let word = isMe ? (result > 0 ? "ganas" : result < 0 ? "pierdes" : "empatas") : (result > 0 ? "gana" : result < 0 ? "pierde" : "empata")
                let state = [r.vueltaAccum * sign] + r.openPressures.map { $0 * sign }
                let mine = isMe ? "tú" : spokenName(p), his = "él"
                var detail = "\(mine) \(myGross) · \(his) \(hisGross)"
                var said = "\(r.hole) \(word) \(myGross) a \(hisGross)"
                if myStroke > 0 || hisStroke > 0 {
                    // Dónde cae el stroke: a veces el empate en golpes se gana por el neto.
                    let who = myStroke > 0 ? (isMe ? "tuyo" : "de \(spokenName(p))") : "de él"
                    let amount = myStroke > 0 ? myStroke : hisStroke
                    let size = amount == 1 ? "" : " (\(strokesWords(amount)))"
                    detail += " · stroke \(who)\(size) · neto \(myNet)-\(hisNet)"
                    said += ", stroke \(who)\(size), neto \(myNet) a \(hisNet)"
                }
                lines.append(.init(label: "\(r.hole) \(word)", value: numbersText(state), detail: detail, tone: toneOf(state[0])))
                parts.append(said)
            }
            let finalState = [final.vueltaAccum * sign] + final.openPressures.map { $0 * sign }
            spoken.append("Contra \(spokenName(other)): \(parts.joined(separator: ", ")). Van \(numbersSpoken(finalState)).")
        }

        // Parejas: lo mismo, hoyo por hoyo, con las bolas de cada lado y quién recibe ventaja.
        for lane in activeLanes where lane.base.contains(p) || lane.opp.contains(p) {
            if let opponent, !((lane.base.contains(p) ? lane.opp : lane.base).contains(opponent)) { continue }
            let mine = lane.base.contains(p)
            let sign = mine ? 1 : -1
            let mySide = mine ? lane.base : lane.opp, hisSide = mine ? lane.opp : lane.base
            let rows = ["F9", "B9"].flatMap { pairZoomRows(laneId: lane.id, segmentOverride: $0) }
                .sorted { index($0.hole) < index($1.hole) }.suffix(Self.whyHolesV2)
            guard let final = rows.last else { continue }
            lines.append(.init(label: "\(mySide.joined(separator: "+")) vs \(hisSide.joined(separator: "+"))", value: "", header: true))
            var parts: [String] = []
            for r in rows {
                shown.append(r.hole)
                let result = r.result * sign
                let word = result > 0 ? "ganan" : result < 0 ? "pierden" : "empatan"
                let state = [r.vueltaAccum * sign] + r.openPressures.map { $0 * sign }
                func balls(_ side: [PairBallLine]) -> String { side.map { "\($0.alias) \($0.gross)" }.joined(separator: " · ") }
                let advantage = (r.basePlayers + r.oppPlayers).filter { $0.laneStrokes > 0 }.map(\.alias)
                let detail = "\(balls(mine ? r.basePlayers : r.oppPlayers))  vs  \(balls(mine ? r.oppPlayers : r.basePlayers))"
                    + (advantage.isEmpty ? "" : " · ventaja \(advantage.joined(separator: ", "))")
                lines.append(.init(label: "\(r.hole) \(word)", value: numbersText(state), detail: detail, tone: toneOf(state[0])))
                parts.append("\(r.hole) \(word)")
            }
            let finalState = [final.vueltaAccum * sign] + final.openPressures.map { $0 * sign }
            let partner = mySide.filter { $0 != p }.map(spokenName)
            let rivals = hisSide.map(spokenName)
            spoken.append("Pareja" + (partner.isEmpty ? "" : " con \(spokenList(partner))") + " contra \(spokenList(rivals)): \(parts.joined(separator: ", ")). Van \(numbersSpoken(finalState)).")
        }

        guard !lines.isEmpty else { return .plain("Todavía no hay hoyos completos para explicar.") }
        let upTo = shown.max { index($0) < index($1) }
        return WatchAnswerDTO(title: upTo.map { "Hasta el hoyo \($0)" } ?? "Últimos hoyos", lines: lines, spoken: spoken.joined(separator: " "))
    }
}
