import Foundation

// MARK: - Marcas Especiales

enum SpecialMark: String, Codable {
    case eagle = "Eagle"
    case birdie = "Birdie"
    case par = "Par"
    case bogey = "Bogey"
    case doubleBogey = "Double Bogey"
    case none = "N/A"
}

// MARK: - Historial de Edición

struct EditHistoryEntry: Codable {
    let previousStrokes: Int
    let previousPutts: Int
    let previousPenalties: Int
    let timestamp: Date
}

// MARK: - Registro de Puntaje

struct GolfScoreRecord: Codable {
    let player: String
    let hole: Int
    var strokes: Int
    var putts: Int
    var penalties: Int
    var specialMark: SpecialMark
    var isEdited: Bool
    var editHistory: [EditHistoryEntry]
    let timestamp: Date

    init(player: String, hole: Int, strokes: Int, putts: Int = 0, penalties: Int = 0, specialMark: SpecialMark = .none) {
        self.player = player
        self.hole = hole
        self.strokes = strokes
        self.putts = putts
        self.penalties = penalties
        self.specialMark = specialMark
        self.isEdited = false
        self.editHistory = []
        self.timestamp = Date()
    }
}

// MARK: - Totales por Jugador

struct PlayerTotals: Codable {
    let player: String
    var totalStrokes: Int
    var totalPutts: Int
    var totalPenalties: Int
    var birdies: Int
    var eagles: Int
    var pars: Int
    var bogeys: Int
    var doubleBogeys: Int
    var netScore: Int
}
