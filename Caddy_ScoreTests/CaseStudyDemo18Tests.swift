//
//  CaseStudyDemo18Tests.swift
//  Caddy_ScoreTests
//
//  Red de seguridad antes de construir la Vista v2: fija los números del caso de estudio
//  (la ronda demo `loadDemo18()` del CGM) para poder demostrar que cualquier pantalla nueva
//  muestra lo mismo que la v1. Si una de estas pruebas falla, cambió la lógica, no el diseño.
//
//  Origen de los valores esperados:
//  - golpes brutos, F9/B9 vs ROB y reparto de golpes: calculados a mano sobre el scorecard del demo;
//  - dinero (+$1325 / +$1175): leído de la app en el simulador (Resumen, TOTAL GENERAL).
//
//  Nota: loadDemo18() guarda la config de apuestas (saveBetConfig) — correr estas pruebas solo
//  en el simulador, no sobre un dispositivo con una ronda real en curso.
//

import Foundation
import Testing
@testable import Caddy_Score

@MainActor
struct CaseStudyDemo18Tests {

    // Ronda demo recién cargada: CGM, sale en el hoyo 1, ROB da 8 a DAN, pareja DAN+FER vs RIC+ANS (12).
    private func makeDemo() -> MatchManager {
        let m = MatchManager()
        m.loadDemo18()
        return m
    }

    private func holesWhereDanReceives(from opp: String, in m: MatchManager) -> Set<Int> {
        Set((1...18).filter {
            m.individualMatchupStrokes(yoAlias: "DAN", oppAlias: opp, hole: $0, carryAlias: nil).yo > 0
        })
    }

    private func grossSum(_ m: MatchManager, alias: String, holes: [Int]) -> Int {
        holes.reduce(0) { $0 + m.getScore(hole: $1, player: alias) }
    }

    // MARK: Datos base

    @Test func demoLoadsFivePlayersFromHoleOne() {
        let m = makeDemo()
        #expect(m.players.map(\.alias) == ["DAN", "FER", "ROB", "RIC", "ANS"])
        #expect(m.startHole == 1)
        #expect(m.playOrder() == Array(1...18))
    }

    @Test func danGrossByNine() {
        let m = makeDemo()
        #expect(grossSum(m, alias: "DAN", holes: Array(1...9)) == 48)
        #expect(grossSum(m, alias: "DAN", holes: Array(10...18)) == 58)
        #expect(grossSum(m, alias: "DAN", holes: Array(1...18)) == 106)
    }

    // MARK: Reparto de golpes (regla R3)

    @Test func eightStrokesVsRobAtStartOne() {
        let m = makeDemo()
        #expect(holesWhereDanReceives(from: "ROB", in: m) == [4, 17, 2, 11, 6, 10, 9, 15])
    }

    // Con totales PARES el reparto en CGM no cambia al mover la salida (los SI son impares en
    // 1-9 y pares en 10-18); lo que cambia es qué nueve es F9.
    @Test func eightStrokesVsRobSameHolesAtStartTen() {
        let m = makeDemo()
        m.updateStartHole(10, resetScores: false)
        #expect(holesWhereDanReceives(from: "ROB", in: m) == [4, 17, 2, 11, 6, 10, 9, 15])
    }

    // Con totales IMPARES sí se reasigna: el golpe extra va al primer nueve jugado.
    @Test func sevenStrokesMoveWithStartHole() {
        let m = makeDemo()
        m.setStrokesVsBase(alias: "ROB", value: -7)
        #expect(holesWhereDanReceives(from: "ROB", in: m) == [2, 4, 6, 9, 10, 11, 17])
        m.updateStartHole(10, resetScores: false)
        #expect(holesWhereDanReceives(from: "ROB", in: m) == [2, 4, 6, 10, 11, 15, 17])
    }

    // El total de golpes nunca cambia, solo dónde caen: la suma sobre los 18 hoyos es el total,
    // con cualquier hoyo de salida y también con medios golpes.
    @Test func distributionAlwaysSumsToTheTotal() {
        let holes = CourseCatalog.cgm.holes
        for start in 1...18 {
            for half in 0...40 {
                let total = Double(half) / 2
                let sum = holes.reduce(0.0) {
                    $0 + MatchManager.distributedStrokes(total: total, hole: $1.number, startHole: start, holes: holes)
                }
                #expect(abs(sum - total) < 0.001, "salida \(start), total \(total): suma \(sum)")
            }
        }
    }

