//
//  CatalogGatingTests.swift
//  Caddy_ScoreTests
//
//  El catálogo de apuestas gobierna qué cuenta: apagar Oyes, Oyes Parejas o Match Parejas los quita del cálculo,
//  el "Vale" de Oyes se usa y una unidad manual apagada deja de contar (sus eventos se conservan). Se prueba con el
//  caso de estudio cambiando solo `betCatalog` (las definiciones ACTIVAS), sin tocar el catálogo guardado.
//

import Foundation
import Testing
@testable import Caddy_Score

@MainActor
struct CatalogGatingTests {

    private func catalog(without tags: Set<String> = [], oyesUnits: Int = 1) -> [BetDefinition] {
        DemoFixture.defaultCatalog()
            .filter { !tags.contains($0.tag) }
            .map { def in
                var copy = def
                if def.tag == "OYES" || def.tag == "OYESP" { copy.units = oyesUnits }
                return copy
            }
    }

    private func robUnits(_ m: MatchManager) -> Int {
        m.resultadoRowsV2().first { $0.title == "ROB" }?.unitsNet ?? 0
    }

    // MARK: Medal y Skins

    private func medalSkinsCatalog(medal: Int? = nil, skins: Int? = nil) -> [BetDefinition] {
        var out = catalog()
        if let medal { out.append(BetDefinition(tag: "MEDAL", name: "Medal", type: .individual, mode: .calculado, units: medal, description: "")) }
        if let skins { out.append(BetDefinition(tag: "SKIN", name: "Skins", type: .individual, mode: .calculado, units: skins, description: "")) }
        return out
    }

    private func zeroStrokes(_ m: MatchManager) {
        for p in m.players { m.setStrokesVsBase(alias: p.alias, value: 0) }
    }

    private func setScores(_ m: MatchManager, _ scores: [Int: [String: Int]]) {
        for (hole, byAlias) in scores {
            for (alias, gross) in byAlias {
                if let i = m.players.firstIndex(where: { $0.alias == alias }) { m.players[i].scores[hole] = (gross: gross, putts: nil) }
            }
        }
    }

    private func unitStake(_ m: MatchManager, _ opponent: String) -> Int {
        m.unitStakeForIndividual(opponentAlias: opponent, segmentOverride: "F9") + m.unitStakeForIndividual(opponentAlias: opponent, segmentOverride: "B9")
    }

    @Test func skinsAccumulateWhenTheTopIsTiedAndTheNextWinnerTakesThemAll() {
        let m = DemoFixture.make()
        zeroStrokes(m)
        m.skinsParticipantAliases = ["DAN", "ROB", "FER"]
        setScores(m, [1: ["DAN": 4, "ROB": 4, "FER": 5],     // DAN y ROB empatan arriba: se acumula
                      2: ["DAN": 5, "ROB": 5, "FER": 4],     // gana FER y se lleva 2 skins
                      3: ["DAN": 4, "ROB": 5, "FER": 5]])    // gana DAN 1 skin
        m.betCatalog = medalSkinsCatalog(skins: 2)
        let holes = m.skinsSummary().holes
        #expect(holes[0].winner == nil && holes[0].skins == 0 && holes[0].pot == 1)
        #expect(holes[1].winner == "FER" && holes[1].skins == 2 && holes[1].pot == 2)
        #expect(holes[2].winner == "DAN" && holes[2].skins == 1 && holes[2].pot == 1)
        // Cada skin vale 2 unidades y cada perdedor le paga al ganador: DAN vs ROB +2; DAN vs FER −4 (FER, 2 skins) +2 (DAN, 1 skin).
        #expect(m.skinsStake(opponentAlias: "ROB", holes: [1, 2, 3]) == 2)
        #expect(m.skinsStake(opponentAlias: "FER", holes: [1, 2, 3]) == -2)
        // Quien no juega Skins no entra: ANS no cobra ni paga.
        #expect(m.skinsStake(opponentAlias: "ANS", holes: [1, 2, 3]) == 0)
    }

