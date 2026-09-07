//  📌 Rol: Gestor de estado de la ronda.
//  🔍 Uso: Compartido entre la app principal y la extensión de Siri.
//  ⚠️ Nota: Se llama SiriMatchManager para evitar conflictos de compilación
//           entre targets que comparten el mismo módulo.
//  🔄 Si en el futuro la extensión Siri tiene su propio módulo,
//     se puede renombrar a MatchManager.

import Foundation

// MARK: - Modelos de Datos

struct MatchMeta: Codable {
    let matchId: String
    let club: Club
    let course: Course
    let players: [Player]
    let startingHole: Int
    let betType: String
    let createdAt: String
}

struct Club: Codable {
    let name: String
    let location: String
}

struct Course: Codable {
    let totalHoles: Int
    let holeOrder: [Int]
    let pars: [Int]
    let handicap: [Int]
}

struct Player: Codable {
    let name: String
    let position: Int
    let isUser: Bool
    let handicap: Int
}

// MARK: - Gestor de la Ronda (Compartido)

class SiriMatchManager {
    static let shared = SiriMatchManager()

    private var matchMeta: MatchMeta?
    private var currentPosition: Int = 0  // Índice en holeOrder

    // MARK: - Cargar Meta Datos

    func loadMatch(from jsonData: Data) throws {
        matchMeta = try JSONDecoder().decode(MatchMeta.self, from: jsonData)
        if let meta = matchMeta {
            currentPosition = meta.course.holeOrder.firstIndex(of: meta.startingHole) ?? 0
        }
    }

    // MARK: - Obtener Hoyo Físico Actual

    func getCurrentPhysicalHole() -> Int? {
        guard let meta = matchMeta else { return nil }
        guard currentPosition < meta.course.holeOrder.count else { return nil }
        return meta.course.holeOrder[currentPosition]
    }

    // MARK: - Obtener Par del Hoyo Actual

    func getCurrentPar() -> Int? {
        guard let meta = matchMeta else { return nil }
        guard let hole = getCurrentPhysicalHole() else { return nil }
        return meta.course.pars[hole - 1]
    }

    // MARK: - Obtener Handicap del Hoyo Actual

    func getCurrentHandicap() -> Int? {
        guard let meta = matchMeta else { return nil }
        guard let hole = getCurrentPhysicalHole() else { return nil }
        return meta.course.handicap[hole - 1]
    }

    // MARK: - Avanzar al Siguiente Hoyo

    func advanceHole() {
        guard let meta = matchMeta else { return }
        if currentPosition < meta.course.holeOrder.count - 1 {
            currentPosition += 1
            print("⛳ Siguiente hoyo físico: \(getCurrentPhysicalHole() ?? 0)")
        } else {
            print("🏌️ ¡Ronda completada!")
        }
    }

    // MARK: - Reiniciar Ronda

    func resetMatch() {
        guard let meta = matchMeta else { return }
        currentPosition = meta.course.holeOrder.firstIndex(of: meta.startingHole) ?? 0
    }

    // MARK: - Obtener Lista de Jugadores

    func getPlayers() -> [String] {
        return matchMeta?.players.map { $0.name } ?? []
    }

    // MARK: - Obtener el Jugador Usuario

    func getUserPlayer() -> String? {
        return matchMeta?.players.first(where: { $0.isUser })?.name
    }

    // MARK: - Obtener Nombre del Club

    func getClubName() -> String {
        return matchMeta?.club.name ?? "Club Desconocido"
    }
}
