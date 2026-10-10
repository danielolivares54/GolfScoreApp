//
//  MatchManager.swift
//  Caddy_Score
//
//  Created by daniel olivares on 2/14/26.
//

import Foundation
import Combine

enum CellOverride: String, Codable {
    case none
    case penaltyStroke   // diagonal sobre la celda
    case lostHole        // Cruz ✕
    case noShow          // Cruz ✕
    case disqualified    // Cruz ✕
    case conceded        // Cruz ✕
}

struct PlayerModel: Identifiable {
    let id = UUID()
    let alias: String
    let name: String
    var strokesVsBase: Double
    var scores: [Int: (gross: Int, putts: Int?)] = [:]
    var cellOverrides: [Int: CellOverride] = [:]
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

enum BetType: String, CaseIterable, Codable {
    case individual
    case parejas
}

enum BetMode: String, CaseIterable, Codable {
    case calculado
    case manual
}

enum PuttsBetMode: String, CaseIterable, Codable {
    case hole18 = "H18"
    case byRound = "Vuelta"
}

struct BetDefinition: Identifiable, Codable, Equatable {
    var id = UUID()
    let tag: String
    var name: String
    let type: BetType
    let mode: BetMode
    var units: Int
    var description: String
    // Único interruptor de activación — global, no por match ni por plantilla. Un tag
    // desactivado aquí no aparece como opción ni se registra en ningún match.
    var isEnabled: Bool = true
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
    var id = UUID()
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
    let adjust50Points: Int
    let adjust50Active: Bool
    let doublePressActive: Bool
    let matchPoints: Int
    let unitsPoints: Int
    let vueltaMoney: Int
    let presionMoney: Int
    let carryMoney: Int
    let adjust50Money: Int
    let matchMoney: Int
    let unitsMoney: Int
    let totalMoney: Int
}

struct WalletSnapshot {
    let lines: [WalletLine]
    let totalMoney: Int
}

// Apuesta (plantilla + valores) de un oponente individual específico — permite que cada rival
// tenga una apuesta distinta a los demás. Las parejas no usan esto, ver betValuesByOpponent.
struct OpponentBetValues: Codable, Equatable {
    var templateId: String?
    var vueltaValue: Int
    var presionValue: Int
    var matchValue: Int
    var unitValue: Int
}

struct MatchBetSwitches: Codable {
    var vuelta: Bool = true
    var presion: Bool = true
    var carry: Bool = true
    var adjust50: Bool = true
    var match: Bool = true
    var units: Bool = true

