//
//  MyHistoryV2.swift
//  Caddie Score — Vista v2, Paso 9: mis estadísticas (Acumulado = promedio ± desviación · Este match = porcentajes)
//
//  Mismas cifras que MyHistoryView: salen de MyHistoryData (las fórmulas se movieron tal cual para compartirlas).
//  Datos: histograma de resultados, golpes (medal, bruto) y putts por nueve, promedio vs par por tipo de hoyo,
//  impacto del stroke y oyes/dinero acumulados.
//

import SwiftUI

struct MyHistoryV2: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rounds: [RoundResultFile] = []
    /// Solo para vistas previas: rondas de muestra en lugar de leer closed_rounds del disco.
    private let sampleRounds: [RoundResultFile]?

    init(sampleRounds: [RoundResultFile]? = nil) { self.sampleRounds = sampleRounds }

    private var stats: MyHistoryData.Stats { MyHistoryData.stats(for: rounds) }
    /// rounds viene de la más nueva a la más vieja: first = último match cerrado.
    private var lastFigures: MyHistoryData.RoundFigures? { rounds.first.flatMap { MyHistoryData.figures(for: $0) } }

    var body: some View {
        let stats = self.stats
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header(matches: stats.matchesCounted)
                ScrollView {
                    VStack(spacing: CSV2.s2) {
                        if rounds.isEmpty {
                            Text("Sin rondas cerradas todavía").font(.v2Body).foregroundStyle(CSV2.secondary)
                                .frame(maxWidth: .infinity).padding(CSV2.s3)
                        } else {
                            histogramCard(stats)
                            strokesPuttsCard
                            parTypeCard(stats)
                            strokeImpactCard(stats)
                            moneyCard(stats)
                        }
                    }
                    .padding(CSV2.s2)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // columnas de ancho fijo: la tabla crece hasta XXXL
        .onAppear { rounds = sampleRounds ?? RoundResultFile.loadAll() }
    }

    private func header(matches: Int) -> some View {
        HStack {
            BackButtonV2 { dismiss() }
            Spacer()
            Text("Mi historial · \(matches) match\(matches == 1 ? "" : "es")").font(.v2Name).foregroundStyle(CSV2.ink)
        }
        .padding(.horizontal, CSV2.s2)
    }

    // MARK: Piezas

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        CardV2 {
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).capsStyleV2()
    }

    private func columnHeader(_ accumulated: String, last: String = "Este match") -> some View {
        HStack {
            Spacer()
            Text(accumulated).frame(width: 112, alignment: .trailing)
            Text(last).frame(width: 84, alignment: .trailing)
        }
        .capsStyleV2()
    }

    private func twoColRow(_ label: String, acc: String, last: String, color: Color = CSV2.ink) -> some View {
        HStack {
            Text(label).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            Text(acc).font(.system(.body, weight: .bold).monospacedDigit()).foregroundStyle(color)
                .frame(width: 112, alignment: .trailing)
            Text(last).font(.system(.body, weight: .bold).monospacedDigit()).foregroundStyle(color)
                .frame(width: 84, alignment: .trailing)
        }
    }

    /// "18% ± 6" (la desviación solo con 2 o más rondas) / "—".
    private func percentText(_ spread: MyHistoryData.Spread?) -> String {
        guard let spread else { return "—" }
        let mean = "\(Int(spread.mean.rounded()))%"
        return spread.std.map { "\(mean) ± \(Int($0.rounded()))" } ?? mean
    }

    /// "40.5 ± 2.1" para golpes y putts.
    private func averageText(_ spread: MyHistoryData.Spread?) -> String {
        guard let spread else { return "—" }
        let mean = String(format: "%.1f", spread.mean)
        return spread.std.map { "\(mean) ± \(String(format: "%.1f", $0))" } ?? mean
    }

    private func valueRow(_ label: String, _ value: String, color: Color = CSV2.ink) -> some View {
        HStack {
            Text(label).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            Text(value).font(.system(.title3, weight: .bold).monospacedDigit()).foregroundStyle(color)
        }
    }

    // MARK: Histograma de resultados (% de hoyos)

    private func countRow(_ label: String, _ keyPath: KeyPath<MyHistoryData.ScoreCounts, Int>, color: Color) -> some View {
        let acc = MyHistoryData.percentSpread(rounds: rounds, keyPath)
        let last = lastFigures.flatMap { MyHistoryData.percent($0.counts, keyPath) }
        return twoColRow(label, acc: percentText(acc), last: last.map { "\(Int($0.rounded()))%" } ?? "—", color: color)
    }

    private func histogramCard(_ stats: MyHistoryData.Stats) -> some View {
        card {
            caption("% de hoyos por resultado")
            columnHeader("Prom. ± σ")
            countRow("Águila o mejor", \.eagleOrBetter, color: CSV2.green)
            countRow("Birdie", \.birdie, color: CSV2.green)
            countRow("Par", \.par, color: CSV2.ink)
            countRow("Bogey", \.bogey, color: CSV2.red)
            countRow("Doble (+2)", \.double, color: CSV2.red)
            countRow("Triple (+3)", \.triple, color: CSV2.red)
            countRow("+4 o más", \.quadOrMore, color: CSV2.red)
            Text("Acumulado: promedio de tus rondas cerradas ± desviación estándar (con 2 o más rondas). Este match: la última ronda cerrada.")
                .font(.v2Label).foregroundStyle(CSV2.secondary)
        }
    }

    // MARK: Golpes y putts (promedio por ronda y último match)

    private func averageRow(_ label: String, _ keyPath: KeyPath<MyHistoryData.RoundFigures, Int?>) -> some View {
        let acc = MyHistoryData.figureSpread(rounds: rounds, keyPath)
        let last = lastFigures?[keyPath: keyPath].map { "\($0)" } ?? "—"
        return twoColRow(label, acc: averageText(acc), last: last)
    }

    private var strokesPuttsCard: some View {
        card {
            caption("Golpes (medal, bruto)")
            columnHeader("Prom. ± σ")
            averageRow("F9", \.strokesF9)
            averageRow("B9", \.strokesB9)
            averageRow("Total 18", \.strokesTotal)
            RowDividerV2()
            caption("Putts")
            columnHeader("Prom. ± σ")
            averageRow("F9", \.puttsF9)
            averageRow("B9", \.puttsB9)
            averageRow("Total 18", \.puttsTotal)
            Text("F9 y B9 siguen el orden de juego de cada ronda. Solo cuentan rondas con ese nueve completo.")
                .font(.v2Label).foregroundStyle(CSV2.secondary)
        }
    }

    // MARK: Promedio vs par por tipo de hoyo

    private func parTypeRow(_ label: String, par: Int, _ stats: MyHistoryData.Stats) -> some View {
        HStack {
            Text(label).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            if let avg = stats.average(forPar: par) {
                Text(avg >= 0 ? "+\(String(format: "%.1f", avg))" : String(format: "%.1f", avg))
                    .font(.system(.title3, weight: .bold).monospacedDigit())
                    .foregroundStyle(avg > 0.05 ? CSV2.red : avg < -0.05 ? CSV2.green : CSV2.ink)
                if let dev = stats.stdDev(forPar: par) {
                    Text("± \(String(format: "%.1f", dev))").font(.v2Label).foregroundStyle(CSV2.secondary)
                }
            } else {
                Text("—").font(.system(.title3, weight: .bold)).foregroundStyle(CSV2.secondary)
            }
        }
    }

    private func parTypeCard(_ stats: MyHistoryData.Stats) -> some View {
        card {
            caption("Promedio vs. par por tipo de hoyo")
            parTypeRow("Par 3", par: 3, stats)
            parTypeRow("Par 4", par: 4, stats)
            parTypeRow("Par 5", par: 5, stats)
            Text("Promedio de golpes vs. par · ± desviación estándar (qué tan parejo juegas ese tipo de hoyo).")
                .font(.v2Label).foregroundStyle(CSV2.secondary)
        }
    }

    // MARK: Impacto del stroke

    private func strokeImpactCard(_ stats: MyHistoryData.Stats) -> some View {
        card {
            caption("Impacto del stroke")
            valueRow("Cuando recibo — gano o empato", "\(Int((stats.receiveWinOrTiePct * 100).rounded()))%", color: CSV2.green)
            valueRow("   Decidió victoria", "\(stats.receiveDecidedWin)", color: CSV2.green)
            valueRow("   Decidió empate", "\(stats.receiveDecidedTie)", color: CSV2.unitFg)
            valueRow("   No fue factor", "\(stats.receiveNoFactor)", color: CSV2.secondary)
            RowDividerV2()
            valueRow("Cuando doy — igual gano o empato", "\(Int((stats.giveWinOrTiePct * 100).rounded()))%", color: CSV2.green)
            Text("de \(stats.giveTotal) hoyos donde le di stroke a un rival").font(.v2Label).foregroundStyle(CSV2.secondary)
        }
    }

    // MARK: Oyes y dinero

    private func moneyCard(_ stats: MyHistoryData.Stats) -> some View {
        let last = rounds.first.map { MyHistoryData.money(for: $0) }
        return card {
            caption("Dinero acumulado")
            columnHeader("Acumulado")
            moneyRow("Individual", stats.moneyIndividual, last: last?.individual)
            moneyRow("Parejas", stats.moneyParejas, last: last?.parejas)
            moneyRow("Total", stats.moneyTotal, last: last?.total, big: true)
        }
    }

    private func moneyRow(_ label: String, _ acc: Int, last: Int?, big: Bool = false) -> some View {
        HStack {
            Text(label).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            MoneyTextV2(amount: acc, size: big ? 22 : 18, weight: .semibold).frame(width: 112, alignment: .trailing)
            Group {
                if let last { MoneyTextV2(amount: last, size: big ? 22 : 18, weight: .semibold) }
                else { Text("—").font(.v2Body).foregroundStyle(CSV2.secondary) }
            }
            .frame(width: 84, alignment: .trailing)
        }
    }
}

#if DEBUG
#Preview("MyHistoryV2 · rondas de muestra") {
    MyHistoryV2(sampleRounds: HistorySamplesV2.rounds)
}
#endif