    @Test func skinsUseTheStrokesBetweenEachPairOfPlayers() throws {
        let m = DemoFixture.make()
        zeroStrokes(m)
        m.setStrokesVsBase(alias: "ROB", value: -1)          // DAN recibe 1 de ROB
        m.skinsParticipantAliases = ["DAN", "ROB"]
        m.betCatalog = medalSkinsCatalog(skins: 1)
        let total = (1...18).reduce(0.0) { $0 + m.skinsPairStrokes("DAN", "ROB", hole: $1).a }
        #expect(total == 1)
        let hole = try #require((1...18).first { m.skinsPairStrokes("DAN", "ROB", hole: $0).a == 1 })
        setScores(m, [hole: ["DAN": 5, "ROB": 4]])           // neto 4 contra 4: empatan
        #expect(m.skinsSummary().holes.first { $0.hole == hole }?.winner == nil)
        setScores(m, [hole: ["DAN": 4, "ROB": 4]])           // neto 3 contra 4: gana DAN
        #expect(m.skinsSummary().holes.first { $0.hole == hole }?.winner == "DAN")
    }

    @Test func skinsStrokesBetweenTwoRivalsAreTheDifferenceOfTheirStrokes() {
        let m = DemoFixture.make()
        zeroStrokes(m)
        m.setStrokesVsBase(alias: "FER", value: 3)
        m.setStrokesVsBase(alias: "ROB", value: 1)
        let ferRob = (1...18).map { m.skinsPairStrokes("FER", "ROB", hole: $0) }
        #expect(ferRob.reduce(0.0) { $0 + $1.a } == 2)       // FER recibe 3 − 1 = 2 de ROB
        #expect(ferRob.reduce(0.0) { $0 + $1.b } == 0)
        let danFer = (1...18).map { m.skinsPairStrokes("DAN", "FER", hole: $0) }
        #expect(danFer.reduce(0.0) { $0 + $1.b } == 3)       // contra la base (DAN) FER recibe sus 3
    }

    @Test func skinsPayInUnitsOnlyWhenTheCatalogTurnsThemOn() {
        let m = DemoFixture.make()
        zeroStrokes(m)
        m.skinsParticipantAliases = ["DAN", "ROB"]
        m.betCatalog = catalog()
        let without = unitStake(m, "ROB")
        #expect(m.skinsSummary().holes.isEmpty)
        m.betCatalog = medalSkinsCatalog(skins: 2)
        // Con los scores de la demo y sin strokes DAN gana 9 skins y ROB 8 (el 18 queda acumulado sin ganador): +1 × 2 unidades.
        #expect(unitStake(m, "ROB") - without == 2)
        #expect(m.skinsSummary().pending == 1)
        #expect(m.unitLogEntriesForZoom().contains { $0.type == "SKIN" })
    }

    @Test func medalPaysTheLowerNetOfTheWholeRound() {
        let m = DemoFixture.make()
        zeroStrokes(m)
        m.betCatalog = catalog()
        #expect(m.medalOutcome(opponentAlias: "ROB") == nil)  // apagado: no cuenta
        let without = unitStake(m, "ROB")
        m.betCatalog = medalSkinsCatalog(medal: 3)
        // DAN y ROB suman 106 golpes en la demo: sin strokes empatan y no se paga.
        #expect(m.medalOutcome(opponentAlias: "ROB")?.result == 0)
        #expect(unitStake(m, "ROB") - without == 0)
        m.setStrokesVsBase(alias: "ROB", value: -1)           // DAN recibe 1: neto 105 contra 106
        let win = m.medalOutcome(opponentAlias: "ROB")
        #expect(win?.result == 1 && win?.yoNet == 105 && win?.oppNet == 106)
        m.betCatalog = catalog()
        let withoutStroke = unitStake(m, "ROB")
        m.betCatalog = medalSkinsCatalog(medal: 3)
        #expect(unitStake(m, "ROB") - withoutStroke == 3)
        m.setStrokesVsBase(alias: "ROB", value: 1)            // ROB recibe 1: pierde DAN
        #expect(m.medalOutcome(opponentAlias: "ROB")?.result == -1)
        #expect(m.unitLogEntriesForZoom().contains { $0.type == "MEDAL" && $0.units == -3 })
    }

