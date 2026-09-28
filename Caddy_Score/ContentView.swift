import SwiftUI

// MARK: - Design tokens

private extension Color {
    static let cBg        = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let cSurface   = Color.white
    static let cBorder    = Color(red: 0.890, green: 0.875, blue: 0.824)
    static let cRowDiv    = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let cInk       = Color(red: 0.110, green: 0.137, blue: 0.129)
    static let cMuted     = Color(red: 0.431, green: 0.416, blue: 0.361)
    static let cFairway   = Color(red: 0.122, green: 0.239, blue: 0.169)
    static let cFairwayL  = Color(red: 0.247, green: 0.420, blue: 0.290)
    static let cGreenHint = Color(red: 0.620, green: 0.729, blue: 0.627)
    static let cBrick     = Color(red: 0.659, green: 0.275, blue: 0.184)
    static let cGold      = Color(red: 0.784, green: 0.608, blue: 0.235)
    static let cSegBg     = Color(red: 0.906, green: 0.886, blue: 0.824)
    static let cDisabled  = Color(red: 0.855, green: 0.835, blue: 0.769)
}

// MARK: - ContentView

struct ScoreCorrection: Equatable {
    let hole: Int
    let alias: String
}

// MARK: - Archivo de resultado al cerrar ronda (CAMBIOS_CADDIE_v2.md #6)
// DTOs propios en vez de hacer Codable a WalletLine/PlayerModel (archivos congelados).

private struct RoundResultLine: Codable {
    let label: String
    let scope: String
    let opponentAlias: String?
    let vueltaPoints: Int
    let presionPoints: Int
    let carryPoints: Int
    let carryActive: Bool
    let matchPoints: Int
    let unitsPoints: Int
    let vueltaMoney: Int
    let presionMoney: Int
    let carryMoney: Int
    let matchMoney: Int
    let unitsMoney: Int
    let totalMoney: Int
}

private struct RoundResultPlayer: Codable {
    let alias: String
    let name: String
    let strokesVsBase: Double
    let scores: [String: Int]  // "hoyo" -> gross
    let putts: [String: Int]   // "hoyo" -> putts
}

private struct RoundResultFile: Codable {
    let roundId: String
    let date: String
    let courseId: String
    let courseName: String
    let startHole: Int
    let players: [RoundResultPlayer]
    let lines: [RoundResultLine]
    let totalMoney: Int
    let closedAt: Date
}

struct ContentView: View {
    @StateObject private var matchManager = MatchManager()

    @State private var showGuidedCapture = false
    @State private var showGuidedSetup   = false
    @State private var showBetSetup      = false
    @State private var showTarjeta       = false
    @State private var showAudit         = false
    @State private var showRescue        = false
    @State private var showCerrarRondaConfirm = false
    @State private var tarjetaInitialMode: TarjetaSheetView.CardViewMode = .golpes

    @State private var correctionRequest: ScoreCorrection? = nil

    @StateObject private var inlineVoice = VoiceGuide()
    @State private var inlineRecordingIdx: Int? = nil

