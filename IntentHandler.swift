import Intents

// Usamos SiriMatchManager en lugar de MatchManager para evitar conflicto de nombres con el target principal.
class IntentHandler: NSObject, LogGolfScoreIntentHandling {

    // MARK: - Resolver Jugador

    func resolvePlayer(for intent: LogGolfScoreIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let playerName = intent.player else {
            completion(.needsValue())
            return
            // MARK: - Escribir record pendiente al App Group para que la app lo confirme

    private func writePendingRecord(_ record: GolfScoreRecord) {
        let appGroupId = "group.comDOG.Caddy-Score"
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ),
        let data = try? JSONEncoder().encode(record) else { return }

        let fileURL = containerURL.appendingPathComponent("pending_score.json")
        try? data.write(to: fileURL)
    }
}

        let players = SiriMatchManager.shared.getPlayers()
        let matchedPlayer = players.first { $0.lowercased() == playerName.lowercased() }

        if let matched = matchedPlayer {
            completion(.success(with: matched))
        } else {
            completion(.disambiguation(with: players))
        }
    }

    // MARK: - Resolver Golpes

    func resolveStrokes(for intent: LogGolfScoreIntent, with completion: @escaping (LogGolfScoreStrokesResolutionResult) -> Void) {
        guard let strokes = intent.strokes else {
            completion(.needsValue())
            return
        }

        if (1...20).contains(strokes) {
            completion(.success(with: strokes))
        } else {
            completion(.unsupported(forReason: .outOfRange))
        }
    }

    // MARK: - Resolver Putts

    func resolvePutts(for intent: LogGolfScoreIntent, with completion: @escaping (LogGolfScorePuttsResolutionResult) -> Void) {
        guard let putts = intent.putts else {
            completion(.success(with: 0))
            return
        }

        if (0...10).contains(putts) {
            completion(.success(with: putts))
        } else {
            completion(.unsupported(forReason: .outOfRange))
        }
    }

    // MARK: - Resolver Penalidades

    func resolvePenalties(for intent: LogGolfScoreIntent, with completion: @escaping (LogGolfScorePenaltiesResolutionResult) -> Void) {
        guard let penalties = intent.penalties else {
            completion(.success(with: 0))
            return
        }

        if (0...10).contains(penalties) {
            completion(.success(with: penalties))
        } else {
            completion(.unsupported(forReason: .outOfRange))
        }
    }

    // MARK: - Confirmar

    func confirm(intent: LogGolfScoreIntent, completion: @escaping (LogGolfScoreIntentResponse) -> Void) {
        guard SiriMatchManager.shared.getCurrentPhysicalHole() != nil else {
            completion(.init(code: .failure, userActivity: nil))
            return
        }
        completion(.init(code: .ready, userActivity: nil))
    }

    // MARK: - Manejar el Comando

    func handle(intent: LogGolfScoreIntent, completion: @escaping (LogGolfScoreIntentResponse) -> Void) {
        guard let player = intent.player,
              let strokes = intent.strokes else {
            completion(.init(code: .failure, userActivity: nil))
            return
        }

        let putts = intent.putts ?? 0
        let penalties = intent.penalties ?? 0
        let specialMark = intent.specialMark ?? .none
        let hole = intent.hole ?? SiriMatchManager.shared.getCurrentPhysicalHole() ?? 0

        if intent.isEdit {
            let success = ScoreManager.shared.editScore(
                player: player,
                hole: hole,
                newStrokes: strokes,
                newPutts: putts,
                newPenalties: penalties,
                newSpecialMark: specialMark
            )

            let response = LogGolfScoreIntentResponse(code: success ? .success : .failure, userActivity: nil)
            response.player = player
            response.strokes = strokes
            response.hole = hole
            completion(response)

        } else {
            let record = GolfScoreRecord(
                player: player,
                hole: hole,
                strokes: strokes,
                putts: putts,
                penalties: penalties,
                specialMark: specialMark
            )

            let success = ScoreManager.shared.saveScore(record: record)
            writePendingRecord(record)  // App leerá esto al volver al foreground

            let response = LogGolfScoreIntentResponse(code: success ? .success : .failure, userActivity: nil)
            response.player = player
            response.strokes = strokes
            response.hole = hole
            completion(response)

            SiriMatchManager.shared.advanceHole()
        }
    }
}
