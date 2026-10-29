//
//  VoiceSheetV2.swift
//  Caddie Score — v2t, Paso 2: el mic de la ronda (iPhone)
//
//  Dictar el hoyo completo → tarjeta (qué entendí / qué falta) → dictar lo que falta → Anotar → banner con Deshacer.
//  Todo el trabajo lo hace VoiceHolePipeline; aquí solo está la pantalla.
//  Graba con VoiceRecorder y transcribe con Whisper, igual que RescueCaptureView de la v1.
//

import SwiftUI

struct VoiceSheetV2: View {
    @ObservedObject var matchManager: MatchManager
    /// Hoyo que se juega en pantalla: es el de la tarjeta salvo que digas otro ("hoyo 7…").
    let hole: Int
    /// Se llama al anotar, con el hoyo y lo necesario para deshacer (el banner vive en la pantalla del hoyo).
    let onApplied: (Int, VoiceUndoToken) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()
    @State private var speech = SpeechReadbackV2()
    /// Lo que el apuntador acaba de leer (también se ve en pantalla).
    @State private var readbackText: WatchAnswerDTO?
    @State private var showContrast = false
    /// Lo último que se leyó: si es un resumen, el botón "Más detalle" repite lo mismo con el detalle.
    private enum LastRequest: Equatable { case intent(ReadbackIntentV2), query(ReadbackQueryV2) }
    @State private var lastRequest: LastRequest?
    /// El detalle ya tiene su pantalla en la app: Resultados (todos los matches) o el detalle del match preguntado.
    private enum DetailScreen: Identifiable {
        case results, match(MatchManager.ResultadoRowV2)
        var id: String { switch self { case .results: "results"; case .match(let row): "match-\(row.id)" } }
    }
    @State private var detailScreen: DetailScreen?
    @State private var lastWasDetailed = false
    @State private var correctionRoute: VoiceHolePipeline.CorrectionRoute?

    /// Las respuestas se dicen en voz alta (un brief corto) además de verse; se silencian con la clave `speakAnswers` = false.
    private static var speaksAnswers: Bool { UserDefaults.standard.object(forKey: "speakAnswers") as? Bool ?? true }

    private enum Phase: Equatable { case idle, recording, processing, failed(String) }
    @State private var phase: Phase = .idle
    /// Lo entendido hasta ahora: cada dictada nueva se suma hasta que el hoyo queda resuelto.
    @State private var draft = VoiceHoleDraft()
    /// Grabaciones de esta sesión; al anotar quedan ligadas a la tarjeta final (para reentrenar).
    @State private var recordIds: [String] = []