    @State private var currentHoleIndex: Int = 0
    @State private var editingPlayerIdx: Int  = 0
    @State private var noteByKey: [String: String] = [:]
    private var playOrder: [Int] { matchManager.playOrder() }
    private var currentHole: Int {
        playOrder.indices.contains(currentHoleIndex) ? playOrder[currentHoleIndex] : 1
    }
    private var currentPar: Int { matchManager.getHole(currentHole)?.par ?? 4 }
    private var currentHC: Int  { matchManager.getHole(currentHole)?.si  ?? 9 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                roundTitle
                holeCarousel
                miniResultado
                editablePlayerGrid
                holeSummaryBar
                legend
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.cBg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if inlineRecordingIdx != nil { inlineMicBar }
                bottomBar
            }
        }
        .onAppear { setupOnAppear() }
        .onReceive(NotificationCenter.default.publisher(for: .openCaddyRecorder)) { _ in
            showGuidedCapture = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .siriRecordPending)) { _ in
            applySiriPendingRecord()
        }
        .onChange(of: currentHoleIndex) { _, _ in
            editingPlayerIdx = 0
            inlineVoice.stopListening()
            inlineRecordingIdx = nil
            noteByKey = [:]
        }
        .sheet(isPresented: $showGuidedCapture) {
            GuidedCaptureView(matchManager: matchManager, targetHole: currentHole)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGuidedSetup)  { GuidedSetupView(matchManager: matchManager).caddySheetDetents() }
        .sheet(isPresented: $showBetSetup)     { BetSetupSheet(matchManager: matchManager) }
        .onChange(of: correctionRequest) { _, req in
            guard let req else { return }
            // Navegar al hoyo correcto
            if let hIdx = playOrder.firstIndex(of: req.hole) { currentHoleIndex = hIdx }
            // Arrancar grabación inline para el jugador
            if let pIdx = matchManager.players.firstIndex(where: { $0.alias == req.alias }) {
                let player = matchManager.players[pIdx]
                editingPlayerIdx = pIdx
                startInlineRecording(for: pIdx, player: player)
            }
            correctionRequest = nil
        }
        .sheet(isPresented: $showTarjeta) {
            TarjetaSheetView(
                matchManager: matchManager,
                correctionRequest: $correctionRequest,
                initialMode: tarjetaInitialMode
            )
                .presentationDetents([.fraction(1.0)])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAudit)        { HoleAuditView(matchManager: matchManager) }
        .sheet(isPresented: $showRescue)       { RescueCaptureView(matchManager: matchManager, autoStart: false) }
        .confirmationDialog(
            "¿Cerrar ronda?",
            isPresented: $showCerrarRondaConfirm,
            titleVisibility: .visible
        ) {
            Button("Cerrar Ronda", role: .destructive) { cerrarRonda() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrará toda la tarjeta (scores, putts, unidades) para empezar una ronda nueva. Esta acción no se puede deshacer.")
        }
    }

    // MARK: Audit button helpers (computed props so SwiftUI tracks them as reactive dependencies)

    private var auditBgColor: Color {
        let played = HoleAudit.playedHoles(manager: matchManager)
        if played.first(where: { !$0.missingScores.isEmpty }) != nil { return .cBrick }
        if matchManager.puttsBetUnits > 0,
           played.first(where: { !$0.missingPutts.isEmpty }) != nil { return .orange }
        return .cFairway
    }

    private var auditCaption: String {
        let played = HoleAudit.playedHoles(manager: matchManager)
        if let gap = played.first(where: { !$0.missingScores.isEmpty }) {
            return "✕ \(gap.missingScores.first ?? "?")"
        }
        if matchManager.puttsBetUnits > 0,
           let gap = played.first(where: { !$0.missingPutts.isEmpty }) {
            return "⚠ \(gap.missingPutts.first ?? "?")"
        }
        let lastOk = played.last(where: { $0.isComplete })
        return lastOk.map { "H\($0.hole)" } ?? "H\(currentHole)"
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("Sale en H\(matchManager.startHole)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(.cInk)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.cSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cDisabled, lineWidth: 1))

            Spacer()

            Button { showAudit = true } label: {
                VStack(spacing: 2) {
                    ZStack {
                        Circle().fill(auditBgColor).frame(width: 40, height: 40)
                        VStack(spacing: -1) {
                            Text("H")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.white.opacity(0.75))
                            Text("\(currentHole)")
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                    Text(auditCaption)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(auditBgColor)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Button { showBetSetup = true } label: {
                VStack(spacing: -1) {
                    Text("$").font(.system(size: 14, weight: .black, design: .monospaced)).foregroundColor(.cFairway)
                    Text(matchManager.activeTemplateId ?? "—")
                        .font(.system(size: 7, weight: .bold)).foregroundColor(.cMuted).lineLimit(1)
                }
                .frame(width: 40, height: 40)
                .background(Color.cSurface)
                .clipShape(Circle())
                .overlay(Circle().stroke(matchManager.activeTemplateId != nil ? Color.cFairway.opacity(0.5) : Color.cDisabled, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            Button { showGuidedSetup = true } label: {
                Image(systemName: "gearshape")
                    .font(.body).foregroundColor(.cInk)
                    .frame(width: 40, height: 40)
                    .background(Color.cSurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.cDisabled, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { showCerrarRondaConfirm = true } label: {
                Image(systemName: "flag.checkered")
                    .font(.body).foregroundColor(.cBrick)
                    .frame(width: 40, height: 40)
                    .background(Color.cSurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.cBrick.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.top, 8)
    }

    // MARK: Round title

    private var roundTitle: some View {
        Text(matchManager.courseName.isEmpty ? "Vuelta del sábado" : matchManager.courseName)
            .font(.system(size: 22, weight: .semibold, design: .serif))
            .foregroundColor(.cInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
    }

    // MARK: Hole carousel

    private var holeCarousel: some View {
        HStack(spacing: 10) {
            carouselArrow(icon: "chevron.left", enabled: currentHoleIndex > 0) {
                currentHoleIndex -= 1
            }
            VStack(spacing: 1) {
                Text("HOYO \(currentHole)")
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundColor(.cBg)
                Text("Par \(currentPar) · HCP \(currentHC)")
                    .font(.system(size: 11)).foregroundColor(.cGreenHint)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color.cFairway).cornerRadius(12)
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -30, currentHoleIndex < playOrder.count - 1 {
                            currentHoleIndex += 1
                        } else if value.translation.width > 30, currentHoleIndex > 0 {
                            currentHoleIndex -= 1
                        }
                    }
            )

            carouselArrow(icon: "chevron.right", enabled: currentHoleIndex < playOrder.count - 1) {
                currentHoleIndex += 1
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 12)
    }

    private func carouselArrow(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.cInk)
                .frame(width: 44, height: 44)
                .background(Color.cSurface).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cBorder, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    // MARK: Mini resultado

    // MARK: Strip de unidades por jugador en el hoyo actual

    private var miniResultado: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(matchManager.players, id: \.id) { player in
                    holeUnitChip(player)
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 10)
    }

    private func holeUnitChip(_ player: PlayerModel) -> some View {
        let score    = matchManager.getScore(hole: currentHole, player: player.alias)
        let hasScore = score > 0
        let diff     = hasScore ? score - currentPar : nil

        let scoreLabel: String = {
            guard let d = diff else { return "–" }
            switch d {
            case ..<(-2): return "Alb"
            case -2:      return "Águila"
            case -1:      return "Birdie"
            case 0:       return "Par"
            case 1:       return "Bogey"
            case 2:       return "+2"
            default:      return "+\(d)"
            }
        }()

        let scoreColor: Color = {
            guard let d = diff else { return .cDisabled }
            return d < 0 ? .cFairwayL : d == 0 ? .cInk : .cBrick
        }()

        // Oye: solo el ganador (rank 1) recibe marcador — los demás nada
        let isOyeWinner = matchManager.oyesRanksByHole[currentHole]?[player.alias] == 1

        // Eventos de unidad (Sandy, HIO, Alb, B18, 3P…) — BIRD redundante con score label
        let unitEvents = matchManager.unitEventsForZoom()
            .filter { $0.hole == currentHole && $0.alias == player.alias && $0.code != "BIRD" }

        return HStack(spacing: 5) {
            Text(player.alias)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)

            Text(scoreLabel)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(hasScore ? scoreColor : .cDisabled)

            // Badge rojo Oyes = ganó el oye (solo el rank 1)
            if isOyeWinner {
                Text("Oyes")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.cBrick)
                    .cornerRadius(4)
            }

            // Cuadro por cada evento de unidad adicional
            ForEach(unitEvents, id: \.id) { ev in
                unitSquare(ev.code)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.cSurface)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
            hasScore ? Color.cBorder : Color.cBorder.opacity(0.35),
            lineWidth: 1))
    }

    // Cuadro coloreado con etiqueta corta para eventos de unidad
    @ViewBuilder
    private func unitSquare(_ code: String) -> some View {
        let label = unitBadgeLabel(code)
        let isSpecial = ["HIO", "ALB", "B18"].contains(code.uppercased())
        let bg: Color    = isSpecial ? Color.cFairwayL.opacity(0.15) : Color.cBorder.opacity(0.5)
        let border: Color = isSpecial ? .cFairwayL : .cDisabled
        let fg: Color    = isSpecial ? .cFairwayL : .cMuted

        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(bg).frame(width: 24, height: 18)
            RoundedRectangle(cornerRadius: 3).strokeBorder(border, lineWidth: 1).frame(width: 24, height: 18)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(fg)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
    }

    private func unitBadgeLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "EAG":          return "Águila"
        case "ALB":          return "Alb"
        case "HIO":          return "H1"
        case "B18":          return "B18"
        case "3P":           return "3Potts"
        case "4P":           return "4Potts"
        case "SANDY", "S":   return "Sandy par"
        case "CHIPN","CHIP": return "Chip"
        default:             return code
        }
    }

    // MARK: Editable player grid

    private var editablePlayerGrid: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("HOYO \(currentHole) · PAR \(currentPar) · HCP \(currentHC)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cMuted)
                    .kerning(0.4)
                Spacer()
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.cMuted)
                Text("toca el nombre")
                    .font(.system(size: 11))
                    .foregroundColor(.cMuted)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(red: 0.984, green: 0.980, blue: 0.961))
            .overlay(alignment: .bottom) { Color.cBorder.frame(height: 1) }

            if matchManager.players.isEmpty {
                Text("Configura jugadores en ⚙ para empezar.")
                    .font(.system(size: 13)).foregroundColor(.cMuted)
                    .multilineTextAlignment(.center).padding(28)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(matchManager.players.enumerated()), id: \.offset) { idx, player in
                    editableRow(player: player, idx: idx,
                                isLast: idx == matchManager.players.count - 1)
                }
            }
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    // "golpe" / "medio golpe" / "golpe y medio" / "2 golpes" / "2 golpes y medio"...
    private func strokeReceiveLabel(_ v: Double) -> String {
        let whole = Int(v)
        let hasHalf = v - Double(whole) >= 0.25
        if whole == 0 { return "medio golpe" }
        let base = whole == 1 ? "golpe" : "\(whole) golpes"
        return hasHalf ? "\(base) y medio" : base
    }

    private func editableRow(player: PlayerModel, idx: Int, isLast: Bool) -> some View {
        let isActive    = idx == editingPlayerIdx
        let score       = matchManager.getScore(hole: currentHole, player: player.alias)
        let putts       = matchManager.getPutts(hole: currentHole, player: player.alias)
        let hasScore    = score > 0
        // Usa la misma distribución (incluye medios strokes) que ya calcula MatchManager para apuestas —
        // antes esta fila truncaba a Int y perdía el .5 al decidir quién recibe golpe.
        let strokeCount: Double = matchManager.distributedStrokes(total: player.strokesVsBase, hole: currentHole)
        let diff: Int?  = hasScore ? (score - currentPar) : nil

        let scoreColor: Color = {
            guard let d = diff else { return .cDisabled }
            return d > 0 ? .cBrick : d < 0 ? .cFairwayL : .cInk
        }()

        // Avatar: verde cuando recibe golpe, gris sin golpe
        let avatarBg: Color = strokeCount >= 2 ? .cFairwayL
                            : strokeCount >= 1 ? .cFairway
                            : .cMuted

        let statusText: String = {
            guard hasScore, let d = diff else {
                return strokeCount > 0 ? "recibe \(strokeReceiveLabel(strokeCount))" : "sin anotar"
            }
            var label: String
            switch d {
            case ..<(-1): label = "Eagle o mejor"
            case -1:      label = "Birdie"
            case 0:       label = "Par"
            case 1:       label = "Bogey"
            default:      label = "\(d) sobre par"
            }
            return strokeCount > 0 ? "\(label) · \(strokeReceiveLabel(strokeCount))" : label
        }()

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Avatar + alias — tap = dictado inline (sin nueva pantalla)
                Button {
                    editingPlayerIdx = idx
                    startInlineRecording(for: idx, player: player)
                } label: {
                    HStack(spacing: 12) {
                        Text(player.alias)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(avatarBg)
                            .clipShape(Circle())

                        HStack(spacing: 8) {
                            let isRecordingThis = inlineRecordingIdx == idx
                            let micBg: Color = isRecordingThis ? .cFairway
                                             : hasScore        ? .cBrick
                                             : .cFairwayL
                            ZStack {
                                Circle().fill(micBg).frame(width: 32, height: 32)
                                Image(systemName: isRecordingThis ? "waveform" : "mic.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .symbolEffect(.pulse, isActive: isRecordingThis)
                            }
                            Text(statusText)
                                .font(.system(size: 13))
                                .foregroundColor(hasScore ? scoreColor.opacity(0.9) : .cMuted)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 16)
                }
                .buttonStyle(.plain)

                Spacer()

                // Putts inline — solo si hay apuesta de putts y la fila está activa
                if isActive && matchManager.puttsBetUnits > 0 {
                    HStack(spacing: 3) {
                        Button {
                            applyEntry(putts: max(0, putts - 1), player: player)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cMuted)
                                .frame(width: 26, height: 26)
                                .background(Color.cBg)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cBorder, lineWidth: 1))
                        }.buttonStyle(.plain)

                        VStack(spacing: 0) {
                            Text("P")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.cDisabled)
                            Text(putts > 0 ? "\(putts)" : "–")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(putts > 0 ? .cInk : .cDisabled)
                        }
                        .frame(width: 20)

                        Button {
                            applyEntry(putts: putts + 1, player: player)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cMuted)
                                .frame(width: 26, height: 26)
                                .background(Color.cBg)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cBorder, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    .padding(.trailing, 8)
                }

                // Score cell — tap arriba/abajo para cambiar golpes
                let isPar = hasScore && diff == 0
                let cellText: String = !hasScore ? "–" : isPar ? "E" : "\(score)"
                let cellColor: Color = !hasScore ? .cDisabled : isPar ? .cInk : scoreColor
                let cellBg: Color    = isPar ? Color(red: 0.937, green: 0.953, blue: 0.937) : Color.cSurface

                VStack(spacing: 0) {
                    // Tap arriba = −1 golpe
                    Button {
                        let cur = matchManager.getScore(hole: currentHole, player: player.alias)
                        let base = cur > 0 ? cur : currentPar
                        applyEntry(strokes: max(1, base - 1), player: player)
                        editingPlayerIdx = idx
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isActive ? .cGold : .cDisabled)
                            .frame(width: 72, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(cellText)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(cellColor)
                        .frame(width: 72, height: 28)

                    // Tap abajo = +1 golpe
                    Button {
                        let cur = matchManager.getScore(hole: currentHole, player: player.alias)
                        let base = cur > 0 ? cur : currentPar
                        applyEntry(strokes: base + 1, player: player)
                        editingPlayerIdx = idx
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isActive ? .cGold : .cDisabled)
                            .frame(width: 72, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 72, height: 68)
                .background(cellBg)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                    isActive ? Color.cGold : Color.cBorder,
                    lineWidth: isActive ? 2 : 1))
                .shadow(color: isActive ? Color.cGold.opacity(0.22) : .clear, radius: 6, x: 0, y: 2)
                .padding(.trailing, 16)
            }
            .padding(.vertical, 10)

            // Oye siempre visible en par 3 (sin necesidad de expandir)
            if currentPar == 3 {
                oyeRow(player: player)
            }
            // Unidades · Nota (solo jugador activo)
            if isActive {
                playerEventsSection(player: player)
            }
        }
        .background(isActive ? Color(red: 0.984, green: 0.976, blue: 0.918) : Color.clear)
        .overlay(alignment: .bottom) {
            if !isLast { Color.cRowDiv.frame(height: 1) }
        }
    }

    // MARK: Oyes · Unidades · Nota (sección expandible por jugador)

    @ViewBuilder
    private func playerEventsSection(player: PlayerModel) -> some View {
        let manualCodes = Set(
            (matchManager.unitEventsByHole[currentHole] ?? [])
                .filter { $0.alias == player.alias }
                .map { $0.code }
        )
        let existingNote = (matchManager.unitEventsByHole[currentHole] ?? [])
            .first { $0.alias == player.alias && $0.code == "NOTA" }?.note ?? ""
        let nKey = "\(player.alias)-\(currentHole)"
        VStack(spacing: 0) {
            // ── Unidades manuales (scroll) — catálogo real, Oyes Rank tiene su propio control (oyeRow) ──
            HStack(spacing: 8) {
                Text("Unidad")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.cMuted)
                    .frame(width: 52, alignment: .trailing)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(manualUnitBets, id: \.id) { bet in
                            unitToggleBtn(bet.name, code: bet.tag, units: bet.units,
                                          active: manualCodes.contains(bet.tag.uppercased()), player: player)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .overlay(alignment: .bottom) { Color.cRowDiv.frame(height: 1) }

            // ── Nota / penalidad ───────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundColor(.cDisabled)
                    .frame(width: 52, alignment: .center)

                TextField("penalidad, 3 putt, chupes…", text: Binding(
                    get: { noteByKey[nKey] ?? existingNote },
                    set: { noteByKey[nKey] = $0 }
                ))
                .font(.system(size: 12))
                .foregroundColor(.cInk)
                .onSubmit {
                    let text = (noteByKey[nKey] ?? "").trimmingCharacters(in: .whitespaces)
                    if text.isEmpty {
                        matchManager.removeUnitEvent(hole: currentHole, alias: player.alias, code: "NOTA")
                    } else {
                        matchManager.upsertUnitEvent(hole: currentHole, alias: player.alias,
                                                     code: "NOTA", units: 0, note: text)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Color(red: 0.980, green: 0.972, blue: 0.910))
    }

    // Fila de Oye rank — siempre visible en par 3 para cada jugador
    @ViewBuilder
    private func oyeRow(player: PlayerModel) -> some View {
        let currentOyeRank = matchManager.oyesRanksByHole[currentHole]?[player.alias]
        let playerCount = max(2, matchManager.players.count)
        HStack(spacing: 6) {
            Text("Oye")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.cMuted)
                .frame(width: 52, alignment: .trailing)
            ForEach(Array(1...playerCount), id: \.self) { rank in
                let sel = currentOyeRank == rank
                Button {
                    if sel {
                        matchManager.clearOyeRank(hole: currentHole, alias: player.alias)
                    } else {
                        var ranks = matchManager.oyesRanksByHole[currentHole] ?? [:]
                        ranks[player.alias] = rank
                        matchManager.setOyesRanks(hole: currentHole, ranksByAlias: ranks)
                    }
                } label: {
                    Text("\(rank)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(sel ? .white : (rank == 1 ? .cBrick : .cMuted))
                        .frame(width: 30, height: 30)
                        .background(sel ? (rank == 1 ? Color.cBrick : Color.cMuted) : Color.cBg)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(
                            sel ? Color.clear : (rank == 1 ? Color.cBrick.opacity(0.5) : Color.cBorder),
                            lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(Color(red: 0.980, green: 0.975, blue: 0.922))
        .overlay(alignment: .bottom) { Color.cRowDiv.frame(height: 1) }
    }

    // Apuestas manuales individuales del catálogo, excluyendo Oyes Rank (tiene su propio control: oyeRow).
    private var manualUnitBets: [BetDefinition] {
        matchManager.betCatalog.filter { $0.type == .individual && $0.mode == .manual && $0.tag.uppercased() != "OYES" }
    }

    @ViewBuilder
    private func unitToggleBtn(_ label: String, code: String, units: Int = 1, active: Bool, player: PlayerModel) -> some View {
        Button {
            if active { matchManager.removeUnitEvent(hole: currentHole, alias: player.alias, code: code) }
            else      { matchManager.upsertUnitEvent(hole: currentHole, alias: player.alias, code: code, units: units) }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(active ? .white : .cMuted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? Color.cFairway : Color.cBg)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                    active ? Color.cFairway : Color.cBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Hole summary bar

    private struct SummaryChip {
        let label: String
        let hx: Double
        let yoStrokes: Double   // strokes que recibí yo (DAN)
        let oppStrokes: Double  // strokes que recibió el contrario
        let lastHole: Int
        let vuelta: Int
        let pressures: [Int]
        let units: Int
        let isPair: Bool
        var netStrokes: Double { yoStrokes - oppStrokes }
    }

    private func buildSummaryChips() -> [SummaryChip] {
        var chips: [SummaryChip] = []
        for opp in matchManager.players where opp.alias != matchManager.yoAlias && !matchManager.baseTeamAliases.contains(opp.alias) {
            let rows = matchManager.individualZoomRows(opponentAlias: opp.alias)
            let upTo = rows.filter { $0.hole <= currentHole }
            guard let last = upTo.last else { continue }
            chips.append(SummaryChip(
                label:      opp.alias,
                hx:         opp.strokesVsBase,
                yoStrokes:  upTo.reduce(0.0) { $0 + $1.yoStrokes  },
                oppStrokes: upTo.reduce(0.0) { $0 + $1.oppStrokes },
                lastHole:   last.hole,
                vuelta:     last.vueltaAccum,
                pressures:  last.openPressures,
                units:      matchManager.unitStakeForIndividual(opponentAlias: opp.alias),
                isPair:     false
            ))
        }
        for lane in matchManager.lanes {
            let rows = matchManager.pairZoomRows(laneId: lane.id)
            let upTo = rows.filter { $0.hole <= currentHole }
            guard let last = upTo.last else { continue }
            chips.append(SummaryChip(
                label:      lane.opp.joined(separator: " "),
                hx:         lane.strokes,
                yoStrokes:  0,
                oppStrokes: 0,
                lastHole:   last.hole,
                vuelta:    last.vueltaAccum,
                pressures: last.openPressures,
                units:     matchManager.unitStakeForPair(laneId: lane.id),
                isPair:    true
            ))
        }
        return chips
    }

    @ViewBuilder
    private var holeSummaryBar: some View {
        let chips = buildSummaryChips()
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        Button { closeAllSheets(); tarjetaInitialMode = .resultado; showTarjeta = true } label: {
                            summaryChipView(chip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
            }
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func summaryChipView(_ chip: SummaryChip) -> some View {
        let vueltaColor: Color = chip.vuelta < 0 ? .cBrick : chip.vuelta > 0 ? .cFairwayL : .cInk
        let vueltaStr   = chip.vuelta < 0 ? "\(chip.vuelta)" : chip.vuelta == 0 ? "E" : "\(chip.vuelta)"
        let unitsColor: Color = chip.units < 0 ? .cBrick : chip.units > 0 ? .cFairwayL : .cDisabled
        let unitsStr    = chip.units == 0 ? "0u" : chip.units < 0 ? "\(chip.units)u" : "\(chip.units)u"
        let borderColor: Color = chip.isPair ? Color.cFairway.opacity(0.4) : Color.cBorder

        VStack(alignment: .leading, spacing: 5) {
            // Fila 1: alias · hx · H(hoyo)
            HStack(spacing: 5) {
                if chip.isPair {
                    Text("PAR")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.cFairway.opacity(0.7))
                }
                Text(chip.label)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
                Text("\(caddyStrokeStr(chip.hx))h · H\(chip.lastHole)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.cDisabled)
            }

            // Fila 2: strokes♦  |  vuelta  presiones  |  units
            HStack(spacing: 7) {
                if !chip.isPair && chip.netStrokes != 0 {
                    let net = chip.netStrokes
                    Text("\(caddyStrokeStr(abs(net)))♦")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(net > 0 ? .cFairwayL : .cBrick)
                }
                borderColor.frame(width: 1, height: 18)
                Text(vueltaStr)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(vueltaColor)
                ForEach(Array(chip.pressures.enumerated()), id: \.offset) { _, p in
                    let pStr: String = p < 0 ? "\(p)" : p == 0 ? "E" : "\(p)"
                    let pColor: Color = p < 0 ? .cBrick : p > 0 ? .cFairwayL : .cInk
                    Text(pStr)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(pColor)
                }
                Color.cBorder.frame(width: 1, height: 18)
                Text(unitsStr)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(unitsColor)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.cSurface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(borderColor, lineWidth: 1))
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(.cInk,      "Par")
            legendDot(.cBrick,    "Sobre par")
            legendDot(.cFairwayL, "Bajo par")
            Spacer()
            Button("demo") { seedDemoRound() }
                .font(.system(size: 9)).foregroundColor(.cDisabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.bottom, 12)
    }

    private func legendDot(_ c: Color, _ l: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(l).font(.system(size: 11)).foregroundColor(.cMuted)
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { showAudit = true } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16))
                    .foregroundColor(.cMuted)
                    .frame(width: 42, height: 40)
                    .background(Color.cSurface)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { advanceToNextHole() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Hoyo \(currentHole) listo →")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.cInk)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.cGold)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 7)
        .background(Color.cBg)
        .overlay(Color.cBorder.frame(height: 1), alignment: .top)
    }

    // MARK: Bottom tab bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            scorecardTabBtn(active: true) { closeAllSheets() }
            tabBtn(icon: "square.grid.2x2",      label: "Tarjeta",   active: false) { closeAllSheets(); tarjetaInitialMode = .golpes;    showTarjeta = true }
            tabBtn(icon: "doc.plaintext",         label: "Resultado", active: false) { closeAllSheets(); tarjetaInitialMode = .resultado; showTarjeta = true }
        }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 16)
        .background(Color.cSurface)
        .overlay(Color.cBorder.frame(height: 1), alignment: .top)
    }

    private func closeAllSheets() {
        showGuidedCapture = false
        showGuidedSetup   = false
        showBetSetup      = false
        showTarjeta       = false
        showAudit         = false
        showRescue        = false
        inlineVoice.stopListening()
        inlineRecordingIdx = nil
    }

    // Tab "Scorecard": lápiz (editar a mano) + mic (dictar) en vez de texto — son las dos formas de anotar un score.
    private func scorecardTabBtn(active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .font(.system(size: 18))
                    .foregroundColor(active ? Color.cFairway : .cMuted)
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundColor(active ? Color.cFairway : .cMuted)
            }
            .frame(maxWidth: .infinity).frame(minHeight: 48).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func tabBtn(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(active ? Color.cFairway : .cMuted)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(active ? Color.cFairway : .cMuted)
            }
            .frame(maxWidth: .infinity).frame(minHeight: 48).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Inline mic bar

    @ViewBuilder
    private var inlineMicBar: some View {
        if let idx = inlineRecordingIdx, matchManager.players.indices.contains(idx) {
            let player = matchManager.players[idx]
            HStack(spacing: 12) {
                // Pulsing mic icon
                ZStack {
                    Circle()
                        .fill(Color.cFairway.opacity(inlineVoice.isListening ? 0.18 : 0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: inlineVoice.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.cFairway)
                        .symbolEffect(.pulse, isActive: inlineVoice.isListening)
                }

                // Player alias + feedback text
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.alias)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cMuted)
                    Text(inlineVoice.partialText.isEmpty ? "di el número de golpes…" : inlineVoice.partialText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.cInk)
                        .lineLimit(1)
                }

                Spacer()

                // Cancel
                Button {
                    inlineVoice.stopListening()
                    inlineRecordingIdx = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.cDisabled)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.cSurface)
            .overlay(alignment: .top) { Color.cGold.frame(height: 2) }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Helpers

    private func startInlineRecording(for idx: Int, player: PlayerModel) {
        inlineVoice.stopListening()
        inlineVoice.currentPar = currentPar
        inlineVoice.onNumber = { n in
            applyEntry(strokes: max(1, n), player: player)
            withAnimation { inlineRecordingIdx = nil }
        }
        inlineVoice.onSkip   = { withAnimation { inlineRecordingIdx = nil } }
        inlineVoice.onAccept = { withAnimation { inlineRecordingIdx = nil } }
        withAnimation { inlineRecordingIdx = idx }
        inlineVoice.startListening()
    }

    private func applyEntry(strokes: Int? = nil, putts: Int? = nil, player: PlayerModel) {
        let savedStrokes = matchManager.getScore(hole: currentHole, player: player.alias)
        let savedPutts   = matchManager.getPutts(hole: currentHole, player: player.alias)
        let s = strokes ?? (savedStrokes > 0 ? savedStrokes : currentPar)
        let p = putts   ?? savedPutts
        guard s > 0 else { return }
        matchManager.applyHoleEntry(HoleEntryData(
            hole_number: currentHole, player_alias: player.alias,
            strokes: s, putts: p, units: nil, tags: nil))
        // Espejo a ScoreManager (persistencia real) — el dictado inline solo vivía
        // en memoria; sin esto, matar la app antes de "Cerrar Ronda" perdía el hoyo.
        _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(
            player: player.alias, hole: currentHole, strokes: s, putts: p
        ))
    }

    private func advanceToNextHole() {
        guard currentHoleIndex < playOrder.count - 1 else { return }
        currentHoleIndex += 1
        editingPlayerIdx = 0
    }

    private func setupOnAppear() {
        let metaPlayers = SiriMatchManager.shared.getPlayers()
        if !metaPlayers.isEmpty {
            matchManager.setPlayers(names: metaPlayers, preserveScores: true)
        }
        let metaStart = SiriMatchManager.shared.getStartingHole()
        if metaStart > 0 { matchManager.startHole = metaStart }
        matchManager.syncFromScoreManager()
        if let next = matchManager.firstIncompleteHole(),
           let idx  = playOrder.firstIndex(of: next) { currentHoleIndex = idx }
        editingPlayerIdx = 0
        if UserDefaults.standard.bool(forKey: "pendingOpenRecorder") {
            UserDefaults.standard.removeObject(forKey: "pendingOpenRecorder")
            showGuidedCapture = true
        }
    }

    private func applySiriPendingRecord() {
        guard let record = AppDelegate.readPendingRecord() else { return }
        matchManager.applyHoleEntry(HoleEntryData(
            hole_number: record.hole, player_alias: record.player,
            strokes: record.strokes, putts: record.putts, units: nil, tags: nil))
        AppDelegate.clearPendingRecord()
    }

    // MARK: Cerrar ronda (único punto que borra datos — CAMBIOS_CADDIE_v2.md #6)

    private func cerrarRonda() {
        closeAllSheets()
        saveRoundResultToFile()
        matchManager.resetScores()
        ScoreManager.shared.clearAll()
        AppDelegate.clearPendingRecord()
        currentHoleIndex = 0
        editingPlayerIdx = 0
        noteByKey = [:]
    }

    // Guarda el resultado final (scores + wallet) a disco antes de borrar.
    // Provisional: hoy solo archiva. El ajuste automático de strokesVsBase en el
    // directorio de jugadores (a partir de este histórico) queda para una fase futura.
    private func saveRoundResultToFile() {
        let snapshot = matchManager.walletSnapshot()
        let lines = snapshot.lines.map { line in
            RoundResultLine(
                label: line.label, scope: line.scope.rawValue, opponentAlias: line.opponentAlias,
                vueltaPoints: line.vueltaPoints, presionPoints: line.presionPoints,
                carryPoints: line.carryPoints, carryActive: line.carryActive,
                matchPoints: line.matchPoints, unitsPoints: line.unitsPoints,
                vueltaMoney: line.vueltaMoney, presionMoney: line.presionMoney,
                carryMoney: line.carryMoney, matchMoney: line.matchMoney,
                unitsMoney: line.unitsMoney, totalMoney: line.totalMoney
            )
        }
        let players = matchManager.players.map { p -> RoundResultPlayer in
            var scores: [String: Int] = [:]
            var putts: [String: Int] = [:]
            for (hole, entry) in p.scores {
                scores["\(hole)"] = entry.gross
                if let pu = entry.putts { putts["\(hole)"] = pu }
            }
            return RoundResultPlayer(alias: p.alias, name: p.name, strokesVsBase: p.strokesVsBase, scores: scores, putts: putts)
        }
        let file = RoundResultFile(
            roundId: matchManager.roundId, date: matchManager.dateString,
            courseId: matchManager.courseId, courseName: matchManager.courseName,
            startHole: matchManager.startHole, players: players, lines: lines,
            totalMoney: snapshot.totalMoney, closedAt: Date()
        )
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.comDOG.Caddy-Score")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let roundsDir = dir.appendingPathComponent("closed_rounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: roundsDir, withIntermediateDirectories: true)
        let fileURL = roundsDir.appendingPathComponent("\(file.roundId).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(file)
            try data.write(to: fileURL)
            print("✅ Ronda cerrada, resultado guardado en: \(fileURL)")
        } catch {
            print("❌ Error guardando resultado de ronda: \(error)")
        }
    }

    // MARK: Demo seed (testing only)

    private func seedDemoRound() {
        // Jugadores: DAN (yo 0h), ANS (16h), CAR (8h), PED (24h)
        matchManager.setPlayers(names: ["Daniel", "Anselmo", "Carlos", "Pedro"])
        matchManager.setStrokesVsBase(alias: "ANS", value: 16)
        matchManager.setStrokesVsBase(alias: "CAR", value: 8)
        matchManager.setStrokesVsBase(alias: "PED", value: 24)

        // Equipo pareja: DAN+CAR vs ANS+PED, 4 strokes de lane
        _ = matchManager.setBaseTeam(["DAN", "CAR"])
        if let lane = matchManager.lanes.first {
            matchManager.setLaneStrokes(id: lane.id, value: 4)
        }

        // Config de apuestas y salida
        matchManager.startHole = 1
        matchManager.setVueltaValue(1)
        matchManager.puttsBetUnits = 2

        // Scores H1-H5 (CGM: H1=Par4 SI13, H2=Par5 SI3, H3=Par3 SI17, H4=Par4 SI1, H5=Par3 SI15)
        let entries: [(h: Int, a: String, s: Int, p: Int)] = [
            (1,"DAN",4,2), (1,"ANS",5,3), (1,"CAR",3,1), (1,"PED",6,2),
            (2,"DAN",5,2), (2,"ANS",5,2), (2,"CAR",5,2), (2,"PED",7,2),
            (3,"DAN",3,1), (3,"ANS",4,2), (3,"CAR",3,2), (3,"PED",5,2),
            (4,"DAN",3,1), (4,"ANS",5,2), (4,"CAR",4,2), (4,"PED",5,2),
            (5,"DAN",2,1), (5,"ANS",3,2), (5,"CAR",4,2), (5,"PED",3,2),
        ]
        for e in entries {
            matchManager.applyHoleEntry(HoleEntryData(
                hole_number: e.h, player_alias: e.a,
                strokes: e.s, putts: e.p, units: nil, tags: nil))
        }

        // OYEs en pares 3 (H3 y H5)
        matchManager.setOyesRanks(hole: 3, ranksByAlias: ["DAN":1,"CAR":2,"ANS":3,"PED":4])
        matchManager.setOyesRanks(hole: 5, ranksByAlias: ["DAN":1,"ANS":2,"PED":3,"CAR":4])

        // Unidades manuales: Sandy ANS H1, Sandy CAR H4, Sandy DAN H5
        matchManager.upsertUnitEvent(hole: 1, alias: "ANS", code: "SANDY", units: 1)
        matchManager.upsertUnitEvent(hole: 4, alias: "CAR", code: "SANDY", units: 1)
        matchManager.upsertUnitEvent(hole: 5, alias: "DAN", code: "SANDY", units: 1)

        // Navegar a H5 para ver estado completo
        currentHoleIndex = 4
    }
}

// MARK: - TarjetaSheetView  (02-tarjeta: hoyos-como-filas, jugadores-como-columnas)

struct TarjetaSheetView: View {
    @ObservedObject var matchManager: MatchManager
    @Binding var correctionRequest: ScoreCorrection?
    @Environment(\.dismiss) private var dismiss
    var initialMode: CardViewMode = .golpes
    @State private var mode: CardViewMode = .golpes

    enum CardViewMode { case golpes, resultado }

    private var holes: [Int] {
        let s = max(1, min(18, matchManager.startHole))
        return (0..<18).map { ((s - 1 + $0) % 18) + 1 }
    }

    var body: some View {
        ZStack {
            Color.cBg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Drag handle — swipe down to close, no Cerrar button
                Capsule()
                    .fill(Color.cDisabled)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12).padding(.bottom, 8)

                topMeta
                modeToggle
                gridScrollArea
                    .frame(maxHeight: .infinity)
                if mode == .golpes { legendBar }
            }
        }
        .onAppear { mode = initialMode }
    }

    // Cerrar Ronda vive solo en la pantalla principal (topBar de ContentView) — no aquí.
    // Ver ContentView.confirmationDialog("¿Cerrar ronda?").

    // MARK: Sub-views

    private var topMeta: some View {
        let id = matchManager.courseId.isEmpty ? "CGM" : matchManager.courseId
        return Text("\(id)  ·  Sale en H\(matchManager.startHole)")
            .font(.system(size: 11.5))
            .foregroundColor(.cMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.bottom, 4)
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            segBtn("Golpes",    active: mode == .golpes)    { mode = .golpes }
            segBtn("Resultado", active: mode == .resultado) { mode = .resultado }
        }
        .padding(3).background(Color.cSegBg).cornerRadius(10)
        .padding(.horizontal, 18).padding(.bottom, 10)
    }

    private func segBtn(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(active ? .cFairway : .cMuted)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(active ? Color.cSurface : Color.clear).cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var gridScrollArea: some View {
        if mode == .resultado {
            ResultsSheetView(matchManager: matchManager, correctionRequest: $correctionRequest, embedded: true)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    playerHeaderRow
                    ForEach(Array(holes.enumerated()), id: \.offset) { idx, h in
                        holeRow(hole: h, rowIndex: idx)
                    }
                    totalsRow
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
            }
            .padding(.horizontal, 18)
        }
    }

    private var playerHeaderRow: some View {
        HStack(spacing: 0) {
            Text(mode == .resultado ? "HOYO" : "HOYO")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.788, green: 0.851, blue: 0.800))
                .frame(width: 50, alignment: .leading)
                .padding(.leading, 10)
            ForEach(matchManager.players, id: \.id) { p in
                Text(p.alias)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.cBg)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .background(Color.cFairway)
    }

    private func holeRow(hole: Int, rowIndex: Int) -> some View {
        let hd   = matchManager.getHole(hole)
        let par  = hd?.par ?? 4
        let hc   = hd?.si  ?? 9
        let even = rowIndex % 2 == 0

        return HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("\(hole)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
                Text("\(par)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(parTextColor(par))
                Text("\(hc)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(hcBg(hc)).cornerRadius(4)
            }
            .frame(width: 50, alignment: .leading).padding(.leading, 10)

            ForEach(matchManager.players, id: \.id) { p in
                if mode == .resultado {
                    resultCell(player: p, hole: hole)
                } else {
                    scoreCell(player: p, hole: hole, par: par, hc: hc)
                }
            }
        }
        .padding(.vertical, 8)
        .background(even ? Color.cSurface : Color(red: 0.984, green: 0.980, blue: 0.960))
        .overlay(alignment: .bottom) { Color.cRowDiv.frame(height: 1) }
    }

    // Modo Golpes: muestra gross + putts + strokes + badge
    private func scoreCell(player: PlayerModel, hole: Int, par: Int, hc: Int) -> some View {
        let gross    = matchManager.getScore(hole: hole, player: player.alias)
        let putts    = matchManager.getPutts(hole: hole, player: player.alias)
        let strokes  = strokesOnHole(si: hc, sVsBase: player.strokesVsBase)
        let isOyes   = matchManager.hasIndividualUnitWin(hole: hole, alias: player.alias)
                    || matchManager.hasPairUnitWin(hole: hole, alias: player.alias)
        let hasScore = gross > 0
        let diff     = hasScore ? (gross - par) : nil
        let badge: String = {
            guard hasScore else { return "" }
            let d = gross - par
            return d <= -2 ? "EAGLE" : d == -1 ? "BIRDIE" : ""
        }()

        return VStack(spacing: 1) {
            if hasScore {
                Text("\(gross)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(isOyes ? .cGold : cellColor(diff))
                if putts > 0 {
                    Text("(\(putts))")
                        .font(.system(size: 9.5))
                        .foregroundColor(.cMuted)
                }
                if strokes > 0 {
                    HStack(spacing: 1) {
                        ForEach(0..<min(strokes, 2), id: \.self) { _ in
                            Circle().fill(Color.cMuted).frame(width: 4, height: 4)
                        }
                    }
                }
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.cFairwayL)
                }
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(.cDisabled)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Modo Resultado: muestra resultado vuelta por hoyo desde la lane del jugador
    private func resultCell(player: PlayerModel, hole: Int) -> some View {
        let r = holeMatchResult(player: player, hole: hole)   // nil = sin datos, Int = resultado
        let accum = holeMatchAccum(player: player, hole: hole)

        return VStack(spacing: 2) {
            if let r {
                // Resultado del hoyo específico (win/loss de ese hoyo)
                let hLabel = r == 0 ? "E" : r > 0 ? "+\(r)" : "\(r)"
                Text(hLabel)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(r > 0 ? .cFairwayL : r < 0 ? .cBrick : .cMuted)
                // Acumulado vuelta hasta ese hoyo
                if let a = accum {
                    let aLabel = a == 0 ? "E" : a > 0 ? "+\(a)" : "\(a)"
                    Text(aLabel)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(a > 0 ? .cFairwayL.opacity(0.7) : a < 0 ? .cBrick.opacity(0.7) : .cMuted)
                }
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(.cDisabled)
            }
        }
        .frame(maxWidth: .infinity)
    }


    // Fila F9 — totales
    private var totalsRow: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("TOT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.cBg)
                Text("\(holes.compactMap { matchManager.getHole($0)?.par }.reduce(0, +))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.788, green: 0.851, blue: 0.800))
            }
            .frame(width: 50, alignment: .leading).padding(.leading, 10)

            ForEach(matchManager.players, id: \.id) { p in
                VStack(spacing: 2) {
                    let total = holes.map { matchManager.getScore(hole: $0, player: p.alias) }.filter { $0 > 0 }.reduce(0, +)
                    let puttTotal = holes.map { matchManager.getPutts(hole: $0, player: p.alias) }.filter { $0 > 0 }.reduce(0, +)
                    Text(total > 0 ? "\(total)" : "—")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(total > 0 ? .cBg : Color(red: 0.788, green: 0.851, blue: 0.800))
                    if puttTotal > 0 {
                        Text("(\(puttTotal))")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color(red: 0.788, green: 0.851, blue: 0.800))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .background(Color.cFairway)
    }

    private var legendBar: some View {
        HStack(spacing: 10) {
            legendDot(.cBrick,    "Sobre par")
            legendDot(.cFairwayL, "Bajo par / gana hoyo")
            HStack(spacing: 4) {
                Circle().fill(Color.cMuted).frame(width: 6, height: 6)
                Text("= stroke").font(.system(size: 10.5)).foregroundColor(.cMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 10.5)).foregroundColor(.cMuted)
        }
    }

    // MARK: Helpers

    private func holeMatchResult(player: PlayerModel, hole: Int) -> Int? {
        guard let lane = matchManager.lanes.first(where: {
            $0.base.contains(player.alias) || $0.opp.contains(player.alias)
        }) else { return nil }
        let rows = matchManager.pairZoomRows(laneId: lane.id)
        guard let row = rows.first(where: { $0.hole == hole }) else { return nil }
        return lane.base.contains(player.alias) ? row.result : -row.result
    }

    private func holeMatchAccum(player: PlayerModel, hole: Int) -> Int? {
        guard let lane = matchManager.lanes.first(where: {
            $0.base.contains(player.alias) || $0.opp.contains(player.alias)
        }) else { return nil }
        let rows = matchManager.pairZoomRows(laneId: lane.id)
        guard let row = rows.first(where: { $0.hole == hole }) else { return nil }
        return lane.base.contains(player.alias) ? row.vueltaAccum : -row.vueltaAccum
    }

    private func strokesOnHole(si: Int, sVsBase: Double) -> Int {
        guard si > 0 else { return 0 }
        let n = Int(sVsBase)
        return n / 18 + (si <= n % 18 ? 1 : 0)
    }

    private func cellColor(_ diff: Int?) -> Color {
        guard let d = diff else { return .cDisabled }
        return d > 0 ? .cBrick : d < 0 ? .cFairwayL : .cInk
    }

    private func parTextColor(_ par: Int) -> Color {
        switch par {
        case 3: return Color(red: 0.184, green: 0.420, blue: 0.420)
        case 5: return Color(red: 0.663, green: 0.475, blue: 0.184)
        default: return .cMuted
        }
    }

    private func hcBg(_ hc: Int) -> Color {
        if hc <= 6  { return Color(red: 0.965, green: 0.851, blue: 0.812) }
        if hc <= 12 { return Color(red: 0.953, green: 0.902, blue: 0.769) }
        return Color(red: 0.863, green: 0.922, blue: 0.867)
    }
}

// MARK: - Shared utilities

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    @ViewBuilder
    func caddySheetDetents() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.large])
        } else { self }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}

private func caddyMoneyColor(_ v: Int) -> Color { v > 0 ? .cFairwayL : v < 0 ? .cBrick : .cMuted }
private func caddyMoneyStr(_ v: Int) -> String { v == 0 ? "$0" : (v > 0 ? "+$\(v)" : "-$\(abs(v))") }

// Muestra strokes sin decimal cuando es entero, con un decimal cuando hay medio punto (ej. "1", "1.5").
private func caddyStrokeStr(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
}

// Bruto/neto acumulado de un jugador dentro de un matchup (lane), para el audit contra el caddie rival.
private struct GrossNetLine: Identifiable {
    let id = UUID()
    let alias: String
    let gross: Int
    let net: Double
    let hasStrokes: Bool
}

// MARK: - Resultados sheet — Caddie Briefing por oponente

// Destino del detalle de unidades (Manual punto 14) — un matchup individual o una lane de parejas.
enum UnitLogTarget: Identifiable {
    case individual(String)
    case pair(UUID)
    var id: String {
        switch self {
        case .individual(let alias): return "IND-\(alias)"
        case .pair(let laneId): return "PAR-\(laneId.uuidString)"
        }
    }
}

// MARK: - Match Zoom — historia completa hoyo por hoyo de un match (Bloque 6 "Reporte Vivo")
//
// Se abre tocando la matchCard compacta en Resultado. Reusa exactamente los mismos datos que
// ya calcula MatchManager (individualZoomRows/pairZoomRows/walletSnapshot) — no agrega cálculo
// nuevo. Toggle F9/B9 para no listar 18 hoyos de golpe; abajo, el mismo desglose de dinero.

struct MatchZoomView: View {
    @ObservedObject var matchManager: MatchManager
    let target: UnitLogTarget
    @Environment(\.dismiss) private var dismiss
    @State private var segment: String = "F9"

    private var zoomTitle: String {
        switch target {
        case .individual(let opp): return "\(matchManager.yoAlias) vs \(opp)"
        case .pair(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return "Pareja" }
            return "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
        }
    }

    private var wallet: WalletLine? {
        switch target {
        case .individual(let opp): return matchManager.walletSnapshot().lines.first { $0.opponentAlias == opp }
        case .pair(let laneId):    return matchManager.walletSnapshot().lines.first { $0.laneId == laneId }
        }
    }

    private var segmentHoles: Set<Int> {
        let order = matchManager.playOrder()
        return Set(segment == "F9" ? order.prefix(9) : order.suffix(9))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.965, green: 0.953, blue: 0.925).ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("", selection: $segment) {
                        Text("F9").tag("F9")
                        Text("B9").tag("B9")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                    ScrollView {
                        VStack(spacing: 0) {
                            switch target {
                            case .individual(let opp): individualTable(opp: opp)
                            case .pair(let laneId):     pairTable(laneId: laneId)
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.890, green: 0.875, blue: 0.824), lineWidth: 1))
                        .padding(.horizontal, 16)
                    }

                    if let w = wallet {
                        Color(red: 0.890, green: 0.875, blue: 0.824).frame(height: 1)
                        zoomWalletRow(w)
                    }
                }
            }
            .navigationTitle(zoomTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
    }

    // MARK: Tabla individual — Hoyo | Bruto | Neto | Strokes | Resultado | Unidad

    @ViewBuilder
    private func individualTable(opp: String) -> some View {
        let rows = matchManager.individualZoomRows(opponentAlias: opp).filter { segmentHoles.contains($0.hole) }
        if rows.isEmpty {
            zoomEmptyHint
        } else {
            zoomHeaderRow()
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 8) {
                    zoomCell("\(r.hole)", 28, .cMuted, mono: true)
                    zoomCell("\(r.yoGross)/\(r.oppGross)", 56, .cInk, mono: true)
                    zoomCell(r.yoStrokes > 0.001 || r.oppStrokes > 0.001
                                ? "\(caddyStrokeStr(r.yoNet))/\(caddyStrokeStr(r.oppNet))" : "—",
                             56, .cFairwayL, mono: true)
                    zoomCell(strokesLabel(yo: r.yoStrokes, opp: r.oppStrokes, oppAlias: opp), 54, .cMuted, mono: true)
                    zoomResultCell(r.result)
                    zoomUnitCell(hole: r.hole, aliases: [matchManager.yoAlias, opp])
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                if idx < rows.count - 1 { Color(red: 0.941, green: 0.929, blue: 0.898).frame(height: 1) }
            }
        }
    }

    // MARK: Tabla parejas — Hoyo | Base | Rival | Resultado | Unidad

    @ViewBuilder
    private func pairTable(laneId: UUID) -> some View {
        if let lane = matchManager.lanes.first(where: { $0.id == laneId }) {
            let sign = lane.base.contains(matchManager.yoAlias) ? 1 : -1
            let rows = matchManager.pairZoomRows(laneId: laneId).filter { segmentHoles.contains($0.hole) }
            if rows.isEmpty {
                zoomEmptyHint
            } else {
                zoomHeaderRowPair()
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                    HStack(spacing: 8) {
                        zoomCell("\(r.hole)", 28, .cMuted, mono: true)
                        zoomCell(pairSideLabel(r.basePlayers), 104, .cInk, mono: true)
                        zoomCell(pairSideLabel(r.oppPlayers), 104, .cInk, mono: true)
                        zoomResultCell(r.result * sign)
                        zoomUnitCell(hole: r.hole, aliases: lane.base + lane.opp)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if idx < rows.count - 1 { Color(red: 0.941, green: 0.929, blue: 0.898).frame(height: 1) }
                }
            }
        } else {
            zoomEmptyHint
        }
    }

    private func pairSideLabel(_ players: [PairBallLine]) -> String {
        players.map { p in
            let strokes = p.individualStrokes + p.laneStrokes
            return strokes > 0.001 ? "\(p.alias) \(p.gross)→\(caddyStrokeStr(p.net))" : "\(p.alias) \(p.gross)"
        }.joined(separator: " ")
    }

    private func strokesLabel(yo: Double, opp: Double, oppAlias: String) -> String {
        if yo > 0.001 { return "\(matchManager.yoAlias)-\(caddyStrokeStr(yo))" }
        if opp > 0.001 { return "\(oppAlias)-\(caddyStrokeStr(opp))" }
        return "—"
    }

    // MARK: Sub-vistas de tabla

    // Columnas del individual: bruto y neto van separados porque cada uno es un número corto.
    private func zoomHeaderRow() -> some View {
        HStack(spacing: 8) {
            zoomHeader("H", 28)
            zoomHeader("Bruto", 56)
            zoomHeader("Neto", 56)
            zoomHeader("Strokes", 54)
            zoomHeader("Res", 34)
            zoomHeader("U", 40)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    // Columnas de parejas: bruto+neto+strokes de los 2 jugadores de cada lado ya vienen concatenados
    // en un solo string (pairSideLabel), así que cada lado es UNA columna ancha, no 3 columnas cortas.
    private func zoomHeaderRowPair() -> some View {
        HStack(spacing: 8) {
            zoomHeader("H", 28)
            zoomHeader("Base", 104)
            zoomHeader("Rival", 104)
            zoomHeader("Res", 34)
            zoomHeader("U", 40)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private func zoomHeader(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold)).foregroundColor(.cMuted)
            .frame(width: width, alignment: .leading)
    }

    private func zoomCell(_ text: String, _ width: CGFloat, _ color: Color, mono: Bool) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: mono ? .monospaced : .default))
            .foregroundColor(color)
            .frame(width: width, alignment: .leading)
            .lineLimit(1)
    }

    private func zoomResultCell(_ result: Int) -> some View {
        let color: Color = result > 0 ? .cFairwayL : result < 0 ? .cBrick : .cMuted
        let label = result == 0 ? "E" : result > 0 ? "+\(result)" : "\(result)"
        return Text(label)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .frame(width: 34, alignment: .leading)
    }

    // Códigos de unidad manual (units != 0) marcados en ese hoyo para cualquiera de estos aliases.
    private func zoomUnitCell(hole: Int, aliases: [String]) -> some View {
        let events = (matchManager.unitEventsByHole[hole] ?? []).filter { aliases.contains($0.alias) && $0.units != 0 }
        let label = events.isEmpty ? "·" : events.map { "\($0.alias):\($0.code)" }.joined(separator: " ")
        return Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(events.isEmpty ? .cDisabled : .cFairway)
            .frame(width: 40, alignment: .leading)
            .lineLimit(1)
    }

    private var zoomEmptyHint: some View {
        Text("Sin hoyos jugados en \(segment) todavía.")
            .font(.system(size: 12)).foregroundColor(.cDisabled)
            .padding(16)
    }

    // Mismo desglose de dinero que la tarjeta compacta (V/P/C/M/U + total) — copia local porque
    // walletBreakdownRow vive en ResultsSheetView y depende de su propio @State (unitLogTarget).
    private func zoomWalletRow(_ w: WalletLine) -> some View {
        HStack(spacing: 10) {
            zoomMoneyChip("V", w.vueltaMoney)
            zoomMoneyChip("P", w.presionMoney)
            zoomMoneyChip("C", w.carryActive ? w.carryMoney : nil)
            zoomMoneyChip("M", w.matchMoney)
            zoomMoneyChip("U", w.unitsMoney)
            Spacer()
            Text(caddyMoneyStr(w.totalMoney))
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(caddyMoneyColor(w.totalMoney))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func zoomMoneyChip(_ label: String, _ value: Int?) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.cDisabled)
            Text(value == nil ? "–" : caddyMoneyStr(value!))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(value == nil ? .cDisabled : caddyMoneyColor(value!))
        }
    }
}

