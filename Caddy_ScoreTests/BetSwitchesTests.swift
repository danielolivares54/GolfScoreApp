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

    @Test func readsTheRoundWithTheMoneyOfEveryMatch() throws {
        let m = DemoFixture.make()
        let text = m.roundReadbackV2()
        #expect(text.hasPrefix("Llevas 18 hoyos completos."))
        #expect(text.contains("contra Roberto"))
        #expect(text.contains("En total,"))
        // Primero el conteo de las apuestas y después el dinero (total, individuales y parejas).
        let counts = try! #require(text.range(of: "Por conteo."))
        let money = try! #require(text.range(of: "Dinero."))
        #expect(counts.lowerBound < money.lowerBound)
        let total = try! #require(text.range(of: "En total,"))
        let individuals = try! #require(text.range(of: "Individuales,"))
        let pairs = try! #require(text.range(of: "Parejas,"))
        #expect(money.lowerBound < total.lowerBound && total.lowerBound < individuals.lowerBound && individuals.lowerBound < pairs.lowerBound)
        let robMoney = m.resultadoRowsV2().first { $0.title == "ROB" }!.money
        #expect(text.contains(robMoney >= 0 ? "ganando \(robMoney) pesos" : "perdiendo \(-robMoney) pesos") || robMoney == 0)
    }
}

// MARK: - Preguntas sobre lo anotado ("¿qué hizo Roberto en el 5?")

