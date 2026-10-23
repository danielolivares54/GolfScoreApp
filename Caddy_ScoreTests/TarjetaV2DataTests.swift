//
//  TarjetaV2DataTests.swift
//  Caddy_ScoreTests
//
//  Tarjeta v2 (P2): los datos de la tabla salen de MatchManager.tarjetaNinesV2(). Se fijan, con el
//  caso de estudio, los nueves en orden de juego, los totales, los puntos de golpe (misma regla que
//  la v1: solo rivales que reciben; la columna de yo no lleva) y el marcador dorado de oye/evento.
//

import Testing
@testable import Caddy_Score

@MainActor
struct TarjetaV2DataTests {

    // Orden de columnas = orden de players en el demo: DAN, FER, ROB, RIC, ANS.
    private let dan = 0, fer = 1

    private func dots(_ nine: MatchManager.TarjetaNineV2, column: Int) -> Set<Int> {
        Set(nine.holes.filter { $0.cells[column].strokes > 0 }.map { $0.hole })
    }

    @Test func ninesAtStartOne() {
        let nines = DemoFixture.make().tarjetaNinesV2()
        #expect(nines.map(\.title) == ["F9 · 1–9", "B9 · 10–18"])
        #expect(nines.map { $0.holes.map(\.hole) } == [Array(1...9), Array(10...18)])
        #expect(nines.map(\.parTotal) == [36, 36])
    }

    @Test func ninesFollowTheStartHole() {
        let m = DemoFixture.make()
        m.updateStartHole(10, resetScores: false)
        let nines = m.tarjetaNinesV2()
        #expect(nines.map(\.title) == ["F9 · 10–18", "B9 · 1–9"])
        // Daniel: 48 en los hoyos 1–9 y 58 en los 10–18, ahora al revés.
        #expect(nines[0].grossTotals[dan] == 58)
        #expect(nines[1].grossTotals[dan] == 48)
    }

    @Test func grossTotalsAtStartOne() {
        let nines = DemoFixture.make().tarjetaNinesV2()
        #expect(nines[0].grossTotals[dan] == 48)
        #expect(nines[1].grossTotals[dan] == 58)
    }

    @Test func rangeTextWrapsAroundWithoutPlus() {
        #expect(MatchManager.rangeTextV2(Array(10...18)) == "10–18")
        #expect(MatchManager.rangeTextV2(Array(14...18) + Array(1...4)) == "14–18, 1–4")
        #expect(MatchManager.rangeTextV2([7]) == "7")
    }

    @Test func emptyHolesHaveNoGross() {
        let m = DemoFixture.make()
        m.resetScores()
        let nines = m.tarjetaNinesV2()
        #expect(nines.allSatisfy { $0.grossTotals.allSatisfy { $0 == nil } })
        #expect(nines[0].holes[0].cells[dan].gross == nil)
    }

