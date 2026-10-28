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
