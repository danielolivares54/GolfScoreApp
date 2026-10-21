//
//  MatchDetailV2DataTests.swift
//  Caddy_ScoreTests
//
//  Detalle de un match en la Vista v2: debe traer TODO lo que muestra la v1 (tabla de conceptos, línea
//  de strokes, estado y botones de Carry / Ajuste 50 / Doble B9) y las acciones deben hacer lo mismo que
//  los botones de la v1. Valores del caso de estudio (los mismos que la pantalla de la v1 en el simulador).
//

import Testing
@testable import Caddy_Score

@MainActor
struct MatchDetailV2DataTests {

    private func row(_ m: MatchManager, title: String? = nil, rivals: String? = nil) throws -> MatchManager.ResultadoRowV2 {
        let rows = m.resultadoRowsV2()
        return try #require(rows.first { r in
            if let title, r.title == title { return true }
            if let rivals, r.rivalsText == rivals { return true }
            return false
        })
    }

    private func conceptNames(_ resumen: MatchResumen) -> [String] { resumen.filas.map(\.nombre) }

    // El total de la tabla del match = el dinero de esa línea de la billetera, para los 7 matches.
    @Test func everyMatchTotalEqualsItsWalletLine() throws {
        let m = DemoFixture.make()
        for r in m.resultadoRowsV2() {
            let resumen = try #require(m.matchResumenV2(for: r.target))
            #expect(resumen.total == r.money, "\(r.title) \(r.rivalsText ?? "")")
        }
    }

    @Test func robConceptTableMatchesV1() throws {
        let m = DemoFixture.make()
        let r = try row(m, title: "ROB")
        let resumen = try #require(m.matchResumenV2(for: r.target))
        #expect(resumen.strokes == 8 && resumen.tag == 50)
        #expect(resumen.carryActivo && resumen.dobleB9)
        // F9, B9 ×2 (Doble B9), Match, Carry, Unidades — como la tabla de la v1.
        #expect(conceptNames(resumen) == ["F9", "B9 ×2", "Match", "Carry", "Unidades"])
        #expect(resumen.f9.chips == ["+2"] && resumen.f9.monto == 50)
        #expect(resumen.b9.chips == ["+4", "+2"] && resumen.b9.monto == 200)
        #expect(resumen.match.chips == ["+6"] && resumen.match.monto == 50)
        #expect(resumen.carry.chips == ["+3", "+1"] && resumen.carry.monto == 100)
        #expect(resumen.unidades.chips == ["+1"] && resumen.unidades.monto == 25)
        #expect(resumen.total == 425)
    }

    @Test func pairConceptTableMatchesV1() throws {
        let m = DemoFixture.make()
        let r = try row(m, rivals: "RIC – ANS")
        let resumen = try #require(m.matchResumenV2(for: r.target))
        #expect(resumen.strokes == 12 && resumen.carryActivo && !resumen.dobleB9)
        #expect(resumen.f9.chips == ["+3"] && resumen.f9.monto == 50)
        #expect(resumen.b9.chips == ["+2", "-2"] && resumen.b9.monto == 0)   // la v1 usa el signo "-" ASCII
        #expect(resumen.carry.monto == 0)
        #expect(resumen.total == 200)
    }

    @Test func strokesSummaryLineIsTheV1Line() throws {
        let m = DemoFixture.make()
        let rob = try row(m, title: "ROB")
        let pair = try row(m, rivals: "RIC – ANS")
        #expect(m.strokesSummaryV2(for: rob.target) == "DAN F9 8/4 · B9 8/4 → DAN 7/3 C+3")
        #expect(m.strokesSummaryV2(for: pair.target) == "ANS F9 12/6 · B9 12/6 → ANS 13/7 C+1")
    }

    // MARK: Estado de los botones

    @Test func refreshStateOfRobAndPair() throws {
        let m = DemoFixture.make()
        let rob = m.refreshStateV2(for: try row(m, title: "ROB").target)
        #expect(rob.carryActive && rob.doublePressActive && !rob.adjust50Active && !rob.f9Tied)
        #expect(rob.carryRequester == "ROB")
        #expect(rob.statusText == "Carry B9 activo · ROB")

        let pair = m.refreshStateV2(for: try row(m, rivals: "RIC – ANS").target)
        #expect(pair.carryActive && !pair.doublePressActive)
        #expect(pair.carryRequester == "ANS")
        #expect(pair.candidates == ["RIC", "ANS"])
    }

    @Test func secondNineIsInPlay() {
        #expect(DemoFixture.make().currentSegmentV2 == "B9")
        let m = DemoFixture.make()
        m.resetScores()
        #expect(m.currentSegmentV2 == "F9")
    }

    // MARK: Acciones (las mismas que los botones de la v1)

    @Test func adjust50SwitchesCarryOffAndBack() throws {
        let m = DemoFixture.make()
        let target = try row(m, title: "ROB").target
        m.toggleAdjust50V2(for: target)
        var state = m.refreshStateV2(for: target)
        #expect(state.adjust50Active && !state.carryActive)
        #expect(state.statusText == "Ajuste 50 activo")

        m.toggleCarryV2(for: target, requester: nil)      // Carry apaga Ajuste 50
        state = m.refreshStateV2(for: target)
        #expect(state.carryActive && !state.adjust50Active)

        m.toggleCarryV2(for: target, requester: nil)      // tocar Carry otra vez lo cancela
        #expect(m.refreshStateV2(for: target).carryActive == false)
    }

    @Test func doublePressToggles() throws {
        let m = DemoFixture.make()
        let target = try row(m, title: "ROB").target
        #expect(m.refreshStateV2(for: target).doublePressActive)
        m.toggleDoublePressV2(for: target)
        #expect(m.refreshStateV2(for: target).doublePressActive == false)
        #expect(try #require(m.matchResumenV2(for: target)).filas.map(\.nombre).contains("B9"))   // sin ×2
        m.toggleDoublePressV2(for: target)
        #expect(m.refreshStateV2(for: target).doublePressActive)
    }

    @Test func pairCarryUsesTheChosenPartner() throws {
        let m = DemoFixture.make()
        let r = try row(m, rivals: "RIC – ANS")
        guard case .pair(let laneId) = r.target else { Issue.record("no es pareja"); return }
        m.toggleCarryV2(for: r.target, requester: nil)               // lo apaga
        #expect(m.refreshStateV2(for: r.target).carryActive == false)
        m.toggleCarryV2(for: r.target, requester: "RIC")             // lo activa para RIC
        #expect(m.pairCarryRequesterByLane[laneId] == "RIC")
    }

    // MARK: Enlaces

    @Test func unitLogHasEntriesForRob() throws {
        let m = DemoFixture.make()
        let target = try row(m, title: "ROB").target
        let entries = m.unitLogEntriesV2(target, segment: "ALL")
        #expect(!entries.isEmpty)
        #expect(entries.map(\.hole) == entries.map(\.hole).sorted())
        #expect(m.unitLogTitleV2(target) == "Unidades · DAN vs ROB")
    }
}
