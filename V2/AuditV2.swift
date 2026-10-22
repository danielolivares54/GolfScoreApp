//
//  AuditV2.swift
//  Caddie Score — Vista v2, Paso 7: auditoría y corrección de la tarjeta
//
//  Mismos datos y mismo guardado que HoleAuditView (v1): HoleAudit.playedHoles para la lista y, al
//  guardar, applyHoleEntry + restaurar 3P/4P + espejo a ScoreManager. Oyes y unidades se aplican al
//  tocar, igual que en la hoja de corrección de la v1.
//

import SwiftUI

private struct CorrectionTargetV2: Identifiable {
    let id = UUID()
    let hole: Int
    let par: Int
    let alias: String
    let playerName: String
    var score: Int
    var putts: Int
}

struct AuditV2: View {
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss
    @State private var target: CorrectionTargetV2?

    private var audited: [HoleAuditStatus] { HoleAudit.playedHoles(manager: matchManager) }
    private var incompleteCount: Int { audited.filter { $0.hasWarning }.count }
    private var f9: [HoleAuditStatus] {
        let set = Set(matchManager.playOrder().prefix(9)); return audited.filter { set.contains($0.hole) }
    }
    private var b9: [HoleAuditStatus] {
        let set = Set(matchManager.playOrder().suffix(9)); return audited.filter { set.contains($0.hole) }
    }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: CSV2.s2) {
                    header
                    if audited.isEmpty {
                        Text("Sin hoyos anotados aún").font(.v2Body).foregroundStyle(CSV2.secondary)
                            .frame(maxWidth: .infinity).padding(CSV2.s3)
                    } else {
                        if incompleteCount > 0 { banner }
                        chapter("F9", f9)
                        chapter("B9", b9)
                        oyesAndUnits
                    }
                }
                .padding(CSV2.s2)
            }
        }
        .sheet(item: $target) { item in
            CorrectionSheetV2(target: item, matchManager: matchManager)
                .presentationDetents([.large])
        }
    }

    private var header: some View {
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
            Text("Corrección · Tarjeta").font(.v2Name).foregroundStyle(CSV2.ink)
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("\(incompleteCount) hoyo\(incompleteCount == 1 ? "" : "s") con datos incompletos — toca una celda para corregir")
                .font(.v2Label).foregroundStyle(CSV2.ink)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func chapter(_ title: String, _ holes: [HoleAuditStatus]) -> some View {
        if !holes.isEmpty {
            VStack(alignment: .leading, spacing: CSV2.s1) {
                Text(title).font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
                ForEach(holes, id: \.hole) { holeCard($0) }
            }
        }
    }

    // MARK: Tarjeta de hoyo

    private func holeCard(_ status: HoleAuditStatus) -> some View {
        CardV2 {
            VStack(spacing: 0) {
                HStack {
                    Text("Hoyo \(status.hole)").font(.v2Name).foregroundStyle(CSV2.ink)
                    ParTagV2(par: status.par)
                    Spacer()
                    statusIcon(status)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Rectangle().fill(CSV2.rowLine).frame(height: 1)
                HStack(spacing: 0) {
                    ForEach(Array(status.playerData.enumerated()), id: \.offset) { _, pd in
                        Button { open(hole: status.hole, par: status.par, alias: pd.alias) } label: {
                            playerCell(pd, par: status.par)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(cellLabel(pd))
                        .accessibilityHint("Abre la corrección")
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: CSV2.rCard)
            .stroke(!status.missingScores.isEmpty ? CSV2.red.opacity(0.5)
                    : !status.missingPutts.isEmpty ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1.5))
    }

    private func playerCell(_ pd: (alias: String, score: Int, putts: Int, strokes: Double), par: Int) -> some View {
        let hasScore = pd.score > 0
        let tracked = matchManager.tracksPutts(alias: pd.alias)
        return VStack(spacing: 4) {
            Text(pd.alias).font(.v2Caps).foregroundStyle(CSV2.secondary)
            if hasScore {
                ScoreMarkV2(gross: pd.score, par: par, size: 32, strokeDots: pd.strokes)
            } else {
                Text("✕").font(.system(size: 22, weight: .heavy)).foregroundStyle(CSV2.red)
                    .frame(width: 32, height: 32)
            }
            if hasScore && pd.strokes > 0.001 {
                Text("→\(strokesTextV2(Double(pd.score) - pd.strokes))").font(.v2Label).foregroundStyle(CSV2.stroke)
            }
            Text(pd.putts > 0 ? "\(pd.putts)p" : (hasScore && tracked) ? "—p" : " ")
                .font(.v2Label).foregroundStyle(pd.putts > 0 ? CSV2.secondary : .orange)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background((!hasScore ? CSV2.red.opacity(0.08)
                     : (pd.putts == 0 && tracked) ? Color.orange.opacity(0.10) : Color.clear))
        .contentShape(Rectangle())
    }

    private func cellLabel(_ pd: (alias: String, score: Int, putts: Int, strokes: Double)) -> String {
        var text = "\(pd.alias), " + (pd.score > 0 ? "\(pd.score) golpes" : "sin score")
        if pd.putts > 0 { text += ", \(pd.putts) putts" }
        return text
    }

    @ViewBuilder private func statusIcon(_ status: HoleAuditStatus) -> some View {
        if status.isComplete {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(CSV2.green)
        } else if !status.missingScores.isEmpty {
            Image(systemName: "xmark.circle.fill").foregroundStyle(CSV2.red)
        } else {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    // MARK: Oyes y unidades marcadas en cancha

    private struct OyeRow: Identifiable { let id = UUID(); let hole: Int; let alias: String; let rank: Int }
    private struct UnitRow: Identifiable { let id: UUID; let hole: Int; let alias: String; let code: String }

    private var oyeRows: [OyeRow] {
        let played = Set(audited.map(\.hole))
        var rows: [OyeRow] = []
        for (hole, ranks) in matchManager.oyesRanksByHole where played.contains(hole) {
            for (alias, rank) in ranks { rows.append(OyeRow(hole: hole, alias: alias, rank: rank)) }
        }
        return rows.sorted { $0.hole == $1.hole ? $0.rank < $1.rank : $0.hole < $1.hole }
    }

    private var unitRows: [UnitRow] {
        let played = Set(audited.map(\.hole))
        var rows: [UnitRow] = []
        for (hole, events) in matchManager.unitEventsByHole where played.contains(hole) {
            for event in events where event.code.uppercased() != "NOTA" {
                rows.append(UnitRow(id: event.id, hole: hole, alias: event.alias, code: event.code))
            }
        }
        return rows.sorted { $0.hole < $1.hole }
    }

    private func unitName(_ code: String) -> String {
        matchManager.betCatalog.first { $0.tag.uppercased() == code.uppercased() }?.name ?? code
    }

    @ViewBuilder private var oyesAndUnits: some View {
        let oyes = oyeRows, units = unitRows
        if !oyes.isEmpty || !units.isEmpty {
            VStack(alignment: .leading, spacing: CSV2.s1) {
                Text("Oyes y unidades").font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
                CardV2 {
                    VStack(spacing: 0) {
                        ForEach(oyes) { row in
                            listRow(hole: row.hole, alias: row.alias,
                                    text: "Oye \(row.rank)º", color: row.rank == 1 ? CSV2.unitFg : CSV2.secondary)
                        }
                        ForEach(units) { row in
                            listRow(hole: row.hole, alias: row.alias, text: unitName(row.code), color: CSV2.green)
                        }
                    }
                }
            }
        }
    }

    private func listRow(hole: Int, alias: String, text: String, color: Color) -> some View {
        Button {
            let par = matchManager.getHole(hole)?.par ?? 4
            open(hole: hole, par: par, alias: alias)
        } label: {
            HStack {
                Text("Hoyo \(hole)").font(.v2Body).foregroundStyle(CSV2.ink)
                Text(alias).font(.v2Label).foregroundStyle(CSV2.secondary)
                Spacer()
                Text(text).font(.v2Label).bold().foregroundStyle(color)
            }
            .padding(.horizontal, 14).frame(minHeight: CSV2.minTap)
            .overlay(alignment: .bottom) { Rectangle().fill(CSV2.rowLine).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Abrir corrección

    private func open(hole: Int, par: Int, alias: String) {
        let player = matchManager.players.first { $0.alias == alias }
        let score = matchManager.getScore(hole: hole, player: alias)
        let putts = matchManager.getPutts(hole: hole, player: alias)
        target = CorrectionTargetV2(hole: hole, par: par, alias: alias, playerName: player?.name ?? alias,
                                    score: score > 0 ? score : par, putts: putts > 0 ? putts : 2)
    }
}

// MARK: - Hoja de corrección

private struct CorrectionSheetV2: View {
    @State var target: CorrectionTargetV2
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: CSV2.s2) {
                    HStack {
                        Button { dismiss() } label: {
                            Text("Cancelar").font(.v2Body).foregroundStyle(CSV2.ink).frame(minHeight: CSV2.minTap)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    VStack(spacing: 4) {
                        Text("HOYO \(target.hole) · PAR \(target.par)").font(.v2Caps).foregroundStyle(CSV2.secondary)
                        Text(target.playerName).font(.v2Name).foregroundStyle(CSV2.ink)
                        Text(target.alias).font(.v2Label).foregroundStyle(CSV2.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    steppers
                    if target.par == 3 { oyeRank }
                    unitTiles
                    saveButton
                }
                .padding(CSV2.s2)
            }
        }
    }

    private var steppers: some View {
        CardV2 {
            HStack(spacing: 0) {
                stepper("Score", value: target.score, range: 1...15,
                        minus: { target.score = max(1, target.score - 1) },
                        plus: { target.score = min(15, target.score + 1) },
                        color: target.score < target.par ? CSV2.green : target.score > target.par ? CSV2.red : CSV2.ink)
                Rectangle().fill(CSV2.rowLine).frame(width: 1)
                stepper("Putts", value: target.putts, range: 0...6,
                        minus: { target.putts = max(0, target.putts - 1) },
                        plus: { target.putts = min(6, target.putts + 1) },
                        color: CSV2.ink)
            }
        }
    }

    private func stepper(_ label: String, value: Int, range: ClosedRange<Int>,
                         minus: @escaping () -> Void, plus: @escaping () -> Void, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(label).font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
            StepButtonV2(symbol: "plus", action: plus).disabled(value >= range.upperBound)
            Text("\(value)").font(.system(size: 44, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            StepButtonV2(symbol: "minus", action: minus).disabled(value <= range.lowerBound)
        }
        .frame(maxWidth: .infinity).padding(.vertical, CSV2.s2)
    }

    private var oyeRank: some View {
        let current = matchManager.oyesRanksByHole[target.hole]?[target.alias]
        let count = max(2, matchManager.players.count)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Oye · puesto").font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
            HStack(spacing: 6) {
                ForEach(1...count, id: \.self) { rank in
                    let selected = current == rank
                    Button {
                        if selected {
                            matchManager.clearOyeRank(hole: target.hole, alias: target.alias)
                        } else {
                            var ranks = matchManager.oyesRanksByHole[target.hole] ?? [:]
                            ranks[target.alias] = rank
                            matchManager.setOyesRanks(hole: target.hole, ranksByAlias: ranks)
                        }
                    } label: {
                        Text("\(rank)").font(.v2Body).foregroundStyle(selected ? CSV2.unitFg : CSV2.ink)
                            .frame(maxWidth: .infinity, minHeight: CSV2.minTap)
                            .background(selected ? CSV2.unitBg : CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCell))
                            .overlay(RoundedRectangle(cornerRadius: CSV2.rCell)
                                .strokeBorder(CSV2.unitLine, style: StrokeStyle(lineWidth: 2, dash: selected ? [] : [4, 3])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func hasTag(_ code: String) -> Bool {
        (matchManager.unitEventsByHole[target.hole] ?? [])
            .contains { $0.alias == target.alias && $0.code == code.uppercased() }
    }

    @ViewBuilder private var unitTiles: some View {
        let bets = matchManager.manualUnitBetsV2
        if !bets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Unidades activas").font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(bets, id: \.id) { bet in
                        let on = hasTag(bet.tag)
                        Button {
                            if on { matchManager.removeUnitEvent(hole: target.hole, alias: target.alias, code: bet.tag) }
                            else { matchManager.upsertUnitEvent(hole: target.hole, alias: target.alias, code: bet.tag, units: bet.units) }
                        } label: {
                            Text(on ? "\(bet.name) · agregado" : bet.name).font(.v2Body)
                                .foregroundStyle(on ? CSV2.unitFg : CSV2.ink)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(on ? CSV2.unitBg : CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
                                .overlay(RoundedRectangle(cornerRadius: CSV2.rCard)
                                    .strokeBorder(CSV2.unitLine, style: StrokeStyle(lineWidth: 2, dash: on ? [] : [4, 3])))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            // applyHoleEntry auto-marca 3P/4P según putts: si el tag ya tenía un valor real se restaura después,
            // igual que en la v1 (no se toca el cálculo de MatchManager).
            let events = matchManager.unitEventsByHole[target.hole]
            let preserved3P = events?.first { $0.alias == target.alias && $0.code == "3P" }
            let preserved4P = events?.first { $0.alias == target.alias && $0.code == "4P" }
            matchManager.applyHoleEntry(HoleEntryData(
                hole_number: target.hole, player_alias: target.alias,
                strokes: target.score, putts: target.putts, units: nil, tags: nil))
            if let e = preserved3P {
                matchManager.upsertUnitEvent(hole: target.hole, alias: target.alias, code: "3P", units: e.units, note: e.note)
            }
            if let e = preserved4P {
                matchManager.upsertUnitEvent(hole: target.hole, alias: target.alias, code: "4P", units: e.units, note: e.note)
            }
            _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(
                player: target.alias, hole: target.hole, strokes: target.score, putts: target.putts))
            dismiss()
        } label: {
            Text("Guardar corrección").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(CSV2.green, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.top, CSV2.s1)
    }
}

#if DEBUG
#Preview("AuditV2 · ronda demo (hoyos 3 y 5 incompletos)") {
    let manager = MatchManager()
    manager.loadDemo18()
    // Un score sin putts para ver la advertencia naranja.
    manager.applyHoleEntry(HoleEntryData(hole_number: 3, player_alias: "DAN",
                                         strokes: manager.getScore(hole: 3, player: "DAN"),
                                         putts: 0, units: nil, tags: nil))
    return AuditV2(matchManager: manager)
}
#endif
