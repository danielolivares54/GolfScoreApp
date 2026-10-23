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

// MARK: - El apuntador lee lo anotado

@MainActor
struct CardReadbackTests {
    @Test func spokenRequestsAreRecognized() {
        #expect(ReadbackIntentV2.detect("¿Qué llevo?") == .hole)
        #expect(ReadbackIntentV2.detect("léeme el hoyo") == .hole)
        #expect(ReadbackIntentV2.detect("Cómo vamos") == .round)
        #expect(ReadbackIntentV2.detect("cuánto llevo en la ronda") == .round)
        #expect(ReadbackIntentV2.detect("qué falta") == .missing)
        #expect(ReadbackIntentV2.detect("yo tres, rob cuatro") == nil)   // un dato del hoyo no es una petición
        #expect(ReadbackIntentV2.detect("hoyo 5 daniel cuatro") == nil)
    }

    @Test func readsAFullHoleWithNamesPuttsOyesUnitsAndNotes() {
        let m = DemoFixture.make()
        let hole = 14   // par 3 con oyes en el caso de estudio
        m.upsertUnitEvent(hole: hole, alias: "DAN", code: "HO", units: 1)
        m.upsertUnitEvent(hole: hole, alias: "ROB", code: "NOTA", units: 0, note: "bola al agua")
        let text = m.holeReadbackV2(hole).text
        #expect(text.hasPrefix("Hoyo 14, par 3."))
        for name in ["Daniel", "Fernando", "Roberto", "Ricardo", "Anselmo"] { #expect(text.contains(name)) }
        #expect(text.contains("Oyes:"))
        #expect(text.contains("Daniel: hole out."))
        #expect(text.contains("Nota de Roberto: bola al agua."))
    }

    @Test func saysWhatIsMissing() {
        let m = DemoFixture.make()
        for alias in ["FER", "ANS"] { m.players[m.players.firstIndex { $0.alias == alias }!].scores[14] = nil }
        let r = m.holeReadbackV2(14)
        #expect(r.text.contains("Falta el score de Fernando y Anselmo"))
        #expect(r.missing.first == "el score de Fernando y Anselmo")
        #expect(m.readbackV2(.missing, hole: 14).hasPrefix("En el hoyo 14 falta el score de Fernando y Anselmo"))
    }

    @Test func anEmptyHoleSaysSo() {
        let m = DemoFixture.make()
        for i in m.players.indices { m.players[i].scores[14] = nil }
        #expect(m.holeReadbackV2(14).text == "El hoyo 14 todavía no tiene nada anotado.")
    }

    @Test func aPickedUpHoleIsReadAsLost() {
        let m = DemoFixture.make()
        m.setCellOverride(alias: "ROB", hole: 3, override: .lostHole)
        #expect(m.holeReadbackV2(3).text.contains("Roberto") && m.holeReadbackV2(3).text.contains("se levantó, hoyo perdido"))
    }

    @Test func readsTheRoundWithTheMoneyOfEveryMatch() {
        let m = DemoFixture.make()
        let text = m.roundReadbackV2()
        #expect(text.hasPrefix("Llevas 18 hoyos completos."))
        #expect(text.contains("Contra Roberto"))
        #expect(text.contains("En total,"))
        let robMoney = m.resultadoRowsV2().first { $0.title == "ROB" }!.money
        #expect(text.contains(robMoney >= 0 ? "ganando \(robMoney) pesos" : "perdiendo \(-robMoney) pesos") || robMoney == 0)
    }
}

// MARK: - Preguntas sobre lo anotado ("¿qué hizo Roberto en el 5?")

@MainActor
struct CardQuestionsTests {
    private func slang() -> VoiceSlangStore { VoiceSlangStore(defaults: UserDefaults(suiteName: "q-\(UUID().uuidString)")!) }
    private func ask(_ m: MatchManager, _ kind: String, _ who: String? = nil, hole: Int? = nil, current: Int = 14) -> String {
        VoiceHolePipeline.answer(.init(tipo: kind, jugador: who, hoyo: hole), match: m, currentHole: current, slang: slang())
    }

