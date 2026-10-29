//
//  WatchModel.swift
//  El reloj solo graba, manda el audio y las órdenes, y pinta la tarjeta que le devuelve el iPhone.
//

import SwiftUI
import AVFoundation
import WatchConnectivity
import WatchKit

/// La bocina del reloj: dice la respuesta en español de México.
@MainActor
final class WatchSpeech {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        stop()
        // El micrófono deja la sesión en modo grabación: para hablar hace falta reproducción.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-MX") ?? AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}

@MainActor @Observable
final class WatchModel: NSObject, WCSessionDelegate {
    enum Phase: Equatable { case idle, recording, sending, failed(String) }

    var card = WatchCardDTO.empty
    /// La respuesta a la última pregunta (se ve hasta que se cierra o llega otra dictada).
    /// El reloj habla un brief corto ("Vas 3, 1 contra Rob, al hoyo 7"): no distrae. Se silencia con la clave `speakAnswers` = false.
    static var speaksAnswers: Bool { UserDefaults.standard.object(forKey: "speakAnswers") as? Bool ?? true }
    var answer: WatchAnswerDTO?
    var context: WatchContextDTO?
    var phase: Phase = .idle
    var reachable = false

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var revisionAtSend = -1
    /// El iPhone avisó que estaba procesando después de mandar el audio (así se sabe que la respuesta que llega es la de esta dictada).
    private var sawProcessing = false
    @ObservationIgnored private let speech = WatchSpeech()
    /// La última respuesta ya atendida: el contexto se repite en cada envío y no debe volver a hablar.
    private var seenAnswerId: String?
    private var timeout: Task<Void, Never>?
    private var staleProcessing: Task<Void, Never>?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // Audios viejos que no se llegaron a entregar no deben procesarse después.
        WCSession.default.outstandingFileTransfers.forEach { $0.cancel() }
        startPollingState()
    }

    /// Mientras no haya contexto del iPhone se vuelve a pedir cada pocos segundos; al llegar el ciclo termina (antes seguía
    /// despertando al reloj cada 4 s para nada). Se reactiva si el iPhone vuelve a ser alcanzable y aún no hay contexto.
    private var pollTask: Task<Void, Never>?
    private func startPollingState() {
        guard pollTask == nil, context == nil else { return }
        pollTask = Task { @MainActor in
            while !Task.isCancelled, self.context == nil {
                self.requestState()
                try? await Task.sleep(for: .seconds(4))
            }
            self.pollTask = nil
        }
    }

    // MARK: Lo que se ve

    /// Hay algo dictado por revisar (lo ya anotado de antes no cuenta).
    var hasDraft: Bool { card.rows.contains { $0.state == .ok || $0.state == .doubt } || !card.chips.isEmpty }
    var isWorking: Bool { phase == .sending || card.processing }

    // MARK: Grabar y mandar

