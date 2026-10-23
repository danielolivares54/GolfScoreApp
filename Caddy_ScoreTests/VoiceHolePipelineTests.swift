//
//  VoiceHolePipelineTests.swift
//  Caddy_ScoreTests
//
//  v2t: el dictado integral del hoyo. Con el caso de estudio (DAN, FER, ROB, RIC, ANS; el hoyo 14 es par 3
//  con Oyes activo) y un extractor falso: sin red ni LLM. Los apodos y las grabaciones usan almacenes temporales.
//

import Testing
import Foundation
@testable import Caddy_Score

@MainActor
struct VoiceHolePipelineTests {

    /// Caso de estudio con el hoyo 14 vacío y una unidad dictable ("Sandy par") activa en el catálogo.
    private func setup() -> MatchManager {
        let m = DemoFixture.make()
        for i in m.players.indices { m.players[i].scores[14] = nil }
        m.oyesRanksByHole[14] = nil
        m.unitEventsByHole[14] = nil
        m.betCatalog.append(BetDefinition(tag: "SAND", name: "Sandy par", type: .individual, mode: .manual, units: 1, description: ""))
        return m
    }

    private func slang() -> VoiceSlangStore {
        VoiceSlangStore(defaults: UserDefaults(suiteName: "voice-tests-\(UUID().uuidString)")!)
    }

    private func extraction(hole: Int? = 14, scores: [(String, Int?, Int?)] = [], oyes: [(String, Int)] = [],
                            units: [(String, String)] = [], notes: [(String, String)] = []) -> VoiceHoleExtraction {
        VoiceHoleExtraction(
            hoyo: hole,
            scores: scores.map { .init(jugador: $0.0, gross: $0.1, putts: $0.2) },
            oyes: oyes.map { .init(jugador: $0.0, rank: $0.1) },
            unidades: units.map { .init(jugador: $0.0, codigo: $0.1, cantidad: nil) },
            notas: notes.map { .init(jugador: $0.0, texto: $0.1) })
    }

    private func sc(_ j: String, _ g: Int? = nil, _ p: Int? = nil, rel: String? = nil) -> VoiceHoleExtraction.Score {
        .init(jugador: j, gross: g, putts: p, relativo: rel)
    }
    private func extractor(_ e: VoiceHoleExtraction) -> VoiceHolePipeline.Extractor { { _, _ in e } }

    // MARK: Lo que falta

    @Test func threePlayersTwoOyesAndOneUnitSaysWhatIsMissing() async throws {
        let m = setup()
        let e = extraction(scores: [("DAN", 3, 2), ("ROB", 4, nil), ("RIC", 5, 2)],
                           oyes: [("ROB", 1), ("DAN", 2)], units: [("DAN", "SAND")])
        let draft = try await VoiceHolePipeline.propose(transcript: "hoyo 14 dan tres rob cuatro ric cinco oyes rob dan sandy dan",
                                                        match: m, defaultHole: 14, slang: slang(), extractor: extractor(e))
        let report = VoiceHolePipeline.report(draft, match: m)
        #expect(report.understood.contains("hoyo 14"))
        #expect(report.understood.contains("DAN 3 (2 putts)"))
        #expect(report.understood.contains { $0.hasPrefix("oyes 1° ROB, 2° DAN") })
        #expect(report.understood.contains("DAN Sandy par"))
        #expect(report.missing.contains("score de FER, ANS"))
        #expect(report.missing.contains("putts de ROB"))
        #expect(report.missing.contains("lugar de oyes de RIC"))
        #expect(!report.isComplete)
        #expect(report.message.contains("Falta:"))
    }