    var summary: String {
        var out: [String] = []
        if vuelta { out.append("V") }
        if presion { out.append("P") }
        if carry { out.append("C") }
        if adjust50 { out.append("A") }
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
    // Default $1 (no $0) para que el cálculo siempre refleje algo mientras no se configure una
    // apuesta real — $0 en todo se veía como "no funciona", no como "sin apuesta".
    @Published var vueltaValue: Int = 1
    @Published var presionValue: Int = 1
    @Published var matchValue: Int = 1
    @Published var unitValue: Int = 1
    @Published var puttsBetMode: PuttsBetMode = .hole18
    @Published var puttsBetUnits: Int = 2
    @Published var activeTemplateId: String? = nil
    // Cada oponente individual puede tener su propia plantilla/valor de apuesta (distinto al de otros
    // rivales). Las parejas NO usan este diccionario — siguen compartiendo un solo valor global
    // (vueltaValue/presionValue/matchValue/unitValue arriba), igual para las 3 combinaciones de lane.
    @Published var betValuesByOpponent: [String: OpponentBetValues] = [:]
    @Published var individualBetSwitchesByOpponent: [String: MatchBetSwitches] = [:]
    @Published var pairBetSwitchesByLane: [UUID: MatchBetSwitches] = [:]
    // Carry en B9 por matchup individual (oponente -> alias que lo solicitó).
    @Published var individualCarryRequesterByOpponent: [String: String] = [:]
    @Published var individualCarryStartHoleByOpponent: [String: Int] = [:]
    // Carry en B9 por pareja (laneId -> alias que lo solicitó).
    @Published var pairCarryRequesterByLane: [UUID: String] = [:]
    @Published var pairCarryStartHoleByLane: [UUID: Int] = [:]
    // Double Press en B9 — activo o no por rival/pareja. Solo duplica el dinero de Vuelta y
    // Presión en B9 (no Match, no strokes) — es monetización pura, independiente de Carry/Ajuste 50.
    @Published var individualDoublePressOpponents: Set<String> = []
    @Published var pairDoublePressLanes: Set<UUID> = []
    // Ajuste 50 en B9 — activo o no por rival/pareja. Redefine los strokes de B9 según el
    // resultado del F9 (ver individualAdjust50Profile/pairAdjust50Profile) — mutuamente excluyente
    // con Carry para el mismo rival/pareja (SSOT Sección 7).
    @Published var individualAdjust50Opponents: Set<String> = []
    @Published var pairAdjust50Lanes: Set<UUID> = []
    // Cuando el ajuste se invierte de lado (ver pairAdjust50Profile) y ese lado tiene 2
    // compañeros, quién de ellos recibe el stroke invertido — elegido por el usuario, igual que
    // pairCarryRequesterByLane. Sin elección guardada, cae a otherSide.first (mismo default que Carry).
    @Published var pairAdjust50FlipReceiverByLane: [UUID: String] = [:]
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
        rebuildBetInstances()

        NotificationCenter.default.addObserver(
            forName: .siriRecordPending,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromScoreManager()
        }
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
        players = []
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

    // El catálogo real (editable, persistido) vive en BetDefinitionStore — esto solo copia al
    // match la foto vigente de tags habilitados. Para recoger cambios hechos en el editor de
    // catálogo a medio match, se vuelve a llamar (ver BetDefinitionEditorView).
    func setupDefaultBets() {
        betCatalog = BetDefinitionStore.shared.entries.filter { $0.isEnabled }
        // Ya no hay selección por match/plantilla — todo tag habilitado en el catálogo global
        // está activo en todos los matches. Ver BetDefinitionEditorView.
        activeBets = betCatalog.map { ActiveBet(definition: $0, tagOverride: nil) }
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

    func setVueltaValue(_ value: Int) {
        vueltaValue = max(0, value)
        unitValue = max(0, value / 2)
        objectWillChange.send()
    }

    func setUnitValue(_ value: Int) {
        unitValue = max(0, value)
        objectWillChange.send()
        saveBetConfig()
    }

    func setApuestaValues(vuelta: Int, presion: Int, match: Int) {
        vueltaValue = max(0, vuelta)
        presionValue = max(0, presion)
        matchValue = max(0, match)
        objectWillChange.send()
        saveBetConfig()
    }

    func setPuttsBet(mode: PuttsBetMode, units: Int) {
        puttsBetMode = mode
        puttsBetUnits = max(0, units)
        objectWillChange.send()
    }

    func applyBetTemplate(_ template: BetTemplate) {
        activeTemplateId = template.id
        vueltaValue = template.vueltaValue
        presionValue = template.presionValue
        matchValue = template.matchValue
        unitValue = template.unitValue
        puttsBetMode = template.puttsBetMode
        puttsBetUnits = template.puttsEnabled ? template.puttsBetUnits : 0
        objectWillChange.send()
        saveBetConfig()
    }

    // Apuesta propia de un oponente individual — no toca vueltaValue/presionValue/matchValue/unitValue
    // globales (esos siguen siendo los que usan las parejas). Ver walletSnapshot().
    func setBetTemplateForOpponent(_ opponentAlias: String, template: BetTemplate) {
        betValuesByOpponent[opponentAlias] = OpponentBetValues(
            templateId: template.id,
            vueltaValue: template.vueltaValue,
            presionValue: template.presionValue,
            matchValue: template.matchValue,
            unitValue: template.unitValue
        )
        objectWillChange.send()
        saveBetConfig()
    }

    // Valores de apuesta a usar para un oponente individual: su propia plantilla si se definió,
    // o los valores globales de la ronda como respaldo (match creado antes de esta función).
    func betValues(forOpponent opponentAlias: String) -> OpponentBetValues {
        betValuesByOpponent[opponentAlias] ?? OpponentBetValues(
            templateId: activeTemplateId,
            vueltaValue: vueltaValue,
            presionValue: presionValue,
            matchValue: matchValue,
            unitValue: unitValue
        )
    }

    // MARK: - Persistencia de configuración de apuestas (plantilla, valores, parejas)
    //
    // Antes solo los golpes (ScoreManager) sobrevivían a un relanzamiento de la app — vuelta/
    // presión/match/unit, las parejas (lanes) y sus strokes vivían solo en memoria y se perdían
    // cada vez. Esto se guarda en el mismo App Group que ScoreManager, y se borra junto con los
    // golpes al "Cerrar Ronda" (único punto que borra datos).
    private struct BetConfigSnapshot: Codable {
        var activeTemplateId: String?
        var vueltaValue: Int
        var presionValue: Int
        var matchValue: Int
        var unitValue: Int
        var betValuesByOpponent: [String: OpponentBetValues]
        var baseTeamAliases: [String]
        // Las lanes se reconstruyen desde baseTeamAliases (nuevos UUID cada vez) — los strokes de
        // pareja se guardan por la combinación de aliases oponentes (estable), no por lane.id.
        var laneStrokesByOppKey: [String: Double]
        var strokesVsBaseByAlias: [String: Double]
        // Carry B9 — quién lo pidió y desde qué hoyo arrancó a contar. Las claves de pareja usan
        // la misma combinación estable de aliases que laneStrokesByOppKey, no laneId.
        // decodeIfPresent con default [:] para no romper archivos bet_config.json guardados antes
        // de que existiera el carry (campos nuevos, JSON viejo no los tiene).
        var individualCarryRequesterByOpponent: [String: String] = [:]
        var individualCarryStartHoleByOpponent: [String: Int] = [:]
        var pairCarryRequesterByOppKey: [String: String] = [:]
        var pairCarryStartHoleByOppKey: [String: Int] = [:]
        // Quién de los dos carga el stroke de pareja — sin esto, effectiveLaneStrokeProfile
        // nunca lo aplicaba (strokeCarrier quedaba nil en cada relanzamiento, aunque el número
        // de strokes sí se hubiera guardado). "los strokes son la base de la apuesta."
        var laneCarrierByOppKey: [String: String] = [:]
        // Ajuste 50 y Doble B9 de pareja — antes no se guardaban en absoluto (solo vivían en
        // pairAdjust50Lanes/pairDoublePressLanes, Set<UUID> en memoria), así que un relanzamiento
        // de la app los perdía siempre, no solo al guardar el Setup.
        var pairAdjust50ByOppKey: [String] = []
        var pairDoublePressByOppKey: [String] = []
        // Roster + campo — sin esto, syncFromScoreManager()/el resto de este snapshot no tienen
        // a quién aplicarse tras matar la app a medio match: players arranca vacío en cada
        // relanzamiento (setupDefaultPlayers), y el replay por alias/nombre no encuentra nada.
        var playerNames: [String] = []
        var courseId: String = ""
        var matchStartHole: Int = 1

        init(activeTemplateId: String?, vueltaValue: Int, presionValue: Int, matchValue: Int, unitValue: Int,
             betValuesByOpponent: [String: OpponentBetValues], baseTeamAliases: [String],
             laneStrokesByOppKey: [String: Double], strokesVsBaseByAlias: [String: Double],
             individualCarryRequesterByOpponent: [String: String], individualCarryStartHoleByOpponent: [String: Int],
             pairCarryRequesterByOppKey: [String: String], pairCarryStartHoleByOppKey: [String: Int],
             laneCarrierByOppKey: [String: String],
             pairAdjust50ByOppKey: [String] = [], pairDoublePressByOppKey: [String] = [],
             playerNames: [String] = [], courseId: String = "", matchStartHole: Int = 1) {
            self.activeTemplateId = activeTemplateId
            self.vueltaValue = vueltaValue
            self.presionValue = presionValue
            self.matchValue = matchValue
            self.unitValue = unitValue
            self.betValuesByOpponent = betValuesByOpponent
            self.baseTeamAliases = baseTeamAliases
            self.laneStrokesByOppKey = laneStrokesByOppKey
            self.strokesVsBaseByAlias = strokesVsBaseByAlias
            self.individualCarryRequesterByOpponent = individualCarryRequesterByOpponent
            self.individualCarryStartHoleByOpponent = individualCarryStartHoleByOpponent
            self.pairCarryRequesterByOppKey = pairCarryRequesterByOppKey
            self.pairCarryStartHoleByOppKey = pairCarryStartHoleByOppKey
            self.laneCarrierByOppKey = laneCarrierByOppKey
            self.pairAdjust50ByOppKey = pairAdjust50ByOppKey
            self.pairDoublePressByOppKey = pairDoublePressByOppKey
            self.playerNames = playerNames
            self.courseId = courseId
            self.matchStartHole = matchStartHole
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            activeTemplateId = try c.decodeIfPresent(String.self, forKey: .activeTemplateId)
            vueltaValue = try c.decode(Int.self, forKey: .vueltaValue)
            presionValue = try c.decode(Int.self, forKey: .presionValue)
            matchValue = try c.decode(Int.self, forKey: .matchValue)
            unitValue = try c.decode(Int.self, forKey: .unitValue)
            betValuesByOpponent = try c.decode([String: OpponentBetValues].self, forKey: .betValuesByOpponent)
            baseTeamAliases = try c.decode([String].self, forKey: .baseTeamAliases)
            laneStrokesByOppKey = try c.decode([String: Double].self, forKey: .laneStrokesByOppKey)
            strokesVsBaseByAlias = try c.decode([String: Double].self, forKey: .strokesVsBaseByAlias)
            individualCarryRequesterByOpponent = try c.decodeIfPresent([String: String].self, forKey: .individualCarryRequesterByOpponent) ?? [:]
            individualCarryStartHoleByOpponent = try c.decodeIfPresent([String: Int].self, forKey: .individualCarryStartHoleByOpponent) ?? [:]
            pairCarryRequesterByOppKey = try c.decodeIfPresent([String: String].self, forKey: .pairCarryRequesterByOppKey) ?? [:]
            pairCarryStartHoleByOppKey = try c.decodeIfPresent([String: Int].self, forKey: .pairCarryStartHoleByOppKey) ?? [:]
            laneCarrierByOppKey = try c.decodeIfPresent([String: String].self, forKey: .laneCarrierByOppKey) ?? [:]
            pairAdjust50ByOppKey = try c.decodeIfPresent([String].self, forKey: .pairAdjust50ByOppKey) ?? []
            pairDoublePressByOppKey = try c.decodeIfPresent([String].self, forKey: .pairDoublePressByOppKey) ?? []
            playerNames = try c.decodeIfPresent([String].self, forKey: .playerNames) ?? []
            courseId = try c.decodeIfPresent(String.self, forKey: .courseId) ?? ""
            matchStartHole = try c.decodeIfPresent(Int.self, forKey: .matchStartHole) ?? 1
        }
    }

    private let betConfigFileName = "bet_config.json"
    private var betConfigURL: URL? {
        let fm = FileManager.default
        let dir = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.comDOG.Caddy-Score")
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
        return dir?.appendingPathComponent(betConfigFileName)
    }

    func saveBetConfig() {
        guard let url = betConfigURL else { return }
        var laneKeys: [String: Double] = [:]
        var laneCarrierKeys: [String: String] = [:]
        for lane in lanes {
            let key = lane.opp.sorted().joined(separator: "+")
            laneKeys[key] = lane.strokes
            if let carrier = lane.strokeCarrier { laneCarrierKeys[key] = carrier }
        }
        var strokesByAlias: [String: Double] = [:]
        for p in players { strokesByAlias[p.alias] = p.strokesVsBase }
        // Carry de pareja vive por laneId (inestable entre reconstrucciones) — se re-mapea a la
        // misma clave estable de aliases que usa laneStrokesByOppKey antes de guardar.
        var pairCarryReqByKey: [String: String] = [:]
        var pairCarryStartByKey: [String: Int] = [:]
        var pairAdjust50Keys: [String] = []
        var pairDoublePressKeys: [String] = []
        for lane in lanes {
            let key = lane.opp.sorted().joined(separator: "+")
            if let req = pairCarryRequesterByLane[lane.id] { pairCarryReqByKey[key] = req }
            if let start = pairCarryStartHoleByLane[lane.id] { pairCarryStartByKey[key] = start }
            if pairAdjust50Lanes.contains(lane.id) { pairAdjust50Keys.append(key) }
            if pairDoublePressLanes.contains(lane.id) { pairDoublePressKeys.append(key) }
        }
        let snapshot = BetConfigSnapshot(
            activeTemplateId: activeTemplateId,
            vueltaValue: vueltaValue, presionValue: presionValue, matchValue: matchValue, unitValue: unitValue,
            betValuesByOpponent: betValuesByOpponent,
            baseTeamAliases: baseTeamAliases,
            laneStrokesByOppKey: laneKeys,
            strokesVsBaseByAlias: strokesByAlias,
            individualCarryRequesterByOpponent: individualCarryRequesterByOpponent,
            individualCarryStartHoleByOpponent: individualCarryStartHoleByOpponent,
            pairCarryRequesterByOppKey: pairCarryReqByKey,
            pairCarryStartHoleByOppKey: pairCarryStartByKey,
            laneCarrierByOppKey: laneCarrierKeys,
            pairAdjust50ByOppKey: pairAdjust50Keys,
            pairDoublePressByOppKey: pairDoublePressKeys,
            playerNames: players.map { $0.name }, courseId: courseId, matchStartHole: startHole
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url)
        } catch {
            print("❌ Error guardando config de apuestas: \(error)")
        }
    }

    func loadBetConfig() {
        guard let url = betConfigURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(BetConfigSnapshot.self, from: data)
            // Restaura roster + campo PRIMERO — todo lo demás (strokes, lanes, carry) se aplica
            // por alias, y players arranca vacío en cada relanzamiento (ver comentario en
            // BetConfigSnapshot). Sin esto, el resto del restore no encuentra a quién aplicarse.
            if players.isEmpty, !snapshot.playerNames.isEmpty {
                if let course = CourseCatalog.all.first(where: { $0.id == snapshot.courseId }) {
                    setCourse(course, resetScores: false)
                }
                startHole = max(1, min(18, snapshot.matchStartHole))
                setPlayers(names: snapshot.playerNames, preserveScores: false)
            }
            activeTemplateId = snapshot.activeTemplateId
            vueltaValue = snapshot.vueltaValue
            presionValue = snapshot.presionValue
            matchValue = snapshot.matchValue
            unitValue = snapshot.unitValue
            betValuesByOpponent = snapshot.betValuesByOpponent
            for (alias, strokes) in snapshot.strokesVsBaseByAlias {
                setStrokesVsBase(alias: alias, value: strokes)
            }
            if snapshot.baseTeamAliases.count >= 2 {
                _ = setBaseTeam(snapshot.baseTeamAliases)
                for lane in lanes {
                    let key = lane.opp.sorted().joined(separator: "+")
                    if let strokes = snapshot.laneStrokesByOppKey[key] {
                        setLaneStrokes(id: lane.id, value: strokes)
                    }
                    if let carrier = snapshot.laneCarrierByOppKey[key] {
                        setLaneCarrier(id: lane.id, carrier: carrier)
                    }
                    if let req = snapshot.pairCarryRequesterByOppKey[key],
                       let start = snapshot.pairCarryStartHoleByOppKey[key] {
                        restorePairCarry(laneId: lane.id, requesterAlias: req, startHole: start)
                    }
                    if snapshot.pairAdjust50ByOppKey.contains(key) { pairAdjust50Lanes.insert(lane.id) }
                    if snapshot.pairDoublePressByOppKey.contains(key) { pairDoublePressLanes.insert(lane.id) }
                }
            }
            for (opp, req) in snapshot.individualCarryRequesterByOpponent {
                if let start = snapshot.individualCarryStartHoleByOpponent[opp] {
                    restoreIndividualCarry(opponentAlias: opp, requesterAlias: req, startHole: start)
                }
            }
            objectWillChange.send()
            // Guardado final: los pasos de arriba (setStrokesVsBase/setLaneStrokes/setLaneCarrier)
            // disparan guardados intermedios a medio restaurar, ANTES de que el carry (este mismo
            // bloque) se restaure — y restoreIndividualCarry/restorePairCarry nunca guardan solos.
            // Sin este guardado final, el archivo se queda con la versión incompleta y el carry
            // nunca sobrevive un segundo relanzamiento.
            saveBetConfig()
            print("✅ Configuración de apuestas cargada desde disco")
        } catch {
            print("❌ Error cargando config de apuestas: \(error)")
        }
    }

