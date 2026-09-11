import Foundation

class SiriMatchManager {
    static let shared = SiriMatchManager()

    private var matchId: String = ""
    private var clubName: String = ""
    private var players: [String] = []
    private var startingHole: Int = 1
    private var betType: String = ""

    // MARK: - Load match metadata from JSON

    func loadMatch(from data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        matchId = json?["matchId"] as? String ?? ""
        betType = json?["betType"] as? String ?? ""
        startingHole = json?["startingHole"] as? Int ?? 1

        if let club = json?["club"] as? [String: Any] {
            clubName = club["name"] as? String ?? ""
        }

        if let playerList = json?["players"] as? [[String: Any]] {
            players = playerList.compactMap { $0["name"] as? String }
        }
    }

    // MARK: - Accessors

    func getClubName() -> String { clubName.isEmpty ? "Club de Golf México" : clubName }
    func getPlayers() -> [String] {
        players.isEmpty ? ["Daniel", "Anselmo", "Roberto", "Ricardo", "Fernando"] : players
    }
    func getMatchId() -> String { matchId }
    func getStartingHole() -> Int { startingHole }
    func getBetType() -> String { betType }
}
