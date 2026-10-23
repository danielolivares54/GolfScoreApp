//
//  HoleScreenV2.swift
//  Caddie Score — Vista v2, Paso 2: pantalla principal de captura (a mano)
//
//  Escribe con las MISMAS llamadas que la v1 (applyHoleEntry + ScoreManager, setOyesRanks/clearOyeRank),
//  así que un hoyo capturado aquí da los mismos scores, putts, oyes y dinero que en la v1.
//  Voz: el mic central abre VoiceSheetV2 (v2t, pipeline compartido con el futuro Watch). Los botones Evento / Nota
//  de la barra abren EventSheetV2 / NoteSheetV2.
//

import SwiftUI

struct HoleScreenV2: View {
    @ObservedObject var matchManager: MatchManager
    @AppStorage(AppKeys.uiVersion) private var uiVersion = "v1"
    /// Hoyo actual COMPARTIDO con la v1 (misma clave que ContentView): posición dentro del orden de juego.
    @AppStorage(AppKeys.currentHoleIndex) private var currentHoleIndex = 0

    @State private var showTarjeta = false
    @State private var showResultado = false
    @State private var showAudit = false
    @State private var showSetup = false
    @State private var showHistory = false
    @State private var showCloseConfirm = false
    @State private var showEvento = false
    @State private var showNota = false
    @State private var showVoice = false
    @State private var showBetSwitches = false
    /// Última captura por voz, para el banner "Hoyo N actualizado · Deshacer".
    @State private var voiceUndo: (hole: Int, token: VoiceUndoToken)?