    // Salida en 1 en CGM = la regla anterior (solo SI). Es la garantía de que las rondas
    // existentes no cambian.
    @Test func startOneEqualsOldSIRule() {
        let holes = CourseCatalog.cgm.holes
        func oldRule(_ total: Double, si: Int) -> Double {
            guard total > 0 else { return 0 }
            let full = Int(total / 18.0)
            let remainder = total - Double(full * 18)
            let whole = Int(remainder.rounded(.down))
            let fraction = remainder - Double(whole)
            var strokes = Double(full)
            if si <= whole { strokes += 1 } else if fraction >= 0.5, si == whole + 1 { strokes += 0.5 }
            return strokes
        }
        for half in 0...80 {
            let total = Double(half) / 2
            for h in holes {
                let new = MatchManager.distributedStrokes(total: total, hole: h.number, startHole: 1, holes: holes)
                #expect(new == oldRule(total, si: h.si), "total \(total), hoyo \(h.number)")
            }
        }
    }

    // MARK: Resultados vs ROB (hoyos ganados con golpes)

    @Test func robNinesAtStartOne() {
        let m = makeDemo()
        #expect(m.individualF9Vuelta(opponentAlias: "ROB") == 2)
        #expect(m.individualB9Vuelta(opponentAlias: "ROB") == 4)
    }

    // Mover la salida a 10: F9 pasa a ser 10-18 y B9 1-9, así que los resultados se intercambian.
    @Test func robNinesSwapAtStartTen() {
        let m = makeDemo()
        m.updateStartHole(10, resetScores: false)
        #expect(m.individualF9Vuelta(opponentAlias: "ROB") == 4)
        #expect(m.individualB9Vuelta(opponentAlias: "ROB") == 2)
    }

    // MARK: Efectos de cambiar la salida (R5)

    @Test func changingStartHoleSwitchesOffCarryAndDoublePress() {
        let m = makeDemo()
        #expect(m.individualCarryRequesterByOpponent["ROB"] != nil)
        #expect(m.individualDoublePressOpponents.contains("ROB"))
        m.updateStartHole(10, resetScores: false)
        #expect(m.individualCarryRequesterByOpponent.isEmpty)
        #expect(m.individualDoublePressOpponents.isEmpty)
    }

    @Test func sameStartHoleKeepsCarry() {
        let m = makeDemo()
        m.updateStartHole(1, resetScores: false)
        #expect(m.individualCarryRequesterByOpponent["ROB"] != nil)
    }

    // MARK: Dinero
    //
    // El caso de estudio define SUS PROPIOS valores (vuelta/presión/match $50, unidad $25 — ver
    // loadDemo18) y aquí se fija también el catálogo de unidades, para que el resultado no dependa
    // de lo que haya guardado en el dispositivo. (En el simulador la app daba $1325 porque traía
    // valores por rival guardados de corridas anteriores: +$100 extra en el match de cada rival.)

    private func defaultCatalog() -> [BetDefinition] { DemoFixture.defaultCatalog() }

