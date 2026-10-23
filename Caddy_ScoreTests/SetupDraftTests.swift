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

    @Test func savingTheSetupKeepsTheValuesEditedByHandUnlessTheTagChanges() throws {
        let templates = BetTemplateStore.shared.entries
        let t1 = try #require(templates.first)
        let m = DemoFixture.make()
        m.setTemplateV2(t1, for: .individual("ROB"))
        m.setTemplateV2(t1, for: .pair(m.lanes[0].id))
        var rob = m.betValuesV2(for: .individual("ROB")); rob.presionValue += 7
        m.setBetValuesV2(rob, for: .individual("ROB"))
        var pair = m.betValuesV2(for: .pair(m.lanes[0].id)); pair.matchValue += 9
        m.setBetValuesV2(pair, for: .pair(m.lanes[0].id))

        m.applySetupDraft(currentDraft(m))   // guardar sin cambiar el tag: no pisa lo editado
        #expect(m.betValuesV2(for: .individual("ROB")).presionValue == rob.presionValue)
        #expect(m.betValuesV2(for: .pair(m.lanes[0].id)).matchValue == pair.matchValue)

        // Si en el Setup se elige OTRO tag para ese rival, sí se copian los valores de ese tag.
        guard let t2 = templates.first(where: { $0.id != t1.id }) else { return }
        var draft = currentDraft(m)
        draft.templateIdByOpponent["ROB"] = t2.id
        m.applySetupDraft(draft)
        #expect(m.betValuesV2(for: .individual("ROB")).presionValue == t2.presionValue)
        #expect(m.betValuesV2(for: .individual("ROB")).templateId == t2.id)
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

    // MARK: Modelo del borrador (SetupDraftModel, usado por SetupV2)

    @Test func aliasesUseTheFirstThreeLettersAndNumberDuplicates() {
        let list = MatchManager.setupAliases(from: ["Daniel", "Fernando", "Roberto", "Robin", " ", "123"])
        #expect(list.map(\.alias) == ["DAN", "FER", "ROB", "ROB1"])
    }

    @Test func loadedModelSavesWithoutChangingTheMatch() {
        let m = DemoFixture.make()
        let before = m.resultadoRowsV2().map { "\($0.title)|\($0.f9Net)|\($0.b9Net)|\($0.money)" }
        let model = SetupDraftModel(manager: m)
        model.load()
        // El Setup ofrece la primera plantilla del catálogo guardado a los rivales que no tienen una; el valor de esa
        // plantilla depende de lo que haya guardado el dispositivo, así que aquí se deja sin elegir (el caso de estudio
        // define sus propios valores) para que la prueba no dependa del simulador.
        model.templateIdByOpponent = [:]
        model.selectedTemplateId = ""
        #expect(model.aliases == ["DAN", "FER", "ROB", "RIC", "ANS"])
        #expect(model.baseAliases == ["DAN", "FER"])
        #expect(model.lanes.count == 3)
        model.save()
        let after = m.resultadoRowsV2().map { "\($0.title)|\($0.f9Net)|\($0.b9Net)|\($0.money)" }
        #expect(after == before)
    }

    @Test func modelLimitsPlayersToFiveAndCleansRemovedOnes() {
        let m = DemoFixture.make()
        let model = SetupDraftModel(manager: m)
        model.load()
        model.addPlayer("Sexto", directoryMatch: nil)
        #expect(model.playerNames.count == 5)           // ya eran 5
        model.removePlayer(at: 4)                       // quita a ANS
        #expect(model.strokesByAlias["ANS"] == nil)
        #expect(model.templateIdByOpponent["ANS"] == nil)
        #expect(model.lanes.count == 1)                 // con 4 jugadores queda un carril
        #expect(model.canAdvance(step: 1))
    }

    @Test func strokeStepsAdjustByWholeAndHalf() {
        let m = DemoFixture.make()
        let model = SetupDraftModel(manager: m)
        model.load()
        model.adjustStroke(alias: "FER", delta: 1)
        model.adjustStroke(alias: "FER", delta: 0.5)
        #expect(model.strokesByAlias["FER"] == 1.5)
        let key = model.lanes[0].id
        model.adjustLaneStroke(key: key, delta: -50)
        #expect(model.laneStrokes[key] == 0)            // las parejas no bajan de 0
    }

    @Test func canAdvanceFollowsTheV1Conditions() {
        let m = DemoFixture.make()
        let model = SetupDraftModel(manager: m)
        model.load()
        #expect(model.canAdvance(step: 0) && model.canAdvance(step: 2))
        model.base2 = model.base1
        #expect(!model.canAdvance(step: 2))
        model.startHole = 19
        #expect(!model.canAdvance(step: 0))
    }

    @Test func strokeHolesTextListsWholeAndHalfHoles() {
        let m = DemoFixture.make()
        let eight = m.strokeHolesText(total: -8, startHole: 1)
        #expect(eight?.hasPrefix("hoyos ") == true)
        #expect(eight?.contains("½") == false)
        let split = m.strokeHolesText(total: 3.5, startHole: 1)
        #expect(split?.contains(" y ½ en ") == true)
        #expect(m.strokeHolesText(total: 0, startHole: 1) == nil)
    }
}
