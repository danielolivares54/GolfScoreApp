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

// Alcance de la apuesta de putts: qué hoyos cuentan. f9/b9 siguen el orden de juego (primer y
// segundo nueve jugados, ver playOrder()), igual que el resto de las apuestas.
enum PuttsBetMode: String, CaseIterable, Codable {
    case hole18 = "H18"
    case byRound = "Vuelta"
    case f9 = "F9"
    case b9 = "B9"
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
    // Solo el tag PUTTS lo usa: alcance de la apuesta (F9 / B9 / 18). Optional con default nil —
    // los catálogos guardados antes de este campo decodifican igual.
    var puttsScope: PuttsBetMode? = nil
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
    // Vuelta + Presión separadas por segmento (f9Money + b9Money == vueltaMoney + presionMoney) —
    // para mostrar F9 y B9 por separado sin tocar los totales.
    var f9Money: Int = 0
    var b9Money: Int = 0
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
    // Vista v1 y v2 comparten UN MatchManager (lo crea RootView). La carga inicial (config guardada,
    // scores, demo) debe correr una sola vez por match, no cada vez que se cambia de vista.
    var didRunInitialSetup = false

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
    // 0 = apuesta de putts cerrada; el valor real lo pone el tag PUTTS del catálogo.
    @Published var puttsBetUnits: Int = 0
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
        syncPuttsBetFromCatalog()
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
        saveBetConfig()
    }

    // Una plantilla se copia al match al elegirla (valores globales de parejas y valores propios de
    // cada rival). Si después se edita la plantilla, esas copias quedaban con el monto viejo — aquí
    // se re-sincronizan con la versión nueva. El dinero se deriva en walletSnapshot(), así que
    // todo se recalcula solo; esto solo evita que se quede con valores desactualizados.
    func refreshBetValues(fromTemplate tpl: BetTemplate) {
        if activeTemplateId == tpl.id {
            vueltaValue = tpl.vueltaValue
            presionValue = tpl.presionValue
            matchValue = tpl.matchValue
            unitValue = tpl.unitValue
        }
        for (alias, v) in betValuesByOpponent where v.templateId == tpl.id {
            betValuesByOpponent[alias] = OpponentBetValues(
                templateId: tpl.id,
                vueltaValue: tpl.vueltaValue,
                presionValue: tpl.presionValue,
                matchValue: tpl.matchValue,
                unitValue: tpl.unitValue
            )
        }
        objectWillChange.send()
        saveBetConfig()
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

    // Los putts son una apuesta opcional: los del usuario (yoAlias) siempre se registran; los de
    // los demás jugadores solo se piden y se auditan si la apuesta de putts está activa.
    var puttsBetActive: Bool { puttsBetUnits > 0 }

    func tracksPutts(alias: String) -> Bool {
        alias == yoAlias || puttsBetActive
    }

    // La apuesta de putts se define en el tag PUTTS del catálogo (encendido, precio, alcance);
    // aquí solo se copia al match. Se llama al armar el match y al cerrar el editor de catálogo.
    func syncPuttsBetFromCatalog() {
        guard let def = BetDefinitionStore.shared.entries.first(where: { $0.tag == BetDefinitionStore.puttsTag }) else { return }
        puttsBetUnits = def.isEnabled ? def.units : 0
        puttsBetMode = def.puttsScope ?? .hole18
    }

    func setPuttsBet(mode: PuttsBetMode, units: Int) {
        puttsBetMode = mode
        puttsBetUnits = max(0, units)
        BetDefinitionStore.shared.setPutts(scope: mode, units: puttsBetUnits)
        objectWillChange.send()
    }

    func applyBetTemplate(_ template: BetTemplate) {
        activeTemplateId = template.id
        vueltaValue = template.vueltaValue
        presionValue = template.presionValue
        matchValue = template.matchValue
        unitValue = template.unitValue
        // Los putts ya no vienen de la plantilla: los define el tag PUTTS del catálogo (ver
        // syncPuttsBetFromCatalog). Si no, guardar el Setup pisaba el tag con lo de la plantilla.
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
            .filter { isUnitCodeActive($0.code) }   // una unidad desactivada en el catálogo deja de contar (sus eventos se conservan)
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
                guard isOyesEnabled,
                      getHole(hole)?.par == 3,
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
                for lane in activeLanes.prefix(3) {
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
                for lane in activeLanes.prefix(3) {
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
        // OYES (par 3) cuentan como unidades: positivo si yo quedo mejor rankeado que el rival.
        for hole in zoomHolesForCurrentRound(segmentOverride: segmentOverride) {
            total += oyesIndividualResult(hole: hole, opponentAlias: opponentAlias) ?? 0
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
        // OYES de pareja (mejor rank de cada lado), positivo a favor del lado base.
        for hole in zoomHolesForCurrentRound(segmentOverride: segmentOverride) {
            total += oyesPairResult(hole: hole, lane: lane) ?? 0
        }
        return total
    }

    func hasIndividualUnitWin(hole: Int, alias: String) -> Bool {
        let manual = (unitEventsByHole[hole] ?? []).filter { $0.alias == alias && isUnitCodeActive($0.code) }.reduce(0) { $0 + $1.units }
        let calc = calculatedUnitEventsForHole(hole).filter { $0.alias == alias }.reduce(0) { $0 + $1.units }
        return (manual + calc) > 0
    }

    func hasPairUnitWin(hole: Int, alias: String) -> Bool {
        for lane in activeLanes {
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
            clearCarryDependentState()
        }
        objectWillChange.send()
    }

    // Carry / Ajuste 50 / Doble Press se deciden con el resultado del F9 y guardan hoyos
    // absolutos; cualquier cambio de Setup que mueva ese F9 (hoyo de salida, strokes, parejas,
    // quién carga el golpe) los deja calculados sobre datos viejos.
    func clearCarryDependentState() {
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
        objectWillChange.send()
    }

    // Cierre de GuidedSetupView.applySetup: un solo guardado con el Setup completo (setCourse no
    // guarda por sí solo) y un refresh para que tarjeta, auditoría y dinero se recalculen.
    func finishSetupApply() {
        saveBetConfig()
        objectWillChange.send()
    }

    // Todo lo que alimenta el reparto de golpes y el resultado del F9. GuidedSetupView.applySetup
    // la toma antes y después de aplicar el Setup: si cambió, el estado derivado del F9 se invalida.
    var strokeSetupSignature: String {
        let playerPart = players.map { "\($0.alias):\($0.strokesVsBase)" }.joined(separator: ",")
        let lanePart = lanes
            .map { "\($0.base.sorted().joined(separator: "+"))>\($0.opp.sorted().joined(separator: "+")):\($0.strokes):\($0.strokeCarrier ?? "")" }
            .sorted()
            .joined(separator: ",")
        return "\(courseId)|\(startHole)|\(playerPart)|\(baseTeamAliases.sorted().joined(separator: ","))|\(lanePart)"
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

    // Los 18 hoyos capturados por todos los jugadores — el Match solo se cobra al terminar la ronda.
    func isRoundComplete() -> Bool {
        let order = playOrder()
        return order.count >= 18 && order.allSatisfy { isHoleComplete($0) }
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
        if activeLanes.isEmpty { return [] }
        return activeLanes.prefix(3).compactMap { lane in
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
        // Los switches de apuesta por pareja también cuelgan del lane.id (UUID nuevo en cada
        // rebuild) — sin esto, guardar el Setup los regresaba a sus valores por defecto.
        var switchesByKey: [String: MatchBetSwitches] = [:]
        for lane in lanes {
            let key = lane.opp.sorted().joined(separator: "+")
            if let sw = pairBetSwitchesByLane[lane.id] { switchesByKey[key] = sw }
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
            if let sw = switchesByKey[key] { pairBetSwitchesByLane[lane.id] = sw }
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
            rebuildBetInstances()
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
        // Sin chequeo de elegibilidad: loadBetConfig() corre ANTES de syncFromScoreManager(), así
        // que al relanzar todavía no hay scores y el F9 sale 0 (nadie elegible) — el carry guardado
        // se descartaba y el guardado final lo borraba del disco. isIndividualCarryActive() ya
        // vuelve a validar requester == elegible cada vez que se usa.
        guard players.contains(where: { $0.alias == opponentAlias }),
              requesterAlias == yoAlias || requesterAlias == opponentAlias else { return }
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
        // Convenio neto del matchup: quien recibe vs quien da (p. ej. si ROB le da 8 a DAN,
        // el strokesVsBase de DAN puede ser 0 y el de ROB -8; el convenio real es 8).
        let netConvenio = playerStrokes(alias: yoAlias) - playerStrokes(alias: opponentAlias)
        let convenio = abs(netConvenio)
        let f9Part = "F9 \(fmtStroke(convenio))/\(fmtStroke(f9Value))"

        if isIndividualAdjust50Active(opponentAlias: opponentAlias) {
            let profile = individualAdjust50Profile(opponentAlias: opponentAlias)
            let whoSuffix = (profile.receiver != nil && profile.receiver != alias) ? " → \(profile.receiver!)" : ""
            return "\(alias) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalB9))/\(fmtStroke(profile.amount))A\(whoSuffix)"
        }
        if isIndividualCarryActive(opponentAlias: opponentAlias), let carryAlias = individualCarryRequesterByOpponent[opponentAlias] {
            let carryPts = individualCarryResultB9(opponentAlias: opponentAlias)
            let cLabel = carryPts >= 0 ? "+\(carryPts)" : "\(carryPts)"
            // Convenio ajustado por el carry (±1 a favor de quien lo pidió) y sus strokes en B9.
            let carrySigned = netConvenio + (carryAlias == yoAlias ? 1 : -1)
            let carryTotal = abs(carrySigned)
            let carryReceiver = carrySigned > 0.001 ? yoAlias : (carrySigned < -0.001 ? opponentAlias : nil)
            let carryB9 = Array(playOrder().suffix(9)).reduce(0.0) { acc, h in
                let s = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: h, carryAlias: carryAlias)
                return acc + (carryReceiver == yoAlias ? s.yo : s.opp)
            }
            let carryPart = carryReceiver.map { "\($0) \(fmtStroke(carryTotal))/\(fmtStroke(carryB9))" } ?? "0/0"
            return "\(alias) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalB9)) → \(carryPart) C\(cLabel)"
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
        guard let hIdx = order.firstIndex(of: hole), let startIdx = order.firstIndex(of: start), hIdx >= startIdx else { return 0 }
        // Diferencia entre el stroke con carry y el normal para ese jugador en ese hoyo
        // (puede ser +1, 0 o negativo si el solicitante daba strokes).
        let with = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: hole, carryAlias: requester)
        let without = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: opponentAlias, hole: hole, carryAlias: nil)
        return alias == yoAlias ? with.yo - without.yo : with.opp - without.opp
    }

    func pairCarryExtraStroke(laneId: UUID, alias: String, hole: Int) -> Double {
        guard isPairCarryActive(laneId: laneId),
              let requester = pairCarryRequesterByLane[laneId], requester == alias,
              segmentForHole(hole) == "B9" else { return 0 }
        let start = pairCarryStartHoleByLane[laneId] ?? firstBackNineHole()
        let order = playOrder()
        guard let hIdx = order.firstIndex(of: hole), let startIdx = order.firstIndex(of: start), hIdx >= startIdx,
              let lane = lanes.first(where: { $0.id == laneId }) else { return 0 }
        // Diferencia real entre el stroke con carry (convenio ±1 repartido por SI) y el normal.
        let with = laneCarrierStroke(lane: lane, alias: alias, hole: hole, carryRequesterAlias: requester)
        let without = laneCarrierStroke(lane: lane, alias: alias, hole: hole, carryRequesterAlias: nil)
        return with - without
    }

    // Mismo motivo que restoreIndividualCarry: preserva el startHole guardado en vez de
    // recalcularlo con el progreso actual del juego.
    private func restorePairCarry(laneId: UUID, requesterAlias: String, startHole: Int) {
        // Sin chequeo de elegibilidad (ver restoreIndividualCarry): al relanzar aún no hay scores
        // y no hay lado perdedor de F9. isPairCarryActive() lo valida al usarse.
        guard let lane = lanes.first(where: { $0.id == laneId }),
              lane.base.contains(requesterAlias) || lane.opp.contains(requesterAlias) else { return }
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
            // Convenio ajustado por el carry (±1 a favor de quien lo pidió) y sus strokes en B9.
            let adjusted = effectiveLaneStrokeProfile(lane: lane, carryRequesterAlias: carryAlias)
            let b9Profile = laneB9CarryProfile(lane: lane, requesterAlias: carryAlias)
            let carryB9 = b9Profile.carrier.map { c in
                b9.reduce(0.0) { $0 + laneCarrierStroke(lane: lane, alias: c, hole: $1, carryRequesterAlias: carryAlias) }
            } ?? 0
            let carryPart = b9Profile.carrier.map { "\($0) \(fmtStroke(adjusted.total))/\(fmtStroke(carryB9))" } ?? "0/0"
            return "\(carrier) \(f9Part) · B9 \(fmtStroke(convenio))/\(fmtStroke(normalB9)) → \(carryPart) C\(cLabel)"
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

    // Resultado del hoyo sin Carry vs con Carry (perspectiva del lado base) — solo si el Carry de
    // la pareja está activo y el hoyo es de B9. Para mostrar exactamente cómo cambia el resultado.
    func pairCarryHoleResults(laneId: UUID, hole: Int) -> (without: Int, with: Int)? {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              isPairCarryActive(laneId: laneId),
              let requester = pairCarryRequesterByLane[laneId],
              segmentForHole(hole) == "B9",
              let withCarry = pairResult(hole: hole, lane: lane, carryRequesterAlias: requester),
              let withoutCarry = pairResult(hole: hole, lane: lane) else { return nil }
        return (withoutCarry, withCarry)
    }

    // Vuelta acumulada y presiones abiertas de B9 calculadas CON el stroke del Carry, hoyo por hoyo
    // — para compararlas con el Acum normal (que no incluye el carry). Perspectiva del lado base
    // (pareja) o de yo (individual). Vacío si el Carry no está activo.
    func carryAccumByHole(laneId: UUID?, opponentAlias: String?) -> [Int: (vuelta: Int, pres: [Int])] {
        let b9 = Array(playOrder().suffix(9))
        var values: [(hole: Int, v: Int)] = []
        let threshold: Int
        if let laneId {
            guard let lane = lanes.first(where: { $0.id == laneId }),
                  isPairCarryActive(laneId: laneId),
                  let requester = pairCarryRequesterByLane[laneId] else { return [:] }
            threshold = 3
            for h in b9 {
                if let v = pairResult(hole: h, lane: lane, carryRequesterAlias: requester) { values.append((h, v)) }
            }
        } else if let opp = opponentAlias {
            guard isIndividualCarryActive(opponentAlias: opp),
                  let carryAlias = individualCarryRequesterByOpponent[opp] else { return [:] }
            threshold = 2
            for h in b9 {
                if let v = holeResultVsYo(opponentAlias: opp, hole: h, carryAlias: carryAlias) { values.append((h, v)) }
            }
        } else {
            return [:]
        }
        let states = pressureStates(values: values.map { $0.v }, threshold: threshold)
        var out: [Int: (vuelta: Int, pres: [Int])] = [:]
        var vuelta = 0
        for (i, e) in values.enumerated() {
            vuelta += e.v
            out[e.hole] = (vuelta, states[i].filter { $0 != 0 })
        }
        return out
    }

    // Igual que pairCarryHoleResults, para individual (perspectiva de yo).
    func individualCarryHoleResults(opponentAlias: String, hole: Int) -> (without: Int, with: Int)? {
        guard isIndividualCarryActive(opponentAlias: opponentAlias),
              let carryAlias = individualCarryRequesterByOpponent[opponentAlias],
              segmentForHole(hole) == "B9",
              let withCarry = holeResultVsYo(opponentAlias: opponentAlias, hole: hole, carryAlias: carryAlias),
              let withoutCarry = holeResultVsYo(opponentAlias: opponentAlias, hole: hole, carryAlias: nil) else { return nil }
        return (withoutCarry, withCarry)
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
        let roundComplete = isRoundComplete()

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
                mMoney = (switches.match && roundComplete) ? mPts * ov.matchValue : 0
            }
            // Carry = apuesta aparte con la apuesta original: la vuelta de B9 con los strokes del
            // Carry vale 1 unidad (gane por lo que gane) + 1 unidad de presión por cada presión
            // abierta (ej. 5 3 1 = vuelta + 2 presiones). No lleva Doble B9.
            let carryOn = switches.carry && carryActive
            let carryPres = (carryOn ? individualCarryRequesterByOpponent[opp] : nil).map {
                pressureNet(values: individualCarryValuesB9(opponentAlias: opp, requester: $0), threshold: 2)
            } ?? 0
            let cMoney = carryOn ? signedUnit(carryPts) * ov.vueltaValue + carryPres * ov.presionValue : 0
            let aMoney = aPts * ov.vueltaValue
            let uMoney = uPts * ov.unitValue
            let total = vMoney + pMoney + cMoney + aMoney + mMoney + uMoney
            let f9Money: Int
            let b9Money: Int
            if f9Tied {
                f9Money = pMoney
                b9Money = vMoney
            } else {
                f9Money = (switches.vuelta ? signedUnit(f9V) * ov.vueltaValue : 0)
                    + (switches.presion ? f9P * ov.presionValue : 0)
                b9Money = (switches.vuelta ? signedUnit(b9V) * ov.vueltaValue * dpMultiplier : 0)
                    + (switches.presion ? b9P * ov.presionValue * dpMultiplier : 0)
            }
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
                    totalMoney: total,
                    f9Money: f9Money,
                    b9Money: b9Money
                )
            )
        }

        for lane in activeLanes.prefix(3) {
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
            // Carry de pareja: misma regla que individual (vuelta + una unidad por presión), con
            // el valor original de la pareja y sin Doble B9.
            let carryOn = switches.carry && carryActive
            let carryPres = (carryOn ? pairCarryRequesterByLane[lane.id] : nil).map {
                pressureNet(values: pairCarryValuesB9(lane: lane, requester: $0), threshold: 3)
            } ?? 0
            let cMoney = carryOn ? signedUnit(cPts) * vueltaValue + carryPres * presionValue : 0
            let aMoney = aPts * vueltaValue
            let mMoney = roundComplete ? mPts * matchValue : 0
            let uMoney = uPts * unitValue
            let total = vMoney + pMoney + cMoney + aMoney + mMoney + uMoney
            let f9Money = (switches.vuelta ? signedUnit(f9V) * vueltaValue : 0)
                + (switches.presion ? f9P * presionValue : 0)
            let b9Money = (switches.vuelta ? signedUnit(b9V) * vueltaValue * dpMultiplier : 0)
                + (switches.presion ? b9P * presionValue * dpMultiplier : 0)
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
                    totalMoney: total,
                    f9Money: f9Money,
                    b9Money: b9Money
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

    private func individualCarryValuesB9(opponentAlias: String, requester: String) -> [Int?] {
        Array(playOrder().suffix(9)).map { holeResultVsYo(opponentAlias: opponentAlias, hole: $0, carryAlias: requester) }
    }

    private func pairCarryValuesB9(lane: LaneModel, requester: String) -> [Int?] {
        Array(playOrder().suffix(9)).map { pairResult(hole: $0, lane: lane, carryRequesterAlias: requester) }
    }

    // Presiones del Carry (valor de cada una) — para la vista de tabla. Pareja: perspectiva del lado base.
    func individualCarryPresionB9(opponentAlias: String) -> [Int] {
        guard isIndividualCarryActive(opponentAlias: opponentAlias),
              let requester = individualCarryRequesterByOpponent[opponentAlias] else { return [] }
        return pressureValues(values: individualCarryValuesB9(opponentAlias: opponentAlias, requester: requester), threshold: 2)
    }

    func pairCarryPresionB9(laneId: UUID) -> [Int] {
        guard let lane = lanes.first(where: { $0.id == laneId }),
              isPairCarryActive(laneId: laneId),
              let requester = pairCarryRequesterByLane[laneId] else { return [] }
        return pressureValues(values: pairCarryValuesB9(lane: lane, requester: requester), threshold: 3)
    }

    // Convenio de strokes del matchup, siempre entero (para la línea de condiciones de la tabla).
    func individualStrokesConvenio(opponentAlias: String) -> Int {
        Int(abs(playerStrokes(alias: yoAlias) - playerStrokes(alias: opponentAlias)).rounded())
    }

    func pairStrokesConvenio(laneId: UUID) -> Int {
        Int((lanes.first(where: { $0.id == laneId })?.strokes ?? 0).rounded())
    }

    func pairCarryMoneyB9(laneId: UUID) -> Int {
        guard isPairCarryActive(laneId: laneId),
              let lane = lanes.first(where: { $0.id == laneId }),
              let requester = pairCarryRequesterByLane[laneId] else { return 0 }
        let pres = pressureNet(values: pairCarryValuesB9(lane: lane, requester: requester), threshold: 3)
        return signedUnit(pairCarryResultB9(laneId: laneId)) * vueltaValue + pres * presionValue
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
        guard isIndividualCarryActive(opponentAlias: opponentAlias),
              let requester = individualCarryRequesterByOpponent[opponentAlias] else { return 0 }
        let ov = betValues(forOpponent: opponentAlias)
        let pres = pressureNet(values: individualCarryValuesB9(opponentAlias: opponentAlias, requester: requester), threshold: 2)
        return signedUnit(individualCarryResultB9(opponentAlias: opponentAlias)) * ov.vueltaValue + pres * ov.presionValue
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
        // Sin valor puesto para ese hoyo, vale lo que diga el catálogo ("Vale" de Oyes / Oyes Parejas).
        return catalogUnits(forTag: pair ? "OYESP" : "OYES") ?? 1
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
        guard isOyesEnabled else { return nil }
        guard getHole(hole)?.par == 3 else { return nil }
        guard let ranks = oyesRanksByHole[hole],
              let yoRank = ranks[yoAlias],
              let oppRank = ranks[opponentAlias] else { return nil }
        let unit = oyesUnitForHole(hole, pair: false)
        if yoRank < oppRank { return unit }
        if yoRank > oppRank { return -unit }
        return 0
    }

    // Quién ganó el Oyes de un par 3 en un match — para pintarlo en Resultados y en la tarjeta.
    // Individual: positivo = gana yo, negativo = gana el rival. nil si no hay ranks de ambos.
    func oyesIndividualOutcome(hole: Int, opponentAlias: String) -> Int? {
        oyesIndividualResult(hole: hole, opponentAlias: opponentAlias)
    }

    // Pareja: positivo = gana el lado base, negativo = gana el lado rival. nil si faltan ranks.
    func oyesPairOutcome(hole: Int, laneId: UUID) -> Int? {
        guard let lane = lanes.first(where: { $0.id == laneId }) else { return nil }
        return oyesPairResult(hole: hole, lane: lane)
    }

    private func oyesPairResult(hole: Int, lane: LaneModel) -> Int? {
        guard isOyesPairEnabled, isPairMatchEnabled else { return nil }
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
        if activeLanes.isEmpty { return [] }
        return activeLanes.prefix(3).map { lane in
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

        // Carry: ajusta el CONVENIO (total de strokes del matchup) en ±1 a favor de quien pidió
        // el carry, no un stroke por hoyo. Si el solicitante recibía N pasa a N+1; si daba N pasa
        // a dar N-1 (y si cruza 0 cambia la dirección). El nuevo total se reparte por Stroke
        // Index igual que el convenio normal y solo se aplica a los hoyos de B9.
        if segmentForHole(hole) == "B9", let carry = carryAlias, carry == yoAlias || carry == oppAlias {
            // El ±1 se suma a los strokes que YA caen en B9 y se reparte solo entre los 9 hoyos de
            // B9 (rank relativo de SI) — repartido sobre 18 hoyos podía caer en F9 y B9 no cambiaba.
            // Positivo = recibe yo, negativo = recibe el oponente.
            let b9 = Array(playOrder().suffix(9))
            let normalB9 = b9.reduce(0.0) { acc, h in
                let s = individualMatchupStrokes(yoAlias: yoAlias, oppAlias: oppAlias, hole: h, carryAlias: nil)
                return acc + s.yo - s.opp
            }
            let signed = normalB9 + (carry == yoAlias ? 1 : -1)
            yoStroke = signed > 0 ? distributedStrokesWithinHoles(total: signed, hole: hole, holes: b9) : 0
            oppStroke = signed < 0 ? distributedStrokesWithinHoles(total: -signed, hole: hole, holes: b9) : 0
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

    // Perfil del Carry de pareja en B9: el stroke extra (±1) se suma a los strokes que YA caen en
    // B9 y se reparte solo entre los 9 hoyos de B9 (rank relativo de SI) — no sobre los 18 hoyos,
    // donde el +1 podía caer en un hoyo de F9 y B9 quedaba igual (ej. 12 → 13: el SI 13 es de F9).
    private func laneB9CarryProfile(lane: LaneModel, requesterAlias: String) -> (total: Double, carrier: String?) {
        let normal = effectiveLaneStrokeProfile(lane: lane, carryRequesterAlias: nil)
        let b9 = Array(playOrder().suffix(9))
        var signedB9 = 0.0
        if let c = normal.carrier {
            let n = b9.reduce(0.0) { $0 + distributedStrokes(total: normal.total, hole: $1) }
            signedB9 = lane.base.contains(c) ? n : -n
        }
        if lane.base.contains(requesterAlias) {
            signedB9 += 1
        } else if lane.opp.contains(requesterAlias) {
            signedB9 -= 1
        }
        // Quien ya lleva el stroke lo sigue llevando. Solo si ese lado no tenía carrier (strokes en
        // 0) el stroke lo lleva quien pidió el carry, no el primero de la lista.
        let current = lane.strokeCarrier
        if signedB9 > 0.001 {
            let fallback = lane.base.contains(requesterAlias) ? requesterAlias : (lane.base.first ?? "")
            let carrier = (current != nil && lane.base.contains(current!)) ? current! : fallback
            return (signedB9, carrier.isEmpty ? nil : carrier)
        }
        if signedB9 < -0.001 {
            let fallback = lane.opp.contains(requesterAlias) ? requesterAlias : (lane.opp.first ?? "")
            let carrier = (current != nil && lane.opp.contains(current!)) ? current! : fallback
            return (-signedB9, carrier.isEmpty ? nil : carrier)
        }
        return (0, nil)
    }

    private func laneCarrierStroke(lane: LaneModel, alias: String, hole: Int, carryRequesterAlias: String? = nil) -> Double {
        if let requester = carryRequesterAlias, segmentForHole(hole) == "B9" {
            let p = laneB9CarryProfile(lane: lane, requesterAlias: requester)
            guard p.carrier == alias, p.total > 0.001 else { return 0 }
            return distributedStrokesWithinHoles(total: p.total, hole: hole, holes: Array(playOrder().suffix(9)))
        }
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
            let fallback = (carryRequesterAlias.map { lane.base.contains($0) } ?? false) ? carryRequesterAlias! : (lane.base.first ?? "")
            let carrier = (currentCarrier != nil && lane.base.contains(currentCarrier!)) ? currentCarrier! : fallback
            return (signed, carrier.isEmpty ? nil : carrier)
        }
        let fallback = (carryRequesterAlias.map { lane.opp.contains($0) } ?? false) ? carryRequesterAlias! : (lane.opp.first ?? "")
        let carrier = (currentCarrier != nil && lane.opp.contains(currentCarrier!)) ? currentCarrier! : fallback
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
        Self.distributedStrokes(total: total, hole: hole, startHole: startHole, holes: holes)
    }

    // Reparto de golpes que sigue el ORDEN DE JUEGO, no solo el SI fijo de la cancha: los golpes
    // se alternan entre el primer nueve jugado y el segundo (el 1.º, 3.º, 5.º… al primero; el 2.º,
    // 4.º… al segundo), y dentro de cada nueve van al hoyo más difícil por SI relativo a ese nueve.
    // Con salida en el hoyo 1 y un campo con SI impares en F9 / pares en B9 (CGM) da exactamente
    // el mismo reparto que el SI puro; al mover el hoyo de salida, el primer nueve jugado cambia
    // y el reparto se reasigna. Es estática para que RoundHistoryView (rondas cerradas, sin
    // MatchManager vivo) use la misma regla con el startHole que guardó la ronda.
    static func distributedStrokes(total: Double, hole: Int, startHole: Int, holes: [HoleModel]) -> Double {
        guard total > 0, holes.count == 18,
              let target = holes.first(where: { $0.number == hole }) else { return 0 }
        let start = max(1, min(18, startHole))
        let order = (0..<18).map { ((start - 1 + $0) % 18) + 1 }
        guard let pos = order.firstIndex(of: hole) else { return 0 }
        let segment = pos < 9 ? 0 : 1
        let siByNumber = Dictionary(holes.map { ($0.number, $0.si) }, uniquingKeysWith: { a, _ in a })
        let nine = order[(segment * 9)..<(segment * 9 + 9)]
        let rank = nine.filter { (siByNumber[$0] ?? 99) < target.si }.count + 1
        // Posición de este hoyo en la secuencia alternada de golpes (1 = el más difícil del
        // primer nueve, 2 = el más difícil del segundo, 3 = el 2.º del primero…).
        let sequence = 2 * rank - 1 + segment

        let fullRounds = Int(total / 18.0)
        let remainder = total - Double(fullRounds * 18)
        let whole = Int(floor(remainder))
        let fraction = remainder - Double(whole)
        var strokes = Double(fullRounds)
        if sequence <= whole {
            strokes += 1
        } else if fraction >= 0.5, sequence == whole + 1 {
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

#if DEBUG
// Ronda demo de 18 hoyos para probar en el simulador (se activa con el default "demo18" = true).
// Los golpes de DAN y ROB en F9 y los de B9 de los 5 jugadores salen de las capturas reales del CGM;
// el F9 de FER/RIC/ANS es inventado. Nada de esto se compila en Release.
extension MatchManager {
    func loadDemo18() {
        setCourse(CourseCatalog.cgm, resetScores: true)
        startHole = 1
        setPlayers(names: ["Daniel", "Fernando", "Roberto", "Ricardo", "Anselmo"], preserveScores: false)

        // Golpes por hoyo 1...18
        let scores: [String: [Int]] = [
            "DAN": [4, 9, 4, 6, 2, 6, 5, 5, 7,   6, 7, 9, 6, 3, 7, 4, 10, 6],
            "ROB": [5, 8, 3, 5, 4, 7, 5, 6, 5,   6, 7, 9, 7, 3, 7, 4, 9, 6],
            "FER": [5, 7, 3, 5, 3, 6, 5, 5, 6,   5, 6, 5, 7, 2, 5, 4, 6, 6],
            "RIC": [5, 8, 4, 6, 4, 7, 6, 6, 6,   5, 7, 7, 5, 6, 7, 5, 8, 6],
            "ANS": [5, 8, 4, 6, 3, 7, 5, 6, 6,   7, 7, 8, 7, 3, 7, 5, 7, 5],
        ]
        for (alias, holes) in scores {
            for (i, g) in holes.enumerated() {
                applyHoleEntry(HoleEntryData(hole_number: i + 1, player_alias: alias, strokes: g, putts: nil, units: nil, tags: nil))
            }
        }

        // Strokes: ROB le da 8 a DAN; pareja DAN+FER vs RIC+ANS con 12 a favor de ANS.
        setApuestaValues(vuelta: 50, presion: 50, match: 50)
        setUnitValue(25)
        setStrokesVsBase(alias: "ROB", value: -8)
        if setBaseTeam(["DAN", "FER"]) {
            setLaneStrokesForMatch(base: ["DAN", "FER"], opp: ["RIC", "ANS"], value: 12)
            setLaneCarrierForMatch(base: ["DAN", "FER"], opp: ["RIC", "ANS"], carrier: "ANS")
        }

        // Oyes en los par 3 (H14 y H16): DAN 3 vs ROB 2 en H14; DAN 3 vs ROB 4 en H16.
        setOyesRanks(hole: 14, ranksByAlias: ["FER": 1, "ROB": 2, "DAN": 3, "RIC": 4, "ANS": 5])
        setOyesRanks(hole: 16, ranksByAlias: ["FER": 1, "RIC": 2, "DAN": 3, "ROB": 4, "ANS": 5])

        // Apuestas activas: Carry + Doble B9 contra ROB; Carry de ANS en RIC+ANS.
        if let eligible = individualCarryEligibleRequester(opponentAlias: "ROB") {
            setIndividualCarryRequest(opponentAlias: "ROB", requesterAlias: eligible)
        }
        setIndividualDoublePress(opponentAlias: "ROB", active: true)
        if let lane = lanes.first(where: { Set($0.opp) == Set(["RIC", "ANS"]) }) {
            setPairCarryRequest(laneId: lane.id, requesterAlias: "ANS")
        }
        objectWillChange.send()
    }
}
#endif

// MARK: - Tarjeta "Carry B9" (B9 normal vs B9 con el stroke del Carry)

struct CarryCardPlayer: Identifiable {
    let id = UUID()
    let alias: String
    let isMySide: Bool          // yo / lado base
    let gross: Int
    let strokesNormal: Double
    let strokesCarry: Double
}

struct CarryCardRow: Identifiable {
    let id = UUID()
    let hole: Int
    let par: Int
    let si: Int
    let players: [CarryCardPlayer]
    let resultNormal: Int
    let resultCarry: Int
    let accumNormal: Int
    let presNormal: [Int]
    let accumCarry: Int
    let presCarry: [Int]
    // +1 = el carry agrega un stroke en este hoyo, -1 = lo quita, 0 = igual que B9.
    let strokeChange: Double
    var diverges: Bool { resultNormal != resultCarry }
}

struct CarryCardData {
    let title: String
    let requester: String
    let normalStrokes: Double       // strokes que caen en B9 sin carry (de quien los recibe)
    let carryStrokes: Double
    let receiverNormal: String?
    let receiverCarry: String?
    let changeHole: Int?            // hoyo donde el carry agrega o quita el stroke
    let changeRank: Int?            // "ventaja" N de B9 (rank de SI entre los 9 hoyos)
    let rows: [CarryCardRow]
    var vueltaNormal: Int { rows.last?.accumNormal ?? 0 }
    var vueltaCarry: Int { rows.last?.accumCarry ?? 0 }
    var presNormal: [Int] { rows.last?.presNormal ?? [] }
    var presCarry: [Int] { rows.last?.presCarry ?? [] }
    var hasDifference: Bool { rows.contains { $0.diverges } }
}

extension MatchManager {
    // Todo lo que muestra la tarjeta Carry B9: strokes con y sin carry, resultado por hoyo en las dos
    // versiones, acumulado y presiones de cada una. nil si el Carry de ese match no está activo.
    // Pareja: perspectiva del lado base; individual: perspectiva de yo.
    func carryCardData(target: UnitLogTarget) -> CarryCardData? {
        let b9 = Array(playOrder().suffix(9))
        let title: String
        let requester: String
        let mine: [String]
        let other: [String]
        let threshold: Int
        let resNormal: (Int) -> Int?
        let resCarry: (Int) -> Int?
        let strokesNormal: (String, Int) -> Double
        let strokesCarry: (String, Int) -> Double

        switch target {
        case .individual(let opp):
            guard isIndividualCarryActive(opponentAlias: opp),
                  let req = individualCarryRequesterByOpponent[opp] else { return nil }
            title = "\(yoAlias) vs \(opp)"
            requester = req
            mine = [yoAlias]
            other = [opp]
            threshold = 2
            resNormal = { self.holeResultVsYo(opponentAlias: opp, hole: $0, carryAlias: nil) }
            resCarry = { self.holeResultVsYo(opponentAlias: opp, hole: $0, carryAlias: req) }
            strokesNormal = { alias, h in
                let s = self.individualMatchupStrokes(yoAlias: self.yoAlias, oppAlias: opp, hole: h, carryAlias: nil)
                return alias == self.yoAlias ? s.yo : s.opp
            }
            strokesCarry = { alias, h in
                let s = self.individualMatchupStrokes(yoAlias: self.yoAlias, oppAlias: opp, hole: h, carryAlias: req)
                return alias == self.yoAlias ? s.yo : s.opp
            }
        case .pair(let laneId):
            guard let lane = lanes.first(where: { $0.id == laneId }),
                  isPairCarryActive(laneId: laneId),
                  let req = pairCarryRequesterByLane[laneId] else { return nil }
            title = "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
            requester = req
            mine = lane.base
            other = lane.opp
            threshold = 3
            resNormal = { self.pairResult(hole: $0, lane: lane) }
            resCarry = { self.pairResult(hole: $0, lane: lane, carryRequesterAlias: req) }
            strokesNormal = { alias, h in self.laneCarrierStroke(lane: lane, alias: alias, hole: h) }
            strokesCarry = { alias, h in self.laneCarrierStroke(lane: lane, alias: alias, hole: h, carryRequesterAlias: req) }
        }

        let aliases = mine + other

        // Strokes de B9 (todos los hoyos, hayan o no sido jugados) y hoyo donde cambia el carry.
        var totalNormal: [String: Double] = [:]
        var totalCarry: [String: Double] = [:]
        var changeHole: Int? = nil
        for h in b9 {
            var delta = 0.0
            for a in aliases {
                let sn = strokesNormal(a, h), sc = strokesCarry(a, h)
                totalNormal[a, default: 0] += sn
                totalCarry[a, default: 0] += sc
                delta += sc - sn
            }
            if changeHole == nil, abs(delta) > 0.001 { changeHole = h }
        }
        let receiverNormal = totalNormal.filter { $0.value > 0.001 }.max { $0.value < $1.value }?.key
        let receiverCarry = totalCarry.filter { $0.value > 0.001 }.max { $0.value < $1.value }?.key
        let bySI = b9.sorted { (getHole($0)?.si ?? 99) < (getHole($1)?.si ?? 99) }
        let changeRank = changeHole.flatMap { bySI.firstIndex(of: $0) }.map { $0 + 1 }

        // Filas con resultado normal y con carry, acumulados y presiones de cada versión.
        var rows: [CarryCardRow] = []
        var normVals: [Int] = []
        var carryVals: [Int] = []
        for h in b9 {
            guard let rn = resNormal(h), let rc = resCarry(h) else { continue }
            normVals.append(rn)
            carryVals.append(rc)
            let presN = (pressureStates(values: normVals, threshold: threshold).last ?? []).filter { $0 != 0 }
            let presC = (pressureStates(values: carryVals, threshold: threshold).last ?? []).filter { $0 != 0 }
            var change = 0.0
            let players: [CarryCardPlayer] = aliases.map { a in
                let sn = strokesNormal(a, h), sc = strokesCarry(a, h)
                change += sc - sn
                return CarryCardPlayer(alias: a, isMySide: mine.contains(a), gross: getScore(hole: h, player: a),
                                       strokesNormal: sn, strokesCarry: sc)
            }
            rows.append(CarryCardRow(
                hole: h, par: getHole(h)?.par ?? 0, si: getHole(h)?.si ?? 0, players: players,
                resultNormal: rn, resultCarry: rc,
                accumNormal: normVals.reduce(0, +), presNormal: presN,
                accumCarry: carryVals.reduce(0, +), presCarry: presC,
                strokeChange: change
            ))
        }

        return CarryCardData(
            title: title, requester: requester,
            normalStrokes: receiverNormal.flatMap { totalNormal[$0] } ?? 0,
            carryStrokes: receiverCarry.flatMap { totalCarry[$0] } ?? 0,
            receiverNormal: receiverNormal, receiverCarry: receiverCarry,
            changeHole: changeHole, changeRank: changeRank, rows: rows
        )
    }
}


// MARK: - Cerrar ronda (compartido por la Vista v1 y la v2)

extension MatchManager {
    /// Único punto que borra datos de la ronda: ajusta strokes entre rondas, guarda el resultado a disco
    /// y limpia scores, apuestas y registro pendiente. El orden es el mismo que tenía ContentView.cerrarRonda().
    func closeRound() {
        // El Directorio se actualiza con ESTE match (strokes usados y próximos, plantilla, resultado, dinero) y de ahí
        // salen los strokes y el tag del siguiente. Los strokes del roster vivo se cambian DESPUÉS de archivar la
        // ronda (el archivo guarda los strokes con los que se jugó).
        let nextStrokes = applyInterMatchStrokeCarry()
        saveRoundResultToFile()
        for (alias, value) in nextStrokes { setStrokesVsBase(alias: alias, value: value) }
        resetScores()
        ScoreManager.shared.clearAll()
        // El match nuevo no hereda Carry / Ajuste 50 / Doble B9 ni el identificador de la ronda cerrada (cada ronda
        // cerrada es un archivo propio). clearCarryDependentState guarda la configuración, así que va ANTES de borrarla.
        clearCarryDependentState()
        generateRoundId()
        clearBetConfig()
        AppDelegate.clearPendingRecord()
    }

    // Ajuste de stroke entre rondas (regla 2026-10-06, solo IND — TEAM queda fuera porque las
    // parejas varían de ronda a ronda). Quien ganó el B9 de un duelo da un golpe más la próxima
    // vez (el rival se vuelve más duro de vencer); quien lo perdió recibe un golpe más. Gatillado
    // por plantilla vía BetTemplate.carryMatchEnabled. Empate en B9 (0) no mueve nada — no hay
    // ganador al que asignarle la dirección del ajuste.
    //
    // Usa siempre el B9 plano (individualB9Vuelta), nunca el ajustado por Carry/Ajuste 50 — la
    // apuesta de Vuelta normal tampoco usa el ajustado (confirmado corriendo walletSnapshot con
    // datos reales el 2026-10-06), así que este ajuste se mantiene consistente con esa línea base.
    //
    // Excepción: si Ajuste 50 estuvo activo, NO se autoaplica ningún stroke — Ajuste 50 redefine
    // el stroke efectivo con su propia fórmula (ganados/perdidos, no un ±1 plano), y replicar esa
    // fórmula para el salto entre rondas es un caso raro que Daniel prefiere resolver a mano. Solo
    // se deja una bandera en lastResult para que se revise el Setup del próximo match contra ese rival.
    @discardableResult
    func applyInterMatchStrokeCarry(directory: PlayerDirectoryStore = .shared) -> [String: Double] {
        var nextStrokes: [String: Double] = [:]
        let opponents = self.players.map(\.alias).filter { $0 != self.yoAlias }
        guard !opponents.isEmpty else { return nextStrokes }
        let snapshot = self.walletSnapshot()
        for opp in opponents {
            guard let player = self.players.first(where: { $0.alias == opp }) else { continue }
            let templateId = self.betValues(forOpponent: opp).templateId
            let carryEnabled = BetTemplateStore.shared.entries.first(where: { $0.id == templateId })?.carryMatchEnabled ?? true

            let f9 = self.individualF9Vuelta(opponentAlias: opp)
            let b9 = self.individualB9Vuelta(opponentAlias: opp)
            let line = snapshot.lines.first(where: { $0.opponentAlias == opp && $0.scope == .individual })
            let matchLabel = line.map { $0.matchPoints >= 0 ? "+\($0.matchPoints)" : "\($0.matchPoints)" } ?? "—"
            let base = "F9 \(f9 >= 0 ? "+" : "")\(f9) · B9 \(b9 >= 0 ? "+" : "")\(b9) · Match \(matchLabel)"
                + " · $\(line?.totalMoney ?? 0) · \(self.dateString)"

            var delta = 0.0
            var summary = base
            if self.isIndividualAdjust50Active(opponentAlias: opp) {
                // Con Ajuste 50 activo se aplica la misma fórmula de medio golpe por hoyo que usa
                // individualAdjust50Profile dentro de la ronda (ganados se restan, perdidos se suman, 0.5 por
                // hoyo), proyectada sobre el B9 recién jugado como si fuera el F9 de un ajuste nuevo.
                let (wins, losses) = self.individualB9WinLossCount(opponentAlias: opp)
                delta = 0.5 * Double(wins - losses)
                summary = "⚖️ Ajuste 50 (B9 \(wins)-\(losses)) · " + base
            } else {
                // El match completo (F9+B9, 18 hoyos) define quién gana — no solo el B9. matchTotal > 0 = yo gané:
                // el rival recibe un golpe más (+1); matchTotal < 0 = yo perdí: da un golpe más (-1). Un empate (0)
                // no mueve los strokes, pero el match SÍ se registra en el Directorio.
                let matchTotal = f9 + b9
                delta = matchTotal > 0 ? 1 : (matchTotal < 0 ? -1 : 0)
            }
            // Si la plantilla de este rival no pide ajuste entre rondas, el match se registra igual pero sin mover strokes.
            if !carryEnabled { delta = 0 }

            let used = player.strokesVsBase
            let next = used + delta
            directory.recordClosedMatch(
                playerName: player.name, alias: player.alias, strokesUsed: used, nextStrokes: next,
                templateId: templateId, resultSummary: summary, roundId: self.roundId, moneyMxn: line?.totalMoney ?? 0
            )
            nextStrokes[opp] = next
        }
        return nextStrokes
    }

    // Guarda el resultado final (scores + wallet) a disco antes de borrar.
    func saveRoundResultToFile() {
        let snapshot = self.walletSnapshot()
        let lines = snapshot.lines.map { line -> RoundResultLine in
            // F9/B9 por rival solo aplica a IND (igual que applyInterMatchStrokeCarry) — las
            // parejas varían de ronda a ronda, no hay "próximo match" fijo contra el que comparar.
            let isIndividual = line.scope.rawValue == "individual"
            let f9 = isIndividual ? line.opponentAlias.map { self.individualF9Vuelta(opponentAlias: $0) } : nil
            let b9 = isIndividual ? line.opponentAlias.map { self.individualB9Vuelta(opponentAlias: $0) } : nil
            return RoundResultLine(
                label: line.label, scope: line.scope.rawValue, opponentAlias: line.opponentAlias,
                vueltaPoints: line.vueltaPoints, presionPoints: line.presionPoints,
                carryPoints: line.carryPoints, carryActive: line.carryActive,
                matchPoints: line.matchPoints, unitsPoints: line.unitsPoints,
                vueltaMoney: line.vueltaMoney, presionMoney: line.presionMoney,
                carryMoney: line.carryMoney, matchMoney: line.matchMoney,
                unitsMoney: line.unitsMoney, totalMoney: line.totalMoney,
                f9Points: f9, b9Points: b9
            )
        }
        let players = self.players.map { p -> RoundResultPlayer in
            var scores: [String: Int] = [:]
            var putts: [String: Int] = [:]
            for (hole, entry) in p.scores {
                scores["\(hole)"] = entry.gross
                if let pu = entry.putts { putts["\(hole)"] = pu }
            }
            return RoundResultPlayer(alias: p.alias, name: p.name, strokesVsBase: p.strokesVsBase, scores: scores, putts: putts)
        }
        var oyesWins: [String: Int] = [:]
        for (_, ranks) in self.oyesRanksByHole {
            for (alias, rank) in ranks where rank == 1 {
                oyesWins[alias, default: 0] += 1
            }
        }
        let file = RoundResultFile(
            roundId: self.roundId, date: self.dateString,
            courseId: self.courseId, courseName: self.courseName,
            startHole: self.startHole, players: players, lines: lines,
            totalMoney: snapshot.totalMoney, closedAt: Date(),
            oyesWinsByAlias: oyesWins
        )
        guard let roundsDir = RoundResultFile.closedRoundsDirectory() else { return }
        try? FileManager.default.createDirectory(at: roundsDir, withIntermediateDirectories: true)
        let fileURL = roundsDir.appendingPathComponent("\(file.roundId).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(file)
            try data.write(to: fileURL)
            print("✅ Ronda cerrada, resultado guardado en: \(fileURL)")
        } catch {
            print("❌ Error guardando resultado de ronda: \(error)")
        }
    }
}

// MARK: - Carga inicial del match (la Vista v2 también puede ser la primera en abrirse)

extension MatchManager {
    func loadInitialMatchState() {
        didRunInitialSetup = true
        // loadBetConfig() primero: restaura el roster (players), el campo y el hoyo de salida
        // desde el snapshot persistido antes de que syncFromScoreManager() intente reaplicar
        // scores por alias — si players sigue vacío en este punto, ese replay no encuentra a
        // nadie y descarta todo en silencio.
        // Bug reportado: antes match_meta.json (startingHole: 1 + roster fijo) se aplicaba SIEMPRE
        // antes de esto, en cada relanzamiento y cada vez que ContentView reaparecía. Pisaba el
        // hoyo de salida guardado desde el Setup, y como players ya no estaba vacío,
        // loadBetConfig() tampoco restauraba el roster ni el hoyo guardados.
        self.loadBetConfig()
        // match_meta.json solo siembra un match NUEVO (nada restaurado). Segunda pasada de
        // loadBetConfig() para aplicar por alias strokes/lanes de un snapshot sin roster.
        if self.players.isEmpty {
            let metaPlayers = SiriMatchManager.shared.getPlayers()
            if !metaPlayers.isEmpty {
                self.setPlayers(names: metaPlayers, preserveScores: true)
                let metaStart = SiriMatchManager.shared.getStartingHole()
                if metaStart > 0 { self.startHole = metaStart }
                self.loadBetConfig()
            }
        }
        self.syncFromScoreManager()
        #if DEBUG
        // Solo simulador/debug: carga una ronda de 18 hoyos con `defaults write <bundle> demo18 -bool YES`.
        if UserDefaults.standard.bool(forKey: "demo18") { self.loadDemo18() }
        #endif
    }
}


// MARK: - Guardado del Setup (compartido por el Setup de la v1 y SetupV2)

extension MatchManager {
    /// Todo lo que el Setup (4 pasos) deja escrito antes de guardar.
    struct SetupDraft {
        var courseId: String
        var startHole: Int
        var playerNames: [String]
        /// Alias que el Setup calculó para esos nombres (mismo orden).
        var aliases: [String]
        var strokesByAlias: [String: Double]
        var templateIdByOpponent: [String: String]
        var base1: String
        var base2: String
        var laneStrokes: [String: Double]
        var laneCarrierByKey: [String: String]
        var selectedTemplateId: String
        var vueltaValueText: String
    }

    /// Los carriles (parejas contra parejas) que salen de la pareja base: misma regla que el Setup de la v1.
    static func setupLanes(base: [String], allAliases: [String]) -> [(id: String, base: [String], opp: [String])] {
        guard base.count >= 2 else { return [] }
        let opp = allAliases.filter { !base.contains($0) }
        func make(_ pair: [String]) -> (id: String, base: [String], opp: [String]) {
            (id: (base.sorted() + ["vs"] + pair.sorted()).joined(separator: "-"), base: base, opp: pair)
        }
        if opp.count == 2 { return [make(opp)] }
        if opp.count == 3 { return [[opp[0], opp[1]], [opp[0], opp[2]], [opp[1], opp[2]]].map(make) }
        return []
    }

    /// Paso Campo: aplica campo y hoyo de salida. Si mueven el F9 (campo u hoyo de salida distintos),
    /// Carry/Ajuste 50/Doble Press se invalidan igual que en applySetupDraft.
    func applyCourseAndStartHole(courseId: String, startHole: Int) {
        let signatureBefore = strokeSetupSignature
        if let course = CourseCatalog.all.first(where: { $0.id == courseId }) {
            setCourse(course, resetScores: false)
        }
        updateStartHole(startHole, resetScores: false)
        if strokeSetupSignature != signatureBefore { clearCarryDependentState() }
        finishSetupApply()
    }

    func applySetupDraft(_ draft: SetupDraft) {
        let templates = BetTemplateStore.shared.entries
        // Si algo que alimenta el reparto de golpes cambia (hoyo de salida, strokes, parejas,
        // quién carga), el F9 y todo lo que se decidió con él (Carry, Ajuste 50, Doble Press)
        // queda calculado sobre datos viejos — se compara antes/después para invalidarlo.
        let signatureBefore = strokeSetupSignature
        if let course = CourseCatalog.all.first(where: { $0.id == draft.courseId }) {
            setCourse(course, resetScores: false)
        }
        updateStartHole(draft.startHole, resetScores: false)
        setPlayers(names: draft.playerNames, preserveScores: true)
        for p in players {
            if p.alias == yoAlias { continue }
            let strokes = draft.strokesByAlias[p.alias] ?? 0
            setStrokesVsBase(alias: p.alias, value: strokes)
            let tplId = draft.templateIdByOpponent[p.alias]
            if let tplId, let tpl = templates.first(where: { $0.id == tplId }) {
                setBetTemplateForOpponent(p.alias, template: tpl)
            }
            // Aprende/actualiza el directorio con lo que realmente quedó configurado para este
            // jugador — la próxima vez que se escriba su nombre, el mini-search ya sugiere estos
            // mismos strokes y plantilla.
            PlayerDirectoryStore.shared.upsert(name: p.name, alias: p.alias, strokesVsBase: strokes, preferredTagId: tplId)
        }
        let base = [draft.base1, draft.base2].filter { !$0.isEmpty }
        if base.count >= 2 {
            let opp = players.map { $0.alias }.filter { !base.contains($0) }
            _ = setBaseTeam(base, opponentsOverride: opp)
            for lane in Self.setupLanes(base: base, allAliases: draft.aliases) {
                setLaneStrokesForMatch(base: lane.base, opp: lane.opp, value: draft.laneStrokes[lane.id] ?? 0)
                if let carrier = draft.laneCarrierByKey[lane.id], !carrier.isEmpty {
                    setLaneCarrierForMatch(base: lane.base, opp: lane.opp, carrier: carrier)
                }
            }
        }
        if let tpl = templates.first(where: { $0.id == draft.selectedTemplateId }) {
            applyBetTemplate(tpl)
            // Si el usuario ajustó el monto de vuelta a mano después de elegir la plantilla, respeta ese override.
            if let v = Int(draft.vueltaValueText), v != tpl.vueltaValue { setVueltaValue(v) }
        } else if let v = Int(draft.vueltaValueText) {
            setVueltaValue(v)
        }
        if strokeSetupSignature != signatureBefore { clearCarryDependentState() }
        // Un solo guardado al final con el Setup completo (setCourse no guarda por sí solo) y un
        // refresh explícito para que tarjeta, auditoría y dinero se recalculen con lo nuevo.
        finishSetupApply()
    }
}

// MARK: - Borrador del Setup (estado y reglas del Setup guiado, para la Vista v2)
//
// Misma lógica que GuidedSetupView (loadDefaults, addPlayerName, syncStrokes, syncLaneSetupState, ajustes de
// strokes): vive aquí, fuera de la vista, para poder probarla. La v1 conserva su copia en @State.

extension MatchManager {
    /// Alias de cada nombre: 3 primeras letras en mayúsculas, con contador si se repiten (igual que el Setup de la v1).
    static func setupAliases(from names: [String]) -> [(alias: String, name: String)] {
        var out: [(alias: String, name: String)] = []
        for name in names {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { continue }
            let letters = clean.uppercased().filter { $0.isLetter }
            if letters.isEmpty { continue }
            let existing = out.map { $0.alias }
            var alias = String(letters.prefix(3))
            var counter = 1
            while existing.contains(alias) { alias = String(letters.prefix(3)) + String(counter); counter += 1 }
            out.append((alias: alias, name: clean))
        }
        return out
    }

    /// Hoyos donde cae cada golpe, en orden de juego: "hoyos 17, 4, 11 y ½ en 2" (nil si no hay golpes).
    func strokeHolesText(total: Double, startHole: Int) -> String? {
        let amount = abs(total)
        guard amount > 0, holes.count == 18 else { return nil }
        let start = max(1, min(18, startHole))
        let order = (0..<18).map { ((start - 1 + $0) % 18) + 1 }
        var whole: [Int] = []
        var halves: [Int] = []
        for hole in order {
            let v = Self.distributedStrokes(total: amount, hole: hole, startHole: start, holes: holes)
            if v >= 1 { whole.append(hole) } else if v > 0 { halves.append(hole) }
        }
        var parts: [String] = []
        if !whole.isEmpty { parts.append("hoyos " + whole.map(String.init).joined(separator: ", ")) }
        if !halves.isEmpty { parts.append("½ en " + halves.map(String.init).joined(separator: ", ")) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " y ")
    }
}

final class SetupDraftModel: ObservableObject {
    let manager: MatchManager
    @Published var courseId = ""
    @Published var startHole = 1
    @Published var playerNames: [String] = []
    @Published var strokesByAlias: [String: Double] = [:]
    @Published var templateIdByOpponent: [String: String] = [:]
    @Published var base1 = ""
    @Published var base2 = ""
    @Published var laneStrokes: [String: Double] = [:]
    @Published var laneCarrierByKey: [String: String] = [:]
    @Published var selectedTemplateId = ""
    @Published var vueltaValueText = ""

    init(manager: MatchManager) { self.manager = manager }

    var aliasList: [(alias: String, name: String)] { MatchManager.setupAliases(from: playerNames) }
    var aliases: [String] { aliasList.map { $0.alias } }
    var rivals: [(alias: String, name: String)] { aliasList.filter { $0.alias != manager.yoAlias } }
    var baseAliases: [String] { [base1, base2].filter { !$0.isEmpty } }
    var opponentsForBase: [String] { aliases.filter { !baseAliases.contains($0) } }
    var lanes: [(id: String, base: [String], opp: [String])] {
        MatchManager.setupLanes(base: baseAliases, allAliases: aliases)
    }

    var draft: MatchManager.SetupDraft {
        MatchManager.SetupDraft(
            courseId: courseId, startHole: startHole, playerNames: playerNames, aliases: aliases,
            strokesByAlias: strokesByAlias, templateIdByOpponent: templateIdByOpponent,
            base1: base1, base2: base2, laneStrokes: laneStrokes, laneCarrierByKey: laneCarrierByKey,
            selectedTemplateId: selectedTemplateId, vueltaValueText: vueltaValueText)
    }

    /// Carga lo que tiene el match en curso (solo la primera vez).
    func load() {
        if !courseId.isEmpty { return }
        courseId = manager.courseId.isEmpty ? CourseCatalog.default.id : manager.courseId
        startHole = manager.startHole
        playerNames = manager.players.map { $0.name }
        syncStrokes()
        // Restaura la pareja base real del match; si no hay (match nuevo), caen los dos primeros.
        let live = Set(manager.players.map { $0.alias })
        let existing = manager.baseTeamAliases.filter { live.contains($0) }
        if existing.count >= 2 {
            base1 = existing[0]; base2 = existing[1]
        } else {
            if let first = aliasList.first?.alias { base1 = first }
            if aliasList.count > 1 { base2 = aliasList[1].alias }
        }
        syncLanes()
        vueltaValueText = manager.vueltaValue > 0 ? "\(manager.vueltaValue)" : ""
        selectedTemplateId = manager.activeTemplateId ?? ""
    }

    func syncStrokes() {
        let current = aliases.filter { $0 != manager.yoAlias }
        for a in current where strokesByAlias[a] == nil {
            // Un jugador que YA está en el match conserva exactamente sus strokes (también 0); uno nuevo arranca en 0.
            strokesByAlias[a] = manager.players.first(where: { $0.alias == a })?.strokesVsBase ?? 0
        }
        for key in strokesByAlias.keys where !current.contains(key) { strokesByAlias.removeValue(forKey: key) }
        for a in current where templateIdByOpponent[a] == nil {
            templateIdByOpponent[a] = manager.betValuesByOpponent[a]?.templateId
                ?? BetTemplateStore.shared.entries.first?.id ?? ""
        }
        for key in templateIdByOpponent.keys where !current.contains(key) { templateIdByOpponent.removeValue(forKey: key) }
    }

    func syncBaseDefaults() {
        if base1.isEmpty, let first = aliasList.first?.alias { base1 = first }
        if base2.isEmpty, aliasList.count > 1 { base2 = aliasList[1].alias }
    }

    func syncLanes() {
        let current = lanes
        let keys = Set(current.map { $0.id })
        for lane in current {
            if laneStrokes[lane.id] == nil {
                if let existing = manager.lanes.first(where: { Set($0.base) == Set(lane.base) && Set($0.opp) == Set(lane.opp) }) {
                    laneStrokes[lane.id] = existing.strokes
                    laneCarrierByKey[lane.id] = existing.strokeCarrier ?? ""
                } else {
                    laneStrokes[lane.id] = 0; laneCarrierByKey[lane.id] = ""
                }
            } else if laneCarrierByKey[lane.id] == nil {
                laneCarrierByKey[lane.id] = ""
            }
        }
        for key in laneStrokes.keys where !keys.contains(key) { laneStrokes.removeValue(forKey: key) }
        for key in laneCarrierByKey.keys where !keys.contains(key) { laneCarrierByKey.removeValue(forKey: key) }
    }

    /// Agrega un jugador (máximo 5). Si viene del directorio, toma sus strokes y plantilla.
    func addPlayer(_ rawName: String, directoryMatch: PlayerDirectoryEntry?) {
        let clean = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, playerNames.count < 5 else { return }
        let match = directoryMatch ?? PlayerDirectoryStore.shared.entries.first(where: {
            $0.name.caseInsensitiveCompare(clean) == .orderedSame
        })
        playerNames.append(clean)
        syncStrokes(); syncBaseDefaults(); syncLanes()
        if let match, match.name.caseInsensitiveCompare(clean) == .orderedSame,
           let alias = aliasList.first(where: { $0.name == clean })?.alias {
            strokesByAlias[alias] = match.strokesVsBase
            if let tag = match.preferredTagId { templateIdByOpponent[alias] = tag }
        }
    }

    func removePlayer(at index: Int) {
        guard playerNames.indices.contains(index) else { return }
        playerNames.remove(at: index)
        syncStrokes(); syncBaseDefaults(); syncLanes()
    }

    func adjustStroke(alias: String, delta: Double) {
        let next = max(-20, min(20, (strokesByAlias[alias] ?? 0) + delta))
        strokesByAlias[alias] = (next * 2).rounded() / 2
    }

    func adjustLaneStroke(key: String, delta: Double) {
        let next = max(0, min(20, (laneStrokes[key] ?? 0) + delta))
        laneStrokes[key] = (next * 2).rounded() / 2
    }

    func applyTemplate(_ template: BetTemplate) {
        selectedTemplateId = template.id
        vueltaValueText = "\(template.vueltaValue)"
    }

    /// Mismas condiciones que `canAdvance()` de la v1. step: 0 = Campo, 1 = Oponentes, 2 = Parejas.
    func canAdvance(step: Int) -> Bool {
        switch step {
        case 0: return !courseId.isEmpty && startHole >= 1 && startHole <= 18
        case 1: return playerNames.count >= 2 && playerNames.count <= 5 && !aliasList.isEmpty
        default: return aliasList.count < 4 || (base1 != base2 && !base1.isEmpty && !base2.isEmpty)
        }
    }

    func applyCourseAndStartHole() {
        manager.applyCourseAndStartHole(courseId: courseId, startHole: startHole)
    }

    func save() { manager.applySetupDraft(draft) }
}


// MARK: - El catálogo de apuestas gobierna qué cuenta (Oyes, Oyes Parejas, Match Parejas, unidades manuales)
//
// betCatalog = las definiciones ACTIVAS del catálogo (ver setupDefaultBets). Una lista vacía (aún sin cargar) cuenta
// como "todo activo" para no apagar nada por accidente.

extension MatchManager {
    func isCatalogTagEnabled(_ tag: String) -> Bool {
        if betCatalog.isEmpty { return true }
        return betCatalog.contains { $0.tag.uppercased() == tag.uppercased() }
    }

    /// Valor ("Vale") de una unidad del catálogo activo, nil si no está.
    func catalogUnits(forTag tag: String) -> Int? {
        betCatalog.first { $0.tag.uppercased() == tag.uppercased() }?.units
    }

    var isOyesEnabled: Bool { isCatalogTagEnabled("OYES") }
    var isOyesPairEnabled: Bool { isCatalogTagEnabled("OYESP") }
    var isPairMatchEnabled: Bool { isCatalogTagEnabled("PAIR") }

    /// Las parejas que participan: ninguna si "Match Parejas" está apagado en el catálogo.
    var activeLanes: [LaneModel] { isPairMatchEnabled ? lanes : [] }

    /// ¿Cuenta un evento manual con este código? Una unidad conocida del catálogo que está apagada no cuenta
    /// (sus eventos ya anotados se conservan y vuelven a contar si se reactiva). Notas y códigos desconocidos cuentan.
    func isUnitCodeActive(_ code: String) -> Bool {
        let c = code.uppercased()
        if c == "NOTA" { return true }
        guard BetDefinitionStore.shared.entries.contains(where: { $0.tag.uppercased() == c }) else { return true }
        return isCatalogTagEnabled(c)
    }
}