    @Test func whatSomeoneShotOnAHole() {
        let m = DemoFixture.make()
        let gross = m.getScore(hole: 3, player: "ROB")
        let text = ask(m, "score", "Roberto", hole: 3)
        #expect(text.hasPrefix("Roberto hizo \(gross) en el hoyo 3, "))
        // Sin decir de quién: lee el hoyo completo.
        #expect(ask(m, "score", nil, hole: 3).hasPrefix("Hoyo 3, par 3."))
        // Un hoyo sin score lo dice.
        for i in m.players.indices { m.players[i].scores[3] = nil }
        #expect(ask(m, "score", "Roberto", hole: 3) == "Roberto no tiene score en el hoyo 3.")
    }

    @Test func totalsAndPutts() {
        let m = DemoFixture.make()
        let sum = (1...18).reduce(0) { $0 + m.getScore(hole: $1, player: "DAN") }
        #expect(ask(m, "total", "DAN").hasPrefix("Daniel lleva \(sum) golpes en 18 hoyos"))
        m.applyHoleEntry(HoleEntryData(hole_number: 5, player_alias: "DAN", strokes: m.getScore(hole: 5, player: "DAN"), putts: 3, units: nil, tags: nil))
        #expect(ask(m, "putts", "DAN", hole: 5) == "Daniel hizo 3 putts en el hoyo 5.")
        #expect(ask(m, "putts", "DAN").contains("putts en"))
    }

