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
    func statusReadbackV2(alias: String?, opponent: String?) -> String {
        let me = yoAlias
        let p = alias ?? me
        let order = playOrder()
        func lastHole(_ holesWithRows: Set<Int>) -> Int? { order.last { holesWithRows.contains($0) } }
        var blocks: [String] = []
        for opp in players.map(\.alias) where opp != me {
            guard p == me || p == opp else { continue }
            if let opponent, opponent != (p == me ? opp : me) { continue }
            let held = Set(["F9", "B9"].flatMap { individualZoomRows(opponentAlias: opp, segmentOverride: $0).map(\.hole) })
            if let h = lastHole(held), let b = individualHoleBlock(perspective: p, opponent: opp, holes: [h], detail: false) { blocks.append(b) }
        }
        for lane in activeLanes where lane.base.contains(p) || lane.opp.contains(p) {
            if let opponent, !((lane.base.contains(p) ? lane.opp : lane.base).contains(opponent)) { continue }
            let held = Set(["F9", "B9"].flatMap { pairZoomRows(laneId: lane.id, segmentOverride: $0).map(\.hole) })
            if let h = lastHole(held), let b = pairHoleBlock(perspective: p, lane: lane, holes: [h], detail: false) { blocks.append(b) }
        }
        guard !blocks.isEmpty else { return "Todavía no hay hoyos completos para ese match." }
        return blocks.joined(separator: " ")
    }

    private func outcomeWords(_ r: Int, _ name: String) -> String { r > 0 ? "gana \(name)" : r < 0 ? "pierde \(name)" : "empatan" }

    /// Antes / ahora de la vuelta y las presiones, desde el lado de `sign`.
    private func beforeAfter(_ prev: (v: Int, p: [Int])?, _ cur: (v: Int, p: [Int]), sign: Int, nine: String) -> String {
        let beforeV = (prev?.v ?? 0) * sign, afterV = cur.v * sign
        let beforeP = prev?.p.count ?? 0, afterP = cur.p.count
        return "Vuelta \(nine): antes \(countWords(beforeV)), ahora \(countWords(afterV)). " +
            "Presiones abiertas: antes \(beforeP), ahora \(afterP)."
    }

    private func individualHoleBlock(perspective p: String, opponent opp: String, holes: [Int], detail: Bool = true) -> String? {
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
                let briefStroke = myStroke > 0 ? "\(myName) recibe \(strokesWords(myStroke))" : hisStroke > 0 ? "\(hisName) recibe \(strokesWords(hisStroke))" : "sin strokes"
                lines.append("Hoyo \(hole): \(myGross) contra \(hisGross), \(outcomeWords(r.result * sign, myName)), \(briefStroke). Vuelta \(nine) \(countWords(r.vueltaAccum * sign)).")
            } else if holes.count <= 3 {
                lines.append("Hoyo \(hole): \(myName) tiró \(myGross) y \(hisName) \(hisGross). \(strokeText). \(outcomeWords(r.result * sign, myName).prefix(1).uppercased() + outcomeWords(r.result * sign, myName).dropFirst()). \(ba)")
            } else {
                lines.append("hoyo \(hole), \(myGross) contra \(hisGross), \(outcomeWords(r.result * sign, myName))")
            }
        }
        let head = "\(spokenName(p)) contra \(spokenName(other))."
        if holes.count <= 3 { return head + " " + lines.joined(separator: " ") }
        // Grupo de hoyos: una línea por hoyo y cómo queda la vuelta de cada nueve al final.
        var tail: [String] = []
        for nine in ["F9", "B9"] where holes.contains(where: { nineOf($0) == nine }) {
            let rows = individualZoomRows(opponentAlias: opp, segmentOverride: nine)
            if let last = rows.last { tail.append("Vuelta \(nine) ahora \(countWords(last.vueltaAccum * sign)), \(last.openPressures.count) presion\(last.openPressures.count == 1 ? "" : "es") abierta\(last.openPressures.count == 1 ? "" : "s")") }
        }
        return head + " " + lines.joined(separator: "; ") + ". " + tail.joined(separator: ". ") + "."
    }

    private func pairHoleBlock(perspective p: String, lane: LaneModel, holes: [Int], detail: Bool = true) -> String? {
        let mine = lane.base.contains(p)
        let sign = mine ? 1 : -1
        let mySide = mine ? lane.base : lane.opp, hisSide = mine ? lane.opp : lane.base
        let head = "Pareja \(mySide.map(spokenName).joined(separator: " y ")) contra \(hisSide.map(spokenName).joined(separator: " y "))."
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
                let briefBalls = "\(myBalls.map(ball).joined(separator: " y ")) contra \(hisBalls.map(ball).joined(separator: " y "))"
                lines.append("Hoyo \(hole): \(briefBalls), \(word), \(carriers.isEmpty ? "sin strokes" : spokenList(carriers)). Vuelta \(nine) \(countWords(r.vueltaAccum * sign)).")
            } else if holes.count <= 3 {
                lines.append("Hoyo \(hole): tiraron \(spokenList(myBalls.map(ball))) contra \(spokenList(hisBalls.map(ball))). \(stroke). \(word.prefix(1).uppercased() + word.dropFirst()). \(ba)")
            } else {
                lines.append("hoyo \(hole), \(word)")
            }
        }
        return head + " " + lines.joined(separator: holes.count <= 3 ? " " : "; ") + (holes.count <= 3 ? "" : ".")
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

    // MARK: El acumulado y por qué resultó

    /// Explica cómo se llegó al resultado de cada match: hoyos ganados y perdidos, vuelta, presiones, match, strokes y unidades,
    /// y al final lo que suma. Todo con los mismos números de la tabla de conceptos de Resultados.
    func explainReadbackV2(alias: String?, opponent: String?, detail: Bool = true) -> String {
        let rows = matchesFor(alias: alias, opponent: opponent)
        guard !rows.isEmpty else { return "No encontré ese match." }
        let blocks = rows.compactMap { row -> String? in
            guard let r = matchResumenV2(for: row.target) else { return nil }
            let sign = signFor(row, alias: alias)
            let me = sign == 1 && (alias == nil || alias == yoAlias || { if case .pair = row.kind { return true } else { return false } }())
            let money = row.money * sign
            if !detail {
                let counts = "F9 \(countWords(row.f9Net * sign)), B9 \(countWords(row.b9Net * sign)), match \(countWords((row.f9Net + row.b9Net) * sign))"
                let units = r.unidades.monto == 0 ? "" : ", unidades \(r.unidades.monto * sign > 0 ? "a favor" : "en contra")"
                return "\(matchName(row).prefix(1).uppercased() + matchName(row).dropFirst()), \(moneyWords(money)): \(counts)\(units)."
            }
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
