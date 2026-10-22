//
//  SetupDraftTests.swift
//  Caddy_ScoreTests
//
//  El guardado del Setup ahora vive en MatchManager.applySetupDraft (lo usan la v1 y la v2). Se fija con
//  el caso de estudio que guardar el MISMO borrador no cambia nada y que cambiar el hoyo de salida,
//  los strokes o la pareja base aplica las reglas R1/R3/R5 (reparto por orden de juego y reseteo del Carry).
//

import Testing
@testable import Caddy_Score

@MainActor
struct SetupDraftTests {

    /// El borrador que el Setup mostraría para el match en curso (sin tocar nada).
    private func currentDraft(_ m: MatchManager) -> MatchManager.SetupDraft {
        var laneStrokes: [String: Double] = [:]
        var carriers: [String: String] = [:]
        for lane in m.lanes {
            let key = (lane.base.sorted() + ["vs"] + lane.opp.sorted()).joined(separator: "-")
            laneStrokes[key] = lane.strokes
            carriers[key] = lane.strokeCarrier ?? ""
        }
        var templates: [String: String] = [:]
        for p in m.players where p.alias != m.yoAlias {
            if let id = m.betValuesByOpponent[p.alias]?.templateId { templates[p.alias] = id }
        }
        return MatchManager.SetupDraft(
            courseId: m.courseId, startHole: m.startHole,
            playerNames: m.players.map(\.name), aliases: m.players.map(\.alias),
            strokesByAlias: Dictionary(uniqueKeysWithValues: m.players.map { ($0.alias, $0.strokesVsBase) }),
            templateIdByOpponent: templates,
            base1: m.baseTeamAliases.first ?? "", base2: m.baseTeamAliases.dropFirst().first ?? "",
            laneStrokes: laneStrokes, laneCarrierByKey: carriers,
            selectedTemplateId: m.activeTemplateId ?? "", vueltaValueText: "\(m.vueltaValue)")
    }

    @Test func savingTheSameDraftChangesNothing() {
        let m = DemoFixture.make()
        let before = m.resultadoRowsV2().map { "\($0.title)|\($0.f9Net)|\($0.b9Net)|\($0.money)" }
        m.applySetupDraft(currentDraft(m))
        let after = m.resultadoRowsV2().map { "\($0.title)|\($0.f9Net)|\($0.b9Net)|\($0.money)" }
        #expect(after == before)
        #expect(m.startHole == 1)
        #expect(m.individualCarryRequesterByOpponent["ROB"] != nil)
        #expect(m.individualDoublePressOpponents.contains("ROB"))
    }

    @Test func changingTheStartHoleResetsCarryAndMovesTheNines() {
        let m = DemoFixture.make()
        var draft = currentDraft(m)
        draft.startHole = 10
        m.applySetupDraft(draft)
        #expect(m.startHole == 10)
        #expect(m.individualCarryRequesterByOpponent.isEmpty)
        #expect(m.individualDoublePressOpponents.isEmpty)
        #expect(m.tarjetaNinesV2().map(\.title) == ["F9 · 10–18", "B9 · 1–9"])
        // Los strokes totales no cambian, solo dónde caen (R3).
        #expect(m.players.first { $0.alias == "ROB" }?.strokesVsBase == -8)  // negativo = DAN recibe 8 de ROB
    }

    @Test func changingStrokesAppliesToAllHoles() {
        let m = DemoFixture.make()
        var draft = currentDraft(m)
        draft.strokesByAlias["FER"] = 3.5
        m.applySetupDraft(draft)
        let fer = m.players.first { $0.alias == "FER" }
        #expect(fer?.strokesVsBase == 3.5)
        let total = (1...18).reduce(0.0) { $0 + m.distributedStrokes(total: 3.5, hole: $1) }
        #expect(total == 3.5)
    }

    @Test func lanesFollowTheBasePair() {
        // Con 5 jugadores y pareja base DAN+FER salen 3 carriles; con 4, uno.
        let five = MatchManager.setupLanes(base: ["DAN", "FER"], allAliases: ["DAN", "FER", "ROB", "RIC", "ANS"])
        #expect(five.count == 3)
        let four = MatchManager.setupLanes(base: ["DAN", "FER"], allAliases: ["DAN", "FER", "ROB", "RIC"])
        #expect(four.count == 1)
        #expect(four[0].id == "DAN-FER-vs-RIC-ROB")
        #expect(MatchManager.setupLanes(base: ["DAN"], allAliases: ["DAN", "FER"]).isEmpty)
    }
}
