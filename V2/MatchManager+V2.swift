//
//  MatchManager+V2.swift
//  Caddie Score — Vista v2: datos de solo lectura para las pantallas v2
//
//  Regla de la v2: NO se cambia lógica. Este archivo solo LEE de MatchManager llamando las mismas
//  funciones que ya usa la v1 (ResultsSheetView.resumenRows) y las junta en filas listas para
//  dibujar. Si la v1 cambia un número, la v2 lo cambia igual: no hay segunda fórmula.
//

import Foundation

extension MatchManager {

    /// Un match (individual o pareja) visto desde yoAlias — una fila de la pantalla Resultado v2.
    struct ResultadoRowV2: Identifiable {
        enum Kind {
            case individual(alias: String)
            case pair(laneId: UUID)
        }

        let kind: Kind
        /// "ROB" (individual) o "con FER" (pareja: el compañero de yo).
        let title: String
        /// Solo parejas: "RIC – ANS" (nombres unidos con guion, nunca con "+").
        let rivalsText: String?
        /// Quién recibe los golpes del match (nil = nadie / sin definir) y cuántos (admite ½).
        let strokesReceiver: String?
        let strokesAmount: Double
        /// Resultado de cada nueve desde el lado de yo (hoyos ganados − perdidos) y hoyos jugados.
        let f9Net: Int
        let f9Played: Int
        let b9Net: Int
        let b9Played: Int
        /// Valor de cada presión abierta en cada nueve (lado de yo), igual que el sub-renglón de F9/B9 en la v1.
        let f9Presiones: [Int]
        let b9Presiones: [Int]
        /// Carry de B9 (solo B9): si está activo y cuánto dinero lleva ahora (puede ser $0).
        let carryActive: Bool
        let carryMoney: Int
        /// Unidades netas (eventos + oyes), igual que la columna UNID de la v1.
        let unitsNet: Int
        let money: Int
        /// Con qué se apuesta este match: plantilla (el "tag", p. ej. TPCH) y sus valores — "TPCH · vuelta $50 · presión $50 …".
        let betText: String?

        var id: String {
            switch kind {
            case .individual(let alias): return "ind-\(alias)"
            case .pair(let laneId):      return "par-\(laneId.uuidString)"
            }
        }

        /// Destino del detalle existente de la v1 (MatchZoomView).
        var target: UnitLogTarget {
            switch kind {
            case .individual(let alias): return .individual(alias)
            case .pair(let laneId):      return .pair(laneId)
            }
        }

        var isPair: Bool {
            if case .pair = kind { return true }
            return false
        }
    }

    /// Filas de la pantalla Resultado v2: primero los rivales individuales, luego las parejas.
    /// Mismas llamadas que ResultsSheetView.resumenRows (v1).
    func resultadoRowsV2() -> [ResultadoRowV2] {
        let wallet = walletSnapshot()
        var rows: [ResultadoRowV2] = []

        for opp in players where opp.alias != yoAlias {
            let line = wallet.lines.first { $0.opponentAlias == opp.alias }
            let f9Rows = individualZoomRows(opponentAlias: opp.alias, segmentOverride: "F9")
            let b9Rows = individualZoomRows(opponentAlias: opp.alias, segmentOverride: "B9")
            // strokesVsBase: > 0 = el rival recibe de yo; < 0 = yo recibo del rival.
            let receiver: String? = opp.strokesVsBase > 0 ? opp.alias : (opp.strokesVsBase < 0 ? yoAlias : nil)
            let bet = betValues(forOpponent: opp.alias)
            rows.append(ResultadoRowV2(
                kind: .individual(alias: opp.alias),
                title: opp.alias,
                rivalsText: nil,
                strokesReceiver: receiver,
                strokesAmount: abs(opp.strokesVsBase),
                f9Net: individualF9Vuelta(opponentAlias: opp.alias),
                f9Played: f9Rows.count,
                b9Net: b9Rows.last?.vueltaAccum ?? 0,
                b9Played: b9Rows.count,
                f9Presiones: individualF9Presion(opponentAlias: opp.alias),
                b9Presiones: individualB9Presion(opponentAlias: opp.alias),
                carryActive: line?.carryActive ?? false,
                carryMoney: line?.carryMoney ?? 0,
                unitsNet: line?.unitsPoints ?? 0,
                money: line?.totalMoney ?? 0,
                betText: betSummaryV2(templateId: bet.templateId, values: bet)
            ))
        }

        for lane in activeLanes {
            let line = wallet.lines.first { $0.laneId == lane.id }
            let mine = lane.base.contains(yoAlias)
            let sign = mine ? 1 : -1
            let mySide = mine ? lane.base : lane.opp
            let rivalSide = mine ? lane.opp : lane.base
            let partners = mySide.filter { $0 != yoAlias }
            let f9Rows = pairZoomRows(laneId: lane.id, segmentOverride: "F9")
            let b9Rows = pairZoomRows(laneId: lane.id, segmentOverride: "B9")
            rows.append(ResultadoRowV2(
                kind: .pair(laneId: lane.id),
                title: partners.isEmpty ? "pareja" : "con " + partners.joined(separator: " – "),
                rivalsText: rivalSide.joined(separator: " – "),
                strokesReceiver: lane.strokes > 0 ? lane.strokeCarrier : nil,
                strokesAmount: lane.strokes,
                f9Net: pairF9Vuelta(laneId: lane.id) * sign,
                f9Played: f9Rows.count,
                b9Net: (b9Rows.last?.vueltaAccum ?? 0) * sign,
                b9Played: b9Rows.count,
                f9Presiones: pairF9Presion(laneId: lane.id).map { $0 * sign },
                b9Presiones: pairB9Presion(laneId: lane.id).map { $0 * sign },
                carryActive: line?.carryActive ?? false,
                carryMoney: line?.carryMoney ?? 0,
                unitsNet: line?.unitsPoints ?? 0,
                money: line?.totalMoney ?? 0,
                betText: betSummaryV2(templateId: activeTemplateId,
                                      values: OpponentBetValues(templateId: activeTemplateId, vueltaValue: vueltaValue,
                                                                presionValue: presionValue, matchValue: matchValue,
                                                                unitValue: unitValue))
            ))
        }
        return rows
    }

