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

    private func extractor(_ e: VoiceHoleExtraction) -> VoiceHolePipeline.Extractor { { _, _ in e } }

    // MARK: Lo que falta

    @Test func threePlayersTwoOyesAndOneUnitSaysWhatIsMissing() async throws {
        let m = setup()
        let e = extraction(scores: [("DAN", 3, 2), ("ROB", 4, nil), ("RIC", 5, 2)],
                           oyes: [("ROB", 1), ("DAN", 2)], units: [("DAN", "SAND")])
        let draft = try await VoiceHolePipeline.propose(transcript: "hoyo 14 dan tres rob cuatro ric cinco oyes rob dan sandy dan",
                                                        match: m, slang: slang(), extractor: extractor(e))
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
            transcript: "primera", match: m, slang: s,
            extractor: extractor(extraction(scores: [("DAN", 3, 2), ("ROB", 4, 2)], oyes: [("ROB", 1)])))
        draft = try await VoiceHolePipeline.propose(
            transcript: "segunda", match: m, draft: draft, slang: s,
            extractor: extractor(extraction(hole: nil, scores: [("FER", 5, 2), ("RIC", 5, 2), ("ANS", 4, 2)],
                                            oyes: [("DAN", 2), ("FER", 3), ("RIC", 4), ("ANS", 5)])))
        let report = VoiceHolePipeline.report(draft, match: m)
        #expect(report.isComplete)
        #expect(report.message.hasSuffix("Está completo."))
        #expect(draft.hole == 14)
        #expect(draft.transcripts == ["primera", "segunda"])
    }

    @Test func theLatestDictationWinsOnTheSameCell() async throws {
        let m = setup()
        let s = slang()
        var draft = try await VoiceHolePipeline.propose(transcript: "a", match: m, slang: s,
                                                        extractor: extractor(extraction(scores: [("DAN", 3, 2)])))
        draft = try await VoiceHolePipeline.propose(transcript: "corrige", match: m, draft: draft, slang: s,
                                                    extractor: extractor(extraction(hole: nil, scores: [("DAN", 4, nil)])))
        #expect(draft.cells["DAN"]?.gross == 4)
        #expect(draft.cells["DAN"]?.putts == 2)   // los putts ya dictados se conservan
    }

    @Test func putts_alone_fillTheCell() async throws {
        let m = setup()
        let s = slang()
        var draft = try await VoiceHolePipeline.propose(transcript: "a", match: m, slang: s,
                                                        extractor: extractor(extraction(scores: [("ROB", 4, nil)])))
        draft = try await VoiceHolePipeline.propose(transcript: "rob dos putts", match: m, draft: draft, slang: s,
                                                    extractor: extractor(extraction(hole: nil, scores: [("ROB", nil, 2)])))
        #expect(draft.cells["ROB"] == .init(gross: 4, putts: 2))
    }

    @Test func nothingHeardLeavesTheDraftAlone() async {
        let m = setup()
        await #expect(throws: VoiceHoleError.nothingHeard) {
            _ = try await VoiceHolePipeline.propose(transcript: "ruido", match: m, slang: slang(),
                                                    extractor: extractor(VoiceHoleExtraction()))
        }
        await #expect(throws: VoiceHoleError.emptyTranscript) {
            _ = try await VoiceHolePipeline.propose(transcript: "  ", match: m, slang: slang(),
                                                    extractor: extractor(VoiceHoleExtraction()))
        }
    }

    // MARK: Unidades, notas y alias

    @Test func anUnknownUnitIsADoubtAndNotApplied() async throws {
        let m = setup()
        let draft = try await VoiceHolePipeline.propose(
            transcript: "x", match: m, slang: slang(),
            extractor: extractor(extraction(scores: [("DAN", 4, 2)], units: [("DAN", "chip raro")])))
        #expect(draft.units.isEmpty)
        #expect(VoiceHolePipeline.report(draft, match: m).doubts.contains { $0.contains("chip raro") })
        #expect(!VoiceHolePipeline.canApply(draft, match: m))
    }

    @Test func holeOutAndThreePuttAreReceivedEvenWithoutButtons() async throws {
        let m = setup()
        let draft = try await VoiceHolePipeline.propose(
            transcript: "x", match: m, slang: slang(),
            extractor: extractor(extraction(scores: [("DAN", 3, 1)], units: [("DAN", "HO"), ("ROB", "3P")])))
        #expect(draft.units.contains(.init(alias: "DAN", code: "HO", units: 1)))
        #expect(draft.units.contains(.init(alias: "ROB", code: "3P", units: 1)))
        #expect(draft.doubts.isEmpty)
        #expect(VoiceHolePipeline.report(draft, match: m).understood.contains("DAN Hole Out"))
    }

    @Test func yoMeansDanAndNotesAreKept() async throws {
        let m = setup()
        let draft = try await VoiceHolePipeline.propose(
            transcript: "x", match: m, slang: slang(),
            extractor: extractor(extraction(scores: [("yo", 3, 1)], notes: [("", "bola al agua")])))
        #expect(draft.cells["DAN"]?.gross == 3)
        #expect(draft.notes == [.init(alias: "DAN", text: "bola al agua")])
    }

    @Test func aNicknameIsLearnedWhenYouFixItAndUsedNextTime() async throws {
        let m = setup()
        let s = slang()
        var draft = try await VoiceHolePipeline.propose(
            transcript: "el chino cuatro", match: m, slang: s,
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
            transcript: "chino cinco", match: m, slang: s,
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
        let draft = try await VoiceHolePipeline.propose(transcript: "x", match: m, slang: slang(), extractor: extractor(e))
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
        let draft = try await VoiceHolePipeline.propose(transcript: "x", match: m, slang: slang(), extractor: extractor(e))
        let token = try #require(VoicePipelineSpec.apply(draft, m))
        #expect(m.getScore(hole: 5, player: "DAN") == before + 2)
        VoiceHolePipeline.undo(token, match: m)
        #expect(m.getScore(hole: 5, player: "DAN") == before)
    }

    @Test func doubtfulDraftsAreNotApplied() async throws {
        let m = setup()
        let draft = try await VoiceHolePipeline.propose(
            transcript: "x", match: m, slang: slang(),
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
