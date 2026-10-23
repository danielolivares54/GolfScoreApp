//
//  MyHistoryDataTests.swift
//  Caddy_ScoreTests
//
//  Las cifras de "Mi Historial" salen de MyHistoryData (movido tal cual desde MyHistoryView para que la v1 y
//  la v2 usen las mismas fórmulas). Se fijan con una ronda cerrada sintética en el CGM.
//

import Foundation
import Testing
@testable import Caddy_Score

struct MyHistoryDataTests {

    /// DAN hace par en los hoyos 1–9 y bogey en los 10–18, con 2 putts en todos; ROB le da 2 strokes.
    private func makeRound(startHole: Int = 1, oyes: Int = 2) -> RoundResultFile {
        let course = CourseCatalog.default
        var danScores: [String: Int] = [:], danPutts: [String: Int] = [:], robScores: [String: Int] = [:]
        for hole in course.holes {
            let extra = hole.number >= 10 ? 1 : 0
            danScores["\(hole.number)"] = hole.par + extra
            danPutts["\(hole.number)"] = 2
            robScores["\(hole.number)"] = hole.par       // ROB hace par en todo
        }
        func line(_ scope: String, _ money: Int) -> RoundResultLine {
            RoundResultLine(label: scope, scope: scope, opponentAlias: scope == "individual" ? "ROB" : nil,
                            vueltaPoints: 0, presionPoints: 0, carryPoints: 0, carryActive: false, matchPoints: 0,
                            unitsPoints: 0, vueltaMoney: 0, presionMoney: 0, carryMoney: 0, matchMoney: 0,
                            unitsMoney: 0, totalMoney: money)
        }
        return RoundResultFile(
            roundId: "test-\(startHole)", date: "21 oct", courseId: course.id, courseName: course.name,
            startHole: startHole,
            players: [
                RoundResultPlayer(alias: "DAN", name: "Daniel", strokesVsBase: 0, scores: danScores, putts: danPutts),
                RoundResultPlayer(alias: "ROB", name: "Roberto", strokesVsBase: -2, scores: robScores, putts: [:]),
            ],
            lines: [line("individual", 300), line("parejas", -100)],
            totalMoney: 200, closedAt: Date(), oyesWinsByAlias: ["DAN": oyes])
    }

    @Test func figuresOfOneRound() throws {
        let f = try #require(MyHistoryData.figures(for: makeRound()))
        #expect(f.strokesF9 == 36)
        #expect(f.strokesB9 == 45)
        #expect(f.strokesTotal == 81)
        #expect(f.puttsF9 == 18 && f.puttsB9 == 18 && f.puttsTotal == 36)
        #expect(f.counts.par == 9 && f.counts.bogey == 9)
    }

    @Test func ninesFollowTheStartHoleOfTheRound() throws {
        // Saliendo en el 10, el primer nueve jugado son los hoyos 10–18 (los bogeys).
        let f = try #require(MyHistoryData.figures(for: makeRound(startHole: 10)))
        #expect(f.strokesF9 == 45)
        #expect(f.strokesB9 == 36)
    }

    @Test func incompleteNineIsNotAveraged() throws {
        var round = makeRound()
        let dan = round.players[0]
        var scores = dan.scores
        scores.removeValue(forKey: "5")
        round = RoundResultFile(
            roundId: round.roundId, date: round.date, courseId: round.courseId, courseName: round.courseName,
            startHole: 1,
            players: [RoundResultPlayer(alias: "DAN", name: "Daniel", strokesVsBase: 0, scores: scores, putts: dan.putts),
                      round.players[1]],
            lines: round.lines, totalMoney: round.totalMoney, closedAt: round.closedAt, oyesWinsByAlias: nil)
        let f = try #require(MyHistoryData.figures(for: round))
        #expect(f.strokesF9 == nil)
        #expect(f.strokesTotal == nil)
        #expect(f.strokesB9 == 45)
    }

