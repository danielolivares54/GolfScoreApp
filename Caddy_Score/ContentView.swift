import SwiftUI

// MARK: - Design tokens

private extension Color {
    static let cBg        = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let cSurface   = Color.white
    static let cBorder    = Color(red: 0.890, green: 0.875, blue: 0.824)
    static let cRowDiv    = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let cInk       = Color(red: 0.110, green: 0.137, blue: 0.129)
    static let cMuted     = Color(red: 0.431, green: 0.416, blue: 0.361)
    static let cFairway   = Color(red: 0.114, green: 0.627, blue: 0.310) // #1DA04F, verde de marca (logo)
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
    @State private var tarjetaInitialMode: TarjetaSheetView.CardViewMode = .resultado

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
        // Bug reportado: al cambiar el hoyo de inicio desde el Setup (applySetup() preserva
        // scores a propósito, resetScores: false), la tarjeta se quedaba mostrando la misma
        // posición de scroll de antes — un índice que ahora apunta a un hoyo físico distinto
        // dentro del nuevo playOrder(). El audit/semáforo sí se recalculaba bien (ya lee
        // matchManager.startHole en vivo), pero la tarjeta visible no seguía el cambio.
        .onChange(of: matchManager.startHole) { _, _ in
            currentHoleIndex = 0
        }
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
                    .font(.system(size: 23, weight: .bold, design: .monospaced))
                    .foregroundColor(.cBg)
                Text("Par \(currentPar) · HCP \(currentHC)")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.cGreenHint)
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
        let unitEvents = matchManager.unitEventsForZoom(segmentOverride: matchManager.segmentForHole(currentHole))
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
                    .font(.system(size: 13, weight: .bold))
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

        // Avatar: verde cuando recibe golpe, gris sin golpe. strokeCount >= 1 dejaba fuera el
        // medio golpe (0.5) — el texto ya decía "medio golpe" pero el avatar se veía igual que
        // sin ventaja, el único indicador rápido de un vistazo no distinguía 0.5 de 0.
        let avatarBg: Color = strokeCount >= 2 ? .cFairwayL
                            : strokeCount > 0.001 ? .cFairway
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
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundColor(putts > 0 ? .cInk : .cDisabled)
                        }
                        .frame(width: 24)

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
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(sel ? .white : (rank == 1 ? .cBrick : .cMuted))
                        .frame(width: 34, height: 34)
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
        // individualZoomRows()/pairZoomRows() sin segmentOverride auto-detectan UN solo segmento
        // "actual" — concatenar F9+B9 explícitos cubre los 18 hoyos sin ese salto. vueltaAccum
        // reinicia en 0 al empezar B9, así que si el hoyo vigente cae en B9 hay que sumarle el
        // total de F9 para que "vuelta" sea el acumulado real del match, no solo del segmento.
        for opp in matchManager.players where opp.alias != matchManager.yoAlias && !matchManager.baseTeamAliases.contains(opp.alias) {
            let f9Rows = matchManager.individualZoomRows(opponentAlias: opp.alias, segmentOverride: "F9")
            let b9Rows = matchManager.individualZoomRows(opponentAlias: opp.alias, segmentOverride: "B9")
            let upTo = (f9Rows + b9Rows).filter { $0.hole <= currentHole }
            guard let last = upTo.last else { continue }
            let vuelta = matchManager.segmentForHole(last.hole) == "B9"
                ? matchManager.individualF9Vuelta(opponentAlias: opp.alias) + last.vueltaAccum
                : last.vueltaAccum
            chips.append(SummaryChip(
                label:      opp.alias,
                hx:         opp.strokesVsBase,
                yoStrokes:  upTo.reduce(0.0) { $0 + $1.yoStrokes  },
                oppStrokes: upTo.reduce(0.0) { $0 + $1.oppStrokes },
                lastHole:   last.hole,
                vuelta:     vuelta,
                pressures:  last.openPressures,
                units:      matchManager.unitStakeForIndividual(opponentAlias: opp.alias),
                isPair:     false
            ))
        }
        for lane in matchManager.lanes {
            let f9Rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: "F9")
            let b9Rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: "B9")
            let upTo = (f9Rows + b9Rows).filter { $0.hole <= currentHole }
            guard let last = upTo.last else { continue }
            let vuelta = matchManager.segmentForHole(last.hole) == "B9"
                ? matchManager.pairF9Vuelta(laneId: lane.id) + last.vueltaAccum
                : last.vueltaAccum
            chips.append(SummaryChip(
                label:      lane.opp.joined(separator: " "),
                hx:         lane.strokes,
                yoStrokes:  0,
                oppStrokes: 0,
                lastHole:   last.hole,
                vuelta:    vuelta,
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
        matchManager.loadBetConfig()
        // Siembra única (por ahora, pedida por Daniel): si no hay nada configurado todavía (ni
        // base de pareja ni overrides individuales — primera vez, o justo después de Cerrar
        // Ronda), usa "S y D" para cada rival individual y "S y D 4" para parejas, como apuesta
        // pareja para todos mientras se decide el flujo real de configuración.
        if matchManager.baseTeamAliases.isEmpty && matchManager.betValuesByOpponent.isEmpty {
            let templates = BetTemplateStore.shared.entries
            if let syd4 = templates.first(where: { $0.id == "SYD4" }) {
                matchManager.applyBetTemplate(syd4)
            }
            if let syd = templates.first(where: { $0.id == "SYD" }) {
                for p in matchManager.players where p.alias != matchManager.yoAlias {
                    matchManager.setBetTemplateForOpponent(p.alias, template: syd)
                }
            }
            _ = matchManager.setBaseTeam(["DAN", "ANS"])

            // Strokes de ejemplo (handicap vs DAN=base 0) — para poder revisar neto + marca ●
            // con datos reales en vez de todo en 0. Valores variados a propósito: ANS/ROB con
            // ventaja real, RIC poca, FER da golpes (negativo) — cubre los 3 casos visuales.
            let exampleStrokes: [String: Double] = ["ANS": 5, "ROB": 9, "RIC": 3, "FER": -2]
            for (alias, strokes) in exampleStrokes where matchManager.players.contains(where: { $0.alias == alias }) {
                matchManager.setStrokesVsBase(alias: alias, value: strokes)
            }
            // Strokes de pareja (adicionales a los individuales, por lane) — variados igual.
            let exampleLaneStrokes: [Set<String>: Double] = [["ROB","RIC"]: 3, ["ROB","FER"]: 1, ["RIC","FER"]: 4]
            for lane in matchManager.lanes {
                if let s = exampleLaneStrokes[Set(lane.opp)] {
                    matchManager.setLaneStrokes(id: lane.id, value: s)
                    // setLaneStrokes solo fija el número — el que lo carga es otra llamada
                    // aparte. Sin esto, effectiveLaneStrokeProfile nunca aplica el stroke a
                    // nadie (strokeCarrier queda nil), aunque el número ya esté guardado.
                    matchManager.setLaneCarrier(id: lane.id, carrier: lane.opp.first)
                }
            }
        }
        // Scores de ejemplo — guard independiente del de apuestas arriba: si alguna vez queda
        // la config de apuestas sembrada pero sin ningún score anotado (p.ej. tras reinstalar
        // la app en el simulador), esto los repone sin esperar a que el guard de arriba corra.
        if matchManager.getScore(hole: 1, player: matchManager.yoAlias) <= 0 {
            seedDemoScores()
        }
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
        applyInterMatchStrokeCarry()
        saveRoundResultToFile()
        matchManager.resetScores()
        ScoreManager.shared.clearAll()
        matchManager.clearBetConfig()
        AppDelegate.clearPendingRecord()
        currentHoleIndex = 0
        editingPlayerIdx = 0
        noteByKey = [:]
    }

    // Ajuste de stroke entre rondas (regla 2026-10-06, solo IND — TEAM queda fuera porque las
    // parejas varían de ronda a ronda). Quien ganó el B9 de un duelo da un golpe más la próxima
    // vez (el rival se vuelve más duro de vencer); quien lo perdió recibe un golpe más. Gatillado
    // por plantilla vía BetTemplate.carryMatchEnabled. Empate en B9 (0) no mueve nada — no hay
    // ganador al que asignarle la dirección del ajuste.
    //
    // Usa siempre el B9 plano (individualB9Vuelta), nunca el ajustado por Carry/Ajuste 50 — la
    // apuesta de Vuelta normal tampoco usa el ajustado (confirmado corriendo walletSnapshot con
    // datos reales el 2026-10-06), así que este ajuste se mantiene consistente con esa línea base.
    //
    // Excepción: si Ajuste 50 estuvo activo, NO se autoaplica ningún stroke — Ajuste 50 redefine
    // el stroke efectivo con su propia fórmula (ganados/perdidos, no un ±1 plano), y replicar esa
    // fórmula para el salto entre rondas es un caso raro que Daniel prefiere resolver a mano. Solo
    // se deja una bandera en lastResult para que se revise el Setup del próximo match contra ese rival.
    private func applyInterMatchStrokeCarry() {
        let opponents = matchManager.players.map(\.alias).filter { $0 != matchManager.yoAlias }
        guard !opponents.isEmpty else { return }
        let snapshot = matchManager.walletSnapshot()
        for opp in opponents {
            guard let player = matchManager.players.first(where: { $0.alias == opp }) else { continue }
            let templateId = matchManager.betValues(forOpponent: opp).templateId
            let carryEnabled = BetTemplateStore.shared.entries.first(where: { $0.id == templateId })?.carryMatchEnabled ?? true
            guard carryEnabled else { continue }

            let f9 = matchManager.individualF9Vuelta(opponentAlias: opp)
            let b9 = matchManager.individualB9Vuelta(opponentAlias: opp)
            let line = snapshot.lines.first(where: { $0.opponentAlias == opp && $0.scope == .individual })
            let matchLabel = line.map { $0.matchPoints >= 0 ? "+\($0.matchPoints)" : "\($0.matchPoints)" } ?? "—"
            let base = "F9 \(f9 >= 0 ? "+" : "")\(f9) · B9 \(b9 >= 0 ? "+" : "")\(b9) · Match \(matchLabel)"
                + " · $\(line?.totalMoney ?? 0) · \(matchManager.dateString)"

            if matchManager.isIndividualAdjust50Active(opponentAlias: opp) {
                let summary = "⚠️ AJUSTE 50 ACTIVO — revisar stroke a mano · " + base
                PlayerDirectoryStore.shared.applyMatchStrokeShift(
                    playerName: player.name, delta: 0, resultSummary: summary, roundId: matchManager.roundId
                )
                continue
            }

            // b9 > 0 = yo gané el duelo en B9 -> el rival perdió -> recibe un golpe más (+1).
            // b9 < 0 = yo perdí -> el rival ganó -> da un golpe más -> su strokeVsBase baja (-1).
            guard b9 != 0 else { continue }
            let delta: Double = b9 > 0 ? 1 : -1
            PlayerDirectoryStore.shared.applyMatchStrokeShift(
                playerName: player.name, delta: delta, resultSummary: base, roundId: matchManager.roundId
            )
        }
    }

    // Guarda el resultado final (scores + wallet) a disco antes de borrar.
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

    // MARK: Siembra de scores de ejemplo (18 hoyos, 5 jugadores)

    // Mismo criterio de "solo una vez" que el bloque de apuestas en setupOnAppear — nunca pisa
    // datos reales, solo rellena si de verdad no hay nada anotado todavía (ej. justo después de
    // reinstalar la app). Jugadores y pareja base (DAN+ANS) ya quedan fijados arriba.
    private func seedDemoScores() {
        let pars: [Int] = [4,5,3,4,3,5,4,4,4,4,5,4,4,3,4,3,4,4]
        let offsets: [(alias: String, base: Int)] = [("DAN", 0), ("ANS", 1), ("ROB", 2), ("RIC", 1), ("FER", -1)]

        for hole in 1...18 {
            let par = pars[hole - 1]
            let wiggle = hole % 4 == 0 ? 1 : (hole % 3 == 0 ? -1 : 0)
            for (alias, base) in offsets where matchManager.players.contains(where: { $0.alias == alias }) {
                let strokes = max(1, par + base + wiggle)
                let putts = strokes - par >= 1 ? 2 : 1
                matchManager.applyHoleEntry(HoleEntryData(
                    hole_number: hole, player_alias: alias,
                    strokes: strokes, putts: putts, units: nil, tags: nil))
            }
        }

        // Oyes en los pares 3 — se alterna quién gana para ver los dos colores del badge.
        let par3Holes = [3, 5, 14, 16]
        let aliases = offsets.map { $0.alias }
        for (i, hole) in par3Holes.enumerated() {
            let winner = aliases[i % aliases.count]
            let order = [winner] + aliases.filter { $0 != winner }
            var ranks: [String: Int] = [:]
            for (idx, alias) in order.enumerated() { ranks[alias] = idx + 1 }
            matchManager.setOyesRanks(hole: hole, ranksByAlias: ranks)
        }
    }
}

