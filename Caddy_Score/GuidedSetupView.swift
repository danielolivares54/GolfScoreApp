import SwiftUI

// MARK: - Design tokens
private extension Color {
    static let cBg       = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let cSurface  = Color.white
    static let cBorder   = Color(red: 0.890, green: 0.875, blue: 0.824)
    static let cRowDiv   = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let cInk      = Color(red: 0.110, green: 0.137, blue: 0.129)
    static let cMuted    = Color(red: 0.431, green: 0.416, blue: 0.361)
    static let cFairway  = Color(red: 0.114, green: 0.627, blue: 0.310) // #1DA04F, verde de marca (logo)
    static let cFairwayL = Color(red: 0.290, green: 0.471, blue: 0.337)
    static let cBrick    = Color(red: 0.659, green: 0.275, blue: 0.184)
    static let cSegBg    = Color(red: 0.906, green: 0.886, blue: 0.824)
    static let cDisabled = Color(red: 0.855, green: 0.835, blue: 0.769)
}

struct GuidedSetupView: View {
    // 3 pasos (antes 4): Campo absorbe Hoyo de salida. Jugadores absorbe Strokes 1 a 1 +
    // la plantilla de apuesta DE CADA RIVAL (cada oponente individual puede tener una distinta)
    // + apuestas manuales individuales. Parejas absorbe Strokes en parejas + UNA SOLA plantilla
    // compartida para todas las combinaciones de pareja + apuestas manuales de parejas.
    // Ver CAMBIOS_CADDIE_v2.md / Manual de refactorización.
    enum Step: Int, CaseIterable {
        case campo, jugadores, parejas

        var title: String {
            switch self {
            case .campo:     return "Campo"
            case .jugadores: return "Oponentes"
            case .parejas:   return "Parejas"
            }
        }