    @Test func aSecondDictationAddsWhatWasMissingUntilTheHoleIsComplete() async throws {
        let m = setup()
        let s = slang()
        var draft = try await VoiceHolePipeline.propose(
            transcript: "dan tres rob cuatro oyes primero rob", match: m, defaultHole: 14, slang: s,
            extractor: extractor(extraction(scores: [("DAN", 3, 2), ("ROB", 4, 2)], oyes: [("ROB", 1)])))
        draft = try await VoiceHolePipeline.propose(
            transcript: "fer cinco ric cinco ans cuatro, oyes segundo dan tercero fer cuarto ric quinto ans", match: m, draft: draft, defaultHole: 14, slang: s,
            extractor: extractor(extraction(hole: nil, scores: [("FER", 5, 2), ("RIC", 5, 2), ("ANS", 4, 2)],
                                            oyes: [("DAN", 2), ("FER", 3), ("RIC", 4), ("ANS", 5)])))
        let report = VoiceHolePipeline.report(draft, match: m)
        #expect(report.isComplete)
        #expect(report.message.hasSuffix("Está completo."))
        #expect(draft.hole == 14)
        #expect(draft.transcripts.count == 2)
    }

    @Test func theLatestDictationWinsOnTheSameCell() async throws {
        let m = setup()
        let s = slang()
        var draft = try await VoiceHolePipeline.propose(transcript: "a", match: m, defaultHole: 14, slang: s,
                                                        extractor: extractor(extraction(scores: [("DAN", 3, 2)])))
        draft = try await VoiceHolePipeline.propose(transcript: "corrige", match: m, draft: draft, defaultHole: 14, slang: s,
                                                    extractor: extractor(extraction(hole: nil, scores: [("DAN", 4, nil)])))
        #expect(draft.cells["DAN"]?.gross == 4)
        #expect(draft.cells["DAN"]?.putts == 2)   // los putts ya dictados se conservan
    }

    @Test func putts_alone_fillTheCell() async throws {
        let m = setup()
        let s = slang()
        var draft = try await VoiceHolePipeline.propose(transcript: "a", match: m, defaultHole: 14, slang: s,
                                                        extractor: extractor(extraction(scores: [("ROB", 4, nil)])))
        draft = try await VoiceHolePipeline.propose(transcript: "rob dos putts", match: m, draft: draft, defaultHole: 14, slang: s,
                                                    extractor: extractor(extraction(hole: nil, scores: [("ROB", nil, 2)])))
        #expect(draft.cells["ROB"] == .init(gross: 4, putts: 2))
    }

