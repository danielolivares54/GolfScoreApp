import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    static let appGroupId = "group.comDOG.Caddy-Score"
    static let pendingRecordFile = "pending_score.json"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        loadMatchMeta()
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Lee cualquier record que Siri haya dejado pendiente
        NotificationCenter.default.post(name: .siriRecordPending, object: nil)
    }

    // MARK: - Cargar configuración de la ronda

    private func loadMatchMeta() {
        guard let url = Bundle.main.url(forResource: "match_meta", withExtension: "json") else {
            print("❌ match_meta.json no encontrado en el bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            try SiriMatchManager.shared.loadMatch(from: data)
            print("✅ Match cargado correctamente")
            print("🏌️ Club: \(SiriMatchManager.shared.getClubName())")
            print("⛳ Hoyo inicial: \(SiriMatchManager.shared.getCurrentPhysicalHole() ?? 0)")
            print("👥 Jugadores: \(SiriMatchManager.shared.getPlayers())")
        } catch {
            print("❌ Error cargando match: \(error)")
        }
    }

    // MARK: - Leer record pendiente del App Group (escrito por Siri)

    static func readPendingRecord() -> GolfScoreRecord? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return nil }

        let fileURL = containerURL.appendingPathComponent(pendingRecordFile)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }

        return try? JSONDecoder().decode(GolfScoreRecord.self, from: data)
    }

    static func clearPendingRecord() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else { return }

        let fileURL = containerURL.appendingPathComponent(pendingRecordFile)
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension Notification.Name {
    static let siriRecordPending = Notification.Name("siriRecordPending")
}
