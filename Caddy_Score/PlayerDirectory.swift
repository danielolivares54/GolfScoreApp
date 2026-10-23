import Foundation
import Combine

// Un jugador conocido — strokes y plantilla de apuesta que normalmente se le asignan, para no
// tener que recapturarlos cada ronda. Ver SSOT Sección 17 (PLAYER_BET_TAGS) y ST-14 ("el Tag
// sugiere la apuesta, el Match conserva la decisión final").
struct PlayerDirectoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var alias: String
    var strokesVsBase: Double
    var preferredTagId: String?
    var lastUsedAt: Date = Date()
    // Jugadores inactivos no aparecen en el mini-search del Setup por default, pero siguen
    // visibles/editables desde la pantalla de administración del directorio.
    var active: Bool = true

    // Campos heredados de la hoja de control (Players_Current_Siri_v3) — se conservan como
    // contexto histórico aunque el Setup actual no los use todos.
    var opponentTee: String?
    var adjustmentNotes: String?
    var lastResult: String?
    var strokeAnt: Double?
    var myTee: String?
    var comentario: String?
    var gameMoneyMxn: Double?
    var accumulatedMxn: Double?
    // Liga este jugador con su última entrada en el log de matches (Matches/UNITS_LOG, SSOT
    // Sección 14) para poder trazar de qué partida vienen sus datos acumulados.
    var lastKeyId: String?
    // Fecha del último match CERRADO contra este jugador (lastUsedAt también se mueve al guardar un Setup).
    var lastGameAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, alias, strokesVsBase, preferredTagId, lastUsedAt, active
        case opponentTee, adjustmentNotes, lastResult, strokeAnt, myTee, comentario
        case gameMoneyMxn, accumulatedMxn, lastKeyId, lastGameAt
    }

    init(id: UUID = UUID(), name: String, alias: String, strokesVsBase: Double, preferredTagId: String? = nil, lastUsedAt: Date = Date(), active: Bool = true, opponentTee: String? = nil, adjustmentNotes: String? = nil, lastResult: String? = nil, strokeAnt: Double? = nil, myTee: String? = nil, comentario: String? = nil, gameMoneyMxn: Double? = nil, accumulatedMxn: Double? = nil, lastKeyId: String? = nil, lastGameAt: Date? = nil) {
        self.id = id
        self.name = name
        self.alias = alias
        self.strokesVsBase = strokesVsBase
        self.preferredTagId = preferredTagId
        self.lastUsedAt = lastUsedAt
        self.active = active
        self.opponentTee = opponentTee
        self.adjustmentNotes = adjustmentNotes
        self.lastResult = lastResult
        self.strokeAnt = strokeAnt
        self.myTee = myTee
        self.comentario = comentario
        self.gameMoneyMxn = gameMoneyMxn
        self.accumulatedMxn = accumulatedMxn
        self.lastKeyId = lastKeyId
        self.lastGameAt = lastGameAt
    }

    // Decodificación manual: los JSON guardados antes de agregar un campo nuevo no lo traen, y
    // el decoder sintetizado no aplica los defaults de arriba cuando falta una key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        alias = try c.decode(String.self, forKey: .alias)
        strokesVsBase = try c.decode(Double.self, forKey: .strokesVsBase)
        preferredTagId = try c.decodeIfPresent(String.self, forKey: .preferredTagId)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt) ?? Date()
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        opponentTee = try c.decodeIfPresent(String.self, forKey: .opponentTee)
        adjustmentNotes = try c.decodeIfPresent(String.self, forKey: .adjustmentNotes)
        lastResult = try c.decodeIfPresent(String.self, forKey: .lastResult)
        strokeAnt = try c.decodeIfPresent(Double.self, forKey: .strokeAnt)
        myTee = try c.decodeIfPresent(String.self, forKey: .myTee)
        comentario = try c.decodeIfPresent(String.self, forKey: .comentario)
        gameMoneyMxn = try c.decodeIfPresent(Double.self, forKey: .gameMoneyMxn)
        accumulatedMxn = try c.decodeIfPresent(Double.self, forKey: .accumulatedMxn)
        lastKeyId = try c.decodeIfPresent(String.self, forKey: .lastKeyId)
        lastGameAt = try c.decodeIfPresent(Date.self, forKey: .lastGameAt)
    }
}