    // MARK: Zapato (ganar todos los Oyes)

    private func zapatoCatalog(units: Int) -> [BetDefinition] {
        catalog() + [BetDefinition(tag: "ZAP", name: "Zapato", type: .individual, mode: .calculado, units: units, description: "")]
    }

    /// Todos los par 3 con Oyes capturado: `winners[i]` gana el i-ésimo par 3 (el otro queda segundo).
    private func setOyes(_ m: MatchManager, winners: [String]) -> [Int] {
        let par3 = m.playOrder().filter { m.getHole($0)?.par == 3 }
        m.oyesRanksByHole = [:]
        for (i, hole) in par3.enumerated() {
            let winner = winners[i % winners.count]
            let other = winner == "DAN" ? "ROB" : "DAN"
            m.setOyesRanks(hole: hole, ranksByAlias: [winner: 1, other: 2])
        }
        return par3
    }

    @Test func zapatoGoesToWhoWinsEveryOyesAtTheLastPar3() {
        let m = DemoFixture.make()
        let par3 = setOyes(m, winners: ["DAN"])
        #expect(par3.count >= 2)
        m.betCatalog = catalog()
        let without = robUnits(m)
        m.betCatalog = zapatoCatalog(units: 3)
        let award = m.zapatoAward()
        #expect(award?.alias == "DAN" && award?.hole == par3.last)
        #expect(robUnits(m) - without == 3)        // el Zapato vale lo que dice el catálogo
        m.betCatalog = zapatoCatalog(units: 5)
        #expect(robUnits(m) - without == 5)
    }

    @Test func zapatoNeedsTheSamePlayerInEveryOyes() {
        let m = DemoFixture.make()
        _ = setOyes(m, winners: ["DAN", "ROB"])    // se reparten los Oyes
        m.betCatalog = zapatoCatalog(units: 3)
        #expect(m.zapatoAward() == nil)
        // Un par 3 sin ganador capturado tampoco cuenta.
        let par3 = setOyes(m, winners: ["DAN"])
        m.clearOyeRank(hole: par3[0], alias: "DAN")
        #expect(m.zapatoAward() == nil)
    }

    @Test func zapatoIsOffWhenTheCatalogTurnsItOffOrOyesIsOff() {
        let m = DemoFixture.make()
        _ = setOyes(m, winners: ["DAN"])
        m.betCatalog = catalog()                   // sin ZAP en el catálogo activo
        #expect(!m.unitLogEntriesForZoom().contains { $0.type == "ZAP" })
        m.betCatalog = zapatoCatalog(units: 3).filter { $0.tag != "OYES" }
        #expect(m.zapatoAward() == nil)            // sin Oyes no hay Zapato
    }

    @Test func switchingOyesOffRemovesItFromTheCalculation() {
        let m = DemoFixture.make()
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") != nil)
        #expect(m.unitLogEntriesForZoom().contains { $0.type.hasPrefix("OYES") })
        m.betCatalog = catalog(without: ["OYES"])
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") == nil)
        #expect(!m.unitLogEntriesForZoom(includePair: false).contains { $0.type.hasPrefix("OYES") })
        #expect(!m.isOyesEnabled)
    }

    @Test func oyesIsWorthWhatTheCatalogSays() {
        let m = DemoFixture.make()
        // En el hoyo 14 DAN (puesto 3) pierde el oye contra ROB (puesto 2): -1 unidad con "Vale 1".
        m.betCatalog = catalog(oyesUnits: 1)
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") == -1)
        m.betCatalog = catalog(oyesUnits: 3)
        #expect(m.oyesIndividualOutcome(hole: 14, opponentAlias: "ROB") == -3)
    }

