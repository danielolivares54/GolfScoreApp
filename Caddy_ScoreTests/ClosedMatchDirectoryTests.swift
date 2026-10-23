//
//  ClosedMatchDirectoryTests.swift
//  Caddy_ScoreTests
//
//  Al CERRAR un match el Directorio se actualiza con ese match (strokes usados y próximos, plantilla, resultado,
//  fecha del último juego y dinero) y de ahí salen los strokes y el tag del siguiente. Un empate se registra pero
//  no mueve los strokes; cada match se registra una sola vez. Se usa un directorio temporal, no el real.
//

import Foundation
import Testing
@testable import Caddy_Score

@MainActor
struct ClosedMatchDirectoryTests {

    private func makeStore() -> (PlayerDirectoryStore, cleanup: () -> Void) {
        let name = "test_directory_\(UUID().uuidString).json"
        let store = PlayerDirectoryStore(fileName: name)
        let cleanup = {
            if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(name) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return (store, cleanup)
    }

    private func entry(_ store: PlayerDirectoryStore, _ name: String) -> PlayerDirectoryEntry? {
        store.entries.first { $0.name == name }
    }

    @Test func closingTheDemoMatchRecordsEachRivalAndSetsTheNextStrokes() {
        let (store, cleanup) = makeStore(); defer { cleanup() }
        let m = DemoFixture.make()
        let next = m.applyInterMatchStrokeCarry(directory: store)
        // ROB: DAN recibía 8 y ganó el match (F9 +2, B9 +4) → ROB da uno menos: DAN recibe 7.
        #expect(next["ROB"] == -7)
        let rob = entry(store, "Roberto")
        #expect(rob?.strokeAnt == -8)
        #expect(rob?.strokesVsBase == -7)
        #expect(rob?.lastKeyId == m.roundId)
        #expect(rob?.lastGameAt != nil)
        #expect(rob?.gameMoneyMxn == 425)
        #expect(rob?.accumulatedMxn == 425)
        #expect(rob?.lastResult?.contains("Match") == true)
        // FER perdió el match contra DAN y quien pierde recibe… cada rival queda registrado.
        #expect(Set(next.keys) == ["FER", "ROB", "RIC", "ANS"])
        #expect(["Fernando", "Roberto", "Ricardo", "Anselmo"].allSatisfy { entry(store, $0)?.lastGameAt != nil })
    }

    @Test func aTieIsRecordedButStrokesDoNotMove() {
        let (store, cleanup) = makeStore(); defer { cleanup() }
        store.recordClosedMatch(playerName: "Empate Test", alias: "EMP", strokesUsed: 3, nextStrokes: 3, templateId: "TPCH",
                                resultSummary: "F9 +0 · B9 +0 · Match +0", roundId: "R1", moneyMxn: 0)
        let e = entry(store, "Empate Test")
        #expect(e?.strokesVsBase == 3 && e?.strokeAnt == 3)
        #expect(e?.lastGameAt != nil)
        #expect(e?.preferredTagId == "TPCH")
        #expect(e?.accumulatedMxn == 0)
    }

    @Test func eachMatchIsRecordedOnlyOnceAndMoneyAccumulates() {
        let (store, cleanup) = makeStore(); defer { cleanup() }
        func record(_ round: String, money: Int, next: Double) {
            store.recordClosedMatch(playerName: "Acum Test", alias: "ACU", strokesUsed: 2, nextStrokes: next, templateId: nil,
                                    resultSummary: "x", roundId: round, moneyMxn: money)
        }
        record("R1", money: 100, next: 3)
        record("R1", money: 100, next: 4)      // el mismo match otra vez: se ignora
        #expect(entry(store, "Acum Test")?.strokesVsBase == 3)
        #expect(entry(store, "Acum Test")?.accumulatedMxn == 100)
        record("R2", money: -40, next: 3)
        #expect(entry(store, "Acum Test")?.accumulatedMxn == 60)
        #expect(entry(store, "Acum Test")?.gameMoneyMxn == -40)
    }

    @Test func theTemplateUsedBecomesThePreferredTagOfTheNextMatch() {
        let (store, cleanup) = makeStore(); defer { cleanup() }
        store.upsert(name: "Tag Test", alias: "TAG", strokesVsBase: 1, preferredTagId: "VIEJA")
        store.recordClosedMatch(playerName: "Tag Test", alias: "TAG", strokesUsed: 1, nextStrokes: 2, templateId: "NUEVA",
                                resultSummary: "x", roundId: "R9", moneyMxn: 0)
        #expect(entry(store, "Tag Test")?.preferredTagId == "NUEVA")
        // Lo que el Setup ofrece a un jugador agregado de nuevo: strokes y tag del Directorio.
        #expect(entry(store, "Tag Test")?.strokesVsBase == 2)
    }

    @Test func closingARoundGivesTheNextMatchANewRoundId() {
        let m = DemoFixture.make()
        let before = m.roundId
        // generateRoundId es lo que closeRound() llama al final: el id depende de la hora (segundos).
        m.generateRoundId()
        #expect(!m.roundId.isEmpty)
        #expect(before.hasPrefix("R") && m.roundId.hasPrefix("R"))
    }

    // MARK: Solo un match completo cuenta

    @Test func anIncompleteMatchDoesNotTouchTheDirectoryOrTheStrokes() {
        let (store, cleanup) = makeStore(); defer { cleanup() }
        let m = DemoFixture.make()
        #expect(m.isMatchComplete(opponentAlias: "ROB"))
        // A ROB le falta el hoyo 18: ese match queda incompleto; los otros tres siguen completos.
        m.players[m.players.firstIndex { $0.alias == "ROB" }!].scores.removeValue(forKey: 18)
        #expect(!m.isMatchComplete(opponentAlias: "ROB"))
        #expect(m.completeMatchCounts.complete == 3 && m.completeMatchCounts.total == 4)
        let next = m.applyInterMatchStrokeCarry(directory: store)
        #expect(next["ROB"] == nil)
        #expect(Set(next.keys) == ["FER", "RIC", "ANS"])
        #expect(entry(store, "Roberto")?.lastGameAt == nil)
        #expect(entry(store, "Roberto")?.accumulatedMxn == nil)
        #expect(m.closeRoundWarning.contains("incompleto"))
    }

    @Test func aFullyIncompleteRoundMovesNothing() {
        let (store, cleanup) = makeStore(); defer { cleanup() }
        let m = DemoFixture.make()
        for i in m.players.indices { m.players[i].scores.removeValue(forKey: 12) }
        #expect(m.applyInterMatchStrokeCarry(directory: store).isEmpty)
        #expect(["Fernando", "Roberto", "Ricardo", "Anselmo"].allSatisfy { entry(store, $0)?.lastGameAt == nil })
    }

    // MARK: Log de notas

    @Test func roundNotesAreLoggedInPlayOrderAndSkipEmptyOnes() {
        let m = DemoFixture.make()
        m.upsertUnitEvent(hole: 14, alias: "DAN", code: "NOTA", units: 0, note: "Bola al agua")
        m.upsertUnitEvent(hole: 3, alias: "ROB", code: "NOTA", units: 0, note: "  Penalidad  ")
        m.upsertUnitEvent(hole: 5, alias: "FER", code: "NOTA", units: 0, note: "   ")
        let notes = m.roundNotes()
        #expect(notes == [RoundResultNote(hole: 3, alias: "ROB", text: "Penalidad"),
                          RoundResultNote(hole: 14, alias: "DAN", text: "Bola al agua")])
        m.updateStartHole(10, resetScores: false)
        #expect(m.roundNotes().map(\.hole) == [14, 3])     // en orden de juego: el 14 antes que el 3
    }

    @Test func archivedRoundsKeepTheirNotesAndOldFilesStillDecode() throws {
        let note = RoundResultNote(hole: 7, alias: "DAN", text: "x")
        let json = #"{"roundId":"R1","date":"d","courseId":"c","courseName":"n","startHole":1,"players":[],"lines":[],"totalMoney":0,"closedAt":"2026-10-23T00:00:00Z"}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(RoundResultFile.self, from: Data(json.utf8))
        #expect(old.notes == nil)
        let withNotes = RoundResultFile(roundId: "R2", date: "d", courseId: "c", courseName: "n", startHole: 1, players: [], lines: [],
                                        totalMoney: 0, closedAt: Date(), notes: [note])
        let data = try JSONEncoder().encode(withNotes)
        #expect(try JSONDecoder().decode(RoundResultFile.self, from: data).notes == [note])
    }
}