    func clearBetConfig() {
        guard let url = betConfigURL else { return }
        try? FileManager.default.removeItem(at: url)
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

    func removeUnitEvent(hole: Int, alias: String, code: String) {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        unitEventsByHole[hole]?.removeAll { $0.alias == alias && $0.code == clean }
        objectWillChange.send()
    }

    func clearOyeRank(hole: Int, alias: String) {
        oyesRanksByHole[hole]?.removeValue(forKey: alias)
        if oyesRanksByHole[hole]?.isEmpty == true { oyesRanksByHole.removeValue(forKey: hole) }
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
        let clamped = max(1, min(18, value))
        let changed = clamped != startHole
        startHole = clamped
        if shouldResetScores {
            resetScores()
        } else if changed {
            // El F9/B9 se recorre completo al mover el hoyo de inicio sin resetear scores (ej.
            // GuidedSetupView.applySetup edita el Setup de una ronda en curso). Cualquier
            // Carry/Ajuste 50/Double Press ya activo quedó calculado sobre el F9 viejo y guarda
            // un startHole absoluto del orden viejo (individualCarryStartHoleByOpponent, etc.) —
            // dejarlo "vivo" aplicaría el carry desde un hoyo que ya no es el inicio de B9, o lo
            // seguiría dando por elegible/inelegible según un F9 que ya no es el que se jugó. Se
            // limpia en vez de dejarlo stale; el usuario lo vuelve a activar si todavía aplica.
            individualCarryRequesterByOpponent.removeAll()
            individualCarryStartHoleByOpponent.removeAll()
            individualDoublePressOpponents.removeAll()
            individualAdjust50Opponents.removeAll()
            pairCarryRequesterByLane.removeAll()
            pairCarryStartHoleByLane.removeAll()
            pairDoublePressLanes.removeAll()
            pairAdjust50Lanes.removeAll()
            pairAdjust50FlipReceiverByLane.removeAll()
            saveBetConfig()
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
        saveBetConfig()
    }

    func setBaseTeam(_ aliases: [String], opponentsOverride: [String]? = nil) -> Bool {
        let baseUnique = uniqueAliases(aliases).filter { a in
            players.contains(where: { $0.alias == a })
        }
        if baseUnique.count < 2 { return false }
        baseTeamAliases = baseUnique
        rebuildLanesFromBase(opponentsOverride: opponentsOverride)
        objectWillChange.send()
        saveBetConfig()
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
        // Antes de reconstruir, preserva TODO el estado por-lane (strokes, quién carga, Carry,
        // Ajuste 50, Doble B9) usando la combinación estable de oponentes como llave — lane.id
        // es un UUID nuevo en cada rebuild, así que sin este paso cualquier llamada a
        // setBaseTeam (ej. guardar el Setup a mitad de ronda sin cambiar la pareja base) huérfana
        // silenciosamente cualquier apuesta de pareja ya activada.
        var strokesByKey: [String: Double] = [:]
        var carrierByKey: [String: String] = [:]
        var carryReqByKey: [String: String] = [:]
        var carryStartByKey: [String: Int] = [:]
        var adjust50Keys: Set<String> = []
        var doublePressKeys: Set<String> = []
        for lane in lanes {
            let key = lane.opp.sorted().joined(separator: "+")
            strokesByKey[key] = lane.strokes
            if let carrier = lane.strokeCarrier { carrierByKey[key] = carrier }
            if let req = pairCarryRequesterByLane[lane.id] { carryReqByKey[key] = req }
            if let start = pairCarryStartHoleByLane[lane.id] { carryStartByKey[key] = start }
            if pairAdjust50Lanes.contains(lane.id) { adjust50Keys.insert(key) }
            if pairDoublePressLanes.contains(lane.id) { doublePressKeys.insert(key) }
        }

        lanes.removeAll()
        pairCarryRequesterByLane.removeAll()
        pairCarryStartHoleByLane.removeAll()
        pairAdjust50Lanes.removeAll()
        pairDoublePressLanes.removeAll()

        let base = baseTeamAliases
        let rawOpp = opponentsOverride ?? players.map { $0.alias }
        let opponents = uniqueAliases(rawOpp).filter { !base.contains($0) }

        func makeLane(opp: [String]) -> LaneModel {
            let key = opp.sorted().joined(separator: "+")
            let lane = LaneModel(id: UUID(), base: base, opp: opp,
                                  strokes: strokesByKey[key] ?? 0,
                                  strokeCarrier: carrierByKey[key])
            if let req = carryReqByKey[key] {
                pairCarryRequesterByLane[lane.id] = req
                pairCarryStartHoleByLane[lane.id] = carryStartByKey[key] ?? firstBackNineHole()
            }
            if adjust50Keys.contains(key) { pairAdjust50Lanes.insert(lane.id) }
            if doublePressKeys.contains(key) { pairDoublePressLanes.insert(lane.id) }
            return lane
        }

        if base.count == 2 {
            if opponents.count == 2 {
                lanes.append(makeLane(opp: opponents))
            } else if opponents.count == 3 {
                let combos = [
                    [opponents[0], opponents[1]],
                    [opponents[0], opponents[2]],
                    [opponents[1], opponents[2]]
                ]
                for opp in combos {
                    lanes.append(makeLane(opp: opp))
                }
            }
            reconcileBetSwitches()
            return
        }
        if base.count == 3 && opponents.count == 2 {
            lanes.append(makeLane(opp: opponents))
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
        betValuesByOpponent = betValuesByOpponent.filter { validOpps.contains($0.key) }

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
        saveBetConfig()
    }

    func setLaneCarrier(id: UUID, carrier: String?) {
        guard let idx = lanes.firstIndex(where: { $0.id == id }) else { return }
        var updated = lanes[idx]
        updated.strokeCarrier = carrier
        lanes[idx] = updated
        objectWillChange.send()
        saveBetConfig()
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
        saveBetConfig()
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
        saveBetConfig()
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

    // Resultado crudo de B9 (no signedUnit) — quien gana este segmento es quien mueve el
    // strokeVsBase del rival para el próximo match (regla 2026-10-06, ver ContentView.cerrarRonda).
    func individualB9Vuelta(opponentAlias: String) -> Int {
        b9VueltaVsOpponent(opponentAlias: opponentAlias)
    }

    // Conteo de hoyos ganados/perdidos de B9 (no el neto de vuelta) — lo usa el carry entre
    // rondas cuando Ajuste 50 estuvo activo, para aplicar la misma fórmula de medio golpe por
    // hoyo que usa individualAdjust50Profile dentro de la ronda, pero proyectada hacia la
    // próxima ronda (como si el B9 recién jugado fuera el F9 de un ajuste nuevo).
    func individualB9WinLossCount(opponentAlias: String) -> (wins: Int, losses: Int) {
        let b9 = Array(playOrder().suffix(9))
        let values = b9.compactMap { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: nil) }
        return (values.filter { $0 > 0 }.count, values.filter { $0 < 0 }.count)
    }

    // Cada presión lleva su valor propio (CAMBIOS_CADDIE_v2.md #5: "5 3 1", nunca un conteo
    // colapsado "2 presiones"). Se lee directo de pressureStates — la MISMA fuente que
    // pressureNet() usa para el dinero real dentro de walletSnapshot() (cálculo congelado, no
    // se tocó) — solo que aquí se expone el array completo en vez de colapsarlo a un neto.
    func individualF9Presion(opponentAlias: String) -> [Int] {
        let order = playOrder()
        let f9 = Array(order.prefix(9))
        let values = f9.map { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: nil) }
        return pressureValues(values: values, threshold: 2)
    }

    func individualB9Presion(opponentAlias: String) -> [Int] {
        let order = playOrder()
        let b9 = Array(order.suffix(9))
        let values = b9.map { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: nil) }
        return pressureValues(values: values, threshold: 2)
    }

    func setIndividualCarryRequest(opponentAlias: String, requesterAlias: String?) {
        guard players.contains(where: { $0.alias == opponentAlias }) else { return }
        guard opponentAlias != yoAlias else { return }
        if requesterAlias == nil {
            individualCarryRequesterByOpponent.removeValue(forKey: opponentAlias)
            individualCarryStartHoleByOpponent.removeValue(forKey: opponentAlias)
            objectWillChange.send()
            saveBetConfig()
            return
        }
        guard let eligible = individualCarryEligibleRequester(opponentAlias: opponentAlias),
              eligible == requesterAlias else { return }
        // Mutuamente excluyente con Ajuste 50 para el mismo rival (SSOT Sección 7).
        guard !isIndividualAdjust50Active(opponentAlias: opponentAlias) else { return }
        individualCarryRequesterByOpponent[opponentAlias] = eligible
        individualCarryStartHoleByOpponent[opponentAlias] = carryStartHoleForB9()
        objectWillChange.send()
        saveBetConfig()
    }

    func clearIndividualCarryRequest(opponentAlias: String) {
        setIndividualCarryRequest(opponentAlias: opponentAlias, requesterAlias: nil)
    }

    // Restaura un carry ya guardado en disco, preservando el startHole exacto de cuando se pidió
    // — a diferencia de setIndividualCarryRequest, que SIEMPRE recalcula carryStartHoleForB9()
    // (correcto al pedirlo por primera vez, incorrecto al recargar: el juego ya avanzó más hoyos
    // de los que había al momento original de la activación).
    private func restoreIndividualCarry(opponentAlias: String, requesterAlias: String, startHole: Int) {
        guard let eligible = individualCarryEligibleRequester(opponentAlias: opponentAlias),
              eligible == requesterAlias else { return }
        individualCarryRequesterByOpponent[opponentAlias] = requesterAlias
        individualCarryStartHoleByOpponent[opponentAlias] = startHole
    }

    func isIndividualCarryActive(opponentAlias: String) -> Bool {
        guard let requester = individualCarryRequesterByOpponent[opponentAlias],
              let eligible = individualCarryEligibleRequester(opponentAlias: opponentAlias) else { return false }
        return requester == eligible
    }

    // MARK: Double Press (individual) — mismo botón/elegibilidad que Carry (quien perdió el F9),
    // pero solo duplica dinero de Vuelta+Presión en B9 (ver walletSnapshot). No asigna stroke.
    func setIndividualDoublePress(opponentAlias: String, active: Bool) {
        guard individualCarryEligibleRequester(opponentAlias: opponentAlias) != nil else { return }
        if active { individualDoublePressOpponents.insert(opponentAlias) }
        else { individualDoublePressOpponents.remove(opponentAlias) }
        objectWillChange.send()
        saveBetConfig()
    }

    func isIndividualDoublePressActive(opponentAlias: String) -> Bool {
        individualDoublePressOpponents.contains(opponentAlias)
    }

    // MARK: Ajuste 50 (individual) — mutuamente excluyente con Carry para el mismo rival
    // (SSOT Sección 7). Redefine los strokes de B9 según el resultado del F9: 50% de los hoyos
    // ganados se resta, 50% de los hoyos perdidos se suma, sobre el stroke normal de B9 de quien
    // ya recibía strokes en el convenio base — puede incluso invertir quién lo recibe.
    func setIndividualAdjust50(opponentAlias: String, active: Bool) {
        guard individualCarryEligibleRequester(opponentAlias: opponentAlias) != nil else { return }
        if active {
            guard !isIndividualCarryActive(opponentAlias: opponentAlias) else { return }
            individualAdjust50Opponents.insert(opponentAlias)
        } else {
            individualAdjust50Opponents.remove(opponentAlias)
        }
        objectWillChange.send()
        saveBetConfig()
    }

    func isIndividualAdjust50Active(opponentAlias: String) -> Bool {
        individualAdjust50Opponents.contains(opponentAlias)
    }

    // Strokes normales de B9 (sin Carry ni Ajuste 50) para yo/oponente — suma del reparto
    // normal por Stroke Index sobre los 9 hoyos de B9, antes de cualquier ajuste.
    private func normalB9StrokeTotal(opponentAlias: String) -> (yo: Double, opp: Double) {
        let b9 = Array(playOrder().suffix(9))
        return b9.reduce((0.0, 0.0)) { acc, h in
            let s = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: h, carryAlias: nil)
            return (acc.0 + s.yo, acc.1 + s.opp)
        }
    }

