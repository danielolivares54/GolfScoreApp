//
//  WatchCardCoordinatorTests.swift
//  v2t · Watch: la tarjeta que ve el reloj sale del borrador del iPhone; lápiz, goma, Anotar y Deshacer.
//

import Testing
import Foundation
@testable import Caddy_Score

@MainActor
struct WatchCardCoordinatorTests {
    private func make(_ match: MatchManager, hole: Int = 6, _ e: VoiceHoleExtraction) -> WatchCardCoordinator {
        let slang = VoiceSlangStore(defaults: UserDefaults(suiteName: "watch-\(UUID().uuidString)")!)
        return WatchCardCoordinator(match: match, currentHole: { hole },
                                    transcriber: { _, _ in "daniel cuatro roberto cinco" },
                                    extractor: { _, _ in e }, slang: slang, hasKey: { true })
    }
    private let audio = URL(fileURLWithPath: "/tmp/none.m4a")

    @Test func aDictationBecomesACardWithOneRowPerPlayer() async {
        let m = DemoFixture.make()
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 4, putts: 2), .init(jugador: "ROB", gross: 5, putts: nil)]))
        await c.receiveAudio(audio)
        let card = c.card()
        #expect(card.hole == 6 && card.rows.count == m.players.count)
        #expect(card.rows.first { $0.alias == "DAN" }?.gross == 4 && card.rows.first { $0.alias == "DAN" }?.putts == 2)
        #expect(card.rows.first { $0.alias == "ROB" }?.state == .ok)
        #expect(card.rows.filter { $0.state == .saved }.count == m.players.count - 2)   // el hoyo 6 del demo ya tenía a todos: no "faltan"
        #expect(card.error == nil && !card.processing)
    }

    @Test func pencilConfirmsADoubtAndEraserRemovesAValue() async {
        let m = DemoFixture.make()
        // Dos scores distintos para el mismo jugador: duda que bloquea Anotar hasta confirmarla con el lápiz.
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 4, putts: nil), .init(jugador: "DAN", gross: 5, putts: nil),
                                                      .init(jugador: "ROB", gross: 6, putts: nil)]))
        await c.receiveAudio(audio)
        #expect(c.card().rows.first { $0.alias == "DAN" }?.state == .doubt && !c.card().canApply)
        c.handle(.edit(alias: "DAN", gross: 5, putts: 2))             // lápiz: confirma
        #expect(c.card().rows.first { $0.alias == "DAN" }?.state == .ok && c.card().canApply)
        c.handle(.clear(alias: "ROB"))                                // goma
        #expect(c.card().rows.first { $0.alias == "ROB" }?.state == .saved)   // borrar lo dictado deja lo que ya estaba anotado
    }

    @Test func anUnknownNameIsDroppedWithANoticeAndTheSetupIsUntouched() async {
        let m = DemoFixture.make()
        let roster = m.players.map(\.alias)
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 4, putts: nil), .init(jugador: "Anselmito", gross: 5, putts: nil)]))
        await c.receiveAudio(audio)
        let card = c.card()
        #expect(card.rows.map(\.alias) == roster)                     // ninguna fila nueva
        #expect(card.notice?.contains("Anselmito") == true && card.canApply)
        c.handle(.apply)
        #expect(m.players.map(\.alias) == roster && m.getScore(hole: 6, player: "DAN") == 4)
    }

    @Test func playersAlreadyAnnotatedShowAsSavedNotAsMissing() async {
        let m = DemoFixture.make()   // el hoyo 6 ya tiene los scores de todos
        let before = Dictionary(uniqueKeysWithValues: m.players.map { ($0.alias, m.getScore(hole: 6, player: $0.alias)) })
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "ROB", gross: 7, putts: nil)]))
        await c.receiveAudio(audio)
        let rows = c.card().rows
        #expect(rows.first { $0.alias == "ROB" }?.state == .ok && rows.first { $0.alias == "ROB" }?.gross == 7)
        for r in rows where r.alias != "ROB" {
            #expect(r.state == .saved && r.gross == before[r.alias])        // se ve su score, no "falta"
        }
        #expect(c.card().canApply)
        c.handle(.apply)
        for p in m.players where p.alias != "ROB" { #expect(m.getScore(hole: 6, player: p.alias) == before[p.alias]) }
    }

    @Test func applyWritesTheHoleAndUndoRestoresIt() async {
        let m = DemoFixture.make()
        let before = m.getScore(hole: 6, player: "DAN")
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 9, putts: 3)]))
        await c.receiveAudio(audio)
        #expect(c.card().replaces == (before > 0))
        c.handle(.apply)
        #expect(m.getScore(hole: 6, player: "DAN") == 9)
        let after = c.card()
        #expect(after.applied?.hole == 6 && after.applied?.canUndo == true && after.rows.allSatisfy { $0.state == .missing })
        c.handle(.undo)
        #expect(m.getScore(hole: 6, player: "DAN") == before)
        #expect(c.card().applied == nil)
    }

    @Test func applyIsBlockedWhileThereAreDoubts() async {
        let m = DemoFixture.make()
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 4, putts: nil), .init(jugador: "DAN", gross: 9, putts: nil)]))
        await c.receiveAudio(audio)
        let before = m.getScore(hole: 6, player: "DAN")
        c.handle(.apply)
        #expect(m.getScore(hole: 6, player: "DAN") == before && c.card().applied == nil)
    }

    @Test func aQuestionOrAMissingKeyIsAnErrorNotAnEdit() async {
        let m = DemoFixture.make()
        let noKey = WatchCardCoordinator(match: m, currentHole: { 6 }, transcriber: { _, _ in "x" },
                                         extractor: { _, _ in VoiceHoleExtraction() }, hasKey: { false })
        await noKey.receiveAudio(audio)
        #expect(noKey.card().error != nil && noKey.draft.isEmpty)

        let asks = WatchCardCoordinator(match: m, currentHole: { 6 }, transcriber: { _, _ in "cómo vamos" },
                                        extractor: { _, _ in VoiceHoleExtraction() }, hasKey: { true })
        await asks.receiveAudio(audio)
        #expect(asks.card().error != nil && asks.draft.isEmpty)
    }

    @Test func theCardRoundTripsAsJSONForTheWatch() async throws {
        let m = DemoFixture.make()
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 4, putts: 2)]))
        await c.receiveAudio(audio)
        let card = c.card()
        #expect(try JSONDecoder().decode(WatchCardDTO.self, from: JSONEncoder().encode(card)) == card)
        let cmd = WatchCommand.edit(alias: "DAN", gross: 5, putts: nil)
        #expect(try JSONDecoder().decode(WatchCommand.self, from: JSONEncoder().encode(cmd)) == cmd)
    }
}
