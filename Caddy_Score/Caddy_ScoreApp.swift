//
//  Caddy_ScoreApp.swift
//  Caddy_Score
//
//  Created by daniel olivares on 2/14/26.
//

import SwiftUI
import UIKit
import AppIntents

// MARK: - App Entry Point

@main
struct Caddy_ScoreApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - App Delegate

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
        NotificationCenter.default.post(name: .siriRecordPending, object: nil)
    }

    private func loadMatchMeta() {
        guard let url = Bundle.main.url(forResource: "match_meta", withExtension: "json") else {
            print("❌ match_meta.json no encontrado")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            try SiriMatchManager.shared.loadMatch(from: data)
            print("✅ Match cargado: \(SiriMatchManager.shared.getClubName())")
        } catch {
            print("❌ Error cargando match: \(error)")
        }
    }

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
        try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(pendingRecordFile))
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let siriRecordPending = Notification.Name("siriRecordPending")
}

// MARK: - App Intent: Log Golf Score

struct LogGolfScoreIntent: AppIntent {
    static var title: LocalizedStringResource = "Anotar puntaje de golf"
    static var description = IntentDescription("Registra el puntaje de un jugador en un hoyo específico")

    @Parameter(title: "Jugador", description: "Nombre del jugador")
    var player: String

    @Parameter(title: "Golpes", description: "Número de golpes")
    var strokes: Int

    @Parameter(title: "Putts", description: "Número de putts (opcional)", default: 0)
    var putts: Int

    @Parameter(title: "Penalidades", description: "Penalidades (opcional)", default: 0)
    var penalties: Int

    @Parameter(title: "Hoyo", description: "Número de hoyo (1-18)")
    var hole: Int

    @Parameter(title: "Es edición", description: "Si es una edición de un hoyo ya registrado", default: false)
    var isEdit: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (1...18).contains(hole) else {
            throw NSError(domain: "Caddy_Score", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "El hoyo debe estar entre 1 y 18"])
        }

        let players = SiriMatchManager.shared.getPlayers()
        guard players.contains(player) else {
            throw NSError(domain: "Caddy_Score", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Jugador '\(player)' no encontrado"])
        }

        let success: Bool
        if isEdit {
            success = ScoreManager.shared.editScore(
                player: player, hole: hole,
                newStrokes: strokes, newPutts: putts,
                newPenalties: penalties, newSpecialMark: .none
            )
        } else {
            let record = GolfScoreRecord(
                player: player, hole: hole,
                strokes: strokes, putts: putts,
                penalties: penalties, specialMark: .none
            )
            success = ScoreManager.shared.saveScore(record: record)
        }

        guard success else {
            throw NSError(domain: "Caddy_Score", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No se pudo guardar el puntaje"])
        }

        NotificationCenter.default.post(name: .siriRecordPending, object: nil)

        let dialog = isEdit
            ? "Actualizado: \(player), hoyo \(hole) ahora \(strokes) golpes"
            : "Anotado: \(player), \(strokes) golpes en el hoyo \(hole)"
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - App Shortcuts Provider

struct Caddy_ScoreAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogGolfScoreIntent(),
            phrases: [
                "Anotar golf en \(.applicationName)",
                "Registrar puntaje en \(.applicationName)",
                "Anotar hoyo en \(.applicationName)"
            ],
            shortTitle: "Anotar Golf",
            systemImageName: "figure.golf"
        )
    }
}

// MARK: - SpecialMark AppEnum

extension SpecialMark: CaseIterable {
    nonisolated public static var allCases: [SpecialMark] {
        [.eagle, .birdie, .par, .bogey, .doubleBogey, .none]
    }
}

extension SpecialMark: AppEnum {
    nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Marca Especial")
    }
    nonisolated static var caseDisplayRepresentations: [SpecialMark: DisplayRepresentation] {
        [
            .eagle:       "Eagle",
            .birdie:      "Birdie",
            .par:         "Par",
            .bogey:       "Bogey",
            .doubleBogey: "Double Bogey",
            .none:        "Ninguna"
        ]
    }
}