struct ResultsSheetView: View {
    @ObservedObject var matchManager: MatchManager
    @Binding var correctionRequest: ScoreCorrection?
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAlias: String? = nil
    @State private var detailHole: Int? = nil
    @State private var unitLogTarget: UnitLogTarget? = nil
    @State private var matchZoomTarget: UnitLogTarget? = nil

    private var opponents: [PlayerModel] {
        matchManager.players.filter { $0.alias != matchManager.yoAlias }
    }
    private var selectedOpp: PlayerModel? {
        guard let a = selectedAlias else { return nil }
        return matchManager.players.first { $0.alias == a }
    }

    var body: some View {
        ZStack {
            if !embedded { Color.cBg.ignoresSafeArea() }
            VStack(spacing: 0) {
                if !embedded {
                    Capsule()
                        .fill(Color.cDisabled)
                        .frame(width: 36, height: 4)
                        .padding(.top, 12).padding(.bottom, 10)

                    // Course + yo
                    let courseId = matchManager.courseId.isEmpty ? "CGM" : matchManager.courseId
                    Text("\(courseId)  ·  \(matchManager.yoAlias)")
                        .font(.system(size: 11.5))
                        .foregroundColor(.cMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.bottom, 12)
                }

                // Opponent chip selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(opponents) { opp in oppChip(opp) }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 14)

                // Detail scroll
                if let opp = selectedOpp {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 12) {
                            individualCard(opp: opp)
                            ForEach(lanesForOpp(opp.alias)) { lane in
                                pairCard(lane: lane, opp: opp)
                            }
                            scorecardStrip(opp: opp)
                            if let h = detailHole {
                                holeDetailCard(hole: h, opp: opp)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .animation(.spring(duration: 0.25), value: detailHole)
                        .padding(.horizontal, 18).padding(.bottom, 32)
                    }
                    .onChange(of: selectedAlias) { _, _ in detailHole = nil }
                } else if opponents.isEmpty {
                    Text("Configura jugadores en ⚙ para ver resultados.")
                        .font(.system(size: 13)).foregroundColor(.cMuted)
                        .multilineTextAlignment(.center).padding(40)
                } else {
                    Text("Toca un oponente")
                        .font(.system(size: 14)).foregroundColor(.cMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { if selectedAlias == nil { selectedAlias = opponents.first?.alias } }
        .sheet(item: $unitLogTarget) { target in
            NavigationStack {
                UnitLogDetailView(title: unitLogTitle(target), entries: unitLogEntries(target))
            }
        }
        .sheet(item: $matchZoomTarget) { target in
            MatchZoomView(matchManager: matchManager, target: target)
        }
    }

    // MARK: Detalle de unidades (Manual punto 14) — hoyo, jugador, tipo, ganó/perdió

    private func unitLogTitle(_ target: UnitLogTarget) -> String {
        switch target {
        case .individual(let opp): return "Unidades · \(matchManager.yoAlias) vs \(opp)"
        case .pair(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return "Unidades · Pareja" }
            return "Unidades · \(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
        }
    }

    private func unitLogEntries(_ target: UnitLogTarget) -> [UnitLogEntry] {
        switch target {
        case .individual(let opp):
            return matchManager.unitLogEntriesForZoom(includeIndividual: true, includePair: false)
                .filter { $0.scope == .individual && $0.vs == opp }
        case .pair(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return [] }
            let player = lane.base.joined(separator: "+")
            let vs     = lane.opp.joined(separator: "+")
            return matchManager.unitLogEntriesForZoom(includeIndividual: false, includePair: true)
                .filter { $0.scope == .parejas && $0.player == player && $0.vs == vs }
        }
    }

    private func unitTarget(for w: WalletLine) -> UnitLogTarget? {
        if let opp = w.opponentAlias { return .individual(opp) }
        if let laneId = w.laneId { return .pair(laneId) }
        return nil
    }

    // MARK: Opponent chip

    private func oppChip(_ opp: PlayerModel) -> some View {
        let sel = selectedAlias == opp.alias
        return Button { selectedAlias = opp.alias } label: {
            VStack(spacing: 4) {
                Text(opp.alias)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(sel ? .cBg : .cInk)
                    .frame(width: 52, height: 52)
                    .background(sel ? Color.cFairway : Color.cSurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(sel ? Color.cFairway : Color.cBorder, lineWidth: 1.5))
                Text(opp.name.components(separatedBy: " ").first ?? "")
                    .font(.system(size: 9))
                    .foregroundColor(sel ? .cFairway : .cMuted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Individual card

    private func individualCard(opp: PlayerModel) -> some View {
        let rows  = matchManager.individualZoomRows(opponentAlias: opp.alias)
        let last  = rows.last
        let totalV = last?.vueltaAccum ?? 0
        let f9V    = matchManager.individualF9Vuelta(opponentAlias: opp.alias)
        let b9V    = totalV - f9V
        let openP  = last?.openPressures ?? []
        let wallet = matchManager.walletSnapshot().lines.first { $0.opponentAlias == opp.alias }

        // Bruto/neto acumulado por jugador — para el audit contra el caddie rival (Manual punto 12).
        let played = rows.filter { $0.yoGross > 0 && $0.oppGross > 0 }
        let grossNet = [
            GrossNetLine(alias: matchManager.yoAlias,
                         gross: played.map(\.yoGross).reduce(0, +),
                         net: played.map(\.yoNet).reduce(0, +),
                         hasStrokes: played.contains { $0.yoStrokes > 0.001 }),
            GrossNetLine(alias: opp.alias,
                         gross: played.map(\.oppGross).reduce(0, +),
                         net: played.map(\.oppNet).reduce(0, +),
                         hasStrokes: played.contains { $0.oppStrokes > 0.001 })
        ]

        return matchCard(
            title: "INDIVIDUAL",
            subtitle: "\(matchManager.yoAlias) vs \(opp.alias)",
            grossNet: grossNet,
            f9V: f9V, b9V: b9V,
            openPressures: openP,
            wallet: wallet,
            hasData: !rows.isEmpty,
            zoomTarget: .individual(opp.alias)
        )
    }

    // MARK: Pair card

    private func pairCard(lane: LaneModel, opp: PlayerModel) -> some View {
        let rows     = matchManager.pairZoomRows(laneId: lane.id)
        let last     = rows.last
        let yoBase   = lane.base.contains(matchManager.yoAlias)
        let sign     = yoBase ? 1 : -1
        let totalV   = (last?.vueltaAccum ?? 0) * sign
        let f9V      = matchManager.pairF9Vuelta(laneId: lane.id) * sign
        let b9V      = totalV - f9V
        let openP    = (last?.openPressures ?? []).map { $0 * sign }
        let baseL    = lane.base.joined(separator: "+")
        let oppL     = lane.opp.joined(separator: "+")
        let wallet   = matchManager.walletSnapshot().lines.first { $0.laneId == lane.id }

        // Bruto/neto acumulado por jugador de cada lado de la lane (Manual punto 12).
        var totals: [String: (gross: Int, net: Double, strokes: Double)] = [:]
        for row in rows {
            for line in row.basePlayers + row.oppPlayers where line.gross > 0 {
                var t = totals[line.alias] ?? (0, 0, 0)
                t.gross += line.gross
                t.net += line.net
                t.strokes += line.individualStrokes + line.laneStrokes
                totals[line.alias] = t
            }
        }
        let grossNet = (lane.base + lane.opp).map { alias -> GrossNetLine in
            let t = totals[alias] ?? (0, 0, 0)
            return GrossNetLine(alias: alias, gross: t.gross, net: t.net, hasStrokes: t.strokes > 0.001)
        }

        return matchCard(
            title: "PAREJA",
            subtitle: "\(baseL) vs \(oppL)",
            grossNet: grossNet,
            f9V: f9V, b9V: b9V,
            openPressures: openP,
            wallet: wallet,
            hasData: !rows.isEmpty,
            zoomTarget: .pair(lane.id)
        )
    }

    // Shared card builder for individual and pair.
    // Siempre despliega los 5 conceptos completos (Vuelta, Presión, Carry, Match, Unidades) — nunca resumido.
    private func matchCard(title: String, subtitle: String,
                           grossNet: [GrossNetLine],
                           f9V: Int, b9V: Int,
                           openPressures: [Int], wallet: WalletLine?,
                           hasData: Bool, zoomTarget: UnitLogTarget) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            // Header — toca la tarjeta completa para abrir el Zoom a pantalla completa (historia hoyo
            // por hoyo de este match: bruto/neto/strokes/unidades, F9 y B9). El botón "U" del wallet
            // (más abajo) sigue abriendo su propio detalle sin disparar este tap, por buttonStyle(.plain).
            Button { matchZoomTarget = zoomTarget } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cMuted).kerning(0.5)
                    Spacer()
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cMuted).lineLimit(1)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.cDisabled)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hasData {
                // Bruto → neto por jugador (quien recibe strokes) — para el audit contra el caddie rival.
                if !grossNet.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(grossNet) { g in grossNetChip(g) }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.bottom, 8)
                }

                // F9 / B9 + presiones abiertas — todo en una sola línea (regla de Daniel: sin resúmenes en filas separadas)
                HStack(spacing: 0) {
                    segmentCell("F9", vuelta: f9V)
                    Color.cRowDiv.frame(width: 1)
                    segmentCell("B9", vuelta: b9V)
                    if !openPressures.isEmpty {
                        Color.cRowDiv.frame(width: 1)
                        pressCell(openPressures)
                    }
                }
                .padding(.bottom, 8)

                Color.cBorder.frame(height: 1)
                if let w = wallet {
                    walletBreakdownRow(w)
                }

            } else {
                Text("Sin datos aún — anota golpes para ver resultado")
                    .font(.system(size: 12)).foregroundColor(.cDisabled)
                    .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
    }

    // Chip de bruto → neto acumulado por jugador (mismo patrón que playerLine en holeDetailCard).
    private func grossNetChip(_ g: GrossNetLine) -> some View {
        HStack(spacing: 3) {
            Text(g.alias)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)
            if g.gross > 0 {
                Text("\(g.gross)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
                if g.hasStrokes {
                    Text("→\(caddyStrokeStr(g.net))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cFairwayL)
                    // Strokes exactos = bruto - neto (ya viene neteado desde individualZoomRows/pairZoomRows) —
                    // se muestra aparte para no obligar al caddie a restar de cabeza.
                    Text("(-\(caddyStrokeStr(Double(g.gross) - g.net)))")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cMuted)
                }
            } else {
                Text("—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.cDisabled)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Color.cBg).cornerRadius(6)
    }

    // Fila de dinero completa: Vuelta, Presión, Carry, Match, Unidades y Total.
    // Siempre se despliegan los 5 conceptos — nunca resumido (regla de Daniel).
    private func walletBreakdownRow(_ w: WalletLine) -> some View {
        HStack(spacing: 10) {
            moneyChip("V", w.vueltaMoney)
            moneyChip("P", w.presionMoney)
            if w.carryActive { moneyChip("C", w.carryMoney) } else { moneyChip("C", nil) }
            moneyChip("M", w.matchMoney)
            Button { unitLogTarget = unitTarget(for: w) } label: {
                moneyChip("U", w.unitsMoney)
            }
            .buttonStyle(.plain)
            .disabled(unitTarget(for: w) == nil)
            Spacer()
            Text(caddyMoneyStr(w.totalMoney))
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(caddyMoneyColor(w.totalMoney))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func moneyChip(_ label: String, _ value: Int?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.cDisabled)
            Text(value == nil ? "–" : caddyMoneyStr(value!))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(value == nil ? .cDisabled : caddyMoneyColor(value!))
        }
    }

    // MARK: Segment cell (F9 / B9)

    private func segmentCell(_ label: String, vuelta: Int) -> some View {
        let color: Color = vuelta > 0 ? .cFairwayL : vuelta < 0 ? .cBrick : .cMuted
        let vLabel = vuelta == 0 ? "E" : vuelta > 0 ? "+\(vuelta)" : "\(vuelta)"
        return VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)
            Text(vLabel)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text("Vuelta")
                .font(.system(size: 9)).foregroundColor(.cDisabled)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    // Columna de presiones abiertas — misma línea que F9/B9, cada presión con su valor propio.
    private func pressCell(_ pressures: [Int]) -> some View {
        VStack(spacing: 4) {
            Text("PRES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)
            HStack(spacing: 6) {
                ForEach(Array(pressures.enumerated()), id: \.offset) { _, p in
                    Text(p == 0 ? "E" : p > 0 ? "+\(p)" : "\(p)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(p > 0 ? .cFairwayL : p < 0 ? .cBrick : .cMuted)
                }
            }
            Text("Abiertas")
                .font(.system(size: 9)).foregroundColor(.cDisabled)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    // MARK: Mini scorecard strip (yo vs opp)

    private func scorecardStrip(opp: PlayerModel) -> some View {
        let order  = matchManager.playOrder()
        let yo     = matchManager.yoAlias
        let pars   = order.map { matchManager.getHole($0)?.par ?? 4 }
        let yoS    = order.map { matchManager.getScore(hole: $0, player: yo) }
        let oppS   = order.map { matchManager.getScore(hole: $0, player: opp.alias) }
        let strokesPerHole = order.map { matchManager.individualMatchupStrokes(yoAlias: yo, oppAlias: opp.alias, hole: $0, carryAlias: nil) }
        let yoNet  = zip(yoS, strokesPerHole).map { Double($0) - $1.yo }
        let oppNet = zip(oppS, strokesPerHole).map { Double($0) - $1.opp }

        return VStack(alignment: .leading, spacing: 0) {
            Text("GOLPES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted).kerning(0.5)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hole numbers row — tap to select hole
                    HStack(spacing: 0) {
                        Text("H")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.788, green: 0.851, blue: 0.800))
                            .frame(width: 36, alignment: .leading).padding(.leading, 14)
                        ForEach(Array(order.enumerated()), id: \.offset) { i, h in
                            let sel = detailHole == h
                            Text("\(h)")
                                .font(.system(size: 10, weight: sel ? .bold : .semibold, design: .monospaced))
                                .foregroundColor(sel ? .cGold : Color(red: 0.788, green: 0.851, blue: 0.800))
                                .frame(width: 26)
                                .background(sel ? Color.white.opacity(0.12) : Color.clear)
                                .onTapGesture { withAnimation(.spring(duration: 0.22)) { detailHole = detailHole == h ? nil : h } }
                        }
                    }
                    .frame(height: 26).background(Color.cFairway)

                    Color.cBorder.frame(height: 1)

                    // Yo scores
                    HStack(spacing: 0) {
                        Text(yo)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.cFairwayL)
                            .frame(width: 36, alignment: .leading).padding(.leading, 14)
                        ForEach(Array(order.enumerated()), id: \.offset) { i, h in
                            scoreCell(score: yoS[i], par: pars[i], strokes: strokesPerHole[i].yo, net: yoNet[i])
                                .background(detailHole == h ? Color.cGold.opacity(0.12) : Color.clear)
                                .onTapGesture { withAnimation(.spring(duration: 0.22)) { detailHole = detailHole == h ? nil : h } }
                        }
                    }
                    .frame(height: 32).background(Color.cSurface)

                    Color.cRowDiv.frame(height: 1)

                    // Opp scores
                    HStack(spacing: 0) {
                        Text(opp.alias)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.cMuted)
                            .frame(width: 36, alignment: .leading).padding(.leading, 14)
                        ForEach(Array(order.enumerated()), id: \.offset) { i, h in
                            scoreCell(score: oppS[i], par: pars[i], strokes: strokesPerHole[i].opp, net: oppNet[i])
                                .background(detailHole == h ? Color.cGold.opacity(0.10) : Color(red: 0.984, green: 0.980, blue: 0.960))
                                .onTapGesture { withAnimation(.spring(duration: 0.22)) { detailHole = detailHole == h ? nil : h } }
                        }
                    }
                    .frame(height: 32).background(Color(red: 0.984, green: 0.980, blue: 0.960))
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
    }

    // Bruto solo, o "bruto/neto" cuando el jugador recibe stroke en ese hoyo (BetZoomCard.gnCell portado aquí).
    private func scoreCell(score: Int, par: Int, strokes: Double = 0, net: Double = 0) -> some View {
        let hasStroke = strokes > 0.001
        let text  = score <= 0 ? "·" : (hasStroke ? "\(score)/\(caddyStrokeStr(net))" : "\(score)")
        let diff  = score > 0 ? score - par : 0
        let color: Color = score <= 0 ? .cDisabled
                         : diff > 0   ? .cBrick
                         : diff < 0   ? .cFairwayL
                         : .cInk
        return Text(text)
            .font(.system(size: 12, weight: score > 0 ? .semibold : .regular, design: .monospaced))
            .foregroundColor(color)
            .frame(width: hasStroke ? 42 : 26)
    }

    // MARK: Hole detail card — tarjeta plena + navegación por hoyo

    private func holeDetailCard(hole: Int, opp: PlayerModel) -> some View {
        let order    = matchManager.playOrder()
        let idx      = order.firstIndex(of: hole) ?? 0
        let prevH    = idx > 0                  ? order[idx - 1] : nil
        let nextH    = idx < order.count - 1    ? order[idx + 1] : nil
        let hd       = matchManager.getHole(hole)
        let par      = hd?.par ?? 4
        let hc       = hd?.si ?? 9
        let yo       = matchManager.yoAlias

        // Individual row
        let indRows  = matchManager.individualZoomRows(opponentAlias: opp.alias)
        let indRow   = indRows.first { $0.hole == hole }

        // Pair rows (with full player lines)
        let laneRows: [(lane: LaneModel, row: PairZoomRow)] = lanesForOpp(opp.alias).compactMap { lane in
            guard let row = matchManager.pairZoomRows(laneId: lane.id).first(where: { $0.hole == hole }) else { return nil }
            return (lane, row)
        }

        return VStack(alignment: .leading, spacing: 0) {

            // ── Header: ←  HOYO N · Par P · HCP H  →  ✕ ────────────────
            HStack(spacing: 0) {
                Button {
                    if let p = prevH { withAnimation(.spring(duration: 0.22)) { detailHole = p } }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(prevH.map { "H\($0)" } ?? "").font(.system(size: 10))
                    }
                    .foregroundColor(prevH != nil ? .cFairway : .cDisabled)
                    .frame(width: 44, height: 40)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 1) {
                    Text("HOYO \(hole)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.cInk)
                    Text("Par \(par) · HCP \(hc)")
                        .font(.system(size: 10)).foregroundColor(.cMuted)
                }

                Spacer()

                HStack(spacing: 0) {
                    Button {
                        if let n = nextH { withAnimation(.spring(duration: 0.22)) { detailHole = n } }
                    } label: {
                        HStack(spacing: 3) {
                            Text(nextH.map { "H\($0)" } ?? "").font(.system(size: 10))
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(nextH != nil ? .cFairway : .cDisabled)
                        .frame(width: 44, height: 40)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(duration: 0.22)) { detailHole = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18)).foregroundColor(.cDisabled)
                    }
                    .buttonStyle(.plain).padding(.trailing, 10)
                }
            }
            .padding(.leading, 4)

            Color.cBorder.frame(height: 1)

            // ── Tarjeta plena: todos los jugadores ────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Row labels
                    VStack(alignment: .leading, spacing: 0) {
                        Text("").frame(height: 28)
                        Color.cBorder.frame(height: 1)
                        Text("Bruto").font(.system(size: 11)).foregroundColor(.cMuted).frame(height: 28)
                        Text("Putts").font(.system(size: 11)).foregroundColor(.cMuted).frame(height: 24)
                    }
                    .frame(width: 48, alignment: .leading).padding(.leading, 14)

                    ForEach(matchManager.players) { p in
                        let g = matchManager.getScore(hole: hole, player: p.alias)
                        let t = matchManager.getPutts(hole: hole, player: p.alias)
                        let d = g > 0 ? g - par : 0
                        let isOpp = p.alias == opp.alias
                        let isYo  = p.alias == yo

                        Button {
                            correctionRequest = ScoreCorrection(hole: hole, alias: p.alias)
                            dismiss()
                        } label: {
                            VStack(spacing: 0) {
                                // Alias + mic hint
                                HStack(spacing: 2) {
                                    Text(p.alias)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(isYo ? .cFairwayL : isOpp ? .cBrick.opacity(0.8) : .cMuted)
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 7))
                                        .foregroundColor(.cDisabled)
                                }
                                .frame(maxWidth: .infinity).frame(height: 28)

                                Color.cBorder.frame(height: 1)

                                // Bruto
                                Text(g > 0 ? "\(g)" : "—")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(g <= 0 ? .cDisabled : d > 0 ? .cBrick : d < 0 ? .cFairwayL : .cInk)
                                    .frame(maxWidth: .infinity).frame(height: 28)

                                // Putts
                                Text(t > 0 ? "(\(t))" : "·")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(t > 0 ? .cMuted : .cDisabled)
                                    .frame(maxWidth: .infinity).frame(height: 24)
                            }
                            .frame(width: 46)
                            .background(isYo ? Color.cFairway.opacity(0.06) : isOpp ? Color.cBrick.opacity(0.04) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)

            // ── Oyes · Unidades · Notas ───────────────────────────────────
            let showEvt = (par == 3 && !(matchManager.oyesRanksByHole[hole]?.isEmpty ?? true))
                       || !(matchManager.unitEventsByHole[hole]?.isEmpty ?? true)
            if showEvt {
                Color.cBorder.frame(height: 1)
                holeEventsSection(hole: hole, par: par)
            }

            // ── Individual: yo vs opp en este hoyo ───────────────────────
            if let r = indRow {
                Color.cBorder.frame(height: 1)
                let winner = r.result == 0 ? "Empate" : r.result > 0 ? "\(yo) gana" : "\(opp.alias) gana"
                let aColor: Color = r.vueltaAccum > 0 ? .cFairwayL : r.vueltaAccum < 0 ? .cBrick : .cMuted
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INDIVIDUAL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cMuted).kerning(0.5)
                        Text(winner).font(.system(size: 12)).foregroundColor(.cInk)
                        // Neto side by side
                        HStack(spacing: 8) {
                            Text("\(yo) \(r.yoStrokes > 0 ? String(format: "%.1f", r.yoNet) : "\(r.yoGross)")")
                            Text("\(opp.alias) \(r.oppStrokes > 0 ? String(format: "%.1f", r.oppNet) : "\(r.oppGross)")")
                        }
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.cMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Acum").font(.system(size: 10)).foregroundColor(.cMuted)
                        Text(r.vueltaAccum == 0 ? "E" : r.vueltaAccum > 0 ? "+\(r.vueltaAccum)" : "\(r.vueltaAccum)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(aColor)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }

            // ── Parejas: todos los jugadores de la lane ──────────────────
            ForEach(laneRows, id: \.lane.id) { lr in
                let yoBase  = lr.lane.base.contains(yo)
                let sign    = yoBase ? 1 : -1
                let pResult = lr.row.result * sign
                let pAccum  = lr.row.vueltaAccum * sign
                let winner  = pResult == 0 ? "Empate" : pResult > 0 ? "Tu pareja gana" : "Oponentes ganan"
                let pColor: Color = pAccum > 0 ? .cFairwayL : pAccum < 0 ? .cBrick : .cMuted

                Color.cBorder.frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("PAREJA")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cMuted).kerning(0.5)
                        Text("· \(lr.lane.base.joined(separator: "+")) vs \(lr.lane.opp.joined(separator: "+"))")
                            .font(.system(size: 10)).foregroundColor(.cMuted).lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Acum").font(.system(size: 10)).foregroundColor(.cMuted)
                            Text(pAccum == 0 ? "E" : pAccum > 0 ? "+\(pAccum)" : "\(pAccum)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(pColor)
                        }
                    }

                    // Base side
                    HStack(spacing: 6) {
                        Text("Base:").font(.system(size: 10, weight: .semibold)).foregroundColor(.cMuted).frame(width: 36, alignment: .leading)
                        ForEach(lr.row.basePlayers, id: \.alias) { line in
                            playerLine(line: line, par: par)
                        }
                    }
                    // Opp side
                    HStack(spacing: 6) {
                        Text("Opp:").font(.system(size: 10, weight: .semibold)).foregroundColor(.cMuted).frame(width: 36, alignment: .leading)
                        ForEach(lr.row.oppPlayers, id: \.alias) { line in
                            playerLine(line: line, par: par)
                        }
                    }

                    Text(winner).font(.system(size: 11)).foregroundColor(.cInk)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }

            if indRow == nil && laneRows.isEmpty {
                Color.cBorder.frame(height: 1)
                Text("Sin datos de match — anota scores para ver resultado")
                    .font(.system(size: 12)).foregroundColor(.cDisabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cGold.opacity(0.5), lineWidth: 1.5))
        // Swipe izquierda/derecha para navegar hoyos
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    withAnimation(.spring(duration: 0.22)) {
                        if v.translation.width > 40, let p = prevH { detailHole = p }
                        else if v.translation.width < -40, let n = nextH { detailHole = n }
                    }
                }
        )
    }

    // Player chip inside pair lane (alias · bruto → neto · laneStroke dot)
    private func playerLine(line: PairBallLine, par: Int) -> some View {
        let diff = line.gross > 0 ? line.gross - par : 0
        let gColor: Color = line.gross <= 0 ? .cDisabled : diff > 0 ? .cBrick : diff < 0 ? .cFairwayL : .cInk
        return HStack(spacing: 3) {
            Text(line.alias)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)
            Text(line.gross > 0 ? "\(line.gross)" : "—")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(gColor)
            if line.laneStrokes > 0 {
                Circle().fill(Color.cFairwayL).frame(width: 5, height: 5)
                Text("→\(String(format: "%.0f", line.net))")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(.cMuted)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.cBg).cornerRadius(6)
    }

    // MARK: Sección eventos por hoyo (Oyes · Unidades · Notas)

    private func holeEventsSection(hole: Int, par: Int) -> some View {
        let ranks     = matchManager.oyesRanksByHole[hole] ?? [:]
        let allEvents = matchManager.unitEventsByHole[hole] ?? []

        // Jugadores con al menos un evento de unidad o nota
        let withData  = matchManager.players.filter { p in
            let evts = allEvents.filter { $0.alias == p.alias && $0.code != "NOTA" && $0.code != "BIRD" }
            let note = allEvents.first { $0.alias == p.alias && $0.code == "NOTA" }?.note ?? ""
            return !evts.isEmpty || !note.isEmpty
        }

        return VStack(alignment: .leading, spacing: 6) {

            // Oye ranks (par 3 con datos)
            if par == 3 && !ranks.isEmpty {
                HStack(spacing: 8) {
                    Text("Oye")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cMuted)
                    ForEach(matchManager.players) { p in
                        if let rank = ranks[p.alias] {
                            HStack(spacing: 2) {
                                Text(p.alias)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(rank == 1 ? .cBrick : .cMuted)
                                ZStack {
                                    Circle()
                                        .fill(rank == 1 ? Color.cBrick : Color.clear)
                                        .frame(width: 16, height: 16)
                                    Circle()
                                        .strokeBorder(rank == 1 ? Color.cBrick : Color.cDisabled, lineWidth: 1)
                                        .frame(width: 16, height: 16)
                                    Text("\(rank)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(rank == 1 ? .white : .cDisabled)
                                }
                            }
                        }
                    }
                    Spacer()
                }
            }

            // Unidades + notas por jugador
            ForEach(withData) { p in
                let evts = allEvents.filter { $0.alias == p.alias && $0.code != "NOTA" && $0.code != "BIRD" }
                let note = allEvents.first { $0.alias == p.alias && $0.code == "NOTA" }?.note ?? ""
                let isOyeWinner = ranks[p.alias] == 1

                HStack(spacing: 5) {
                    Text(p.alias)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cMuted)
                        .frame(width: 34, alignment: .leading)

                    if isOyeWinner {
                        Circle().fill(Color.cBrick).frame(width: 8, height: 8)
                    }

                    ForEach(evts) { ev in
                        resultEvtSquare(ev.code)
                    }

                    if !note.isEmpty {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9)).foregroundColor(.cDisabled)
                        Text(note)
                            .font(.system(size: 10)).foregroundColor(.cMuted)
                            .lineLimit(1)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func resultEvtSquare(_ code: String) -> some View {
        let label     = evtLabel(code)
        let isSpecial = ["HIO", "ALB", "B18"].contains(code.uppercased())
        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(isSpecial ? Color.cFairwayL.opacity(0.15) : Color.cBorder.opacity(0.4))
                .frame(width: 24, height: 16)
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(isSpecial ? Color.cFairwayL : Color.cDisabled, lineWidth: 1)
                .frame(width: 24, height: 16)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(isSpecial ? .cFairwayL : .cMuted)
                .minimumScaleFactor(0.5).lineLimit(1)
        }
    }

    private func evtLabel(_ code: String) -> String {
        switch code.uppercased() {
        case "EAG":          return "Águila"
        case "ALB":          return "Alb"
        case "HIO":          return "H1"
        case "B18":          return "B18"
        case "3P":           return "3P"
        case "4P":           return "4P"
        case "SANDY", "S":   return "Sandy par"
        case "CHIPN","CHIP": return "Chip"
        default:             return code
        }
    }

    // MARK: Helpers

    private func lanesForOpp(_ alias: String) -> [LaneModel] {
        matchManager.lanes.filter { $0.base.contains(alias) || $0.opp.contains(alias) }
    }
}