    /// "TPCH · vuelta $50 · presión $50 · match $50 · unidad $25" (nil si no hay ni plantilla ni valores).
    func betSummaryV2(templateId: String?, values: OpponentBetValues) -> String? {
        let name = templateId.flatMap { id in BetTemplateStore.shared.entries.first { $0.id == id }?.name }
        let amounts = "vuelta $\(values.vueltaValue) · presión $\(values.presionValue) · match $\(values.matchValue) · unidad $\(values.unitValue)"
        return name.map { "\($0) · \(amounts)" } ?? amounts
    }

    /// Neto de la ronda: la suma de todos los matches (igual que "TOTAL GENERAL" en la v1).
    func resultadoTotalV2() -> Int {
        resultadoRowsV2().reduce(0) { $0 + $1.money }
    }

    /// Hoyos con score de todos los jugadores ("después de N hoyos").
    func completedHolesCountV2() -> Int {
        (1...18).filter { isHoleComplete($0) }.count
    }
}

// MARK: - Tarjeta v2 (P2): tabla de golpes por nueve, en orden de juego

extension MatchManager {

    /// Una celda de la tarjeta: lo que el jugador anotó en ese hoyo.
    struct TarjetaCellV2 {
        /// Golpes brutos (nil = sin anotar).
        let gross: Int?
        /// Golpes que ESE jugador recibe en el hoyo — misma regla que la v1: solo los rivales que
        /// reciben de yo (strokesVsBase > 0). La columna de yo y los rivales que dan golpes no llevan punto.
        let strokes: Double
        /// Evento de unidad u oye ganado en ese hoyo (cuadro dorado).
        let hasEvent: Bool
        /// Putts anotados (nil = sin anotar; solo se registran los de quien rastrea putts, regla R8).
        let putts: Int?
    }

    struct TarjetaHoleV2: Identifiable {
        var id: Int { hole }
        let hole: Int
        let par: Int
        let hcp: Int
        /// Una celda por jugador, en el orden de `players`.
        let cells: [TarjetaCellV2]
    }

    /// Un nueve JUGADO: F9 = primeros 9 en orden de juego, B9 = los siguientes 9.
    struct TarjetaNineV2: Identifiable {
        var id: String { name }
        let name: String            // "F9" / "B9"
        let rangeText: String       // "10–18" o "14–18, 1–4"
        let holes: [TarjetaHoleV2]
        let parTotal: Int
        /// Suma de golpes por jugador (nil si no hay ningún score en ese nueve).
        let grossTotals: [Int?]
        /// Suma de putts por jugador (nil si no hay ninguno en ese nueve).
        let puttsTotals: [Int?]
        var title: String { "\(name) · \(rangeText)" }
    }