        var progressLabel: String {
            switch self {
            case .campo:     return "PASO 1 DE 3 · CAMPO"
            case .jugadores: return "PASO 2 DE 3 · OPONENTES, STROKES Y APUESTA"
            case .parejas:   return "PASO 3 DE 3 · PAREJAS Y STROKES"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager
    @ObservedObject private var templateStore = BetTemplateStore.shared
    @State private var stepIndex = 0
    @State private var selectedCourseId: String = ""
    @State private var startHole: Int = 1
    @State private var playerNames: [String] = []
    @State private var newPlayerName = ""
    // Jugador del directorio que coincide con lo escrito — si se confirma al tocar una
    // sugerencia, addPlayerName() toma sus strokes/tag en vez de los defaults.
    @State private var pendingDirectoryMatch: PlayerDirectoryEntry?
    @State private var showingPlayerDirectory = false
    @State private var strokesByAlias: [String: Double] = [:]
    @State private var base1: String = ""
    @State private var base2: String = ""
    @State private var laneStrokes: [String: Double] = [:]
    @State private var laneCarrierByKey: [String: String] = [:]
    @State private var vueltaValueText: String = ""
    @State private var selectedTemplateId: String = ""       // plantilla compartida de PAREJAS
    @State private var templateIdByOpponent: [String: String] = [:]  // plantilla por rival individual
    @State private var selectedBetIds: Set<UUID> = []
    @State private var betTagOverrides: [UUID: String] = [:]

    private var step: Step { Step.allCases[stepIndex] }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cBg.ignoresSafeArea()
                VStack(spacing: 0) {
                    progressSection
                    ScrollView {
                        VStack(spacing: 18) { stepContent }
                            .padding(.horizontal, 18).padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Setup guiado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(stepIndex == 0 ? "Cancelar" : "Atrás") {
                        if stepIndex == 0 { dismiss() }
                        else { stepIndex = max(0, stepIndex - 1) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.cMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(stepIndex == Step.allCases.count - 1 ? "Guardar" : "Siguiente") {
                        if stepIndex == Step.allCases.count - 1 { applySetup(); dismiss() }
                        else { stepIndex = min(Step.allCases.count - 1, stepIndex + 1) }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(canAdvance() ? .cFairway : .cDisabled)
                    .disabled(!canAdvance())
                }
            }
            .onAppear { loadDefaults(); syncLaneSetupState() }
            .onChange(of: base1)       { _, _ in syncLaneSetupState() }
            .onChange(of: base2)       { _, _ in syncLaneSetupState() }
            .onChange(of: playerNames) { _, _ in syncLaneSetupState() }
        }
    }

    // MARK: Progress bar

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<Step.allCases.count, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(idx <= stepIndex ? Color.cFairway : Color.cBorder)
                        .frame(maxWidth: .infinity).frame(height: 4)
                }
            }
            Text(step.progressLabel)
                .font(.system(size: 11, weight: .bold)).kerning(0.5)
                .foregroundColor(.cMuted)
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 18)
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .campo:
            campoStep
            Divider().padding(.vertical, 4)
            hoyoSalidaStep
        case .jugadores:
            jugadoresStep
            Divider().padding(.vertical, 4)
            strokesStep
            Divider().padding(.vertical, 4)
            unidadesCalculadasStep
            Divider().padding(.vertical, 4)
            betPickerScroll(title: "Apuestas individuales", type: .individual)
        case .parejas:
            parejasStep
            Divider().padding(.vertical, 4)
            strokesParejasStep
            Divider().padding(.vertical, 4)
            parejaApuestaStep
            Divider().padding(.vertical, 4)
            betPickerScroll(title: "Apuestas por parejas", type: .parejas)
        }
    }

    // MARK: Step 1 — Campo

    private var campoStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Campo")
            VStack(spacing: 0) {
                ForEach(Array(CourseCatalog.all.enumerated()), id: \.offset) { idx, course in
                    Button {
                        selectedCourseId = course.id
                    } label: {
                        HStack {
                            Text(course.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.cInk)
                            Spacer()
                            if course.id == selectedCourseId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.cFairway)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color.cSurface)
                    }
                    .buttonStyle(.plain)
                    if idx < CourseCatalog.all.count - 1 {
                        Color.cRowDiv.frame(height: 1).padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.cSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
        }
    }

    // MARK: Step 2 — Hoyo de salida

    private var hoyoSalidaStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("¿En qué hoyo empiezan?")
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    stepperBtn(icon: "minus") { startHole = max(1, startHole - 1) }
                    VStack(spacing: 2) {
                        Text("\(startHole)")
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .foregroundColor(.cFairway)
                        Text("de 18 hoyos")
                            .font(.system(size: 11)).foregroundColor(.cMuted)
                    }
                    .frame(maxWidth: .infinity)
                    stepperBtn(icon: "plus") { startHole = min(18, startHole + 1) }
                }
                Text("La vuelta se anota en el orden real de juego, empezando por este hoyo — no necesariamente el 1.")
                    .font(.system(size: 12)).foregroundColor(.cMuted).lineSpacing(4)
            }
            .padding(16)
            .background(Color.cSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
        }
    }

    // MARK: Step 3 — Jugadores

    private var jugadoresStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            let atCap = playerNames.count >= 5

            HStack {
                Spacer()
                Button { showingPlayerDirectory = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.text.rectangle")
                        Text("Directorio")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.cFairway)
                }
            }

            // Add row
            HStack(spacing: 8) {
                TextField(atCap ? "Máximo de 5 jugadores alcanzado" : "Nombre del jugador", text: $newPlayerName)
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(atCap ? Color(red: 0.941, green: 0.929, blue: 0.898) : Color.cSurface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cBorder, lineWidth: 1))
                    .cornerRadius(12)
                    .disabled(atCap)
                    .foregroundColor(atCap ? .cMuted : .cInk)

                Button("Agregar") { addPlayerName() }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(atCap || newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(red: 0.541, green: 0.518, blue: 0.447) : .cBg)
                    .frame(height: 46).padding(.horizontal, 18)
                    .background(atCap || newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.cDisabled : Color.cFairway)
                    .cornerRadius(12)
                    .disabled(atCap || newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Mini-search del directorio — al escribir "An" aparecen los jugadores conocidos
            // que empiezan igual; tocar una sugerencia precarga su alias de siempre, strokes y
            // plantilla de apuesta en vez de partir de cero.
            let directoryMatches = PlayerDirectoryStore.shared.search(newPlayerName)
            if !directoryMatches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(directoryMatches.enumerated()), id: \.element.id) { idx, entry in
                        Button {
                            newPlayerName = entry.name
                            pendingDirectoryMatch = entry
                        } label: {
                            HStack(spacing: 8) {
                                Text(entry.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.cInk)
                                Text(entry.alias)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.cMuted)
                                Spacer()
                                Text("Strokes \(formatStrokeShort(entry.strokesVsBase))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.cMuted)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < directoryMatches.count - 1 {
                            Color.cRowDiv.frame(height: 1)
                        }
                    }
                }
                .background(Color.cSurface)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cBorder, lineWidth: 1))
            }

            // Player list
            if !playerNames.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(playerAliases.enumerated()), id: \.offset) { idx, p in
                        let isBase1 = idx == 0
                        let isBase2 = idx == 1
                        let roleLabel = isBase1 ? "Pareja base 1" : isBase2 ? "Pareja base 2" : "Oponente"
                        let badgeBg: Color = isBase1 ? .cFairway : isBase2 ? .cFairwayL : Color(red: 0.541, green: 0.518, blue: 0.447)

                        HStack(spacing: 12) {
                            Text(p.alias)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.cBg)
                                .frame(width: 40, height: 40)
                                .background(badgeBg)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundColor(.cInk)
                                Text(roleLabel)
                                    .font(.system(size: 11))
                                    .foregroundColor(.cMuted)
                            }
                            Spacer()

                            Button {
                                playerNames.remove(at: idx)
                                syncStrokes(); syncBaseDefaults()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
                                    .foregroundColor(.cBrick)
                                    .frame(width: 38, height: 38)
                                    .background(Color.cBg)
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 10)
                        .background(Color.cSurface)
                        if idx < playerAliases.count - 1 {
                            Color.cRowDiv.frame(height: 1).padding(.horizontal, 8)
                        }
                    }
                }
                .background(Color.cSurface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))

                Text("\(playerNames.count) de 5 jugadores\(atCap ? " · límite alcanzado" : "")")
                    .font(.system(size: 11.5)).foregroundColor(.cMuted)
                    .padding(.leading, 2)
            }
        }
    }

    // MARK: Step 4 — Strokes individuales

    private var strokesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daniel juega presión individual contra cada uno. Ajusta los strokes y la apuesta de cada rival — cada uno puede tener una plantilla distinta.")
                .font(.system(size: 12.5)).foregroundColor(.cMuted).lineSpacing(4)

            let rivals = playerAliases.filter { $0.alias != matchManager.yoAlias }
            if !rivals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Strokes y apuesta por rival")
                    VStack(spacing: 0) {
                        ForEach(Array(rivals.enumerated()), id: \.offset) { idx, p in
                            let strokes = strokesByAlias[p.alias] ?? 0
                            let strokeColor: Color = strokes > 0.001 ? .cFairway : strokes < -0.001 ? .cBrick : Color(red: 0.769, green: 0.753, blue: 0.682)
                            VStack(spacing: 8) {
                                HStack {
                                    Text("vs \(p.name)")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundColor(.cInk)
                                    Spacer()
                                    HStack(spacing: 0) {
                                        strokeBtn(icon: "minus") { adjustStroke(alias: p.alias, delta: -1.0) }
                                        Text(formatSignedStroke(strokes))
                                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                                            .foregroundColor(strokeColor)
                                            .frame(width: 48).multilineTextAlignment(.center)
                                        halfStrokeBtn(active: hasHalfStroke(strokes)) {
                                            adjustStroke(alias: p.alias, delta: hasHalfStroke(strokes) ? -0.5 : 0.5)
                                        }
                                        strokeBtn(icon: "plus") { adjustStroke(alias: p.alias, delta: 1.0) }
                                    }
                                }
                                HStack {
                                    Text("Apuesta")
                                        .font(.system(size: 11.5)).foregroundColor(.cMuted)
                                    Spacer()
                                    opponentTemplateMenu(for: p.alias)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .background(Color.cSurface)
                            if idx < rivals.count - 1 {
                                Color.cRowDiv.frame(height: 1).padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Color.cSurface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
                    Text("Positivo = le das strokes · negativo = te da strokes")
                        .font(.system(size: 11.5)).foregroundColor(.cMuted).padding(.leading, 2)
                }
            }
        }
        .sheet(isPresented: $showingPlayerDirectory) {
            PlayerDirectoryView()
        }
    }

    // Plantilla propia de este rival — cada oponente puede tener una distinta (a diferencia de
    // parejas, que comparten una sola). Ver MatchManager.setBetTemplateForOpponent.
    private func opponentTemplateMenu(for alias: String) -> some View {
        Menu {
            ForEach(templateStore.entries) { tpl in
                Button(tpl.name) { templateIdByOpponent[alias] = tpl.id }
            }
        } label: {
            HStack(spacing: 3) {
                Text(templateName(templateIdByOpponent[alias] ?? ""))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.cFairway)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.cFairway)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.cBg)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cFairway.opacity(0.4), lineWidth: 1))
        }
    }

    // MARK: Step 5 — Parejas

    private var parejasStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if playerAliases.count < 4 {
                emptyHint("Se necesitan al menos 4 jugadores para configurar parejas.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Pareja base")
                    VStack(spacing: 0) {
                        pickerRow("Jugador 1", selection: $base1)
                        Color.cRowDiv.frame(height: 1)
                        pickerRow("Jugador 2", selection: $base2)
                    }
                    .background(Color.cSurface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))

                    if base1 == base2 && !base1.isEmpty {
                        Text("La pareja base necesita dos jugadores distintos.")
                            .font(.system(size: 11.5)).foregroundColor(.cBrick).padding(.leading, 2)
                    } else {
                        let opps = opponentsForBase()
                        if !opps.isEmpty {
                            Text("Oponentes: \(opps.joined(separator: ", "))")
                                .font(.system(size: 11.5)).foregroundColor(.cMuted).padding(.leading, 2)
                            Text("La apuesta\(selectedTemplateId.isEmpty ? "" : " \"\(templateName(selectedTemplateId))\"") aplica igual a las \(opps.count > 1 ? "\(opps.count) combinaciones de pareja" : "parejas") — no varía por lane.")
                                .font(.system(size: 11.5)).foregroundColor(.cMuted).padding(.leading, 2)
                        }
                    }
                }
            }
        }
    }

    // MARK: Step 6 — Strokes en parejas

    private var strokesParejasStep: some View {
        let lanes = buildLocalLanes()
        return VStack(alignment: .leading, spacing: 16) {
            if !base1.isEmpty && !base2.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PAREJA BASE")
                        .font(.system(size: 10.5, weight: .bold)).kerning(0.5)
                        .foregroundColor(Color(red: 0.620, green: 0.729, blue: 0.659))
                    Text("\(base1) + \(base2)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.cBg)
                    let opps = opponentsForBase()
                    if !opps.isEmpty {
                        Text("vs \(opps.joined(separator: ", ")) · rotando")
                            .font(.system(size: 12)).foregroundColor(Color(red: 0.620, green: 0.729, blue: 0.659))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cFairway)
                .cornerRadius(14)
            }

            if lanes.isEmpty {
                emptyHint("Define primero la pareja base.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Strokes y quién lleva, por rival")
                    VStack(spacing: 0) {
                        ForEach(Array(lanes.enumerated()), id: \.offset) { idx, lane in
                            let key = lane.id
                            let strokes = laneStrokes[key] ?? 0
                            let carrier = laneCarrierByKey[key] ?? ""
                            let allPairMembers = lane.base + lane.opp

                            VStack(spacing: 8) {
                                HStack {
                                    Text("vs \(lane.opp.joined(separator: " + "))")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.cInk)
                                    Spacer()
                                    HStack(spacing: 10) {
                                        strokeBtn(icon: "minus") { adjustLaneStroke(key: key, delta: -1.0) }
                                        Text(formatStroke(strokes))
                                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                                            .foregroundColor(.cFairway)
                                            .frame(width: 28, alignment: .center)
                                        halfStrokeBtn(active: hasHalfStroke(strokes)) {
                                            adjustLaneStroke(key: key, delta: hasHalfStroke(strokes) ? -0.5 : 0.5)
                                        }
                                        strokeBtn(icon: "plus") { adjustLaneStroke(key: key, delta: 1.0) }
                                    }
                                }

                                HStack {
                                    Text("Da strokes")
                                        .font(.system(size: 12)).foregroundColor(.cMuted)
                                    Spacer()
                                    HStack(spacing: 2) {
                                        ForEach(allPairMembers, id: \.self) { alias in
                                            let isBase = lane.base.contains(alias)
                                            Button {
                                                laneCarrierByKey[key] = alias
                                            } label: {
                                                Text(alias)
                                                    .font(.system(size: 11.5, weight: .semibold))
                                                    .foregroundColor(carrier == alias ? (isBase ? .cFairway : .cBrick) : .cMuted)
                                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                                    .background(carrier == alias ? Color.cSurface : Color.clear)
                                                    .cornerRadius(6)
                                            }
                                        }
                                    }
                                    .padding(2)
                                    .background(Color.cSegBg)
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            if idx < lanes.count - 1 {
                                Color.cRowDiv.frame(height: 1).padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Color.cSurface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
                    Text("\"Da strokes\" = esa pareja es la más fuerte y le da ventaja a la otra. Verde = pareja base, rojo = rival.")
                        .font(.system(size: 11.5)).foregroundColor(.cMuted).lineSpacing(3)
                }
            }
        }
    }

    // MARK: Unidades calculadas (dentro del paso Jugadores — ajuste fino global, no por rival)

    // Unidades calculadas (Birdie, Águila, Albatros, Hole in One, Birdie 18) son automáticas —
    // un solo switch las activa/desactiva todas, no se eligen una por una. Es global (no por
    // rival): cada oponente ya elige su propia plantilla de $ arriba, pero cuáles unidades
    // cuentan sigue siendo una sola decisión para toda la ronda.
    private var unidadesCalculadasStep: some View {
        let calculadoBets = matchManager.betCatalog.filter { $0.mode == .calculado }
        return Group {
            if !calculadoBets.isEmpty {
                let ids = calculadoBets.map(\.id)
                let unidadesOn = ids.allSatisfy { selectedBetIds.contains($0) }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionTitle("Unidades")
                        Text(calculadoBets.map(\.name).joined(separator: ", "))
                            .font(.system(size: 11.5)).foregroundColor(.cMuted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { unidadesOn },
                        set: { on in if on { selectedBetIds.formUnion(ids) } else { selectedBetIds.subtract(ids) } }
                    )).labelsHidden().toggleStyle(SwitchToggleStyle(tint: .cFairway))
                }
                .padding(16)
                .background(Color.cSurface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
            }
        }
    }

    // MARK: Apuesta de parejas (dentro del paso Parejas — un solo valor, igual para las 3 combinaciones)

    private var parejaApuestaStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Apuesta de parejas")
            Text("Esta plantilla fija vuelta, presión, match y unidad para todas las combinaciones de pareja — no varía por lane.")
                .font(.system(size: 12)).foregroundColor(.cMuted).lineSpacing(4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templateStore.entries) { tpl in
                        let selected = selectedTemplateId == tpl.id
                        Button { applyTemplateLocally(tpl) } label: {
                            Text(tpl.name)
                                .font(.system(size: 13, weight: selected ? .black : .semibold))
                                .foregroundColor(selected ? .cBg : .cFairway)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(selected ? Color.cFairway : Color.cSurface)
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color.cFairway.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.cMuted)
                    TextField("Valor vuelta", text: $vueltaValueText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cInk)
                }
                .padding(.horizontal, 12).frame(height: 44).frame(maxWidth: .infinity)
                .background(Color.cBg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cBorder, lineWidth: 1))
                .cornerRadius(10)

                if unitValueFromText() > 0 {
                    Text("Unidad: $\(unitValueFromText())")
                        .font(.system(size: 13)).foregroundColor(.cMuted)
                }
            }
        }
    }

    // Apuestas manuales (no las de unidades automáticas) — una lista con scroll por tipo, para ahorrar espacio.
    @ViewBuilder
    private func betPickerScroll(title: String, type: BetType) -> some View {
        let bets = matchManager.betCatalog.filter { $0.type == type && $0.mode == .manual }
        if !bets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(title)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(bets.enumerated()), id: \.offset) { idx, bet in
                            Toggle(isOn: Binding(
                                get: { selectedBetIds.contains(bet.id) },
                                set: { on in if on { selectedBetIds.insert(bet.id) } else { selectedBetIds.remove(bet.id) } }
                            )) {
                                Text(bet.name)
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.cInk)
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .cFairway))
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color.cSurface)
                            if idx < bets.count - 1 {
                                Color.cRowDiv.frame(height: 1).padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
                .background(Color.cSurface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
            }
        }
    }

    // MARK: Shared sub-views

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.cInk)
    }

    private func stepperBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.cInk)
                .frame(width: 46, height: 46)
                .background(Color.cBg)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cBorder, lineWidth: 1))
                .cornerRadius(12)
        }
    }

    private func strokeBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.cInk)
                .frame(width: 38, height: 38)
                .background(Color.cBg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cBorder, lineWidth: 1))
                .cornerRadius(10)
        }
    }

    // Control independiente por rival/lane para agregar o quitar exactamente 0.5 — cada matchup es su propio botón.
    private func halfStrokeBtn(active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("½")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(active ? .cBg : .cInk)
                .frame(width: 32, height: 38)
                .background(active ? Color.cFairway : Color.cBg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.cFairway : Color.cBorder, lineWidth: 1))
                .cornerRadius(10)
        }
    }

    private func hasHalfStroke(_ value: Double) -> Bool {
        Int((value * 2).rounded()) % 2 != 0
    }

    private func pickerRow(_ label: String, selection: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14)).foregroundColor(.cMuted)
            Spacer()
            Picker("", selection: selection) {
                ForEach(playerAliases, id: \.alias) { p in
                    Text("\(p.alias) — \(p.name)").tag(p.alias)
                }
            }
            .tint(.cFairway)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13)).foregroundColor(.cMuted)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
    }

    // MARK: Data & logic (unchanged from original)

    private var playerAliases: [(alias: String, name: String)] { buildAliases(from: playerNames) }

    private func loadDefaults() {
        if !selectedCourseId.isEmpty { return }
        selectedCourseId = matchManager.courseId.isEmpty ? CourseCatalog.default.id : matchManager.courseId
        startHole = matchManager.startHole
        playerNames = matchManager.players.map { $0.name }
        if playerNames.isEmpty { playerNames = ["Daniel"] }
        syncStrokes()
        if let first = playerAliases.first?.alias { base1 = first }
        if playerAliases.count > 1 { base2 = playerAliases[1].alias }
        syncLaneSetupState()
        vueltaValueText = matchManager.vueltaValue > 0 ? "\(matchManager.vueltaValue)" : ""
        selectedTemplateId = matchManager.activeTemplateId ?? ""
        selectedBetIds = Set(matchManager.activeBets.map { $0.definition.id })
        for bet in matchManager.activeBets {
            if let tag = bet.tagOverride { betTagOverrides[bet.definition.id] = tag }
        }
    }

    private func addPlayerName() {
        let clean = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, playerNames.count < 5 else { return }
        // Si el usuario tocó la sugerencia del mini-search usamos esa entrada; si en vez de eso
        // escribió el nombre completo y dio "Agregar" directo, buscamos por nombre exacto para no
        // perder el autofill de strokes/plantilla solo por no haber tocado el dropdown.
        let match = pendingDirectoryMatch ?? PlayerDirectoryStore.shared.entries.first(where: {
            $0.name.caseInsensitiveCompare(clean) == .orderedSame
        })
        playerNames.append(clean); newPlayerName = ""; pendingDirectoryMatch = nil
        syncStrokes(); syncBaseDefaults()
        // Si el nombre agregado viene de una sugerencia del directorio, usa sus strokes/tag en
        // vez de los defaults que syncStrokes() ya puso — el alias real lo sigue decidiendo
        // buildAliases (no forzamos el alias guardado, solo strokes y plantilla).
        if let match, match.name.caseInsensitiveCompare(clean) == .orderedSame,
           let alias = playerAliases.first(where: { $0.name == clean })?.alias {
            strokesByAlias[alias] = match.strokesVsBase
            if let tag = match.preferredTagId { templateIdByOpponent[alias] = tag }
        }
    }

    private func formatStrokeShort(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    private func syncStrokes() {
        let aliases = playerAliases.map { $0.alias }.filter { $0 != matchManager.yoAlias }
        for a in aliases where strokesByAlias[a] == nil {
            let current = matchManager.players.first(where: { $0.alias == a })
            // Un jugador ya en el match con strokes en 0 suele significar que nunca se le asignó
            // nada (se agregó antes de que existiera el directorio, o sin pasar por el mini-search)
            // — en ese caso preferimos lo que el directorio tiene guardado para ese nombre en vez
            // de perpetuar el 0. Si el match ya trae un valor explícito distinto de 0, se respeta.
            if let current, current.strokesVsBase != 0 {
                strokesByAlias[a] = current.strokesVsBase
            } else if let name = current?.name,
                      let dirEntry = PlayerDirectoryStore.shared.entries.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                strokesByAlias[a] = dirEntry.strokesVsBase
            } else {
                strokesByAlias[a] = current?.strokesVsBase ?? 0
            }
        }
        for key in strokesByAlias.keys where !aliases.contains(key) { strokesByAlias.removeValue(forKey: key) }

        for a in aliases where templateIdByOpponent[a] == nil {
            templateIdByOpponent[a] = matchManager.betValuesByOpponent[a]?.templateId
                ?? templateStore.entries.first?.id ?? ""
        }
        for key in templateIdByOpponent.keys where !aliases.contains(key) { templateIdByOpponent.removeValue(forKey: key) }
    }

    private func syncBaseDefaults() {
        if base1.isEmpty, let first = playerAliases.first?.alias { base1 = first }
        if base2.isEmpty, playerAliases.count > 1 { base2 = playerAliases[1].alias }
    }

    private func opponentsForBase() -> [String] {
        let base = [base1, base2].filter { !$0.isEmpty }
        return playerAliases.map { $0.alias }.filter { !base.contains($0) }
    }

    private func buildLocalLanes() -> [LocalLane] {
        let base = [base1, base2].filter { !$0.isEmpty }
        if base.count < 2 { return [] }
        let all = playerAliases.map { $0.alias }
        let opp = all.filter { !base.contains($0) }
        if opp.count == 2 { return [LocalLane(base: base, opp: opp)] }
        if opp.count == 3 {
            return [[opp[0], opp[1]], [opp[0], opp[2]], [opp[1], opp[2]]].map { LocalLane(base: base, opp: $0) }
        }
        if base.count == 3 && opp.count == 2 { return [LocalLane(base: base, opp: opp)] }
        return []
    }

    private func unitValueFromText() -> Int {
        guard let v = Int(vueltaValueText) else { return 0 }
        return v / 2
    }

    private func canAdvance() -> Bool {
        switch step {
        case .campo:
            return !selectedCourseId.isEmpty && startHole >= 1 && startHole <= 18
        case .jugadores:
            return playerNames.count >= 2 && playerNames.count <= 5 && !playerAliases.isEmpty
        case .parejas:
            return playerAliases.count < 4 || (base1 != base2 && !base1.isEmpty && !base2.isEmpty)
        }
    }

    private func applySetup() {
        if let course = CourseCatalog.all.first(where: { $0.id == selectedCourseId }) {
            matchManager.setCourse(course, resetScores: false)
        }
        matchManager.updateStartHole(startHole, resetScores: false)
        matchManager.setPlayers(names: playerNames, preserveScores: true)
        for p in matchManager.players {
            if p.alias == matchManager.yoAlias { continue }
            let strokes = strokesByAlias[p.alias] ?? 0
            matchManager.setStrokesVsBase(alias: p.alias, value: strokes)
            let tplId = templateIdByOpponent[p.alias]
            if let tplId, let tpl = templateStore.entries.first(where: { $0.id == tplId }) {
                matchManager.setBetTemplateForOpponent(p.alias, template: tpl)
            }
            // Aprende/actualiza el directorio con lo que realmente quedó configurado para este
            // jugador — la próxima vez que se escriba su nombre, el mini-search ya sugiere estos
            // mismos strokes y plantilla.
            PlayerDirectoryStore.shared.upsert(name: p.name, alias: p.alias, strokesVsBase: strokes, preferredTagId: tplId)
        }
        let base = [base1, base2].filter { !$0.isEmpty }
        if base.count >= 2 {
            let opp = matchManager.players.map { $0.alias }.filter { !base.contains($0) }
            _ = matchManager.setBaseTeam(base, opponentsOverride: opp)
            for lane in buildLocalLanes() {
                let key = lane.id
                matchManager.setLaneStrokesForMatch(base: lane.base, opp: lane.opp, value: laneStrokes[key] ?? 0)
                if let carrier = laneCarrierByKey[key], !carrier.isEmpty {
                    matchManager.setLaneCarrierForMatch(base: lane.base, opp: lane.opp, carrier: carrier)
                }
            }
        }
        if let tpl = templateStore.entries.first(where: { $0.id == selectedTemplateId }) {
            matchManager.applyBetTemplate(tpl)
            // Si el usuario ajustó el monto de vuelta a mano después de elegir la plantilla, respeta ese override.
            if let v = Int(vueltaValueText), v != tpl.vueltaValue { matchManager.setVueltaValue(v) }
        } else if let v = Int(vueltaValueText) {
            matchManager.setVueltaValue(v)
        }
        let active = matchManager.betCatalog
            .filter { selectedBetIds.contains($0.id) }
            .map { def in ActiveBet(definition: def, tagOverride: tagOverridesValue(for: def.id)) }
        matchManager.setActiveBets(active)
    }

    private func tagOverridesValue(for id: UUID) -> String? {
        guard let raw = betTagOverrides[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    // Aplica la plantilla localmente al estado del wizard (no muta matchManager hasta "Guardar") —
    // preserva las apuestas manuales ya elegidas, solo reemplaza el subconjunto de unidades calculadas.
    private func applyTemplateLocally(_ tpl: BetTemplate) {
        selectedTemplateId = tpl.id
        vueltaValueText = "\(tpl.vueltaValue)"
        let calculadoIds = Set(matchManager.betCatalog.filter { $0.mode == .calculado }.map(\.id))
        selectedBetIds.subtract(calculadoIds)
        let templateIds = matchManager.betCatalog
            .filter { tpl.activeUnitTags.contains($0.tag.uppercased()) }
            .map(\.id)
        selectedBetIds.formUnion(templateIds)
    }

    private func templateName(_ id: String) -> String {
        templateStore.entries.first(where: { $0.id == id })?.name ?? id
    }

    private func buildAliases(from names: [String]) -> [(alias: String, name: String)] {
        var out: [(alias: String, name: String)] = []
        for name in names {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { continue }
            let alias = suggestAliasLocal(name: clean, existing: out.map { $0.alias })
            if alias.isEmpty { continue }
            out.append((alias: alias, name: clean))
        }
        return out
    }

    private func suggestAliasLocal(name: String, existing: [String]) -> String {
        let letters = name.uppercased().filter { $0.isLetter }
        if letters.isEmpty { return "" }
        var alias = String(letters.prefix(3))
        var counter = 1
        while existing.contains(alias) { alias = String(letters.prefix(3)) + String(counter); counter += 1 }
        return alias
    }

    private func formatStroke(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }

    private func formatSignedStroke(_ value: Double) -> String {
        (value > 0 ? "+" : "") + formatStroke(value)
    }

    private func adjustStroke(alias: String, delta: Double) {
        let next = max(-20, min(20, (strokesByAlias[alias] ?? 0) + delta))
        strokesByAlias[alias] = (next * 2).rounded() / 2
    }

    private func adjustLaneStroke(key: String, delta: Double) {
        let next = max(0, min(20, (laneStrokes[key] ?? 0) + delta))
        laneStrokes[key] = (next * 2).rounded() / 2
    }

    private func syncLaneSetupState() {
        let lanes = buildLocalLanes()
        let keys = Set(lanes.map { $0.id })
        for lane in lanes {
            let key = lane.id
            if laneStrokes[key] == nil {
                if let existing = matchManager.lanes.first(where: { Set($0.base) == Set(lane.base) && Set($0.opp) == Set(lane.opp) }) {
                    laneStrokes[key] = existing.strokes
                    laneCarrierByKey[key] = existing.strokeCarrier ?? ""
                } else {
                    laneStrokes[key] = 0; laneCarrierByKey[key] = ""
                }
            } else if laneCarrierByKey[key] == nil {
                laneCarrierByKey[key] = ""
            }
        }
        for key in laneStrokes.keys where !keys.contains(key) { laneStrokes.removeValue(forKey: key) }
        for key in laneCarrierByKey.keys where !keys.contains(key) { laneCarrierByKey.removeValue(forKey: key) }
    }

    private struct LocalLane: Identifiable {
        let id: String
        let base: [String]
        let opp: [String]
        init(base: [String], opp: [String]) {
            self.base = base; self.opp = opp
            self.id = (base.sorted() + ["vs"] + opp.sorted()).joined(separator: "-")
        }
    }
}