    private func f9WinLossCount(opponentAlias: String) -> (wins: Int, losses: Int) {
        let f9 = Array(playOrder().prefix(9))
        let values = f9.compactMap { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: nil) }
        return (values.filter { $0 > 0 }.count, values.filter { $0 < 0 }.count)
    }

    // Perfil efectivo de Ajuste 50 para B9: quién recibe el stroke ajustado y cuánto. Puede ser
    // la misma persona que recibía normalmente (con más o menos strokes) o cambiar de lado si el
    // ajuste "se pasa" del monto normal (mismo patrón de inversión que effectiveLaneStrokeProfile).
    func individualAdjust50Profile(opponentAlias: String) -> (receiver: String?, amount: Double) {
        let (yoNormal, oppNormal) = normalB9StrokeTotal(opponentAlias: opponentAlias)
        guard yoNormal > 0.001 || oppNormal > 0.001 else { return (nil, 0) }
        let receiverIsYo = yoNormal > 0.001
        let receiverAlias = receiverIsYo ? yoAlias : opponentAlias
        let normalAmount = receiverIsYo ? yoNormal : oppNormal

        let (yoWins, yoLosses) = f9WinLossCount(opponentAlias: opponentAlias)
        let receiverWins = receiverIsYo ? yoWins : yoLosses
        let receiverLosses = receiverIsYo ? yoLosses : yoWins

        let delta: Double
        if receiverWins > receiverLosses { delta = -0.5 * Double(receiverWins) }
        else if receiverLosses > receiverWins { delta = 0.5 * Double(receiverLosses) }
        else { delta = 0 }

        let adjusted = normalAmount + delta
        if adjusted > 0.001 {
            return (receiverAlias, adjusted)
        } else if adjusted < -0.001 {
            return (receiverIsYo ? opponentAlias : yoAlias, -adjusted)
        }
        return (nil, 0)
    }

    // Stroke efectivo de Ajuste 50 para UN jugador en UN hoyo de B9 — repartido por Stroke
    // Index pero solo entre los 9 hoyos de B9 (ver distributedStrokesWithinHoles).
    func individualAdjust50ExtraStroke(opponentAlias: String, alias: String, hole: Int) -> Double {
        guard isIndividualAdjust50Active(opponentAlias: opponentAlias),
              segmentForHole(hole) == "B9" else { return 0 }
        let profile = individualAdjust50Profile(opponentAlias: opponentAlias)
        guard profile.receiver == alias, profile.amount > 0.001 else { return 0 }
        let b9 = Array(playOrder().suffix(9))
        return distributedStrokesWithinHoles(total: profile.amount, hole: hole, holes: b9)
    }

    private func fmtStroke(_ v: Double) -> String {
        let whole = Int(v)
        if abs(v - Double(whole)) < 0.01 { return "\(whole)" }
        return String(format: "%.1f", v)
    }

