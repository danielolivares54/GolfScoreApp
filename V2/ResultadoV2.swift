//
//  ResultadoV2.swift
//  Caddie Score — Vista v2, fase P1: pantalla Resultado (solo lectura)
//
//  Mismos números que la v1: todo sale de MatchManager.resultadoRowsV2() (que llama las mismas
//  funciones que ResultsSheetView). Tocar una fila abre el detalle hoyo por hoyo que ya existe
//  (MatchZoomView). Diseño: DESIGN_SPEC.md §3.5 — sin "vs", golpes en palabras, hasta 3 parejas.
//

import SwiftUI

struct ResultadoV2: View {
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    /// Detalle de un match (la pantalla hoyo por hoyo de la v1).
    @State private var zoomTarget: UnitLogTarget?

    private var rows: [MatchManager.ResultadoRowV2] { matchManager.resultadoRowsV2() }
    private var individualRows: [MatchManager.ResultadoRowV2] { rows.filter { !$0.isPair } }
    private var pairRows: [MatchManager.ResultadoRowV2] { rows.filter { $0.isPair } }
    private var total: Int { rows.reduce(0) { $0 + $1.money } }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: CSV2.s2) {
                    header
                    totalCard
                    if rows.isEmpty {
                        Text("Configura jugadores en Setup para ver resultados.")
                            .font(.v2Body).foregroundStyle(CSV2.secondary)
                            .multilineTextAlignment(.center).padding(CSV2.s3)
                    }
                    if !individualRows.isEmpty { matchesCard(title: "Individual", rows: individualRows) }
                    if !pairRows.isEmpty { matchesCard(title: "Parejas", rows: pairRows) }
                }
                .padding(CSV2.s2)
            }
        }
        .sheet(item: $zoomTarget) { target in
            MatchZoomView(matchManager: matchManager, target: target, initialSegment: "F9")
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text("Volver").font(.v2Body)
                }
                .foregroundStyle(CSV2.ink)
                .frame(minHeight: CSV2.minTap)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("después de \(matchManager.completedHolesCountV2()) hoyos")
                .font(.v2Label).foregroundStyle(CSV2.secondary)
        }
    }

    // MARK: Total

    private var totalCard: some View {
        CardV2 {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(matchManager.yoAlias) · total en curso")
                    .font(.v2Label).foregroundStyle(CSV2.secondary)
                MoneyTextV2(amount: total, size: 32, weight: .regular)
                Text(summaryLine)
                    .font(.v2Label).foregroundStyle(CSV2.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CSV2.s2)
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryLine: String {
        let i = individualRows.count, p = pairRows.count
        return "\(i) \(i == 1 ? "individual" : "individuales") · \(p) \(p == 1 ? "pareja activa" : "parejas activas")"
    }

    // MARK: Tarjetas de matches

    private func matchesCard(title: String, rows: [MatchManager.ResultadoRowV2]) -> some View {
        CardV2 {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(title).frame(maxWidth: .infinity, alignment: .leading)
                    Text("F9").frame(width: ColumnV2.status, alignment: .trailing)
                    Text("B9").frame(width: ColumnV2.status, alignment: .trailing)
                    Text("Unid").frame(width: ColumnV2.units, alignment: .trailing)
                    Text("$").frame(width: ColumnV2.money, alignment: .trailing)
                }
                .font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
                .padding(.horizontal, CSV2.s2).padding(.vertical, 12)

                ForEach(rows) { row in
                    Rectangle().fill(CSV2.rowLine).frame(height: 1)
                    matchRow(row)
                }
            }
        }
    }

    private func matchRow(_ row: MatchManager.ResultadoRowV2) -> some View {
        Button { zoomTarget = row.target } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.v2Name).foregroundStyle(CSV2.ink)
                    if let rivals = row.rivalsText {
                        Text(rivals).font(.v2Label).foregroundStyle(CSV2.secondary)
                    }
                    strokesLine(row)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MatchStatusV2(net: row.f9Net, played: row.f9Played)
                    .frame(width: ColumnV2.status, alignment: .trailing)
                MatchStatusV2(net: row.b9Net, played: row.b9Played)
                    .frame(width: ColumnV2.status, alignment: .trailing)
                UnitsNetV2(net: row.unitsNet)
                    .frame(width: ColumnV2.units, alignment: .trailing)
                MoneyTextV2(amount: row.money, size: 16, weight: .semibold)
                    .frame(width: ColumnV2.money, alignment: .trailing)
            }
            .padding(.horizontal, CSV2.s2).padding(.vertical, 12)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el detalle hoyo por hoyo")
    }

    @ViewBuilder private func strokesLine(_ row: MatchManager.ResultadoRowV2) -> some View {
        if let receiver = row.strokesReceiver {
            StrokeTextV2(receiver: receiver, amount: row.strokesAmount)
        } else if row.strokesAmount > 0 {
            // Golpes definidos pero sin jugador que los reciba (pareja sin "lleva").
            Text("\(strokesTextV2(row.strokesAmount)) strokes").font(.v2Label).foregroundStyle(CSV2.stroke)
        } else {
            Text("sin strokes").font(.v2Label).foregroundStyle(CSV2.secondary)
        }
    }
}

/// Anchos de columna compartidos por la cabecera y las filas, para que todo quede alineado.
private enum ColumnV2 {
    static let status: CGFloat = 44
    static let units: CGFloat = 44
    static let money: CGFloat = 72
}

/// Unidades netas: "+2" verde, "−1" rojo, "E" gris (misma lectura que la columna UNID de la v1).
private struct UnitsNetV2: View {
    let net: Int
    var body: some View {
        let text = net > 0 ? "+\(net)" : net < 0 ? "−\(-net)" : "E"
        let color = net > 0 ? CSV2.green : net < 0 ? CSV2.red : CSV2.secondary
        Text(text).font(.system(size: 16, weight: .bold).monospacedDigit()).foregroundStyle(color)
    }
}

#if DEBUG
#Preview("ResultadoV2 · ronda demo") {
    let manager = MatchManager()
    manager.loadDemo18()
    return ResultadoV2(matchManager: manager)
}
#endif