    @Test func lifetimeStatsAddUpTheRounds() {
        let stats = MyHistoryData.stats(for: [makeRound(), makeRound(startHole: 10, oyes: 1)])
        #expect(stats.matchesCounted == 2)
        #expect(stats.counts.par == 18 && stats.counts.bogey == 18)
        #expect(stats.oyesWins == 3)
        #expect(stats.moneyIndividual == 600 && stats.moneyParejas == -200 && stats.moneyTotal == 400)
    }

    @Test func parTypeAveragesAreComputedPerHoleType() throws {
        let stats = MyHistoryData.stats(for: [makeRound()])
        // Cada tipo de hoyo tiene algunos pares (hoyos 1–9) y algunos bogeys (10–18): promedio entre 0 y 1.
        for par in [3, 4, 5] {
            let avg = try #require(stats.average(forPar: par))
            #expect(avg > 0 && avg < 1)
        }
    }

    @Test func strokeImpactCountsTheHolesWhereDanReceives() {
        // ROB da 2 strokes a DAN (negativo): hay hoyos donde DAN recibe y se clasifican (decidió / no fue factor).
        let stats = MyHistoryData.stats(for: [makeRound()])
        #expect(stats.receiveTotal == 2)
        #expect(stats.giveTotal == 0)
    }

    // MARK: Promedio, desviación estándar y porcentajes

    @Test func spreadNeedsTwoRoundsForTheDeviation() {
        #expect(MyHistoryData.spread([]) == nil)
        #expect(MyHistoryData.spread([4]) == MyHistoryData.Spread(mean: 4, std: nil))
        let two = MyHistoryData.spread([2, 4])
        #expect(two?.mean == 3)
        #expect(two?.std == 1)           // población: sqrt(((2-3)² + (4-3)²) / 2)
    }

    @Test func percentOfHolesPerRound() throws {
        let f = try #require(MyHistoryData.figures(for: makeRound()))
        #expect(f.counts.total == 18)
        #expect(MyHistoryData.percent(f.counts, \.par) == 50)
        #expect(MyHistoryData.percent(f.counts, \.bogey) == 50)
        #expect(MyHistoryData.percent(f.counts, \.birdie) == 0)
    }

    @Test func percentSpreadAcrossRounds() {
        // Una ronda con 9 pares y 9 bogeys (50 % / 50 %) y otra de solo bogeys (0 % pares): promedio 25 %, desviación 25.
        let flat = makeRound()
        let allBogey = RoundResultFile(
            roundId: "b", date: flat.date, courseId: flat.courseId, courseName: flat.courseName, startHole: 1,
            players: [RoundResultPlayer(alias: "DAN", name: "Daniel", strokesVsBase: 0,
                                        scores: Dictionary(uniqueKeysWithValues: CourseCatalog.default.holes.map { ("\($0.number)", $0.par + 1) }),
                                        putts: [:])],
            lines: [], totalMoney: 0, closedAt: Date(), oyesWinsByAlias: nil)
        let spread = MyHistoryData.percentSpread(rounds: [flat, allBogey], \.par)
        #expect(spread?.mean == 25)
        #expect(spread?.std == 25)
        #expect(MyHistoryData.percentSpread(rounds: [flat], \.par)?.std == nil)
    }

    @Test func figureSpreadAveragesStrokesPerNine() {
        let spread = MyHistoryData.figureSpread(rounds: [makeRound(), makeRound(startHole: 10)], \.strokesF9)
        // F9 = 36 en la primera ronda y 45 en la que sale del 10: promedio 40.5.
        #expect(spread?.mean == 40.5)
        #expect(spread?.std == 4.5)
    }

    @Test func moneyOfOneRoundSplitsIndividualAndPairs() {
        let money = MyHistoryData.money(for: makeRound())
        #expect(money.individual == 300 && money.parejas == -100 && money.total == 200)
    }
}