final class PlayerDirectoryStore: ObservableObject {
    static let shared = PlayerDirectoryStore()

    @Published private(set) var entries: [PlayerDirectoryEntry] = []

    private let fileName: String

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    /// `fileName` distinto solo para pruebas (que no toquen el directorio real).
    init(fileName: String = "player_directory.json") {
        self.fileName = fileName
        load()
        if entries.isEmpty {
            seedInitialData()
        }
    }

    // Prefijo sobre nombre o alias — "An" encuentra "Anselmo" (alias "ANS"). Los usados más
    // recientemente salen primero, para que el candidato más probable quede arriba.
    func search(_ query: String) -> [PlayerDirectoryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return entries
            .filter { $0.active && ($0.name.lowercased().hasPrefix(q) || $0.alias.lowercased().hasPrefix(q)) }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    // Agrega o actualiza por nombre (insensible a mayúsculas) — se llama tanto al aprender
    // automáticamente desde el Setup como al editar manualmente desde el directorio.
    func upsert(name: String, alias: String, strokesVsBase: Double, preferredTagId: String?, active: Bool = true, lastUsedAt: Date = Date(), opponentTee: String? = nil, adjustmentNotes: String? = nil, lastResult: String? = nil, strokeAnt: Double? = nil, myTee: String? = nil, comentario: String? = nil, gameMoneyMxn: Double? = nil, accumulatedMxn: Double? = nil, lastKeyId: String? = nil) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        if let idx = entries.firstIndex(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            entries[idx].alias = alias
            entries[idx].strokesVsBase = strokesVsBase
            entries[idx].preferredTagId = preferredTagId ?? entries[idx].preferredTagId
            entries[idx].active = active
            entries[idx].lastUsedAt = lastUsedAt
            entries[idx].opponentTee = opponentTee ?? entries[idx].opponentTee
            entries[idx].adjustmentNotes = adjustmentNotes ?? entries[idx].adjustmentNotes
            entries[idx].lastResult = lastResult ?? entries[idx].lastResult
            entries[idx].strokeAnt = strokeAnt ?? entries[idx].strokeAnt
            entries[idx].myTee = myTee ?? entries[idx].myTee
            entries[idx].comentario = comentario ?? entries[idx].comentario
            entries[idx].gameMoneyMxn = gameMoneyMxn ?? entries[idx].gameMoneyMxn
            entries[idx].accumulatedMxn = accumulatedMxn ?? entries[idx].accumulatedMxn
            entries[idx].lastKeyId = lastKeyId ?? entries[idx].lastKeyId
        } else {
            entries.append(PlayerDirectoryEntry(name: cleanName, alias: alias, strokesVsBase: strokesVsBase, preferredTagId: preferredTagId, lastUsedAt: lastUsedAt, active: active, opponentTee: opponentTee, adjustmentNotes: adjustmentNotes, lastResult: lastResult, strokeAnt: strokeAnt, myTee: myTee, comentario: comentario, gameMoneyMxn: gameMoneyMxn, accumulatedMxn: accumulatedMxn, lastKeyId: lastKeyId))
        }
        save()
    }