    @Test func whichOyesWasWon() {
        let m = DemoFixture.make()
        let par3 = (1...18).filter { m.getHole($0)?.par == 3 && !(m.oyesRanksByHole[$0] ?? [:]).isEmpty }
        let winners = Dictionary(grouping: par3, by: { h in m.oyesRanksByHole[h]!.first { $0.value == 1 }!.key })
        #expect(!winners.isEmpty)
        for (alias, holes) in winners {
            let text = ask(m, "oyes", alias)
            #expect(text.contains("ganó el oyes en"))
            for h in holes { #expect(text.contains(String(h))) }
        }
        let nobody = m.players.map(\.alias).first { winners[$0] == nil }
        if let nobody { #expect(ask(m, "oyes", nobody).contains("no ha ganado ningún oyes")) }
        #expect(ask(m, "oyes").hasPrefix("Oyes ganados:"))
        #expect(ask(m, "oyes", nil, hole: 14).hasPrefix("Oyes del hoyo 14: primero"))
    }

    @Test func whereAndWhichUnits() {
        let m = DemoFixture.make()
        m.betCatalog.append(BetDefinition(tag: "SAND", name: "Sandy par", type: .individual, mode: .manual, units: 1, description: ""))
        m.upsertUnitEvent(hole: 4, alias: "ANS", code: "SAND", units: 1)
        m.upsertUnitEvent(hole: 14, alias: "ANS", code: "HO", units: 1)
        m.upsertUnitEvent(hole: 14, alias: "ROB", code: "NOTA", units: 0, note: "no cuenta")
        #expect(ask(m, "unidades", "Anselmo") == "Anselmo hizo unidades: Sandy par en el hoyo 4 y hole out en el hoyo 14.")
        #expect(ask(m, "unidades", "Ricardo") == "Ricardo no tiene unidades anotadas.")
        #expect(ask(m, "unidades", nil, hole: 14).contains("Anselmo, hole out"))
        #expect(ask(m, "unidades").contains("Anselmo: Sandy par en el hoyo 4"))
    }

    @Test func ninesPressuresAndStrokesOfAMatch() {
        let m = DemoFixture.make()
        let rob = m.resultadoRowsV2().first { $0.title == "ROB" }!
        let text = ask(m, "nueve", "Roberto")
        #expect(text.hasPrefix("Contra Roberto. F9: "))
        #expect(text.contains("B9: "))
        #expect(text.contains("Strokes: Daniel recibe 8"))
        // Las presiones abiertas de B9 salen de lo mismo que Resultados.
        let open = rob.b9Presiones.count
        #expect(text.contains(open == 0 ? "sin presiones abiertas" : "\(open) presion"))
        // Solo B9 / solo presiones / solo strokes.
        let b9 = VoiceHolePipeline.answer(.init(tipo: "nueve", jugador: "Roberto", segmento: "B9"), match: m, currentHole: 14, slang: slang())
        #expect(b9.contains("B9: ") && !b9.contains("F9: "))
        let pres = VoiceHolePipeline.answer(.init(tipo: "presiones", jugador: "Roberto", segmento: "B9"), match: m, currentHole: 14, slang: slang())
        #expect(!pres.contains("Strokes") && pres.contains("B9: "))
        let st = ask(m, "strokes", "Roberto")
        #expect(st.contains("Strokes: Daniel recibe 8") && !st.contains("F9:") && !st.contains("B9:"))
    }

    @Test func allMatchesWhenNobodyIsNamedAndTheActiveRefreshIsSaid() {
        let m = DemoFixture.make()
        let text = ask(m, "nueve")
        #expect(text.contains("Contra Roberto") && text.contains("Contra Ricardo") && text.contains("Pareja"))
        let robRefresh = m.refreshStateV2(for: .individual("ROB"))
        if robRefresh.carryActive { #expect(ask(m, "nueve", "Roberto").contains("Carry activo")) }
        if robRefresh.doublePressActive { #expect(ask(m, "strokes", "Roberto").contains("Doble B9 activo")) }
    }

    @Test func notesAndUnknownPlayers() {
        let m = DemoFixture.make()
        m.upsertUnitEvent(hole: 14, alias: "ROB", code: "NOTA", units: 0, note: "bola al agua")
        #expect(ask(m, "notas") == "hoyo 14, Roberto: bola al agua.")
        #expect(ask(m, "score", "Pelón", hole: 3) == "No encontré a \"Pelón\" entre los jugadores.")
    }

    @Test func meMeansTheUserNameInQuestionsToo() {
        let m = DemoFixture.make()
        let saved = VoiceHolePipeline.userName
        defer { VoiceHolePipeline.userName = saved }
        VoiceHolePipeline.userName = { "Roberto" }
        #expect(ask(m, "score", "yo", hole: 3).hasPrefix("Roberto hizo"))
    }

    @Test func aQuestionIsNotWrittenToTheCard() async throws {
        let m = DemoFixture.make()
        let before = m.getScore(hole: 5, player: "ROB")
        let e = VoiceHoleExtraction(consulta: .init(tipo: "score", jugador: "Roberto", hoyo: 5))
        await #expect(throws: VoiceHoleError.query(.init(tipo: "score", jugador: "Roberto", hoyo: 5))) {
            _ = try await VoiceHolePipeline.propose(transcript: "qué hizo Roberto en el 5", match: m, defaultHole: 5,
                                                    slang: slang(), extractor: { _, _ in e })
        }
        #expect(m.getScore(hole: 5, player: "ROB") == before)
    }

    @Test func aQuestionDecodesFromTheModelJSON() throws {
        let json = #"{"hoyo":null,"scores":[],"consulta":{"tipo":"unidades","jugador":"Ricardo","hoyo":null}}"#
        let e = try JSONDecoder().decode(VoiceHoleExtraction.self, from: Data(json.utf8))
        #expect(e.consulta == .init(tipo: "unidades", jugador: "Ricardo", hoyo: nil))
        let none = try JSONDecoder().decode(VoiceHoleExtraction.self, from: Data(#"{"scores":[],"consulta":null}"#.utf8))
        #expect(none.consulta == nil)
    }
}
