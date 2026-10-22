//
//  MyHistoryV2.swift
//  Caddie Score — Vista v2, Paso 9: mis estadísticas (Acumulado / Este match)
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
    private var allFigures: [MyHistoryData.RoundFigures] { rounds.compactMap { MyHistoryData.figures(for: $0) } }
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
                            oyesMoneyCard(stats)
                        }
                    }
                    .padding(CSV2.s2)
                }
            }
        }
        .onAppear { rounds = sampleRounds ?? RoundResultFile.loadAll() }
    }

    private func header(matches: Int) -> some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text("Volver").font(.v2Body)
                }
                .foregroundStyle(CSV2.ink).frame(minHeight: CSV2.minTap)
            }
            .buttonStyle(.plain)
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
        Text(text).font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
    }

    private func columnHeader(_ accumulated: String) -> some View {
        HStack {
            Spacer()
            Text(accumulated).frame(width: 84, alignment: .trailing)
            Text("Este match").frame(width: 84, alignment: .trailing)
        }
        .font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
    }

    private func twoColRow(_ label: String, acc: String, last: String, color: Color = CSV2.ink) -> some View {
        HStack {
            Text(label).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            Text(acc).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(color)
                .frame(width: 84, alignment: .trailing)
            Text(last).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(color)
                .frame(width: 84, alignment: .trailing)
        }
    }

    private func valueRow(_ label: String, _ value: String, color: Color = CSV2.ink) -> some View {
        HStack {
            Text(label).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            Text(value).font(.system(size: 20, weight: .bold).monospacedDigit()).foregroundStyle(color)
        }
    }

    // MARK: Histograma de resultados

    private func countRow(_ label: String, _ keyPath: KeyPath<MyHistoryData.ScoreCounts, Int>, _ stats: MyHistoryData.Stats,
                          color: Color) -> some View {
        twoColRow(label, acc: "\(stats.counts[keyPath: keyPath])",
                  last: lastFigures.map { "\($0.counts[keyPath: keyPath])" } ?? "—", color: color)
    }

    private func histogramCard(_ stats: MyHistoryData.Stats) -> some View {
        card {
            columnHeader("Acumulado")
            countRow("Águila o mejor", \.eagleOrBetter, stats, color: CSV2.green)
            countRow("Birdie", \.birdie, stats, color: CSV2.green)
            countRow("Par", \.par, stats, color: CSV2.ink)
            countRow("Bogey", \.bogey, stats, color: CSV2.red)
            countRow("Doble bogey (+2)", \.double, stats, color: CSV2.red)
            countRow("Triple bogey (+3)", \.triple, stats, color: CSV2.red)
            countRow("+4 o más", \.quadOrMore, stats, color: CSV2.red)
        }
    }

    // MARK: Golpes y putts (promedio por ronda y último match)

    private func averageRow(_ label: String, _ keyPath: KeyPath<MyHistoryData.RoundFigures, Int?>) -> some View {
        let values = allFigures.compactMap { $0[keyPath: keyPath] }
        let avg = values.isEmpty ? "—" : String(format: "%.1f", Double(values.reduce(0, +)) / Double(values.count))
        let last = lastFigures?[keyPath: keyPath].map { "\($0)" } ?? "—"
        return twoColRow(label, acc: avg, last: last)
    }

    private var strokesPuttsCard: some View {
        card {
            caption("Golpes (medal, bruto)")
            columnHeader("Prom.")
            averageRow("F9", \.strokesF9)
            averageRow("B9", \.strokesB9)
            averageRow("Total 18", \.strokesTotal)
            Rectangle().fill(CSV2.rowLine).frame(height: 1)
            caption("Putts")
            columnHeader("Prom.")
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
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(avg > 0.05 ? CSV2.red : avg < -0.05 ? CSV2.green : CSV2.ink)
                if let dev = stats.stdDev(forPar: par) {
                    Text("± \(String(format: "%.1f", dev))").font(.v2Label).foregroundStyle(CSV2.secondary)
                }
            } else {
                Text("—").font(.system(size: 20, weight: .bold)).foregroundStyle(CSV2.secondary)
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
            Rectangle().fill(CSV2.rowLine).frame(height: 1)
            valueRow("Cuando doy — igual gano o empato", "\(Int((stats.giveWinOrTiePct * 100).rounded()))%", color: CSV2.green)
            Text("de \(stats.giveTotal) hoyos donde le di stroke a un rival").font(.v2Label).foregroundStyle(CSV2.secondary)
        }
    }

    // MARK: Oyes y dinero

    private func moneyRow(_ label: String, _ value: Int, big: Bool = false) -> some View {
        HStack {
            Text(label).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            MoneyTextV2(amount: value, size: big ? 24 : 18, weight: .semibold)
        }
    }

    private func oyesMoneyCard(_ stats: MyHistoryData.Stats) -> some View {
        card {
            valueRow("Oyes ganados", "\(stats.oyesWins)", color: CSV2.unitFg)
            Rectangle().fill(CSV2.rowLine).frame(height: 1)
            moneyRow("Individual", stats.moneyIndividual)
            moneyRow("Parejas", stats.moneyParejas)
            moneyRow("Total acumulado", stats.moneyTotal, big: true)
        }
    }
}

#if DEBUG
#Preview("MyHistoryV2 · rondas de muestra") {
    MyHistoryV2(sampleRounds: HistorySamplesV2.rounds)
}
#endif