    // Asigna estos campos directamente (a diferencia de upsert, que preserva el valor viejo si
    // llega nil) — así la edición manual puede borrar un tee/nota/stroke anterior, no solo rellenarlo.
    func setDetails(id: UUID, opponentTee: String?, myTee: String?, adjustmentNotes: String?, comentario: String?, strokeAnt: Double?) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].opponentTee = opponentTee
        entries[idx].myTee = myTee
        entries[idx].adjustmentNotes = adjustmentNotes
        entries[idx].comentario = comentario
        entries[idx].strokeAnt = strokeAnt
        save()
    }

    // Ajuste de stroke entre rondas (regla 2026-10-06): quien ganó el B9 de un duelo IND mueve
    // ±1 el strokeVsBase del rival para el próximo match. El valor viejo se conserva en
    // strokeAnt, y resultSummary/roundId quedan en lastResult/lastKeyId como la bitácora de
    // "por qué cambió" — se consulta la próxima vez que se arme el Setup contra ese rival.
    func applyMatchStrokeShift(playerName: String, delta: Double, resultSummary: String, roundId: String) {
        guard let idx = entries.firstIndex(where: { $0.name.caseInsensitiveCompare(playerName) == .orderedSame }) else { return }
        entries[idx].strokeAnt = entries[idx].strokesVsBase
        entries[idx].strokesVsBase += delta
        entries[idx].lastResult = resultSummary
        entries[idx].lastKeyId = roundId
        entries[idx].lastUsedAt = Date()
        save()
    }

    /// Al CERRAR un match: el Directorio queda listo para el siguiente. Guarda los strokes que se usaron (strokeAnt), los
    /// que valen para el próximo (strokesVsBase; sin cambio si el match empató), la plantilla de apuesta usada
    /// (preferredTagId), el resultado, la fecha del último juego y el dinero (último y acumulado). Cada match se registra
    /// una sola vez (por roundId); un empate también se registra.
    func recordClosedMatch(playerName: String, alias: String, strokesUsed: Double, nextStrokes: Double, templateId: String?,
                           resultSummary: String, roundId: String, moneyMxn: Int, date: Date = Date()) {
        let cleanName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        var idx = entries.firstIndex(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame })
        if idx == nil {
            entries.append(PlayerDirectoryEntry(name: cleanName, alias: alias, strokesVsBase: nextStrokes, preferredTagId: templateId))
            idx = entries.count - 1
        }
        guard let i = idx, entries[i].lastKeyId != roundId else { return }
        entries[i].strokeAnt = strokesUsed
        entries[i].strokesVsBase = nextStrokes
        if let templateId, !templateId.isEmpty { entries[i].preferredTagId = templateId }
        entries[i].lastResult = resultSummary
        entries[i].lastKeyId = roundId
        entries[i].lastGameAt = date
        entries[i].lastUsedAt = date
        entries[i].gameMoneyMxn = Double(moneyMxn)
        entries[i].accumulatedMxn = (entries[i].accumulatedMxn ?? 0) + Double(moneyMxn)
        save()
    }

    func remove(_ entry: PlayerDirectoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url)
        } catch {
            print("❌ Error guardando directorio de jugadores: \(error)")
        }
    }

    private func load() {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([PlayerDirectoryEntry].self, from: data)
        } catch {
            print("❌ Error cargando directorio de jugadores: \(error)")
        }
    }

    // Semilla de arranque: si el directorio está vacío (primer lanzamiento, o reinstalación que
    // borró el contenedor), carga la hoja de control histórica (Players_Current_Siri_v3) una
    // sola vez. No pisa nada si ya hay datos — upsert por nombre es idempotente si se corre dos veces.
    private func seedInitialData() {
        guard let data = PlayerDirectorySeed.json.data(using: .utf8),
              let seedDict = try? JSONDecoder().decode([String: PlayerDirectorySeed.Record].self, from: data) else {
            return
        }
        var usedAliases = Set(entries.map { $0.alias })
        for rec in seedDict.values.sorted(by: { $0.player_name < $1.player_name }) {
            let letters = rec.player_name.uppercased().filter { $0.isLetter }
            let base = String(letters.prefix(3))
            var alias = base
            var counter = 1
            while usedAliases.contains(alias) {
                alias = base + String(counter)
                counter += 1
            }
            usedAliases.insert(alias)

            let tagId: String?
            if rec.tag_ind == "Tpch" { tagId = "TPCH" }
            else if rec.tag_ind == "Jue" { tagId = "JUEVES" }
            else { tagId = nil }

            let lastUsed = PlayerDirectorySeed.parseDate(rec.last_game_date) ?? Date()

            upsert(
                name: rec.player_name,
                alias: alias,
                strokesVsBase: rec.strokes,
                preferredTagId: tagId,
                active: rec.active,
                lastUsedAt: lastUsed,
                opponentTee: PlayerDirectorySeed.blank(rec.opponent_tee),
                adjustmentNotes: PlayerDirectorySeed.blank(rec.adjustment_notes),
                lastResult: PlayerDirectorySeed.blank(rec.last_result),
                strokeAnt: PlayerDirectorySeed.zeroToNil(rec.stroke_ant),
                myTee: PlayerDirectorySeed.blank(rec.my_tee),
                comentario: PlayerDirectorySeed.blank(rec.comentario),
                gameMoneyMxn: PlayerDirectorySeed.zeroToNil(rec.game_money_mxn),
                accumulatedMxn: PlayerDirectorySeed.zeroToNil(rec.accumulated_mxn)
            )
        }
    }
}