    @Test func switchingPairOyesOffOnlyAffectsPairs() {
        let m = DemoFixture.make()
        let laneId = m.lanes[0].id
        #expect(m.oyesPairOutcome(hole: 14, laneId: laneId) != nil)
        let individualBefore = robUnits(m)
        m.betCatalog = catalog(without: ["OYESP"])
        #expect(m.oyesPairOutcome(hole: 14, laneId: laneId) == nil)
        #expect(robUnits(m) == individualBefore)
    }

    @Test func matchParejasCannotBeSwitchedOffTheCatalogNeverHidesDefinedPairs() {
        let m = DemoFixture.make()
        let before = m.resultadoRowsV2().filter(\.isPair).count
        #expect(before == 3)
        m.betCatalog = catalog(without: ["PAIR"])          // aunque el tag falte o esté apagado en el catálogo
        #expect(m.isPairMatchEnabled)
        #expect(m.resultadoRowsV2().filter(\.isPair).count == before)
        #expect(m.activeLanes.count == m.lanes.count)
    }

    @Test func theSavedCatalogAlwaysHasMatchParejasOn() {
        // Un catálogo guardado con Match Parejas apagado se vuelve a encender al abrirse, y el editor ya no lo muestra.
        #expect(BetDefinitionStore.shared.entries.first { $0.tag == "PAIR" }?.isEnabled == true)
    }

    @Test func aSwitchedOffManualUnitStopsCountingButKeepsItsEvents() {
        let m = DemoFixture.make()
        let before = robUnits(m)
        m.upsertUnitEvent(hole: 1, alias: "DAN", code: "3P", units: 1)
        #expect(robUnits(m) == before + 1)
        m.betCatalog = catalog(without: ["3P"])
        #expect(robUnits(m) == before)
        #expect(m.unitEventsByHole[1]?.contains { $0.code == "3P" && $0.alias == "DAN" } == true)
        m.betCatalog = catalog()
        #expect(robUnits(m) == before + 1)   // al reactivarla vuelve a contar
    }

    @Test func notesAndUnknownCodesAlwaysCount() {
        let m = DemoFixture.make()
        #expect(m.isUnitCodeActive("NOTA"))
        #expect(m.isUnitCodeActive("4P"))          // no está en el catálogo: no se apaga
        #expect(m.isUnitCodeActive("3P"))
        m.betCatalog = catalog(without: ["3P"])
        #expect(!m.isUnitCodeActive("3P"))
    }

    @Test func builtInUnitsCannotBeDeletedButCustomOnesCan() {
        let store = BetDefinitionStore.shared
        let builtIn = BetDefinition(tag: "OYES", name: "Oyes Rank", type: .individual, mode: .manual, units: 1, description: "")
        let custom = BetDefinition(tag: "SAND", name: "Sandy par", type: .individual, mode: .manual, units: 1, description: "")
        #expect(store.isBuiltIn(builtIn))
        #expect(!store.isBuiltIn(custom))
    }
}

/// El catálogo de CGM sale de la tarjeta impresa vigente: sus totales y sus índices deben cuadrar con lo impreso.
struct CourseCatalogTeesTests {
    private let cgm = CourseCatalog.cgm

    @Test func theIndexesAreTheOnesOnTheCard() {
        // Caballeros: el 13 y el 16 eran 18 y 14 en la app; la tarjeta dice 14 y 18.
        #expect(cgm.holes.map(\.si) == [13, 3, 17, 1, 15, 5, 11, 9, 7, 6, 4, 10, 14, 16, 8, 18, 2, 12])
        #expect(cgm.damasSI == [13, 5, 17, 3, 15, 1, 11, 9, 7, 2, 4, 10, 12, 18, 8, 16, 6, 14])
        #expect(cgm.holes.map(\.si).sorted() == Array(1...18) && cgm.damasSI.sorted() == Array(1...18))
        #expect(cgm.holes.map(\.par) == [4, 5, 3, 4, 3, 5, 4, 4, 4, 4, 5, 4, 4, 3, 4, 3, 5, 4])
    }

