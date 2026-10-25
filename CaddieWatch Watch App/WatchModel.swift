//
//  WatchModel.swift
//  El reloj solo graba, manda el audio y las órdenes, y pinta la tarjeta que le devuelve el iPhone.
//

import SwiftUI
import AVFoundation
import WatchConnectivity
import WatchKit

@MainActor @Observable
final class WatchModel: NSObject, WCSessionDelegate {
    enum Phase: Equatable { case idle, recording, sending, failed(String) }

    var card = WatchCardDTO.empty
    var context: WatchContextDTO?
    var phase: Phase = .idle
    var reachable = false

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var revisionAtSend = -1

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Lo que se ve

    var hasDraft: Bool { card.rows.contains { $0.state != .missing } || !card.chips.isEmpty }
    var isWorking: Bool { phase == .sending || card.processing }

    // MARK: Grabar y mandar

    func startRecording() {
        guard phase != .recording else { return }
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
        phase = .sending
        WCSession.default.transferFile(url, metadata: nil)
        WKInterfaceDevice.current().play(.stop)
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
            self.absorb(ctx)
            self.requestState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if session.isReachable { self.requestState() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.absorb(applicationContext) }
    }

    private func absorb(_ ctx: [String: Any]) {
        let decoder = JSONDecoder()
        if let data = ctx[WatchKey.context] as? Data, let c = try? decoder.decode(WatchContextDTO.self, from: data) { context = c }
        if let data = ctx[WatchKey.card] as? Data, let c = try? decoder.decode(WatchCardDTO.self, from: data) {
            let previous = card
            card = c
            if phase == .sending, c.revision != revisionAtSend, !c.processing { phase = .idle }
            if c.error != nil, !c.processing { phase = .idle; WKInterfaceDevice.current().play(.failure) }
            if previous.applied == nil, c.applied != nil { WKInterfaceDevice.current().play(.success) }
        }
    }
}
