//
//  WatchBridgeV2.swift
//  v2t · Watch: el transporte (WatchConnectivity) en el iPhone. Recibe el audio y las órdenes del reloj, se las
//  pasa a `WatchCardCoordinator` y devuelve la tarjeta por applicationContext (la última gana, no se acumulan).
//

import Foundation
import WatchConnectivity
import os

private let watchLog = Logger(subsystem: "comDOG.Caddy-Score", category: "watch")

final class WatchBridgeV2: NSObject, WCSessionDelegate {
    static let shared = WatchBridgeV2()

    @MainActor private var coordinator: WatchCardCoordinator?
    @MainActor private var match: MatchManager?
    /// Vigila el hoyo de la pantalla del iPhone: si lo cambias (flechas o deslizar), el reloj se entera.
    @MainActor private var holeObserver: Task<Void, Never>?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// Se llama una vez con el MatchManager de la app (el mismo de las vistas).
    @MainActor func start(match: MatchManager) {
        guard coordinator == nil else { return }
        self.match = match
        let c = WatchCardCoordinator(match: match, currentHole: { [weak match] in
            guard let match else { return 1 }
            let order = match.playOrder()
            let index = UserDefaults.standard.integer(forKey: AppKeys.currentHoleIndex)
            return order.indices.contains(index) ? order[index] : (order.first ?? 1)
        })
        c.onChange = { [weak self] in self?.push() }
        // Quien dicta dice el hoyo y el iPhone lo recibe: la pantalla se mueve a ese hoyo (el mismo índice que usa la pantalla del iPhone).
        // Pasar al hoyo siguiente es del iPhone; el reloj lo recibe de él.
        c.onHoleDictated = { [weak match] hole in
            guard let match, let index = match.playOrder().firstIndex(of: hole) else { return }
            watchLog.notice("se dictó el hoyo \(hole) → pantalla al índice \(index)")
            UserDefaults.standard.set(index, forKey: AppKeys.currentHoleIndex)
        }
        coordinator = c
        session?.delegate = self
        session?.activate()
        holeObserver = Task { @MainActor [weak self] in
            var last = UserDefaults.standard.integer(forKey: AppKeys.currentHoleIndex)
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                let now = UserDefaults.standard.integer(forKey: AppKeys.currentHoleIndex)
                guard now != last else { continue }
                watchLog.notice("el hoyo en pantalla cambió: índice \(last) → \(now)")
                last = now
                self?.push()
            }
        }
    }

    /// Manda al reloj la tarjeta y el hoyo en juego. Si el reloj no está disponible no pasa nada: la próxima vez llega lo último.
    @MainActor func push() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let coordinator, let match else { return }
        let encoder = JSONEncoder()
        guard let card = try? encoder.encode(coordinator.card()),
              let context = try? encoder.encode(coordinator.context(course: match.courseName)) else { return }
        var payload: [String: Any] = [WatchKey.card: card, WatchKey.context: context]
        if let answer = coordinator.answer, let data = try? encoder.encode(answer) { payload[WatchKey.answer] = data }
        try? session.updateApplicationContext(payload)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.push() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    /// El reloj pide el estado actual (al abrirse). WatchConnectivity entrega a una u otra versión según si el reloj
    /// pidió respuesta o no: hay que atender las dos.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let audio = message[WatchKey.audioHole] as? Data { receive(audio: audio); return }
        Task { @MainActor in self.push() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler([:])
        if let audio = message[WatchKey.audioHole] as? Data { receive(audio: audio); return }
        Task { @MainActor in self.push() }
    }

    /// Audio del hoyo que llegó como mensaje (el camino rápido): se guarda en un archivo y entra igual que el de `transferFile`.
    private func receive(audio: Data) {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).m4a")
        guard (try? audio.write(to: copy)) != nil else { return }
        Task { @MainActor in
            await self.coordinator?.receiveAudio(copy)
            try? FileManager.default.removeItem(at: copy)
        }
    }

    /// Órdenes: lápiz, goma, Anotar, Deshacer.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        handle(messageData)
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        replyHandler(Data())
        handle(messageData)
    }

    private func handle(_ data: Data) {
        guard let command = try? JSONDecoder().decode(WatchCommand.self, from: data) else { return }
        Task { @MainActor in self.coordinator?.handle(command) }
    }

    /// Audio del hoyo: el archivo se borra al salir de esta función, se copia antes.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).m4a")
        do { try FileManager.default.copyItem(at: file.fileURL, to: copy) } catch { return }
        Task { @MainActor in
            await self.coordinator?.receiveAudio(copy)
            try? FileManager.default.removeItem(at: copy)
        }
    }
}