    @Test func eachTeeAddsUpToTheTotalsPrintedOnTheCard() {
        let printed: [String: (Int, Int)] = ["azules-h": (3684, 3665), "blancas-h": (3379, 3404), "doradas-h": (3110, 3176),
                                             "verdes-h": (2878, 2876), "plateadas-h": (2217, 2253), "blancas-d": (3379, 3404),
                                             "rojas-d": (2859, 2863), "rosas-d": (2217, 2253)]
        #expect(cgm.tees.count == printed.count)
        for tee in cgm.tees {
            #expect(tee.yards.count == 18)
            let want = printed[tee.id]
            #expect(tee.yards.prefix(9).reduce(0, +) == want?.0 && tee.yards.suffix(9).reduce(0, +) == want?.1)
        }
    }

    @Test func whoLeavesFromTheRedsGetsTheDamasIndexAndTheirOwnDistance() {
        let reds = cgm.tees.first { $0.id == "rojas-d" }
        let blues = cgm.tees.first { $0.id == "azules-h" }
        #expect(cgm.si(hole: 10, tee: reds) == 2 && cgm.si(hole: 13, tee: reds) == 12 && cgm.si(hole: 6, tee: reds) == 1)
        #expect(cgm.si(hole: 10, tee: blues) == 6 && cgm.si(hole: 6, tee: blues) == 5)
        #expect(cgm.si(hole: 10, tee: nil) == 6)                       // sin tee: el de siempre
        #expect(cgm.yards(hole: 3, tee: reds) == 120 && cgm.yards(hole: 3, tee: blues) == 175)
        #expect(cgm.yards(hole: 3, tee: nil) == nil)
    }
}

/// El tee de cada jugador: default del directorio, lo que se elige en el Setup manda y se puede recorrer con el stepper.
struct PlayerTeeTests {
    private let cgm = CourseCatalog.cgm
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "tee-\(UUID().uuidString)")! }

    @Test func theDirectoryTextFindsItsTeeAndDoesNotGuessTheRest() {
        #expect(cgm.tee(named: "Verdes")?.id == "verdes-h")
        #expect(cgm.tee(named: " doradas ")?.id == "doradas-h")
        #expect(cgm.tee(named: "Blancas")?.id == "blancas-h")                // a secas: Caballeros
        #expect(cgm.tee(named: "Blancas (Damas)")?.id == "blancas-d")
        #expect(cgm.tee(named: "Rojas")?.id == "rojas-d")
        for unknown in ["Ajuste", "Verdes / Doradas", "Platino", "", nil] { #expect(cgm.tee(named: unknown) == nil) }
    }

    @Test func theStepperWalksThroughTheTeesAndPassesBySinElegir() {
        var seen: [String] = []
        var tee: TeeModel? = nil
        for _ in 0..<cgm.tees.count + 1 {
            tee = cgm.cycle(from: tee, by: 1)
            seen.append(tee?.id ?? "nil")
        }
        #expect(seen.first == cgm.tees.first?.id && seen.last == "nil" && seen.count == cgm.tees.count + 1)
        #expect(cgm.cycle(from: nil, by: -1)?.id == cgm.tees.last?.id)       // hacia atrás desde "sin elegir" va al último
    }

    @Test func anAliasFindsThePlayerInTheDirectoryAndItsTee() {
        let dir = PlayerDirectoryStore(fileName: "tee-\(UUID().uuidString).json")
        dir.upsert(name: "JL Castro", alias: "JL", strokesVsBase: 0, preferredTagId: nil, opponentTee: "Doradas")
        let d = defaults()
        // Escrito solo "JL" en el Setup: no es el nombre completo, pero sí el alias del directorio.
        #expect(PlayerTeeStore.tee(player: "JL", alias: "JL", in: cgm, defaults: d, directory: dir)?.id == "doradas-h")
        #expect(PlayerTeeStore.tee(player: "JL", in: cgm, defaults: defaults(), directory: dir) == nil)   // sin alias no hay forma de saberlo
        // Cambiarlo en el Setup se guarda también en el directorio, para el siguiente match.
        PlayerTeeStore.set(cgm.tee(named: "Verdes"), player: "JL", alias: "JL", defaults: d, directory: dir)
        #expect(dir.entries.first { $0.alias == "JL" }?.opponentTee == "Verdes")
    }

    @Test func whatIsChosenInTheSetupWinsAndIsRemembered() {
        let d = defaults()
        #expect(PlayerTeeStore.tee(player: "Fernando", in: cgm, defaults: d, directory: nil) == nil)
        PlayerTeeStore.set(cgm.tee(named: "Rojas"), player: "Fernando", defaults: d, directory: nil)
        #expect(PlayerTeeStore.tee(player: "fernando", in: cgm, defaults: d, directory: nil)?.id == "rojas-d")
        PlayerTeeStore.set(nil, player: "Fernando", defaults: d, directory: nil)   // quitarlo a propósito se respeta
        #expect(PlayerTeeStore.tee(player: "Fernando", in: cgm, defaults: d, directory: nil) == nil)
    }
}