// Datos de arranque tomados de Players_Current_Siri_v3.json (hoja de control histórica del
// usuario) — sólo se usan una vez, cuando el directorio está vacío. Ver seedInitialData() arriba.
private enum PlayerDirectorySeed {
    struct Record: Decodable {
        let player_name: String
        let strokes: Double
        let tag_ind: String
        let last_game_date: String
        let active: Bool
        let opponent_tee: String
        let adjustment_notes: String
        let last_result: String
        let stroke_ant: Double
        let my_tee: String
        let comentario: String
        let game_money_mxn: Double
        let accumulated_mxn: Double
    }

    static func blank(_ s: String) -> String? {
        if s.isEmpty { return nil }
        return s
    }

    static func zeroToNil(_ d: Double) -> Double? {
        if d == 0 { return nil }
        return d
    }

    static func parseDate(_ raw: String) -> Date? {
        if raw.isEmpty { return nil }
        let f1 = DateFormatter()
        f1.dateFormat = "yyyy-MM-dd"
        if let d = f1.date(from: raw) { return d }
        let f2 = DateFormatter()
        f2.dateFormat = "d MMM yyyy 'at' HH:mm"
        f2.locale = Locale(identifier: "en_US")
        if let d = f2.date(from: raw) { return d }
        return nil
    }

