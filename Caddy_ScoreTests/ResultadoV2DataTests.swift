//
//  ResultadoV2DataTests.swift
//  Caddy_ScoreTests
//
//  La pantalla Resultado v2 (P1) debe mostrar EXACTAMENTE los números de la v1. Estas pruebas
//  fijan, con el caso de estudio, lo que entrega MatchManager.resultadoRowsV2(): los mismos
//  valores que ya fija CaseStudyDemo18Tests (F9/B9 vs ROB y el dinero por línea).
//

import Testing
@testable import Caddy_Score

@MainActor
struct ResultadoV2DataTests {

    private func row(_ rows: [MatchManager.ResultadoRowV2], title: String) -> MatchManager.ResultadoRowV2? {
        rows.first { $0.title == title }
    }

    @Test func hasFourIndividualsAndThreePairs() {
        let rows = DemoFixture.make().resultadoRowsV2()
        #expect(rows.filter { !$0.isPair }.count == 4)
        #expect(rows.filter { $0.isPair }.count == 3)
    }

    @Test func robRowMatchesTheCaseStudy() throws {
        let rows = DemoFixture.make().resultadoRowsV2()
        let rob = try #require(row(rows, title: "ROB"))
        #expect(rob.f9Net == 2 && rob.f9Played == 9)
        #expect(rob.b9Net == 4 && rob.b9Played == 9)
        #expect(rob.money == 425)
        // ROB da 8 golpes a DAN: el que recibe es DAN, con 8.
        #expect(rob.strokesReceiver == "DAN")
        #expect(rob.strokesAmount == 8)
    }

    @Test func rivalsWithoutStrokesHaveNoReceiver() throws {
        let rows = DemoFixture.make().resultadoRowsV2()
        let fer = try #require(row(rows, title: "FER"))
        #expect(fer.strokesReceiver == nil)
        #expect(fer.strokesAmount == 0)
        #expect(fer.money == -300)
    }

    @Test func pairRowsAreNamedByDansPartner() throws {
        let rows = DemoFixture.make().resultadoRowsV2()
        let pairs = rows.filter { $0.isPair }
        // En el demo la pareja base es DAN+FER: todas se llaman "con FER".
        #expect(pairs.allSatisfy { $0.title == "con FER" })
        #expect(Set(pairs.compactMap { $0.rivalsText }) == ["ROB – RIC", "ROB – ANS", "RIC – ANS"])
        let ricAns = try #require(pairs.first { $0.rivalsText == "RIC – ANS" })
        #expect(ricAns.strokesReceiver == "ANS")
        #expect(ricAns.strokesAmount == 12)
        #expect(ricAns.money == 200)
    }

    // Presiones y Carry: los valores que la tabla de Resultado de la v1 muestra bajo F9/B9 en el
    // caso de estudio (leídos del simulador).
    @Test func individualPressuresAndCarryMatchV1() throws {
        let rows = DemoFixture.make().resultadoRowsV2()
        let fer = try #require(row(rows, title: "FER"))
        let rob = try #require(row(rows, title: "ROB"))
        let ric = try #require(row(rows, title: "RIC"))
        let ans = try #require(row(rows, title: "ANS"))
        #expect(fer.f9Presiones == [] && fer.b9Presiones == [-3, -1] && fer.carryActive == false)
        #expect(rob.f9Presiones == [] && rob.b9Presiones == [2])
        #expect(rob.carryActive && rob.carryMoney == 100)
        #expect(ric.f9Presiones == [1, -1] && ric.b9Presiones == [])
        #expect(ans.f9Presiones == [] && ans.b9Presiones == [-2])
    }

    @Test func pairPressuresAndCarryMatchV1() throws {
        let pairs = DemoFixture.make().resultadoRowsV2().filter { $0.isPair }
        let robRic = try #require(pairs.first { $0.rivalsText == "ROB – RIC" })
        let robAns = try #require(pairs.first { $0.rivalsText == "ROB – ANS" })
        let ricAns = try #require(pairs.first { $0.rivalsText == "RIC – ANS" })
        #expect(robRic.f9Presiones == [3] && robRic.b9Presiones == [2])
        #expect(robAns.f9Presiones == [2, -2] && robAns.b9Presiones == [4, 1])
        // Carry de pareja activo pero en $0 (la v1 lo muestra como "Carry $0").
        #expect(ricAns.f9Presiones == [] && ricAns.b9Presiones == [-2])
        #expect(ricAns.carryActive && ricAns.carryMoney == 0)
    }

    @Test func totalIsTheSumOfEveryMatch() {
        let m = DemoFixture.make()
        let rows = m.resultadoRowsV2()
        #expect(rows.reduce(0) { $0 + $1.money } == 1225)
        #expect(m.resultadoTotalV2() == 1225)
        // Y coincide con el TOTAL GENERAL de la v1 (walletSnapshot).
        #expect(m.resultadoTotalV2() == m.walletSnapshot().totalMoney)
    }

    @Test func completedHolesCount() {
        #expect(DemoFixture.make().completedHolesCountV2() == 18)
    }

    // Mover la salida a 10 intercambia F9/B9 vs ROB también en la fila de la v2.
    @Test func rowsFollowTheStartHole() throws {
        let m = DemoFixture.make()
        m.updateStartHole(10, resetScores: false)
        let rob = try #require(row(m.resultadoRowsV2(), title: "ROB"))
        #expect(rob.f9Net == 4)
        #expect(rob.b9Net == 2)
        #expect(m.resultadoTotalV2() == 1075)
    }
}
