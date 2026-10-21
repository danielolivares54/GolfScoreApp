//
//  TarjetaV2.swift
//  Caddie Score — Vista v2, fase P2: Tarjeta (tabla de golpes, solo lectura)
//
//  Decisiones de Daniel: marcas golf estándar (círculo = birdie, doble círculo = eagle o mejor,
//  cuadro = bogey, doble cuadro = doble o peor), con los TAMAÑOS de la v2 (marca 32 pt, filas 52 pt);
//  el cuadro dorado marca evento u oye; la columna de yo se comporta como en la v1 (los puntos de
//  golpe solo salen en los rivales que reciben de yo). Datos: MatchManager.tarjetaNinesV2().
//

import SwiftUI

struct TarjetaV2: View {
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    /// 0 = primer nueve jugado (F9), 1 = segundo (B9). Con salida en 10: F9 = 10–18, B9 = 1–9.
    @State private var nineIndex = 0

    private var players: [PlayerModel] { matchManager.players }

    var body: some View {
        let nines = matchManager.tarjetaNinesV2()
        let safeIndex = min(nineIndex, max(nines.count - 1, 0))
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Cabecera, selector de nueve y leyenda quedan FIJOS: solo la tabla se desplaza, así
                // "Volver" siempre se puede tocar aunque el sheet sea más bajo que la tabla.
                VStack(spacing: 10) {
                    header
                    if !(nines.isEmpty || players.isEmpty) {
                        Picker("Nueve", selection: $nineIndex) {
                            ForEach(nines.indices, id: \.self) { Text(nines[$0].title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        playersLine
                        legend
                    }
                }
                .padding(.horizontal, CSV2.s2).padding(.bottom, CSV2.s1)

                ScrollView {
                    if nines.isEmpty || players.isEmpty {
                        Text("Configura jugadores en Setup para ver la tarjeta.")
                            .font(.v2Body).foregroundStyle(CSV2.secondary)
                            .multilineTextAlignment(.center).padding(CSV2.s3)
                    } else {
                        table(nines[safeIndex], allNines: nines)
                            .padding(.horizontal, CSV2.s2).padding(.bottom, CSV2.s3)
                    }
                }
            }
        }
    }

    // MARK: Cabecera y leyenda

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
            Text("Tarjeta").font(.v2Name).foregroundStyle(CSV2.ink)
        }
    }

    /// Quién es cada columna, SIEMPRE visible (pedido de Daniel): código en negritas + nombre. Las columnas son
    /// angostas (5 jugadores), así que los nombres van en esta línea fija y no dentro de la cabecera de la tabla.
    private var playersLine: some View {
        var text = Text("")
        for (index, player) in players.enumerated() {
            if index > 0 { text = text + Text("   ") }
            text = text
                + Text(player.alias).font(.v2Label).bold().foregroundStyle(CSV2.ink)
                + Text(" \(player.name)").font(.v2Label).foregroundStyle(CSV2.secondary)
        }
        return text
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(players.map { "\($0.alias) es \($0.name)" }.joined(separator: ", "))
    }

    private var legend: some View {
        // Sin contornos: el color del número dice el resultado; los dos puntos redondos son lo único extra.
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                legendItem("bajo par") { Text("3").font(.system(size: 15, weight: .heavy)).foregroundStyle(CSV2.green) }
                legendItem("par") { Text("4").font(.system(size: 15, weight: .heavy)).foregroundStyle(CSV2.ink) }
                legendItem("sobre par") { Text("5").font(.system(size: 15, weight: .heavy)).foregroundStyle(CSV2.red) }
            }
            HStack(spacing: 14) {
                legendItem("recibe stroke") { Circle().fill(CSV2.stroke).frame(width: 9, height: 9) }
                legendItem("unidad / oye") { Circle().fill(CSV2.unitLine).frame(width: 9, height: 9) }
            }
        }
        .font(.v2Label).foregroundStyle(CSV2.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func legendItem<Mark: View>(_ text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) { mark(); Text(text) }
    }

    // MARK: Tabla

    private func table(_ nine: MatchManager.TarjetaNineV2, allNines: [MatchManager.TarjetaNineV2]) -> some View {
        CardV2 {
            VStack(spacing: 0) {
                columnHeader
                ForEach(nine.holes) { hole in
                    Rectangle().fill(CSV2.rowLine).frame(height: 1)
                    holeRow(hole)
                }
                footer(nine)
                total18(allNines)
            }
            .clipShape(RoundedRectangle(cornerRadius: CSV2.rCard))
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Hoyo").frame(width: ColumnT.hole, alignment: .leading)
            Text("P").frame(width: ColumnT.par)
            Text("HCP").frame(width: ColumnT.hcp)
            ForEach(players, id: \.id) { p in
                Text(p.alias).frame(maxWidth: .infinity)
            }
        }
        .font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
        .padding(.horizontal, CSV2.s1 + 4).padding(.vertical, 12)
    }

    private func holeRow(_ hole: MatchManager.TarjetaHoleV2) -> some View {
        HStack(spacing: 0) {
            Text("\(hole.hole)").font(.v2Body).foregroundStyle(CSV2.ink)
                .frame(width: ColumnT.hole, alignment: .leading)
            Text("\(hole.par)").font(.v2Body).foregroundStyle(CSV2.ink)
                .frame(width: ColumnT.par)
            HcpCellV2(hcp: hole.hcp).frame(width: ColumnT.hcp)
            ForEach(Array(hole.cells.enumerated()), id: \.offset) { index, cell in
                ScoreMarkV2(gross: cell.gross, par: hole.par, size: 32,
                            strokeDots: cell.strokes, hasEvent: cell.hasEvent)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cellLabel(player: players[index].alias, hole: hole, cell: cell))
            }
        }
        .padding(.horizontal, CSV2.s1 + 4)
        .frame(height: 52)
    }

    /// Fila de cierre (fondo oscuro): nombre del nueve, suma del par y golpes totales por jugador.
    private func footer(_ nine: MatchManager.TarjetaNineV2) -> some View {
        HStack(spacing: 0) {
            Text(nine.name).frame(width: ColumnT.hole, alignment: .leading)
            Text("\(nine.parTotal)").frame(width: ColumnT.par)
            Spacer().frame(width: ColumnT.hcp)
            ForEach(Array(nine.grossTotals.enumerated()), id: \.offset) { _, total in
                Text(total.map(String.init) ?? "—").frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 16, weight: .bold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, CSV2.s1 + 4)
        .frame(height: 52)
        .background { Rectangle().fill(CSV2.ink) }
    }

    /// Los 18 hoyos: par y golpes por jugador (suma de los dos nueves).
    private func total18(_ nines: [MatchManager.TarjetaNineV2]) -> some View {
        let par = nines.reduce(0) { $0 + $1.parTotal }
        let totals: [Int?] = players.indices.map { i in
            let parts = nines.compactMap { $0.grossTotals[i] }
            return parts.isEmpty ? nil : parts.reduce(0, +)
        }
        // Segunda línea de la fila de cierre (mismo fondo oscuro): así la tabla y sus totales caben juntos.
        return HStack(spacing: 0) {
            // Mismos anchos que la tabla: etiqueta sobre Hoyo+P, par en la columna HCP, golpes bajo cada jugador.
            Text("Total 18").frame(width: ColumnT.hole + ColumnT.par, alignment: .leading)
            Text("\(par)").frame(width: ColumnT.hcp)
            ForEach(Array(totals.enumerated()), id: \.offset) { _, total in
                Text(total.map(String.init) ?? "—").frame(maxWidth: .infinity)
            }
        }
        .font(.system(size: 14, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, CSV2.s1 + 4)
        .frame(height: 40)
        .background { Rectangle().fill(CSV2.ink) }
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 1) }
    }

    private func cellLabel(player: String, hole: MatchManager.TarjetaHoleV2, cell: MatchManager.TarjetaCellV2) -> String {
        var text = "\(player), hoyo \(hole.hole), "
        text += cell.gross.map { "\($0) golpes" } ?? "sin anotar"
        if cell.strokes >= 1 { text += ", recibe stroke" } else if cell.strokes > 0 { text += ", recibe medio stroke" }
        if cell.hasEvent { text += ", con evento u oye" }
        return text
    }
}

private enum ColumnT {
    static let hole: CGFloat = 40
    static let par: CGFloat = 28
    static let hcp: CGFloat = 46
}

/// HCP del hoyo: número dentro de un contorno (la cabecera de la columna ya dice "HCP").
private struct HcpCellV2: View {
    let hcp: Int
    var body: some View {
        Text("\(hcp)").font(.v2Label).foregroundStyle(CSV2.ink)
            .frame(minWidth: 28).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CSV2.secondary, lineWidth: 2))
    }
}

#if DEBUG
#Preview("TarjetaV2 · ronda demo") {
    let manager = MatchManager()
    manager.loadDemo18()
    return TarjetaV2(matchManager: manager)
}

#Preview("TarjetaV2 · FER recibe 3½, sale en 10") {
    let manager = MatchManager()
    manager.loadDemo18()
    manager.setStrokesVsBase(alias: "FER", value: 3.5)
    manager.updateStartHole(10, resetScores: false)
    return TarjetaV2(matchManager: manager)
}
#endif
