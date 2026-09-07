import Foundation

// MARK: - Codable types for match_meta.json

struct MatchMeta: Codable {
    let matchId: String
    let club: MatchMetaClub
    let course: MatchMetaCourse
    let players: [MatchMetaPlayer]
    let startingHole: Int
    let betType: String
    let createdAt: String
}

struct MatchMetaClub: Codable {
    let name: String
    let location: String
}

struct MatchMetaCourse: Codable {
    let totalHoles: Int
    let holeOrder: [Int]
    let pars: [Int]
    let handicap: [Int]
}

struct MatchMetaPlayer: Codable {
    let name: String
    let position: Int
    let isUser: Bool
    let handicap: Int
}

// MARK: - Loader

enum MatchMetaLoader {
    /// Loads match_meta.json from the app bundle. Returns nil if missing or malformed.
    static func load(filename: String = "match_meta") -> MatchMeta? {
        guard
            let url = Bundle.main.url(forResource: filename, withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }

        let decoder = JSONDecoder()
        return try? decoder.decode(MatchMeta.self, from: data)
    }
}

// MARK: - MatchManager seeding extension
// Call matchManager.seed(from: meta) right after init() to replace fixture data.

extension MatchManager {
    func seed(from meta: MatchMeta) {
        // Players
        let names = meta.players
            .sorted { $0.position < $1.position }
            .map { $0.name }
        setPlayers(names: names)

        // Starting hole
        startHole = meta.startingHole

        // Course holes — build from meta pars + handicap in holeOrder sequence
        let metaHoles: [HoleModel] = meta.course.holeOrder.enumerated().compactMap { idx, holeNum in
            guard idx < meta.course.pars.count, idx < meta.course.handicap.count else { return nil }
            return HoleModel(number: holeNum, par: meta.course.pars[idx], si: meta.course.handicap[idx])
        }
        if !metaHoles.isEmpty {
            holes = metaHoles
        }

        objectWillChange.send()
    }
}
