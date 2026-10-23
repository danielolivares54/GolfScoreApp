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
