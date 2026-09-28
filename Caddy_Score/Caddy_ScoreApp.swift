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
        // Re-register Siri shortcuts on every launch so phrase changes take effect immediately
        Caddy_ScoreAppShortcuts.updateAppShortcutParameters()
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // If Siri set the guided-capture flag, relay it now that ContentView is active
        if UserDefaults.standard.bool(forKey: "pendingOpenRecorder") {
            UserDefaults.standard.removeObject(forKey: "pendingOpenRecorder")
            NotificationCenter.default.post(name: .openCaddyRecorder, object: nil)
        }
        NotificationCenter.default.post(name: .siriRecordPending, object: nil)
    }

    private func loadMatchMeta() {
        // Try bundle first (if file was added to resources), otherwise fall back to embedded default
        if let url = Bundle.main.url(forResource: "match_meta", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           (try? SiriMatchManager.shared.loadMatch(from: data)) != nil {
            print("✅ Match cargado desde bundle: \(SiriMatchManager.shared.getClubName())")
            return
        }
        // Embedded default — keeps the app working without bundle resource setup
        let embedded = """
        {
          "matchId": "2026-09-07-CGM-Match1",
          "club": { "name": "Club de Golf México", "location": "Ciudad de México" },
          "course": {
            "totalHoles": 18,
            "holeOrder": [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18],
            "pars": [4,5,3,4,3,5,4,4,4,4,5,4,4,3,4,3,4,4],
            "handicap": [13,3,17,1,15,5,9,7,6,4,10,14,16,8,18,2,12,12]
          },
          "players": [
            {"name":"Daniel","position":1,"isUser":true,"handicap":0},
            {"name":"Anselmo","position":2,"isUser":false,"handicap":0},
            {"name":"Roberto","position":3,"isUser":false,"handicap":0},
            {"name":"Ricardo","position":4,"isUser":false,"handicap":0},
            {"name":"Fernando","position":5,"isUser":false,"handicap":0}
          ],
          "startingHole": 1,
          "betType": "VPCM",
          "createdAt": "2026-09-07T10:00:00Z"
        }
        """
        if let data = embedded.data(using: .utf8),
           (try? SiriMatchManager.shared.loadMatch(from: data)) != nil {
            print("✅ Match cargado desde embedded: \(SiriMatchManager.shared.getClubName())")
        }
    }

    static var pendingFileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(pendingRecordFile)
    }

    static func readPendingRecord() -> GolfScoreRecord? {
        guard let fileURL = pendingFileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(GolfScoreRecord.self, from: data)
    }

    static func clearPendingRecord() {
        guard let fileURL = pendingFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let siriRecordPending  = Notification.Name("siriRecordPending")
    static let openCaddyRecorder  = Notification.Name("openCaddyRecorder")
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
        let matchedPlayer = players.first { $0.lowercased() == player.lowercased() }
        guard let resolvedPlayer = matchedPlayer else {
            throw NSError(domain: "Caddy_Score", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Jugador '\(player)' no reconocido. Jugadores: \(players.joined(separator: ", "))"])
        }

        let record = GolfScoreRecord(
            player: resolvedPlayer, hole: hole,
            strokes: strokes, putts: putts,
            penalties: penalties, specialMark: .none
        )

        let success: Bool
        if isEdit {
            success = ScoreManager.shared.editScore(
                player: resolvedPlayer, hole: hole,
                newStrokes: strokes, newPutts: putts,
                newPenalties: penalties, newSpecialMark: .none
            )
        } else {
            success = ScoreManager.shared.saveScore(record: record)
        }

        guard success else {
            throw NSError(domain: "Caddy_Score", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No se pudo guardar el puntaje"])
        }

        // Write to pending_score.json in Documents so ContentView/MatchManager can pick it up
        if let fileURL = AppDelegate.pendingFileURL,
           let data = try? JSONEncoder().encode(record) {
            try? data.write(to: fileURL)
        }

        NotificationCenter.default.post(name: .siriRecordPending, object: nil)

        // Build context-aware dialog
        let allScores = ScoreManager.shared.allRecords()
        let holesDone = Set(allScores.map { $0.hole }).sorted()
        let missingPlayers = players.filter { p in
            ScoreManager.shared.getScore(player: p, hole: hole) == nil
        }

        var dialog = isEdit
            ? "Listo. \(resolvedPlayer), hoyo \(hole) actualizado a \(strokes) golpes."
            : "Anotado. \(resolvedPlayer), \(strokes) golpes en el hoyo \(hole)."

        if !missingPlayers.isEmpty {
            dialog += " Faltan: \(missingPlayers.joined(separator: ", "))."
        }
        if let nextHole = (1...18).first(where: { !holesDone.contains($0) }) {
            dialog += " Siguiente: hoyo \(nextHole)."
        }

        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Intent: abrir grabación de voz (sin parámetros)

struct CaddyRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Golf Caddy"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(true, forKey: "pendingOpenRecorder")
        NotificationCenter.default.post(name: .openCaddyRecorder, object: nil)
        return .result(dialog: "Abriendo Golf Caddy")
    }
}

// MARK: - App Shortcuts Provider

struct Caddy_ScoreAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaddyRecordIntent(),
            phrases: [
                "Golf \(.applicationName)",
                "\(.applicationName) Golf",
                "Anotar \(.applicationName)",
                "Dictar \(.applicationName)"
            ],
            shortTitle: "Golf Caddy",
            systemImageName: "mic.fill"
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