    func startRecording() {
        guard phase != .recording else { return }
        speech.stop()
        // iOS cierra la app del iPhone si pasan ~15 min sin usarla: dictar NO se bloquea. Si el iPhone no está alcanzable el audio
        // se encola (transferFile) y la app lo procesa cuando despierte.
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                guard granted else { self.phase = .failed("Permiso de micrófono denegado. Actívalo en Ajustes del reloj."); return }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hoyo-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
                                           AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
            let r = try AVAudioRecorder(url: url, settings: settings)
            guard r.record() else { phase = .failed("No se pudo grabar."); return }
            recorder = r
            recordingURL = url
            phase = .recording
            WKInterfaceDevice.current().play(.start)
        } catch {
            phase = .failed("No se pudo grabar: \(error.localizedDescription)")
        }
    }

    func stopAndSend() {
        guard phase == .recording, let r = recorder, let url = recordingURL else { return }
        r.stop()
        recorder = nil
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        guard WCSession.default.activationState == .activated else { phase = .failed("El iPhone no está disponible."); return }
        revisionAtSend = card.revision
        sawProcessing = false
        phase = .sending
        sendAudio(url)
        WKInterfaceDevice.current().play(.stop)
        // Si el iPhone no contesta no se queda "Interpretando…" para siempre: 30 s sin señal, o 75 s si dijo que estaba procesando
        // (el iPhone corta su propio trabajo a los 45 s).
        timeout?.cancel()
        timeout = Task {
            try? await Task.sleep(for: .seconds(30))
            if self.card.processing { try? await Task.sleep(for: .seconds(45)) }
            guard !Task.isCancelled, self.phase == .sending else { return }
            self.card.processing = false
            self.phase = .failed(self.queuedWhileAsleep
                ? "Enviado. Se anota cuando el iPhone despierte; abre Caddie Score para acelerarlo."
                : "El iPhone no respondió. Abre Caddie Score en el iPhone y vuelve a dictar.")
            WKInterfaceDevice.current().play(.failure)
        }
    }

    /// Cierra la respuesta y calla la voz.
    func dismissAnswer() {
        speech.stop()
        answer = nil
    }

    /// Con el iPhone alcanzable el clip (unos cientos de KB) viaja como mensaje: llega al instante. `transferFile` es una cola
    /// que puede tardar minutos (y entre simuladores casi no entrega), así que solo es el respaldo.
    /// El último audio se mandó sin el iPhone alcanzable: queda en cola y se procesa cuando la app del iPhone despierte.
    private var queuedWhileAsleep = false

    private func sendAudio(_ url: URL) {
        let session = WCSession.default
        queuedWhileAsleep = !session.isReachable
        if session.isReachable, let data = try? Data(contentsOf: url), data.count < 1_000_000 {
            session.sendMessage([WatchKey.audioHole: data], replyHandler: nil) { _ in
                Task { @MainActor in WCSession.default.transferFile(url, metadata: nil) }
            }
        } else {
            session.transferFile(url, metadata: nil)
        }
    }

    func cancelRecording() {
        recorder?.stop()
        recorder = nil
        phase = .idle
    }

    // MARK: Órdenes

    func send(_ command: WatchCommand) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(command) else {
            phase = .failed("iPhone no disponible. Acércalo y abre la app.")
            return
        }
        if case .failed = phase { phase = .idle }   // un aviso viejo no se queda
        WCSession.default.sendMessageData(data, replyHandler: nil) { error in
            Task { @MainActor in self.phase = .failed("No llegó al iPhone: \(error.localizedDescription)") }
        }
        if command == .apply { WKInterfaceDevice.current().play(.success) }
    }

    func requestState() {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([:], replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        Task { @MainActor in
            self.reachable = session.isReachable
            self.absorb(ctx, fromLaunch: true)
            self.requestState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if session.isReachable { self.requestState(); self.startPollingState() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.absorb(applicationContext) }
    }

    /// `fromLaunch`: el contexto guardado de antes de abrir la app puede traer "procesando" de una dictada que ya terminó o murió;
    /// al abrir no se muestra. Durante la sesión, "procesando" caduca a los 60 s si el iPhone no manda nada más.
    private func absorb(_ ctx: [String: Any], fromLaunch: Bool = false) {
        let decoder = JSONDecoder()
        if let data = ctx[WatchKey.context] as? Data, let c = try? decoder.decode(WatchContextDTO.self, from: data) { context = c }
        if let data = ctx[WatchKey.answer] as? Data, let a = try? decoder.decode(WatchAnswerDTO.self, from: data) {
            // Una respuesta guardada de antes de abrir la app no se muestra ni se dice.
            if a.id != seenAnswerId {
                seenAnswerId = a.id
                if !fromLaunch {
                    answer = a
                    if Self.speaksAnswers, !a.spoken.isEmpty { speech.speak(a.spoken) }
                    WKInterfaceDevice.current().play(.success)
                }
            }
        } else if ctx[WatchKey.answer] == nil, !fromLaunch {
            answer = nil   // el iPhone ya la limpió (otra dictada)
        }
        if let data = ctx[WatchKey.card] as? Data, let c = try? decoder.decode(WatchCardDTO.self, from: data) {
            let previous = card
            var c = c
            if fromLaunch { c.processing = false }
            card = c
            staleProcessing?.cancel()
            if c.processing {
                staleProcessing = Task { [revision = c.revision] in
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled, self.card.revision == revision, self.card.processing else { return }
                    self.card.processing = false
                }
            }
            if phase == .sending, c.processing { sawProcessing = true }
            // Terminó la dictada: llegó otra revisión, o el iPhone ya había avisado "procesando" y ahora no (su revisión vuelve a 0 si se reabre).
            if phase == .sending, !c.processing, c.revision != revisionAtSend || sawProcessing { phase = .idle; timeout?.cancel() }
            if c.error != nil, !c.processing { phase = .idle; WKInterfaceDevice.current().play(.failure) }
            if previous.applied == nil, c.applied != nil { WKInterfaceDevice.current().play(.success) }
        }
    }
}