    static let json = #"""
    {"Gustavo":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":0,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Gustavo","accumulated_mxn":0},"Miguel Ángel":{"opponent_tee":"Doradas","adjustment_notes":"No","active":true,"strokes":3,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Miguel Ángel","accumulated_mxn":0},"Fernando":{"opponent_tee":"Doradas","adjustment_notes":"","active":true,"strokes":5,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"50/50","comentario":"50/50/0/25","game_money_mxn":0,"player_name":"Fernando","accumulated_mxn":0},"Al Crespo":{"opponent_tee":"Verdes / Doradas","adjustment_notes":"no","active":true,"strokes":-3,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Al Crespo","accumulated_mxn":0},"Luis V":{"opponent_tee":"Verdes","adjustment_notes":"Ajustado","active":true,"strokes":3,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Luis V","accumulated_mxn":0},"Carlos Ángel":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":7,"last_result":"","stroke_ant":0,"last_game_date":"2025-05-06","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Carlos Ángel","accumulated_mxn":0},"Orozco Raúl":{"opponent_tee":"Verdes","adjustment_notes":"Ajustado","active":true,"strokes":8,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Orozco Raúl","accumulated_mxn":0},"Ricardo Fernández":{"opponent_tee":"Doradas","adjustment_notes":"Carry","active":true,"strokes":0,"last_result":"","stroke_ant":0,"last_game_date":"2025-05-04","my_tee":"","tag_ind":"50/50","comentario":"50/50/0/25","game_money_mxn":0,"player_name":"Ricardo Fernández","accumulated_mxn":0},"Julian":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":0,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Julian","accumulated_mxn":0},"Jesús":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":4,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Jesús","accumulated_mxn":0},"Federico":{"opponent_tee":"Doradas","adjustment_notes":"Ajustado","active":true,"strokes":1,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Federico","accumulated_mxn":0},"Roberto Sr":{"opponent_tee":"Verdes","adjustment_notes":"Así","active":true,"strokes":10,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"50/50","comentario":"50/50/0/25","game_money_mxn":0,"player_name":"Roberto Sr","accumulated_mxn":0},"Jorge":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":3,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"40/40","comentario":"40/40/0/20","game_money_mxn":0,"player_name":"Jorge","accumulated_mxn":0},"Ricardo GR":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":6,"last_result":"","stroke_ant":0,"last_game_date":"2026-02-18","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Ricardo GR","accumulated_mxn":0},"J. Reynoso":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":4,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"J. Reynoso","accumulated_mxn":0},"Dr. Luis G":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":7,"last_result":"","stroke_ant":0,"last_game_date":"2026-08-10","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Dr. Luis G","accumulated_mxn":0},"D. Ruiz":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":11,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"D. Ruiz","accumulated_mxn":0},"T. Wolf":{"opponent_tee":"Verdes","adjustment_notes":"l","active":true,"strokes":2,"last_result":"","stroke_ant":0,"last_game_date":"2017-06-01","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"T. Wolf","accumulated_mxn":0},"Jorge Camargo":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":0.5,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Jorge Camargo","accumulated_mxn":0},"Adolfo Blasquez":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":6,"last_result":"","stroke_ant":0,"last_game_date":"2025-06-05","my_tee":"","tag_ind":"Jue","comentario":"80/40/40/20","game_money_mxn":0,"player_name":"Adolfo Blasquez","accumulated_mxn":0},"Carlos Muñoz":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":4,"last_result":"","stroke_ant":0,"last_game_date":"2025-06-04","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Carlos Muñoz","accumulated_mxn":0},"Armando Lepe":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":10,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Armando Lepe","accumulated_mxn":0},"Jorge Jr":{"opponent_tee":"Doradas","adjustment_notes":"","active":true,"strokes":11,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Jorge Jr","accumulated_mxn":0},"Ricardo Salido":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":5,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Jue","comentario":"80/40/40/20","game_money_mxn":0,"player_name":"Ricardo Salido","accumulated_mxn":0},"A Olivares":{"opponent_tee":"Ajuste","adjustment_notes":"","active":true,"strokes":1,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"A Olivares","accumulated_mxn":0},"J. González":{"opponent_tee":"Platino","adjustment_notes":"","active":true,"strokes":2,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"J. González","accumulated_mxn":0},"Agustin":{"opponent_tee":"Doradas","adjustment_notes":"","active":true,"strokes":2,"last_result":"","stroke_ant":0,"last_game_date":"2025-09-18","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Agustin","accumulated_mxn":0},"Arturo":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":8,"last_result":"","stroke_ant":0,"last_game_date":"2026-08-10","my_tee":"","tag_ind":"Na","comentario":"0/0/0/0","game_money_mxn":0,"player_name":"Arturo","accumulated_mxn":0},"JL Castro":{"opponent_tee":"Doradas","adjustment_notes":"","active":true,"strokes":0,"last_result":"","stroke_ant":0,"last_game_date":"2025-03-08","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"JL Castro","accumulated_mxn":0},"Ramón Santoyo":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":6,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Ramón Santoyo","accumulated_mxn":0},"Alex Mena":{"opponent_tee":"Doradas","adjustment_notes":"","active":true,"strokes":9,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Alex Mena","accumulated_mxn":0},"Ramiro":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":6,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Ramiro","accumulated_mxn":0},"Francisco Pérez":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":5,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Jue","comentario":"80/40/40/20","game_money_mxn":0,"player_name":"Francisco Pérez","accumulated_mxn":0},"Luis S L":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":2,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Luis S L","accumulated_mxn":0},"Anselmo":{"opponent_tee":"Doradas","adjustment_notes":"","active":true,"strokes":3,"last_result":"Gane ","stroke_ant":4,"last_game_date":"1 Sep 2026 at 12:00","my_tee":"","tag_ind":"50/50","comentario":"50/50/0/25","game_money_mxn":-570,"player_name":"Anselmo","accumulated_mxn":0},"Salvador":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":3,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Salvador","accumulated_mxn":0},"De la Rosa":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":4,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"De la Rosa","accumulated_mxn":0},"Diego":{"opponent_tee":"Verdes","adjustment_notes":"","active":true,"strokes":11,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"30/30","comentario":"30/30/0/15","game_money_mxn":0,"player_name":"Diego","accumulated_mxn":0},"Luis Felipe":{"opponent_tee":"Verdes","adjustment_notes":"Ajustado","active":true,"strokes":3,"last_result":"","stroke_ant":0,"last_game_date":"","my_tee":"","tag_ind":"Tpch","comentario":"40/20/0/10","game_money_mxn":0,"player_name":"Luis Felipe","accumulated_mxn":0}}
    """#
}
