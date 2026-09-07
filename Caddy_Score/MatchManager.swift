//
//  MatchManager.swift
//  Caddy_Score
//
//  Created by daniel olivares on 2/14/26.
//

import Foundation
import Combine

struct PlayerModel: Identifiable {
    let id = UUID()
    let alias: String
    let name: String
    var strokesVsBase: Double
    var scores: [Int: (gross: Int, putts: Int?)] = [:]
}

struct HoleModel {
    let number: Int
    let par: Int
    let si: Int
}

struct CourseModel {
    let id: String
    let name: String
    let holes: [HoleModel]
}

struct LaneModel: Identifiable {
    let id: UUID
    let base: [String]
    let opp: [String]
    var strokes: Double
    var strokeCarrier: String?
}

enum BetType: String, CaseIterable {
    case individual
    case parejas
}

enum BetMode: String, CaseIterable {
    case calculado
    case manual
}

enum PuttsBetMode: String, CaseIterable {
    case hole18 = "H18"
    case byRound = "Vuelta"
}

struct BetDefinition: Identifiable {
    let id = UUID()
    let tag: String
    let name: String
    let type: BetType
    let mode: BetMode
    let units: Int
    let description: String
}

struct ActiveBet: Identifiable {
    let id = UUID()
    let definition: BetDefinition
    var tagOverride: String?
}

struct IndividualZoomRow: Identifiable {
    let id = UUID()
    let hole: Int
    let par: Int
    let si: Int
    let yoGross: Int
    let yoStrokes: Double
    let yoNet: Double
    let oppAlias: String
    let oppGross: Int
    let oppStrokes: Double
    let oppNet: Double
    let result: Int
    let vueltaAccum: Int
    let matchAccum: Int
    let openPressures: [Int]
    let yoPuttsAccum: Int
    let oppPuttsAccum: Int
    let totalPuttsAccum: Int
}

struct PairBallLine {
    let alias: String
    let gross: Int
    let individualStrokes: Double
    let laneStrokes: Double
    let net: Double
}

struct PairZoomRow: Identifiable {
    let id = UUID()
    let hole: Int
    let par: Int
    let si: Int
    let basePlayers: [PairBallLine]
    let oppPlayers: [PairBallLine]
    let carrierAlias: String?
    let result: Int
    let vueltaAccum: Int
    let matchAccum: Int
    let openPressures: [Int]
}

struct UnitEvent: Identifiable {
    let id = UUID()
    let hole: Int
    let alias: String
    let code: String
    let units: Int
    let note: String?
}

struct UnitLogEntry: Identifiable {
    let id = UUID()
    let hole: Int
    let player: String
    let type: String
    let scope: BetType
    let vs: String?
    let units: Int
    let detail: String?
}

enum BetScopeTag: String, Codable, CaseIterable {
    case individual = "INDIVIDUAL"
    case twosome = "TWOSOME"
    case both = "BOTH"
}

enum BetMomentTag: String, Codable, CaseIterable {
    case f9 = "F9"
    case b9 = "B9"
    case h18 = "18H"
}

enum BetInputType: String, Codable, CaseIterable {
    case calculated = "CALCULATED"
    case input = "INPUT"
    case hybrid = "HYBRID"
}

enum BetSettlementRule: String, Codable, CaseIterable {
    case unitary = "UNITARY"
    case difference = "DIFFERENCE"
    case countNonZero = "COUNT_NON_ZERO"
}

enum BetValueRule: String, Codable, CaseIterable {
    case fixed = "FIXED"
    case byProfile = "BY_PROFILE"
    case multiplier = "MULTIPLIER"
}

struct BetCatalogV2Entry: Identifiable, Codable {
    let id = UUID()
    let betId: String
    let name: String
    let scope: BetScopeTag
    let moment: BetMomentTag
    let inputType: BetInputType
    let settlement: BetSettlementRule
    let valueRule: BetValueRule
    let baseValue: Int
    let multiplier: Double
    let enabled: Bool
    let dependsOn: [String]
}

enum BetInstanceScope: String, Codable {
    case individual = "IND"
    case twosome = "TWO"
}

struct BetInstance: Identifiable, Codable {
    let id: UUID
    let scope: BetInstanceScope
    let opponentId: String
    let userSide: [String]
    let oppSide: [String]
    let catalogBetIds: [String]
}

struct WalletLine: Identifiable {
    let id = UUID()
    let label: String
    let scope: BetType
    let opponentAlias: String?
    let laneId: UUID?
    let activationSummary: String
    let vueltaPoints: Int
    let presionPoints: Int
    let carryPoints: Int
    let carryActive: Bool
    let matchPoints: Int
    let unitsPoints: Int
    let vueltaMoney: Int
    let presionMoney: Int
    let carryMoney: Int
    let matchMoney: Int
    let unitsMoney: Int
    let totalMoney: Int
}

struct WalletSnapshot {
    let lines: [WalletLine]
    let totalMoney: Int
}

struct MatchBetSwitches: Codable {
    var vuelta: Bool = true
    var presion: Bool = true
    var carry: Bool = true
    var match: Bool = true
    var units: Bool = true

    var summary: String {
        var out: [String] = []
        if vuelta { out.append("V") }
        if presion { out.append("P") }
        if carry { out.append("C") }
        if match { out.append("M") }
        if units { out.append("U") }
        return out.isEmpty ? "—" : out.joined(separator: " ")
    }
}

enum CourseCatalog {
    static let cgm: CourseModel = {
        let pars = [4, 5, 3, 4, 3, 5, 4, 4, 4, 4, 5, 4, 4, 3, 4, 3, 5, 4]
        let sis = [13, 3, 17, 1, 15, 5, 11, 9, 7, 6, 4, 10, 18, 16, 8, 14, 2, 12]
        let holes = (1...18).map { HoleModel(number: $0, par: pars[$0 - 1], si: sis[$0 - 1]) }
        return CourseModel(id: "CGM", name: "CGM", holes: holes)
    }()

    static var `default`: CourseModel { cgm }
    static var all: [CourseModel] { [cgm] }
}

class MatchManager: ObservableObject {
    @Published var roundId = ""
    @Published var dateString = ""
    @Published var gameStartTime: Date = Date()
    @Published var startHole = 10
    @Published var courseId = ""
    @Published var courseName = ""
    @Published var players: [PlayerModel] = []
    @Published var holes: [HoleModel] = []
    @Published var lanes: [LaneModel] = []
    @Published var yoAlias = "DAN"
    @Published var baseTeamAliases: [String] = []
    @Published var betCatalog: [BetDefinition] = []
    @Published var activeBets: [ActiveBet] = []
    @Published var betCatalogV2: [BetCatalogV2Entry] = []
    @Published var betInstances: [BetInstance] = []
    @Published var vueltaValue: Int = 0
    @Published var presionValue: Int = 0
    @Published var matchValue: Int = 0
    @Published var unitValue: Int = 0
    @Published var puttsBetMode: PuttsBetMode = .hole18
    @Published var puttsBetUnits: Int = 2
    @Published var individualBetSwitchesByOpponent: [String: MatchBetSwitches] = [:]
    @Published var pairBetSwitchesByLane: [UUID: MatchBetSwitches] = [:]
    // Carry en B9 por matchup individual (oponente -> alias que lo solicitó).
    @Published var individualCarryRequesterByOpponent: [String: String] = [:]
    @Published var individualCarryStartHoleByOpponent: [String: Int] = [:]
    // Carry en B9 por pareja (laneId -> alias que lo solicitó).
    @Published var pairCarryRequesterByLane: [UUID: String] = [:]
    @Published var pairCarryStartHoleByLane: [UUID: Int] = [:]
    // Diccionario de sinonimos por alias para robustecer V2T de nombres propios.
    @Published var aliasSynonyms: [String: Set<String>] = [:]
    // OYES rank capturado por hoyo (solo par 3), por alias.
    @Published var oyesRanksByHole: [Int: [String: Int]] = [:]
    // Historial de valor por hoyo para soportar cambios entre F9/B9.
    @Published var oyesIndividualUnitByHole: [Int: Int] = [:]
    @Published var oyesPairUnitByHole: [Int: Int] = [:]
    // Unidades manuales por hoyo (ej. SANDY PAR, BIRDIE, etc.).
    @Published var unitEventsByHole: [Int: [UnitEvent]] = [:]
    
    init() {
        generateRoundId()
        setupDefaultPlayers()
        setupDefaultCourse()
        setupDefaultBets()
        setupDefaultBetCatalogV2()
        seedDefaultAliasSynonyms()
        loadExcelFixtureM5()
        rebuildBetInstances()
    }
    
    func generateRoundId() {
        gameStartTime = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        roundId = "R\(formatter.string(from: Date()))"
        
        formatter.dateFormat = "yyyy-MM-dd"
        dateString = formatter.string(from: Date())
    }
    
    func setupDefaultPlayers() {
        players = [
            PlayerModel(alias: "DAN", name: "Daniel", strokesVsBase: 0)
        ]
    }

    func setPlayers(names: [String], preserveScores: Bool = false) {
        let oldPlayers = players
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty { return }
        var newPlayers: [PlayerModel] = []
        for name in cleaned.prefix(5) {
            let alias = suggestAliasForList(name: name, existing: newPlayers.map { $0.alias })
            if alias.isEmpty { continue }
            var player = PlayerModel(alias: alias, name: name, strokesVsBase: 0)
            if preserveScores {
                let newKey = normalizePlayerKey(name)
                if let old = oldPlayers.first(where: { normalizePlayerKey($0.name) == newKey || $0.alias == alias }) {
                    player.scores = old.scores
                    player.strokesVsBase = old.strokesVsBase
                }
            }
            newPlayers.append(player)
        }
        guard !newPlayers.isEmpty else { return }
        players = newPlayers
        yoAlias = newPlayers[0].alias
        seedDefaultAliasSynonyms()
        onPlayersChanged(resetExistingScores: !preserveScores)
        objectWillChange.send()
    }