    @Test func nothingHeardLeavesTheDraftAlone() async {
        let m = setup()
        await #expect(throws: VoiceHoleError.nothingHeard) {
            _ = try await VoiceHolePipeline.propose(transcript: "ruido", match: m, defaultHole: 14, slang: slang(),
                                                    extractor: extractor(VoiceHoleExtraction()))
        }
        await #expect(throws: VoiceHoleError.emptyTranscript) {
            _ = try await VoiceHolePipeline.propose(transcript: "  ", match: m, defaultHole: 14, slang: slang(),
                                                    extractor: extractor(VoiceHoleExtraction()))
        }
    }

    // MARK: Unidades, notas y alias

    @Test func anUnknownUnitIsADoubtAndNotApplied() async throws {
        let m = setup()
        let draft = try await VoiceHolePipeline.propose(
            transcript: "x", match: m, defaultHole: 14, slang: slang(),
            extractor: extractor(extraction(scores: [("DAN", 4, 2)], units: [("DAN", "chip raro")])))
        #expect(draft.units.isEmpty)
        #expect(VoiceHolePipeline.report(draft, match: m).doubts.contains { $0.contains("chip raro") })
        #expect(!VoiceHolePipeline.canApply(draft, match: m))
    }

    @Test func theHoleOnScreenIsUsedUnlessYouSayAnother() async throws {
        let m = setup()
        let e = extraction(hole: 3, scores: [("ROB", 4, nil)])   // el LLM inventó el hoyo 3: no lo dijeron
        let a = try await VoiceHolePipeline.propose(transcript: "rob cuatro", match: m, defaultHole: 14, slang: slang(), extractor: extractor(e))
        #expect(a.hole == 14)
        let b = try await VoiceHolePipeline.propose(transcript: "hoyo 3 rob cuatro", match: m, defaultHole: 14, slang: slang(), extractor: extractor(e))
        #expect(b.hole == 3)
    }

    @Test func theRestOfThePlayersGetBogeyOrANumber() async throws {
        let m = setup()   // el hoyo 14 es par 3
        let bogey = try await VoiceHolePipeline.propose(
            transcript: "rob dos, los demas bogey", match: m, defaultHole: 14, slang: slang(),
            extractor: extractor(VoiceHoleExtraction(hoyo: 14, scores: [sc("ROB", 2), sc("DEMAS", rel: "bogey")])))
        #expect(bogey.cells["ROB"]?.gross == 2)
        #expect(bogey.cells.filter { $0.key != "ROB" }.allSatisfy { $0.value.gross == 4 })
        #expect(bogey.cells.count == 5)

        let five = try await VoiceHolePipeline.propose(
            transcript: "yo tres, los demas cinco", match: m, defaultHole: 14, slang: slang(),
            extractor: extractor(extraction(scores: [("yo", 3, nil), ("DEMAS", 5, nil)])))
        #expect(five.cells["DAN"]?.gross == 3)
        #expect(five.cells["ROB"]?.gross == 5 && five.cells["ANS"]?.gross == 5)
    }

    @Test func anInventedOyesOrderIsIgnoredWhenNobodyTalkedAboutOyes() async throws {
        let m = setup()
        let e = extraction(scores: [("ROB", nil, 3)], oyes: [("ROB", 1)], units: [("DAN", "HO")])
        let a = try await VoiceHolePipeline.propose(transcript: "dan hole out y rob tres putts", match: m, defaultHole: 14, slang: slang(), extractor: extractor(e))
        #expect(a.oyes.isEmpty)
        let b = try await VoiceHolePipeline.propose(transcript: "oyes primero rob", match: m, defaultHole: 14, slang: slang(), extractor: extractor(e))
        #expect(b.oyes == ["ROB": 1])
    }

    @Test func holeOutAndThreePuttAreReceivedEvenWithoutButtons() async throws {
        let m = setup()
        let draft = try await VoiceHolePipeline.propose(
            transcript: "x", match: m, defaultHole: 14, slang: slang(),
            extractor: extractor(extraction(scores: [("DAN", 3, 1)], units: [("DAN", "HO"), ("ROB", "3P")])))
        #expect(draft.units.contains(.init(alias: "DAN", code: "HO", units: 1)))
        #expect(draft.units.contains(.init(alias: "ROB", code: "3P", units: 1)))
        #expect(draft.doubts.isEmpty)
        #expect(VoiceHolePipeline.report(draft, match: m).understood.contains("DAN Hole Out"))
    }

    @Test func yoMeansDanAndNotesAreKept() async throws {
        let m = setup()
        let draft = try await VoiceHolePipeline.propose(
            transcript: "x", match: m, defaultHole: 14, slang: slang(),
            extractor: extractor(extraction(scores: [("yo", 3, 1)], notes: [("", "bola al agua")])))
        #expect(draft.cells["DAN"]?.gross == 3)
        #expect(draft.notes == [.init(alias: "DAN", text: "bola al agua")])
    }

    @Test func aNicknameIsLearnedWhenYouFixItAndUsedNextTime() async throws {
        let m = setup()
        let s = slang()
        var draft = try await VoiceHolePipeline.propose(
            transcript: "el chino cuatro", match: m, defaultHole: 14, slang: s,
            extractor: extractor(extraction(scores: [("Chino", 4, 2)])))
        #expect(draft.cells["CHINO"]?.gross == 4)
        #expect(!VoiceHolePipeline.canApply(draft, match: m))   // jugador no reconocido

        draft = VoiceHolePipeline.reassign(draft, from: "CHINO", to: "ROB", spoken: "Chino", slang: s)
        #expect(draft.cells["ROB"]?.gross == 4)
        #expect(draft.cells["CHINO"] == nil)
        #expect(VoiceHolePipeline.canApply(draft, match: m))
        #expect(s.target(for: "chino") == "ROB")

        // La siguiente vez "Chino" ya es ROB, sin preguntar.
        let next = try await VoiceHolePipeline.propose(
            transcript: "chino cinco", match: m, defaultHole: 14, slang: s,
            extractor: extractor(extraction(scores: [("Chino", 5, nil)])))
        #expect(next.cells["ROB"]?.gross == 5)
        #expect(next.doubts.isEmpty)
    }

    // MARK: Anotar y deshacer

    @Test func applyWritesEverythingAndUndoRestoresTheWholeHole() async throws {
        let m = setup()
        m.upsertUnitEvent(hole: 14, alias: "FER", code: "SAND", units: 1)   // algo previo que Deshacer debe devolver
        let e = extraction(scores: [("DAN", 3, 2), ("ROB", 4, 2)], oyes: [("ROB", 1), ("DAN", 2)],
                           units: [("DAN", "SAND")], notes: [("ROB", "penalidad")])
        let draft = try await VoiceHolePipeline.propose(transcript: "dan tres rob cuatro oyes primero rob segundo dan", match: m, defaultHole: 14, slang: slang(), extractor: extractor(e))
        let token = try #require(VoicePipelineSpec.apply(draft, m))

        #expect(m.getScore(hole: 14, player: "DAN") == 3)
        #expect(m.getPutts(hole: 14, player: "ROB") == 2)
        #expect(m.oyesRanksByHole[14] == ["ROB": 1, "DAN": 2])
        #expect(m.unitEventsByHole[14]?.contains { $0.alias == "DAN" && $0.code == "SAND" } == true)
        #expect(m.unitEventsByHole[14]?.contains { $0.alias == "ROB" && $0.code == "NOTA" && $0.note == "penalidad" } == true)

        VoiceHolePipeline.undo(token, match: m)
        #expect(m.getScore(hole: 14, player: "DAN") == 0)
        #expect(m.oyesRanksByHole[14] == nil)
        #expect(m.unitEventsByHole[14]?.map(\.alias) == ["FER"])
    }

    @Test func undoPutsBackThePreviousScoreOfACorrectedCell() async throws {
        let m = setup()
        let before = m.getScore(hole: 5, player: "DAN")
        let e = extraction(hole: 5, scores: [("DAN", before + 2, nil)])
        let draft = try await VoiceHolePipeline.propose(transcript: "hoyo 5 dan lo que sea", match: m, defaultHole: 14, slang: slang(), extractor: extractor(e))
        let token = try #require(VoicePipelineSpec.apply(draft, m))
        #expect(m.getScore(hole: 5, player: "DAN") == before + 2)
        VoiceHolePipeline.undo(token, match: m)
        #expect(m.getScore(hole: 5, player: "DAN") == before)
    }

    @Test func doubtfulDraftsAreNotApplied() async throws {
        let m = setup()
        let draft = try await VoiceHolePipeline.propose(
            transcript: "x", match: m, defaultHole: 14, slang: slang(),
            extractor: extractor(extraction(scores: [("Pelón", 4, 2)])))
        #expect(VoicePipelineSpec.apply(draft, m) == nil)
        #expect(m.getScore(hole: 14, player: "DAN") == 0)
    }

    // MARK: Grabaciones para reentrenar

    @Test func recordingsAreKeptAndLinkedToTheFinalCard() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString)")
        let store = VoiceRecordStore(directory: dir)
        let audio = dir.appendingPathComponent("in.m4a")
        try Data([1, 2, 3]).write(to: audio)

        let a = store.record(audio: audio, transcript: "dan tres rob cuatro", roundId: "R1", hole: 14)
        let b = store.record(audio: nil, transcript: "el chino cinco", roundId: "R1", hole: 14)
        #expect(store.entries().count == 2)
        #expect(store.entries().first?.audioFile != nil)
        #expect(store.entries().allSatisfy { $0.finalCard == nil })

        store.resolve(ids: [a, b], finalCard: "H14 DAN 3 | ROB 4 | CHINO→ROB")
        #expect(store.entries().allSatisfy { $0.finalCard == "H14 DAN 3 | ROB 4 | CHINO→ROB" })
        #expect(VoiceRecordStore(directory: dir).entries().count == 2)   // sobrevive a reabrir
    }
}

