//
//  MatchDetailDataV2.swift
//  Caddie Score — Vista v2: detalle de UN match (datos y acciones)
//
//  Paridad con la v1: todo lo que ResultsSheetView muestra y hace para un match (individual o
//  pareja) se arma aquí con las MISMAS funciones de MatchManager que usa la v1 — buildResumen,
//  b9RefreshChip, individualCard/pairCard. No hay fórmulas nuevas ni reglas nuevas:
//  - Lectura: matchResumenV2, refreshStateV2, strokesSummaryV2, unitLog*V2.
//  - Acciones (carry / ajuste 50 / doble B9): llaman a las mismas funciones que los botones de la v1.
//

import Foundation

extension MatchManager {

    // MARK: Lectura

    /// "B9" si ya hay scores en el segundo nueve jugado, si no "F9" — igual que ResultsSheetView.currentSegment (v1).
    var currentSegmentV2: String {
        let back = Array(playOrder().suffix(9))
        let hasBackData = back.contains { hole in players.contains { getScore(hole: hole, player: $0.alias) > 0 } }
        return hasBackData ? "B9" : "F9"
    }

    /// Línea de strokes de la v1 (la que sale en dorado bajo F9/B9). Los números y el orden son los de la v1.
    func strokesSummaryV2(for target: UnitLogTarget) -> String? {
        switch target {
        case .individual(let opp): return individualStrokeSummaryLine(opponentAlias: opp)
        case .pair(let laneId):    return pairStrokeSummaryLine(laneId: laneId)
        }
    }

    /// Estado de los botones Carry / Ajuste 50 / Doble B9 (v1: variables de individualCard/pairCard + b9RefreshChip).
    struct RefreshStateV2 {
        let f9Tied: Bool
        let carryActive: Bool
        let adjust50Active: Bool
        let doublePressActive: Bool
        let carryRequester: String?
        /// Quién puede pedir el Carry (individual: el que perdió el F9; pareja: sus compañeros).
        let candidates: [String]

        /// Mismo texto que la v1 sobre los botones.
        var statusText: String {
            if carryActive { return "Carry B9 activo · \(carryRequester ?? "")" }
            if adjust50Active { return "Ajuste 50 activo" }
            if f9Tied { return "F9 empatado — Carry/Ajuste 50/Doble B9 no aplican" }
            if candidates.count > 1 { return "Perdieron F9 — elige el refresh de B9" }
            return "\(candidates.first ?? "") perdió F9 — elige el refresh de B9"
        }
    }

    func refreshStateV2(for target: UnitLogTarget) -> RefreshStateV2 {
        switch target {
        case .individual(let opp):
            let candidates = individualCarryEligibleRequester(opponentAlias: opp).map { [$0] } ?? []
            let carryOn = isIndividualCarryActive(opponentAlias: opp)
            let adjustOn = isIndividualAdjust50Active(opponentAlias: opp)
            return RefreshStateV2(
                f9Tied: candidates.isEmpty && !carryOn && !adjustOn,
                carryActive: carryOn, adjust50Active: adjustOn,
                doublePressActive: isIndividualDoublePressActive(opponentAlias: opp),
                carryRequester: individualCarryRequesterByOpponent[opp], candidates: candidates)
        case .pair(let laneId):
            let candidates = pairCarryEligibleTeam(laneId: laneId)
            let carryOn = isPairCarryActive(laneId: laneId)
            let adjustOn = isPairAdjust50Active(laneId: laneId)
            return RefreshStateV2(
                f9Tied: candidates.isEmpty && !carryOn && !adjustOn,
                carryActive: carryOn, adjust50Active: adjustOn,
                doublePressActive: isPairDoublePressActive(laneId: laneId),
                carryRequester: pairCarryRequesterByLane[laneId], candidates: candidates)
        }
    }

