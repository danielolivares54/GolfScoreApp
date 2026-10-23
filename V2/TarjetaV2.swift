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
    /// Apagado = golpes; encendido = putts en las mismas celdas y total de putts por nueve.
    @State private var showPutts: Bool
    /// Hoyo actual COMPARTIDO con la v1/HoleScreenV2: la fila de ese hoyo va en verde y tocar una celda lo cambia.
    @AppStorage(AppKeys.currentHoleIndex) private var currentHoleIndex = 0
    /// Match elegido para resaltar sus strokes por hoyo (nil = "Todos": los puntos de cada jugador como siempre).
    @State private var selectedMatchId: String?
    /// Celda tocada: se abre la hoja de corrección (la misma de la Auditoría) para editar score, putts, oye y unidades.
    @State private var correction: CorrectionTargetV2?

    init(matchManager: MatchManager, startWithPutts: Bool = false, initialMatchId: String? = nil) {
        self.matchManager = matchManager
        _showPutts = State(initialValue: startWithPutts)
        _selectedMatchId = State(initialValue: initialMatchId)
    }

    private var players: [PlayerModel] { matchManager.players }

    var body: some View {
        let nines = matchManager.tarjetaNinesV2()
        let ctx = matchContext()
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
                        if !showPutts {
                            matchBar(ctx)
                            if ctx.selected != nil { matchSummary(ctx) } else { legend }
                        }
                    }
                }
                .padding(.horizontal, CSV2.s2).padding(.bottom, CSV2.s1)

                ScrollView {
                    if nines.isEmpty || players.isEmpty {
                        Text("Configura jugadores en Setup para ver la tarjeta.")
                            .font(.v2Body).foregroundStyle(CSV2.secondary)
                            .multilineTextAlignment(.center).padding(CSV2.s3)
                    } else {
                        table(nines[safeIndex], allNines: nines, ctx: ctx)
                            .padding(.horizontal, CSV2.s2).padding(.bottom, CSV2.s3)
                    }
                }
            }
        }
        .sheet(item: $correction) { target in
            CorrectionSheetV2(target: target, matchManager: matchManager).presentationDetents([.large])
        }
    }

    // MARK: Match elegido (resalta los strokes de ese match hoyo por hoyo)

    /// Todo lo del match elegido, calculado UNA vez por render (resultadoRowsV2 y matchStrokesByHoleV2 son costosos).
    private struct MatchContext {
        let rows: [MatchManager.ResultadoRowV2]
        let selected: MatchManager.ResultadoRowV2?
        let strokes: [Int: [String: Double]]
        let participants: Set<String>?
    }

    private func matchContext() -> MatchContext {
        guard !showPutts else { return MatchContext(rows: [], selected: nil, strokes: [:], participants: nil) }
        let rows = matchManager.resultadoRowsV2()
        let selected = rows.first { $0.id == selectedMatchId }
        return MatchContext(rows: rows, selected: selected,
                            strokes: selected.map { matchManager.matchStrokesByHoleV2($0.target) } ?? [:],
                            participants: selected.map { matchManager.matchParticipantsV2($0.target) })
    }

    private func matchBar(_ ctx: MatchContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                matchChip("Todos", id: nil)
                ForEach(ctx.rows) { row in
                    matchChip(row.isPair ? "vs \(row.rivalsText ?? row.title)" : row.title, id: row.id)
                }
            }
        }
    }

    private func matchChip(_ title: String, id: String?) -> some View {
        let on = selectedMatchId == id
        return Button { selectedMatchId = id } label: {
            Text(title).font(.v2Label).foregroundStyle(on ? .white : CSV2.ink)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(on ? CSV2.stroke : CSV2.surface, in: Capsule())
                .overlay(Capsule().stroke(on ? CSV2.stroke : CSV2.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Match \(title)\(on ? ", seleccionado" : "")")
    }

    /// "DAN recibe 8 · hoyos 17, 4, 11…" — o "sin strokes" si ese match no tiene.
    @ViewBuilder private func matchSummary(_ ctx: MatchContext) -> some View {
        if let row = ctx.selected {
            Group {
                if let receiver = row.strokesReceiver, row.strokesAmount > 0 {
                    StrokeTextV2(receiver: receiver, amount: row.strokesAmount,
                                 detail: matchManager.strokeHolesText(total: row.strokesAmount, startHole: matchManager.startHole))
                } else {
                    Text("Este match no tiene strokes").font(.v2Label).foregroundStyle(CSV2.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Cabecera y leyenda

    private var header: some View {
        HStack {
            BackButtonV2 { dismiss() }
            Spacer()
            Text("Tarjeta").font(.v2Name).foregroundStyle(CSV2.ink)
            Spacer()
            Toggle("Putts", isOn: $showPutts)
                .font(.v2Body).foregroundStyle(CSV2.ink)
                .fixedSize()
                .tint(CSV2.green)
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

    private func table(_ nine: MatchManager.TarjetaNineV2, allNines: [MatchManager.TarjetaNineV2], ctx: MatchContext) -> some View {
        CardV2 {
            VStack(spacing: 0) {
                columnHeader(ctx)
                ForEach(nine.holes) { hole in
                    Rectangle().fill(CSV2.rowLine).frame(height: 1)
                    holeRow(hole, ctx)
                }
                footer(nine)
                total18(allNines)
            }
            .clipShape(RoundedRectangle(cornerRadius: CSV2.rCard))
        }
    }

    private func columnHeader(_ ctx: MatchContext) -> some View {
        HStack(spacing: 0) {
            Text("Hoyo").frame(width: ColumnT.hole, alignment: .leading)
            Text("P").frame(width: ColumnT.par)
            Text("HCP").frame(width: ColumnT.hcp)
            ForEach(players, id: \.id) { p in
                Text(p.alias).frame(maxWidth: .infinity)
                    .opacity(ctx.participants.map { $0.contains(p.alias) } ?? true ? 1 : 0.3)
            }
        }
        .font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
        .padding(.horizontal, CSV2.s1 + 4).padding(.vertical, 12)
    }

    private func holeRow(_ hole: MatchManager.TarjetaHoleV2, _ ctx: MatchContext) -> some View {
        HStack(spacing: 0) {
            Button { goToHole(hole.hole) } label: {
                Text("\(hole.hole)").font(.v2Body).foregroundStyle(CSV2.ink)
                    .frame(width: ColumnT.hole, height: 52, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hoyo \(hole.hole)")
            .accessibilityHint("Va a la captura de este hoyo")
            Text("\(hole.par)").font(.v2Body).foregroundStyle(CSV2.ink)
                .frame(width: ColumnT.par)
            HcpCellV2(hcp: hole.hcp).frame(width: ColumnT.hcp)
            ForEach(Array(hole.cells.enumerated()), id: \.offset) { index, cell in
                Button { openCorrection(hole: hole, index: index, cell: cell) } label: {
                    cellMark(hole: hole, cell: cell, alias: players[index].alias, ctx: ctx)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cellLabel(player: players[index].alias, hole: hole, cell: cell))
                .accessibilityHint("Abre la corrección de este hoyo")
            }
        }
        .padding(.horizontal, CSV2.s1 + 4)
        .frame(height: 52)
        .background(hole.hole == currentHole ? CSV2.green.opacity(0.14) : Color.clear)
    }

    /// Golpes con su marca de golf, o los putts como número simple (sin color de par: no hay par de putts).
    @ViewBuilder private func cellMark(hole: MatchManager.TarjetaHoleV2, cell: MatchManager.TarjetaCellV2, alias: String, ctx: MatchContext) -> some View {
        if showPutts {
            Text(cell.putts.map(String.init) ?? "—")
                .font(.system(size: 32 * 0.58, weight: .heavy).monospacedDigit())
                .foregroundStyle(cell.putts == nil ? CSV2.secondary : CSV2.ink)
                .frame(width: 32, height: 32)
        } else if ctx.participants != nil {
            // Match elegido: solo cuentan los strokes de ESE match (también los míos); los demás jugadores se atenúan.
            let strokes = ctx.strokes[hole.hole]?[alias] ?? 0
            ScoreMarkV2(gross: cell.gross, par: hole.par, size: 32, strokeDots: strokes, hasEvent: cell.hasEvent)
                .padding(6)
                .background {
                    if strokes > 0 {
                        RoundedRectangle(cornerRadius: CSV2.rCell).fill(CSV2.stroke.opacity(0.16))
                            .overlay(RoundedRectangle(cornerRadius: CSV2.rCell).stroke(CSV2.stroke, lineWidth: 1.5))
                    }
                }
                .opacity(ctx.participants?.contains(alias) == true ? 1 : 0.3)
        } else {
            ScoreMarkV2(gross: cell.gross, par: hole.par, size: 32,
                        strokeDots: cell.strokes, hasEvent: cell.hasEvent)
        }
    }

    private func openCorrection(hole: MatchManager.TarjetaHoleV2, index: Int, cell: MatchManager.TarjetaCellV2) {
        let player = players[index]
        correction = CorrectionTargetV2(hole: hole.hole, par: hole.par, alias: player.alias, playerName: player.name,
                                        score: cell.gross ?? hole.par, putts: cell.putts ?? 2)
    }

    private var currentHole: Int {
        let order = matchManager.playOrder()
        return order.indices.contains(currentHoleIndex) ? order[currentHoleIndex] : 1
    }

    /// Tocar una celda lleva a ese hoyo en la pantalla de captura (el dictado a ese jugador se conectará con v2t).
    private func goToHole(_ hole: Int) {
        if let index = matchManager.playOrder().firstIndex(of: hole) { currentHoleIndex = index }
        dismiss()
    }

    /// Fila de cierre (fondo oscuro): nombre del nueve, suma del par y golpes totales por jugador.
    private func footer(_ nine: MatchManager.TarjetaNineV2) -> some View {
        HStack(spacing: 0) {
            Text(nine.name).frame(width: ColumnT.hole, alignment: .leading)
            Text("\(nine.parTotal)").frame(width: ColumnT.par)
            Spacer().frame(width: ColumnT.hcp)
            ForEach(Array((showPutts ? nine.puttsTotals : nine.grossTotals).enumerated()), id: \.offset) { _, total in
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
            let parts = nines.compactMap { showPutts ? $0.puttsTotals[i] : $0.grossTotals[i] }
            return parts.isEmpty ? nil : parts.reduce(0, +)
        }
        // Segunda línea de la fila de cierre (mismo fondo oscuro): así la tabla y sus totales caben juntos.
        return HStack(spacing: 0) {
            // Mismos anchos que la tabla: etiqueta sobre Hoyo+P, par en la columna HCP, golpes bajo cada jugador.
            Text(showPutts ? "Putts 18" : "Total 18").frame(width: ColumnT.hole + ColumnT.par, alignment: .leading)
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
        if let putts = cell.putts { text += ", \(putts) putts" }
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
#Preview("TarjetaV2 · match vs ROB resaltado") {
    UserDefaults.standard.set(4, forKey: AppKeys.currentHoleIndex)
    let manager = MatchManager()
    manager.loadDemo18()
    return TarjetaV2(matchManager: manager, initialMatchId: "ind-ROB")
}

#Preview("TarjetaV2 · putts, hoyo actual 5") {
    UserDefaults.standard.set(4, forKey: AppKeys.currentHoleIndex)
    let manager = MatchManager()
    manager.loadDemo18()
    // El demo no trae putts: se anotan los de DAN (siempre se registran) en los primeros hoyos.
    for (hole, putts) in [(1, 2), (2, 3), (3, 2), (4, 2), (5, 1)] {
        manager.applyHoleEntry(HoleEntryData(hole_number: hole, player_alias: "DAN",
                                             strokes: manager.getScore(hole: hole, player: "DAN"),
                                             putts: putts, units: nil, tags: nil))
    }
    return TarjetaV2(matchManager: manager, startWithPutts: true)
}

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
