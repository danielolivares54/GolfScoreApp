import SwiftUI

// MARK: - Design tokens

private extension Color {
    static let cBg      = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let cSurface = Color.white
    static let cBorder  = Color(red: 0.890, green: 0.875, blue: 0.824)
    static let cRowDiv  = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let cInk     = Color(red: 0.110, green: 0.137, blue: 0.129)
    static let cMuted   = Color(red: 0.431, green: 0.416, blue: 0.361)
    static let cFairway = Color(red: 0.122, green: 0.239, blue: 0.169)
    static let cFairwayL = Color(red: 0.247, green: 0.420, blue: 0.290)
    static let cBrick   = Color(red: 0.659, green: 0.275, blue: 0.184)
    static let cGold    = Color(red: 0.784, green: 0.608, blue: 0.235)
    static let cGreenHint = Color(red: 0.624, green: 0.733, blue: 0.659)
    static let cDisabled = Color(red: 0.855, green: 0.835, blue: 0.769)
    static let cWarnBg  = Color(red: 1.0,   green: 0.953, blue: 0.875)
    static let cErrBg   = Color(red: 0.992, green: 0.910, blue: 0.894)
}

// MARK: - Data model

struct HoleAuditStatus {
    let hole: Int
    let par: Int
    let playerData: [(alias: String, score: Int, putts: Int)]

    var isComplete: Bool     { playerData.allSatisfy { $0.score > 0 } }
    var missingScores: [String] { playerData.filter { $0.score == 0 }.map { $0.alias } }
    var missingPutts:  [String] { playerData.filter { $0.score > 0 && $0.putts == 0 }.map { $0.alias } }
    var hasWarning: Bool     { !missingScores.isEmpty || !missingPutts.isEmpty }
}

// MARK: - Audit helpers

enum HoleAudit {
    static func playedHoles(manager: MatchManager) -> [HoleAuditStatus] {
        holeWindow(manager: manager).compactMap { hole in
            let pd = manager.players.map { p in
                (alias: p.alias,
                 score: manager.getScore(hole: hole, player: p.alias),
                 putts: manager.getPutts(hole: hole, player: p.alias))
            }
            guard pd.contains(where: { $0.score > 0 }) else { return nil }
            return HoleAuditStatus(
                hole: hole,
                par: manager.getHole(hole)?.par ?? 4,
                playerData: pd
            )
        }
    }

    static func incompleteCount(manager: MatchManager) -> Int {
        playedHoles(manager: manager).filter { $0.hasWarning }.count
    }

    static func focusedHole(manager: MatchManager) -> Int {
        let window = holeWindow(manager: manager)
        let lastWithData = window.last { hole in
            manager.players.contains { p in manager.getScore(hole: hole, player: p.alias) > 0 }
        }
        return lastWithData ?? manager.expectedNextHole()
    }

    static func holeWindow(manager: MatchManager) -> [Int] {
        let s = max(1, min(18, manager.startHole))
        return (0..<9).map { ((s - 1 + $0) % 18) + 1 }
    }
}

// MARK: - Edit target

private struct EditTarget: Identifiable {
    let id = UUID()
    let hole: Int
    let par: Int
    let alias: String
    let playerName: String
    var score: Int
    var putts: Int
}

// MARK: - Audit Sheet

struct HoleAuditView: View {
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss

    @State private var editTarget: EditTarget?