/// Los campos de Acapulco salen de las tarjetas (xlsx): forma válida, y el reloj toma par y distancia del campo elegido.
struct AcapulcoCoursesTests {
    @Test func everyCourseHasAValidShape() {
        let courses = CourseCatalog.all
        #expect(courses.map(\.id).count == Set(courses.map(\.id)).count && courses.count == 4)
        for c in courses {
            #expect(c.holes.count == 18 && c.holes.map(\.par).reduce(0, +) == 72)
            #expect(c.holes.map(\.si).sorted() == Array(1...18))
            #expect(!c.tees.isEmpty && c.tees.allSatisfy { $0.yards.count == 18 && $0.yards.allSatisfy { $0 > 0 } })
            #expect(c.tees.map(\.id).count == Set(c.tees.map(\.id)).count)
        }
    }

    @Test func teesGetShorterFromTheBackToTheFront() {
        // Negras ≥ Azules ≥ Blancas ≥ Doradas/Amarillas ≥ Rojas en el total de cada campo.
        for c in [CourseCatalog.turtleDunes, CourseCatalog.tresVidas, CourseCatalog.princessImperial] {
            let totals = c.tees.map { $0.yards.reduce(0, +) }
            #expect(totals == totals.sorted(by: >))
        }
    }

    @MainActor @Test func theWatchContextFollowsTheChosenCourse() {
        let m = DemoFixture.make()
        let slang = VoiceSlangStore(defaults: UserDefaults(suiteName: "ctx-\(UUID().uuidString)")!)
        m.setCourse(CourseCatalog.turtleDunes, resetScores: false)
        defer { MyTeeStore.set(nil, courseId: "TURTLE") }
        MyTeeStore.set("rojas", courseId: "TURTLE")
        let c = WatchCardCoordinator(match: m, currentHole: { 6 }, transcriber: { _, _ in "" },
                                     extractor: { _, _ in VoiceHoleExtraction() }, slang: slang, hasKey: { true })
        let ctx = c.context(course: m.courseName)
        #expect(m.myTeeYardsV2(hole: 6) == 488)                                // el iPhone muestra la misma distancia que el reloj
        #expect(ctx.course == "Turtle Dunes" && ctx.hole == 6 && ctx.par == 5 && ctx.teeDistance == 488)   // hoyo 6 de Turtle Dunes: par 5, 488 desde las rojas
    }
}

extension AcapulcoCoursesTests {
    @Test func tresVidasHoles16To18AreFourThreeFour() {
        let pars = CourseCatalog.tresVidas.holes.map(\.par)
        #expect(Array(pars[15...17]) == [4, 3, 4])
    }
}
