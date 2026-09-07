import Foundation

class ScoreManager {
    static let shared = ScoreManager()

    private var scores: [String: [Int: GolfScoreRecord]] = [:]  // [Player: [Hole: Record]]
    private let fileName = "golf_scores.json"
    private let appGroupId = "group.comDOG.Caddy-Score"

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    // MARK: - Guardar un puntaje

    func saveScore(record: GolfScoreRecord) -> Bool {
        if scores[record.player] == nil {
            scores[record.player] = [:]
        }
        scores[record.player]?[record.hole] = record
        saveToDisk()
        return true
    }

    // MARK: - Editar un puntaje existente

    func editScore(player: String, hole: Int, newStrokes: Int, newPutts: Int, newPenalties: Int, newSpecialMark: SpecialMark) -> Bool {
        guard var existing = scores[player]?[hole] else { return false }

        let editEntry = EditHistoryEntry(
            previousStrokes: existing.strokes,
            previousPutts: existing.putts,
            previousPenalties: existing.penalties,
            timestamp: Date()
        )
        existing.editHistory.append(editEntry)

        existing.strokes = newStrokes
        existing.putts = newPutts
        existing.penalties = newPenalties
        existing.specialMark = newSpecialMark
        existing.isEdited = true

        scores[player]?[hole] = existing
        saveToDisk()
        return true
    }

    // MARK: - Obtener un puntaje específico

    func getScore(player: String, hole: Int) -> GolfScoreRecord? {
        return scores[player]?[hole]
    }

    // MARK: - Obtener todos los puntajes de un jugador

    func getScoresForPlayer(_ player: String) -> [GolfScoreRecord] {
        guard let playerScores = scores[player] else { return [] }
        return playerScores.values.sorted { $0.hole < $1.hole }
    }

    // MARK: - Calcular totales por jugador

    func calculateTotals(for player: String) -> PlayerTotals {
        var totalStrokes = 0
        var totalPutts = 0
        var totalPenalties = 0
        var birdies = 0, eagles = 0, pars = 0, bogeys = 0, doubleBogeys = 0

        guard let playerScores = scores[player] else {
            return PlayerTotals(player: player, totalStrokes: 0, totalPutts: 0, totalPenalties: 0,
                                birdies: 0, eagles: 0, pars: 0, bogeys: 0, doubleBogeys: 0, netScore: 0)
        }

        for (_, record) in playerScores {
            totalStrokes += record.strokes + record.penalties
            totalPutts += record.putts
            totalPenalties += record.penalties

            switch record.specialMark {
            case .birdie:      birdies += 1
            case .eagle:       eagles += 1
            case .par:         pars += 1
            case .bogey:       bogeys += 1
            case .doubleBogey: doubleBogeys += 1
            default: break
            }
        }

        let handicap = SiriMatchManager.shared.getPlayers().firstIndex(of: player) ?? 0

        return PlayerTotals(
            player: player,
            totalStrokes: totalStrokes,
            totalPutts: totalPutts,
            totalPenalties: totalPenalties,
            birdies: birdies,
            eagles: eagles,
            pars: pars,
            bogeys: bogeys,
            doubleBogeys: doubleBogeys,
            netScore: totalStrokes - handicap
        )
    }

    // MARK: - Contar marcas especiales por hoyo

    func getSpecialMarksCount(for hole: Int) -> Int {
        var count = 0
        for player in scores.keys {
            if let record = scores[player]?[hole], record.specialMark != .none {
                count += 1
            }
        }
        return count
    }

    // MARK: - Exportar todos los datos a JSON

    func exportAllScores() -> String? {
        let allData: [String: Any] = [
            "matchId": SiriMatchManager.shared.getClubName(),
            "date": Date().ISO8601Format(),
            "players": scores.map { player, holes in
                return [
                    "player": player,
                    "scores": holes.values.sorted { $0.hole < $1.hole }.map { record in
                        return [
                            "hole": record.hole,
                            "strokes": record.strokes,
                            "putts": record.putts,
                            "penalties": record.penalties,
                            "specialMark": record.specialMark.rawValue,
                            "isEdited": record.isEdited
                        ]
                    },
                    "totals": calculateTotals(for: player)
                ]
            }
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: allData, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("❌ Error exportando JSON: \(error)")
            return nil
        }
    }

    // MARK: - Guardar en disco

    private func saveToDisk() {
        guard let documentsURL = sharedContainerURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(scores)
            try data.write(to: fileURL)
            print("✅ Puntajes guardados en: \(fileURL)")
        } catch {
            print("❌ Error guardando puntajes: \(error)")
        }
    }

    // MARK: - Cargar desde disco

    func loadFromDisk() {
        guard let documentsURL = sharedContainerURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsURL.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            scores = try JSONDecoder().decode([String: [Int: GolfScoreRecord]].self, from: data)
            print("✅ Puntajes cargados desde disco")
        } catch {
            print("❌ Error cargando puntajes: \(error)")
        }
    }
}