/// Atajo: apply devuelve opcional.
@MainActor
private enum VoicePipelineSpec {
    static func apply(_ d: VoiceHoleDraft, _ m: MatchManager) -> VoiceUndoToken? { VoiceHolePipeline.apply(d, match: m) }
}

// MARK: - "Yo" y los nombres salen del Setup

@MainActor
struct SetupNamesTests {
    private func slang() -> VoiceSlangStore { VoiceSlangStore(defaults: UserDefaults(suiteName: "setup-\(UUID().uuidString)")!) }
    private func run(_ m: MatchManager, _ e: VoiceHoleExtraction, text: String = "yo tres") async throws -> VoiceHoleDraft {
        try await VoiceHolePipeline.propose(transcript: text, match: m, defaultHole: 6, slang: slang(), extractor: { _, _ in e })
    }

    @Test func meIsTheUserNameFromTheEnvFileEvenIfSetupSaysAnotherYo() async throws {
        let m = DemoFixture.make()
        let saved = VoiceHolePipeline.userName
        defer { VoiceHolePipeline.userName = saved }
        VoiceHolePipeline.userName = { "Roberto" }
        #expect(VoiceHolePipeline.meAlias(m) == "ROB")
        let d = try await run(m, .init(hoyo: 6, scores: [.init(jugador: "yo", gross: 3, putts: nil)]))
        #expect(d.cells["ROB"]?.gross == 3)
        #expect(d.cells["DAN"] == nil)
        let ctx = VoiceHolePipeline.context(match: m, hole: 6, slang: slang())
        #expect(ctx["yo_alias"] as? String == "ROB")
    }

