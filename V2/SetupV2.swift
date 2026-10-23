//
//  SetupV2.swift
//  Caddie Score — Vista v2, Paso 8: Setup en 3 pasos (Campo · Oponentes · Parejas)
//
//  El estado y las reglas del Setup salen de SetupDraftModel y el guardado de MatchManager.applySetupDraft /
//  applyCourseAndStartHole: los mismos que la v1 (R1, R3, R5, R11, R12). Aquí solo cambia cómo se ve:
//  strokes en palabras ("ALC recibe 3½ · hoyos 17, 4, 11 y ½ en 2"), controles grandes y la pareja base según el
//  modelo real (pareja base + carriles). Directorio, Log y Apuestas abren las vistas de la v1.
//

import SwiftUI

struct SetupV2: View {
    @ObservedObject var matchManager: MatchManager
    @StateObject private var model: SetupDraftModel
    @ObservedObject private var templateStore = BetTemplateStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var stepIndex: Int
    @State private var newPlayerName = ""
    @State private var pendingDirectoryMatch: PlayerDirectoryEntry?
    @State private var showDirectory = false
    @State private var showHistory = false
    @State private var showBets = false
    @State private var showCatalog = false

    private let stepTitles = ["Campo", "Oponentes", "Parejas"]

    init(matchManager: MatchManager, initialStep: Int = 0) {
        self.matchManager = matchManager
        _stepIndex = State(initialValue: initialStep)
        _model = StateObject(wrappedValue: SetupDraftModel(manager: matchManager))
    }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: CSV2.s2) { stepContent }
                        .padding(.horizontal, CSV2.s2).padding(.bottom, CSV2.s3)
                }
            }
        }
        .onAppear { model.load() }
        .onChange(of: model.base1) { _, _ in model.syncLanes() }
        .onChange(of: model.base2) { _, _ in model.syncLanes() }
        .sheet(isPresented: $showDirectory) { PlayerDirectoryView() }
        .sheet(isPresented: $showHistory) { HistorialV2() }
        .sheet(isPresented: $showCatalog) { CatalogoV2(matchManager: matchManager) }
        .sheet(isPresented: $showBets, onDismiss: {
            // Recoge altas/bajas/cambios de valor hechos en el catálogo para que ya aparezcan en este Setup.
            matchManager.setupDefaultBets()
        }) {
            BetsHubView(matchManager: matchManager)
        }
    }

    // MARK: Barra superior y progreso

    private var isLast: Bool { stepIndex == stepTitles.count - 1 }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: CSV2.s1) {
            HStack {
                Button {
                    if stepIndex == 0 { dismiss() } else { stepIndex -= 1 }
                } label: {
                    Text(stepIndex == 0 ? "Cancelar" : "Atrás").font(.v2Body).foregroundStyle(CSV2.ink)
                        .frame(minHeight: CSV2.minTap)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Setup").font(.v2Name).foregroundStyle(CSV2.ink)
                Spacer()
                Button {
                    if isLast {
                        model.save()
                        dismiss()
                    } else {
                        // Campo + hoyo de salida se aplican al avanzar (como en la v1): los golpes se reparten de nuevo
                        // y se apagan Carry, Ajuste 50 y Doble Press si estaban activos.
                        if stepIndex == 0 { model.applyCourseAndStartHole() }
                        stepIndex += 1
                    }
                } label: {
                    Text(isLast ? "Guardar" : "Siguiente").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: 40)
                        .background(CSV2.green, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!model.canAdvance(step: stepIndex))
                .opacity(model.canAdvance(step: stepIndex) ? 1 : 0.4)
            }
            HStack(spacing: 4) {
                ForEach(0..<stepTitles.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= stepIndex ? CSV2.green : CSV2.line)
                        .frame(height: 4)
                }
            }
            Text("Paso \(stepIndex + 1) de \(stepTitles.count) · \(stepTitles[stepIndex])")
                .capsStyleV2()
        }
        .padding(.horizontal, CSV2.s2).padding(.top, CSV2.s1).padding(.bottom, CSV2.s2)
    }

    @ViewBuilder private var stepContent: some View {
        switch stepIndex {
        case 0:
            courseCard
            startHoleCard
        case 1:
            toolsRow
            addPlayerCard
            playersCard
            rivalsCard
        default:
            basePairCard
            lanesCard
            pairBetCard
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).capsStyleV2()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Paso 1 — Campo y hoyo de salida

    private var courseCard: some View {
        VStack(spacing: 8) {
            sectionTitle("Campo")
            CardV2 {
                VStack(spacing: 0) {
                    ForEach(Array(CourseCatalog.all.enumerated()), id: \.offset) { index, course in
                        if index > 0 { RowDividerV2() }
                        Button { model.courseId = course.id } label: {
                            HStack {
                                Image(systemName: "flag.fill").foregroundStyle(CSV2.green)
                                Text(course.name).font(.v2Body).foregroundStyle(CSV2.ink)
                                Spacer()
                                if course.id == model.courseId {
                                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(CSV2.green)
                                }
                            }
                            .padding(.horizontal, CSV2.s2).frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var startHoleCard: some View {
        VStack(spacing: 8) {
            sectionTitle("¿En qué hoyo empiezan?")
            CardV2 {
                VStack(spacing: CSV2.s2) {
                    HStack(spacing: CSV2.s2) {
                        StepButtonV2(symbol: "minus") { model.startHole = max(1, model.startHole - 1) }
                            .accessibilityLabel("Un hoyo antes")
                        VStack(spacing: 2) {
                            Text("\(model.startHole)").font(.v2Hole).foregroundStyle(CSV2.green)
                            Text("de 18 hoyos").font(.v2Label).foregroundStyle(CSV2.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        StepButtonV2(symbol: "plus") { model.startHole = min(18, model.startHole + 1) }
                            .accessibilityLabel("Un hoyo después")
                    }
                    Text("La vuelta se anota en el orden real de juego, empezando por este hoyo — no necesariamente el 1.")
                        .font(.v2Label).foregroundStyle(CSV2.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Al tocar Siguiente se aplica el campo y el hoyo de salida: los golpes se reparten de nuevo según el orden de juego y se apagan Carry, Ajuste 50 y Doble Press si estaban activos.")
                        .font(.v2Label).foregroundStyle(CSV2.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(CSV2.s2)
            }
        }
    }

    // MARK: Paso 2 — Oponentes, strokes y apuesta por rival

    private var toolsRow: some View {
        HStack(spacing: CSV2.s1) {
            toolButton("Log", "clock.arrow.circlepath") { showHistory = true }
            toolButton("Directorio", "person.text.rectangle") { showDirectory = true }
            toolButton("Apuestas", "dollarsign.circle") { showBets = true }
            toolButton("Catálogo", "slider.horizontal.3") { showCatalog = true }
        }
    }

    private func toolButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.v2Label)
            }
            .foregroundStyle(CSV2.green)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).stroke(CSV2.line))
        }
        .buttonStyle(.plain)
    }

    private var atCap: Bool { model.playerNames.count >= 5 }
    private var canAdd: Bool { !atCap && !newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var addPlayerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(atCap ? "Máximo de 5 jugadores alcanzado" : "Nombre del jugador", text: $newPlayerName)
                    .font(.v2Body).disabled(atCap)
                    .padding(.horizontal, 14).frame(minHeight: CSV2.minTap)
                    .background(CSV2.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CSV2.line))
                Button {
                    model.addPlayer(newPlayerName, directoryMatch: pendingDirectoryMatch)
                    newPlayerName = ""; pendingDirectoryMatch = nil
                } label: {
                    Text("Agregar").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(minHeight: CSV2.minTap)
                        .background(canAdd ? CSV2.green : CSV2.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).disabled(!canAdd)
            }
            // Mini-búsqueda del directorio: tocar una sugerencia precarga sus strokes y su plantilla.
            let matches = PlayerDirectoryStore.shared.search(newPlayerName)
            if !matches.isEmpty {
                CardV2 {
                    VStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { RowDividerV2() }
                            Button {
                                newPlayerName = entry.name
                                pendingDirectoryMatch = entry
                            } label: {
                                HStack(spacing: 8) {
                                    Text(entry.name).font(.v2Body).foregroundStyle(CSV2.ink)
                                    Text(entry.alias).font(.v2Label).foregroundStyle(CSV2.secondary)
                                    Spacer()
                                    Text("Strokes \(strokesTextV2(entry.strokesVsBase))").font(.v2Label).foregroundStyle(CSV2.secondary)
                                }
                                .padding(.horizontal, 14).frame(minHeight: CSV2.minTap)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var playersCard: some View {
        if !model.playerNames.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Jugadores")
                CardV2 {
                    VStack(spacing: 0) {
                        ForEach(Array(model.aliasList.enumerated()), id: \.offset) { index, player in
                            if index > 0 { RowDividerV2() }
                            HStack(spacing: 12) {
                                Text(player.alias).font(.v2Label).bold().foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(index < 2 ? CSV2.green : CSV2.secondary, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.name).font(.v2Body).foregroundStyle(CSV2.ink)
                                    Text(index == 0 ? "Pareja base 1" : index == 1 ? "Pareja base 2" : "Oponente")
                                        .font(.v2Label).foregroundStyle(CSV2.secondary)
                                }
                                Spacer()
                                Button { model.removePlayer(at: index) } label: {
                                    Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(CSV2.red)
                                        .frame(width: CSV2.minTap, height: CSV2.minTap)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Quitar a \(player.name)")
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }
                }
                Text("\(model.playerNames.count) de 5 jugadores\(atCap ? " · límite alcanzado" : "")")
                    .font(.v2Label).foregroundStyle(CSV2.secondary)
            }
        }
    }

    @ViewBuilder private var rivalsCard: some View {
        if !model.rivals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Strokes y apuesta por rival")
                Text("\(matchManager.players.first { $0.alias == matchManager.yoAlias }?.name ?? "Daniel") juega presión individual contra cada uno. Cada rival puede tener su propia plantilla de apuesta.")
                    .font(.v2Label).foregroundStyle(CSV2.secondary)
                CardV2 {
                    VStack(spacing: 0) {
                        ForEach(Array(model.rivals.enumerated()), id: \.offset) { index, rival in
                            if index > 0 { RowDividerV2() }
                            rivalRow(rival)
                        }
                    }
                }
            }
        }
    }

    private func rivalRow(_ rival: (alias: String, name: String)) -> some View {
        let strokes = model.strokesByAlias[rival.alias] ?? 0
        // Positivo = el rival recibe de yo; negativo = yo recibo del rival (misma convención que la v1).
        let receiver = strokes >= 0 ? rival.alias : matchManager.yoAlias
        return VStack(alignment: .leading, spacing: 10) {
            Text("vs \(rival.name)").font(.v2Name).foregroundStyle(CSV2.ink)
            HStack(spacing: 8) {
                StepButtonV2(symbol: "minus") { model.adjustStroke(alias: rival.alias, delta: -1) }
                    .accessibilityLabel("Un stroke menos")
                Text(strokesTextV2(abs(strokes))).font(.v2Score).foregroundStyle(strokes == 0 ? CSV2.secondary : CSV2.stroke)
                    .frame(minWidth: 56)
                HalfButtonV2(isOn: hasHalf(strokes)) {
                    model.adjustStroke(alias: rival.alias, delta: hasHalf(strokes) ? (strokes > 0 ? -0.5 : 0.5) : 0.5)
                }
                StepButtonV2(symbol: "plus") { model.adjustStroke(alias: rival.alias, delta: 1) }
                    .accessibilityLabel("Un stroke más")
                Spacer(minLength: 0)
            }
            StrokeTextV2(receiver: receiver, amount: abs(strokes),
                         detail: matchManager.strokeHolesText(total: strokes, startHole: model.startHole))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Apuesta").font(.v2Label).foregroundStyle(CSV2.secondary)
                Spacer()
                templateMenu(for: rival.alias)
            }
        }
        .padding(CSV2.s2)
    }

    private func hasHalf(_ value: Double) -> Bool { Int((abs(value) * 2).rounded()) % 2 != 0 }

    private func templateName(_ id: String) -> String {
        templateStore.entries.first(where: { $0.id == id })?.name ?? "Elegir"
    }

    private func templateMenu(for alias: String) -> some View {
        Menu {
            ForEach(templateStore.entries) { template in
                Button(template.name) { model.templateIdByOpponent[alias] = template.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text(templateName(model.templateIdByOpponent[alias] ?? "")).font(.v2Body)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(CSV2.green)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CSV2.green.opacity(0.4)))
        }
    }

    // MARK: Paso 3 — Pareja base, carriles y apuesta de parejas

    @ViewBuilder private var basePairCard: some View {
        if model.aliasList.count < 4 {
            hint("Se necesitan al menos 4 jugadores para configurar parejas.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Pareja base")
                CardV2 {
                    VStack(spacing: 0) {
                        basePicker("Jugador 1", selection: $model.base1)
                        RowDividerV2()
                        basePicker("Jugador 2", selection: $model.base2)
                    }
                }
                if model.base1 == model.base2 && !model.base1.isEmpty {
                    Text("La pareja base necesita dos jugadores distintos.").font(.v2Label).foregroundStyle(CSV2.red)
                } else if !model.opponentsForBase.isEmpty {
                    Text("Oponentes: \(model.opponentsForBase.joined(separator: " – "))").font(.v2Label).foregroundStyle(CSV2.secondary)
                }
            }
        }
    }

    private func basePicker(_ label: String, selection: Binding<String>) -> some View {
        let current = model.aliasList.first { $0.alias == selection.wrappedValue }
        return HStack {
            Text(label).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            Menu {
                Picker("", selection: selection) {
                    ForEach(model.aliasList, id: \.alias) { Text("\($0.alias) — \($0.name)").tag($0.alias) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(current.map { "\($0.alias) \($0.name)" } ?? "Elegir").font(.v2Body)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(CSV2.green)
                .frame(minHeight: CSV2.minTap)
            }
        }
        .padding(.horizontal, CSV2.s2)
    }

    @ViewBuilder private var lanesCard: some View {
        let lanes = model.lanes
        if !model.base1.isEmpty && !model.base2.isEmpty && model.base1 != model.base2 {
            VStack(alignment: .leading, spacing: 8) {
                CardV2 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pareja base").capsStyleV2()
                        Text("\(model.base1) – \(model.base2)").font(.v2Name).foregroundStyle(CSV2.ink)
                        if !model.opponentsForBase.isEmpty {
                            Text("vs \(model.opponentsForBase.joined(separator: " – ")) · rotando")
                                .font(.v2Label).foregroundStyle(CSV2.secondary)
                        }
                    }
                    .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
                }
                if lanes.isEmpty {
                    hint("Define primero la pareja base.")
                } else {
                    sectionTitle("Strokes y quién lleva, por rival")
                    CardV2 {
                        VStack(spacing: 0) {
                            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                                if index > 0 { RowDividerV2() }
                                laneRow(lane)
                            }
                        }
                    }
                }
            }
        }
    }

    private func laneRow(_ lane: (id: String, base: [String], opp: [String])) -> some View {
        let strokes = model.laneStrokes[lane.id] ?? 0
        let carrier = model.laneCarrierByKey[lane.id] ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            Text("vs \(lane.opp.joined(separator: " – "))").font(.v2Name).foregroundStyle(CSV2.ink)
            HStack(spacing: 8) {
                StepButtonV2(symbol: "minus") { model.adjustLaneStroke(key: lane.id, delta: -1) }
                    .accessibilityLabel("Un stroke menos")
                Text(strokesTextV2(strokes)).font(.v2Score).foregroundStyle(strokes == 0 ? CSV2.secondary : CSV2.stroke)
                    .frame(minWidth: 56)
                HalfButtonV2(isOn: hasHalf(strokes)) {
                    model.adjustLaneStroke(key: lane.id, delta: hasHalf(strokes) ? -0.5 : 0.5)
                }
                StepButtonV2(symbol: "plus") { model.adjustLaneStroke(key: lane.id, delta: 1) }
                    .accessibilityLabel("Un stroke más")
                Spacer(minLength: 0)
            }
            Text("Quién lleva los strokes").capsStyleV2()
            AliasChipRowV2(items: (lane.base + lane.opp).map { ($0, "\($0) lleva los strokes") }, selected: carrier, tint: CSV2.stroke) {
                model.laneCarrierByKey[lane.id] = $0
            }
            if strokes > 0 {
                if carrier.isEmpty {
                    Text("Elige quién lleva los strokes.").font(.v2Label).foregroundStyle(CSV2.red)
                } else {
                    StrokeTextV2(receiver: carrier, amount: strokes,
                                 detail: matchManager.strokeHolesText(total: strokes, startHole: model.startHole))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(CSV2.s2)
    }

    private var pairBetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Apuesta de parejas")
            Text("Esta plantilla fija vuelta, presión, match y unidad para todas las combinaciones de pareja — no varía por carril.")
                .font(.v2Label).foregroundStyle(CSV2.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(templateStore.entries) { template in
                        let on = model.selectedTemplateId == template.id
                        Button { model.applyTemplate(template) } label: {
                            Text(template.name).font(.v2Body).foregroundStyle(on ? .white : CSV2.green)
                                .padding(.horizontal, 16).frame(minHeight: CSV2.minTap)
                                .background(on ? CSV2.green : CSV2.surface, in: Capsule())
                                .overlay(Capsule().stroke(CSV2.green.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("$").font(.v2Body).foregroundStyle(CSV2.secondary)
                    TextField("Valor vuelta", text: $model.vueltaValueText)
                        .keyboardType(.numberPad).font(.v2Body)
                }
                .padding(.horizontal, 12).frame(minHeight: CSV2.minTap).frame(maxWidth: .infinity)
                .background(CSV2.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CSV2.line))
                if let value = Int(model.vueltaValueText), value / 2 > 0 {
                    Text("Unidad: $\(value / 2)").font(.v2Label).foregroundStyle(CSV2.secondary)
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.v2Body).foregroundStyle(CSV2.secondary)
            .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
            .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).stroke(CSV2.line))
    }
}

#if DEBUG
#Preview("SetupV2 · Oponentes (demo)") {
    let manager = MatchManager()
    manager.loadDemo18()
    return SetupV2(matchManager: manager, initialStep: 1)
}

#Preview("SetupV2 · Parejas (demo)") {
    let manager = MatchManager()
    manager.loadDemo18()
    return SetupV2(matchManager: manager, initialStep: 2)
}

#Preview("SetupV2 · Campo (demo)") {
    let manager = MatchManager()
    manager.loadDemo18()
    return SetupV2(matchManager: manager)
}
#endif
