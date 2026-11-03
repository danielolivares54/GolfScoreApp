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

    @Test func anotatingGivesTheNumericUpdateWithTheSpokenBriefAndExpandsToThePreviousHoles() async {
        let m = DemoFixture.make()
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 9, putts: 3)]))
        await c.receiveAudio(audio)
        c.handle(.apply)
        // El update es lo mismo que "cómo voy" con el hoyo ya anotado, y no se dice en voz alta.
        let expected = m.watchStandingsV2(alias: nil, opponent: nil)
        #expect(c.answer?.lines == expected.lines && c.answer?.title == expected.title)
        #expect(c.answer?.spoken.isEmpty == false)   // el brief hablado: "Vas …"
        // "Ampliar": los hoyos anteriores (el último anotado y los anteriores), con neto donde hay stroke.
        c.handle(.explain)
        #expect(c.answer?.title == m.watchWhyV2(alias: nil, opponent: nil).title)
        #expect(c.answer?.lines.isEmpty == false && c.card().applied != nil)
        // Cerrar o deshacer limpia todo.
        c.handle(.undo)
        #expect(c.answer == nil && c.card().applied == nil)
    }

    @Test func theWatchGetsTheDistanceFromTheTeeTheUserLeavesFrom() {
        let m = DemoFixture.make()
        let c = make(m, VoiceHoleExtraction())
        let course = m.courseId
        defer { MyTeeStore.set(nil, courseId: course) }
        MyTeeStore.set(nil, courseId: course)
        #expect(c.context(course: m.courseName).teeDistance == nil)          // sin tee elegido no se inventa una distancia
        MyTeeStore.set("rojas-d", courseId: course)
        let hole = c.context(course: m.courseName).hole
        let expected = CourseCatalog.all.first { $0.id == course }?.tees.first { $0.id == "rojas-d" }?.yards[hole - 1]
        #expect(expected != nil && c.context(course: m.courseName).teeDistance == expected)
        MyTeeStore.set("azules-h", courseId: course)
        #expect(c.context(course: m.courseName).teeDistance != expected)
    }

    @Test func theWatchGetsTheCardHcpOfTheHoleForTheTeeTheUserLeavesFrom() {
        let m = DemoFixture.make()
        let c = make(m, VoiceHoleExtraction())
        let course = m.courseId
        defer { MyTeeStore.set(nil, courseId: course) }
        MyTeeStore.set(nil, courseId: course)
        let hole = c.context(course: m.courseName).hole
        #expect(c.context(course: m.courseName).hcp == m.getHole(hole)?.si)       // sin tee: el HCP de siempre
        MyTeeStore.set("azules-h", courseId: course)
        #expect(c.context(course: m.courseName).hcp == m.getHole(hole)?.si)       // tee de caballeros: la misma tabla
        if let damas = CourseCatalog.all.first(where: { $0.id == course })?.damasSI, damas.count == 18 {
            MyTeeStore.set("rojas-d", courseId: course)
            #expect(c.context(course: m.courseName).hcp == damas[hole - 1])       // tee de damas: su propia tabla
        }
    }

    @Test func theStandingsShowEveryNumberOfTheMatchAndTheWatchKnowsTheLastDoneHole() {
        let m = DemoFixture.make()
        let answer = m.watchStandingsV2(alias: nil, opponent: nil)
        #expect(!answer.lines.isEmpty)
        for line in answer.lines {
            // Debajo de "3 -1" van todos los números: F9, B9 y el dinero, con las mismas etiquetas en reloj, iPhone e historial.
            let detail = line.detail ?? ""
            #expect(detail.contains("F9") && detail.contains("B9") && detail.contains("$"))
        }
        let c = make(m, VoiceHoleExtraction())
        #expect(c.context(course: m.courseName).lastDone == m.lastHoleHeldV2())
        #expect(m.lastHoleHeldV2() != nil)
    }

    @Test func theWatchOnlyAnswersTheShortMenuAndSendsTheRestToTheIPhone() {
        let m = DemoFixture.make()
        func q(_ tipo: String, detalle: Bool? = nil) -> ReadbackQueryV2 { .init(tipo: tipo, detalle: detalle) }
        for allowed in ["estatus", "explicar", "unidades", "nueve", "strokes"] {
            let a = VoiceHolePipeline.shortAnswer(q(allowed), match: m, currentHole: 6, forWatch: true)
            #expect(a.text != "Eso ábrelo en el iPhone.")
        }
        for blocked in ["dinero", "oyes", "notas", "otro"] {
            #expect(VoiceHolePipeline.shortAnswer(q(blocked), match: m, currentHole: 6, forWatch: true).text == "Eso ábrelo en el iPhone.")
        }
        // El detalle largo (cada apuesta con su dinero) se abre en el iPhone; el iPhone sigue contestándolo.
        #expect(VoiceHolePipeline.shortAnswer(q("estatus", detalle: true), match: m, currentHole: 6, forWatch: true).text == "Eso ábrelo en el iPhone.")
        #expect(VoiceHolePipeline.shortAnswer(q("dinero"), match: m, currentHole: 6, forWatch: false).text != "Eso ábrelo en el iPhone.")
    }

    @Test func theHomeMenuSpeaksTheBriefForStandingsAndIsSilentForTheLastHolesList() {
        let m = DemoFixture.make()
        let c = make(m, VoiceHoleExtraction())
        c.handle(.standings)
        #expect(c.answer?.lines.isEmpty == false && c.answer?.spoken.isEmpty == false)   // "Cómo voy" se dice como brief
        let standings = c.answer?.title
        c.handle(.explain)
        #expect(c.answer?.title != standings && c.answer?.spoken == "")
    }

    @Test func everyStandingsLineCarriesTheStrokesOfThatMatch() {
        let m = DemoFixture.make()
        let rows = m.detailRowsV2(alias: nil, opponent: nil)
        let lines = m.watchStandingsV2(alias: nil, opponent: nil).lines
        #expect(rows.count == lines.count && !rows.isEmpty)
        for (row, line) in zip(rows, lines) {
            #expect((line.detail ?? "").contains("Strokes") == (row.strokesReceiver != nil && row.strokesAmount > 0))
        }
    }

    @Test func withoutASetupTheWatchAsksToConfigureTheMatchOnTheIPhoneFirst() async {
        let empty = MatchManager()
        empty.players = []
        let c = make(empty, VoiceHoleExtraction())
        #expect(c.context(course: empty.courseName).ready == false)
        await c.receiveAudio(audio)
        #expect(c.card().error?.contains("configura el match") == true && c.draft.cells.isEmpty)
        // Con el match armado todo sigue igual.
        let m = DemoFixture.make()
        #expect(make(m, VoiceHoleExtraction()).context(course: m.courseName).ready)
    }

    @Test func theSpokenBriefIsShort() {
        let m = DemoFixture.make()
        // Un solo match: "Vas 3, 1 contra Roberto, al hoyo 8".
        let rob = m.watchStandingsV2(alias: nil, opponent: "ROB")
        let singleMatch = m.detailRowsV2(alias: nil, opponent: "ROB").count == 1
        #expect(singleMatch ? (rob.spoken.hasPrefix("Vas ") && rob.spoken.contains(" contra ")) : rob.spoken.hasPrefix("Al hoyo"))
        // Varios: "Al hoyo 8. …" con un renglón por match, sin letanía.
        let all = m.watchStandingsV2(alias: nil, opponent: nil).spoken
        #expect(all.hasPrefix("Al hoyo"))
        #expect(!all.contains("pareja"))      // las parejas se ven en pantalla, no se dicen
        #expect(all.count < 200)
    }

    @Test func applyIsBlockedWhileThereAreDoubts() async {
        let m = DemoFixture.make()
        let c = make(m, VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 4, putts: nil), .init(jugador: "DAN", gross: 9, putts: nil)]))
        await c.receiveAudio(audio)
        let before = m.getScore(hole: 6, player: "DAN")
        c.handle(.apply)
        #expect(m.getScore(hole: 6, player: "DAN") == before && c.card().applied == nil)
    }

    @Test func aMissingKeyIsAnErrorNotAnEdit() async {
        let m = DemoFixture.make()
        let noKey = WatchCardCoordinator(match: m, currentHole: { 6 }, transcriber: { _, _ in "x" },
                                         extractor: { _, _ in VoiceHoleExtraction() }, hasKey: { false })
        await noKey.receiveAudio(audio)
        #expect(noKey.card().error != nil && noKey.draft.isEmpty)
    }

    @Test func aQuestionIsAnsweredShortAndLeavesTheDraftAlone() async throws {
        let m = DemoFixture.make()
        let asks = WatchCardCoordinator(match: m, currentHole: { 6 }, transcriber: { _, _ in "cómo vamos" },
                                        extractor: { _, _ in VoiceHoleExtraction() }, hasKey: { true })
        await asks.receiveAudio(audio)
        let answer = try #require(asks.answer)
        #expect(asks.card().error == nil && asks.draft.isEmpty && !asks.card().processing)
        #expect(!answer.lines.isEmpty && answer.lines.allSatisfy { !$0.label.isEmpty && !$0.value.isEmpty })
        #expect(answer.spoken.hasPrefix("Al hoyo"))
        #expect(try JSONDecoder().decode(WatchAnswerDTO.self, from: JSONEncoder().encode(answer)) == answer)
        // Otra dictada borra la respuesta vieja.
        await asks.receiveAudio(audio)
        #expect(asks.answer?.id != answer.id)
        asks.handle(.discard)
        #expect(asks.answer == nil)
    }

    @Test func theWhyAnswerListsTheLastThreeHolesPerRival() async throws {
        let m = DemoFixture.make()
        let asks = WatchCardCoordinator(match: m, currentHole: { 6 }, transcriber: { _, _ in "cómo vamos" },
                                        extractor: { _, _ in VoiceHoleExtraction() }, hasKey: { true })
        let why = m.watchWhyV2(alias: nil, opponent: nil)
        #expect(why.title.hasPrefix("Hasta el hoyo") || why.text != nil)
        let holeLines = why.lines.filter { !$0.header && $0.detail != nil }
        let rivals = why.lines.filter(\.header).count
        #expect(holeLines.count <= rivals * MatchManager.whyHolesV2)
        #expect(holeLines.allSatisfy { $0.detail?.hasPrefix("tú") == true || $0.detail?.contains(" vs ") == true })   // individual o pareja
        _ = asks
    }

    @Test func theWhyAnswerEndsAtTheLastAnnotatedHoleWithTheTwoBefore() {
        let m = DemoFixture.make()
        let status = m.watchStandingsV2(alias: nil, opponent: nil)
        // "Hoyo 8 · F9": hasta dónde llega "cómo voy".
        let lastHole = status.title.split(separator: " ").dropFirst().first.flatMap { Int($0) }
        let why = m.watchWhyV2(alias: nil, opponent: nil)
        #expect(lastHole != nil && why.title == "Hasta el hoyo \(lastHole ?? 0)")
        let holeLines = why.lines.filter { !$0.header && $0.detail != nil }
        let holes = holeLines.compactMap { Int($0.label.split(separator: " ").first ?? "") }
        #expect(holes.contains(lastHole ?? 0))                       // el último anotado es el ancla
        let rivals = why.lines.filter(\.header).count
        #expect(holes.count <= rivals * MatchManager.whyHolesV2)    // y los dos anteriores, no más
        // Donde el neto decide, se dice de quién es el stroke.
        for line in holeLines where line.detail?.contains("neto") == true { #expect(line.detail?.contains("stroke") == true) }
        // Desde "cómo voy" y "por qué" se puede corregir el hoyo.
        #expect(VoiceHolePipeline.correctionRoute(for: ReadbackQueryV2(tipo: "estatus"), match: m, currentHole: 6) == .hole(6))
        #expect(VoiceHolePipeline.correctionRoute(for: ReadbackQueryV2(tipo: "explicar"), match: m, currentHole: 6) == .hole(6))
    }

    @Test func theWhyWindowIsAVariableWithADefaultOfThree() {
        let key = "whyHolesV2"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(MatchManager.whyHolesV2 == 3)
        MatchManager.whyHolesV2 = 2
        #expect(MatchManager.whyHolesV2 == 2)
        MatchManager.whyHolesV2 = 99
        #expect(MatchManager.whyHolesV2 == 6)      // tope
        MatchManager.whyHolesV2 = 0
        #expect(MatchManager.whyHolesV2 == 1)      // piso
        let m = DemoFixture.make()
        MatchManager.whyHolesV2 = 1
        let why = m.watchWhyV2(alias: nil, opponent: nil)
        let rivals = why.lines.filter(\.header).count
        #expect(why.lines.filter { !$0.header && $0.detail != nil }.count <= rivals)
    }

    @Test func theDetailExplainsEveryBetWithItsCountAndItsMoney() {
        let m = DemoFixture.make()
        let detail = m.watchDetailV2(alias: nil, opponent: nil)
        let headers = detail.lines.filter(\.header)
        #expect(!headers.isEmpty && headers.allSatisfy { $0.value.contains("$") })          // cada match, con su total
        let bets = detail.lines.filter { !$0.header && $0.label != "Strokes" }
        #expect(bets.allSatisfy { !$0.value.isEmpty && $0.detail != nil })                 // conteo + monetización
        for name in ["F9", "Match", "Unidades"] { #expect(bets.contains { $0.label == name }) }
        #expect(bets.filter { $0.label == "Unidades" }.allSatisfy { $0.detail?.contains("Oyes") == true })
        // En voz solo el total; el resto se lee en pantalla.
        #expect(detail.spoken.hasPrefix("Detalle en pantalla"))
        // "Más detalle" desde cómo voy / por qué llega a la tarjeta.
        let viaQuery = VoiceHolePipeline.shortAnswer(ReadbackQueryV2(tipo: "explicar"), match: m, currentHole: 6, detail: true)
        #expect(viaQuery.title == "Detalle")
    }

    @Test func askingAboutOneRivalOnlyListsThatRival() {
        let m = DemoFixture.make()
        let all = m.watchStandingsV2(alias: nil, opponent: nil).lines
        let rob = m.watchStandingsV2(alias: nil, opponent: "ROB").lines
        #expect(!rob.isEmpty && rob.count < all.count)
        #expect(rob.allSatisfy { $0.label.contains("ROB") })
        // El iPhone abre el detalle del match (uno) o Resultados (varios).
        #expect(VoiceHolePipeline.detailRows(for: ReadbackQueryV2(tipo: "explicar"), match: m).count == m.resultadoRowsV2().count)
        #expect(VoiceHolePipeline.detailRows(for: ReadbackQueryV2(tipo: "explicar", oponente: "ROB"), match: m).count == rob.count)
        #expect(VoiceHolePipeline.isDetailQuery(ReadbackQueryV2(tipo: "explicar")) && !VoiceHolePipeline.isDetailQuery(ReadbackQueryV2(tipo: "dinero")))
    }

    /// Un hoyo par 3 de la demo (los oyes solo se juegan ahí).
    private func parThree(_ m: MatchManager) -> Int { (1...18).first { m.getHole($0)?.par == 3 } ?? 3 }

    @Test func aLongDictationIsReadLocallyWithTheHoleAndTheOyes() async throws {
        let m = DemoFixture.make()
        let slang = VoiceSlangStore(defaults: UserDefaults(suiteName: "local-\(UUID().uuidString)")!)
        let h = parThree(m)
        let said = "Hoyo \(h), yo tiro par, Rob par, Ans 4, Ric 5, Fer 6, yo soy el 1 en oyes, Rob 2, Ans 3, Ric 4, Fer 5."
        let local = VoiceHolePipeline.localExtraction(said, match: m, slang: slang)
        #expect(local?.hoyo == h && local?.scores.count == 5)          // sin llamar al modelo
        // El mismo dictado de punta a punta: hoyo, scores y los cinco lugares de oyes (yo primero).
        let draft = try await VoiceHolePipeline.propose(transcript: said, match: m, defaultHole: 1, slang: slang,
                                                        extractor: { t, _ in VoiceHolePipeline.localExtraction(t, match: m, slang: slang) ?? VoiceHoleExtraction() })
        let par = try #require(m.getHole(h)?.par)
        #expect(draft.hole == h)                                      // el hoyo que dijo, no el de la pantalla
        #expect(draft.cells[m.yoAlias]?.gross == par && draft.cells["ANS"]?.gross == 4 && draft.cells["FER"]?.gross == 6)
        #expect(draft.oyes[m.yoAlias] == 1 && draft.oyes["ROB"] == 2 && draft.oyes["ANS"] == 3 && draft.oyes["RIC"] == 4 && draft.oyes["FER"] == 5)
        #expect(draft.doubts.isEmpty)
        // Preguntas y frases libres no se leen aquí: las decide el modelo.
        #expect(VoiceHolePipeline.localExtraction("cómo voy con Rob", match: m, slang: slang) == nil)
        #expect(VoiceHolePipeline.localExtraction("Rob cuatro y se enojó con el caddie", match: m, slang: slang) == nil)
    }

    @Test func theHoleSaidInTheTextWinsOverTheScreenAndTheModel() async throws {
        let m = DemoFixture.make()
        let slang = VoiceSlangStore(defaults: UserDefaults(suiteName: "hoyo-\(UUID().uuidString)")!)
        // El modelo no devolvió el hoyo y la pantalla estaba en el 1: manda lo dicho.
        let draft = try await VoiceHolePipeline.propose(transcript: "Hoyo 16 yo cuatro", match: m, defaultHole: 1, slang: slang,
                                                        extractor: { _, _ in VoiceHoleExtraction(scores: [.init(jugador: "yo", gross: 4, putts: nil)]) })
        #expect(draft.hole == 16)
        // "Del hoyo 5 al 8" es una corrida, no el hoyo en juego.
        #expect(VoiceHolePipeline.holeFromText("del hoyo 5 al 8 daniel par") == nil)
        #expect(VoiceHolePipeline.holeFromText("hoyo diez y seis yo par") == 16)
    }

    @Test func theDictatedHoleMovesTheScreenButAnnotatingDoesNot() async {
        let m = DemoFixture.make()
        let slang = VoiceSlangStore(defaults: UserDefaults(suiteName: "dictado-\(UUID().uuidString)")!)
        func coordinator(said: String, screen: Int) -> WatchCardCoordinator {
            WatchCardCoordinator(match: m, currentHole: { screen }, transcriber: { _, _ in said },
                                 extractor: { _, _ in VoiceHoleExtraction(scores: [.init(jugador: "DAN", gross: 4, putts: nil)]) },
                                 slang: slang, hasKey: { true })
        }
        // Dictó el 12 con la pantalla en el 6: la pantalla se lleva al 12.
        var moved: [Int] = []
        let a = coordinator(said: "hoyo 12 daniel cuatro", screen: 6)
        a.onHoleDictated = { moved.append($0) }
        await a.receiveAudio(audio)
        #expect(moved == [12])
        // Anotar no mueve nada: el hoyo siguiente lo decide el iPhone.
        a.handle(.apply)
        #expect(moved == [12])
        // Sin decir hoyo (es el de la pantalla) tampoco se mueve.
        var again: [Int] = []
        let b = coordinator(said: "daniel cuatro", screen: 6)
        b.onHoleDictated = { again.append($0) }
        await b.receiveAudio(audio)
        #expect(again.isEmpty)
    }

    @Test func everyoneParIncludesWhoIsDictating() async throws {
        let m = DemoFixture.make()
        let slang = VoiceSlangStore(defaults: UserDefaults(suiteName: "todos-\(UUID().uuidString)")!)
        let others = m.players.map(\.alias).filter { $0 != m.yoAlias }
        func score(_ alias: String) -> VoiceHoleExtraction.Score { .init(jugador: alias, gross: nil, putts: nil, relativo: "par") }
        func propose(_ said: String, _ scores: [VoiceHoleExtraction.Score]) async throws -> VoiceHoleDraft {
            try await VoiceHolePipeline.propose(transcript: said, match: m, defaultHole: 10, slang: slang,
                                                extractor: { _, _ in VoiceHoleExtraction(scores: scores) })
        }
        let par = try #require(m.getHole(10)?.par)
        // El modelo contestó "los demás": todos, incluido yo.
        let rest = try await propose("Todos tiraron par.", [score("DEMAS")])
        #expect(m.players.allSatisfy { rest.cells[$0.alias]?.gross == par })
        // El modelo enumeró solo a los otros: "todos" me incluye igual.
        let listed = try await propose("Todos tiraron par.", others.map(score))
        #expect(m.players.allSatisfy { listed.cells[$0.alias]?.gross == par })
        // "Todos menos yo": yo no entro.
        let without = try await propose("Todos menos yo tiraron par.", others.map(score))
        #expect(without.cells[m.yoAlias] == nil)
    }

    @Test func theShortAnswerIsJustNamesAndNumbers() {
        let m = DemoFixture.make()
        let status = VoiceHolePipeline.shortAnswer(ReadbackQueryV2(tipo: "estatus"), match: m, currentHole: 6)
        #expect(!status.lines.isEmpty && status.text == nil)
        #expect(status.lines.allSatisfy { !$0.value.isEmpty })
        // Dicho en voz alta: nombres y números, sin la letanía de "arriba", "abajo", "presión", "más".
        #expect(status.spoken.hasPrefix("Al hoyo"))
        for word in ["arriba", "abajo", "presión", "presiones", "más", "pesos"] { #expect(!status.spoken.contains(word)) }
        // Con detalle es la tarjeta: cada apuesta con su conteo y su dinero.
        let long = VoiceHolePipeline.shortAnswer(ReadbackQueryV2(tipo: "estatus", detalle: true), match: m, currentHole: 6)
        #expect(long.title == "Detalle" && !long.lines.isEmpty)
        // Una pregunta que no es de estatus ni de por qué sigue siendo texto.
        #expect(VoiceHolePipeline.shortAnswer(ReadbackQueryV2(tipo: "dinero"), match: m, currentHole: 6).text != nil)
        #expect(VoiceHolePipeline.isStatusQuery(ReadbackQueryV2(tipo: "estatus")))
        #expect(!VoiceHolePipeline.isStatusQuery(ReadbackQueryV2(tipo: "estatus", hoyo: 5)))
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