    @Test func withoutAUserNameMeFallsBackToTheSetupYo() {
        let m = DemoFixture.make()
        let saved = VoiceHolePipeline.userName
        defer { VoiceHolePipeline.userName = saved }
        VoiceHolePipeline.userName = { nil }
        #expect(VoiceHolePipeline.meAlias(m) == m.yoAlias)
        VoiceHolePipeline.userName = { "Alguien que no juega" }
        #expect(VoiceHolePipeline.meAlias(m) == m.yoAlias)
    }

    @Test func thePlayerNamesAreTheOnesFromSetup() async throws {
        let m = DemoFixture.make()
        m.setPlayers(names: ["Daniel", "Beto", "Chuy"], preserveScores: false)
        let ctx = VoiceHolePipeline.context(match: m, hole: 6, slang: slang())
        let roster = (ctx["jugadores"] as? [[String: String]]) ?? []
        #expect(roster.map { $0["nombre"] } == ["Daniel", "Beto", "Chuy"])
        #expect(roster.map { $0["alias"] } == m.players.map(\.alias))
        // Alguien que no está en el Setup no se acepta: queda como duda, no se anota.
        let d = try await run(m, .init(hoyo: 6, scores: [.init(jugador: "Anselmo", gross: 5, putts: nil)]), text: "anselmo cinco")
        #expect(!VoiceHolePipeline.canApply(d, match: m))
    }

    @Test func theStartHoleOfTheSetupDecidesWhichHoleIsOnScreen() {
        let m = DemoFixture.make()
        #expect(m.playOrder().first == m.startHole)
    }
}

// MARK: - Casos de dictado de campo (casos_dictado.json). El LLM se simula con lo que devolvió de verdad.

