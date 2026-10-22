//
//  CatalogGatingTests.swift
//  Caddy_ScoreTests
//
//  El catálogo de apuestas gobierna qué cuenta: apagar Oyes, Oyes Parejas o Match Parejas los quita del cálculo,
//  el "Vale" de Oyes se usa y una unidad manual apagada deja de contar (sus eventos se conservan). Se prueba con el
//  caso de estudio cambiando solo `betCatalog` (las definiciones ACTIVAS), sin tocar el catálogo guardado.
//

import Testing
@testable import Caddy_Score

@MainActor
struct CatalogGatingTests {

    private func catalog(without tags: Set<String> = [], oyesUnits: Int = 1) -> [BetDefinition] {
        DemoFixture.defaultCatalog()
            .filter { !tags.contains($0.tag) }
            .map { def in
                var copy = def
                if def.tag == "OYES" || def.tag == "OYESP" { copy.units = oyesUnits }
                return copy
            }
    }

    private func robUnits(_ m: MatchManager) -> Int {
        m.resultadoRowsV2().first { $0.title == "ROB" }?.unitsNet ?? 0
    }

    @Test func switchingOyesOffRemovesItFromTheCalculation() {
        let m = DemoFixture.make()
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") != nil)
        #expect(m.unitLogEntriesForZoom().contains { $0.type.hasPrefix("OYES") })
        m.betCatalog = catalog(without: ["OYES"])
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") == nil)
        #expect(!m.unitLogEntriesForZoom(includePair: false).contains { $0.type.hasPrefix("OYES") })
        #expect(!m.isOyesEnabled)
    }

    @Test func oyesIsWorthWhatTheCatalogSays() {
        let m = DemoFixture.make()
        // En el hoyo 14 DAN (puesto 3) pierde el oye contra ROB (puesto 2): -1 unidad con "Vale 1".
        m.betCatalog = catalog(oyesUnits: 1)
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") == -1)
        m.betCatalog = catalog(oyesUnits: 3)
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") == -3)
    }

    @Test func switchingPairOyesOffOnlyAffectsPairs() {
        let m = DemoFixture.make()
        let laneId = m.lanes[0].id
        #expect(m.oyesPairOutcome(hole: 14, laneId: laneId) != nil)
        let individualBefore = robUnits(m)
        m.betCatalog = catalog(without: ["OYESP"])
        #expect(m.oyesPairOutcome(hole: 14, laneId: laneId) == nil)
        #expect(robUnits(m) == individualBefore)
    }

    @Test func switchingPairMatchOffRemovesEveryPairLine() {
        let m = DemoFixture.make()
        #expect(m.resultadoRowsV2().filter(\.isPair).count == 3)
        let individualsOnly = m.resultadoRowsV2().filter { !$0.isPair }.reduce(0) { $0 + $1.money }
        m.betCatalog = catalog(without: ["PAIR"])
        #expect(m.resultadoRowsV2().filter(\.isPair).isEmpty)
        #expect(m.walletSnapshot().lines.allSatisfy { $0.scope != .parejas })
        #expect(m.walletSnapshot().totalMoney == individualsOnly)
        #expect(m.activeLanes.isEmpty && !m.lanes.isEmpty)   // las parejas siguen definidas, solo no cuentan
    }

    @Test func aSwitchedOffManualUnitStopsCountingButKeepsItsEvents() {
        let m = DemoFixture.make()
        let before = robUnits(m)
        m.upsertUnitEvent(hole: 1, alias: "DAN", code: "3P", units: 1)
        #expect(robUnits(m) == before + 1)
        m.betCatalog = catalog(without: ["3P"])
        #expect(robUnits(m) == before)
        #expect(m.unitEventsByHole[1]?.contains { $0.code == "3P" && $0.alias == "DAN" } == true)
        m.betCatalog = catalog()
        #expect(robUnits(m) == before + 1)   // al reactivarla vuelve a contar
    }

    @Test func notesAndUnknownCodesAlwaysCount() {
        let m = DemoFixture.make()
        #expect(m.isUnitCodeActive("NOTA"))
        #expect(m.isUnitCodeActive("4P"))          // no está en el catálogo: no se apaga
        #expect(m.isUnitCodeActive("3P"))
        m.betCatalog = catalog(without: ["3P"])
        #expect(!m.isUnitCodeActive("3P"))
    }

    @Test func builtInUnitsCannotBeDeletedButCustomOnesCan() {
        let store = BetDefinitionStore.shared
        let builtIn = BetDefinition(tag: "OYES", name: "Oyes Rank", type: .individual, mode: .manual, units: 1, description: "")
        let custom = BetDefinition(tag: "SAND", name: "Sandy par", type: .individual, mode: .manual, units: 1, description: "")
        #expect(store.isBuiltIn(builtIn))
        #expect(!store.isBuiltIn(custom))
    }
}
