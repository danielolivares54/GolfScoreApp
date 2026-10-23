//
//  VoiceSheetV2.swift
//  Caddie Score — v2t, Paso 2: el mic de la ronda (iPhone)
//
//  Dictar el hoyo completo → tarjeta de confirmación → Anotar → banner con Deshacer.
//  Todo el trabajo lo hace VoiceHolePipeline (proponer / aplicar / deshacer); aquí solo está la pantalla.
//  Graba con VoiceRecorder y transcribe con Whisper, igual que RescueCaptureView de la v1.
//

import SwiftUI

struct VoiceSheetV2: View {
    @ObservedObject var matchManager: MatchManager
    /// Se llama al anotar, con lo necesario para deshacer (el banner vive en la pantalla del hoyo).
    let onApplied: (VoiceHoleProposal, VoiceUndoToken) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()

    private enum Phase: Equatable {
        case idle, recording, processing
        case review(VoiceHoleProposal)
        case failed(String)
    }
    @State private var phase: Phase = .idle

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: CSV2.s2) {
                HStack {
                    Text("Dictar el hoyo").font(.v2Name).foregroundStyle(CSV2.ink)
                    Spacer()
                    Button("Cerrar") { recorder.cancelIfNeeded(); dismiss() }
                        .font(.v2Body).foregroundStyle(CSV2.secondary).frame(minHeight: CSV2.minTap)
                }
                content
                Spacer(minLength: 0)
            }
            .padding(CSV2.s2)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            VStack(spacing: CSV2.s2) {
                Text("Di el hoyo completo: \"Yo cuatro, Anselmo cinco y los demás bogey\"")
                    .font(.v2Label).foregroundStyle(CSV2.secondary).multilineTextAlignment(.center)
                micButton(symbol: "mic.circle.fill", color: CSV2.green, label: "Empezar a grabar") { start() }
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
            }.frame(maxWidth: .infinity, minHeight: 160)
        case .review(let proposal):
            reviewCard(proposal)
        case .failed(let message):
            VStack(spacing: CSV2.s2) {
                Text(message).font(.v2Body).foregroundStyle(CSV2.ink).multilineTextAlignment(.center)
                PrimaryButtonV2(title: "Reintentar") { phase = .idle }
            }.frame(maxWidth: .infinity)
        }
    }

    private func micButton(symbol: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 88)).foregroundStyle(color)
                .frame(minWidth: CSV2.minTap, minHeight: CSV2.minTap)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Tarjeta de confirmación

    private func reviewCard(_ proposal: VoiceHoleProposal) -> some View {
        VStack(alignment: .leading, spacing: CSV2.s2) {
            Text("Hoyo \(proposal.hole) · se va a anotar").capsStyleV2()
            VStack(spacing: 0) {
                ForEach(proposal.rows) { row in
                    HStack {
                        Text(row.alias).font(.v2Name).foregroundStyle(CSV2.ink)
                        Spacer()
                        Text("\(row.gross)" + (row.putts.map { " · \($0) putts" } ?? ""))
                            .font(.v2Body).foregroundStyle(CSV2.ink)
                        if case .doubtful(let why) = row.state {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CSV2.warning)
                                .accessibilityLabel("Dudoso: \(why)")
                        }
                    }
                    .padding(.vertical, 10)
                    if case .doubtful(let why) = row.state {
                        Text(why).font(.v2Label).foregroundStyle(CSV2.warning)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
                    }
                    RowDividerV2()
                }
            }
            Text("\"\(proposal.transcript)\"").font(.v2Label).foregroundStyle(CSV2.secondary)
            HStack(spacing: 12) {
                Button("Repetir") { phase = .idle }
                    .font(.v2Body).foregroundStyle(CSV2.secondary).frame(maxWidth: .infinity, minHeight: CSV2.minTap)
                PrimaryButtonV2(title: "Anotar") {
                    let token = VoiceHolePipeline.apply(proposal, match: matchManager)
                    onApplied(proposal, token)
                    dismiss()
                }
            }
        }
    }

    // MARK: Grabar → transcribir → proponer

    private func start() {
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
                let proposal = try await VoiceHolePipeline.propose(transcript: text, match: matchManager)
                phase = .review(proposal)
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
