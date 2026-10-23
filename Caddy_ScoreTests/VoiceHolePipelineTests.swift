//
//  VoiceHolePipelineTests.swift
//  Caddy_ScoreTests
//
//  v2t Paso 1: proponer no guarda nada, aplicar anota, deshacer devuelve lo anterior.
//  Se prueba con el caso de estudio (DemoFixture) y un parser falso: sin red ni LLM.
//

import Testing
import Foundation
@testable import Caddy_Score

@MainActor
struct VoiceHolePipelineTests {

    private func entities(hole: Int?, _ scores: [(String, Int, Int?)]) -> ScoreEntities {
        ScoreEntities(hoyo: hole, scores: scores.map { PlayerScore(jugador: $0.0, gross: $0.1, putts: $0.2) })
    }

    /// Un hoyo que el caso de estudio no tiene capturado para nadie no existe: se usa el 18 vaciándolo.
    private func emptyHole(_ m: MatchManager, _ hole: Int) {
        for i in m.players.indices { m.players[i].scores[hole] = nil }
    }

    @Test func proposingDoesNotWriteAnything() async throws {
        let m = DemoFixture.make()
        emptyHole(m, 18)
        let parser: VoiceHolePipeline.Parser = { _, _ in
            LLMResult(ok: true, error: nil, intent: "registro_score",
                      entities: ScoreEntities(hoyo: 18, scores: [PlayerScore(jugador: "DAN", gross: 4, putts: 2)]))
        }
        let proposal = try await VoiceHolePipeline.propose(transcript: "hoyo 18 daniel cuatro", match: m, parser: parser)
        #expect(proposal.hole == 18)
        #expect(proposal.rows.map(\.alias) == ["DAN"])
        #expect(proposal.rows.first?.gross == 4)
        #expect(m.getScore(hole: 18, player: "DAN") == 0)
    }

    @Test func applyWritesAndUndoRestoresThePreviousValue() throws {
        let m = DemoFixture.make()
        let before = m.getScore(hole: 5, player: "DAN")
        #expect(before > 0)
        let proposal = VoiceHoleProposal(hole: 5, rows: [
            VoiceHoleRow(alias: "DAN", gross: before + 2, putts: 3, state: .ok)
        ], transcript: "")
        let token = VoiceHolePipeline.apply(proposal, match: m)
        #expect(m.getScore(hole: 5, player: "DAN") == before + 2)
        #expect(m.getPutts(hole: 5, player: "DAN") == 3)
        VoiceHolePipeline.undo(token, match: m)
        #expect(m.getScore(hole: 5, player: "DAN") == before)
    }

    @Test func undoOfAnEmptyCellLeavesItEmpty() {
        let m = DemoFixture.make()
        emptyHole(m, 18)
        let proposal = VoiceHoleProposal(hole: 18, rows: [
            VoiceHoleRow(alias: "DAN", gross: 5, putts: nil, state: .ok)
        ], transcript: "")
        let token = VoiceHolePipeline.apply(proposal, match: m)
        #expect(m.getScore(hole: 18, player: "DAN") == 5)
        VoiceHolePipeline.undo(token, match: m)
        #expect(m.getScore(hole: 18, player: "DAN") == 0)
    }

    @Test func doubtfulRowsAreMarked() throws {
        let m = DemoFixture.make()
        let proposal = try VoiceHolePipeline.proposal(
            from: entities(hole: 18, [("DAN", 4, 6), ("ROB", 4, 2)]), transcript: "hoyo 18 daniel cuatro roberto cuatro", match: m)
        #expect(proposal.rows.first { $0.alias == "DAN" }?.state == .doubtful("Más putts que golpes"))
        #expect(proposal.rows.first { $0.alias == "ROB" }?.state == .ok)
        #expect(proposal.hasDoubts)
    }

    @Test func missingPiecesAreReportedInSpanish() async {
        let m = DemoFixture.make()
        let parser: VoiceHolePipeline.Parser = { _, _ in
            LLMResult(ok: true, error: nil, intent: nil, entities: ScoreEntities(hoyo: 18, scores: []))
        }
        await #expect(throws: VoiceHoleError.emptyTranscript) {
            _ = try await VoiceHolePipeline.propose(transcript: "   ", match: m, parser: parser)
        }
        await #expect(throws: VoiceHoleError.noScores) {
            _ = try await VoiceHolePipeline.propose(transcript: "hoyo 18 daniel cuatro", match: m, parser: parser)
        }
    }
}