    private func normalF9StrokeTotal(opponentAlias: String) -> (yo: Double, opp: Double) {
        let f9 = Array(playOrder().prefix(9))
        return f9.reduce((0.0, 0.0)) { acc, h in
            let s = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: h, carryAlias: nil)
            return (acc.0 + s.yo, acc.1 + s.opp)
        }
    }

    // Línea de texto lista para mostrar en la tarjeta: a quién le toca el stroke, cuánto en F9,
    // y cuánto en B9 — incluyendo qué mecanismo (Carry/Ajuste 50) está modificando el B9, si alguno.
    // nil si nadie recibe strokes en este matchup.
    // Formato compacto: "{convenio}/{segmento}" para F9 y B9. En B9, si hay Carry activo se
    // agrega "C{puntos}" (resultado del Carry); si hay Ajuste 50 activo se agrega un tercer
    // número "/{efectivo}A" en vez del normal. Convenio = lo acordado para 18 hoyos completos.
    func individualStrokeSummaryLine(opponentAlias: String) -> String? {
        let (f9Yo, f9Opp) = normalF9StrokeTotal(opponentAlias: opponentAlias)
        let (b9Yo, b9Opp) = normalB9StrokeTotal(opponentAlias: opponentAlias)
        guard f9Yo > 0.001 || f9Opp > 0.001 || b9Yo > 0.001 || b9Opp > 0.001 else { return nil }
        let receiverIsYo = b9Yo > 0.001 || f9Yo > 0.001
        let alias = receiverIsYo ? yoAlias : opponentAlias
        let f9Value = receiverIsYo ? f9Yo : f9Opp
        let normalB9 = receiverIsYo ? b9Yo : b9Opp
        let convenio = abs(playerStrokes(alias: alias))
        let f9Part = "F9 \(fmtStroke(convenio))/\(fmtStroke(f9Value))"

        if isIndividualAdjust50Active(opponentAlias: opponentAlias) {
            let profile = individualAdjust50Profile(opponentAlias: opponentAlias)
            let whoSuffix = (profile.receiver != nil && profile.receiver != alias) ? " → \(profile.receiver!)" : ""
            return "\(alias) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalB9))/\(fmtStroke(profile.amount))A\(whoSuffix)"
        }
        if isIndividualCarryActive(opponentAlias: opponentAlias), let carryAlias = individualCarryRequesterByOpponent[opponentAlias] {
            let normalForCarrier = carryAlias == yoAlias ? b9Yo : b9Opp
            let carryPts = individualCarryResultB9(opponentAlias: opponentAlias)
            let cLabel = carryPts >= 0 ? "+\(carryPts)" : "\(carryPts)"
            return "\(carryAlias) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalForCarrier)) C\(cLabel)"
        }
        return "\(alias) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalB9))"
    }

    // Resultado hoyo por hoyo en B9 REEMPLAZANDO (no sumando) el stroke normal del receptor por
    // el stroke de Ajuste 50 — a diferencia de Carry (aditivo), Ajuste 50 sustituye el convenio
    // base de ese segmento (SSOT Sección 7: Carry y Ajuste son mutuamente excluyentes).
    private func holeResultVsYoAdjust50(opponentAlias: String, hole: Int, receiver: String?, amount: Double) -> Int? {
        let yoGross = getScore(hole: hole, player: yoAlias)
        let oppGross = getScore(hole: hole, player: opponentAlias)
        if yoGross <= 0 || oppGross <= 0 { return nil }
        var strokes = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: hole, carryAlias: nil)
        if segmentForHole(hole) == "B9" {
            strokes = (0, 0)
            if let receiver, amount > 0.001 {
                let b9 = Array(playOrder().suffix(9))
                let amt = distributedStrokesWithinHoles(total: amount, hole: hole, holes: b9)
                if receiver == yoAlias { strokes.yo = amt }
                else if receiver == opponentAlias { strokes.opp = amt }
            }
        }
        let yoNet = Double(yoGross) - strokes.yo
        let oppNet = Double(oppGross) - strokes.opp
        return compareNet(a: yoNet, b: oppNet)
    }

    // Resultado de la apuesta Ajuste 50 en B9 (solo si está activa) — categoría de wallet
    // independiente, igual patrón que individualCarryResultB9.
    func individualAdjust50ResultB9(opponentAlias: String) -> Int {
        guard isIndividualAdjust50Active(opponentAlias: opponentAlias) else { return 0 }
        let profile = individualAdjust50Profile(opponentAlias: opponentAlias)
        let b9 = Array(playOrder().suffix(9))
        return b9.compactMap { holeResultVsYoAdjust50(opponentAlias: opponentAlias, hole: $0, receiver: profile.receiver, amount: profile.amount) }.reduce(0, +)
    }

    func pairCarryEligibleRequester(laneId: UUID) -> String? {
        pairCarryEligibleTeam(laneId: laneId).first
    }

    // Todo el lado que perdió el F9 (no solo el primero de la lista) — para que la UI pueda
    // ofrecer un selector entre los 1-2 compañeros de ese lado en vez de asumir siempre al
    // primero. setPairCarryRequest ya solo exige que el requester sea de este lado, así que
    // asignarle el Carry a cualquiera de estos aliases es válido.
    func pairCarryEligibleTeam(laneId: UUID) -> [String] {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return [] }
        let f9 = pairF9Vuelta(lane: lane)
        if f9 == 0 { return [] }
        return f9 > 0 ? lane.opp : lane.base
    }

    func setPairCarryRequest(laneId: UUID, requesterAlias: String?) {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return }
        if requesterAlias == nil {
            pairCarryRequesterByLane.removeValue(forKey: laneId)
            pairCarryStartHoleByLane.removeValue(forKey: laneId)
            objectWillChange.send()
            saveBetConfig()
            return
        }
        guard let req = requesterAlias,
              let eligible = pairCarryEligibleRequester(laneId: laneId) else { return }
        let reqInBase = lane.base.contains(req)
        let reqInOpp = lane.opp.contains(req)
        guard reqInBase || reqInOpp else { return }
        let eligibleInBase = lane.base.contains(eligible)
        let eligibleInOpp = lane.opp.contains(eligible)
        // Mutuamente excluyente con Ajuste 50 para la misma pareja (SSOT Sección 7).
        guard !isPairAdjust50Active(laneId: laneId) else { return }
        if (reqInBase && eligibleInBase) || (reqInOpp && eligibleInOpp) {
            pairCarryRequesterByLane[laneId] = req
            pairCarryStartHoleByLane[laneId] = carryStartHoleForB9()
            objectWillChange.send()
            saveBetConfig()
        }
    }

    func clearPairCarryRequest(laneId: UUID) {
        setPairCarryRequest(laneId: laneId, requesterAlias: nil)
    }

    // Stroke extra (+1) que el carry agrega para UN jugador aislado en UN hoyo — lo usa la
    // tarjeta hoyo-por-hoyo (holeDetailCard en ContentView), que muestra golpes crudos por
    // jugador, no el neto de un matchup. Mismo criterio que individualMatchupStrokes
    // (B9 + desde el hoyo de activación + solo el que pidió el carry).
    func individualCarryExtraStroke(opponentAlias: String, alias: String, hole: Int) -> Double {
        guard isIndividualCarryActive(opponentAlias: opponentAlias),
              let requester = individualCarryRequesterByOpponent[opponentAlias], requester == alias,
              segmentForHole(hole) == "B9" else { return 0 }
        let start = individualCarryStartHoleByOpponent[opponentAlias] ?? firstBackNineHole()
        let order = playOrder()
        guard let hIdx = order.firstIndex(of: hole), let startIdx = order.firstIndex(of: start) else { return 0 }
        return hIdx >= startIdx ? 1 : 0
    }

    func pairCarryExtraStroke(laneId: UUID, alias: String, hole: Int) -> Double {
        guard isPairCarryActive(laneId: laneId),
              let requester = pairCarryRequesterByLane[laneId], requester == alias,
              segmentForHole(hole) == "B9" else { return 0 }
        let start = pairCarryStartHoleByLane[laneId] ?? firstBackNineHole()
        let order = playOrder()
        guard let hIdx = order.firstIndex(of: hole), let startIdx = order.firstIndex(of: start) else { return 0 }
        return hIdx >= startIdx ? 1 : 0
    }

    // Mismo motivo que restoreIndividualCarry: preserva el startHole guardado en vez de
    // recalcularlo con el progreso actual del juego.
    private func restorePairCarry(laneId: UUID, requesterAlias: String, startHole: Int) {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              let eligible = pairCarryEligibleRequester(laneId: laneId) else { return }
        let reqInBase = lane.base.contains(requesterAlias)
        let reqInOpp = lane.opp.contains(requesterAlias)
        let eligibleInBase = lane.base.contains(eligible)
        let eligibleInOpp = lane.opp.contains(eligible)
        guard (reqInBase && eligibleInBase) || (reqInOpp && eligibleInOpp) else { return }
        pairCarryRequesterByLane[laneId] = requesterAlias
        pairCarryStartHoleByLane[laneId] = startHole
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

    // MARK: Double Press (pareja) — mismo criterio que individual.
    func setPairDoublePress(laneId: UUID, active: Bool) {
        guard pairCarryEligibleRequester(laneId: laneId) != nil else { return }
        if active { pairDoublePressLanes.insert(laneId) }
        else { pairDoublePressLanes.remove(laneId) }
        objectWillChange.send()
        saveBetConfig()
    }

    func isPairDoublePressActive(laneId: UUID) -> Bool {
        pairDoublePressLanes.contains(laneId)
    }

    // MARK: Ajuste 50 (pareja) — mismo criterio que individual, usando el stroke base de la
    // pareja (lane.strokes/strokeCarrier, vía effectiveLaneStrokeProfile) y el resultado F9 de
    // la pareja completa. Mutuamente excluyente con Carry para la misma pareja.
    func setPairAdjust50(laneId: UUID, active: Bool) {
        guard pairCarryEligibleRequester(laneId: laneId) != nil else { return }
        if active {
            guard !isPairCarryActive(laneId: laneId) else { return }
            pairAdjust50Lanes.insert(laneId)
        } else {
            pairAdjust50Lanes.remove(laneId)
        }
        objectWillChange.send()
        saveBetConfig()
    }

    func isPairAdjust50Active(laneId: UUID) -> Bool {
        pairAdjust50Lanes.contains(laneId)
    }

    private func f9WinLossCountPair(lane: LaneModel) -> (wins: Int, losses: Int) {
        let f9 = Array(playOrder().prefix(9))
        let values = f9.compactMap { pairResult(hole: $0, lane: lane) }
        return (values.filter { $0 > 0 }.count, values.filter { $0 < 0 }.count)
    }

    // Cálculo compartido de Ajuste 50 (pareja) sin decidir todavía QUIÉN recibe en caso de
    // inversión — eso lo resuelven pairAdjust50FlipCandidates/pairAdjust50Profile por separado,
    // para que la UI pueda preguntar "¿hay que elegir?" antes de forzar un default.
    private func pairAdjust50RawProfile(laneId: UUID) -> (receiverInBase: Bool, normalCarrier: String, adjusted: Double)? {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return nil }
        let normal = effectiveLaneStrokeProfile(lane: lane, carryRequesterAlias: nil)
        guard let normalCarrier = normal.carrier, normal.total > 0.001 else { return nil }
        let receiverInBase = lane.base.contains(normalCarrier)

        // El total normal de Ajuste 50 es solo la porción de B9 del convenio (igual criterio
        // que individualAdjust50/normalB9StrokeTotal) — normal.total es el convenio COMPLETO de
        // 18 hoyos, no la porción de B9; usarlo directo aquí era el bug.
        let b9 = Array(playOrder().suffix(9))
        let normalB9Total = b9.reduce(0.0) { $0 + laneCarrierStroke(lane: lane, alias: normalCarrier, hole: $1) }

        let (baseWins, baseLosses) = f9WinLossCountPair(lane: lane)
        let receiverWins = receiverInBase ? baseWins : baseLosses
        let receiverLosses = receiverInBase ? baseLosses : baseWins

        let delta: Double
        if receiverWins > receiverLosses { delta = -0.5 * Double(receiverWins) }
        else if receiverLosses > receiverWins { delta = 0.5 * Double(receiverLosses) }
        else { delta = 0 }

        return (receiverInBase, normalCarrier, normalB9Total + delta)
    }

    // Candidatos a elegir cuando Ajuste 50 se invierte de lado Y ese lado tiene 2 compañeros —
    // vacío si no hay inversión o si el lado solo tiene 1 jugador (no hay nada que elegir).
    func pairAdjust50FlipCandidates(laneId: UUID) -> [String] {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              let raw = pairAdjust50RawProfile(laneId: laneId),
              raw.adjusted < -0.001 else { return [] }
        let otherSide = raw.receiverInBase ? lane.opp : lane.base
        return otherSide.count > 1 ? otherSide : []
    }

    func setPairAdjust50FlipReceiver(laneId: UUID, alias: String) {
        guard pairAdjust50FlipCandidates(laneId: laneId).contains(alias) else { return }
        pairAdjust50FlipReceiverByLane[laneId] = alias
        objectWillChange.send()
        saveBetConfig()
    }

    func pairAdjust50Profile(laneId: UUID) -> (receiver: String?, amount: Double) {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              let raw = pairAdjust50RawProfile(laneId: laneId) else { return (nil, 0) }
        if raw.adjusted > 0.001 {
            return (raw.normalCarrier, raw.adjusted)
        } else if raw.adjusted < -0.001 {
            let otherSide = raw.receiverInBase ? lane.opp : lane.base
            let stored = pairAdjust50FlipReceiverByLane[laneId]
            let chosen = (stored != nil && otherSide.contains(stored!)) ? stored : otherSide.first
            return (chosen, -raw.adjusted)
        }
        return (nil, 0)
    }

    func pairAdjust50ExtraStroke(laneId: UUID, alias: String, hole: Int) -> Double {
        guard isPairAdjust50Active(laneId: laneId),
              segmentForHole(hole) == "B9" else { return 0 }
        let profile = pairAdjust50Profile(laneId: laneId)
        guard profile.receiver == alias, profile.amount > 0.001 else { return 0 }
        let b9 = Array(playOrder().suffix(9))
        return distributedStrokesWithinHoles(total: profile.amount, hole: hole, holes: b9)
    }

    // Misma línea de resumen que individualStrokeSummaryLine, para pareja — usa el carrier
    // normal de la pareja (lane.strokeCarrier) como base del F9. Si el Carry lo pidió un
    // compañero distinto al carrier normal (selector de pareja), esta línea sigue describiendo
    // al carrier normal; no se desdobla en dos líneas todavía.
    // Mismo formato compacto que individualStrokeSummaryLine — ver esa función para el
    // significado de "{convenio}/{segmento}", "C{puntos}" y "/{efectivo}A".
    func pairStrokeSummaryLine(laneId: UUID) -> String? {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return nil }
        let normal = effectiveLaneStrokeProfile(lane: lane, carryRequesterAlias: nil)
        guard let carrier = normal.carrier, normal.total > 0.001 else { return nil }
        let f9 = Array(playOrder().prefix(9))
        let b9 = Array(playOrder().suffix(9))
        let f9Value = f9.reduce(0.0) { $0 + laneCarrierStroke(lane: lane, alias: carrier, hole: $1) }
        let normalB9 = b9.reduce(0.0) { $0 + laneCarrierStroke(lane: lane, alias: carrier, hole: $1) }
        let convenio = lane.strokes
        let f9Part = "F9 \(fmtStroke(convenio))/\(fmtStroke(f9Value))"

        if isPairAdjust50Active(laneId: laneId) {
            let profile = pairAdjust50Profile(laneId: laneId)
            let whoSuffix = (profile.receiver != nil && profile.receiver != carrier) ? " → \(profile.receiver!)" : ""
            let amount = profile.amount
            return "\(carrier) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalB9))/\(fmtStroke(amount))A\(whoSuffix)"
        }
        if isPairCarryActive(laneId: laneId), let carryAlias = pairCarryRequesterByLane[laneId] {
            let carryPts = pairCarryResultB9(laneId: laneId)
            let cLabel = carryPts >= 0 ? "+\(carryPts)" : "\(carryPts)"
            return "\(carryAlias) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalB9)) C\(cLabel)"
        }
        return "\(carrier) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalB9))"
    }

    // Mismo patrón que pairResult/pairNets (mejor-bola: compara la peor bola de cada lado y la
    // mejor bola de cada lado, suma los dos resultados), pero reemplazando el stroke de pareja
    // normal por el de Ajuste 50 en B9 — autocontenida, no toca pairResult/pairNets/laneCarrierStroke.
    private func pairResultAdjust50(hole: Int, lane: LaneModel, receiver: String?, amount: Double) -> Int? {
        guard segmentForHole(hole) == "B9" else {
            return pairResult(hole: hole, lane: lane)
        }
        let b9 = Array(playOrder().suffix(9))
        let adjustedStroke: Double = (receiver != nil && amount > 0.001)
            ? distributedStrokesWithinHoles(total: amount, hole: hole, holes: b9) : 0

        func netsFor(_ aliases: [String]) -> [Double] {
            var nets: [Double] = []
            for alias in aliases {
                let gross = getScore(hole: hole, player: alias)
                if gross <= 0 { continue }
                let stroke = (alias == receiver) ? adjustedStroke : 0
                nets.append(Double(gross) - stroke)
            }
            return nets.sorted()
        }

        let baseNets = netsFor(lane.base)
        let oppNets = netsFor(lane.opp)
        if baseNets.count < 2 || oppNets.count < 2 { return nil }
        let minResult = compareNet(a: baseNets[0], b: oppNets[0])
        let maxResult = compareNet(a: baseNets[1], b: oppNets[1])
        return minResult + maxResult
    }

    // Resultado de la apuesta Ajuste 50 en B9 (solo si está activa) — categoría de wallet
    // independiente, igual patrón que pairCarryResultB9.
    func pairAdjust50ResultB9(laneId: UUID) -> Int {
        guard isPairAdjust50Active(laneId: laneId), let lane = lanes.first(where: { $0.id == laneId }) else { return 0 }
        let profile = pairAdjust50Profile(laneId: laneId)
        let b9 = Array(playOrder().suffix(9))
        return b9.compactMap { pairResultAdjust50(hole: $0, lane: lane, receiver: profile.receiver, amount: profile.amount) }.reduce(0, +)
    }

    func pairCarryResultB9(laneId: UUID) -> Int {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              isPairCarryActive(laneId: laneId),
              let requester = pairCarryRequesterByLane[laneId] else { return 0 }
        let startHole = pairCarryStartHoleByLane[laneId] ?? firstBackNineHole()
        return pairCarryComputedB9(lane: lane, requesterAlias: requester, startHole: startHole)
    }

    // Mismo resultado que pairCarryResultB9, hoyo por hoyo — ver individualCarryResultSeries.
    func pairCarryResultSeries(laneId: UUID) -> [Int] {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              isPairCarryActive(laneId: laneId),
              let requester = pairCarryRequesterByLane[laneId] else { return [] }
        let startHole = pairCarryStartHoleByLane[laneId] ?? firstBackNineHole()
        let order = playOrder()
        let b9 = Array(order.suffix(9))
        guard let startIdx = b9.firstIndex(of: startHole) else { return [] }
        return Array(b9[startIdx...]).compactMap { pairResult(hole: $0, lane: lane, carryRequesterAlias: requester) }
    }

    // Ver individualCarryDivergesAtHole — mismo criterio para pareja.
    func pairCarryDivergesAtHole(laneId: UUID, hole: Int) -> Bool {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              isPairCarryActive(laneId: laneId),
              let requester = pairCarryRequesterByLane[laneId],
              segmentForHole(hole) == "B9" else { return false }
        guard let withCarry = pairResult(hole: hole, lane: lane, carryRequesterAlias: requester),
              let withoutCarry = pairResult(hole: hole, lane: lane) else { return false }
        return withCarry != withoutCarry
    }

    func pairF9Vuelta(laneId: UUID) -> Int {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return 0 }
        return pairF9Vuelta(lane: lane)
    }

    // Cada presión con su propio valor (CAMBIOS_CADDIE_v2.md #5). Mismo threshold que
    // walletSnapshot() usa para parejas: 3. Siempre desde la perspectiva de lane.base — el
    // caller invierte el signo de cada valor si yo estoy del lado opp.
    func pairF9Presion(laneId: UUID) -> [Int] {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return [] }
        let order = playOrder()
        let f9 = Array(order.prefix(9))
        let values = f9.map { pairResult(hole: $0, lane: lane) }
        return pressureValues(values: values, threshold: 3)
    }

    func pairB9Presion(laneId: UUID) -> [Int] {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return [] }
        let order = playOrder()
        let b9 = Array(order.suffix(9))
        let values = b9.map { pairResult(hole: $0, lane: lane) }
        return pressureValues(values: values, threshold: 3)
    }

    // Valores de presión acumulados hoyo por hoyo (una entrada por hoyo de `holes`, en el mismo
    // orden) — para la columna "Acum" del Zoom, que audita vuelta+presión fila por fila.
    func individualPresionSeries(opponentAlias: String, holes: [Int]) -> [[Int]] {
        let values = holes.map { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: nil) }
        guard !values.isEmpty else { return [] }
        return (1...values.count).map { pressureValues(values: Array(values.prefix($0)), threshold: 2) }
    }

    func pairPresionSeries(laneId: UUID, holes: [Int]) -> [[Int]] {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return [] }
        let values = holes.map { pairResult(hole: $0, lane: lane) }
        guard !values.isEmpty else { return [] }
        return (1...values.count).map { pressureValues(values: Array(values.prefix($0)), threshold: 3) }
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
            let adjust50Pts = individualAdjust50ResultB9(opponentAlias: opp)
            let adjust50Active = isIndividualAdjust50Active(opponentAlias: opp)
            let doublePressActive = isIndividualDoublePressActive(opponentAlias: opp)
            let unitsPts = unitStakeForIndividual(opponentAlias: opp, segmentOverride: "F9")
                + unitStakeForIndividual(opponentAlias: opp, segmentOverride: "B9")

            let vPts = switches.vuelta ? vueltaPts : 0
            let pPts = switches.presion ? presionPts : 0
            let cPts = (switches.carry && carryActive) ? carryPts : 0
            let aPts = (switches.adjust50 && adjust50Active) ? adjust50Pts : 0
            let mPts = switches.match ? matchPts : 0
            let uPts = switches.units ? unitsPts : 0

            // Cada oponente usa su propia plantilla/valor — no el global de la ronda (ese es solo para parejas).
            let ov = betValues(forOpponent: opp)
            // Double Press solo duplica el dinero de Vuelta y Presión en B9 (no Match, no strokes,
            // no F9) — el resultado deportivo (vPts/pPts) no cambia, solo la monetización.
            let dpMultiplier = doublePressActive ? 2 : 1

            // Regla "F9 vuelta = 0" (empate, 2026-10-06): Carry/Ajuste/Double Press ya quedan
            // bloqueados en su elegibilidad (individualCarryEligibleRequester retorna nil), así
            // que aquí solo cambia la liquidación. B9 (vuelta + presión) y Match se funden en un
            // solo precio combinado — suma de vueltaValue + presionValue + matchValue de la
            // plantilla — aplicado a cada unidad ganada (vuelta cuenta 1, cada presión de B9
            // cuenta 1 más, sin importar su valor nominal). El Match no liquida aparte, queda
            // absorbido en ese precio combinado. La presión de F9 ya cerró como segmento
            // independiente (ST-06 del SSOT) y se sigue cobrando normal, sin tocar. Solo aplica
            // si las tres apuestas (vuelta/presión/match) están activas a la vez para este rival;
            // si el usuario las separó manualmente, se usa el cálculo normal de abajo.
            let f9Tied = f9V == 0 && switches.vuelta && switches.presion && switches.match
            let vMoney: Int
            let pMoney: Int
            let mMoney: Int
            if f9Tied {
                let bundledPrice = ov.vueltaValue + ov.presionValue + ov.matchValue
                let bundledUnits = signedUnit(b9V) + b9P
                vMoney = bundledUnits * bundledPrice
                pMoney = f9P * ov.presionValue
                mMoney = 0
            } else {
                vMoney = switches.vuelta
                    ? signedUnit(f9V) * ov.vueltaValue + signedUnit(b9V) * ov.vueltaValue * dpMultiplier
                    : 0
                pMoney = switches.presion
                    ? f9P * ov.presionValue + b9P * ov.presionValue * dpMultiplier
                    : 0
                mMoney = switches.match ? mPts * ov.matchValue : 0
            }
            let cMoney = cPts * ov.vueltaValue
            let aMoney = aPts * ov.vueltaValue
            let uMoney = uPts * ov.unitValue
            let total = vMoney + pMoney + cMoney + aMoney + mMoney + uMoney
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
                    adjust50Points: aPts,
                    adjust50Active: adjust50Active,
                    doublePressActive: doublePressActive,
                    matchPoints: mPts,
                    unitsPoints: uPts,
                    vueltaMoney: vMoney,
                    presionMoney: pMoney,
                    carryMoney: cMoney,
                    adjust50Money: aMoney,
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
            let adjust50Pts = pairAdjust50ResultB9(laneId: lane.id)
            let adjust50Active = isPairAdjust50Active(laneId: lane.id)
            let doublePressActive = isPairDoublePressActive(laneId: lane.id)
            let unitsPts = unitStakeForPair(laneId: lane.id, segmentOverride: "F9")
                + unitStakeForPair(laneId: lane.id, segmentOverride: "B9")

            let vPts = switches.vuelta ? vueltaPts : 0
            let pPts = switches.presion ? presionPts : 0
            let cPts = (switches.carry && carryActive) ? carryPts : 0
            let aPts = (switches.adjust50 && adjust50Active) ? adjust50Pts : 0
            let mPts = switches.match ? matchPts : 0
            let uPts = switches.units ? unitsPts : 0

            let dpMultiplier = doublePressActive ? 2 : 1
            let vMoney = switches.vuelta
                ? signedUnit(f9V) * vueltaValue + signedUnit(b9V) * vueltaValue * dpMultiplier
                : 0
            let pMoney = switches.presion
                ? f9P * presionValue + b9P * presionValue * dpMultiplier
                : 0
            let cMoney = cPts * vueltaValue
            let aMoney = aPts * vueltaValue
            let mMoney = mPts * matchValue
            let uMoney = uPts * unitValue
            let total = vMoney + pMoney + cMoney + aMoney + mMoney + uMoney
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
                    adjust50Points: aPts,
                    adjust50Active: adjust50Active,
                    doublePressActive: doublePressActive,
                    matchPoints: mPts,
                    unitsPoints: uPts,
                    vueltaMoney: vMoney,
                    presionMoney: pMoney,
                    carryMoney: cMoney,
                    adjust50Money: aMoney,
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

    // Mismo resultado que individualCarryResultB9, pero hoyo por hoyo en vez de colapsado en un
    // solo número — mismo criterio que Presión (nunca un neto colapsado, CAMBIOS_CADDIE_v2.md
    // #5), para poder auditar de qué hoyos sale el total en una discusión.
    func individualCarryResultSeries(opponentAlias: String) -> [Int] {
        guard isIndividualCarryActive(opponentAlias: opponentAlias),
              let carryAlias = individualCarryRequesterByOpponent[opponentAlias] else { return [] }
        let startHole = individualCarryStartHoleByOpponent[opponentAlias] ?? firstBackNineHole()
        let order = playOrder()
        let b9 = Array(order.suffix(9))
        guard let startIdx = b9.firstIndex(of: startHole) else { return [] }
        return Array(b9[startIdx...]).compactMap { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: carryAlias) }
    }

    // ¿El Carry realmente cambia quién gana ESTE hoyo, comparado con el resultado sin Carry?
    // El stroke extra aplica mecánicamente en todos los hoyos de B9 desde la activación, pero
    // la mayoría de las veces no cambia el resultado (el jugador ya ganaba/perdía igual). La
    // simbología "C" en la tarjeta debe aparecer solo donde SÍ cambia algo — no en cada hoyo.
    func individualCarryDivergesAtHole(opponentAlias: String, hole: Int) -> Bool {
        guard isIndividualCarryActive(opponentAlias: opponentAlias),
              let carryAlias = individualCarryRequesterByOpponent[opponentAlias],
              segmentForHole(hole) == "B9" else { return false }
        guard let withCarry = holeResultVsYo(opponentAlias: opponentAlias, hole: hole, carryAlias: carryAlias),
              let withoutCarry = holeResultVsYo(opponentAlias: opponentAlias, hole: hole, carryAlias: nil) else { return false }
        return withCarry != withoutCarry
    }

    // Siempre calcula carry en B9 (sin importar si está activa), para monetización.
    func individualCarryComputedB9(opponentAlias: String) -> Int {
        guard let requester = individualCarryEligibleRequester(opponentAlias: opponentAlias) else { return 0 }
        return individualCarryComputedB9(opponentAlias: opponentAlias, requesterAlias: requester, startHole: firstBackNineHole())
    }

    func individualCarryMoneyB9(opponentAlias: String) -> Int {
        guard isIndividualCarryActive(opponentAlias: opponentAlias) else { return 0 }
        return individualCarryResultB9(opponentAlias: opponentAlias) * betValues(forOpponent: opponentAlias).vueltaValue
    }

    private func f9VueltaVsOpponent(opponentAlias: String) -> Int {
        let order = playOrder()
        let f9 = Array(order.prefix(9))
        return f9.compactMap { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: nil) }.reduce(0, +)
    }

    private func b9VueltaVsOpponent(opponentAlias: String) -> Int {
        let order = playOrder()
        let b9 = Array(order.suffix(9))
        return b9.compactMap { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: nil) }.reduce(0, +)
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
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "HIO", units: unitsForCalculatedTag("HIO", fallback: 1), note: "Hole in One"))
            }
            if enabled.contains("ALB"), gross == (h.par - 3) {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "ALB", units: unitsForCalculatedTag("ALB", fallback: 1), note: "Albatros"))
            } else if enabled.contains("EAG"), gross == (h.par - 2) {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "EAG", units: unitsForCalculatedTag("EAG", fallback: 1), note: "Aguila"))
            } else if enabled.contains("BIRD"), gross == (h.par - 1) {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "BIRD", units: unitsForCalculatedTag("BIRD", fallback: 1), note: "Birdie"))
            }
            if enabled.contains("B18"), hole == 18, gross == (h.par - 1) {
                out.append(UnitEvent(hole: hole, alias: p.alias, code: "B18", units: unitsForCalculatedTag("B18", fallback: 1), note: "Birdie 18"))
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
    func individualMatchupStrokes(yoAlias: String, oppAlias: String, hole: Int, carryAlias: String?) -> (yo: Double, opp: Double) {
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
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return [] }
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

    // Stroke de PAREJA para un jugador aislado en un hoyo — lo usa la tarjeta hoyo-por-hoyo.
    // A diferencia de individual (cada jugador trae su propio strokesVsBase contra DAN), en
    // pareja el stroke lo carga UN SOLO jugador por lado (lane.strokeCarrier) — mezclar el
    // stroke individual de cada uno en una vista de pareja hacía ver "dos jugadores con stroke"
    // en el mismo match, cuando debería ser solo el que carga por su lado.
    func pairStrokeForPlayer(laneId: UUID, alias: String, hole: Int) -> Double {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return 0 }
        var carryRequester: String? = nil
        if isPairCarryActive(laneId: laneId), segmentForHole(hole) == "B9",
           let req = pairCarryRequesterByLane[laneId] {
            let start = pairCarryStartHoleByLane[laneId] ?? firstBackNineHole()
            let order = playOrder()
            if let hIdx = order.firstIndex(of: hole), let startIdx = order.firstIndex(of: start), hIdx >= startIdx {
                carryRequester = req
            }
        }
        return laneCarrierStroke(lane: lane, alias: alias, hole: hole, carryRequesterAlias: carryRequester)
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

    // El Carry siempre aplica desde el primer hoyo de B9 — sin importar en qué hoyo se active
    // el botón. Igual que Ajuste 50 y Doble B9, que ya cubren todo el segmento completo; antes
    // esta función usaba expectedNextHole() (el próximo hoyo a jugar), lo que dejaba fuera del
    // Carry cualquier hoyo de B9 ya anotado antes de activarlo.
    private func carryStartHoleForB9() -> Int {
        firstBackNineHole()
    }

    func distributedStrokes(total: Double, hole: Int) -> Double {
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

    // Igual que distributedStrokes, pero repartiendo un total entre un subconjunto de hoyos
    // (p. ej. solo los 9 de B9) según su rango de Stroke Index RELATIVO dentro de ese subconjunto,
    // no el SI absoluto del curso — Ajuste 50 define un total exclusivo de B9, no un convenio
    // de los 18 hoyos, así que no puede usar distributedStrokes (que repartiría por SI global y
    // podría caer en hoyos del F9).
    private func distributedStrokesWithinHoles(total: Double, hole: Int, holes: [Int]) -> Double {
        guard total > 0.001, !holes.isEmpty else { return 0 }
        let ranked = holes.sorted { (getHole($0)?.si ?? 99) < (getHole($1)?.si ?? 99) }
        guard let idx = ranked.firstIndex(of: hole) else { return 0 }
        let rank = idx + 1
        let fullRounds = Int(total / Double(holes.count))
        let remainder = total - Double(fullRounds * holes.count)
        let whole = Int(floor(remainder))
        let fraction = remainder - Double(whole)
        var strokes = Double(fullRounds)
        if rank <= whole {
            strokes += 1
        } else if fraction >= 0.5, rank == whole + 1 {
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

    // Cada presión activa, con su propio valor — leído directo de pressureStates (la MISMA
    // fuente que pressureNet() usa para el dinero real), sin ningún cálculo nuevo. Se omiten las
    // que están en exactamente 0: "arrancan en 0 y empiezan a contar desde el siguiente hoyo"
    // (ver pressureStates) — en 0 todavía no han jugado ni un hoyo, no hay nada que mostrar.
    private func pressureValues(values: [Int?], threshold: Int) -> [Int] {
        let compact = values.compactMap { $0 }
        if compact.isEmpty { return [] }
        let active = pressureStates(values: compact, threshold: threshold).last ?? []
        return active.filter { $0 != 0 }
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
            let prevActive = active
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

    // MARK: - Cell overrides & unit badges (Bloque 3)

    func cellOverride(alias: String, hole: Int) -> CellOverride {
        players.first(where: { $0.alias == alias })?.cellOverrides[hole] ?? .none
    }

    func setCellOverride(alias: String, hole: Int, override value: CellOverride) {
        guard let idx = players.firstIndex(where: { $0.alias == alias }) else { return }
        if value == .none {
            players[idx].cellOverrides.removeValue(forKey: hole)
        } else {
            players[idx].cellOverrides[hole] = value
        }
        objectWillChange.send()
    }

    // Lee ScoreManager desde disco y aplica los records al estado en memoria.
    // Se dispara cuando Siri anota o cuando la app vuelve a foreground.
    func syncFromScoreManager() {
        ScoreManager.shared.loadFromDisk()
        let records = ScoreManager.shared.allRecords()
        for record in records {
            // Acepta alias ("DAN") o nombre completo ("Daniel") — cubre Siri y el test manual
            guard let idx = players.firstIndex(where: {
                $0.alias == record.player || $0.name == record.player
            }) else { continue }
            players[idx].scores[record.hole] = (gross: record.strokes, putts: record.putts)
        }
        objectWillChange.send()
    }

    // Conteo de eventos de unidad (manuales + calculados: Birdie/Eagle/Albatros/HIO… + Oyes
    // rank 1) para un jugador en un hoyo — usado para pegar círculos en su celda del Zoom.
    func unitEventCount(alias: String, hole: Int) -> Int {
        var count = (unitEventsByHole[hole] ?? []).filter { $0.alias == alias && $0.units != 0 }.count
        count += calculatedUnitEventsForHole(hole).filter { $0.alias == alias }.count
        if oyesRanksByHole[hole]?[alias] == 1 { count += 1 }
        return count
    }

    func unitBadges(alias: String, hole: Int) -> [String] {
        let manual = unitEventsByHole[hole]?.filter { $0.alias == alias } ?? []
        let calculated = calculatedUnitEventsForHole(hole).filter { $0.alias == alias }
        var badges: [String] = []
        for event in manual + calculated {
            switch event.code {
            case "SANDY_PAR": badges.append("S")
            case "UP_DOWN":   badges.append("↕")
            case "CHIP_IN":   badges.append("◎")
            case "HIO":       badges.append("1○")
            case "ALB":       badges.append("A")
            default: break
            }
        }
        return badges
    }
}