@MainActor
struct CardQuestionsTests {
    private func slang() -> VoiceSlangStore { VoiceSlangStore(defaults: UserDefaults(suiteName: "q-\(UUID().uuidString)")!) }
    private func ask(_ m: MatchManager, _ kind: String, _ who: String? = nil, hole: Int? = nil, current: Int = 14) -> String {
        VoiceHolePipeline.answer(.init(tipo: kind, jugador: who, hoyo: hole), match: m, currentHole: current, slang: slang(), detail: true)
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
        let b9 = VoiceHolePipeline.answer(.init(tipo: "nueve", jugador: "Roberto", segmento: "B9"), match: m, currentHole: 14, slang: slang(), detail: true)
        #expect(b9.contains("B9: ") && !b9.contains("F9: "))
        let pres = VoiceHolePipeline.answer(.init(tipo: "presiones", jugador: "Roberto", segmento: "B9"), match: m, currentHole: 14, slang: slang(), detail: true)
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

// MARK: - Cómo quedó un hoyo contra el rival, vuelta/presión/match y el porqué del acumulado

@MainActor
struct CardResultsTests {
    private func slang() -> VoiceSlangStore { VoiceSlangStore(defaults: UserDefaults(suiteName: "res-\(UUID().uuidString)")!) }
    private func ask(_ m: MatchManager, _ q: ReadbackQueryV2, current: Int = 14) -> String {
        VoiceHolePipeline.answer(q, match: m, currentHole: current, slang: slang(), detail: true)
    }
    private func signed(_ n: Int) -> String { m_countWords(n) }
    private func m_countWords(_ n: Int) -> String { n > 0 ? "\(n) arriba" : n < 0 ? "\(-n) abajo" : "parejos" }

    @Test func aHoleAgainstARivalSaysWhoShotWhatStrokesResultAndBeforeAfter() throws {
        let m = DemoFixture.make()
        let hole = 8
        let rows = m.individualZoomRows(opponentAlias: "ROB", segmentOverride: "F9")
        let i = try #require(rows.firstIndex { $0.hole == hole })
        let r = rows[i]
        let text = ask(m, .init(tipo: "hoyo", jugador: "Daniel", oponente: "Roberto", hoyo: hole))
        #expect(text.hasPrefix("Daniel contra Roberto."))
        #expect(text.contains("Daniel tiró \(r.yoGross) y Roberto \(r.oppGross)"))
        // Quién lleva stroke en ese hoyo.
        if r.yoStrokes > 0 { #expect(text.contains("Daniel recibe")) }
        else if r.oppStrokes > 0 { #expect(text.contains("Roberto recibe")) }
        else { #expect(text.contains("Sin strokes en este hoyo")) }
        // Ganó, perdió o empataron.
        #expect(text.contains(r.result > 0 ? "Gana Daniel" : r.result < 0 ? "Pierde Daniel" : "Empatan"))
        // Cuánto iba antes y cómo queda.
        let before = i > 0 ? rows[i - 1].vueltaAccum : 0
        #expect(text.contains("Vuelta F9: antes \(m_countWords(before)), ahora \(m_countWords(r.vueltaAccum))"))
        #expect(text.contains("Presiones abiertas: antes \(i > 0 ? rows[i - 1].openPressures.count : 0), ahora \(r.openPressures.count)"))
    }

    @Test func fromTheRivalsSideEverythingFlips() throws {
        let m = DemoFixture.make()
        let r = try #require(m.individualZoomRows(opponentAlias: "ROB", segmentOverride: "F9").first { $0.hole == 8 })
        let text = ask(m, .init(tipo: "hoyo", jugador: "Roberto", oponente: "Daniel", hoyo: 8))
        #expect(text.contains("Roberto tiró \(r.oppGross) y Daniel \(r.yoGross)"))
        #expect(text.contains(r.result > 0 ? "Pierde Roberto" : r.result < 0 ? "Gana Roberto" : "Empatan"))
    }

    @Test func noOpponentMeansEveryMatchOfThePlayerIncludingPairs() {
        let m = DemoFixture.make()
        let text = ask(m, .init(tipo: "hoyo", jugador: "yo", hoyo: 8))
        for name in ["Roberto", "Fernando", "Ricardo", "Anselmo"] { #expect(text.contains("Daniel contra \(name).")) }
        #expect(text.contains("Pareja "))
        #expect(text.contains("tiraron"))
    }

    @Test func aGroupOfHolesIsCompactAndSaysWhereTheVueltaStands() {
        let m = DemoFixture.make()
        let text = ask(m, .init(tipo: "hoyo", jugador: "yo", oponente: "Roberto", hoyo: 5, hasta: 8))
        #expect(text.contains("hoyo 5,") && text.contains("hoyo 8,"))
        #expect(text.contains("Vuelta F9 ahora"))
        #expect(!text.contains("Presiones abiertas: antes"))   // el grupo no repite el antes/después de cada hoyo
    }

    @Test func aHoleWithoutScoresSaysSo() {
        let m = DemoFixture.make()
        for i in m.players.indices { m.players[i].scores[8] = nil }
        #expect(ask(m, .init(tipo: "hoyo", jugador: "yo", oponente: "Roberto", hoyo: 8)).contains("todavía no hay scores de los dos"))
    }

    @Test func vueltaPresionAndMatchAnswerWithTheirCount() {
        let m = DemoFixture.make()
        let rob = m.resultadoRowsV2().first { $0.title == "ROB" }!
        let vuelta = ask(m, .init(tipo: "vuelta", jugador: "yo", oponente: "Roberto"))
        #expect(vuelta.contains("vuelta F9 \(m_countWords(rob.f9Net)), vuelta B9 \(m_countWords(rob.b9Net))"))
        #expect(vuelta.contains("Cada vuelta vale"))
        let presion = ask(m, .init(tipo: "presion", jugador: "yo", oponente: "Roberto"))
        #expect(presion.contains("Cada presión vale") && presion.contains("B9,"))
        let match = ask(m, .init(tipo: "match", jugador: "yo", oponente: "Roberto"))
        #expect(match.contains("match \(m_countWords(rob.f9Net + rob.b9Net))") && match.contains("ya se cobra"))
        // Una apuesta apagada se dice.
        var sw = m.betSwitchesV2(for: .individual("ROB")); sw.presion = false
        m.setBetSwitchesV2(sw, for: .individual("ROB"))
        #expect(ask(m, .init(tipo: "presion", jugador: "yo", oponente: "Roberto")).contains("apagada en este match"))
    }

    @Test func explainingAMatchBreaksDownHolesCountsAndMoney() {
        let m = DemoFixture.make()
        let rob = m.resultadoRowsV2().first { $0.title == "ROB" }!
        let text = ask(m, .init(tipo: "explicar", jugador: "yo", oponente: "Roberto"))
        #expect(text.hasPrefix("Contra Roberto, "))
        #expect(text.contains(rob.money >= 0 ? "ganando \(rob.money) pesos" : "perdiendo \(-rob.money) pesos") || rob.money == 0)
        for part in ["F9: ", "B9: ", "Match: ", "Unidades: ", "Strokes: Daniel recibe 8"] { #expect(text.contains(part)) }
        #expect(text.contains("ganaste") || text.contains("perdiste") || text.contains("empataron"))
        // Sin decir de quién: todos los matches y el total.
        let all = ask(m, .init(tipo: "explicar"))
        #expect(all.contains("Contra Ricardo") && all.contains("Pareja ") && all.contains("En total,"))
    }

    @Test func unknownQuestionsListWhatCanBeAnswered() {
        let m = DemoFixture.make()
        #expect(ask(m, .init(tipo: "otro")).hasPrefix("No sé responder eso todavía."))
    }
}

// MARK: - Aprender: ayuda a la transcripción, frases de unidades y ejemplos del usuario

@MainActor
struct VoiceLearningTests {
    private func slang() -> VoiceSlangStore { VoiceSlangStore(defaults: UserDefaults(suiteName: "learn-\(UUID().uuidString)")!) }
    private func tempRecords() -> VoiceRecordStore {
        VoiceRecordStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("learn-\(UUID().uuidString)"))
    }

    @Test func theTranscriptionPromptCarriesNamesUnitsAndLearnedSlang() {
        let m = DemoFixture.make()
        m.betCatalog.append(BetDefinition(tag: "SAND", name: "Sandy par", type: .individual, mode: .manual, units: 1, description: ""))
        let s = slang()
        s.learn("el chino", as: "ROB")
        let prompt = VoiceHolePipeline.transcriptionPrompt(match: m, slang: s)
        #expect(prompt.contains("Dictado de golf en español de México"))
        #expect(prompt.contains("Sandy par") && prompt.contains("Hole Out") && prompt.contains("tripoteó"))
        #expect(prompt.contains("el chino"))
        for name in ["Daniel (DAN)", "Roberto (ROB)", "Anselmo (ANS)"] { #expect(prompt.contains(name)) }
        // Los jugadores van al final: es lo que más pesa en la transcripción.
        #expect(prompt.hasSuffix(")."))
    }

    @Test func aTaughtUnitPhraseIsResolvedByItselfNextTime() async throws {
        let m = DemoFixture.make()
        let s = slang(), r = tempRecords()
        let extraction = VoiceHoleExtraction(hoyo: 14, scores: [.init(jugador: "ROB", gross: 6, putts: 3)],
                                             unidades: [.init(jugador: "ROB", codigo: "tripoteó", cantidad: nil)])
        var d = try await VoiceHolePipeline.propose(transcript: "hoyo 14 Rob seis y tripoteó", match: m, defaultHole: 14, slang: s, records: r,
                                                    extractor: { _, _ in extraction })
        #expect(d.units.isEmpty)
        #expect(d.unknownUnits == [.init(alias: "ROB", spoken: "tripoteó", units: 1)])
        #expect(!VoiceHolePipeline.canApply(d, match: m))

        d = VoiceHolePipeline.assignUnit(d, spoken: "tripoteó", to: "3P", slang: s)
        #expect(d.units == [.init(alias: "ROB", code: "3P", units: 1)])
        #expect(d.unknownUnits.isEmpty && d.doubts.isEmpty)
        #expect(VoiceHolePipeline.canApply(d, match: m))
        #expect(s.target(for: "Tripoteó") == "3P")

        // La siguiente vez, sin preguntar.
        let next = try await VoiceHolePipeline.propose(transcript: "ric tripoteó", match: m, defaultHole: 14, slang: s, records: r,
                                                       extractor: { _, _ in .init(unidades: [.init(jugador: "RIC", codigo: "tripoteó", cantidad: nil)]) })
        #expect(next.units == [.init(alias: "RIC", code: "3P", units: 1)])
        #expect(next.unknownUnits.isEmpty)
    }

    @Test func examplesPutTheHardHolesFirstAndSkipTheUnresolved() {
        let r = tempRecords()
        // Un hoyo que costó dos dictadas.
        let a = r.record(audio: nil, transcript: "rob cuatro y el chino cinco", roundId: "R1", hole: 5)
        let b = r.record(audio: nil, transcript: "el chino es rob, cinco", roundId: "R1", hole: 5)
        r.resolve(ids: [a, b], finalCard: "H5 ROB 5")
        // Uno que salió a la primera, más reciente.
        let c = r.record(audio: nil, transcript: "yo tres", roundId: "R1", hole: 6)
        r.resolve(ids: [c], finalCard: "H6 DAN 3")
        // Uno sin resolver: no es ejemplo.
        _ = r.record(audio: nil, transcript: "ruido", roundId: "R1", hole: 7)

        let ex = r.examples(limit: 5)
        #expect(ex.count == 2)
        #expect((ex[0]["dijo"] as? [String])?.count == 2)    // el difícil primero
        #expect(ex[0]["quedo"] as? String == "H5 ROB 5")
        #expect(r.examples(limit: 1).count == 1)

        let st = r.stats()
        #expect(st.dictations == 4 && st.resolvedHoles == 2 && st.firstTry == 1)
    }

    @Test func theContextSentToTheModelIncludesSlangAndExamples() {
        let m = DemoFixture.make()
        let s = slang(), r = tempRecords()
        s.learn("el chino", as: "ROB")
        let id = r.record(audio: nil, transcript: "el chino cinco", roundId: "R1", hole: 5)
        r.resolve(ids: [id], finalCard: "H5 ROB 5")
        let ctx = VoiceHolePipeline.context(match: m, hole: 5, slang: s, records: r)
        #expect((ctx["apodos"] as? [String: String])?["el chino"] == "ROB")
        #expect((ctx["ejemplos"] as? [[String: Any]])?.count == 1)
    }
}

// MARK: - Por qué las parejas no cuentan

@MainActor
struct PairsNoticeTests {
    @Test func whenEverythingIsFineThereIsNoNotice() {
        let m = DemoFixture.make()
        #expect(m.pairsNoticeV2() == nil)
        #expect(m.pairsNoticeV2(hole: 14) == nil)
        #expect(!m.resultadoRowsV2().filter(\.isPair).isEmpty)
    }

    @Test func definedPairsAlwaysCountEvenIfTheCatalogLacksMatchParejas() {
        let m = DemoFixture.make()
        m.betCatalog = m.betCatalog.filter { $0.tag != "PAIR" }
        #expect(m.pairsNoticeV2() == nil)
        #expect(m.resultadoRowsV2().filter(\.isPair).count == 3)
        #expect(!m.moneyReadbackV2().contains("Ojo"))
    }

    @Test func noBaseTeamMeansNotDefined() {
        let m = DemoFixture.make()
        m.baseTeamAliases = []
        m.lanes = []
        #expect(m.pairsNoticeV2() == .notDefined)
        #expect(m.pairsNoticeTextV2(.notDefined).contains("Defínela en el Setup"))
    }

    @Test func aMissingScoreOfTheFourSaysWho() {
        let m = DemoFixture.make()
        let involved = Set(m.lanes.flatMap { $0.base + $0.opp })
        let who = involved.first { $0 != "DAN" }!
        m.players[m.players.firstIndex { $0.alias == who }!].scores[14] = nil
        guard case .missingScores(let aliases, let hole)? = m.pairsNoticeV2(hole: 14) else { Issue.record("sin aviso"); return }
        #expect(aliases == [who] && hole == 14)
        #expect(m.pairsNoticeTextV2(.missingScores(aliases: aliases, hole: hole)).contains("cuatro jugadores"))
    }

    @Test func fewerThanFourPlayersNeverNagAboutPairs() {
        let m = DemoFixture.make()
        m.setPlayers(names: ["Daniel", "Beto", "Chuy"], preserveScores: false)
        #expect(m.pairsNoticeV2() == nil)
    }
}

// MARK: - Contrastar la tarjeta de un jugador por vuelta, y respuestas breves (con "más detalle" a pedido)

@MainActor
struct ContrastAndBriefTests {
    private func slang() -> VoiceSlangStore { VoiceSlangStore(defaults: UserDefaults(suiteName: "brief-\(UUID().uuidString)")!) }
    private func brief(_ m: MatchManager, _ q: ReadbackQueryV2) -> String {
        VoiceHolePipeline.answer(q, match: m, currentHole: 14, slang: slang())
    }
    private func full(_ m: MatchManager, _ q: ReadbackQueryV2) -> String {
        VoiceHolePipeline.answer(q, match: m, currentHole: 14, slang: slang(), detail: true)
    }

    // Tarjeta de un jugador

    @Test func aPlayersNineHoleByHoleMatchesTheCard() {
        let m = DemoFixture.make()
        let lines = m.playerHolesV2(alias: "DAN", holes: m.holesForNineV2("F9"))
        #expect(lines.count == 9)
        #expect(lines.map(\.hole) == Array(1...9))
        #expect(lines.map(\.gross) == (1...9).map { Optional(m.getScore(hole: $0, player: "DAN")) })
        // Daniel recibe de Roberto: sus strokes salen con quién se los da.
        let withStroke = lines.filter { !$0.strokes.isEmpty }
        #expect(!withStroke.isEmpty)
        #expect(withStroke.allSatisfy { $0.strokes.contains { $0.from == "ROB" } })
        // Roberto no recibe de Daniel.
        #expect(m.playerHolesV2(alias: "ROB", holes: Array(1...9)).allSatisfy { $0.strokes.isEmpty })
    }

    @Test func theDetailedReadingGivesEveryHoleAndTheTotals() {
        let m = DemoFixture.make()
        let text = m.playerCardReadbackV2(alias: "DAN", holes: m.holesForNineV2("F9"), label: "F9", detail: true)
        let sum = (1...9).reduce(0) { $0 + m.getScore(hole: $1, player: "DAN") }
        #expect(text.hasPrefix("Daniel, F9."))
        #expect(text.contains("Hoyo 1, par 4: \(m.getScore(hole: 1, player: "DAN")) golpes"))
        #expect(text.contains("Total F9: \(sum) golpes en 9 hoyos"))
        #expect(text.contains("recibe") && text.contains("de Roberto"))
    }

    @Test func theBriefReadingIsOneLineWithTheStrokeHoles() {
        let m = DemoFixture.make()
        let text = brief(m, .init(tipo: "tarjeta", jugador: "Daniel", segmento: "F9"))
        let row = (1...9).map { String(m.getScore(hole: $0, player: "DAN")) }.joined(separator: ", ")
        #expect(text.hasPrefix("Daniel, F9: \(row)."))
        #expect(text.contains("Total ") && text.contains("Recibe stroke en los hoyos"))
        #expect(!text.contains("Hoyo 1, par"))
        // Sin jugador es yo; un grupo de hoyos con detalle, y "más detalle" lo da completo.
        #expect(brief(m, .init(tipo: "tarjeta", segmento: "B9")).hasPrefix("Daniel, B9:"))
        #expect(full(m, .init(tipo: "tarjeta", jugador: "Daniel", segmento: "F9")).contains("Hoyo 1, par 4"))
        let range = brief(m, .init(tipo: "tarjeta", jugador: "Daniel", hoyo: 3, hasta: 5))
        #expect(range.hasPrefix("Daniel, hoyos 3 al 5: \(m.getScore(hole: 3, player: "DAN")), "))
        #expect(full(m, .init(tipo: "tarjeta", jugador: "Daniel", hoyo: 3, hasta: 5)).contains("Hoyo 3, par"))
        #expect(brief(m, .init(tipo: "tarjeta", jugador: "Daniel", hoyo: 3)).contains("Hoyo 3, par"))   // un solo hoyo: completo
    }

    // Respuestas breves

    @Test func briefAnswersAreShorterAndLeaveOutTheDetail() {
        let m = DemoFixture.make()
        let hole = brief(m, .init(tipo: "otro"))
        #expect(hole.hasPrefix("No sé responder"))

        let money = m.moneyReadbackV2(detail: false), moneyFull = m.moneyReadbackV2(detail: true)
        #expect(money.count < moneyFull.count)
        #expect(money.contains("En total,") && money.contains("Individuales,") && !money.contains("contra Roberto"))

        let round = m.roundReadbackV2(detail: false), roundFull = m.roundReadbackV2(detail: true)
        #expect(round.count < roundFull.count)
        #expect(round.contains("Por conteo.") && round.contains("Dinero."))

        let explain = brief(m, .init(tipo: "explicar", jugador: "yo", oponente: "Roberto"))
        let explainFull = full(m, .init(tipo: "explicar", jugador: "yo", oponente: "Roberto"))
        #expect(explain.count < explainFull.count)
        #expect(explain.hasPrefix("Contra Roberto, ") && explain.contains("F9 ") && !explain.contains("Strokes:"))

        let nine = brief(m, .init(tipo: "nueve", jugador: "yo", oponente: "Roberto"))
        #expect(nine.contains("F9: ") && nine.contains("Dinero:") && !nine.contains("Strokes:") && !nine.contains("presion"))
        #expect(full(m, .init(tipo: "nueve", jugador: "yo", oponente: "Roberto")).contains("Strokes:"))
    }

    @Test func aHoleAgainstARivalIsOneLineUntilYouAskForMore() throws {
        let m = DemoFixture.make()
        let r = try #require(m.individualZoomRows(opponentAlias: "ROB", segmentOverride: "F9").first { $0.hole == 8 })
        let short = brief(m, .init(tipo: "hoyo", jugador: "Daniel", oponente: "Roberto", hoyo: 8))
        #expect(short.contains("Hoyo 8: \(r.yoGross) contra \(r.oppGross)"))
        #expect(short.contains("Vuelta F9 ahora") && !short.contains("Presiones abiertas") && !short.contains("recibe"))
        let long = full(m, .init(tipo: "hoyo", jugador: "Daniel", oponente: "Roberto", hoyo: 8))
        #expect(long.contains("Presiones abiertas: antes") && long.count > short.count)
    }

    @Test func theHoleReadingIsShortByDefault() {
        let m = DemoFixture.make()
        m.upsertUnitEvent(hole: 14, alias: "DAN", code: "HO", units: 1)
        let short = m.holeReadbackV2(14, detail: false).text, long = m.holeReadbackV2(14, detail: true).text
        #expect(short.count < long.count)
        #expect(!short.contains("hole out") && long.contains("hole out"))
        #expect(short.hasPrefix("Hoyo 14, par 3."))
    }

    @Test func askingForTheDetailIsRecognized() {
        #expect(ReadbackIntentV2.asksForDetail("qué llevo con detalle"))
        #expect(ReadbackIntentV2.asksForDetail("léeme el hoyo por hoyo"))
        #expect(ReadbackIntentV2.asksForDetail("explícame cómo voy"))
        #expect(!ReadbackIntentV2.asksForDetail("qué llevo"))
        // El LLM lo marca con `detalle` y entonces la respuesta ya sale completa.
        let m = DemoFixture.make()
        let q = ReadbackQueryV2(tipo: "tarjeta", jugador: "Daniel", segmento: "F9", detalle: true)
        #expect(VoiceHolePipeline.answer(q, match: m, currentHole: 14, slang: slang()).contains("Hoyo 1, par 4"))
    }
}
