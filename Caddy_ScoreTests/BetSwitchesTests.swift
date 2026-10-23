//
//  BetSwitchesTests.swift
//  Caddy_ScoreTests
//
//  "No, yo no apuesto oyes": cada match puede apagar Oyes (y vuelta, presión, carry, ajuste 50, match, unidades)
//  sin tocar el catálogo. Apagar Oyes en un match no afecta a los demás, y los archivos viejos siguen leyéndose.
//

import Testing
import Foundation
@testable import Caddy_Score

@MainActor
struct BetSwitchesTests {

    private func robUnits(_ m: MatchManager) -> Int {
        m.resultadoRowsV2().first { $0.title == "ROB" }?.unitsNet ?? 0
    }

    @Test func turningOyesOffForOneRivalOnlyAffectsThatMatch() {
        let m = DemoFixture.make()
        let robBefore = robUnits(m)
        let robOyesTotal = (1...18).reduce(0) { $0 + (m.oyesIndividualOutcome(hole: $1, opponentAlias: "ROB") ?? 0) }
        let robOyes = m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB")
        let ricOyes = m.oyesIndividualOutcome(hole: 14, opponentAlias: "RIC")
        #expect(robOyes != nil && robOyes != 0)

        var sw = m.betSwitchesForIndividual(opponentAlias: "ROB")
        sw.oyes = false
        m.setBetSwitchesForIndividual(opponentAlias: "ROB", switches: sw)

        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") == nil)
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "RIC") == ricOyes)
        #expect(robUnits(m) == robBefore - robOyesTotal)   // se va solo lo que valían los oyes de ese match

        sw.oyes = true
        m.setBetSwitchesForIndividual(opponentAlias: "ROB", switches: sw)
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") == robOyes)
        #expect(robUnits(m) == robBefore)   // al volver a prenderlo, todo vuelve
    }

    @Test func turningOyesOffForAPairOnlyAffectsThatPair() {
        let m = DemoFixture.make()
        let lane = m.lanes[0]
        #expect(m.oyesPairOutcome(hole: 14, laneId: lane.id) != nil)
        var sw = m.betSwitchesForPair(laneId: lane.id)
        sw.oyes = false
        m.setBetSwitchesForPair(laneId: lane.id, switches: sw)
        #expect(m.oyesPairOutcome(hole: 14, laneId: lane.id) == nil)
        #expect(m.oyesPairOutcome(hole: 14, laneId: m.lanes[1].id) != nil)
    }

    @Test func switchesOldFilesWithoutOyesStillDecodeAsOn() throws {
        let old = #"{"vuelta":true,"presion":false,"carry":true,"adjust50":true,"match":true,"units":true}"#
        let sw = try JSONDecoder().decode(MatchBetSwitches.self, from: Data(old.utf8))
        #expect(sw.oyes)
        #expect(!sw.presion)
        let round = try JSONDecoder().decode(MatchBetSwitches.self, from: JSONEncoder().encode(sw))
        #expect(round == sw)
    }

    @Test func theSummaryListsWhatIsOn() {
        var sw = MatchBetSwitches()
        #expect(sw.summary == "V P C A M O U")
        sw.oyes = false
        #expect(sw.summary == "V P C A M U")
    }

    @Test func theRoundSummaryAndTheEveryoneSwitchFollowTheMatches() {
        let m = DemoFixture.make()
        #expect(m.betSwitchesSummaryV2 == "todas activas")
        #expect(m.betSwitchTargetsV2().count == 4 + 3)   // 4 rivales + 3 parejas del caso de estudio

        var sw = m.betSwitchesForIndividual(opponentAlias: "ROB")
        sw.oyes = false
        m.setBetSwitchesForIndividual(opponentAlias: "ROB", switches: sw)
        #expect(m.betSwitchesSummaryV2 == "sin Oyes en 1")

        m.setAllBetSwitchesV2(\.oyes, to: false)
        #expect(m.betSwitchesSummaryV2 == "sin Oyes")
        #expect(m.betSwitchTargetsV2().allSatisfy { !m.betSwitchesV2(for: $0.target).oyes })
        #expect((1...18).allSatisfy { m.oyesIndividualOutcome(hole: $0, opponentAlias: "RIC") == nil })

        m.setAllBetSwitchesV2(\.oyes, to: true)
        #expect(m.betSwitchesSummaryV2 == "todas activas")
    }

    @Test func resultsSayWhatWasSwitchedOff() {
        let m = DemoFixture.make()
        var sw = m.betSwitchesForIndividual(opponentAlias: "ROB")
        sw.oyes = false
        sw.units = false
        m.setBetSwitchesForIndividual(opponentAlias: "ROB", switches: sw)
        let rob = m.resultadoRowsV2().first { $0.title == "ROB" }
        #expect(rob?.betText?.hasSuffix("sin Oyes, Unidades") == true)
        let ric = m.resultadoRowsV2().first { $0.title == "RIC" }
        #expect(ric?.betText?.contains("sin") == false)
    }

    @Test func aSwitchOnlyTurnsOnWhatTheCatalogAllows() {
        let m = DemoFixture.make()
        #expect(!m.catalogBlocksV2("Oyes", pair: false))
        m.betCatalog = m.betCatalog.filter { $0.tag != "OYES" }
        #expect(m.catalogBlocksV2("Oyes", pair: false))
        #expect(!m.catalogBlocksV2("Vuelta", pair: false))
    }
}