@MainActor
struct DictationCasesTests {
    private func setup() -> MatchManager {
        let m = DemoFixture.make()
        for i in m.players.indices { for h in 1...18 { m.players[i].scores[h] = nil } }
        m.oyesRanksByHole = [:]; m.unitEventsByHole = [:]
        return m
    }
    private func slang() -> VoiceSlangStore { VoiceSlangStore(defaults: UserDefaults(suiteName: "cases-\(UUID().uuidString)")!) }
    private func run(_ m: MatchManager, _ text: String, hole: Int, _ e: VoiceHoleExtraction) async throws -> VoiceHoleDraft {
        try await VoiceHolePipeline.propose(transcript: text, match: m, defaultHole: hole, slang: slang(), extractor: { _, _ in e })
    }
    private func sc(_ j: String, _ g: Int? = nil, _ p: Int? = nil, rel: String? = nil) -> VoiceHoleExtraction.Score {
        .init(jugador: j, gross: g, putts: p, relativo: rel)
    }
    private func grosses(_ d: VoiceHoleDraft) -> [String: Int] { d.cells.compactMapValues(\.gross) }

    @Test func c01FullScores() async throws {   // H6 par 5
        let d = try await run(setup(), "Hoyo seis: Daniel cinco, Anselmo seis, Roberto siete, Ricardo cinco y Fernando cuatro.", hole: 6,
                              .init(hoyo: 6, scores: [sc("Daniel", 5), sc("Anselmo", 6), sc("Roberto", 7), sc("Ricardo", 5), sc("Fernando", 4)]))
        #expect(grosses(d) == ["DAN": 5, "ANS": 6, "ROB": 7, "RIC": 5, "FER": 4])
    }
    @Test func c02MeAndTheRestBogey() async throws {
        let d = try await run(setup(), "Tiré cinco y los demás bogey.", hole: 6,
                              .init(hoyo: 6, scores: [sc("DAN", 5), sc("DEMAS", rel: "bogey")]))
        #expect(grosses(d) == ["DAN": 5, "ANS": 6, "ROB": 6, "RIC": 6, "FER": 6])
    }
    @Test func c03EveryoneParOnTheEight() async throws {
        let d = try await run(setup(), "Todos hicimos par en el ocho.", hole: 8, .init(hoyo: 8, scores: [sc("DEMAS", rel: "par")]))
        #expect(d.hole == 8)
        #expect(grosses(d).values.allSatisfy { $0 == 4 } && grosses(d).count == 5)
    }
    @Test func c04RunOnSentenceWithRelativeScores() async throws {
        let d = try await run(setup(), "Yo par, Anselmo birdie, Roberto doble bogey y los demás bogey.", hole: 6,
                              .init(hoyo: 6, scores: [sc("DAN", rel: "par"), sc("ANS", rel: "birdie"), sc("ROB", rel: "doble_bogey"), sc("DEMAS", rel: "bogey")]))
        #expect(grosses(d) == ["DAN": 5, "ANS": 4, "ROB": 7, "RIC": 6, "FER": 6])
    }
    @Test func c05Nicknames() async throws {
        let d = try await run(setup(), "Dani cuatro, Richi cinco, Bob seis y Anse cuatro.", hole: 8,
                              .init(hoyo: 8, scores: [sc("DAN", 4), sc("RIC", 5), sc("ROB", 6), sc("ANS", 4)]))
        #expect(grosses(d) == ["DAN": 4, "RIC": 5, "ROB": 6, "ANS": 4])
        #expect(d.cells["FER"] == nil)
    }
    @Test func c06TwoScoresForTheSamePlayerIsADoubt() async throws {
        let d = try await run(setup(), "Yo cinco y Daniel seis.", hole: 6, .init(hoyo: 6, scores: [sc("DAN", 5), sc("Daniel", 6)]))
        #expect(d.doubts["DAN"]?.contains("dos scores distintos") == true)
        #expect(!VoiceHolePipeline.canApply(d, match: setup()))
    }
    @Test func c07to09NumbersThatLookAlike() async throws {
        let a = try await run(setup(), "Hoyo doce, Daniel seis golpes y dos putts.", hole: 3, .init(hoyo: 12, scores: [sc("DAN", 6, 2)]))
        #expect(a.hole == 12 && a.cells["DAN"] == .init(gross: 6, putts: 2))
        let b = try await run(setup(), "En el dieciséis Ricardo hizo seis, con tres putts.", hole: 3, .init(hoyo: 16, scores: [sc("RIC", 6, 3)]))
        #expect(b.hole == 16 && b.cells["RIC"] == .init(gross: 6, putts: 3))
        let c = try await run(setup(), "Hoyo dos, Roberto doce golpes y dos putts.", hole: 5, .init(hoyo: 2, scores: [sc("ROB", 12, 2)]))
        #expect(c.hole == 2 && c.cells["ROB"] == .init(gross: 12, putts: 2))
    }
    @Test func c10BirdieEagleParByName() async throws {
        let d = try await run(setup(), "Daniel birdie, Ricardo eagle y Fernando par.", hole: 6,
                              .init(hoyo: 6, scores: [sc("DAN", rel: "birdie"), sc("RIC", rel: "eagle"), sc("FER", rel: "par")]))
        #expect(grosses(d) == ["DAN": 4, "RIC": 3, "FER": 5])
    }
    @Test func c11SpokenCorrectionKeepsTheLastValue() async throws {
        let d = try await run(setup(), "Daniel seis... no, cinco.", hole: 14, .init(hoyo: 14, scores: [sc("DAN", 5)]))
        #expect(d.cells["DAN"]?.gross == 5)
    }
    @Test func c12CorrectionOfAnotherHole() async throws {
        let d = try await run(setup(), "Corrige a Daniel: fueron cinco en el seis.", hole: 14, .init(hoyo: 6, scores: [sc("DAN", 5)]))
        #expect(d.hole == 6 && d.cells["DAN"]?.gross == 5)
    }
    @Test func c13to14FullOyes() async throws {   // H14 par 3 (el 7 del texto del caso es par 4 en este curso)
        let d = try await run(setup(), "Oyes del catorce: primero Ricardo, segundo Anselmo, tercero Daniel, cuarto Roberto y quinto Fernando.", hole: 14,
                              .init(hoyo: 14, oyes: [.init(jugador: "RIC", rank: 1), .init(jugador: "ANS", rank: 2), .init(jugador: "DAN", rank: 3),
                                                    .init(jugador: "ROB", rank: 4), .init(jugador: "FER", rank: 5)]))
        #expect(d.oyes == ["RIC": 1, "ANS": 2, "DAN": 3, "ROB": 4, "FER": 5])
        let n = try await run(setup(), "O yes: Richi primero, Dani segundo, Anse tercero, Bob cuarto y Fernando quinto.", hole: 14,
                              .init(hoyo: 14, oyes: [.init(jugador: "Richi", rank: 1), .init(jugador: "Dani", rank: 2), .init(jugador: "Anse", rank: 3),
                                                    .init(jugador: "Bob", rank: 4), .init(jugador: "Fernando", rank: 5)]))
        #expect(n.oyes == ["RIC": 1, "DAN": 2, "ANS": 3, "ROB": 4, "FER": 5])
        #expect(n.doubts.isEmpty)
    }
    @Test func c15PartialOyesAsksForTheRest() async throws {
        let m = setup()
        let d = try await run(m, "El oyes lo ganó Anselmo.", hole: 14, .init(hoyo: 14, oyes: [.init(jugador: "Anselmo", rank: 1)]))
        #expect(d.oyes == ["ANS": 1])
        #expect(VoiceHolePipeline.report(d, match: m).missing.contains { $0.hasPrefix("lugar de oyes de") })
    }
    @Test func c16TiedOyesIsNotSaved() async throws {
        let d = try await run(setup(), "Primero Daniel y primero Ricardo en los oyes.", hole: 14,
                              .init(hoyo: 14, oyes: [.init(jugador: "Daniel", rank: 1), .init(jugador: "Ricardo", rank: 1)]))
        #expect(d.doubts["oyes"]?.contains("Empate") == true)
        #expect(!VoiceHolePipeline.canApply(d, match: setup()))
    }
    @Test func c17OyesOnAPar5IsRejected() async throws {
        let d = try await run(setup(), "Ricardo ganó el oyes en el seis.", hole: 6, .init(hoyo: 6, oyes: [.init(jugador: "RIC", rank: 1)]))
        #expect(d.oyes.isEmpty)
        #expect(d.doubts["oyes-par"]?.contains("par 5") == true)
    }
    @Test func c18to20PuttsNicknamesAndHoleOut() async throws {
        let a = try await run(setup(), "Roberto hizo seis y tripoteó.", hole: 14, .init(hoyo: 14, scores: [sc("ROB", 6, 3)]))
        #expect(a.cells["ROB"] == .init(gross: 6, putts: 3))
        let b = try await run(setup(), "Fernando cinco y cuatripoteo.", hole: 14, .init(hoyo: 14, scores: [sc("FER", 5, 4)]))
        #expect(b.cells["FER"] == .init(gross: 5, putts: 4))
        let c = try await run(setup(), "Daniel hizo cuatro y hole out.", hole: 14,
                              .init(hoyo: 14, scores: [sc("DAN", 4)], unidades: [.init(jugador: "DAN", codigo: "HO", cantidad: 1)]))
        #expect(c.units == [.init(alias: "DAN", code: "HO", units: 1)])
    }
    @Test func c21NewSlangUnitsAreDoubtsUntilTheyAreInTheCatalog() async throws {
        let m = setup()
        m.betCatalog.append(BetDefinition(tag: "SAND", name: "Sandy par", type: .individual, mode: .manual, units: 1, description: ""))
        let d = try await run(m, "Anselmo hizo sandy y Ricardo chip in.", hole: 14,
                              .init(hoyo: 14, unidades: [.init(jugador: "ANS", codigo: "SAND", cantidad: 1), .init(jugador: "RIC", codigo: "CHIP", cantidad: 1)]))
        #expect(d.units == [.init(alias: "ANS", code: "SAND", units: 1)])
        #expect(d.doubts["unidad:chip"] != nil)
    }
    @Test func c22MixedPhrase() async throws {   // H14 par 3
        let d = try await run(setup(), "Yo tres, Anselmo cuatro y los demás bogey. Oyes primero Ricardo, segundo Daniel, tercero Fernando, cuarto Anselmo, quinto Roberto. Daniel hole out.", hole: 14,
                              .init(hoyo: 14, scores: [sc("DAN", 3), sc("ANS", 4), sc("DEMAS", rel: "bogey")],
                                    oyes: [.init(jugador: "RIC", rank: 1), .init(jugador: "DAN", rank: 2), .init(jugador: "FER", rank: 3),
                                           .init(jugador: "ANS", rank: 4), .init(jugador: "ROB", rank: 5)],
                                    unidades: [.init(jugador: "DAN", codigo: "HO", cantidad: 1)]))
        #expect(grosses(d) == ["DAN": 3, "ANS": 4, "ROB": 4, "RIC": 4, "FER": 4])
        #expect(d.oyes == ["RIC": 1, "DAN": 2, "FER": 3, "ANS": 4, "ROB": 5])
        #expect(d.units == [.init(alias: "DAN", code: "HO", units: 1)])
    }
    @Test func c23NoPlayerNamedAsksWho() async throws {
        let d = try await run(setup(), "Hizo cinco y dos putts.", hole: 6, .init(hoyo: 6, scores: [sc("", 5, 2)]))
        #expect(d.cells.isEmpty)
        #expect(d.doubts["?"]?.contains("¿de quién?") == true)
    }
}

struct AppConfigTests {
    @Test func parsesKeysCommentsQuotesAndExport() {
        let text = """
        # comentario
        OPENAI_API_KEY = "sk-abc"
        export USER_NAME='Daniel'

        SIN_IGUAL
        EMPTY=
        """
        let v = AppConfig.parse(text)
        #expect(v["OPENAI_API_KEY"] == "sk-abc")
        #expect(v["USER_NAME"] == "Daniel")
        #expect(v["EMPTY"] == "")
        #expect(v["SIN_IGUAL"] == nil)
        #expect(v.count == 3)
    }
}