    @ViewBuilder
    private var voiceBanner: some View {
        if let undo = voiceUndo {
            HStack {
                Text("Hoyo \(undo.hole) actualizado ✓").font(.v2Body).foregroundStyle(CSV2.ink)
                Spacer()
                Button("Deshacer") {
                    VoiceHolePipeline.undo(undo.token, match: matchManager)
                    voiceUndo = nil
                }
                .font(.v2Body.weight(.semibold)).foregroundStyle(CSV2.green).frame(minHeight: CSV2.minTap)
            }
            .padding(.horizontal, CSV2.s2)
            .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).strokeBorder(CSV2.green, lineWidth: 1))
            .padding(.horizontal, CSV2.s2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var playOrder: [Int] { matchManager.playOrder() }
    private var currentHole: Int {
        playOrder.indices.contains(currentHoleIndex) ? playOrder[currentHoleIndex] : 1
    }
    private var par: Int { matchManager.getHole(currentHole)?.par ?? 4 }
    private var hcp: Int { matchManager.getHole(currentHole)?.si ?? 9 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: CSV2.s2) {
                    topBar
                    holeCard
                    statusStrip
                    PairsNoticeCardV2(matchManager: matchManager, hole: currentHole)
                    holeEventsCard
                    playersCard
                    if par == 3 && matchManager.isOyesEnabled && !matchManager.players.isEmpty { oyesCard }
                    nextHoleButton
                }
                .padding(CSV2.s2)
            }
            RoundBarV2(
                onTarjeta: { showTarjeta = true },
                onEvento: { showEvento = true },
                onMic: { showVoice = true },
                onNota: { showNota = true },
                onResultado: { showResultado = true }
            )
        }
        .background(CSV2.background.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)   // la fila −/score/+ de cinco jugadores deja de caber después
        .onChange(of: matchManager.startHole) { _, _ in currentHoleIndex = 0 }
        .sheet(isPresented: $showTarjeta) { TarjetaV2(matchManager: matchManager) }
        .sheet(isPresented: $showBetSwitches) { BetSwitchesSheetV2(matchManager: matchManager) }
        .sheet(isPresented: $showResultado) { ResultadoV2(matchManager: matchManager) }
        .sheet(isPresented: $showAudit) { AuditV2(matchManager: matchManager) }
        .sheet(isPresented: $showSetup) { SetupV2(matchManager: matchManager) }
        .sheet(isPresented: $showHistory) { HistorialV2() }
        .sheet(isPresented: $showEvento) { EventSheetV2(matchManager: matchManager, hole: currentHole).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showVoice) {
            VoiceSheetV2(matchManager: matchManager, hole: currentHole) { hole, token in
                voiceUndo = (hole, token)
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    if voiceUndo?.hole == hole { voiceUndo = nil }
                }
            }
        }
        .overlay(alignment: .bottom) { voiceBanner.padding(.bottom, 72) }
        .sheet(isPresented: $showNota) { NoteSheetV2(matchManager: matchManager, hole: currentHole).presentationDetents([.medium, .large]) }
        .confirmationDialog("¿Cerrar ronda?", isPresented: $showCloseConfirm, titleVisibility: .visible) {
            Button("Cerrar Ronda", role: .destructive) {
                matchManager.closeRound()
                currentHoleIndex = 0
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(matchManager.closeRoundWarning)
        }
    }

    // MARK: Barra superior

    private var topBar: some View {
        VStack(alignment: .leading, spacing: CSV2.s1) {
            HStack(alignment: .firstTextBaseline) {
                Text(matchManager.courseName.isEmpty ? "Vuelta del sábado" : matchManager.courseName)
                    .font(.v2Name).foregroundStyle(CSV2.ink).lineLimit(1)
                Text("· Sale en H\(matchManager.startHole)").font(.v2Label).foregroundStyle(CSV2.secondary)
                    .lineLimit(1).fixedSize()
                Spacer()
                PrimaryButtonV2(title: "Vista v1") { uiVersion = "v1" }.fixedSize()
            }
            HStack(spacing: CSV2.s1) {
                auditButton
                iconButton("gearshape", label: "Setup") { showSetup = true }
                iconButton("clock.arrow.circlepath", label: "Historial") { showHistory = true }
                iconButton("flag.checkered", label: "Cerrar ronda", tint: CSV2.red) { showCloseConfirm = true }
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, tint: Color = CSV2.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(.title3)).foregroundStyle(tint)
                .frame(width: CSV2.minTap, height: CSV2.minTap)
                .background(CSV2.surface, in: Circle())
                .overlay(Circle().stroke(CSV2.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // Semáforo de la auditoría: mismos criterios que el de la v1 (falta score = rojo, faltan putts = naranja).
    private var auditState: (color: Color, caption: String) {
        let played = HoleAudit.playedHoles(manager: matchManager)
        if let gap = played.first(where: { !$0.missingScores.isEmpty }) {
            return (CSV2.red, "Falta \(gap.missingScores.first ?? "?")")
        }
        if let gap = played.first(where: { !$0.missingPutts.isEmpty }) {
            return (CSV2.warning, "Putts \(gap.missingPutts.first ?? "?")")
        }
        let lastOk = played.last(where: { $0.isComplete })
        return (CSV2.green, lastOk.map { "H\($0.hole) ok" } ?? "Sin datos")
    }

    private var auditButton: some View {
        let state = auditState
        return Button { showAudit = true } label: {
            HStack(spacing: 6) {
                Circle().fill(state.color).frame(width: 14, height: 14)
                Text(state.caption).font(.v2Label).foregroundStyle(CSV2.ink).lineLimit(1)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: CSV2.minTap, alignment: .leading)
            .background(CSV2.surface, in: Capsule())
            .overlay(Capsule().stroke(CSV2.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auditoría: \(state.caption)")
    }

    // MARK: Tarjeta verde del hoyo

    private var holeCard: some View {
        HStack(spacing: CSV2.s1) {
            arrow("chevron.left", enabled: currentHoleIndex > 0) { currentHoleIndex -= 1 }
            VStack(spacing: 6) {
                Text("HOYO \(currentHole)").holeTitleV2().foregroundStyle(.white)
                HStack(spacing: 8) {
                    ParTagV2(par: par, onGreen: true)
                    HcpTagV2(hcp: hcp, onGreen: true)
                }
            }
            .frame(maxWidth: .infinity)
            arrow("chevron.right", enabled: currentHoleIndex < playOrder.count - 1) { currentHoleIndex += 1 }
        }
        .padding(CSV2.s2)
        .background(CSV2.green, in: RoundedRectangle(cornerRadius: CSV2.rCard))
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -30, currentHoleIndex < playOrder.count - 1 {
                    currentHoleIndex += 1
                } else if value.translation.width > 30, currentHoleIndex > 0 {
                    currentHoleIndex -= 1
                }
            }
        )
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(.title3, weight: .bold)).foregroundStyle(.white)
                .frame(width: CSV2.minTap, height: CSV2.minTap)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(symbol == "chevron.left" ? "Hoyo anterior" : "Hoyo siguiente")
    }

    // MARK: Tira de estado por rival y pareja (de resultadoRowsV2: los mismos números que Resultado)

    @ViewBuilder private var statusStrip: some View {
        let rows = matchManager.resultadoRowsV2()
        if !rows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CSV2.s1) {
                    ForEach(rows) { row in
                        Button { showResultado = true } label: { statusChip(row) }.buttonStyle(.plain)
                    }
                    betsChip
                }
            }
        }
    }

    /// Las apuestas activas ("todas activas" / "sin Oyes en 2"): un toque para apagar o prender.
    private var betsChip: some View {
        Button { showBetSwitches = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label("Apuestas", systemImage: "slider.horizontal.3").font(.v2Label).foregroundStyle(CSV2.green)
                Text(matchManager.betSwitchesSummaryV2).font(.v2Label).foregroundStyle(CSV2.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(CSV2.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CSV2.green.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apuestas activas, \(matchManager.betSwitchesSummaryV2)")
    }

    private func statusChip(_ row: MatchManager.ResultadoRowV2) -> some View {
        // Nueve en juego: el B9 una vez que ya tiene hoyos; antes, el F9.
        let inB9 = row.b9Played > 0
        return VStack(alignment: .leading, spacing: 4) {
            Text(row.title).font(.v2Label).foregroundStyle(CSV2.secondary).lineLimit(1)
            HStack(spacing: 8) {
                MatchStatusV2(net: inB9 ? row.b9Net : row.f9Net, played: inB9 ? row.b9Played : row.f9Played)
                MoneyTextV2(amount: row.money, size: 14, weight: .semibold)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(CSV2.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CSV2.line))
    }

    // MARK: Jugadores

    private var playersCard: some View {
        CardV2 {
            if matchManager.players.isEmpty {
                Text("Configura jugadores en Setup para empezar.")
                    .font(.v2Body).foregroundStyle(CSV2.secondary)
                    .multilineTextAlignment(.center).padding(CSV2.s3).frame(maxWidth: .infinity)
            } else {
                ForEach(Array(matchManager.players.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { RowDividerV2() }
                    playerRow(player)
                }
            }
        }
    }

    private func playerRow(_ player: PlayerModel) -> some View {
        let score = matchManager.getScore(hole: currentHole, player: player.alias)
        let putts = matchManager.getPutts(hole: currentHole, player: player.alias)
        // Misma lectura que la v1: distributedStrokes pide magnitud positiva; el signo de strokesVsBase dice la dirección.
        let strokes = matchManager.distributedStrokes(total: abs(player.strokesVsBase), hole: currentHole)
        let receivesFromMe = player.strokesVsBase > 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: CSV2.s1) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.alias).font(.v2Name).foregroundStyle(CSV2.ink)
                    Text(player.name).font(.v2Label).foregroundStyle(CSV2.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StepButtonV2(symbol: "minus") {
                    let base = score > 0 ? score : par
                    applyEntry(strokes: max(1, base - 1), player: player)
                }
                .accessibilityLabel("Un golpe menos para \(player.name)")
                ScoreMarkV2(gross: score > 0 ? score : nil, par: par, size: 44,
                            strokeDots: receivesFromMe ? strokes : 0,
                            hasEvent: matchManager.isOyesEnabled && matchManager.oyesRanksByHole[currentHole]?[player.alias] == 1)
                    .frame(minWidth: 56)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(player.name): \(score > 0 ? "\(score) golpes" : "sin anotar")")
                StepButtonV2(symbol: "plus") {
                    let base = score > 0 ? score : par
                    applyEntry(strokes: base + 1, player: player)
                }
                .accessibilityLabel("Un golpe más para \(player.name)")
            }
            strokeLine(strokes: strokes, receivesFromMe: receivesFromMe, player: player)
            if matchManager.tracksPutts(alias: player.alias) { puttsRow(putts: putts, player: player) }
        }
        .padding(.horizontal, CSV2.s2).padding(.vertical, 12)
    }

    /// "FER recibe 1" (azul) / "FER te da ½" — la v1 lo dice en la fila del jugador.
    @ViewBuilder private func strokeLine(strokes: Double, receivesFromMe: Bool, player: PlayerModel) -> some View {
        if strokes > 0 {
            HStack(spacing: 6) {
                Circle().fill(CSV2.stroke).frame(width: 9, height: 9)
                Text(receivesFromMe
                     ? "\(player.alias) recibe \(strokesTextV2(strokes))"
                     : "\(player.alias) te da \(strokesTextV2(strokes))")
                    .font(.v2Label).foregroundStyle(CSV2.stroke)
            }
        }
    }

    private func puttsRow(putts: Int, player: PlayerModel) -> some View {
        HStack(spacing: CSV2.s1) {
            Text("Putts").font(.v2Label).foregroundStyle(CSV2.secondary)
            Spacer()
            StepButtonV2(symbol: "minus") { applyEntry(putts: max(0, putts - 1), player: player) }
                .accessibilityLabel("Un putt menos para \(player.name)")
            Text(putts > 0 ? "\(putts)" : "—").font(.v2Score).foregroundStyle(putts > 0 ? CSV2.ink : CSV2.secondary)
                .frame(minWidth: 56)
            StepButtonV2(symbol: "plus") { applyEntry(putts: putts + 1, player: player) }
                .accessibilityLabel("Un putt más para \(player.name)")
        }
    }

    // MARK: Oyes (solo par 3): el puesto de cada jugador, igual que la v1

    private var oyesCard: some View {
        let count = max(2, matchManager.players.count)
        return CardV2 {
            VStack(alignment: .leading, spacing: CSV2.s1) {
                Text("Oyes · puesto de cada jugador").capsStyleV2()
                ForEach(matchManager.players, id: \.id) { player in
                    HStack(spacing: 6) {
                        Text(player.alias).font(.v2Body).foregroundStyle(CSV2.ink).frame(minWidth: 52, alignment: .leading)
                        ForEach(1...count, id: \.self) { rank in oyeButton(rank: rank, player: player) }
                    }
                }
            }
            .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func oyeButton(rank: Int, player: PlayerModel) -> some View {
        let selected = matchManager.oyesRanksByHole[currentHole]?[player.alias] == rank
        return Button {
            if selected {
                matchManager.clearOyeRank(hole: currentHole, alias: player.alias)
            } else {
                var ranks = matchManager.oyesRanksByHole[currentHole] ?? [:]
                ranks[player.alias] = rank
                matchManager.setOyesRanks(hole: currentHole, ranksByAlias: ranks)
            }
        } label: {
            Text("\(rank)").font(.v2Body).foregroundStyle(selected ? CSV2.unitFg : CSV2.ink)
                .frame(maxWidth: .infinity, minHeight: CSV2.minTap)
                .background(selected ? CSV2.unitBg : CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCell))
                .overlay(RoundedRectangle(cornerRadius: CSV2.rCell)
                    .strokeBorder(CSV2.unitLine, style: StrokeStyle(lineWidth: 2, dash: selected ? [] : [4, 3])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(player.alias) puesto \(rank)\(selected ? ", seleccionado" : "")")
    }

    // MARK: Eventos y notas del hoyo (lo que la v1 muestra en la tira de unidades y en el campo de nota)

    /// Eventos de unidad del hoyo (manuales y calculados). BIRD ya lo dice el color del score; NOTA no es evento.
    private var holeEvents: [UnitEvent] {
        matchManager.unitEventsForZoom(segmentOverride: matchManager.segmentForHole(currentHole))
            .filter { $0.hole == currentHole && $0.code.uppercased() != "BIRD" && $0.code.uppercased() != "NOTA" }
    }

    private var holeNotes: [UnitEvent] {
        (matchManager.unitEventsByHole[currentHole] ?? []).filter { $0.code.uppercased() == "NOTA" }
    }

    /// Quien ganó el Oyes (puesto 1), igual que el distintivo "Oyes" de la v1.
    private var oyesWinners: [String] {
        guard par == 3, matchManager.isOyesEnabled else { return [] }
        return matchManager.players.map(\.alias).filter { matchManager.oyesRanksByHole[currentHole]?[$0] == 1 }
    }

    private func eventLabel(_ code: String) -> String {
        matchManager.betCatalog.first { $0.tag.uppercased() == code.uppercased() }?.name ?? code
    }

    @ViewBuilder private var holeEventsCard: some View {
        let events = holeEvents, notes = holeNotes, winners = oyesWinners
        if !(events.isEmpty && notes.isEmpty && winners.isEmpty) {
            CardV2 {
                VStack(alignment: .leading, spacing: CSV2.s1) {
                    Text("Eventos y notas del hoyo").capsStyleV2()
                    FlowPillsV2 {
                        ForEach(winners, id: \.self) { alias in
                            Text("\(alias) Oyes 1º").font(.v2Label).foregroundStyle(CSV2.unitFg)
                                .padding(.horizontal, 12).frame(minHeight: 32)
                                .background(CSV2.unitBg, in: Capsule())
                        }
                        ForEach(events) { event in
                            EventPillV2(alias: event.alias, label: eventLabel(event.code), units: event.units)
                        }
                    }
                    ForEach(notes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(note.alias).font(.v2Label).bold().foregroundStyle(CSV2.ink)
                            Text(note.note ?? "").font(.v2Label).foregroundStyle(CSV2.secondary)
                        }
                    }
                }
                .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: "Hoyo N listo →"

    private var nextHoleButton: some View {
        Button {
            guard currentHoleIndex < playOrder.count - 1 else { return }
            currentHoleIndex += 1
        } label: {
            Text("Hoyo \(currentHole) listo →").font(.system(.body, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(CSV2.green, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(currentHoleIndex >= playOrder.count - 1)
        .opacity(currentHoleIndex >= playOrder.count - 1 ? 0.4 : 1)
    }

    // MARK: Escritura (las mismas llamadas que ContentView.applyEntry)

    private func applyEntry(strokes: Int? = nil, putts: Int? = nil, player: PlayerModel) {
        let savedStrokes = matchManager.getScore(hole: currentHole, player: player.alias)
        let savedPutts = matchManager.getPutts(hole: currentHole, player: player.alias)
        let s = strokes ?? (savedStrokes > 0 ? savedStrokes : par)
        let p = putts ?? savedPutts
        guard s > 0 else { return }
        matchManager.applyHoleEntry(HoleEntryData(
            hole_number: currentHole, player_alias: player.alias,
            strokes: s, putts: p, units: nil, tags: nil))
        // Persistencia real (igual que la v1): sin esto, matar la app antes de cerrar la ronda perdería el hoyo.
        _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(
            player: player.alias, hole: currentHole, strokes: s, putts: p))
    }
}

/// Píldoras que saltan de renglón cuando no caben.
private struct FlowPillsV2: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

#if DEBUG
#Preview("HoleScreenV2 · hoyo 14 (par 3) con evento y nota") {
    UserDefaults.standard.set(13, forKey: AppKeys.currentHoleIndex)
    let manager = MatchManager()
    manager.loadDemo18()
    if let tag = manager.manualUnitBetsV2.first?.tag {
        manager.upsertUnitEvent(hole: 14, alias: "ROB", code: tag, units: 1)
    }
    manager.upsertUnitEvent(hole: 14, alias: "DAN", code: "NOTA", units: 0, note: "Penalidad: bola al agua")
    return HoleScreenV2(matchManager: manager)
}
#Preview("HoleScreenV2 · ronda demo") {
    let manager = MatchManager()
    manager.loadDemo18()
    return HoleScreenV2(matchManager: manager)
}

#endif