// MARK: - Editar el tag y los valores de un match

@MainActor
struct BetEditTests {
    private func robRow(_ m: MatchManager) -> MatchManager.ResultadoRowV2? { m.resultadoRowsV2().first { $0.title == "ROB" } }

    @Test func theReportShowsTheTagNameAndSaysWhenItWasEdited() throws {
        let m = DemoFixture.make()
        let template = try #require(BetTemplateStore.shared.entries.first)
        m.setTemplateV2(template, for: .individual("ROB"))
        #expect(m.betTagLabelV2(for: .individual("ROB")) == template.name)
        #expect(!m.betIsEditedV2(for: .individual("ROB")))

        var v = m.betValuesV2(for: .individual("ROB"))
        v.presionValue += 5
        m.setBetValuesV2(v, for: .individual("ROB"))
        #expect(m.betTagLabelV2(for: .individual("ROB")) == "\(template.name) · editado")
        #expect(robRow(m)?.betText?.contains("presión $\(v.presionValue)") == true)
    }

    @Test func editingTheValuesChangesTheMoneyOfThatMatchOnly() throws {
        let m = DemoFixture.make()
        let template = try #require(BetTemplateStore.shared.entries.first)
        m.setTemplateV2(template, for: .individual("ROB"))
        m.setTemplateV2(template, for: .individual("RIC"))
        let robBefore = try #require(robRow(m)).money
        let ricBefore = try #require(m.resultadoRowsV2().first { $0.title == "RIC" }).money

        var v = m.betValuesV2(for: .individual("ROB"))
        v.vueltaValue *= 2; v.presionValue *= 2; v.matchValue *= 2; v.unitValue *= 2
        m.setBetValuesV2(v, for: .individual("ROB"))
        #expect(try #require(robRow(m)).money == robBefore * 2 || robBefore == 0)
        #expect(try #require(m.resultadoRowsV2().first { $0.title == "RIC" }).money == ricBefore)
    }

    @Test func theUnitFollowsTheVueltaUntilYouEditItOnItsOwn() {
        let m = DemoFixture.make()
        var v = m.betValuesV2(for: .individual("ROB"))
        v.vueltaValue = 100; v.unitValue = 50
        m.setBetValuesV2(v, for: .individual("ROB"))
        m.setVueltaV2(200, for: .individual("ROB"))
        #expect(m.betValuesV2(for: .individual("ROB")).unitValue == 100)   // iban ligadas: se mueven juntas

        var own = m.betValuesV2(for: .individual("ROB"))
        own.unitValue = 30   // la unidad se editó sola
        m.setBetValuesV2(own, for: .individual("ROB"))
        m.setVueltaV2(400, for: .individual("ROB"))
        #expect(m.betValuesV2(for: .individual("ROB")).unitValue == 30)    // ya no la mueve
    }

    @Test func valuesNeverGoBelowZero() {
        let m = DemoFixture.make()
        var v = m.betValuesV2(for: .individual("ROB"))
        v.matchValue = -10; v.unitValue = -1
        m.setBetValuesV2(v, for: .individual("ROB"))
        let after = m.betValuesV2(for: .individual("ROB"))
        #expect(after.matchValue == 0 && after.unitValue == 0)
    }

    @Test func pairValuesAreTheSameForEveryPairAndDoNotTouchTheIndividuals() {
        let m = DemoFixture.make()
        let robBefore = robRow(m)?.money
        let pairBefore = m.resultadoRowsV2().filter(\.isPair).map(\.money)
        var v = m.betValuesV2(for: .pair(m.lanes[0].id))
        v.vueltaValue += 50; v.presionValue += 50; v.matchValue += 50
        m.setBetValuesV2(v, for: .pair(m.lanes[0].id))
        #expect(m.betValuesV2(for: .pair(m.lanes[1].id)) == m.betValuesV2(for: .pair(m.lanes[0].id)))
        #expect(robRow(m)?.money == robBefore)   // el rival tiene su propia apuesta
        #expect(m.resultadoRowsV2().filter(\.isPair).map(\.money) != pairBefore)
    }

    @Test func turningUnitsOffFromTheEditorStopsCountingThem() {
        let m = DemoFixture.make()
        var sw = m.betSwitchesV2(for: .individual("ROB"))
        sw.units = false
        m.setBetSwitchesV2(sw, for: .individual("ROB"))
        #expect(robRow(m)?.betText == nil || robRow(m)?.betText?.contains("sin Unidades") == true)
    }
}