    func tarjetaNinesV2() -> [TarjetaNineV2] {
        let order = playOrder()
        let manual = unitEventsByHole
        let calculatedAndManual = unitEventsForZoom(segmentOverride: "F9") + unitEventsForZoom(segmentOverride: "B9")

        func hasEvent(alias: String, hole: Int) -> Bool {
            // Mismo criterio que la tarjeta del hoyo en la v1: BIRD no cuenta (ya lo dice la marca del score)
            // y las notas ("NOTA") no son eventos.
            let counts: (UnitEvent) -> Bool = {
                $0.hole == hole && $0.alias == alias
                    && $0.code.uppercased() != "BIRD" && $0.code.uppercased() != "NOTA"
            }
            if (manual[hole] ?? []).contains(where: { counts($0) && isUnitCodeActive($0.code) }) { return true }
            if calculatedAndManual.contains(where: counts) { return true }
            if isOyesEnabled, oyesRanksByHole[hole]?[alias] == 1 { return true }
            return hasPairUnitWin(hole: hole, alias: alias)
        }

        let nines: [(String, [Int])] = [("F9", Array(order.prefix(9))), ("B9", Array(order.suffix(9)))]
        return nines.map { name, holeNumbers in
            let holes = holeNumbers.map { h -> TarjetaHoleV2 in
                let data = getHole(h)
                let cells = players.map { p -> TarjetaCellV2 in
                    let score = getScore(hole: h, player: p.alias)
                    let putts = getPutts(hole: h, player: p.alias)
                    return TarjetaCellV2(
                        gross: score > 0 ? score : nil,
                        strokes: distributedStrokes(total: p.strokesVsBase, hole: h),
                        hasEvent: hasEvent(alias: p.alias, hole: h),
                        putts: putts > 0 ? putts : nil
                    )
                }
                return TarjetaHoleV2(hole: h, par: data?.par ?? 4, hcp: data?.si ?? 0, cells: cells)
            }
            let totals: [Int?] = players.indices.map { i in
                let scores = holes.compactMap { $0.cells[i].gross }
                return scores.isEmpty ? nil : scores.reduce(0, +)
            }
            let puttsTotals: [Int?] = players.indices.map { i in
                let values = holes.compactMap { $0.cells[i].putts }
                return values.isEmpty ? nil : values.reduce(0, +)
            }
            return TarjetaNineV2(name: name, rangeText: Self.rangeTextV2(holeNumbers), holes: holes,
                                 parTotal: holes.reduce(0) { $0 + $1.par }, grossTotals: totals,
                                 puttsTotals: puttsTotals)
        }
    }

    /// [10,11,…,18] → "10–18"; [14,…,18,1,…,4] → "14–18, 1–4" (sin "+" para unir).
    static func rangeTextV2(_ holes: [Int]) -> String {
        var runs: [(Int, Int)] = []
        for h in holes {
            if let last = runs.last, h == last.1 + 1 { runs[runs.count - 1].1 = h } else { runs.append((h, h)) }
        }
        return runs.map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0)–\($0.1)" }.joined(separator: ", ")
    }
}


// MARK: - Strokes por hoyo de cada match (para resaltarlos en la Tarjeta v2)

extension MatchManager {

    /// Hoyo → (alias → strokes que recibe ESE jugador en ESE match). Individual: quien recibe del otro (también yo);
    /// pareja: el jugador que lleva los strokes. Los hoyos ya jugados salen de las mismas filas del detalle del match
    /// (con los ajustes de Carry / Ajuste 50); los demás, del reparto base por orden de juego.
    func matchStrokesByHoleV2(_ target: UnitLogTarget) -> [Int: [String: Double]] {
        var result: [Int: [String: Double]] = [:]
        switch target {
        case .individual(let opp):
            guard let rival = players.first(where: { $0.alias == opp }) else { return [:] }
            let receiver = rival.strokesVsBase > 0 ? opp : yoAlias
            if rival.strokesVsBase != 0 {
                for hole in 1...18 {
                    let v = distributedStrokes(total: abs(rival.strokesVsBase), hole: hole)
                    if v > 0 { result[hole] = [receiver: v] }
                }
            }
            let played = individualZoomRows(opponentAlias: opp, segmentOverride: "F9")
                + individualZoomRows(opponentAlias: opp, segmentOverride: "B9")
            for row in played {
                var entry: [String: Double] = [:]
                if row.yoStrokes > 0 { entry[yoAlias] = row.yoStrokes }
                if row.oppStrokes > 0 { entry[opp] = row.oppStrokes }
                result[row.hole] = entry.isEmpty ? nil : entry
            }
        case .pair(let laneId):
            guard let lane = lanes.first(where: { $0.id == laneId }) else { return [:] }
            for hole in 1...18 {
                var entry: [String: Double] = [:]
                for alias in lane.base + lane.opp {
                    let v = pairStrokeForPlayer(laneId: laneId, alias: alias, hole: hole)
                    if v > 0 { entry[alias] = v }
                }
                if !entry.isEmpty { result[hole] = entry }
            }
        }
        return result
    }

    /// Jugadores que participan en un match (sus columnas se destacan en la Tarjeta).
    func matchParticipantsV2(_ target: UnitLogTarget) -> Set<String> {
        switch target {
        case .individual(let opp): return [yoAlias, opp]
        case .pair(let laneId):
            guard let lane = lanes.first(where: { $0.id == laneId }) else { return [] }
            return Set(lane.base + lane.opp)
        }
    }
}