// MARK: - TarjetaSheetView  (02-tarjeta: hoyos-como-filas, jugadores-como-columnas)

struct TarjetaSheetView: View {
    @ObservedObject var matchManager: MatchManager
    @Binding var correctionRequest: ScoreCorrection?
    @Environment(\.dismiss) private var dismiss
    var initialMode: CardViewMode = .resultado
    @State private var mode: CardViewMode = .resultado

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
            segBtn("Resultado", active: mode == .resultado) { mode = .resultado }
            segBtn("Golpes",    active: mode == .golpes)    { mode = .golpes }
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
        // Sin segmentOverride, pairZoomRows() auto-detecta UN solo segmento "actual" — si se pide
        // un hoyo del otro segmento (ej. F9 cuando ya se juega B9) no aparecía en "rows" y esto
        // regresaba nil aunque el hoyo sí tuviera datos. Se pide explícitamente el segmento del hoyo.
        let rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: matchManager.segmentForHole(hole))
        guard let row = rows.first(where: { $0.hole == hole }) else { return nil }
        return lane.base.contains(player.alias) ? row.result : -row.result
    }

    private func holeMatchAccum(player: PlayerModel, hole: Int) -> Int? {
        guard let lane = matchManager.lanes.first(where: {
            $0.base.contains(player.alias) || $0.opp.contains(player.alias)
        }) else { return nil }
        let rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: matchManager.segmentForHole(hole))
        guard let row = rows.first(where: { $0.hole == hole }) else { return nil }
        let sign = lane.base.contains(player.alias) ? 1 : -1
        let accum = row.vueltaAccum * sign
        // vueltaAccum reinicia en 0 al empezar cada segmento — en B9 hay que sumarle el total de
        // F9 para que sea el acumulado real de los 18 hoyos, no solo el del segmento.
        if matchManager.segmentForHole(hole) == "B9" {
            return matchManager.pairF9Vuelta(laneId: lane.id) * sign + accum
        }
        return accum
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
    @State private var segment: String
    @State private var tableWidth: CGFloat = 0

    // Permite abrir el Zoom ya posicionado en F9 o B9 (ej. al tocar ese segmento en matchCard)
    // en vez de arrancar siempre en F9.
    init(matchManager: MatchManager, target: UnitLogTarget, initialSegment: String = "F9") {
        self.matchManager = matchManager
        self.target = target
        self._segment = State(initialValue: initialSegment)
    }

    private var zoomTitle: String {
        switch target {
        case .individual(let opp): return "\(matchManager.yoAlias) vs \(opp)"
        case .pair(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return "Pareja" }
            return "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
        }
    }

    // Los 9 hoyos del segmento activo, EN ORDEN de juego — se renderizan todos (jugados o no),
    // para que la tabla llene la pantalla de forma predecible y no dependa de cuántos hoyos
    // ya se jugaron (antes dejaba un hueco enorme entre los datos y la barra de dinero).
    private var segmentHolesOrdered: [Int] {
        let order = matchManager.playOrder()
        return Array(segment == "F9" ? order.prefix(9) : order.suffix(9))
    }

    // Marca de stroke — mismo lenguaje visual que el resto de la app (project_architecture_sot):
    // ● = 1 stroke, ◐ = 0.5. En dorado para que salte a la vista como "aquí hay ventaja".
    private func strokeMark(_ value: Double) -> String {
        if value <= 0.001 { return "" }
        let whole = Int(value)
        let half = abs(value - Double(whole) - 0.5) < 0.001
        if whole == 0 && half { return "◐" }
        if whole >= 1 && !half { return String(repeating: "●", count: max(1, whole)) }
        return "●\(caddyStrokeStr(value))"
    }

    private var strokeGold: Color { Color(red: 0.831, green: 0.627, blue: 0.090) } // mismo dorado de "Oyes ganador"

    // Mismo texto que ya se ve en matchCard ("DAN F9 7/4 · B9 7/3 C-9") — se repite aquí como
    // subtítulo porque el Zoom es donde el caddie audita hoyo por hoyo y necesita el mismo dato
    // de referencia sin volver a la tarjeta compacta.
    private var strokesSubtitle: String? {
        switch target {
        case .individual(let opp): return matchManager.individualStrokeSummaryLine(opponentAlias: opp)
        case .pair(let laneId): return matchManager.pairStrokeSummaryLine(laneId: laneId)
        }
    }

    // Un color fijo por posición de compañero dentro de una pareja — permite distinguir a cada
    // uno sin repetir su nombre en cada fila (el nombre ya aparece una sola vez en el header).
    private static let partnerColors: [Color] = [.cFairway, Color(red: 0.204, green: 0.396, blue: 0.573)]
    private func partnerColor(_ idx: Int) -> Color { Self.partnerColors[idx % Self.partnerColors.count] }

    // Anchos fijos de las columnas que no escalan con el ancho de pantalla.
    private let holeColWidth: CGFloat = 42 // hoyo + "P{par} H{hcp}" debajo
    private let resColWidth: CGFloat = 44
    private let accumColWidth: CGFloat = 78 // vuelta + presión juntas, mismo tamaño que Res

    // Ancho de cada columna de jugador, calculado a partir del ancho real de pantalla (tableWidth)
    // para que la tabla (H + jugador + jugador + Res + Acum) siempre quepa completa sin recortarse.
    // Antes estos 122pt eran fijos y solo cabían en los iPhones más anchos (~430pt).
    // El piso de 70 forzaba overflow en iPhones normales (~390pt): 268 fijos + 2×70 = 408 > 390,
    // así que la columna Acum (la última del HStack) quedaba parcialmente recortada por el
    // ScrollView (solo vertical, sin scroll horizontal). El piso bajó a 50 — solo protege el
    // estado inicial (tableWidth == 0 antes de que GeometryReader mida), nunca fuerza overflow
    // en un ancho real de pantalla.
    private var playerColWidth: CGFloat {
        let fixedColumns = holeColWidth + resColWidth + accumColWidth
        let gaps: CGFloat = 10 * 4 // 4 espacios en el HStack de 5 elementos
        let paddings: CGFloat = 32 + 32 // padding de la caja blanca (16x2) + padding horizontal de la fila (16x2)
        let available = tableWidth - fixedColumns - gaps - paddings
        return max(50, available / 2)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { outerGeo in
                ZStack {
                    Color(red: 0.965, green: 0.953, blue: 0.925).ignoresSafeArea()
                    VStack(spacing: 0) {
                        if let line = strokesSubtitle {
                            Text(line)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 16).padding(.top, 10)
                        }
                        Picker("", selection: $segment) {
                            Text("F9").tag("F9")
                            Text("B9").tag("B9")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)

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

                    }
                }
                .onAppear { tableWidth = outerGeo.size.width }
                .onChange(of: outerGeo.size.width) { _, newValue in tableWidth = newValue }
            }
            .navigationTitle(zoomTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }
    }

    // MARK: Tabla individual — se listan los 9 hoyos del segmento, jugados o no.

    @ViewBuilder
    private func individualTable(opp: String) -> some View {
        let rowsByHole = Dictionary(uniqueKeysWithValues: matchManager.individualZoomRows(opponentAlias: opp, segmentOverride: segment).map { ($0.hole, $0) })
        let holes = segmentHolesOrdered
        let presionSeries = matchManager.individualPresionSeries(opponentAlias: opp, holes: holes)
        // Último hoyo jugado de este segmento — su acumulado ES el subtotal del segmento
        // (vuelta vuelve a 0 al inicio de cada segmento, ver individualZoomRows).
        let lastPlayedIdx = Array(holes.enumerated()).last { rowsByHole[$0.element] != nil }?.offset
        let subtotalVuelta = lastPlayedIdx.flatMap { rowsByHole[holes[$0]]?.vueltaAccum } ?? 0
        let subtotalPres = lastPlayedIdx.map { presionSeries[$0] } ?? []
        let yoStrokesTotal = holes.compactMap { rowsByHole[$0]?.yoGross }.reduce(0, +)
        let oppStrokesTotal = holes.compactMap { rowsByHole[$0]?.oppGross }.reduce(0, +)
        let strokeTotals: [(alias: String, total: Int, color: Color)] = [
            (matchManager.yoAlias, yoStrokesTotal, .cInk),
            (opp, oppStrokesTotal, .cInk)
        ]

        zoomHeaderRow(rightAliases: [opp])
        ForEach(Array(holes.enumerated()), id: \.offset) { idx, hole in
            if let r = rowsByHole[hole] {
                HStack(spacing: 10) {
                    zoomHoleCell(hole)
                    playerScoreCell(alias: matchManager.yoAlias, hole: hole, gross: r.yoGross, net: r.yoNet, strokes: r.yoStrokes, carryExtra: matchManager.individualCarryExtraStroke(opponentAlias: opp, alias: matchManager.yoAlias, hole: hole), carryDiverges: matchManager.individualCarryDivergesAtHole(opponentAlias: opp, hole: hole), isMySide: true, color: .cInk, width: playerColWidth)
                    playerScoreCell(alias: opp, hole: hole, gross: r.oppGross, net: r.oppNet, strokes: r.oppStrokes, carryExtra: matchManager.individualCarryExtraStroke(opponentAlias: opp, alias: opp, hole: hole), carryDiverges: matchManager.individualCarryDivergesAtHole(opponentAlias: opp, hole: hole), isMySide: false, color: .cInk, width: playerColWidth)
                    zoomResultCell(r.result)
                    zoomAccumCell(vuelta: r.vueltaAccum, pres: presionSeries[idx])
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            } else {
                zoomPlaceholderRow(hole: hole)
            }
            if idx < holes.count - 1 { Color(red: 0.941, green: 0.929, blue: 0.898).frame(height: 1) }
        }
        let carryResult: Int? = (segment == "B9" && matchManager.isIndividualCarryActive(opponentAlias: opp))
            ? matchManager.individualCarryResultB9(opponentAlias: opp) : nil
        zoomSubtotalRow(segment: segment, vuelta: subtotalVuelta, pres: subtotalPres, strokes: strokeTotals, carry: carryResult)
    }

    // Suma de golpes crudos por jugador en el segmento — para el subtotal del Zoom de pareja.
    // Función normal (no @ViewBuilder): el for/if anidado para llenar el diccionario no es
    // representable como bloque de ViewBuilder.
    private func pairStrokeTotals(lane: LaneModel, holes: [Int], rowsByHole: [Int: PairZoomRow]) -> [(alias: String, total: Int, color: Color)] {
        var totals: [String: Int] = [:]
        for hole in holes {
            guard let r = rowsByHole[hole] else { continue }
            for p in r.basePlayers + r.oppPlayers { totals[p.alias, default: 0] += p.gross }
        }
        return lane.base.enumerated().map { ($1, totals[$1] ?? 0, partnerColor($0)) }
             + lane.opp.enumerated().map { ($1, totals[$1] ?? 0, partnerColor($0)) }
    }

    // MARK: Tabla parejas — mismo criterio: los 9 hoyos del segmento, jugados o no.

    @ViewBuilder
    private func pairTable(laneId: UUID) -> some View {
        if let lane = matchManager.lanes.first(where: { $0.id == laneId }) {
            let sign = lane.base.contains(matchManager.yoAlias) ? 1 : -1
            let rowsByHole = Dictionary(uniqueKeysWithValues: matchManager.pairZoomRows(laneId: laneId, segmentOverride: segment).map { ($0.hole, $0) })
            let holes = segmentHolesOrdered
            let presionSeriesRaw = matchManager.pairPresionSeries(laneId: laneId, holes: holes)
            let lastPlayedIdx = Array(holes.enumerated()).last { rowsByHole[$0.element] != nil }?.offset
            let subtotalVuelta = lastPlayedIdx.flatMap { rowsByHole[holes[$0]].map { $0.vueltaAccum * sign } } ?? 0
            let subtotalPresRaw = lastPlayedIdx.map { presionSeriesRaw[$0] } ?? []
            let subtotalPres = subtotalPresRaw.map { $0 * sign }
            let strokeTotals = pairStrokeTotals(lane: lane, holes: holes, rowsByHole: rowsByHole)

            zoomHeaderRow(rightAliases: lane.opp, leftAliases: lane.base)
            ForEach(Array(holes.enumerated()), id: \.offset) { idx, hole in
                if let r = rowsByHole[hole] {
                    let pres = presionSeriesRaw[idx].map { $0 * sign }
                    HStack(spacing: 10) {
                        zoomHoleCell(hole)
                        pairSideCell(r.basePlayers, hole: hole, laneId: laneId, isMySide: sign == 1, width: playerColWidth)
                        pairSideCell(r.oppPlayers, hole: hole, laneId: laneId, isMySide: sign == -1, width: playerColWidth)
                        zoomResultCell(r.result * sign)
                        zoomAccumCell(vuelta: r.vueltaAccum * sign, pres: pres)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                } else {
                    zoomPlaceholderRow(hole: hole)
                }
                if idx < holes.count - 1 { Color(red: 0.941, green: 0.929, blue: 0.898).frame(height: 1) }
            }
            let carryResult: Int? = (segment == "B9" && matchManager.isPairCarryActive(laneId: laneId))
                ? matchManager.pairCarryResultB9(laneId: laneId) * sign : nil
            zoomSubtotalRow(segment: segment, vuelta: subtotalVuelta, pres: subtotalPres, strokes: strokeTotals, carry: carryResult)
        } else {
            zoomPlaceholderRow(hole: 0)
        }
    }

    // Un jugador, una celda: bruto siempre, y si recibió stroke ese hoyo, el neto + el punto
    // de stroke (símbolo común de caddie: ● = 1, ◐ = 0.5) en rojo/verde según de qué lado lo
    // recibe (verde = yo/mi equipo, rojo = el oponente) — antes era dorado uniforme, pero el
    // caddie necesita ver de un vistazo quién lleva la ventaja, no solo que existe.
    // Si el stroke viene de una apuesta de Carry activa (B9), se agrega además una "C" aparte
    // con el mismo esquema de color — el Carry es una apuesta adicional, no se mezcla con el
    // punto de hándicap base.
    // Sin nombre — ya aparece una sola vez en el header de la columna (zoomHeaderNames).
    // Si este jugador tuvo evento(s) de unidad ese hoyo (Oyes, Birdie, Sandy…), el número bruto
    // se encierra en un círculo — igual que en una tarjeta de golf en papel (birdie = 1 círculo,
    // eagle/doble evento = 2 círculos concéntricos) — en vez de un símbolo aparte.
    private func playerScoreCell(alias: String, hole: Int, gross: Int, net: Double, strokes: Double, carryExtra: Double = 0, carryDiverges: Bool = false, isMySide: Bool, color: Color, width: CGFloat) -> some View {
        let hasStroke = strokes > 0.001
        let hasCarry = carryExtra > 0.001
        let sideColor: Color = isMySide ? .cFairwayL : .cBrick
        let unitCount = matchManager.unitEventCount(alias: alias, hole: hole)
        // El neto que se muestra con la flecha "→" debe reflejar TODO lo que bajó el bruto ese
        // hoyo (stroke normal + Carry si aplica) — el stroke de Carry aplica mecánicamente en
        // todos los hoyos de B9 desde la activación, así que el neto siempre lo refleja.
        let adjustedNet = net - carryExtra
        return HStack(spacing: 4) {
            if gross > 0 {
                Text("\(gross)")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .padding(unitCount > 0 ? 3 : 0)
                    .overlay(unitCount >= 1 ? Circle().stroke(Color.cFairway, lineWidth: 1.3) : nil)
                    .overlay(unitCount >= 2 ? Circle().stroke(Color.cFairway, lineWidth: 1.3).padding(-3) : nil)
                if hasStroke || hasCarry {
                    Text("→\(caddyStrokeStr(adjustedNet))")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cFairwayL)
                    if hasStroke {
                        Text(strokeMark(strokes))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(sideColor)
                    }
                    // La "C" solo se marca cuando el Carry realmente cambia quién gana este hoyo
                    // vs el resultado sin Carry — no en cada hoyo donde el stroke aplica. La
                    // mayoría de los hoyos el stroke no altera nada (ya se ganaba/perdía igual),
                    // así que marcarlos todos solo agrega ruido sin información nueva.
                    if hasCarry, carryDiverges {
                        Text("C")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(sideColor)
                    }
                }
            } else {
                Text("—").font(.system(size: 14, design: .monospaced)).foregroundColor(.cDisabled)
            }
        }
        .frame(width: width, alignment: .leading)
        .lineLimit(1)
    }

    // Lado de pareja: los 1-2 jugadores de ese lado, cada uno coloreado según su posición fija
    // (mismo orden y color que en zoomHeaderRow) en vez de repetir su nombre en cada fila.
    private func pairSideCell(_ players: [PairBallLine], hole: Int, laneId: UUID, isMySide: Bool, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(players.enumerated()), id: \.element.alias) { idx, p in
                let strokes = p.individualStrokes + p.laneStrokes
                let carryExtra = matchManager.pairCarryExtraStroke(laneId: laneId, alias: p.alias, hole: hole)
                let carryDiverges = matchManager.pairCarryDivergesAtHole(laneId: laneId, hole: hole)
                playerScoreCell(alias: p.alias, hole: hole, gross: p.gross, net: p.net, strokes: strokes, carryExtra: carryExtra, carryDiverges: carryDiverges, isMySide: isMySide, color: partnerColor(idx), width: width / CGFloat(max(players.count, 1)))
            }
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: Sub-vistas de tabla

    private func zoomHeaderRow(rightAliases: [String], leftAliases: [String]? = nil) -> some View {
        HStack(spacing: 10) {
            zoomHeader("H", holeColWidth)
            zoomHeaderNames(leftAliases ?? [matchManager.yoAlias], playerColWidth)
            zoomHeaderNames(rightAliases, playerColWidth)
            zoomHeader("Res", resColWidth)
            zoomHeader("Acum", accumColWidth)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    // Nombre(s) de columna — en parejas, cada compañero toma el color fijo de su posición
    // (partnerColor) para que las filas de abajo se puedan leer por color sin repetir texto.
    private func zoomHeaderNames(_ aliases: [String], _ width: CGFloat) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(aliases.enumerated()), id: \.offset) { idx, alias in
                if idx > 0 {
                    Text("+").font(.system(size: 11, weight: .bold)).foregroundColor(.cMuted)
                }
                Text(alias)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(aliases.count > 1 ? partnerColor(idx) : .cMuted)
            }
        }
        .frame(width: width, alignment: .leading)
        .lineLimit(1)
    }

    private func zoomHeader(_ text: String, _ width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).foregroundColor(.cMuted)
            .frame(width: width, alignment: .leading)
            .lineLimit(1)
    }

    // Hoyo + Par + HCP (stroke index) juntos — el HCP en el mismo dorado que las marcas de
    // stroke, para ver de un vistazo en qué hoyos aplica ventaja sin tener que buscarlo aparte.
    private func zoomHoleCell(_ hole: Int) -> some View {
        let h = matchManager.getHole(hole)
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(hole)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)
            if let h = h {
                HStack(spacing: 3) {
                    Text("P\(h.par)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cDisabled)
                    Text("H\(h.si)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(strokeGold)
                }
            }
        }
        .frame(width: holeColWidth, alignment: .leading)
    }

    private func zoomResultCell(_ result: Int) -> some View {
        let color: Color = result > 0 ? .cFairwayL : result < 0 ? .cBrick : .cMuted
        let label = result == 0 ? "E" : result > 0 ? "+\(result)" : "\(result)"
        return Text(label)
            .font(.system(size: 17, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .frame(width: resColWidth, alignment: .leading)
    }

    // Acumulado corrido hasta este hoyo — vuelta Y presión juntas (completo, no solo vuelta),
    // para auditar a mano, fila por fila, que el total final cuadra con ambos conceptos.
    // Mismo tamaño que zoomResultCell (17pt) — este número es el que define el resultado real
    // del segmento (no el resultado aislado de un solo hoyo), no puede verse más chico que ese.
    private func zoomAccumCell(vuelta: Int, pres: [Int]) -> some View {
        let color: Color = vuelta > 0 ? .cFairwayL : vuelta < 0 ? .cBrick : .cMuted
        let label = vuelta == 0 ? "E" : vuelta > 0 ? "+\(vuelta)" : "\(vuelta)"
        // Vuelta arriba, presiones abajo en una segunda línea que envuelve si hace falta —
        // antes iban todas en una sola fila con .lineLimit(1), y con 3+ presiones activas a la
        // vez (sí pasa, ver hoyo 7 del ejemplo de parejas) el texto se truncaba a "+…" y
        // ocultaba el valor. Nunca se debe esconder una presión (CAMBIOS_CADDIE_v2.md #5).
        let presText = pres.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            if !pres.isEmpty {
                Text(presText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
            }
        }
        .frame(width: accumColWidth, alignment: .leading)
    }

    // Fila de cierre explícita al terminar los 9 hoyos del segmento — el acumulado de la última
    // fila ya es el subtotal correcto (vuelta reinicia en 0 por segmento), pero se destaca aparte
    // en vez de dejar que se confunda con una fila de hoyo más. Debajo, la suma de golpes crudos
    // de cada jugador en el segmento (mismo OUT/IN que la tira GOLPES, aquí junto al resultado).
    private func zoomSubtotalRow(segment: String, vuelta: Int, pres: [Int], strokes: [(alias: String, total: Int, color: Color)], carry: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Subtotal \(segment)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cMuted)
                Spacer()
                zoomAccumCell(vuelta: vuelta, pres: pres)
                // Resultado final del Carry (un solo número) — el detalle de en qué hoyos
                // realmente cambió algo ya se ve marcado hoyo por hoyo arriba con la "C" en la
                // fila de cada hoyo, no hace falta repetir la lista completa aquí.
                if let c = carry {
                    let cColor: Color = c > 0 ? .cFairwayL : c < 0 ? .cBrick : .cMuted
                    let cLabel = c == 0 ? "E" : c > 0 ? "+\(c)" : "\(c)"
                    HStack(spacing: 1) {
                        Text("C").font(.system(size: 9, weight: .bold)).foregroundColor(.cGold)
                        Text(cLabel).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(cColor)
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach(Array(strokes.enumerated()), id: \.offset) { _, s in
                    HStack(spacing: 4) {
                        Text(s.alias)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.cMuted)
                        Text("\(s.total)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(s.color)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(red: 0.941, green: 0.929, blue: 0.898))
    }


    // Hoyo del segmento todavía sin anotar — se muestra igual (atenuado) para que la tabla
    // siempre llene las 9 filas del segmento, en vez de dejar un hueco vacío hasta la barra de dinero.
    private func zoomPlaceholderRow(hole: Int) -> some View {
        HStack(spacing: 10) {
            zoomHoleCell(hole)
            Text("sin anotar")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.cDisabled)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .opacity(0.55)
    }

}

struct ResultsSheetView: View {
    @ObservedObject var matchManager: MatchManager
    @Binding var correctionRequest: ScoreCorrection?
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    // Un solo match seleccionado a la vez — cada botón del selector (individual o pareja)
    // aclara exactamente ese match, sin mezclar resultados de otros matches en la misma pantalla.
    private enum MatchSelection: Hashable {
        case individual(String)
        case pair(UUID)
    }
    @State private var selection: MatchSelection? = nil
    @State private var detailHole: Int? = nil
    @State private var unitLogTarget: UnitLogTarget? = nil
    @State private var matchZoomTarget: UnitLogTarget? = nil
    @State private var matchZoomInitialSegment: String = "F9"
    // Qué compañero del lado elegible queda seleccionado en el picker de Carry de pareja —
    // por laneId, porque puede haber varias tarjetas de pareja visibles a la vez.
    @State private var carrySelection: [UUID: String] = [:]

    private var opponents: [PlayerModel] {
        matchManager.players.filter { $0.alias != matchManager.yoAlias }
    }

    // Una fila por match — el tablero que se usa para cerrar cuentas con el rival: de un vistazo
    // ves F9/B9/Total de todos los matches, y tocas uno para entrar al detalle (evidencia) si hay
    // que discutir un número.
    private struct ResumenRow: Identifiable {
        let id: MatchSelection
        let label: String
        let f9V: Int
        let f9Pres: [Int]
        let b9V: Int
        let b9Pres: [Int]
        let carryActive: Bool
        let carryMoney: Int
        let units: Int
        let total: Int
    }

    private var resumenRows: [ResumenRow] {
        let wallet = matchManager.walletSnapshot()
        var rows: [ResumenRow] = []
        for opp in opponents {
            let b9Rows = matchManager.individualZoomRows(opponentAlias: opp.alias, segmentOverride: "B9")
            let f9V = matchManager.individualF9Vuelta(opponentAlias: opp.alias)
            let b9V = b9Rows.last?.vueltaAccum ?? 0
            let f9Pres = matchManager.individualF9Presion(opponentAlias: opp.alias)
            let b9Pres = matchManager.individualB9Presion(opponentAlias: opp.alias)
            let line = wallet.lines.first { $0.opponentAlias == opp.alias }
            rows.append(ResumenRow(id: .individual(opp.alias), label: opp.alias, f9V: f9V, f9Pres: f9Pres, b9V: b9V, b9Pres: b9Pres, carryActive: line?.carryActive ?? false, carryMoney: line?.carryMoney ?? 0, units: line?.unitsPoints ?? 0, total: line?.totalMoney ?? 0))
        }
        for lane in matchManager.lanes {
            let sign = lane.base.contains(matchManager.yoAlias) ? 1 : -1
            let b9Rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: "B9")
            let f9V = matchManager.pairF9Vuelta(laneId: lane.id) * sign
            let b9V = (b9Rows.last?.vueltaAccum ?? 0) * sign
            let f9Pres = matchManager.pairF9Presion(laneId: lane.id).map { $0 * sign }
            let b9Pres = matchManager.pairB9Presion(laneId: lane.id).map { $0 * sign }
            let line = wallet.lines.first { $0.laneId == lane.id }
            rows.append(ResumenRow(id: .pair(lane.id), label: lane.opp.joined(separator: "+"), f9V: f9V, f9Pres: f9Pres, b9V: b9V, b9Pres: b9Pres, carryActive: line?.carryActive ?? false, carryMoney: line?.carryMoney ?? 0, units: line?.unitsPoints ?? 0, total: line?.totalMoney ?? 0))
        }
        return rows
    }

    // Suma de todos los matches — el neto real ganado/perdido en la ronda completa.
    private var resumenGrandTotal: Int { resumenRows.reduce(0) { $0 + $1.total } }

    private var resumenTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MATCH")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cMuted)
                Spacer()
                Text("F9").frame(width: 58, alignment: .trailing)
                Text("B9").frame(width: 58, alignment: .trailing)
                Text("UNID").frame(width: 44, alignment: .trailing)
                Text("TOTAL").frame(width: 72, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.cMuted)
            .padding(.horizontal, 14).padding(.vertical, 10)

            Color.cRowDiv.frame(height: 1)

            ForEach(Array(resumenRows.enumerated()), id: \.element.id) { idx, row in
                Button { selection = row.id } label: {
                    HStack {
                        Text(row.label)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.cInk)
                        Spacer()
                        resumenAccumCell(row.f9V, row.f9Pres).frame(width: 58, alignment: .trailing)
                        resumenAccumCell(row.b9V, row.b9Pres, carryMoney: row.carryActive ? row.carryMoney : nil).frame(width: 58, alignment: .trailing)
                        resumenVueltaCell(row.units).frame(width: 44, alignment: .trailing)
                        Text(caddyMoneyStr(row.total))
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundColor(caddyMoneyColor(row.total))
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Color.cRowDiv.frame(height: 1)
            }

            // Suma de todos los matches — el neto real de la ronda completa, ganado o perdido.
            HStack {
                Text("TOTAL GENERAL")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cMuted)
                Spacer()
                Text(caddyMoneyStr(resumenGrandTotal))
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(caddyMoneyColor(resumenGrandTotal))
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .background(Color(red: 0.941, green: 0.929, blue: 0.898))
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
        .padding(.horizontal, 18)
    }

    private func resumenVueltaCell(_ v: Int) -> some View {
        let color: Color = v > 0 ? .cFairwayL : v < 0 ? .cBrick : .cMuted
        let label = v == 0 ? "E" : v > 0 ? "+\(v)" : "\(v)"
        return Text(label)
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .foregroundColor(color)
    }

    // Vuelta + cada presión con su propio valor (CAMBIOS_CADDIE_v2.md #5) — antes el Resumen
    // solo cargaba el vuelta (Int) y nunca mostraba las presiones; con 4-5 presiones activas
    // (ej. "11 9 7 5 3") solo se veía el "11". Vuelta arriba, presiones abajo envolviendo si
    // hace falta — mismo patrón que zoomAccumCell, nunca se trunca ni se esconde un valor.
    // carryMoney solo se pasa para la columna B9 (Carry es exclusivo de B9) — se pinta como una
    // línea extra "Carry $xxx" debajo de vuelta+presión, para que el Total de la fila se pueda
    // reconstruir sumando lo que se ve: F9 + B9 + Carry (CAMBIOS: antes el Carry solo se veía
    // escondido dentro del Total, sin desglose, en esta tabla).
    private func resumenAccumCell(_ vuelta: Int, _ pres: [Int], carryMoney: Int? = nil) -> some View {
        let color: Color = vuelta > 0 ? .cFairwayL : vuelta < 0 ? .cBrick : .cMuted
        let label = vuelta == 0 ? "E" : vuelta > 0 ? "+\(vuelta)" : "\(vuelta)"
        let presText = pres.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: " ")
        return VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            if !pres.isEmpty {
                Text(presText)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
                    .multilineTextAlignment(.trailing)
            }
            if let c = carryMoney {
                Text("Carry \(caddyMoneyStr(c))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    // F9 o B9 según dónde haya datos reales (igual que HoleAudit.holeWindow) — para que el tap
    // genérico en el header de la tarjeta abra el Zoom en el segmento que se está jugando, en vez
    // de forzar siempre F9 aunque ya se hayan anotado hoyos del B9.
    private var currentSegment: String {
        let order = matchManager.playOrder()
        let back = Array(order.suffix(9))
        let hasBackData = back.contains { hole in
            matchManager.players.contains { p in matchManager.getScore(hole: hole, player: p.alias) > 0 }
        }
        return hasBackData ? "B9" : "F9"
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

                // Selector unificado — "Resumen" (tablero de todos los matches) + un botón por
                // match (individual + pareja mezclados). Cada botón aclara solo su propio match.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        resumenChip
                        ForEach(opponents) { opp in oppChip(opp) }
                        ForEach(matchManager.lanes) { lane in laneChip(lane) }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 14)

                switch selection {
                case .individual(let alias):
                    if let opp = matchManager.players.first(where: { $0.alias == alias }) {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 12) {
                                individualCard(opp: opp)
                                holeDetailButton
                                if let h = detailHole {
                                    holeDetailCard(hole: h, opp: opp, laneId: nil)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .animation(.spring(duration: 0.25), value: detailHole)
                            .padding(.horizontal, 18).padding(.bottom, 32)
                        }
                    }
                case .pair(let laneId):
                    if let lane = matchManager.lanes.first(where: { $0.id == laneId }),
                       let focused = lane.opp.compactMap({ alias in matchManager.players.first { $0.alias == alias } }).first {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 12) {
                                pairCard(lane: lane)
                                holeDetailButton
                                if let h = detailHole {
                                    holeDetailCard(hole: h, opp: focused, laneId: laneId)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .animation(.spring(duration: 0.25), value: detailHole)
                            .padding(.horizontal, 18).padding(.bottom, 32)
                        }
                    }
                case nil:
                    if opponents.isEmpty && matchManager.lanes.isEmpty {
                        Text("Configura jugadores en ⚙ para ver resultados.")
                            .font(.system(size: 13)).foregroundColor(.cMuted)
                            .multilineTextAlignment(.center).padding(40)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            resumenTable
                                .padding(.bottom, 32)
                        }
                    }
                }
            }
        }
        .onChange(of: selection) { _, _ in detailHole = nil }
        .sheet(item: $unitLogTarget) { target in
            NavigationStack {
                UnitLogDetailView(title: unitLogTitle(target), entries: unitLogEntries(target))
            }
        }
        .sheet(item: $matchZoomTarget) { target in
            MatchZoomView(matchManager: matchManager, target: target, initialSegment: matchZoomInitialSegment)
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

    // MARK: Resumen chip — vuelve al tablero de todos los matches (selection == nil)

    private var resumenChip: some View {
        let sel = selection == nil
        return Button { selection = nil } label: {
            VStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(sel ? .cBg : .cInk)
                    .frame(width: 52, height: 52)
                    .background(sel ? Color.cFairway : Color.cSurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(sel ? Color.cFairway : Color.cBorder, lineWidth: 1.5))
                Text("Resumen")
                    .font(.system(size: 9))
                    .foregroundColor(sel ? .cFairway : .cMuted)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Opponent chip

    private func oppChip(_ opp: PlayerModel) -> some View {
        let sel = selection == .individual(opp.alias)
        return Button { selection = .individual(opp.alias) } label: {
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

    // MARK: Lane chip (pareja rival)

    private func laneChip(_ lane: LaneModel) -> some View {
        let sel = selection == .pair(lane.id)
        let label = lane.opp.joined(separator: "+")
        return Button { selection = .pair(lane.id) } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(sel ? .cBg : .cInk)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 52)
                    .frame(height: 52)
                    .background(sel ? Color.cFairway : Color.cSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(sel ? Color.cFairway : Color.cBorder, lineWidth: 1.5))
                Text("pareja")
                    .font(.system(size: 9))
                    .foregroundColor(sel ? .cFairway : .cMuted)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Individual card

    private func individualCard(opp: PlayerModel) -> some View {
        // Cada segmento se pide con su propio segmentOverride — sin esto, individualZoomRows()
        // auto-detecta UN solo segmento "actual" (ver zoomHolesForCurrentRound), y una vez que
        // hay datos de B9, "rows.last" pasaba a ser el subtotal de B9 en vez del total de 18
        // hoyos, así que "totalV - f9V" restaba F9 dos veces y el número de B9 salía mal.
        let f9Rows = matchManager.individualZoomRows(opponentAlias: opp.alias, segmentOverride: "F9")
        let b9Rows = matchManager.individualZoomRows(opponentAlias: opp.alias, segmentOverride: "B9")
        let rows = f9Rows + b9Rows
        let f9V    = matchManager.individualF9Vuelta(opponentAlias: opp.alias)
        let b9V    = b9Rows.last?.vueltaAccum ?? 0
        let f9Pres = matchManager.individualF9Presion(opponentAlias: opp.alias)
        let b9Pres = matchManager.individualB9Presion(opponentAlias: opp.alias)
        let carryOn = matchManager.isIndividualCarryActive(opponentAlias: opp.alias)
        let b9Carry: Int? = carryOn ? matchManager.individualCarryResultB9(opponentAlias: opp.alias) : nil
        let wallet = matchManager.walletSnapshot().lines.first { $0.opponentAlias == opp.alias }
        let carryEligible = matchManager.individualCarryEligibleRequester(opponentAlias: opp.alias)
        let adjust50On = matchManager.isIndividualAdjust50Active(opponentAlias: opp.alias)
        let doublePressOn = matchManager.isIndividualDoublePressActive(opponentAlias: opp.alias)

        // Bruto/neto acumulado por jugador — para el audit contra el caddie rival (Manual punto 12).
        return matchCard(
            title: "INDIVIDUAL",
            subtitle: "\(matchManager.yoAlias) vs \(opp.alias)",
            f9V: f9V, b9V: b9V,
            f9Pres: f9Pres, b9Pres: b9Pres, b9Carry: b9Carry,
            wallet: wallet,
            hasData: !rows.isEmpty,
            zoomTarget: .individual(opp.alias),
            carryCandidates: carryEligible.map { [$0] } ?? [],
            carryActive: carryOn,
            carryRequesterAlias: matchManager.individualCarryRequesterByOpponent[opp.alias],
            onActivateCarry: { if let e = carryEligible { matchManager.setIndividualCarryRequest(opponentAlias: opp.alias, requesterAlias: e) } },
            onCancelCarry: { matchManager.clearIndividualCarryRequest(opponentAlias: opp.alias) },
            adjust50Active: adjust50On,
            onActivateAdjust50: { matchManager.setIndividualAdjust50(opponentAlias: opp.alias, active: true) },
            onCancelAdjust50: { matchManager.setIndividualAdjust50(opponentAlias: opp.alias, active: false) },
            doublePressActive: doublePressOn,
            onToggleDoublePress: { matchManager.setIndividualDoublePress(opponentAlias: opp.alias, active: !doublePressOn) },
            strokesLine: matchManager.individualStrokeSummaryLine(opponentAlias: opp.alias)
        )
    }

    // MARK: Pair card

    private func pairCard(lane: LaneModel) -> some View {
        // Mismo fix que individualCard: cada segmento con su propio segmentOverride, en vez de
        // confiar en que "rows.last" (sin override) sea el total de 18 hoyos — una vez hay datos
        // de B9, dejaba de serlo y el número de B9 salía mal.
        let f9Rows   = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: "F9")
        let b9Rows   = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: "B9")
        let rows     = f9Rows + b9Rows
        let yoBase   = lane.base.contains(matchManager.yoAlias)
        let sign     = yoBase ? 1 : -1
        let f9V      = matchManager.pairF9Vuelta(laneId: lane.id) * sign
        let b9V      = (b9Rows.last?.vueltaAccum ?? 0) * sign
        // pairF9/B9Presion vienen siempre desde la perspectiva de lane.base — si yo estoy del
        // lado opp, ganar/perder se invierte (lo que base gana, yo lo pierdo).
        let f9Pres   = matchManager.pairF9Presion(laneId: lane.id).map { $0 * sign }
        let b9Pres   = matchManager.pairB9Presion(laneId: lane.id).map { $0 * sign }
        let carryOn  = matchManager.isPairCarryActive(laneId: lane.id)
        let b9Carry: Int? = carryOn ? matchManager.pairCarryResultB9(laneId: lane.id) * sign : nil
        let baseL    = lane.base.joined(separator: "+")
        let oppL     = lane.opp.joined(separator: "+")
        let wallet   = matchManager.walletSnapshot().lines.first { $0.laneId == lane.id }
        let carryEligibleTeam = matchManager.pairCarryEligibleTeam(laneId: lane.id)
        let carrySelected = carrySelection[lane.id] ?? carryEligibleTeam.first
        let adjust50On = matchManager.isPairAdjust50Active(laneId: lane.id)
        let doublePressOn = matchManager.isPairDoublePressActive(laneId: lane.id)

        return matchCard(
            title: "PAREJA",
            subtitle: "\(baseL) vs \(oppL)",
            f9V: f9V, b9V: b9V,
            f9Pres: f9Pres, b9Pres: b9Pres, b9Carry: b9Carry,
            wallet: wallet,
            hasData: !rows.isEmpty,
            zoomTarget: .pair(lane.id),
            carryCandidates: carryEligibleTeam,
            carryActive: carryOn,
            carryRequesterAlias: matchManager.pairCarryRequesterByLane[lane.id],
            carrySelected: carrySelected,
            onSelectCarryCandidate: { carrySelection[lane.id] = $0 },
            onActivateCarry: { if let alias = carrySelected { matchManager.setPairCarryRequest(laneId: lane.id, requesterAlias: alias) } },
            onCancelCarry: { matchManager.clearPairCarryRequest(laneId: lane.id) },
            adjust50Active: adjust50On,
            onActivateAdjust50: { matchManager.setPairAdjust50(laneId: lane.id, active: true) },
            onCancelAdjust50: { matchManager.setPairAdjust50(laneId: lane.id, active: false) },
            doublePressActive: doublePressOn,
            onToggleDoublePress: { matchManager.setPairDoublePress(laneId: lane.id, active: !doublePressOn) },
            strokesLine: matchManager.pairStrokeSummaryLine(laneId: lane.id)
        )
    }

    // Chip tipo botón para activar/desactivar un refresh de B9 (Carry/Ajuste 50/Doble B9) —
    // se prende/apaga tocando el mismo botón, sin un estado "Ninguno" explícito.
    private func b9RefreshChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(active ? .white : .cMuted)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(active ? Color.cGold : Color.cGold.opacity(0.12))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // Shared card builder for individual and pair.
    // Siempre despliega los 5 conceptos completos (Vuelta, Presión, Carry, Match, Unidades) — nunca resumido.
    private func matchCard(title: String, subtitle: String,
                           f9V: Int, b9V: Int,
                           f9Pres: [Int], b9Pres: [Int], b9Carry: Int? = nil, wallet: WalletLine?,
                           hasData: Bool, zoomTarget: UnitLogTarget,
                           carryCandidates: [String] = [], carryActive: Bool = false, carryRequesterAlias: String? = nil,
                           carrySelected: String? = nil, onSelectCarryCandidate: ((String) -> Void)? = nil,
                           onActivateCarry: (() -> Void)? = nil, onCancelCarry: (() -> Void)? = nil,
                           adjust50Active: Bool = false, onActivateAdjust50: (() -> Void)? = nil, onCancelAdjust50: (() -> Void)? = nil,
                           doublePressActive: Bool = false, onToggleDoublePress: (() -> Void)? = nil,
                           strokesLine: String? = nil) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            // Header — toca la tarjeta completa para abrir el Zoom a pantalla completa (historia hoyo
            // por hoyo de este match: bruto/neto/strokes/unidades, F9 y B9). El botón "U" del wallet
            // (más abajo) sigue abriendo su propio detalle sin disparar este tap, por buttonStyle(.plain).
            Button { matchZoomInitialSegment = currentSegment; matchZoomTarget = zoomTarget } label: {
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
                // F9 / B9, cada uno con su propia presión pegada al número (no en caja aparte,
                // mismo patrón que bruto/neto "5/3" de scoreCell: cifras relacionadas van juntas).
                // Carry solo puede existir en B9 — se pega igual si está activo. Cada segmento es
                // tocable y abre el Zoom directo en ese segmento (no solo desde el header).
                HStack(spacing: 0) {
                    Button { matchZoomInitialSegment = "F9"; matchZoomTarget = zoomTarget } label: {
                        segmentCell("F9", vuelta: f9V, pres: f9Pres)
                    }
                    .buttonStyle(.plain)
                    Color.cRowDiv.frame(width: 1)
                    Button { matchZoomInitialSegment = "B9"; matchZoomTarget = zoomTarget } label: {
                        segmentCell("B9", vuelta: b9V, pres: b9Pres, carry: b9Carry)
                    }
                    .buttonStyle(.plain)
                }

                // Strokes reales (no puntos) que recibe/da cada jugador en F9 y B9 — separado del
                // resultado de Vuelta/Presión/Carry de arriba. Dato clave para la discusión en
                // cancha, así que se resalta en dorado (no texto gris chico) y se permite envolver
                // a 2 líneas en vez de esconderse en un scroll horizontal sin indicador — antes el
                // texto se recortaba y no había pista visual de que había más contenido.
                if let line = strokesLine {
                    Text(line)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.cGold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.bottom, 6)
                }

                // B9 Refresh — solo visible una vez que el F9 queda decidido (CAMBIOS: el que
                // pierde el F9 es quien puede pedirlo). Carry y Ajuste 50 tocan strokes y son
                // mutuamente excluyentes (MatchManager ya lo valida vía guard): activar uno
                // cancela el otro. Doble B9 es independiente — solo duplica dinero, no strokes —
                // por eso puede combinarse con cualquiera de los dos. Los 3 son botones tipo
                // chip que se prenden/apagan solos; no hay un botón "Ninguno" — para apagar
                // Carry o Ajuste 50 se vuelve a tocar el mismo botón que ya está activo.
                if !carryCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11)).foregroundColor(.cGold)
                            Text(carryActive ? "Carry B9 activo · \(carryRequesterAlias ?? "")"
                                 : adjust50Active ? "Ajuste 50 activo"
                                 : (carryCandidates.count > 1
                                    ? "Perdieron F9 — elige el refresh de B9"
                                    : "\(carryCandidates[0]) perdió F9 — elige el refresh de B9"))
                                .font(.system(size: 11, weight: (carryActive || adjust50Active) ? .semibold : .regular))
                                .foregroundColor((carryActive || adjust50Active) ? .cGold : .cMuted)
                            Spacer()
                        }
                        HStack(spacing: 6) {
                            b9RefreshChip(label: "Carry", active: carryActive) {
                                if carryActive {
                                    onCancelCarry?()
                                } else {
                                    if adjust50Active { onCancelAdjust50?() }
                                    onActivateCarry?()
                                }
                            }
                            b9RefreshChip(label: "Ajuste 50", active: adjust50Active) {
                                if adjust50Active {
                                    onCancelAdjust50?()
                                } else {
                                    if carryActive { onCancelCarry?() }
                                    onActivateAdjust50?()
                                }
                            }
                            b9RefreshChip(label: "Doble B9", active: doublePressActive) {
                                onToggleDoublePress?()
                            }
                        }
                        // Solo en pareja puede haber más de un candidato (los 2 compañeros del
                        // lado que perdió el F9) — el selector elige a quién se le asigna el
                        // stroke extra del Carry antes de activarlo.
                        if carryActive, carryCandidates.count > 1 {
                            Picker("", selection: Binding(
                                get: { carrySelected ?? carryCandidates[0] },
                                set: { onSelectCarryCandidate?($0) }
                            )) {
                                ForEach(carryCandidates, id: \.self) { alias in
                                    Text(alias).tag(alias)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.cGold.opacity(0.08))
                }

                // Total en pesos pegado justo debajo de las presiones — con signos mixtos
                // (ej. +7 +4 +1 y a veces alguna negativa) es fácil leer solo los positivos y
                // pensar que vas ganando cuando en realidad una presión se perdió. El total real
                // en dinero queda aquí mismo, no solo hasta abajo en el desglose completo.
                if let w = wallet {
                    HStack(spacing: 4) {
                        Spacer()
                        Text("Total")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cMuted)
                        Text(caddyMoneyStr(w.totalMoney))
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundColor(caddyMoneyColor(w.totalMoney))
                    }
                    .padding(.horizontal, 14)
                }
                Spacer().frame(height: 8)
            } else {
                Text("Sin historial de hoyos aún")
                    .font(.system(size: 12)).foregroundColor(.cDisabled)
                    .padding(.horizontal, 14).padding(.bottom, 8)
            }

            // El dinero (Vuelta/Presión/Carry/Match/Unidades) es un cálculo independiente de
            // walletSnapshot() — siempre se muestra completo aunque el historial de zoom (arriba)
            // todavía no tenga filas (regla dura: nunca resumido, nunca oculto).
            if let w = wallet {
                Color.cBorder.frame(height: 1)
                walletBreakdownRow(w)
            }
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
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

    private func segmentCell(_ label: String, vuelta: Int, pres: [Int] = [], carry: Int? = nil) -> some View {
        let color: Color = vuelta > 0 ? .cFairwayL : vuelta < 0 ? .cBrick : .cMuted
        let vLabel = vuelta == 0 ? "E" : vuelta > 0 ? "+\(vuelta)" : "\(vuelta)"
        var caption = "Vuelta"
        if !pres.isEmpty { caption += " + Pres" }
        if carry != nil { caption += " + Carry" }
        return VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cMuted)
            HStack(spacing: 6) {
                Text(vLabel)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .fixedSize()
                // Con varias presiones abiertas, el contenido puede no caber en el ancho de la
                // columna (mitad de la tarjeta) — antes el texto se envolvía y se encimaba encima
                // de la vuelta. En vez de forzar que quepa, se desplaza horizontal; cada elemento
                // mantiene su tamaño fijo (.fixedSize) para que nunca se parta en dos líneas.
                if !pres.isEmpty || carry != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            // Cada presión con su propio valor (CAMBIOS_CADDIE_v2.md #5: "5 3 1") —
                            // nunca un conteo ni un neto colapsado.
                            ForEach(Array(pres.enumerated()), id: \.offset) { _, p in
                                Text(p > 0 ? "+\(p)" : "\(p)")
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(p > 0 ? .cFairwayL : .cBrick)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            // Resultado final del Carry — un solo número aquí; el detalle de en
                            // qué hoyos cambió algo se ve marcado hoyo por hoyo en la tabla Zoom
                            // (la "C" solo aparece en los hoyos donde el Carry realmente cambió
                            // el resultado vs sin Carry, no en todos los hoyos de B9).
                            if let c = carry {
                                let cColor: Color = c > 0 ? .cFairwayL : c < 0 ? .cBrick : .cMuted
                                let cLabel = c == 0 ? "E" : c > 0 ? "+\(c)" : "\(c)"
                                HStack(spacing: 1) {
                                    Text("C")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.cGold)
                                    Text(cLabel)
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(cColor)
                                }
                                .lineLimit(1)
                                .fixedSize()
                            }
                        }
                    }
                }
            }
            Text(caption)
                .font(.system(size: 9)).foregroundColor(.cDisabled)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    // Botón de entrada a holeDetailCard — antes se abría tocando una celda de la tira GOLPES
    // (eliminada, duplicaba la capa de golpes que el Zoom ya cubre). Arranca en el último hoyo
    // completo (o el 1 si no hay ninguno); de ahí, las flechas ←/→ y el swipe ya navegan todo
    // el resto de hoyos sin volver a tocar este botón.
    private var holeDetailButton: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) {
                detailHole = detailHole == nil ? (matchManager.lastCompleteHole() ?? 1) : nil
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                Text(detailHole == nil ? "Ver hoyo a hoyo" : "Ocultar detalle de hoyo")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: detailHole == nil ? "chevron.right" : "chevron.up")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.cFairway)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.cSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Hole detail card — tarjeta plena + navegación por hoyo

    // Marca de stroke — mismo lenguaje visual que MatchZoomView (project_architecture_sot):
    // ● = 1 stroke, ◐ = 0.5. En dorado para que salte a la vista como "aquí hay ventaja".
    private func strokeMark(_ value: Double) -> String {
        if value <= 0.001 { return "" }
        let whole = Int(value)
        let half = abs(value - Double(whole) - 0.5) < 0.001
        if whole == 0 && half { return "◐" }
        if whole >= 1 && !half { return String(repeating: "●", count: max(1, whole)) }
        return "●\(caddyStrokeStr(value))"
    }
    private var strokeGold: Color { Color(red: 0.831, green: 0.627, blue: 0.090) }

    // Vuelta + presiones apiladas debajo, igual que zoomAccumCell en MatchZoomView — nunca
    // colapsar presiones a un solo número (CAMBIOS_CADDIE_v2.md #5).
    @ViewBuilder
    private func holeDetailAccum(vuelta: Int, pres: [Int], size: CGFloat) -> some View {
        let color: Color = vuelta > 0 ? .cFairwayL : vuelta < 0 ? .cBrick : .cMuted
        let label = vuelta == 0 ? "E" : vuelta > 0 ? "+\(vuelta)" : "\(vuelta)"
        let presText = pres.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: " ")
        VStack(alignment: .trailing, spacing: 2) {
            Text("Acum").font(.system(size: 10)).foregroundColor(.cMuted)
            Text(label)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            if !pres.isEmpty {
                Text(presText)
                    .font(.system(size: size - 4, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
            }
        }
    }

    // `laneId` acota la tarjeta a UN solo match — el seleccionado en los chips de arriba — en vez
    // de desplegar también cualquier otra pareja en la que `opp` participe. nil = match individual.
    private func holeDetailCard(hole: Int, opp: PlayerModel, laneId: UUID?) -> some View {
        let order    = matchManager.playOrder()
        let idx      = order.firstIndex(of: hole) ?? 0
        let prevH    = idx > 0                  ? order[idx - 1] : nil
        let nextH    = idx < order.count - 1    ? order[idx + 1] : nil
        let hd       = matchManager.getHole(hole)
        let par      = hd?.par ?? 4
        let hc       = hd?.si ?? 9
        let yo       = matchManager.yoAlias

        // Hoyo actual + 2 anteriores — puede cruzar el límite F9/B9 (ej. H9→H10), así que el
        // acumulado de cada hoyo abajo se calcula con el segmento DE ESE hoyo, no el actual.
        let holesWindow = Array(order[max(0, idx - 2)...idx])

        // Solo los jugadores del match seleccionado — antes mostraba a los 5 siempre, así que
        // revisando RIC+ROB también aparecía Fernando sin aportar nada a esa revisión.
        let relevantAliases: [String] = {
            if let laneId, let lane = matchManager.lanes.first(where: { $0.id == laneId }) {
                return lane.base + lane.opp
            }
            return [yo, opp.alias]
        }()
        let relevantPlayers = relevantAliases.compactMap { alias in
            matchManager.players.first { $0.alias == alias }
        }

        // Quién está "de mi lado" para colorear strokes/Carry rojo (oponente) / verde (yo o mi
        // equipo) — en pareja es todo lane.base o lane.opp según dónde esté yo, no solo "isYo".
        let mySideAliases: Set<String> = {
            if let laneId, let lane = matchManager.lanes.first(where: { $0.id == laneId }) {
                return Set(lane.base.contains(yo) ? lane.base : lane.opp)
            }
            return [yo]
        }()

        // Individual row — se pide con el segmento de ESTE hoyo, no el auto-detectado, para que
        // no desaparezca al navegar a un hoyo de F9 mientras ya se juega B9 (o viceversa).
        // Solo se calcula si el match seleccionado ES el individual (laneId == nil).
        let indRows  = laneId == nil
            ? matchManager.individualZoomRows(opponentAlias: opp.alias, segmentOverride: matchManager.segmentForHole(hole))
            : []
        let indRow   = indRows.first { $0.hole == hole }

        // Acum (vuelta + presión) de cada hoyo de holesWindow, para la fila "Acum" de la tarjeta
        // plena — así se sigue la racha de los últimos 3 hoyos sin abrir el Zoom
        // (CAMBIOS_CADDIE_v2.md #5: nunca colapsar presiones, siempre el valor propio).
        let indAccumByHole: [Int: (vuelta: Int, pres: [Int])] = {
            guard laneId == nil else { return [:] }
            var result: [Int: (vuelta: Int, pres: [Int])] = [:]
            for seg in Set(holesWindow.map { matchManager.segmentForHole($0) }) {
                let rows = matchManager.individualZoomRows(opponentAlias: opp.alias, segmentOverride: seg)
                let segHoles = rows.map { $0.hole }
                let series = matchManager.individualPresionSeries(opponentAlias: opp.alias, holes: segHoles)
                for (i, r) in rows.enumerated() where holesWindow.contains(r.hole) {
                    result[r.hole] = (r.vueltaAccum, series.indices.contains(i) ? series[i] : [])
                }
            }
            return result
        }()

        // Pair row — solo la lane seleccionada (laneId), nunca todas las lanes de `opp`.
        let laneRows: [(lane: LaneModel, row: PairZoomRow, pres: [Int])] = {
            guard let laneId, let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return [] }
            let rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: matchManager.segmentForHole(hole))
            guard let idx = rows.firstIndex(where: { $0.hole == hole }) else { return [] }
            let segHoles = rows.map { $0.hole }
            let series = matchManager.pairPresionSeries(laneId: lane.id, holes: segHoles)
            let pres = series.indices.contains(idx) ? series[idx] : []
            return [(lane, rows[idx], pres)]
        }()

        let pairAccumByHole: [Int: (vuelta: Int, pres: [Int])] = {
            guard let laneId, let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return [:] }
            let sign = lane.base.contains(yo) ? 1 : -1
            var result: [Int: (vuelta: Int, pres: [Int])] = [:]
            for seg in Set(holesWindow.map { matchManager.segmentForHole($0) }) {
                let rows = matchManager.pairZoomRows(laneId: lane.id, segmentOverride: seg)
                let segHoles = rows.map { $0.hole }
                let series = matchManager.pairPresionSeries(laneId: lane.id, holes: segHoles)
                for (i, r) in rows.enumerated() where holesWindow.contains(r.hole) {
                    result[r.hole] = (r.vueltaAccum * sign, (series.indices.contains(i) ? series[i] : []).map { $0 * sign })
                }
            }
            return result
        }()
        let accumByHole = laneId == nil ? indAccumByHole : pairAccumByHole

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

            // ── Tarjeta plena: hoyo actual + 2 anteriores × todos los jugadores ──
            // "el anterior es donde se revisa" — dejar los últimos 3 hoyos uno junto al otro
            // permite comparar/corregir sin navegar hoyo por hoyo. Usa el mismo ancho de
            // pantalla de siempre (sin landscape); si no caben, el ScrollView los desplaza.
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("").frame(width: 58, alignment: .leading)
                        ForEach(holesWindow, id: \.self) { h in
                            let hd = matchManager.getHole(h)
                            VStack(spacing: 1) {
                                Text("H\(h)")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(h == hole ? .cFairway : .cMuted)
                                Text("Par \(hd?.par ?? 4) · HCP \(hd?.si ?? 0)")
                                    .font(.system(size: 10)).foregroundColor(.cMuted)
                            }
                            .frame(width: 88)
                        }
                    }
                    .padding(.leading, 14).frame(height: 28)

                    Color.cBorder.frame(height: 1)

                    ForEach(relevantPlayers) { p in
                        let isOpp = p.alias == opp.alias
                        let isYo  = p.alias == yo
                        let sideColor: Color = mySideAliases.contains(p.alias) ? .cFairwayL : .cBrick
                        HStack(spacing: 0) {
                            HStack(spacing: 2) {
                                Text(p.alias)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(isYo ? .cFairwayL : isOpp ? .cBrick.opacity(0.8) : .cMuted)
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.cDisabled)
                            }
                            .frame(width: 58, alignment: .leading).padding(.leading, 14)

                            ForEach(holesWindow, id: \.self) { h in
                                let hp      = matchManager.getHole(h)?.par ?? 4
                                let g       = matchManager.getScore(hole: h, player: p.alias)
                                let t       = matchManager.getPutts(hole: h, player: p.alias)
                                let d       = g > 0 ? g - hp : 0
                                // En pareja el stroke lo carga UN SOLO jugador por lado (el de
                                // la lane, no el individual de cada uno contra DAN) — usar
                                // p.strokesVsBase aquí hacía ver "dos jugadores con stroke" en
                                // el mismo match y nunca mostraba el stroke real de la pareja.
                                // pairStrokeForPlayer ya incluye el +1 de Carry si aplica (B9,
                                // desde el hoyo de activación); en individual se mantiene aparte
                                // como "C" porque ahí sí es una apuesta adicional, no el stroke base.
                                let strokes: Double = laneId != nil
                                    ? matchManager.pairStrokeForPlayer(laneId: laneId!, alias: p.alias, hole: h)
                                    : matchManager.distributedStrokes(total: p.strokesVsBase, hole: h)
                                let carryExtra: Double = laneId != nil
                                    ? 0
                                    : matchManager.individualCarryExtraStroke(opponentAlias: opp.alias, alias: p.alias, hole: h)
                                // La "C" solo se marca cuando el Carry realmente cambia el
                                // resultado de ese hoyo vs sin Carry — mismo criterio que en la
                                // tabla Zoom, no en cada hoyo donde el stroke aplica mecánicamente.
                                let carryDiverges: Bool = laneId != nil
                                    ? false
                                    : matchManager.individualCarryDivergesAtHole(opponentAlias: opp.alias, hole: h)

                                Button {
                                    correctionRequest = ScoreCorrection(hole: h, alias: p.alias)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(g > 0 ? "\(g)" : "—")
                                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                                            .foregroundColor(g <= 0 ? .cDisabled : d > 0 ? .cBrick : d < 0 ? .cFairwayL : .cInk)
                                        HStack(spacing: 4) {
                                            Text(t > 0 ? "(\(t))" : "·")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(t > 0 ? .cMuted : .cDisabled)
                                            if strokes > 0.001 {
                                                Text(strokeMark(strokes))
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(sideColor)
                                            }
                                            if carryExtra > 0.001, carryDiverges {
                                                Text("C")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(sideColor)
                                            }
                                        }
                                    }
                                    .frame(width: 88, height: 56)
                                    .background(h == hole ? (isYo ? Color.cFairway.opacity(0.06) : isOpp ? Color.cBrick.opacity(0.04) : Color.clear) : Color.clear)
                                    .overlay(
                                        h == hole ? RoundedRectangle(cornerRadius: 6).stroke(Color.cGold.opacity(0.4), lineWidth: 1) : nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Color.cRowDiv.frame(height: 1)
                    }

                    // ── Acum: vuelta + presión de ESE match, por cada uno de los 3 hoyos —
                    // para seguir la racha sin tener que abrir el Zoom.
                    if !accumByHole.isEmpty {
                        Color.cBorder.frame(height: 1)
                        HStack(spacing: 0) {
                            Text("Acum")
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.cMuted)
                                .frame(width: 58, alignment: .leading).padding(.leading, 14)

                            ForEach(holesWindow, id: \.self) { h in
                                let a      = accumByHole[h]
                                let vuelta = a?.vuelta ?? 0
                                let pres   = a?.pres ?? []
                                let color: Color = vuelta > 0 ? .cFairwayL : vuelta < 0 ? .cBrick : .cMuted
                                let label  = a == nil ? "–" : (vuelta == 0 ? "E" : vuelta > 0 ? "+\(vuelta)" : "\(vuelta)")

                                VStack(spacing: 2) {
                                    Text(label)
                                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                                        .foregroundColor(a == nil ? .cDisabled : color)
                                    if !pres.isEmpty {
                                        Text(pres.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: " "))
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.cInk)
                                    }
                                }
                                .frame(width: 88)
                            }
                        }
                        .padding(.vertical, 6)
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
                    holeDetailAccum(vuelta: r.vueltaAccum, pres: indAccumByHole[hole]?.pres ?? [], size: 16)
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
                let pPres   = lr.pres.map { $0 * sign }

                Color.cBorder.frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("PAREJA")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cMuted).kerning(0.5)
                        Text("· \(lr.lane.base.joined(separator: "+")) vs \(lr.lane.opp.joined(separator: "+"))")
                            .font(.system(size: 10)).foregroundColor(.cMuted).lineLimit(1)
                        Spacer()
                        holeDetailAccum(vuelta: pAccum, pres: pPres, size: 14)
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

}
