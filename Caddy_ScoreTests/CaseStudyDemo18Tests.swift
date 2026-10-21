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
}