    func addPlayer(name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return false }
        if players.count >= 5 { return false }
        let alias = suggestAlias(for: clean)
        if alias.isEmpty { return false }
        players.append(PlayerModel(alias: alias, name: clean, strokesVsBase: 0))
        seedDefaultAliasSynonyms()
        onPlayersChanged()
        objectWillChange.send()
        return true
    }

    func removePlayers(at offsets: IndexSet) {
        for idx in offsets.sorted(by: >) {
            if idx < players.count {
                if players[idx].alias == yoAlias { continue }
                players.remove(at: idx)
            }
        }
        onPlayersChanged()
        objectWillChange.send()
    }

    func suggestAlias(for name: String) -> String {
        let letters = name.uppercased().filter { $0.isLetter }
        if letters.isEmpty { return "" }
        let base = String(letters.prefix(3))
        var alias = base
        var counter = 1
        while players.contains(where: { $0.alias == alias }) {
            alias = base + String(counter)
            counter += 1
        }
        return alias
    }

    private func suggestAliasForList(name: String, existing: [String]) -> String {
        let letters = name.uppercased().filter { $0.isLetter }
        if letters.isEmpty { return "" }
        let base = String(letters.prefix(3))
        var alias = base
        var counter = 1
        while existing.contains(alias) {
            alias = base + String(counter)
            counter += 1
        }
        return alias
    }
    
    func setupDefaultCourse() {
        let course = CourseCatalog.default
        courseId = course.id
        courseName = course.name
        holes = course.holes
    }

    func setupDefaultBets() {
        betCatalog = [
            BetDefinition(tag: "BIRD", name: "Birdie", type: .individual, mode: .calculado, units: 1, description: "Par - 1"),
            BetDefinition(tag: "EAG", name: "Águila", type: .individual, mode: .calculado, units: 2, description: "Par - 2"),
            BetDefinition(tag: "ALB", name: "Albatros", type: .individual, mode: .calculado, units: 3, description: "Par - 3"),
            BetDefinition(tag: "HIO", name: "Hole in One", type: .individual, mode: .calculado, units: 100, description: "Ace"),
            BetDefinition(tag: "B18", name: "Birdie en 18", type: .individual, mode: .calculado, units: 2, description: "Birdie en hoyo 18"),
            BetDefinition(tag: "3P", name: "3 Putt", type: .individual, mode: .manual, units: 1, description: "Manual"),
            BetDefinition(tag: "HO", name: "Hole Out", type: .individual, mode: .manual, units: 1, description: "Manual"),
            BetDefinition(tag: "OYES", name: "Oyes Rank", type: .individual, mode: .manual, units: 1, description: "Ranking par 3"),
            BetDefinition(tag: "PAIR", name: "Match Parejas", type: .parejas, mode: .manual, units: 1, description: "Manual"),
            BetDefinition(tag: "OYESP", name: "Oyes Rank Parejas", type: .parejas, mode: .manual, units: 1, description: "Ranking par 3 (parejas)")
        ]
    }

    // Paso 1: SSOT inicial de apuestas por scope/moment/type.
    func setupDefaultBetCatalogV2() {
        betCatalogV2 = [
            BetCatalogV2Entry(
                betId: "VTA_F9",
                name: "Vuelta F9",
                scope: .both,
                moment: .f9,
                inputType: .calculated,
                settlement: .unitary,
                valueRule: .byProfile,
                baseValue: 1,
                multiplier: 1.0,
                enabled: true,
                dependsOn: []
            ),
            BetCatalogV2Entry(
                betId: "VTA_B9",
                name: "Vuelta B9",
                scope: .both,
                moment: .b9,
                inputType: .calculated,
                settlement: .unitary,
                valueRule: .byProfile,
                baseValue: 1,
                multiplier: 1.0,
                enabled: true,
                dependsOn: []
            ),
            BetCatalogV2Entry(
                betId: "PRS_F9",
                name: "Presión F9",
                scope: .both,
                moment: .f9,
                inputType: .calculated,
                settlement: .countNonZero,
                valueRule: .byProfile,
                baseValue: 1,
                multiplier: 1.0,
                enabled: true,
                dependsOn: []
            ),
            BetCatalogV2Entry(
                betId: "PRS_B9",
                name: "Presión B9",
                scope: .both,
                moment: .b9,
                inputType: .calculated,
                settlement: .countNonZero,
                valueRule: .byProfile,
                baseValue: 1,
                multiplier: 1.0,
                enabled: true,
                dependsOn: []
            ),
            BetCatalogV2Entry(
                betId: "MATCH_18H",
                name: "Match 18H",
                scope: .both,
                moment: .h18,
                inputType: .calculated,
                settlement: .unitary,
                valueRule: .byProfile,
                baseValue: 1,
                multiplier: 1.0,
                enabled: true,
                dependsOn: []
            ),
            BetCatalogV2Entry(
                betId: "CARRY_B9",
                name: "Carry B9",
                scope: .both,
                moment: .b9,
                inputType: .hybrid,
                settlement: .difference,
                valueRule: .byProfile,
                baseValue: 1,
                multiplier: 1.0,
                enabled: true,
                dependsOn: ["VTA_F9"]
            ),
            BetCatalogV2Entry(
                betId: "OYES_18H",
                name: "Oyes 18H",
                scope: .both,
                moment: .h18,
                inputType: .input,
                settlement: .difference,
                valueRule: .fixed,
                baseValue: 1,
                multiplier: 1.0,
                enabled: true,
                dependsOn: []
            ),
            BetCatalogV2Entry(
                betId: "SANDY_18H",
                name: "Sandy 18H",
                scope: .both,
                moment: .h18,
                inputType: .input,
                settlement: .difference,
                valueRule: .fixed,
                baseValue: 1,
                multiplier: 1.0,
                enabled: true,
                dependsOn: []
            )
        ]
    }

    // Fixture de prueba cargado desde Caddy _scores-v2t.xlsx (Sheet1)
    private func loadExcelFixtureM5() {
        gameStartTime = Date()
        roundId = "M5"
        dateString = "2026-03-20"
        let course = CourseCatalog.default
        courseId = course.id
        courseName = course.name
        holes = course.holes
        startHole = 1

        var seeded: [PlayerModel] = [
            PlayerModel(alias: "DAN", name: "DAN", strokesVsBase: 0),
            PlayerModel(alias: "ANS", name: "ANS", strokesVsBase: 0),
            PlayerModel(alias: "ROB", name: "ROB", strokesVsBase: 8),
            PlayerModel(alias: "RIC", name: "RIC", strokesVsBase: 10),
            PlayerModel(alias: "DOA", name: "DOA", strokesVsBase: 0)
        ]

        let rows: [(hole: Int, values: [(gross: Int, putts: Int)])] = [
            (1,  [(4,2),(4,1),(6,2),(5,2),(4,1)]),
            (2,  [(5,2),(5,2),(5,1),(6,2),(4,2)]),
            (3,  [(4,1),(3,1),(4,2),(5,2),(3,1)]),
            (4,  [(5,2),(5,2),(6,2),(4,1),(5,2)]),
            (5,  [(4,1),(4,2),(5,2),(4,1),(3,1)]),
            (6,  [(6,3),(5,2),(7,2),(6,2),(5,2)]),
            (7,  [(3,1),(4,2),(3,1),(4,2),(3,1)]),
            (8,  [(4,2),(4,1),(5,2),(5,2),(4,2)]),
            (9,  [(5,2),(4,2),(6,2),(5,1),(4,2)]),
            (10, [(4,1),(5,2),(4,1),(5,2),(4,1)]),
            (11, [(5,2),(4,1),(5,2),(6,2),(5,2)]),
            (12, [(3,1),(3,1),(4,2),(3,1),(4,2)]),
            (13, [(6,2),(5,2),(6,2),(5,2),(6,2)]),
            (14, [(4,1),(4,2),(5,2),(4,1),(4,1)]),
            (15, [(5,2),(4,1),(5,2),(5,2),(4,1)]),
            (16, [(4,2),(5,2),(4,1),(4,2),(5,2)]),
            (17, [(3,1),(3,1),(4,2),(3,1),(3,1)]),
            (18, [(5,2),(4,2),(5,2),(5,2),(4,2)])
        ]

        for row in rows {
            for playerIndex in 0..<seeded.count {
                let score = row.values[playerIndex]
                seeded[playerIndex].scores[row.hole] = (gross: score.gross, putts: score.putts)
            }
        }

        players = seeded
        yoAlias = "DAN"
        baseTeamAliases = ["DAN", "ANS"]
        rebuildLanesFromBase()
        // Escenario fijo de prueba pedido:
        // DAN+ANS vs ROB+RIC, strokes de pareja 3 y los lleva ANS.
        setLaneStrokesForMatch(base: ["DAN", "ANS"], opp: ["ROB", "RIC"], value: 3)
        setLaneCarrierForMatch(base: ["DAN", "ANS"], opp: ["ROB", "RIC"], carrier: "ANS")
        addUnitEvent(hole: 3, alias: "DAN", code: "SANDY_PAR", units: 1, note: "Sandy par")
        // Escenario OYES de prueba (histórico por hoyo).
        setOyesRanks(
            hole: 3,
            ranksByAlias: ["DAN": 1, "ROB": 2, "ANS": 3, "RIC": 4, "DOA": 5],
            individualUnit: 1,
            pairUnit: 1
        )
        setOyesRanks(
            hole: 5,
            ranksByAlias: ["ROB": 1, "DAN": 2, "DOA": 3, "RIC": 4, "ANS": 5],
            individualUnit: 1,
            pairUnit: 1
        )
        vueltaValue = 50
        presionValue = 50
        matchValue = 50
        unitValue = 25
    }

    func setVueltaValue(_ value: Int) {
        vueltaValue = max(0, value)
        unitValue = max(0, value / 2)
        objectWillChange.send()
    }

    func setUnitValue(_ value: Int) {
        unitValue = max(0, value)
        objectWillChange.send()
    }

    func setApuestaValues(vuelta: Int, presion: Int, match: Int) {
        vueltaValue = max(0, vuelta)
        presionValue = max(0, presion)
        matchValue = max(0, match)
        objectWillChange.send()
    }

    func setPuttsBet(mode: PuttsBetMode, units: Int) {
        puttsBetMode = mode
        puttsBetUnits = max(0, units)
        objectWillChange.send()
    }

    func setActiveBets(_ bets: [ActiveBet]) {
        activeBets = bets
        objectWillChange.send()
    }

    // Paso 2: Instancias por matchup activo.
    func rebuildBetInstances() {
        var instances: [BetInstance] = []
        let individualBetIds = betCatalogV2
            .filter { $0.enabled && ($0.scope == .individual || $0.scope == .both) }
            .map { $0.betId }
        let twosomeBetIds = betCatalogV2
            .filter { $0.enabled && ($0.scope == .twosome || $0.scope == .both) }
            .map { $0.betId }

        let opps = players.map(\.alias).filter { $0 != yoAlias }
        for opp in opps {
            instances.append(
                BetInstance(
                    id: UUID(),
                    scope: .individual,
                    opponentId: "IND-\(yoAlias)-\(opp)",
                    userSide: [yoAlias],
                    oppSide: [opp],
                    catalogBetIds: individualBetIds
                )
            )
        }

        for lane in lanes.prefix(3) {
            let baseLabel = lane.base.joined(separator: "+")
            let oppLabel = lane.opp.joined(separator: "+")
            instances.append(
                BetInstance(
                    id: lane.id,
                    scope: .twosome,
                    opponentId: "TWO-\(baseLabel)-vs-\(oppLabel)",
                    userSide: lane.base,
                    oppSide: lane.opp,
                    catalogBetIds: twosomeBetIds
                )
            )
        }

        betInstances = instances
    }

    func setOyesRanks(hole: Int, ranksByAlias: [String: Int], individualUnit: Int? = nil, pairUnit: Int? = nil) {
        guard let h = getHole(hole), h.par == 3 else { return }
        var cleaned: [String: Int] = [:]
        for (alias, rank) in ranksByAlias {
            guard players.contains(where: { $0.alias == alias }) else { continue }
            guard rank > 0 else { continue }
            cleaned[alias] = rank
        }
        guard !cleaned.isEmpty else { return }
        oyesRanksByHole[hole] = cleaned
        if let u = individualUnit, u > 0 {
            oyesIndividualUnitByHole[hole] = u
        }
        if let u = pairUnit, u > 0 {
            oyesPairUnitByHole[hole] = u
        }
        objectWillChange.send()
    }

    func addUnitEvent(hole: Int, alias: String, code: String, units: Int = 1, note: String? = nil) {
        guard (1...18).contains(hole),
              players.contains(where: { $0.alias == alias }) else { return }
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCode.isEmpty else { return }
        let event = UnitEvent(hole: hole, alias: alias, code: cleanCode, units: units, note: note)
        unitEventsByHole[hole, default: []].append(event)
        objectWillChange.send()
    }

    func upsertUnitEvent(hole: Int, alias: String, code: String, units: Int = 1, note: String? = nil) {
        guard (1...18).contains(hole),
              players.contains(where: { $0.alias == alias }) else { return }
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCode.isEmpty else { return }
        var events = unitEventsByHole[hole] ?? []
        if let idx = events.firstIndex(where: { $0.alias == alias && $0.code == cleanCode }) {
            events.remove(at: idx)
        }
        events.append(UnitEvent(hole: hole, alias: alias, code: cleanCode, units: units, note: note))
        unitEventsByHole[hole] = events
        objectWillChange.send()
    }

    func unitEventsForZoom(segmentOverride: String? = nil) -> [UnitEvent] {
        let holes = Set(zoomHolesForCurrentRound(segmentOverride: segmentOverride))
        if holes.isEmpty { return [] }
        let manual = unitEventsByHole
            .filter { holes.contains($0.key) }
            .flatMap { $0.value }
        let calculated = holes.flatMap { calculatedUnitEventsForHole($0) }
        return (manual + calculated)
            .sorted { a, b in
                if a.hole == b.hole { return a.alias < b.alias }
                return a.hole < b.hole
            }
    }

    func unitCountForHole(_ hole: Int) -> Int {
        (unitEventsByHole[hole]?.count ?? 0) + calculatedUnitEventsForHole(hole).count
    }

    func unitNetForAlias(_ alias: String, segmentOverride: String? = nil) -> Int {
        unitEventsForZoom(segmentOverride: segmentOverride)
            .filter { $0.alias == alias }
            .reduce(0) { $0 + $1.units }
    }

    func unitLogEntriesForZoom(segmentOverride: String? = nil, includeIndividual: Bool = true, includePair: Bool = true) -> [UnitLogEntry] {
        let holes = zoomHolesForCurrentRound(segmentOverride: segmentOverride)
        if holes.isEmpty { return [] }
        var out: [UnitLogEntry] = []
        let directEvents = unitEventsForZoom(segmentOverride: segmentOverride)

        if includeIndividual {
            // Captura explícita del orden OYES en pares 3 para auditoría.
            for hole in holes {
                guard getHole(hole)?.par == 3,
                      let ranks = oyesRanksByHole[hole],
                      !ranks.isEmpty else { continue }
                let order = ranks
                    .sorted { $0.value < $1.value }
                    .map { "\($0.key) \($0.value)" }
                    .joined(separator: " · ")
                out.append(
                    UnitLogEntry(
                        hole: hole,
                        player: "OYES",
                        type: "OYES_ORDEN",
                        scope: .individual,
                        vs: nil,
                        units: 0,
                        detail: order
                    )
                )
            }

            // Unidades de campo sin valor (ej. 3P/4P) se reportan en el log.
            for e in directEvents where e.units == 0 {
                out.append(
                    UnitLogEntry(
                        hole: e.hole,
                        player: e.alias,
                        type: e.code,
                        scope: .individual,
                        vs: nil,
                        units: 0,
                        detail: e.note
                    )
                )
            }

            // Unidades con valor se aplican contra cada rival de YO.
            let opps = players.map(\.alias).filter { $0 != yoAlias }
            for e in directEvents where e.units != 0 {
                for opp in opps {
                    let delta: Int
                    if e.alias == yoAlias {
                        delta = e.units
                    } else if e.alias == opp {
                        delta = -e.units
                    } else {
                        delta = 0
                    }
                    guard delta != 0 else { continue }
                    out.append(
                        UnitLogEntry(
                            hole: e.hole,
                            player: yoAlias,
                            type: e.code,
                            scope: .individual,
                            vs: opp,
                            units: delta,
                            detail: e.note
                        )
                    )
                }
            }

            // OYES individuales por rival vs yo.
            for hole in holes {
                guard let ranks = oyesRanksByHole[hole], let yoRank = ranks[yoAlias] else { continue }
                for opp in opps {
                    guard let oppRank = ranks[opp], let v = oyesIndividualResult(hole: hole, opponentAlias: opp), v != 0 else { continue }
                    out.append(
                        UnitLogEntry(
                            hole: hole,
                            player: yoAlias,
                            type: "OYES_RANK",
                            scope: .individual,
                            vs: opp,
                            units: v,
                            detail: "rank \(yoRank) vs \(oppRank)"
                        )
                    )
                }
            }
        }

        if includePair {
            // Unidades de campo/calculadas aplicadas por cada lane (base vs opp).
            for e in directEvents where e.units != 0 {
                for lane in lanes.prefix(3) {
                    let inBase = lane.base.contains(e.alias)
                    let inOpp = lane.opp.contains(e.alias)
                    if !inBase && !inOpp { continue }
                    let signedUnits = inBase ? e.units : -e.units
                    out.append(
                        UnitLogEntry(
                            hole: e.hole,
                            player: lane.base.joined(separator: "+"),
                            type: e.code,
                            scope: .parejas,
                            vs: lane.opp.joined(separator: "+"),
                            units: signedUnits,
                            detail: "\(e.alias) · \(e.note ?? "unidad")"
                        )
                    )
                }
            }

            for hole in holes {
                guard let ranks = oyesRanksByHole[hole] else { continue }
                for lane in lanes.prefix(3) {
                    guard let r = oyesPairResult(hole: hole, lane: lane), r != 0 else { continue }
                    let yoInBase = lane.base.contains(yoAlias)
                    let yoInOpp = lane.opp.contains(yoAlias)
                    if !yoInBase && !yoInOpp { continue }

                    let baseBest = lane.base.compactMap { ranks[$0] }.min()
                    let oppBest = lane.opp.compactMap { ranks[$0] }.min()
                    let detail: String = {
                        if let b = baseBest, let o = oppBest { return "best \(b) vs \(o)" }
                        return "best vs best"
                    }()

                    if yoInBase {
                        out.append(
                            UnitLogEntry(
                                hole: hole,
                                player: lane.base.joined(separator: "+"),
                                type: "OYESP_RANK",
                                scope: .parejas,
                                vs: lane.opp.joined(separator: "+"),
                                units: r,
                                detail: detail
                            )
                        )
                    } else if yoInOpp {
                        out.append(
                            UnitLogEntry(
                                hole: hole,
                                player: lane.opp.joined(separator: "+"),
                                type: "OYESP_RANK",
                                scope: .parejas,
                                vs: lane.base.joined(separator: "+"),
                                units: -r,
                                detail: detail
                            )
                        )
                    }
                }
            }
        }

        return out.sorted {
            if $0.hole == $1.hole { return $0.player < $1.player }
            return $0.hole < $1.hole
        }
    }

    func unitStakeForIndividual(opponentAlias: String, segmentOverride: String? = nil) -> Int {
        let events = unitEventsForZoom(segmentOverride: segmentOverride)
        var total = 0
        for e in events {
            if e.alias == yoAlias {
                total += e.units
            } else if e.alias == opponentAlias {
                total -= e.units
            }
        }
        return total
    }

    func unitStakeForPair(laneId: UUID, segmentOverride: String? = nil) -> Int {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return 0 }
        let events = unitEventsForZoom(segmentOverride: segmentOverride)
        var total = 0
        for e in events {
            if lane.base.contains(e.alias) {
                total += e.units
            } else if lane.opp.contains(e.alias) {
                total -= e.units
            }
        }
        return total
    }

    func hasIndividualUnitWin(hole: Int, alias: String) -> Bool {
        let manual = (unitEventsByHole[hole] ?? []).filter { $0.alias == alias }.reduce(0) { $0 + $1.units }
        let calc = calculatedUnitEventsForHole(hole).filter { $0.alias == alias }.reduce(0) { $0 + $1.units }
        return (manual + calc) > 0
    }

    func hasPairUnitWin(hole: Int, alias: String) -> Bool {
        for lane in lanes {
            let inBase = lane.base.contains(alias)
            let inOpp = lane.opp.contains(alias)
            if !inBase && !inOpp { continue }
            guard let res = oyesPairResult(hole: hole, lane: lane) else { continue }
            if inBase && res > 0 { return true }
            if inOpp && res < 0 { return true }
        }
        return false
    }

    func setCourse(_ course: CourseModel, resetScores shouldResetScores: Bool = true) {
        courseId = course.id
        courseName = course.name
        holes = course.holes
        if shouldResetScores {
            resetScores()
        }
        objectWillChange.send()
    }

    func updateStartHole(_ value: Int, resetScores shouldResetScores: Bool = true) {
        startHole = max(1, min(18, value))
        if shouldResetScores {
            resetScores()
        }
        objectWillChange.send()
    }
    
    func getHole(_ number: Int) -> HoleModel? {
        holes.first { $0.number == number }
    }

    func segmentForHole(_ hole: Int) -> String {
        if hole < 1 || hole > 18 { return "" }
        let start = max(1, min(18, startHole))
        let order = (0..<18).map { ((start - 1 + $0) % 18) + 1 }
        if let idx = order.firstIndex(of: hole) {
            return idx < 9 ? "F9" : "B9"
        }
        return ""
    }

    func playOrder() -> [Int] {
        let start = max(1, min(18, startHole))
        return (0..<18).map { ((start - 1 + $0) % 18) + 1 }
    }

    func isHoleComplete(_ hole: Int) -> Bool {
        if players.isEmpty { return false }
        for p in players {
            if getScore(hole: hole, player: p.alias) <= 0 {
                return false
            }
        }
        return true
    }

    func filledCountForHole(_ hole: Int) -> Int {
        var count = 0
        for p in players {
            if getScore(hole: hole, player: p.alias) > 0 {
                count += 1
            }
        }
        return count
    }

    func missingPlayersForHole(_ hole: Int) -> [String] {
        return players.filter { getScore(hole: hole, player: $0.alias) <= 0 }.map { $0.alias }
    }

    func lastCompleteHole() -> Int? {
        var last: Int? = nil
        for h in playOrder() {
            if isHoleComplete(h) {
                last = h
            }
        }
        return last
    }

    func firstIncompleteHole() -> Int? {
        if players.isEmpty { return nil }
        for h in playOrder() {
            let filled = filledCountForHole(h)
            if filled > 0 && filled < players.count {
                return h
            }
        }
        return nil
    }

    func expectedNextHole() -> Int {
        let order = playOrder()
        if let last = lastCompleteHole(), let idx = order.firstIndex(of: last), idx < order.count - 1 {
            return order[idx + 1]
        }
        return startHole
    }

    func scorecardSnapshot() -> [String: Any] {
        let holesList = playOrder().map { h -> [String: Any] in
            let hole = getHole(h)
            let scores = players.map { p -> [String: Any] in
                let entry = p.scores[h]
                return [
                    "alias": p.alias,
                    "gross": entry?.gross ?? NSNull(),
                    "putts": entry?.putts ?? NSNull()
                ]
            }
            return [
                "hole": h,
                "par": hole?.par ?? 0,
                "si": hole?.si ?? 0,
                "segment": segmentForHole(h),
                "complete": isHoleComplete(h),
                "filled": filledCountForHole(h),
                "scores": scores
            ]
        }

        let lanesList = lanes.map { lane -> [String: Any] in
            return [
                "base": lane.base,
                "opp": lane.opp,
                "strokes": lane.strokes,
                "carrier": lane.strokeCarrier ?? NSNull()
            ]
        }

        return [
            "match": [
                "round_id": roundId,
                "date": dateString,
                "course_id": courseId,
                "start_hole": startHole,
                "players": players.map { ["alias": $0.alias, "name": $0.name, "strokes_vs_base": $0.strokesVsBase] },
                "base_team": baseTeamAliases,
                "lanes": lanesList
            ],
            "status": [
                "last_complete_hole": lastCompleteHole() as Any,
                "first_incomplete_hole": firstIncompleteHole() as Any,
                "missing_players_in_incomplete": firstIncompleteHole() != nil ? missingPlayersForHole(firstIncompleteHole()!) : []
            ],
            "holes": holesList
        ]
    }
    
    func getScore(hole: Int, player: String) -> Int {
        players.first { $0.alias == player }?.scores[hole]?.gross ?? 0
    }
    
    func getPutts(hole: Int, player: String) -> Int {
        players.first { $0.alias == player }?.scores[hole]?.putts ?? 0
    }
    
    func applyScores(_ entities: ScoreEntities) -> (added: Int, updated: Int) {
        guard let holeNumber = entities.hoyo,
              let scores = entities.scores else { return (0, 0) }
        
        var added = 0
        var updated = 0
        for score in scores {
            guard let alias = normalizeAlias(score.jugador) else { continue }
            if let idx = players.firstIndex(where: { $0.alias == alias }) {
                if players[idx].scores[holeNumber] != nil {
                    updated += 1
                } else {
                    added += 1
                }
                players[idx].scores[holeNumber] = (gross: score.gross, putts: score.putts)
                if let p = score.putts {
                    if p == 3 {
                        upsertUnitEvent(hole: holeNumber, alias: alias, code: "3P", units: 0, note: "Tripoteo")
                    } else if p == 4 {
                        upsertUnitEvent(hole: holeNumber, alias: alias, code: "4P", units: 0, note: "Cuatripoteo")
                    }
                }
            }
        }
        
        objectWillChange.send()
        return (added, updated)
    }

    func applyHoleEntry(_ entry: HoleEntryData) {
        let normalized = entry.player_alias.uppercased()
        if let idx = players.firstIndex(where: { $0.alias == normalized || $0.name == normalized }) {
            players[idx].scores[entry.hole_number] = (gross: entry.strokes, putts: entry.putts)
            if let p = entry.putts {
                if p == 3 {
                    upsertUnitEvent(hole: entry.hole_number, alias: players[idx].alias, code: "3P", units: 0, note: "Tripoteo")
                } else if p == 4 {
                    upsertUnitEvent(hole: entry.hole_number, alias: players[idx].alias, code: "4P", units: 0, note: "Cuatripoteo")
                }
            }
            objectWillChange.send()
        }
    }
    
    func exportState() -> [String: Any] {
        return [
            "round_id": roundId,
            "date": dateString,
            "start_hole": startHole,
            "course_id": courseId,
            "course_name": courseName,
            "yo_alias": yoAlias,
            "base_team": baseTeamAliases,
            "players": players.map {
                ["alias": $0.alias, "name": $0.name]
            }
        ]
    }

    func individualBetSummaryLines() -> [String] {
        let opps = players.map(\.alias).filter { $0 != yoAlias }
        if opps.isEmpty { return [] }

        return opps.map { opp in
            let values = playOrder().map { holeResultVsYo(opponentAlias: opp, hole: $0) }
            let f9Values = Array(values.prefix(9))
            let b9Values = Array(values.suffix(9))
            let f9Vuelta = f9Values.compactMap { $0 }.reduce(0, +)
            let b9Vuelta = b9Values.compactMap { $0 }.reduce(0, +)
            let match = f9Vuelta + b9Vuelta
            let f9Presion = pressureNet(values: f9Values, threshold: 2)
            let b9Presion = pressureNet(values: b9Values, threshold: 2)
            let carry = individualCarryResultB9(opponentAlias: opp)
            return "\(opp): F9 V \(f9Vuelta) P \(signed(f9Presion)) · B9 V \(b9Vuelta) P \(signed(b9Presion)) · Carry \(carry) · Match \(match)"
        }
    }

    func oyesIndividualSummaryLines() -> [String] {
        let par3Holes = playOrder().filter { getHole($0)?.par == 3 }
        if par3Holes.isEmpty { return [] }
        let opps = players.map(\.alias).filter { $0 != yoAlias }
        if opps.isEmpty { return [] }
        return opps.map { opp in
            let values = playOrder().map { oyesIndividualResult(hole: $0, opponentAlias: opp) }
            let f9 = Array(values.prefix(9)).compactMap { $0 }.reduce(0, +)
            let b9 = Array(values.suffix(9)).compactMap { $0 }.reduce(0, +)
            let match = f9 + b9
            return "OYES \(opp): F9 \(signed(f9)) · B9 \(signed(b9)) · Match \(signed(match))"
        }
    }

    func oyesPairSummaryLines() -> [String] {
        if lanes.isEmpty { return [] }
        return lanes.prefix(3).compactMap { lane in
            let values = playOrder().map { oyesPairResult(hole: $0, lane: lane) }
            let hasAny = values.contains { $0 != nil }
            if !hasAny { return nil }
            let f9 = Array(values.prefix(9)).compactMap { $0 }.reduce(0, +)
            let b9 = Array(values.suffix(9)).compactMap { $0 }.reduce(0, +)
            let match = f9 + b9
            let label = "OYESP \(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
            return "\(label): F9 \(signed(f9)) · B9 \(signed(b9)) · Match \(signed(match))"
        }
    }

    func exactAlias(for value: String) -> String? {
        let v = normalizePlayerKey(value).replacingOccurrences(of: " ", with: "")
        if let exact = players.first(where: { $0.alias == v }) { return exact.alias }
        if let exact = players.first(where: { normalizePlayerKey($0.name).replacingOccurrences(of: " ", with: "") == v }) { return exact.alias }
        if let bySynonym = aliasBySynonym(v) { return bySynonym }
        if v == "YO" || v == "ME" || v == "MI" || v == "MIO" || v == "MIA" { return yoAlias }
        return nil
    }

    func resolveAliasDetailed(_ value: String) -> (alias: String?, usedFuzzy: Bool) {
        if let exact = exactAlias(for: value) {
            return (exact, false)
        }
        if let fuzzy = fuzzyAlias(for: value) {
            return (fuzzy, true)
        }
        return (nil, false)
    }

    func normalizeAlias(_ value: String) -> String? {
        return resolveAliasDetailed(value).alias
    }

    func fuzzyCandidates(for text: String, limit: Int = 3) -> [(alias: String, score: Double)] {
        let normalized = normalizePlayerKey(text).lowercased()
        let tokens = candidateTokens(from: normalized)
        if tokens.isEmpty { return [] }
        var best: [String: Double] = [:]
        for p in players {
            let alias = p.alias.lowercased()
            let nameKey = normalizePlayerKey(p.name).lowercased()
            var bestScore = 0.0
            for token in tokens {
                let scoreAlias = similarity(token, alias)
                let scoreName = similarity(token, nameKey)
                let score = max(scoreAlias, scoreName)
                if score > bestScore {
                    bestScore = score
                }
            }
            best[p.alias] = bestScore
        }
        let sorted = best
            .filter { $0.value > 0.65 }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (alias: $0.key, score: $0.value) }
        return Array(sorted)
    }

    func normalizePlayerKey(_ value: String) -> String {
        let honorifics: Set<String> = ["DON", "DONA", "SR", "SRA", "SR.", "SRA.", "SENOR", "SENORA", "JR", "JR.", "HIJO"]
        let cleaned = value.uppercased()
            .replacingOccurrences(of: "[^A-Z0-9 ]", with: "", options: .regularExpression)
        let tokens = cleaned.split(separator: " ").map { String($0) }
        let filtered = tokens.filter { !honorifics.contains($0) }
        return filtered.joined(separator: " ")
    }

    private func aliasBySynonym(_ normalizedNoSpaces: String) -> String? {
        let key = normalizedNoSpaces.uppercased()
        for (alias, synonyms) in aliasSynonyms {
            if synonyms.contains(key) { return alias }
        }
        return nil
    }

    private func seedDefaultAliasSynonyms() {
        var seeded: [String: Set<String>] = [:]
        for p in players {
            let alias = p.alias.uppercased()
            let nameKey = normalizePlayerKey(p.name).replacingOccurrences(of: " ", with: "").uppercased()
            var set: Set<String> = [alias]
            if !nameKey.isEmpty { set.insert(nameKey) }
            seeded[alias] = set
        }

        // Variantes comunes esperadas en campo.
        seeded["RIC", default: []].formUnion(["RICH", "RICHI", "RICHIE", "RICARDO", "RICARDOSR"])
        seeded["ROB", default: []].formUnion(["ROBERTO", "ROBERT", "BOB"])
        seeded["ANS", default: []].formUnion(["ANSELMO", "ANSEL", "ANSE"])
        seeded["DAN", default: []].formUnion(["DANIEL", "DANI", "DANNY"])
        seeded["DOA", default: []].formUnion(["DIEGO", "DIEGOSR"])

        // Conserva customizaciones ya agregadas.
        for (alias, custom) in aliasSynonyms {
            seeded[alias, default: []].formUnion(custom)
        }
        aliasSynonyms = seeded
    }

    func isAmbiguousAliasToken(_ value: String) -> Bool {
        let v = normalizePlayerKey(value).replacingOccurrences(of: " ", with: "").lowercased()
        return ambiguousAliasTokens.contains(v)
    }

    func setStrokesVsBase(alias: String, value: Double) {
        guard let idx = players.firstIndex(where: { $0.alias == alias }) else { return }
        var updated = players[idx]
        updated.strokesVsBase = value
        players[idx] = updated
        objectWillChange.send()
    }

    func setBaseTeam(_ aliases: [String], opponentsOverride: [String]? = nil) -> Bool {
        let baseUnique = uniqueAliases(aliases).filter { a in
            players.contains(where: { $0.alias == a })
        }
        if baseUnique.count < 2 { return false }
        baseTeamAliases = baseUnique
        rebuildLanesFromBase(opponentsOverride: opponentsOverride)
        objectWillChange.send()
        return true
    }

    func resetScores() {
        for i in players.indices {
            players[i].scores.removeAll()
        }
    }

    private func onPlayersChanged(resetExistingScores: Bool = true) {
        baseTeamAliases = baseTeamAliases.filter { a in
            players.contains(where: { $0.alias == a })
        }
        if resetExistingScores {
            resetScores()
        }
        rebuildLanesFromBase()
        reconcileBetSwitches()
        rebuildBetInstances()
    }

    func rebuildLanesFromBase(opponentsOverride: [String]? = nil) {
        lanes.removeAll()
        let base = baseTeamAliases
        let rawOpp = opponentsOverride ?? players.map { $0.alias }
        let opponents = uniqueAliases(rawOpp).filter { !base.contains($0) }
        if base.count == 2 {
            if opponents.count == 2 {
                lanes.append(LaneModel(id: UUID(), base: base, opp: opponents, strokes: 0, strokeCarrier: nil))
            } else if opponents.count == 3 {
                let combos = [
                    [opponents[0], opponents[1]],
                    [opponents[0], opponents[2]],
                    [opponents[1], opponents[2]]
                ]
                for opp in combos {
                    lanes.append(LaneModel(id: UUID(), base: base, opp: opp, strokes: 0, strokeCarrier: nil))
                }
            }
            reconcileBetSwitches()
            return
        }
        if base.count == 3 && opponents.count == 2 {
            lanes.append(LaneModel(id: UUID(), base: base, opp: opponents, strokes: 0, strokeCarrier: nil))
        }
        reconcileBetSwitches()
        rebuildBetInstances()
    }

    private func reconcileBetSwitches() {
        let validOpps = Set(players.map(\.alias).filter { $0 != yoAlias })
        var ind: [String: MatchBetSwitches] = [:]
        for opp in validOpps {
            ind[opp] = individualBetSwitchesByOpponent[opp] ?? MatchBetSwitches()
        }
        individualBetSwitchesByOpponent = ind

        let validLaneIds = Set(lanes.prefix(3).map(\.id))
        var pair: [UUID: MatchBetSwitches] = [:]
        for laneId in validLaneIds {
            pair[laneId] = pairBetSwitchesByLane[laneId] ?? MatchBetSwitches()
        }
        pairBetSwitchesByLane = pair
    }

    func betSwitchesForIndividual(opponentAlias: String) -> MatchBetSwitches {
        individualBetSwitchesByOpponent[opponentAlias] ?? MatchBetSwitches()
    }

    func setBetSwitchesForIndividual(opponentAlias: String, switches: MatchBetSwitches) {
        individualBetSwitchesByOpponent[opponentAlias] = switches
        objectWillChange.send()
    }

    func betSwitchesForPair(laneId: UUID) -> MatchBetSwitches {
        pairBetSwitchesByLane[laneId] ?? MatchBetSwitches()
    }

    func setBetSwitchesForPair(laneId: UUID, switches: MatchBetSwitches) {
        pairBetSwitchesByLane[laneId] = switches
        objectWillChange.send()
    }

    func setLaneStrokes(id: UUID, value: Double) {
        guard let idx = lanes.firstIndex(where: { $0.id == id }) else { return }
        var updated = lanes[idx]
        updated.strokes = max(0, value)
        lanes[idx] = updated
        objectWillChange.send()
    }

    func setLaneCarrier(id: UUID, carrier: String?) {
        guard let idx = lanes.firstIndex(where: { $0.id == id }) else { return }
        var updated = lanes[idx]
        updated.strokeCarrier = carrier
        lanes[idx] = updated
        objectWillChange.send()
    }

    func setLaneCarrierForAlias(_ alias: String) {
        for i in lanes.indices {
            if lanes[i].base.contains(alias) || lanes[i].opp.contains(alias) {
                lanes[i].strokeCarrier = alias
            }
        }
        objectWillChange.send()
    }

    func setLaneCarrierForMatch(base: [String], opp: [String], carrier: String) {
        let baseSet = Set(base)
        let oppSet = Set(opp)
        for i in lanes.indices {
            let b = Set(lanes[i].base)
            let o = Set(lanes[i].opp)
            if b == baseSet && o == oppSet && (b.contains(carrier) || o.contains(carrier)) {
                lanes[i].strokeCarrier = carrier
                break
            }
        }
        objectWillChange.send()
    }

    func setLaneStrokesForMatch(base: [String], opp: [String], value: Double) {
        let baseSet = Set(base)
        let oppSet = Set(opp)
        for i in lanes.indices {
            let b = Set(lanes[i].base)
            let o = Set(lanes[i].opp)
            if b == baseSet && o == oppSet {
                lanes[i].strokes = max(0, value)
                break
            }
        }
        objectWillChange.send()
    }

    private func uniqueAliases(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for v in values {
            if seen.contains(v) { continue }
            seen.insert(v)
            out.append(v)
        }
        return out
    }

    private func holeResultVsYo(opponentAlias: String, hole: Int) -> Int? {
        let yoGross = getScore(hole: hole, player: yoAlias)
        let oppGross = getScore(hole: hole, player: opponentAlias)
        if yoGross <= 0 || oppGross <= 0 { return nil }
        let strokes = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: hole, carryAlias: nil)
        let yoNet = Double(yoGross) - strokes.yo
        let oppNet = Double(oppGross) - strokes.opp
        return compareNet(a: yoNet, b: oppNet)
    }

    func individualCarryEligibleRequester(opponentAlias: String) -> String? {
        let f9 = f9VueltaVsOpponent(opponentAlias: opponentAlias)
        if f9 == 0 { return nil }
        return f9 > 0 ? opponentAlias : yoAlias
    }

    func individualF9Vuelta(opponentAlias: String) -> Int {
        f9VueltaVsOpponent(opponentAlias: opponentAlias)
    }

    func setIndividualCarryRequest(opponentAlias: String, requesterAlias: String?) {
        guard players.contains(where: { $0.alias == opponentAlias }) else { return }
        guard opponentAlias != yoAlias else { return }
        if requesterAlias == nil {
            individualCarryRequesterByOpponent.removeValue(forKey: opponentAlias)
            individualCarryStartHoleByOpponent.removeValue(forKey: opponentAlias)
            objectWillChange.send()
            return
        }
        guard let eligible = individualCarryEligibleRequester(opponentAlias: opponentAlias),
              eligible == requesterAlias else { return }
        individualCarryRequesterByOpponent[opponentAlias] = eligible
        individualCarryStartHoleByOpponent[opponentAlias] = carryStartHoleForB9()
        objectWillChange.send()
    }

    func clearIndividualCarryRequest(opponentAlias: String) {
        setIndividualCarryRequest(opponentAlias: opponentAlias, requesterAlias: nil)
    }

    func isIndividualCarryActive(opponentAlias: String) -> Bool {
        guard let requester = individualCarryRequesterByOpponent[opponentAlias],
              let eligible = individualCarryEligibleRequester(opponentAlias: opponentAlias) else { return false }
        return requester == eligible
    }

    func pairCarryEligibleRequester(laneId: UUID) -> String? {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return nil }
        let f9 = pairF9Vuelta(lane: lane)
        if f9 == 0 { return nil }
        if f9 > 0 {
            return lane.opp.first
        }
        return lane.base.first
    }

    func setPairCarryRequest(laneId: UUID, requesterAlias: String?) {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return }
        if requesterAlias == nil {
            pairCarryRequesterByLane.removeValue(forKey: laneId)
            pairCarryStartHoleByLane.removeValue(forKey: laneId)
            objectWillChange.send()
            return
        }
        guard let req = requesterAlias,
              let eligible = pairCarryEligibleRequester(laneId: laneId) else { return }
        let reqInBase = lane.base.contains(req)
        let reqInOpp = lane.opp.contains(req)
        guard reqInBase || reqInOpp else { return }
        let eligibleInBase = lane.base.contains(eligible)
        let eligibleInOpp = lane.opp.contains(eligible)
        if (reqInBase && eligibleInBase) || (reqInOpp && eligibleInOpp) {
            pairCarryRequesterByLane[laneId] = req
            pairCarryStartHoleByLane[laneId] = carryStartHoleForB9()
            objectWillChange.send()
        }
    }

    func clearPairCarryRequest(laneId: UUID) {
        setPairCarryRequest(laneId: laneId, requesterAlias: nil)
    }

    func isPairCarryActive(laneId: UUID) -> Bool {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              let requester = pairCarryRequesterByLane[laneId],
              let eligible = pairCarryEligibleRequester(laneId: laneId) else { return false }
        let requesterInBase = lane.base.contains(requester)
        let requesterInOpp = lane.opp.contains(requester)
        let eligibleInBase = lane.base.contains(eligible)
        let eligibleInOpp = lane.opp.contains(eligible)
        return (requesterInBase && eligibleInBase) || (requesterInOpp && eligibleInOpp)
    }

    func pairCarryResultB9(laneId: UUID) -> Int {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              isPairCarryActive(laneId: laneId),
              let requester = pairCarryRequesterByLane[laneId] else { return 0 }
        let startHole = pairCarryStartHoleByLane[laneId] ?? firstBackNineHole()
        return pairCarryComputedB9(lane: lane, requesterAlias: requester, startHole: startHole)
    }

    func pairF9Vuelta(laneId: UUID) -> Int {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return 0 }
        return pairF9Vuelta(lane: lane)
    }

    func walletSnapshot() -> WalletSnapshot {
        var lines: [WalletLine] = []
        let opps = players.map(\.alias).filter { $0 != yoAlias }
        let order = playOrder()
        let f9Holes = Array(order.prefix(9))
        let b9Holes = Array(order.suffix(9))

        for opp in opps {
            let switches = betSwitchesForIndividual(opponentAlias: opp)
            let f9Values = f9Holes.map { holeResultVsYo(opponentAlias: opp, hole: $0, carryAlias: nil) }
            let b9Values = b9Holes.map { holeResultVsYo(opponentAlias: opp, hole: $0, carryAlias: nil) }
            let f9V = f9Values.compactMap { $0 }.reduce(0, +)
            let b9V = b9Values.compactMap { $0 }.reduce(0, +)
            let matchRaw = f9V + b9V
            let f9P = pressureNet(values: f9Values, threshold: 2)
            let b9P = pressureNet(values: b9Values, threshold: 2)
            let presionPts = f9P + b9P
            let vueltaPts = signedUnit(f9V) + signedUnit(b9V)
            let matchPts = signedUnit(matchRaw)
            let carryPts = individualCarryResultB9(opponentAlias: opp)
            let carryActive = isIndividualCarryActive(opponentAlias: opp)
            let unitsPts = unitStakeForIndividual(opponentAlias: opp, segmentOverride: "F9")
                + unitStakeForIndividual(opponentAlias: opp, segmentOverride: "B9")

            let vPts = switches.vuelta ? vueltaPts : 0
            let pPts = switches.presion ? presionPts : 0
            let cPts = (switches.carry && carryActive) ? carryPts : 0
            let mPts = switches.match ? matchPts : 0
            let uPts = switches.units ? unitsPts : 0

            let vMoney = vPts * vueltaValue
            let pMoney = pPts * presionValue
            let cMoney = cPts * vueltaValue
            let mMoney = mPts * matchValue
            let uMoney = uPts * unitValue
            let total = vMoney + pMoney + cMoney + mMoney + uMoney
            lines.append(
                WalletLine(
                    label: "vs \(opp)",
                    scope: .individual,
                    opponentAlias: opp,
                    laneId: nil,
                    activationSummary: switches.summary,
                    vueltaPoints: vPts,
                    presionPoints: pPts,
                    carryPoints: cPts,
                    carryActive: carryActive,
                    matchPoints: mPts,
                    unitsPoints: uPts,
                    vueltaMoney: vMoney,
                    presionMoney: pMoney,
                    carryMoney: cMoney,
                    matchMoney: mMoney,
                    unitsMoney: uMoney,
                    totalMoney: total
                )
            )
        }

        for lane in lanes.prefix(3) {
            let switches = betSwitchesForPair(laneId: lane.id)
            let f9Values = f9Holes.map { pairResult(hole: $0, lane: lane) }
            let b9Values = b9Holes.map { pairResult(hole: $0, lane: lane) }
            let f9V = f9Values.compactMap { $0 }.reduce(0, +)
            let b9V = b9Values.compactMap { $0 }.reduce(0, +)
            let matchRaw = f9V + b9V
            let f9P = pressureNet(values: f9Values, threshold: 3)
            let b9P = pressureNet(values: b9Values, threshold: 3)
            let presionPts = f9P + b9P
            let vueltaPts = signedUnit(f9V) + signedUnit(b9V)
            let matchPts = signedUnit(matchRaw)
            let carryPts = pairCarryResultB9(laneId: lane.id)
            let carryActive = isPairCarryActive(laneId: lane.id)
            let unitsPts = unitStakeForPair(laneId: lane.id, segmentOverride: "F9")
                + unitStakeForPair(laneId: lane.id, segmentOverride: "B9")

            let vPts = switches.vuelta ? vueltaPts : 0
            let pPts = switches.presion ? presionPts : 0
            let cPts = (switches.carry && carryActive) ? carryPts : 0
            let mPts = switches.match ? matchPts : 0
            let uPts = switches.units ? unitsPts : 0

            let vMoney = vPts * vueltaValue
            let pMoney = pPts * presionValue
            let cMoney = cPts * vueltaValue
            let mMoney = mPts * matchValue
            let uMoney = uPts * unitValue
            let total = vMoney + pMoney + cMoney + mMoney + uMoney
            lines.append(
                WalletLine(
                    label: "\(lane.base.joined(separator: "+"))/\(lane.opp.joined(separator: "+"))",
                    scope: .parejas,
                    opponentAlias: nil,
                    laneId: lane.id,
                    activationSummary: switches.summary,
                    vueltaPoints: vPts,
                    presionPoints: pPts,
                    carryPoints: cPts,
                    carryActive: carryActive,
                    matchPoints: mPts,
                    unitsPoints: uPts,
                    vueltaMoney: vMoney,
                    presionMoney: pMoney,
                    carryMoney: cMoney,
                    matchMoney: mMoney,
                    unitsMoney: uMoney,
                    totalMoney: total
                )
            )
        }

        let total = lines.reduce(0) { $0 + $1.totalMoney }
        return WalletSnapshot(lines: lines, totalMoney: total)
    }

    // Siempre calcula carry en B9 (sin importar si está activa), para monetización.
    func pairCarryComputedB9(laneId: UUID) -> Int {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              let requester = pairCarryEligibleRequester(laneId: laneId) else { return 0 }
        return pairCarryComputedB9(lane: lane, requesterAlias: requester, startHole: firstBackNineHole())
    }

    func pairCarryMoneyB9(laneId: UUID) -> Int {
        guard isPairCarryActive(laneId: laneId) else { return 0 }
        return pairCarryResultB9(laneId: laneId) * vueltaValue
    }

    // Resultado de la apuesta Carry en B9 (solo si está activa).
    func individualCarryResultB9(opponentAlias: String) -> Int {
        guard isIndividualCarryActive(opponentAlias: opponentAlias),
              let carryAlias = individualCarryRequesterByOpponent[opponentAlias] else { return 0 }
        let startHole = individualCarryStartHoleByOpponent[opponentAlias] ?? firstBackNineHole()
        return individualCarryComputedB9(opponentAlias: opponentAlias, requesterAlias: carryAlias, startHole: startHole)
    }

    // Siempre calcula carry en B9 (sin importar si está activa), para monetización.
    func individualCarryComputedB9(opponentAlias: String) -> Int {
        guard let requester = individualCarryEligibleRequester(opponentAlias: opponentAlias) else { return 0 }
        return individualCarryComputedB9(opponentAlias: opponentAlias, requesterAlias: requester, startHole: firstBackNineHole())
    }

    func individualCarryMoneyB9(opponentAlias: String) -> Int {
        guard isIndividualCarryActive(opponentAlias: opponentAlias) else { return 0 }
        return individualCarryResultB9(opponentAlias: opponentAlias) * vueltaValue
    }

    private func f9VueltaVsOpponent(opponentAlias: String) -> Int {
        let order = playOrder()
        let f9 = Array(order.prefix(9))
        return f9.compactMap { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: nil) }.reduce(0, +)
    }

    private func holeResultVsYo(opponentAlias: String, hole: Int, carryAlias: String?) -> Int? {
        let yoGross = getScore(hole: hole, player: yoAlias)
        let oppGross = getScore(hole: hole, player: opponentAlias)
        if yoGross <= 0 || oppGross <= 0 { return nil }
        let strokes = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: hole, carryAlias: carryAlias)
        let yoNet = Double(yoGross) - strokes.yo
        let oppNet = Double(oppGross) - strokes.opp
        return compareNet(a: yoNet, b: oppNet)
    }

    private func individualCarryComputedB9(opponentAlias: String, requesterAlias: String, startHole: Int) -> Int {
        let order = playOrder()
        let b9 = Array(order.suffix(9))
        let startIdx = b9.firstIndex(of: startHole) ?? 0
        if startIdx >= b9.count { return 0 }
        return Array(b9[startIdx...]).compactMap { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: requesterAlias) }.reduce(0, +)
    }

    private func playerStrokes(alias: String) -> Double {
        players.first(where: { $0.alias == alias })?.strokesVsBase ?? 0
    }

    private func oyesUnitForHole(_ hole: Int, pair: Bool) -> Int {
        if pair {
            if let u = oyesPairUnitByHole[hole], u > 0 { return u }
        } else {
            if let u = oyesIndividualUnitByHole[hole], u > 0 { return u }
        }
        return 1
    }

    private func enabledCalculatedTags() -> Set<String> {
        // Las unidades calculadas de campo se reportan siempre por gross.
        return Set(betCatalog.filter { $0.mode == .calculado }.map { $0.tag.uppercased() })
    }

    private func unitsForCalculatedTag(_ tag: String, fallback: Int) -> Int {
        betCatalog.first(where: { $0.tag.uppercased() == tag })?.units ?? fallback
    }

    private func calculatedUnitEventsForHole(_ hole: Int) -> [UnitEvent] {
        guard let h = getHole(hole) else { return [] }
        let enabled = enabledCalculatedTags()
        if enabled.isEmpty { return [] }
        var out: [UnitEvent] = []
        for p in players {
            let gross = getScore(hole: hole, player: p.alias)
            if gross <= 0 { continue }

            if enabled.contains("HIO"), gross == 1 {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "HIO", units: unitsForCalculatedTag("HIO", fallback: 100), note: "Hole in One"))
            }
            if enabled.contains("ALB"), gross == (h.par - 3) {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "ALB", units: unitsForCalculatedTag("ALB", fallback: 3), note: "Albatros"))
            } else if enabled.contains("EAG"), gross == (h.par - 2) {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "EAG", units: unitsForCalculatedTag("EAG", fallback: 2), note: "Aguila"))
            } else if enabled.contains("BIRD"), gross == (h.par - 1) {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "BIRD", units: unitsForCalculatedTag("BIRD", fallback: 1), note: "Birdie"))
            }
            if enabled.contains("B18"), hole == 18, gross == (h.par - 1) {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "B18", units: unitsForCalculatedTag("B18", fallback: 2), note: "Birdie 18"))
            }
        }
        return out
    }

    private func oyesIndividualResult(hole: Int, opponentAlias: String) -> Int? {
        guard getHole(hole)?.par == 3 else { return nil }
        guard let ranks = oyesRanksByHole[hole],
              let yoRank = ranks[yoAlias],
              let oppRank = ranks[opponentAlias] else { return nil }
        let unit = oyesUnitForHole(hole, pair: false)
        if yoRank < oppRank { return unit }
        if yoRank > oppRank { return -unit }
        return 0
    }

    private func oyesPairResult(hole: Int, lane: LaneModel) -> Int? {
        guard getHole(hole)?.par == 3 else { return nil }
        guard let ranks = oyesRanksByHole[hole] else { return nil }
        let baseRanks = lane.base.compactMap { ranks[$0] }
        let oppRanks = lane.opp.compactMap { ranks[$0] }
        guard baseRanks.count == lane.base.count, oppRanks.count == lane.opp.count,
              let baseBest = baseRanks.min(), let oppBest = oppRanks.min() else { return nil }
        let unit = oyesUnitForHole(hole, pair: true)
        if baseBest < oppBest { return unit }
        if baseBest > oppBest { return -unit }
        return 0
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    func pairBetSummaryLines() -> [String] {
        if lanes.isEmpty { return [] }
        return lanes.prefix(3).map { lane in
            let values = playOrder().map { pairResult(hole: $0, lane: lane) }
            let f9Values = Array(values.prefix(9))
            let b9Values = Array(values.suffix(9))
            let f9Vuelta = f9Values.compactMap { $0 }.reduce(0, +)
            let b9Vuelta = b9Values.compactMap { $0 }.reduce(0, +)
            let match = f9Vuelta + b9Vuelta
            let f9Presion = pressureNet(values: f9Values, threshold: 3)
            let b9Presion = pressureNet(values: b9Values, threshold: 3)
            let label = "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
            let carry = pairCarryResultB9(laneId: lane.id)
            return "\(label): F9 V \(f9Vuelta) P \(signed(f9Presion)) · B9 V \(b9Vuelta) P \(signed(b9Presion)) · Carry \(carry) · Match \(match)"
        }
    }

    func individualZoomRows(opponentAlias: String, segmentOverride: String? = nil) -> [IndividualZoomRow] {
        let holesForSegment = zoomHolesForCurrentRound(segmentOverride: segmentOverride)
        if holesForSegment.isEmpty { return [] }
        var raw: [(hole: Int, row: IndividualZoomRow?)] = []
        var values: [Int] = []
        var yoPuttsAccum = 0
        var oppPuttsAccum = 0
        var vuelta = 0
        var match = 0

        for hole in holesForSegment {
            let yoGross = getScore(hole: hole, player: yoAlias)
            let oppGross = getScore(hole: hole, player: opponentAlias)
            if yoGross <= 0 || oppGross <= 0 {
                raw.append((hole, nil))
                continue
            }
            let strokes = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: hole, carryAlias: nil)
            let yoStroke = strokes.yo
            let oppStroke = strokes.opp
            let yoNet = Double(yoGross) - yoStroke
            let oppNet = Double(oppGross) - oppStroke
            let result = compareNet(a: yoNet, b: oppNet)
            values.append(result)
            vuelta += result
            match += result
            yoPuttsAccum += getPutts(hole: hole, player: yoAlias)
            oppPuttsAccum += getPutts(hole: hole, player: opponentAlias)
            let p = pressureStates(values: values, threshold: 2).last ?? []
            let row = IndividualZoomRow(
                hole: hole,
                par: getHole(hole)?.par ?? 0,
                si: getHole(hole)?.si ?? 0,
                yoGross: yoGross,
                yoStrokes: yoStroke,
                yoNet: yoNet,
                oppAlias: opponentAlias,
                oppGross: oppGross,
                oppStrokes: oppStroke,
                oppNet: oppNet,
                result: result,
                vueltaAccum: vuelta,
                matchAccum: match,
                openPressures: p,
                yoPuttsAccum: yoPuttsAccum,
                oppPuttsAccum: oppPuttsAccum,
                totalPuttsAccum: yoPuttsAccum + oppPuttsAccum
            )
            raw.append((hole, row))
        }

        return raw.compactMap { $0.row }
    }

    // Individuales usan el histórico por jugador vs base:
    // positivo = ese jugador recibe; negativo = ese jugador da (recibe el rival).
    private func individualMatchupStrokes(yoAlias: String, oppAlias: String, hole: Int, carryAlias: String?) -> (yo: Double, opp: Double) {
        let yoTotal = playerStrokes(alias: yoAlias)
        let oppTotal = playerStrokes(alias: oppAlias)

        var yoStroke = 0.0
        var oppStroke = 0.0

        if yoTotal > 0 {
            yoStroke += distributedStrokes(total: yoTotal, hole: hole)
        } else if yoTotal < 0 {
            oppStroke += distributedStrokes(total: -yoTotal, hole: hole)
        }

        if oppTotal > 0 {
            oppStroke += distributedStrokes(total: oppTotal, hole: hole)
        } else if oppTotal < 0 {
            yoStroke += distributedStrokes(total: -oppTotal, hole: hole)
        }

        if segmentForHole(hole) == "B9", let carry = carryAlias {
            if carry == yoAlias {
                yoStroke += 1
            } else if carry == oppAlias {
                oppStroke += 1
            }
        }

        return (yoStroke, oppStroke)
    }

    func pairZoomRows(laneId: UUID, segmentOverride: String? = nil) -> [PairZoomRow] {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              lastCompleteHole() != nil else { return [] }
        let holesForSegment = zoomHolesForCurrentRound(segmentOverride: segmentOverride)
        if holesForSegment.isEmpty { return [] }
        var values: [Int] = []
        var vuelta = 0
        var match = 0
        var rows: [PairZoomRow] = []

        for hole in holesForSegment {
            let baseBalls = pairBallLines(for: lane.base, hole: hole, lane: lane)
            let oppBalls = pairBallLines(for: lane.opp, hole: hole, lane: lane)
            if baseBalls.count < 2 || oppBalls.count < 2 { continue }
            let baseSorted = baseBalls.sorted { $0.net < $1.net }
            let oppSorted = oppBalls.sorted { $0.net < $1.net }
            let minResult = compareNet(a: baseSorted[0].net, b: oppSorted[0].net)
            let maxResult = compareNet(a: baseSorted[1].net, b: oppSorted[1].net)
            let result = minResult + maxResult
            values.append(result)
            vuelta += result
            match += result
            let p = pressureStates(values: values, threshold: 3).last ?? []
            rows.append(
                PairZoomRow(
                    hole: hole,
                    par: getHole(hole)?.par ?? 0,
                    si: getHole(hole)?.si ?? 0,
                    basePlayers: baseBalls,
                    oppPlayers: oppBalls,
                    carrierAlias: lane.strokeCarrier,
                    result: result,
                    vueltaAccum: vuelta,
                    matchAccum: match,
                    openPressures: p
                )
            )
        }
        return rows
    }

    func availableZoomSegments() -> [String] {
        guard let maxHole = lastCompleteHole() else { return [] }
        let order = playOrder()
        guard let maxIdx = order.firstIndex(of: maxHole) else { return [] }
        if maxIdx >= 9 {
            return ["F9", "B9"]
        }
        return ["F9"]
    }

    func lastHoleForZoom(segment: String) -> Int? {
        zoomHolesForCurrentRound(segmentOverride: segment).last
    }

    func puttsSplit(alias: String, uptoHole: Int) -> (f9: Int, b9: Int, total: Int) {
        let order = playOrder()
        guard let maxIdx = order.firstIndex(of: uptoHole) else { return (0, 0, 0) }
        var f9 = 0
        var b9 = 0
        for (idx, h) in order.enumerated() where idx <= maxIdx {
            let p = getPutts(hole: h, player: alias)
            if idx < 9 {
                f9 += p
            } else {
                b9 += p
            }
        }
        return (f9, b9, f9 + b9)
    }

    private func pairResult(hole: Int, lane: LaneModel, carryRequesterAlias: String? = nil) -> Int? {
        let baseNets = pairNets(for: lane.base, hole: hole, lane: lane, carryRequesterAlias: carryRequesterAlias)
        let oppNets = pairNets(for: lane.opp, hole: hole, lane: lane, carryRequesterAlias: carryRequesterAlias)
        if baseNets.count < 2 || oppNets.count < 2 { return nil }
        let minResult = compareNet(a: baseNets[0], b: oppNets[0])
        let maxResult = compareNet(a: baseNets[1], b: oppNets[1])
        return minResult + maxResult
    }

    private func pairBallLines(for aliases: [String], hole: Int, lane: LaneModel, carryRequesterAlias: String? = nil) -> [PairBallLine] {
        var lines: [PairBallLine] = []
        for alias in aliases {
            let gross = getScore(hole: hole, player: alias)
            if gross <= 0 { continue }
            // En parejas solo aplica el stroke de la pareja al jugador "lleva".
            // Los strokes individuales no participan en esta apuesta.
            let individual = 0.0
            let laneExtra = laneCarrierStroke(lane: lane, alias: alias, hole: hole, carryRequesterAlias: carryRequesterAlias)
            let totalStrokes = individual + laneExtra
            let net = Double(gross) - totalStrokes
            lines.append(
                PairBallLine(
                    alias: alias,
                    gross: gross,
                    individualStrokes: individual,
                    laneStrokes: laneExtra,
                    net: net
                )
            )
        }
        return lines
    }

    private func pairNets(for aliases: [String], hole: Int, lane: LaneModel, carryRequesterAlias: String? = nil) -> [Double] {
        var nets: [Double] = []
        for alias in aliases {
            let gross = getScore(hole: hole, player: alias)
            if gross <= 0 { continue }
            // En parejas solo aplica el stroke de la pareja al jugador "lleva".
            // Los strokes individuales no participan en esta apuesta.
            let individual = 0.0
            let laneExtra = laneCarrierStroke(lane: lane, alias: alias, hole: hole, carryRequesterAlias: carryRequesterAlias)
            let net = Double(gross) - individual - laneExtra
            nets.append(net)
        }
        return nets.sorted()
    }

    private func laneCarrierStroke(lane: LaneModel, alias: String, hole: Int, carryRequesterAlias: String? = nil) -> Double {
        let profile = effectiveLaneStrokeProfile(lane: lane, carryRequesterAlias: carryRequesterAlias)
        guard profile.carrier == alias else { return 0 }
        return distributedStrokes(total: profile.total, hole: hole)
    }

    private func effectiveLaneStrokeProfile(lane: LaneModel, carryRequesterAlias: String?) -> (total: Double, carrier: String?) {
        let currentCarrier = lane.strokeCarrier
        let currentSign: Double = {
            guard let c = currentCarrier else { return 0 }
            if lane.base.contains(c) { return lane.strokes }
            if lane.opp.contains(c) { return -lane.strokes }
            return 0
        }()

        var signed = currentSign
        if let requester = carryRequesterAlias {
            if lane.base.contains(requester) {
                signed += 1
            } else if lane.opp.contains(requester) {
                signed -= 1
            }
        }

        if abs(signed) < 0.001 {
            return (0, nil)
        }
        if signed > 0 {
            let carrier = (currentCarrier != nil && lane.base.contains(currentCarrier!)) ? currentCarrier! : (lane.base.first ?? "")
            return (signed, carrier.isEmpty ? nil : carrier)
        }
        let carrier = (currentCarrier != nil && lane.opp.contains(currentCarrier!)) ? currentCarrier! : (lane.opp.first ?? "")
        return (-signed, carrier.isEmpty ? nil : carrier)
    }

    private func pairF9Vuelta(lane: LaneModel) -> Int {
        let order = playOrder()
        let f9 = Array(order.prefix(9))
        return f9.compactMap { pairResult(hole: $0, lane: lane) }.reduce(0, +)
    }

    private func pairCarryComputedB9(lane: LaneModel, requesterAlias: String, startHole: Int) -> Int {
        let order = playOrder()
        let b9 = Array(order.suffix(9))
        let startIdx = b9.firstIndex(of: startHole) ?? 0
        if startIdx >= b9.count { return 0 }
        return Array(b9[startIdx...]).compactMap { pairResult(hole: $0, lane: lane, carryRequesterAlias: requesterAlias) }.reduce(0, +)
    }

    private func firstBackNineHole() -> Int {
        let order = playOrder()
        if order.count > 9 {
            return order[9]
        }
        return order.first ?? startHole
    }

    private func carryStartHoleForB9() -> Int {
        let order = playOrder()
        let b9 = Array(order.suffix(9))
        let expected = expectedNextHole()
        if b9.contains(expected) {
            return expected
        }
        return firstBackNineHole()
    }

    private func distributedStrokes(total: Double, hole: Int) -> Double {
        guard total > 0, let si = getHole(hole)?.si else { return 0 }
        let fullRounds = Int(total / 18.0)
        let remainder = total - Double(fullRounds * 18)
        let whole = Int(floor(remainder))
        let fraction = remainder - Double(whole)
        var strokes = Double(fullRounds)
        if si <= whole {
            strokes += 1
        } else if fraction >= 0.5, si == whole + 1 {
            strokes += 0.5
        }
        return strokes
    }

    private func compareNet(a: Double, b: Double) -> Int {
        if abs(a - b) < 0.001 { return 0 }
        return a < b ? 1 : -1
    }

    private func signedUnit(_ value: Int) -> Int {
        if value > 0 { return 1 }
        if value < 0 { return -1 }
        return 0
    }

    private func pressureCount(values: [Int?], threshold: Int) -> (won: Int, lost: Int) {
        var won = 0
        var lost = 0
        var vuelta = 0
        var opened = false
        var active: [Int] = []

        for raw in values {
            guard let v = raw else { continue }
            vuelta += v
            for i in active.indices {
                active[i] += v
            }

            var survivors: [Int] = []
            var closed = 0
            for p in active {
                if abs(p) >= threshold {
                    if p > 0 { won += 1 } else if p < 0 { lost += 1 }
                    closed += 1
                } else {
                    survivors.append(p)
                }
            }
            active = survivors

            if !opened && abs(vuelta) >= threshold {
                opened = true
                active.append(0)
            }
            if closed > 0 {
                for _ in 0..<closed { active.append(0) }
            }
        }
        return (won, lost)
    }

    // Presión neta al cierre del segmento:
    // suma +1 por cada presión abierta positiva y -1 por cada negativa.
    private func pressureNet(values: [Int?], threshold: Int) -> Int {
        let compact = values.compactMap { $0 }
        if compact.isEmpty { return 0 }
        let last = pressureStates(values: compact, threshold: threshold).last ?? []
        return last.reduce(0) { acc, p in
            if p > 0 { return acc + 1 }
            if p < 0 { return acc - 1 }
            return acc
        }
    }

    private func pressureStates(values: [Int], threshold: Int) -> [[Int]] {
        var out: [[Int]] = []
        var vuelta = 0
        var baseOpened = false
        var active: [Int] = []
        for v in values {
            let prevVuelta = vuelta
            vuelta += v
            var prevActive = active
            for i in active.indices {
                active[i] += v
            }
            var spawned = 0
            // La vuelta abre una sola presión cuando cruza el umbral.
            if !baseOpened, abs(prevVuelta) < threshold, abs(vuelta) >= threshold {
                baseOpened = true
                spawned += 1
            }
            // Cada presión abierta puede abrir otra al cruzar umbral; no se cierra.
            for i in active.indices {
                if abs(prevActive[i]) < threshold, abs(active[i]) >= threshold {
                    spawned += 1
                }
            }
            // Las nuevas presiones arrancan en 0 y empiezan a contar desde el siguiente hoyo.
            if spawned > 0 {
                for _ in 0..<spawned { active.append(0) }
            }
            out.append(active)
        }
        return out
    }

    private func zoomHolesForCurrentRound(segmentOverride: String? = nil) -> [Int] {
        guard let maxHole = lastCompleteHole() else { return [] }
        let order = playOrder()
        guard let maxIdx = order.firstIndex(of: maxHole) else { return [] }
        let selectedSegment: String
        if let s = segmentOverride, (s == "F9" || s == "B9") {
            selectedSegment = s
        } else {
            selectedSegment = maxIdx >= 9 ? "B9" : "F9"
        }
        if selectedSegment == "F9" {
            let end = min(8, maxIdx)
            if end < 0 { return [] }
            return Array(order[0...end])
        }
        if maxIdx < 9 { return [] }
        return Array(order[9...maxIdx])
    }

    private func fuzzyAlias(for text: String) -> String? {
        let normalized = normalizePlayerKey(text).lowercased()
        if normalized.isEmpty { return nil }
        let tokens = candidateTokens(from: normalized)
        if tokens.isEmpty { return nil }
        var bestAlias: String? = nil
        var bestScore = 0.0
        for p in players {
            let alias = p.alias.lowercased()
            let nameKey = normalizePlayerKey(p.name).lowercased()
            for token in tokens {
                let scoreAlias = similarity(token, alias)
                let scoreName = similarity(token, nameKey)
                let score = max(scoreAlias, scoreName)
                if score > bestScore {
                    bestScore = score
                    bestAlias = p.alias
                }
            }
        }
        if bestScore >= 0.78 {
            return bestAlias
        }
        return nil
    }

    private func candidateTokens(from text: String) -> [String] {
        let words = text.split(separator: " ").map { String($0) }
        let filtered = words.filter { !fuzzyStopWords.contains($0) && $0.count >= 2 }
        var tokens: [String] = []
        tokens.append(contentsOf: filtered)
        if filtered.count >= 2 {
            for i in 0..<(filtered.count - 1) {
                tokens.append(filtered[i] + " " + filtered[i + 1])
            }
        }
        return tokens
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        let dist = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        return 1.0 - (Double(dist) / Double(maxLen))
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var dp = Array(repeating: Array(repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
        for i in 0...aChars.count { dp[i][0] = i }
        for j in 0...bChars.count { dp[0][j] = j }
        if aChars.isEmpty || bChars.isEmpty {
            return max(aChars.count, bChars.count)
        }
        for i in 1...aChars.count {
            for j in 1...bChars.count {
                if aChars[i - 1] == bChars[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = min(
                        dp[i - 1][j] + 1,
                        dp[i][j - 1] + 1,
                        dp[i - 1][j - 1] + 1
                    )
                }
            }
        }
        return dp[aChars.count][bChars.count]
    }

    private var fuzzyStopWords: Set<String> {
        return [
            "el","la","los","las","un","una","unos","unas","de","del","al","por","para","con","sin","y","e","o","u",
            "yo","mi","mis","mio","mia","tu","tus","su","sus",
            "hoyo","hoyos","stroke","strokes","golpe","golpes","putt","putts",
            "base","pareja","parejas","contra","vs","versus","dan"
        ]
    }

    private var ambiguousAliasTokens: Set<String> {
        return ["dan"]
    }
}