    private var report: VoiceHoleReport { VoiceHolePipeline.report(draft, match: matchManager) }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: CSV2.s2) {
                    HStack {
                        Text("Dictar el hoyo").font(.v2Name).foregroundStyle(CSV2.ink)
                        Spacer()
                        Button("Cerrar") { recorder.cancelIfNeeded(); speech.stop(); dismiss() }
                            .font(.v2Body).foregroundStyle(CSV2.secondary).frame(minHeight: CSV2.minTap)
                    }
                    holeBanner
                    if let readbackText { readbackCard(readbackText) }
                    if !draft.isEmpty || !draft.ignored.isEmpty { reviewCard }
                    controls
                    learningLine
                }
                .padding(CSV2.s2)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showContrast) { ContrastSheetV2(matchManager: matchManager) }
        .sheet(item: $detailScreen) { screen in
            switch screen {
            case .results: ResultadoV2(matchManager: matchManager)
            case .match(let row): MatchDetailV2(matchManager: matchManager, row: row)
            }
        }
        .sheet(item: $correctionRoute) { route in
            switch route {
            case .player(let alias, let segment, let focus):
                ContrastSheetV2(matchManager: matchManager, alias: alias, segment: segment, focusHole: focus)
            case .hole(let h):
                HoleCorrectionSheetV2(matchManager: matchManager, hole: h)
            }
        }
    }

    /// Qué hoyo se está grabando: el de la pantalla, hasta que el dictado diga otro.
    private var holeBanner: some View {
        let current = draft.hole ?? hole
        let changed = current != hole
        return VStack(alignment: .leading, spacing: 2) {
            Text("Hoyo \(current)").font(.v2Name).foregroundStyle(CSV2.ink)
            if changed {
                Text("Cambiaste del hoyo \(hole). Di \"hoyo \(hole)\" para volver.").font(.v2Label).foregroundStyle(CSV2.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Grabar

    @ViewBuilder
    private var controls: some View {
        switch phase {
        case .idle:
            VStack(spacing: CSV2.s2) {
                Text(draft.isEmpty
                     ? "Di el hoyo: \"Hoyo 14, yo 3, Rob 4\""
                     : "Dicta solo lo que falta o corrige.")
                    .font(.v2Label).foregroundStyle(CSV2.secondary).multilineTextAlignment(.center)
                micButton(symbol: "mic.circle.fill", color: CSV2.green, label: draft.isEmpty ? "Empezar a grabar" : "Dictar lo que falta") { start() }
                readbackButtons
            }.frame(maxWidth: .infinity)
        case .recording:
            VStack(spacing: CSV2.s2) {
                Text("Grabando…").font(.v2Name).foregroundStyle(CSV2.warning)
                micButton(symbol: "stop.circle.fill", color: CSV2.warning, label: "Detener y procesar") { stop() }
                Text("Toca para detener").font(.v2Label).foregroundStyle(CSV2.secondary)
            }.frame(maxWidth: .infinity)
        case .processing:
            VStack(spacing: CSV2.s2) {
                ProgressView().scaleEffect(1.4)
                Text("Procesando…").font(.v2Body).foregroundStyle(CSV2.secondary)
            }.frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let message):
            VStack(spacing: CSV2.s2) {
                Text(message).font(.v2Body).foregroundStyle(CSV2.ink).multilineTextAlignment(.center)
                PrimaryButtonV2(title: "Reintentar") { phase = .idle }
            }.frame(maxWidth: .infinity)
        }
    }

    private func micButton(symbol: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: draft.isEmpty ? 88 : 64)).foregroundStyle(color)
                .frame(minWidth: CSV2.minTap, minHeight: CSV2.minTap)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: El apuntador lee lo que ya está anotado

    /// Tres funciones: revisar lo anotado (unidades, strokes, hoyo), las apuestas (vuelta, presión, match) y el acumulado.
    private var readbackButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("O pregunta hablando: \"cómo voy\", \"por qué\"")
                .font(.v2Label).foregroundStyle(CSV2.secondary)
            readbackGroup("Revisar") {
                readbackChip("Unidades", "plus.circle") { ask(.init(tipo: "unidades")) }
                readbackChip("Strokes", "circle.dotted") { ask(.init(tipo: "strokes")) }
                readbackChip("Este hoyo", "list.number") { ask(.init(tipo: "hoyo", jugador: "yo")) }
                readbackChip("Qué falta", "questionmark.circle") { readAloud(.missing) }
                readbackChip("Contrastar tarjeta", "checklist") { showContrast = true }
            }
            readbackGroup("Apuestas") {
                readbackChip("Vuelta", "arrow.triangle.2.circlepath") { ask(.init(tipo: "vuelta")) }
                readbackChip("Presión", "arrow.triangle.branch") { ask(.init(tipo: "presion")) }
                readbackChip("Match", "flag") { ask(.init(tipo: "match")) }
                readbackChip("F9", "1.circle") { ask(.init(tipo: "nueve", segmento: "F9")) }
                readbackChip("B9", "2.circle") { ask(.init(tipo: "nueve", segmento: "B9")) }
            }
            readbackGroup("Acumulado") {
                readbackChip("Cómo vamos", "speaker.wave.2") { ask(.init(tipo: "estatus")) }
                readbackChip("Dinero", "dollarsign.circle") { ask(.init(tipo: "dinero")) }
                readbackChip("Por qué", "text.bubble") { ask(.init(tipo: "explicar")) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readbackGroup<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).capsStyleV2()
            FlowChipsV2 { content() }
        }
    }

    /// Una pregunta de los botones: se responde igual que una hablada.
    private func ask(_ q: ReadbackQueryV2, detail: Bool = false) {
        // El detalle de cómo voy / por qué no se lee ni se repinta aquí: se abre su pantalla.
        if detail || (q.detalle ?? false), VoiceHolePipeline.isDetailQuery(q) { openDetail(for: q); return }
        let answer = VoiceHolePipeline.shortAnswer(q, match: matchManager, currentHole: draft.hole ?? hole, detail: detail)
        lastRequest = .query(q); lastWasDetailed = detail || (q.detalle ?? false)
        readbackText = answer
        if Self.speaksAnswers { speech.speak(answer.spoken) }
    }

    /// Un match preguntado abre su detalle; varios abren Resultados.
    private func openDetail(for q: ReadbackQueryV2) {
        speech.stop()
        let rows = VoiceHolePipeline.detailRows(for: q, match: matchManager)
        detailScreen = rows.count == 1 ? .match(rows[0]) : .results
    }

    /// Tras "cómo voy" o "por qué": contrastar la tarjeta y corregir.
    private var showsCardActions: Bool {
        if case .query(let q)? = lastRequest { return VoiceHolePipeline.isDetailQuery(q) }
        return false
    }

    private func readbackChip(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.v2Label.weight(.semibold)).foregroundStyle(CSV2.green)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .overlay(Capsule().stroke(CSV2.green.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    /// Una fila de la respuesta corta: nombre a la izquierda, números a la derecha (verde ganando, rojo perdiendo).
    @ViewBuilder
    private func answerRow(_ line: WatchAnswerDTO.Line) -> some View {
        if line.header {
            HStack {
                Text(line.label.uppercased()).capsStyleV2()
                Spacer(minLength: 8)
                if !line.value.isEmpty {
                    Text(line.value).font(.v2Body.weight(.bold).monospacedDigit())
                        .foregroundStyle(line.tone > 0 ? CSV2.green : line.tone < 0 ? CSV2.red : CSV2.ink)
                }
            }.padding(.top, 4)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(line.label).font(.v2Body.weight(.semibold)).foregroundStyle(CSV2.ink)
                    Spacer(minLength: 8)
                    if !line.value.isEmpty {
                        Text(line.value).font(.v2Name.monospacedDigit())
                            .foregroundStyle(line.tone > 0 ? CSV2.green : line.tone < 0 ? CSV2.red : CSV2.ink)
                    }
                }
                if let detail = line.detail { Text(detail).font(.v2Label).foregroundStyle(CSV2.secondary) }
            }
            .padding(.vertical, 2)
        }
    }

    private func readbackCard(_ answer: WatchAnswerDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(answer.title.isEmpty ? "Respuesta" : answer.title).capsStyleV2()
            if let text = answer.text { Text(text).font(.v2Body).foregroundStyle(CSV2.ink) }
            ForEach(Array(answer.lines.enumerated()), id: \.offset) { _, line in answerRow(line) }
            HStack(spacing: 16) {
                if !lastWasDetailed, lastRequest != nil {
                    Button { moreDetail() } label: {
                        Label("Más detalle", systemImage: "text.append").font(.v2Body.weight(.semibold)).foregroundStyle(CSV2.green).frame(minHeight: CSV2.minTap)
                    }.buttonStyle(.plain)
                }
                if showsCardActions {
                    Button { showContrast = true } label: {
                        Label("Contrastar", systemImage: "checklist").font(.v2Body.weight(.semibold)).foregroundStyle(CSV2.ink).frame(minHeight: CSV2.minTap)
                    }.buttonStyle(.plain)
                }
                if let route = currentRoute {
                    Button { correctionRoute = route } label: {
                        Label("Corregir", systemImage: "pencil").font(.v2Body.weight(.semibold)).foregroundStyle(CSV2.ink).frame(minHeight: CSV2.minTap)
                    }.buttonStyle(.plain)
                }
                if speech.isSpeaking {
                    Button { speech.stop() } label: {
                        Label("Detener", systemImage: "stop.fill").font(.v2Body).foregroundStyle(CSV2.warning).frame(minHeight: CSV2.minTap)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
        .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
        .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).strokeBorder(CSV2.line))
        .accessibilityElement(children: .combine)
    }

    private func readAloud(_ intent: ReadbackIntentV2, detail: Bool = false) {
        let text = matchManager.readbackV2(intent, hole: draft.hole ?? hole, detail: detail)
        lastRequest = .intent(intent); lastWasDetailed = detail
        readbackText = .plain(text)
        if Self.speaksAnswers { speech.speak(text) }
    }

    /// Dónde se corrige lo último que se leyó (nil si no hay nada que corregir: dinero, presiones, strokes…).
    private var currentRoute: VoiceHolePipeline.CorrectionRoute? {
        let current = draft.hole ?? hole
        switch lastRequest {
        case .intent(let intent)?: return VoiceHolePipeline.correctionRoute(for: intent, hole: current)
        case .query(let q)?: return VoiceHolePipeline.correctionRoute(for: q, match: matchManager, currentHole: current)
        case nil: return nil
        }
    }

    /// Repite lo último con el detalle.
    private func moreDetail() {
        switch lastRequest {
        case .intent(let intent)?: readAloud(intent, detail: true)
        case .query(let q)?:
            // Tras "cómo voy", lo siguiente son los dos hoyos anteriores (como leer la tarjeta); el detalle largo viene después.
            if VoiceHolePipeline.isStatusQuery(q) { ask(.init(tipo: "explicar", jugador: q.jugador, oponente: q.oponente)) }
            else { ask(q, detail: true) }
        case nil: break
        }
    }

    // MARK: Tarjeta: cómo se vería + qué falta

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: CSV2.s2) {
            Text("Hoyo \(draft.hole.map(String.init) ?? "?") · así quedaría").capsStyleV2()
            VStack(spacing: 0) {
                ForEach(matchManager.players.map(\.alias) + unknownAliases, id: \.self) { alias in playerRow(alias) }
            }
            if !draft.units.isEmpty || !draft.notes.isEmpty { extras }
            if !draft.edits.isEmpty { otherHoles }
            if !draft.unknownUnits.isEmpty { unknownUnitsMenu }
            messageBox
            actionButtons
            if let last = draft.transcripts.last {
                Text("\"\(last)\"").font(.v2Label).foregroundStyle(CSV2.secondary)
            }
        }
    }

    private var unknownAliases: [String] {
        draft.cells.keys.filter { alias in !matchManager.players.contains { $0.alias == alias } }.sorted()
    }

    private func playerRow(_ alias: String) -> some View {
        let cell = draft.cells[alias]
        let isKnown = matchManager.players.contains { $0.alias == alias }
        let savedGross = matchManager.getScore(hole: draft.hole ?? hole, player: alias)
        let savedPutts = matchManager.getPutts(hole: draft.hole ?? hole, player: alias)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(alias).font(.v2Name).foregroundStyle(isKnown ? CSV2.ink : CSV2.warning)
                Spacer()
                if let g = cell?.gross {
                    Text("\(g)").font(.v2Name).foregroundStyle(CSV2.ink)
                } else if savedGross > 0 {
                    Text("\(savedGross)").font(.v2Name).foregroundStyle(CSV2.secondary)   // ya estaba anotado: no falta
                    Text("ya anotado").font(.v2Label).foregroundStyle(CSV2.secondary)
                } else {
                    Text("falta").font(.v2Label).foregroundStyle(CSV2.warning)
                }
                if cell?.gross != nil {
                    let shown = cell?.putts ?? (savedPutts > 0 ? savedPutts : nil)
                    Text(shown.map { "\($0) putts" } ?? "sin putts")
                        .font(.v2Label).foregroundStyle(shown == nil ? CSV2.warning : CSV2.secondary)
                }
                if let rank = draft.oyes[alias] {
                    Text("oyes \(rank)°").font(.v2Label).foregroundStyle(CSV2.green)
                }
            }
            .padding(.top, 8)
            if !isKnown { reassignMenu(from: alias) }
            RowDividerV2()
        }
    }

    /// Un nombre que no está en el roster ("Chino") se reasigna con un toque; la app aprende el apodo.
    private func reassignMenu(from wrong: String) -> some View {
        Menu {
            ForEach(matchManager.players, id: \.alias) { p in
                Button("\(wrong.capitalized) es \(p.alias)") {
                    draft = VoiceHolePipeline.reassign(draft, from: wrong, to: p.alias)
                }
            }
        } label: {
            Label("¿Quién es \"\(wrong.capitalized)\"?", systemImage: "person.fill.questionmark")
                .font(.v2Label).foregroundStyle(CSV2.warning).frame(minHeight: CSV2.minTap, alignment: .leading)
        }
    }

    /// Una unidad que no está en el catálogo: con un toque se asigna a una y la app aprende la frase.
    private var unknownUnitsMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(draft.unknownUnits, id: \.self) { u in
                Menu {
                    ForEach(VoiceHolePipeline.dictatableUnits(matchManager), id: \.tag) { unit in
                        Button("\(u.spoken) es \(unit.name)") { draft = VoiceHolePipeline.assignUnit(draft, spoken: u.spoken, to: unit.tag) }
                    }
                } label: {
                    Label("¿Qué unidad es \"\(u.spoken)\"? (\(matchManager.spokenName(u.alias)))", systemImage: "questionmark.circle")
                        .font(.v2Label).foregroundStyle(CSV2.warning).frame(minHeight: CSV2.minTap, alignment: .leading)
                }
            }
        }
    }

    /// Cómo va el aprendizaje, en una línea.
    private var learningLine: some View {
        let st = VoiceRecordStore.shared.stats()
        return Group {
            if st.resolvedHoles > 0 {
                Text("Aprendizaje: \(st.dictations) dictadas · \(st.firstTry) de \(st.resolvedHoles) hoyos salieron a la primera · \(VoiceSlangStore.shared.terms.count) apodos y frases aprendidos")
                    .font(.v2Label).foregroundStyle(CSV2.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Cambios en otros hoyos (corridas y "se levantó"), tal como se van a anotar.
    private var otherHoles: some View {
        let lines = VoiceHolePipeline.editLines(draft, match: matchManager)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Otros hoyos").capsStyleV2()
            ForEach(lines.understood, id: \.self) { Text($0).font(.v2Body).foregroundStyle(CSV2.ink) }
            ForEach(lines.missing, id: \.self) { Text($0).font(.v2Label).foregroundStyle(CSV2.warning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(draft.units, id: \.self) { u in
                Text("\(u.alias) · \(VoiceHolePipeline.unitName(u.code, match: matchManager))" + (u.units > 1 ? " ×\(u.units)" : ""))
                    .font(.v2Body).foregroundStyle(CSV2.ink)
            }
            ForEach(draft.notes, id: \.self) { n in
                Text("Nota \(n.alias): \(n.text)").font(.v2Label).foregroundStyle(CSV2.secondary)
            }
        }
    }

    /// "Entendí… Falta…" (también es lo que leería el Watch / una voz).
    private var messageBox: some View {
        Text(report.message)
            .font(.v2Body).foregroundStyle(CSV2.ink)
            .padding(CSV2.s2).frame(maxWidth: .infinity, alignment: .leading)
            .background(report.isComplete ? CSV2.surface : CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard)
                .strokeBorder(report.isComplete ? CSV2.green : CSV2.warning, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Empezar de nuevo") { draft = VoiceHoleDraft(); recordIds = [] }
                .font(.v2Body).foregroundStyle(CSV2.secondary).frame(maxWidth: .infinity, minHeight: CSV2.minTap)
            PrimaryButtonV2(title: report.isComplete ? "Anotar" : "Anotar así") { applyDraft() }
                .disabled(!VoiceHolePipeline.canApply(draft, match: matchManager))
        }
    }

    private func applyDraft() {
        guard let hole = draft.hole, let token = VoiceHolePipeline.apply(draft, match: matchManager) else { return }
        VoiceRecordStore.shared.resolve(ids: recordIds, finalCard: VoiceHolePipeline.cardSummary(draft))
        onApplied(hole, token)
        dismiss()
    }

    // MARK: Grabar → transcribir → entender

    private func start() {
        speech.stop()
        // Una respuesta vieja no se queda encima de lo que se va a dictar ahora: la pantalla vuelve al micrófono limpio.
        readbackText = nil
        lastRequest = nil
        guard AppConfig.hasOpenAIKey else {
            phase = .failed("Falta la clave de OpenAI. Pon tu archivo caddie.env en la carpeta de la app (Archivos > Caddie Score). Ejemplo: caddie.env.example")
            return
        }
        recorder.requestMicrophoneAndStart { granted in
            phase = granted ? .recording : .failed("Permiso de micrófono denegado. Actívalo en Ajustes.")
        }
    }

    private func stop() {
        guard let url = recorder.stopRecording() else {
            phase = .failed("No se pudo grabar. Intenta de nuevo.")
            return
        }
        phase = .processing
        Task {
            do {
                let helpText = VoiceHolePipeline.transcriptionPrompt(match: matchManager)
                let text = try await OpenAIService.shared.transcribeAudio(url: url, prompt: helpText)
                // Con audio vacío Whisper devuelve el texto de ayuda: no es una dictada.
                if VoiceHolePipeline.isPromptEcho(text, prompt: helpText) { throw VoiceHoleError.emptyTranscript }
                // "Qué llevo" / "cómo vamos" / "qué falta": no es un dato del hoyo, es una petición de lectura.
                if let intent = ReadbackIntentV2.detect(text, names: matchManager.players.flatMap { [$0.alias, $0.name.split(separator: " ").first.map(String.init) ?? $0.name] }) {
                    let detail = ReadbackIntentV2.asksForDetail(text)
                    // "Cómo vamos" = nombres y números; "explícame" = los dos hoyos anteriores.
                    if intent == .round { ask(.init(tipo: detail ? "explicar" : "estatus")) } else { readAloud(intent, detail: detail) }
                    phase = .idle
                    return
                }
                // La grabación se guarda aunque no se entienda: también sirve para aprender.
                recordIds.append(VoiceRecordStore.shared.record(audio: url, transcript: text,
                                                                roundId: matchManager.roundId, hole: draft.hole))
                draft = try await VoiceHolePipeline.propose(transcript: text, match: matchManager, draft: draft, defaultHole: hole,
                                                            extractor: VoiceHolePipeline.fastThenLive(match: matchManager))
                phase = .idle
            } catch VoiceHoleError.query(let q) {
                ask(q)
                phase = .idle
            } catch let error as VoiceHoleError {
                phase = .failed(error.message)
            } catch {
                phase = .failed("No se pudo procesar: \(error.localizedDescription)")
            }
        }
    }
}

extension VoiceRecorder {
    /// Si se cierra la hoja grabando, corta la grabación y descarta el audio.
    func cancelIfNeeded() {
        if isRecording { _ = stopRecording() }
    }
}

#if DEBUG
#Preview("VoiceSheetV2") {
    let manager = MatchManager()
    manager.loadDemo18()
    return VoiceSheetV2(matchManager: manager, hole: 14) { _, _ in }
}
#endif