    private func money(_ m: MatchManager) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: m.walletSnapshot().lines.map { ($0.label, $0.totalMoney) })
    }

    @Test func moneyPerLineAtStartOne() {
        let m = makeDemo()
        m.betCatalog = defaultCatalog()
        let lines = money(m)
        #expect(lines["vs FER"] == -300)
        #expect(lines["vs ROB"] == 425)       // F9 +2 = $50 · B9 +4/+2 doble = $200 · match $50 · carry $100 · unidades $25
        #expect(lines["vs RIC"] == 75)
        #expect(lines["vs ANS"] == 125)
        #expect(lines["DAN+FER/ROB+RIC"] == 350)
        #expect(lines["DAN+FER/ROB+ANS"] == 350)
        #expect(lines["DAN+FER/RIC+ANS"] == 200)
        #expect(m.walletSnapshot().totalMoney == 1225)
    }

    // Mover la salida a 10 apaga Carry/Doble B9 y reparte los nueves al revés: baja $150 en este caso.
    @Test func totalMoneyAtStartTen() {
        let m = makeDemo()
        m.betCatalog = defaultCatalog()
        m.updateStartHole(10, resetScores: false)
        #expect(m.walletSnapshot().totalMoney == 1075)
    }

    // MARK: R13 — F9 en 0: B9 y Match se pagan con un solo precio combinado

    private func tiedF9Match() -> MatchManager {
        let m = DemoFixture.make()
        m.clearCarryDependentState()
        m.setStrokesVsBase(alias: "ROB", value: 0)
        let order = m.playOrder()
        for (index, hole) in order.enumerated() {
            let dan = m.getScore(hole: hole, player: "DAN")
            // F9: ROB empata a DAN hoyo por hoyo. B9: ROB hace uno más (DAN gana cada hoyo).
            m.applyHoleEntry(HoleEntryData(hole_number: hole, player_alias: "ROB", strokes: index < 9 ? dan : dan + 1,
                                           putts: 0, units: nil, tags: nil))
        }
        return m
    }

    @Test func tiedF9PaysB9AndMatchWithOneCombinedPrice() throws {
        let m = tiedF9Match()
        #expect(m.individualF9Vuelta(opponentAlias: "ROB") == 0)
        let line = try #require(m.walletSnapshot().lines.first { $0.opponentAlias == "ROB" && $0.scope == .individual })
        let v = m.betValues(forOpponent: "ROB")
        let price = v.vueltaValue + v.presionValue + v.matchValue
        let b9Presiones = m.individualB9Presion(opponentAlias: "ROB").reduce(0) { $0 + ($1 > 0 ? 1 : $1 < 0 ? -1 : 0) }
        let units = (m.individualB9Vuelta(opponentAlias: "ROB") > 0 ? 1 : -1) + b9Presiones
        #expect(units >= 2)                                   // vuelta + al menos una presión abierta
        #expect(line.matchMoney == 0)                         // el Match no se paga aparte
        #expect(line.vueltaMoney == units * price)            // unidades × (vuelta + presión + match)
        #expect(line.presionMoney == 0)                       // la presión de F9 no se abrió
    }

    @Test func withAnyOfTheThreeBetsOffTheNormalCalculationApplies() throws {
        let m = tiedF9Match()
        let alias = "ROB"
        var switches = m.betSwitchesForIndividual(opponentAlias: alias)
        switches.match = false
        m.setBetSwitchesForIndividual(opponentAlias: alias, switches: switches)
        let line = try #require(m.walletSnapshot().lines.first { $0.opponentAlias == alias && $0.scope == .individual })
        let v = m.betValues(forOpponent: alias)
        #expect(line.vueltaMoney == v.vueltaValue)            // solo la vuelta de B9 × su valor, sin precio combinado
    }

    @Test func tiedF9LeavesTheNextMatchStrokesAndSaysSoInTheDirectory() throws {
        let m = tiedF9Match()
        #expect(m.isF9ZeroCarry(opponentAlias: "ROB"))
        let name = "test_directory_\(UUID().uuidString).json"
        let store = PlayerDirectoryStore(fileName: name)
        defer {
            if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(name) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let next = m.applyInterMatchStrokeCarry(directory: store)
        #expect(next["ROB"] == 0)                                  // el stroke con el que se jugó (0) no cambia
        let rob = try #require(store.entries.first { $0.name == "Roberto" })
        #expect(rob.strokesVsBase == 0 && rob.strokeAnt == 0)
        #expect(rob.lastResult?.hasPrefix(MatchManager.f9ZeroNote) == true)
    }

    @Test func tiedF9ShowsCarryWithTheCombinedPriceInResults() throws {
        let m = tiedF9Match()
        let row = try #require(m.resultadoRowsV2().first { $0.title == "ROB" })
        let v = m.betValues(forOpponent: "ROB")
        #expect(row.f9CarryPrice == v.vueltaValue + v.presionValue + v.matchValue)
        // Un F9 ganado o perdido no es Carry.
        let other = try #require(DemoFixture.make().resultadoRowsV2().first { $0.title == "ROB" })
        #expect(other.f9CarryPrice == nil)
    }

    @Test func tiedF9AlsoBundlesThePriceInPairs() throws {
        let m = DemoFixture.make()
        m.clearCarryDependentState()
        for p in m.players where p.alias != m.yoAlias { m.setStrokesVsBase(alias: p.alias, value: 0) }
        guard let lane = m.lanes.first(where: { Set($0.opp) == ["RIC", "ANS"] }) else { Issue.record("sin carril"); return }
        m.setLaneStrokesForMatch(base: lane.base, opp: lane.opp, value: 0)
        for (index, hole) in m.playOrder().enumerated() {
            let par = m.getHole(hole)?.par ?? 4
            for p in m.players {
                let weak = ["RIC", "ANS"].contains(p.alias) && index >= 9      // B9: la pareja base gana todos los hoyos
                m.applyHoleEntry(HoleEntryData(hole_number: hole, player_alias: p.alias, strokes: par + (weak ? 1 : 0),
                                               putts: 0, units: nil, tags: nil))
            }
        }
        // Las parejas se reconstruyen con ids nuevos al cambiar strokes: se vuelve a buscar el carril.
        guard let lane = m.lanes.first(where: { Set($0.opp) == ["RIC", "ANS"] }) else { Issue.record("sin carril"); return }
        #expect(m.pairF9Vuelta(laneId: lane.id) == 0)
        let line = try #require(m.walletSnapshot().lines.first { $0.laneId == lane.id })
        let price = m.vueltaValue + m.presionValue + m.matchValue
        let b9P = m.pairB9Presion(laneId: lane.id).reduce(0) { $0 + ($1 > 0 ? 1 : $1 < 0 ? -1 : 0) }
        #expect(line.matchMoney == 0)
        #expect(line.vueltaMoney == (1 + b9P) * price)
        let row = try #require(m.resultadoRowsV2().first { $0.id == "par-\(lane.id.uuidString)" })
        #expect(row.f9CarryPrice == price)
    }
}