    // En el demo nadie recibe de yo (ROB da 8 a yo): ningún punto de golpe, igual que la v1.
    @Test func noStrokeDotsWhenNobodyReceivesFromDan() {
        let nines = DemoFixture.make().tarjetaNinesV2()
        for nine in nines {
            for hole in nine.holes { #expect(hole.cells.allSatisfy { $0.strokes == 0 }) }
        }
    }

    // Un rival que recibe 3 golpes: los puntos van a SU columna, nunca a la de yo, y se reparten
    // por el orden de juego (alternando primer y segundo nueve jugado).
    @Test func receivingRivalGetsDotsThatFollowTheStartHole() {
        let m = DemoFixture.make()
        m.setStrokesVsBase(alias: "FER", value: 3)
        var nines = m.tarjetaNinesV2()
        #expect(dots(nines[0], column: fer) == [2, 4])       // F9 = 1–9
        #expect(dots(nines[1], column: fer) == [17])         // B9 = 10–18
        #expect(dots(nines[0], column: dan).isEmpty && dots(nines[1], column: dan).isEmpty)

        m.updateStartHole(10, resetScores: false)
        nines = m.tarjetaNinesV2()
        #expect(dots(nines[0], column: fer) == [11, 17])     // F9 = 10–18 recibe 2 de los 3
        #expect(dots(nines[1], column: fer) == [4])          // B9 = 1–9
    }

    @Test func halfStrokeIsMarkedAsHalf() {
        let m = DemoFixture.make()
        m.setStrokesVsBase(alias: "FER", value: 0.5)
        let nines = m.tarjetaNinesV2()
        let halves = nines.flatMap(\.holes).filter { $0.cells[fer].strokes == 0.5 }.map(\.hole)
        #expect(halves == [4])   // el medio golpe va al hoyo de SI 1 (hoyo 4)
    }

    // Oye ganado (rank 1) en los par 3 del demo: FER en el 14 y el 16 lleva el cuadro dorado.
    @Test func oyesWinnerGetsTheEventMarker() {
        let nines = DemoFixture.make().tarjetaNinesV2()
        let byHole = Dictionary(uniqueKeysWithValues: nines.flatMap(\.holes).map { ($0.hole, $0) })
        #expect(byHole[14]?.cells[fer].hasEvent == true)
        #expect(byHole[16]?.cells[fer].hasEvent == true)
        #expect(byHole[1]?.cells[fer].hasEvent == false)
        #expect(byHole[1]?.cells[dan].hasEvent == false)
    }

    // MARK: Putts (Paso 5)

    @Test func puttsCellsAndTotalsMatchTheManager() {
        let m = DemoFixture.make()
        let nines = m.tarjetaNinesV2()
        for nine in nines {
            for (i, player) in m.players.enumerated() {
                let expected = nine.holes.map { m.getPutts(hole: $0.hole, player: player.alias) }.filter { $0 > 0 }
                #expect(nine.puttsTotals[i] == (expected.isEmpty ? nil : expected.reduce(0, +)))
                for hole in nine.holes {
                    let value = m.getPutts(hole: hole.hole, player: player.alias)
                    #expect(hole.cells[i].putts == (value > 0 ? value : nil))
                }
            }
        }
    }

    @Test func danPuttsAreRecordedAndSummed() {
        let m = DemoFixture.make()
        for (hole, putts) in [(1, 2), (2, 3), (3, 2)] {
            m.applyHoleEntry(HoleEntryData(hole_number: hole, player_alias: "DAN",
                                           strokes: m.getScore(hole: hole, player: "DAN"),
                                           putts: putts, units: nil, tags: nil))
        }
        let f9 = m.tarjetaNinesV2()[0]
        #expect(f9.holes[0].cells[dan].putts == 2)
        #expect(f9.holes[1].cells[dan].putts == 3)
        #expect(f9.holes[3].cells[dan].putts == nil)
        #expect(f9.puttsTotals[dan] == 7)
    }

    @Test func puttsFollowTheStartHole() {
        let m = DemoFixture.make()
        m.applyHoleEntry(HoleEntryData(hole_number: 1, player_alias: "DAN",
                                       strokes: m.getScore(hole: 1, player: "DAN"),
                                       putts: 2, units: nil, tags: nil))
        let before = m.tarjetaNinesV2()
        m.updateStartHole(10, resetScores: false)
        let after = m.tarjetaNinesV2()
        // Los mismos putts, pero los nueves se intercambian con la salida en el 10.
        #expect(after[0].puttsTotals == before[1].puttsTotals)
        #expect(after[1].puttsTotals == before[0].puttsTotals)
    }

    @Test func holesWithoutPuttsHaveNone() {
        let m = DemoFixture.make()
        let hole = m.tarjetaNinesV2()[0].holes[0].hole
        m.applyHoleEntry(HoleEntryData(hole_number: hole, player_alias: "ANS", strokes: 4, putts: 0, units: nil, tags: nil))
        let cell = m.tarjetaNinesV2()[0].holes[0].cells[4]
        #expect(cell.putts == nil)
    }

    // MARK: Strokes por hoyo de cada match

    @Test func individualMatchStrokesGoToTheReceiver() {
        let m = DemoFixture.make()
        let byHole = m.matchStrokesByHoleV2(.individual("ROB"))
        // ROB da 8 a DAN: 8 hoyos con strokes, todos para DAN y ninguno para ROB.
        #expect(byHole.count == 8)
        #expect(byHole.values.allSatisfy { Set($0.keys) == [m.yoAlias] })
        #expect(byHole.values.reduce(0.0) { $0 + ($1[m.yoAlias] ?? 0) } == 8)
        #expect(m.matchParticipantsV2(.individual("ROB")) == [m.yoAlias, "ROB"])
    }

    @Test func aMatchWithoutStrokesHasNoHighlights() {
        let m = DemoFixture.make()
        #expect(m.matchStrokesByHoleV2(.individual("RIC")).isEmpty)
    }

    @Test func pairMatchStrokesGoToTheCarrier() {
        let m = DemoFixture.make()
        // La pareja RIC–ANS lleva 12 strokes (los lleva ANS): un solo jugador los recibe.
        guard let lane = m.lanes.first(where: { Set($0.opp) == ["RIC", "ANS"] }) else { Issue.record("sin carril"); return }
        let byHole = m.matchStrokesByHoleV2(.pair(lane.id))
        let receivers = Set(byHole.values.flatMap { $0.keys })
        #expect(receivers.count == 1)
        let total = byHole.values.reduce(0.0) { $0 + ($1.values.reduce(0, +)) }
        // Los 12 del Setup, más el stroke extra que suma el Carry de B9 cuando está activo.
        #expect(total >= lane.strokes)
    }
}