    private var audited: [HoleAuditStatus] { HoleAudit.playedHoles(manager: matchManager) }
    private var incompleteCount: Int { audited.filter { $0.hasWarning }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cBg.ignoresSafeArea()
                Group {
                    if audited.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                if incompleteCount > 0 { warningBanner }
                                ForEach(audited, id: \.hole) { status in
                                    holeCard(status)
                                }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 14)
                        }
                    }
                }
            }
            .navigationTitle("Corrección · Tarjeta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $editTarget) { target in
                HoleCorrectionSheet(target: target, matchManager: matchManager)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52)).foregroundColor(.cFairway)
            Text("Sin hoyos anotados aún")
                .font(.system(size: 15)).foregroundColor(.cMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Warning banner

    private var warningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("\(incompleteCount) hoyo\(incompleteCount == 1 ? "" : "s") con datos incompletos — toca una celda para corregir")
                .font(.system(size: 12.5)).foregroundColor(.cInk)
            Spacer()
        }
        .padding(12)
        .background(Color.cWarnBg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: Hole card

    private func holeCard(_ status: HoleAuditStatus) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Hoyo \(status.hole)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
                Text("Par \(status.par)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.cMuted)
                Spacer()
                statusIcon(status)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Color.cRowDiv.frame(height: 1)

            // Player cells row
            HStack(spacing: 0) {
                ForEach(Array(status.playerData.enumerated()), id: \.offset) { idx, pd in
                    Button {
                        openEdit(status: status, pd: pd)
                    } label: {
                        playerCell(pd: pd, par: status.par)
                    }
                    .buttonStyle(.plain)

                    if idx < status.playerData.count - 1 {
                        Color.cRowDiv.frame(width: 1)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(cardBorder(status), lineWidth: 1))
    }

    // MARK: Player cell

    private func playerCell(pd: (alias: String, score: Int, putts: Int), par: Int) -> some View {
        let hasScore = pd.score > 0
        let diff = hasScore ? pd.score - par : 0
        let scoreColor: Color = !hasScore ? .cBrick :
            diff < 0 ? .cFairwayL : diff == 0 ? .cInk : .cBrick

        return VStack(spacing: 3) {
            Text(pd.alias)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)

            Text(hasScore ? "\(pd.score)" : "✕")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(scoreColor)

            Text(pd.putts > 0 ? "\(pd.putts)p" : hasScore ? "—p" : "")
                .font(.system(size: 10))
                .foregroundColor(pd.putts > 0 ? .cMuted : .orange)

            Image(systemName: "pencil.circle")
                .font(.system(size: 11)).foregroundColor(.cDisabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(cellBackground(pd: pd, par: par))
    }

    // MARK: Helpers

    @ViewBuilder
    private func statusIcon(_ s: HoleAuditStatus) -> some View {
        if s.isComplete {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.cFairway)
        } else if !s.missingScores.isEmpty {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.cBrick)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    private func cardBorder(_ s: HoleAuditStatus) -> Color {
        if !s.missingScores.isEmpty { return .cBrick.opacity(0.4) }
        if !s.missingPutts.isEmpty  { return Color.orange.opacity(0.4) }
        return .cBorder
    }

    private func cellBackground(pd: (alias: String, score: Int, putts: Int), par: Int) -> Color {
        if pd.score == 0 { return Color.cErrBg }
        if pd.putts == 0 { return Color.cWarnBg }
        return Color.clear
    }

    private func openEdit(status: HoleAuditStatus, pd: (alias: String, score: Int, putts: Int)) {
        let player = matchManager.players.first { $0.alias == pd.alias }
        editTarget = EditTarget(
            hole: status.hole,
            par: status.par,
            alias: pd.alias,
            playerName: player?.name ?? pd.alias,
            score: pd.score > 0 ? pd.score : status.par,
            putts: pd.putts > 0 ? pd.putts : 2
        )
    }
}

// MARK: - Correction sheet

private struct HoleCorrectionSheet: View {
    @State var target: EditTarget
    @ObservedObject var matchManager: MatchManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    holeHeader
                    Spacer(minLength: 0)
                    stepperBlock
                    unitTagRow
                    Spacer(minLength: 0)
                    saveButton
                }
            }
            .navigationTitle("Corregir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(460)])
    }

    // MARK: Unidad — mismo tag que en la tarjeta principal, editable sin afectar
    // los 4 botones de Score/Putts de arriba. El valor en $ de cada tag ya viene
    // definido en el catálogo de apuestas (BetCatalog) — aquí solo se marca/desmarca.

    // Solo las unidades ACTIVAS para este match (matchManager.activeBets) — no el catálogo completo.
    // Son las que requieren marcarse a mano porque no se derivan de score/putts (Oyes Rank tiene su
    // propio control aparte, se excluye aquí).
    private var manualUnitBets: [BetDefinition] {
        let activeIds = Set(matchManager.activeBets.map { $0.definition.id })
        return matchManager.betCatalog.filter {
            $0.type == .individual && $0.mode == .manual && $0.tag.uppercased() != "OYES" && activeIds.contains($0.id)
        }
    }

    private func hasTag(_ code: String) -> Bool {
        (matchManager.unitEventsByHole[target.hole] ?? [])
            .contains { $0.alias == target.alias && $0.code == code.uppercased() }
    }

    private var unitTagRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unidad")
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.cMuted)
            HStack(spacing: 8) {
                ForEach(manualUnitBets, id: \.id) { bet in
                    let active = hasTag(bet.tag)
                    Button {
                        if active {
                            matchManager.removeUnitEvent(hole: target.hole, alias: target.alias, code: bet.tag)
                        } else {
                            matchManager.upsertUnitEvent(hole: target.hole, alias: target.alias, code: bet.tag, units: bet.units)
                        }
                    } label: {
                        Text(bet.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(active ? .white : .cMuted)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(active ? Color.cFairway : Color.cSurface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                                active ? Color.cFairway : Color.cBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 28).padding(.top, 10)
    }

    // MARK: Hole header

    private var holeHeader: some View {
        VStack(spacing: 4) {
            Text("HOYO \(target.hole) · PAR \(target.par)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.cGreenHint).kerning(0.4)
            Text(target.playerName)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundColor(.cInk)
            Text(target.alias)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20).padding(.bottom, 16)
    }

    // MARK: Steppers

    private var stepperBlock: some View {
        HStack(spacing: 0) {
            stepperColumn(
                label: "Score",
                value: target.score,
                color: scoreColor(target.score, par: target.par),
                range: 1...15,
                onDecrement: { target.score = max(1, target.score - 1) },
                onIncrement: { target.score = min(15, target.score + 1) }
            )

            Color.cBorder.frame(width: 1).padding(.vertical, 16)

            stepperColumn(
                label: "Putts",
                value: target.putts,
                color: .cInk,
                range: 0...6,
                onDecrement: { target.putts = max(0, target.putts - 1) },
                onIncrement: { target.putts = min(6, target.putts + 1) }
            )
        }
        .background(Color.cSurface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cBorder, lineWidth: 1))
        .padding(.horizontal, 28)
    }

    private func stepperColumn(
        label: String, value: Int, color: Color,
        range: ClosedRange<Int>,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.cMuted)
            Button(action: onIncrement) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.cFairway)
                    .frame(width: 44, height: 44)
                    .background(Color.cBg).clipShape(Circle())
            }
            .buttonStyle(.plain).disabled(value >= range.upperBound)

            Text("\(value)")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .frame(height: 48)

            Button(action: onDecrement) {
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.cFairway)
                    .frame(width: 44, height: 44)
                    .background(Color.cBg).clipShape(Circle())
            }
            .buttonStyle(.plain).disabled(value <= range.lowerBound)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: Save

    private var saveButton: some View {
        Button {
            // applyHoleEntry auto-marca 3P/4P según putts (nota informativa, $0) — si el
            // tag ya tenía un valor real (puesto a mano arriba, o antes en la tarjeta),
            // lo respetamos: no se toca el cálculo de MatchManager, solo se restaura
            // el evento existente después de que applyHoleEntry corra su lógica normal.
            let preserved3P = matchManager.unitEventsByHole[target.hole]?.first { $0.alias == target.alias && $0.code == "3P" }
            let preserved4P = matchManager.unitEventsByHole[target.hole]?.first { $0.alias == target.alias && $0.code == "4P" }

            matchManager.applyHoleEntry(HoleEntryData(
                hole_number: target.hole,
                player_alias: target.alias,
                strokes: target.score,
                putts: target.putts,
                units: nil,
                tags: nil
            ))

            if let e = preserved3P {
                matchManager.upsertUnitEvent(hole: target.hole, alias: target.alias, code: "3P", units: e.units, note: e.note)
            }
            if let e = preserved4P {
                matchManager.upsertUnitEvent(hole: target.hole, alias: target.alias, code: "4P", units: e.units, note: e.note)
            }

            // Espejo a ScoreManager (persistencia real) — para que la corrección
            // sobreviva si la app se cierra antes del botón "Cerrar Ronda".
            _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(
                player: target.alias, hole: target.hole,
                strokes: target.score, putts: target.putts
            ))
            dismiss()
        } label: {
            Text("Guardar corrección")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.cFairway)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 16)
    }

    // MARK: Helpers

    private func scoreColor(_ score: Int, par: Int) -> Color {
        let d = score - par
        if d < 0 { return .cFairwayL }
        if d == 0 { return .cInk }
        return .cBrick
    }
}