    /// La tabla de conceptos de un match (F9, B9, Match, Carry, Ajuste 50, Unidades, Total), idéntica a la de
    /// la v1: copia de ResultsSheetView.individualCard/pairCard + buildResumen, con las mismas llamadas.
    func matchResumenV2(for target: UnitLogTarget) -> MatchResumen? {
        func sg(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }
        func chips(_ vuelta: Int, _ pres: [Int]) -> [String] { [sg(vuelta)] + pres.map(sg) }

        let yo = yoAlias
        let wallet = walletSnapshot().lines.first { line in
            switch target {
            case .individual(let opp): return line.opponentAlias == opp
            case .pair(let laneId):    return line.laneId == laneId
            }
        }

        var jugador = yo, oponente = "", strokes = 0
        var f9V = 0, b9V = 0
        var f9Pres: [Int] = [], b9Pres: [Int] = []
        var carryActive = false, doublePressActive = false, adjust50Active = false
        var carryVuelta = 0, carryPres: [Int] = []
        var entries: [UnitLogEntry] = []
        var sign = 1

        switch target {
        case .individual(let opp):
            oponente = opp
            strokes = individualStrokesConvenio(opponentAlias: opp)
            f9V = individualF9Vuelta(opponentAlias: opp)
            b9V = individualZoomRows(opponentAlias: opp, segmentOverride: "B9").last?.vueltaAccum ?? 0
            f9Pres = individualF9Presion(opponentAlias: opp)
            b9Pres = individualB9Presion(opponentAlias: opp)
            carryActive = isIndividualCarryActive(opponentAlias: opp)
            doublePressActive = isIndividualDoublePressActive(opponentAlias: opp)
            adjust50Active = isIndividualAdjust50Active(opponentAlias: opp)
            carryVuelta = individualCarryResultB9(opponentAlias: opp)
            carryPres = individualCarryPresionB9(opponentAlias: opp)
            for seg in ["F9", "B9"] {
                entries += unitLogEntriesForZoom(segmentOverride: seg, includeIndividual: true, includePair: false)
                    .filter { $0.scope == .individual && $0.vs == opp }
            }
        case .pair(let laneId):
            guard let lane = lanes.first(where: { $0.id == laneId }) else { return nil }
            // La billetera de pareja viene del lado base: la v1 pasa los chips desde la perspectiva de yo
            // y luego los regresa a la del lado base (mismo `sign` dos veces). Se conserva igual.
            sign = lane.base.contains(yo) ? 1 : -1
            jugador = lane.base.joined(separator: "+")
            oponente = lane.opp.joined(separator: "+")
            strokes = pairStrokesConvenio(laneId: laneId)
            f9V = pairF9Vuelta(laneId: laneId) * sign
            b9V = (pairZoomRows(laneId: laneId, segmentOverride: "B9").last?.vueltaAccum ?? 0) * sign
            f9Pres = pairF9Presion(laneId: laneId).map { $0 * sign }
            b9Pres = pairB9Presion(laneId: laneId).map { $0 * sign }
            carryActive = isPairCarryActive(laneId: laneId)
            doublePressActive = isPairDoublePressActive(laneId: laneId)
            adjust50Active = isPairAdjust50Active(laneId: laneId)
            carryVuelta = pairCarryResultB9(laneId: laneId)
            carryPres = pairCarryPresionB9(laneId: laneId)
            for seg in ["F9", "B9"] {
                entries += unitLogEntriesForZoom(segmentOverride: seg, includeIndividual: false, includePair: true)
                    .filter { $0.scope == .parejas && $0.player == jugador && $0.vs == oponente }
            }
        }
        entries.sort { $0.hole < $1.hole }

        let f9 = f9V * sign, b9 = b9V * sign
        let f9p = f9Pres.map { $0 * sign }, b9p = b9Pres.map { $0 * sign }
        let matchRaw = f9 + b9
        let unidades = wallet?.unitsPoints ?? 0
        let roundDone = isRoundComplete()

        let unitLines: [String] = entries.isEmpty ? ["Sin unidades registradas"] : entries.map { e in
            "H\(e.hole) · \(e.player) · \(e.detail ?? e.type) (\(sg(e.units)))"
        }
        let campoTotal = entries.filter { !$0.type.hasPrefix("OYES") }.reduce(0) { $0 + $1.units }
        let oyesTotal = entries.filter { $0.type.hasPrefix("OYES") }.reduce(0) { $0 + $1.units }

        return MatchResumen(
            jugador: jugador, oponente: oponente, strokes: strokes,
            tag: betValues(forOpponent: oponente).vueltaValue,
            carryActivo: carryActive, dobleB9: doublePressActive,
            f9: ConceptoMatch(nombre: "F9", chips: chips(f9, f9p), monto: wallet?.f9Money ?? 0,
                              detalle: ["Vuelta F9: \(sg(f9))", "Presiones F9: " + (f9p.isEmpty ? "—" : f9p.map(sg).joined(separator: " · "))]),
            b9: ConceptoMatch(nombre: "B9", chips: chips(b9, b9p), monto: wallet?.b9Money ?? 0,
                              detalle: ["Vuelta B9: \(sg(b9))", "Presiones B9: " + (b9p.isEmpty ? "—" : b9p.map(sg).joined(separator: " · "))]
                                + (doublePressActive ? ["Doble B9: vuelta y presión de B9 ×2"] : [])),
            match: ConceptoMatch(nombre: "Match", chips: [sg(matchRaw)], monto: wallet?.matchMoney ?? 0,
                                 detalle: ["Suma de F9 + B9: \(sg(matchRaw))",
                                           roundDone ? "Ronda completa: el match ya se cobra" : "Se suma al terminar los 18 hoyos"]),
            carry: ConceptoMatch(nombre: "Carry", chips: chips(carryVuelta * sign, carryPres.map { $0 * sign }), monto: wallet?.carryMoney ?? 0,
                                 detalle: ["Vuelta del Carry B9: \(sg(carryVuelta * sign))",
                                           "Presiones del Carry: " + (carryPres.isEmpty ? "—" : carryPres.map { sg($0 * sign) }.joined(separator: " · ")),
                                           "Carry se paga con la apuesta original (Doble B9 no lo afecta)"]),
            unidades: ConceptoMatch(nombre: "Unidades", chips: [sg(unidades)], monto: wallet?.unitsMoney ?? 0,
                                    detalle: ["Campo \(sg(campoTotal)) · Oyes \(sg(oyesTotal))"] + unitLines),
            ajuste: (adjust50Active && (wallet?.adjust50Money ?? 0) != 0)
                ? ConceptoMatch(nombre: "Ajuste 50", chips: [sg(wallet?.adjust50Points ?? 0)], monto: wallet?.adjust50Money ?? 0,
                                detalle: ["Ajuste 50 activo en B9"])
                : nil
        )
    }

