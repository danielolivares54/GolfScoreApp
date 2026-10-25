//
//  WatchBridgeV2.swift
//  v2t · Watch: el transporte (WatchConnectivity) en el iPhone. Recibe el audio y las órdenes del reloj, se las
//  pasa a `WatchCardCoordinator` y devuelve la tarjeta por applicationContext (la última gana, no se acumulan).
//

import Foundation
import WatchConnectivity

final class WatchBridgeV2: NSObject, WCSessionDelegate {
    static let shared = WatchBridgeV2()

    @MainActor private var coordinator: WatchCardCoordinator?
    @MainActor private var match: MatchManager?
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
        coordinator = c
        session?.delegate = self
        session?.activate()
    }

    /// Manda al reloj la tarjeta y el hoyo en juego. Si el reloj no está disponible no pasa nada: la próxima vez llega lo último.
    @MainActor func push() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let coordinator, let match else { return }
        let encoder = JSONEncoder()
        guard let card = try? encoder.encode(coordinator.card()),
              let context = try? encoder.encode(coordinator.context(course: match.courseName)) else { return }
        try? session.updateApplicationContext([WatchKey.card: card, WatchKey.context: context])
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

    /// El reloj pide el estado actual (al abrirse).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler([:])
        Task { @MainActor in self.push() }
    }

    /// Órdenes: lápiz, goma, Anotar, Deshacer.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        replyHandler(Data())
        guard let command = try? JSONDecoder().decode(WatchCommand.self, from: messageData) else { return }
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
