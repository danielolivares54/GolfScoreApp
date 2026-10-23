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
    /// Se llama al anotar, con el hoyo y lo necesario para deshacer (el banner vive en la pantalla del hoyo).
    let onApplied: (Int, VoiceUndoToken) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()

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
                        Button("Cerrar") { recorder.cancelIfNeeded(); dismiss() }
                            .font(.v2Body).foregroundStyle(CSV2.secondary).frame(minHeight: CSV2.minTap)
                    }
                    if !draft.isEmpty { reviewCard }
                    controls
                }
                .padding(CSV2.s2)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Grabar

    @ViewBuilder
    private var controls: some View {
        switch phase {
        case .idle:
            VStack(spacing: CSV2.s2) {
                Text(draft.isEmpty
                     ? "Di el hoyo completo: scores, putts, oyes, unidades y notas. Ej: \"Hoyo 14, yo tres, Rob cuatro, oyes primero Rob segundo yo, yo sandy par\""
                     : "Dicta solo lo que falta o lo que quieras corregir; se suma a lo ya entendido.")
                    .font(.v2Label).foregroundStyle(CSV2.secondary).multilineTextAlignment(.center)
                micButton(symbol: "mic.circle.fill", color: CSV2.green, label: draft.isEmpty ? "Empezar a grabar" : "Dictar lo que falta") { start() }
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

    // MARK: Tarjeta: cómo se vería + qué falta

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: CSV2.s2) {
            Text("Hoyo \(draft.hole.map(String.init) ?? "?") · así quedaría").capsStyleV2()
            VStack(spacing: 0) {
                ForEach(matchManager.players.map(\.alias) + unknownAliases, id: \.self) { alias in playerRow(alias) }
            }
            if !draft.units.isEmpty || !draft.notes.isEmpty { extras }
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
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(alias).font(.v2Name).foregroundStyle(isKnown ? CSV2.ink : CSV2.warning)
                Spacer()
                if let g = cell?.gross {
                    Text("\(g)").font(.v2Name).foregroundStyle(CSV2.ink)
                } else {
                    Text("falta").font(.v2Label).foregroundStyle(CSV2.warning)
                }
                Text(cell?.putts.map { "\($0) putts" } ?? (cell?.gross == nil ? "" : "sin putts"))
                    .font(.v2Label).foregroundStyle(cell?.putts == nil ? CSV2.warning : CSV2.secondary)
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
                let text = try await OpenAIService.shared.transcribeAudio(url: url)
                // La grabación se guarda aunque no se entienda: también sirve para aprender.
                recordIds.append(VoiceRecordStore.shared.record(audio: url, transcript: text,
                                                                roundId: matchManager.roundId, hole: draft.hole))
                draft = try await VoiceHolePipeline.propose(transcript: text, match: matchManager, draft: draft)
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
    return VoiceSheetV2(matchManager: manager) { _, _ in }
}
#endif