    // MARK: Detalle de unidades (mismo contenido que la v1)

    func unitLogTitleV2(_ target: UnitLogTarget) -> String {
        switch target {
        case .individual(let opp): return "Unidades · \(yoAlias) vs \(opp)"
        case .pair(let laneId):
            guard let lane = lanes.first(where: { $0.id == laneId }) else { return "Unidades · Pareja" }
            return "Unidades · \(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
        }
    }

    /// segment: "F9", "B9" o "ALL" (los dos nueves).
    func unitLogEntriesV2(_ target: UnitLogTarget, segment: String?) -> [UnitLogEntry] {
        let segs: [String?] = segment == "ALL" ? ["F9", "B9"] : [segment]
        switch target {
        case .individual(let opp):
            return segs.flatMap { unitLogEntriesForZoom(segmentOverride: $0, includeIndividual: true, includePair: false) }
                .filter { $0.scope == .individual && $0.vs == opp }
                .sorted { $0.hole < $1.hole }
        case .pair(let laneId):
            guard let lane = lanes.first(where: { $0.id == laneId }) else { return [] }
            let player = lane.base.joined(separator: "+")
            let vs = lane.opp.joined(separator: "+")
            return segs.flatMap { unitLogEntriesForZoom(segmentOverride: $0, includeIndividual: false, includePair: true) }
                .filter { $0.scope == .parejas && $0.player == player && $0.vs == vs }
                .sorted { $0.hole < $1.hole }
        }
    }

    // MARK: Acciones — las mismas llamadas que los botones de la v1 (b9RefreshChip)

    /// Carry: si está activo lo cancela; si no, apaga Ajuste 50 y lo activa para `requester`
    /// (individual: el elegible; pareja: el compañero elegido, por defecto el primero elegible).
    func toggleCarryV2(for target: UnitLogTarget, requester: String?) {
        switch target {
        case .individual(let opp):
            if isIndividualCarryActive(opponentAlias: opp) {
                clearIndividualCarryRequest(opponentAlias: opp)
            } else {
                if isIndividualAdjust50Active(opponentAlias: opp) { setIndividualAdjust50(opponentAlias: opp, active: false) }
                if let eligible = individualCarryEligibleRequester(opponentAlias: opp) {
                    setIndividualCarryRequest(opponentAlias: opp, requesterAlias: eligible)
                }
            }
        case .pair(let laneId):
            if isPairCarryActive(laneId: laneId) {
                clearPairCarryRequest(laneId: laneId)
            } else {
                if isPairAdjust50Active(laneId: laneId) { setPairAdjust50(laneId: laneId, active: false) }
                let chosen = requester ?? pairCarryRequesterByLane[laneId] ?? pairCarryEligibleTeam(laneId: laneId).first
                if let alias = chosen { setPairCarryRequest(laneId: laneId, requesterAlias: alias) }
            }
        }
    }

    /// Ajuste 50: si está activo lo apaga; si no, apaga el Carry y lo activa.
    func toggleAdjust50V2(for target: UnitLogTarget) {
        switch target {
        case .individual(let opp):
            if isIndividualAdjust50Active(opponentAlias: opp) {
                setIndividualAdjust50(opponentAlias: opp, active: false)
            } else {
                if isIndividualCarryActive(opponentAlias: opp) { clearIndividualCarryRequest(opponentAlias: opp) }
                setIndividualAdjust50(opponentAlias: opp, active: true)
            }
        case .pair(let laneId):
            if isPairAdjust50Active(laneId: laneId) {
                setPairAdjust50(laneId: laneId, active: false)
            } else {
                if isPairCarryActive(laneId: laneId) { clearPairCarryRequest(laneId: laneId) }
                setPairAdjust50(laneId: laneId, active: true)
            }
        }
    }

    /// Doble B9: se prende/apaga solo (no depende de Carry ni de Ajuste 50).
    func toggleDoublePressV2(for target: UnitLogTarget) {
        switch target {
        case .individual(let opp):
            setIndividualDoublePress(opponentAlias: opp, active: !isIndividualDoublePressActive(opponentAlias: opp))
        case .pair(let laneId):
            setPairDoublePress(laneId: laneId, active: !isPairDoublePressActive(laneId: laneId))
        }
    }
}
