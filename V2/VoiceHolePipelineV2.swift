//
//  VoiceHolePipelineV2.swift
//  Caddie Score — v2t: dictado integral del hoyo (iPhone y, después, Apple Watch)
//
//  Todo lo que lleva la tarjeta de un hoyo se dicta junto: score, putts, orden de oyes, unidades y notas.
//
//    dictada ──▶ extract (LLM) ──▶ VoiceHoleDraft.merging(...)  ◀── nueva dictada ("lo que falta")
//                                        │
//                                        ▼
//                                 report(): "Entendí… Falta…"      (nada se guarda todavía)
//                                        │ el usuario confirma
//                                        ▼
//                      apply ──▶ VoiceUndoToken ──▶ undo
//
//  Reglas de captura que se reutilizan de la v1 (no hay reglas nuevas): MatchInterpreter.apply ("yo",
//  "los demás", todos, bogey/birdie, putts), applyHoleEntry + ScoreManager, setOyesRanks, upsertUnitEvent.
//  Lo que se aprende: apodos (VoiceSlangStore) y las grabaciones con su tarjeta final (VoiceRecordStore).
//

import Foundation

// MARK: - Lo que devuelve el LLM

struct VoiceHoleExtraction: Codable, Equatable {
    struct Score: Codable, Equatable {
        var jugador: String; var gross: Int?; var putts: Int?; var relativo: String? = nil
        /// "se levantó" / "perdió el hoyo": la app le pone un score que pierde el hoyo.
        var levanto: Bool? = nil
        /// Por qué perdió el hoyo ("bola equivocada"); queda como nota en ese hoyo.
        var motivo: String? = nil
    }
    /// "Del hoyo 5 al 8 Daniel tiró par, bogey, doble bogey y dos putts por hoyo".
    struct Run: Codable, Equatable {
        struct Result: Codable, Equatable { var gross: Int? = nil; var relativo: String? = nil; var levanto: Bool? = nil }
        var jugador: String; var desde: Int; var hasta: Int
        var resultados: [Result] = []
        var putts: Int? = nil
        var levanto: Bool? = nil
        var motivo: String? = nil
    }
    struct Oyes: Codable, Equatable { var jugador: String; var rank: Int }
    struct Unit: Codable, Equatable { var jugador: String; var codigo: String; var cantidad: Int? }
    struct Note: Codable, Equatable { var jugador: String; var texto: String }

    var hoyo: Int?
    var scores: [Score] = []
    var oyes: [Oyes] = []
    var unidades: [Unit] = []
    var notas: [Note] = []
    var corridas: [Run] = []
    /// Una pregunta sobre lo anotado (no un dato): se responde con lo que hay, no se anota nada.
    var consulta: ReadbackQueryV2? = nil

    init(hoyo: Int? = nil, scores: [Score] = [], oyes: [Oyes] = [], unidades: [Unit] = [], notas: [Note] = [], corridas: [Run] = [],
         consulta: ReadbackQueryV2? = nil) {
        self.hoyo = hoyo; self.scores = scores; self.oyes = oyes; self.unidades = unidades; self.notas = notas; self.corridas = corridas
        self.consulta = consulta
    }

    // El LLM a veces omite una lista vacía: se toma como [].
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hoyo = try c.decodeIfPresent(Int.self, forKey: .hoyo)
        scores = try c.decodeIfPresent([Score].self, forKey: .scores) ?? []
        oyes = try c.decodeIfPresent([Oyes].self, forKey: .oyes) ?? []
        unidades = try c.decodeIfPresent([Unit].self, forKey: .unidades) ?? []
        notas = try c.decodeIfPresent([Note].self, forKey: .notas) ?? []
        corridas = try c.decodeIfPresent([Run].self, forKey: .corridas) ?? []
        consulta = try? c.decodeIfPresent(ReadbackQueryV2.self, forKey: .consulta)
    }
}

// MARK: - Borrador del hoyo (lo que se entendió hasta ahora)

struct VoiceHoleDraft: Equatable {
    struct Cell: Equatable { var gross: Int?; var putts: Int? }
    struct Unit: Hashable { var alias: String; var code: String; var units: Int }
    struct Note: Hashable { var alias: String; var text: String }
    struct UnknownUnit: Hashable { var alias: String; var spoken: String; var units: Int }
    struct Edit: Hashable { var alias: String; var hole: Int; var gross: Int?; var putts: Int?; var pickup: Bool; var reason: String? = nil }

    var hole: Int?
    var cells: [String: Cell] = [:]
    var oyes: [String: Int] = [:]
    var units: [Unit] = []
    var notes: [Note] = []
    /// Cambios en uno o varios hoyos (una corrida "del 5 al 8", o un "se levantó"). Los golpes ya vienen resueltos con el par del hoyo.
    var edits: [Edit] = []
    /// Unidades dichas que no están en el catálogo: se pueden asignar a una unidad con un toque y la app aprende la frase.
    var unknownUnits: [UnknownUnit] = []
    /// Dudas por alias (jugador desconocido, nombre aproximado, golpes raros…) o por texto ("unidad:xyz").
    var doubts: [String: String] = [:]
    /// Todo lo dictado para este hoyo, en orden (para mostrarlo y para guardarlo con la grabación).
    var transcripts: [String] = []

    var isEmpty: Bool { cells.isEmpty && oyes.isEmpty && units.isEmpty && notes.isEmpty && edits.isEmpty && unknownUnits.isEmpty }
}

/// Lo que se entendió y lo que falta, listo para mostrar en la tarjeta o leer en voz alta.
struct VoiceHoleReport: Equatable {
    var understood: [String]
    var missing: [String]
    var doubts: [String]

    var isComplete: Bool { missing.isEmpty && doubts.isEmpty }

    /// Mensaje corto: qué entendí, qué falta, qué se repite.
    var message: String {
        var parts: [String] = []
        if understood.isEmpty { parts.append("No entendí nada del hoyo todavía.") }
        else { parts.append("Entendí: " + understood.joined(separator: " · ") + ".") }
        if !doubts.isEmpty { parts.append("Revisa: " + doubts.joined(separator: " · ") + ".") }
        if missing.isEmpty { if doubts.isEmpty { parts.append("Está completo.") } }
        else { parts.append("Falta: " + missing.joined(separator: " · ") + ".") }
        return parts.joined(separator: " ")
    }
}

enum VoiceHoleError: Error, Equatable {
    case emptyTranscript
    case notUnderstood(String)
    case nothingHeard
    /// No es un dato del hoyo sino una pregunta sobre lo anotado.
    case query(ReadbackQueryV2)

    var message: String {
        switch self {
        case .emptyTranscript: return "No detecté voz. Habla más cerca del micrófono."
        case .notUnderstood(let text): return text
        case .nothingHeard: return "No entendí datos del hoyo. Di, por ejemplo: \"Hoyo 5, Dan cuatro, Rob cinco\"."
        case .query: return ""
        }
    }
}

/// Foto antes de anotar: Deshacer restaura el hoyo principal completo (scores, oyes, unidades y notas) y las celdas de otros hoyos.
struct VoiceUndoToken {
    let hole: Int
    let scores: [String: (gross: Int, putts: Int?)?]
    let oyes: [String: Int]?
    let unitEvents: [UnitEvent]?
    /// Scores de los otros hoyos tocados por una corrida o un "se levantó".
    var otherHoles: [Int: [String: (gross: Int, putts: Int?)?]] = [:]
    /// Hoyos perdidos ("se levantó") que había antes en las celdas tocadas, por "alias#hoyo".
    var lostBefore: [String: CellOverride] = [:]
    /// Eventos/notas de los otros hoyos tocados (la nota del motivo).
    var otherUnitEvents: [Int: [UnitEvent]?] = [:]
}

// MARK: - Apodos que se aprenden

/// "el chino" → ROB. Se guarda en el teléfono y se le pasa al LLM como contexto en cada dictada.
final class VoiceSlangStore {
    static let shared = VoiceSlangStore()
    private let key = "voiceSlangV1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private(set) var terms: [String: String] {
        get { defaults.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: key) }
    }

    func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func target(for spoken: String) -> String? { terms[normalize(spoken)] }
    func learn(_ spoken: String, as target: String) {
        let k = normalize(spoken)
        guard !k.isEmpty else { return }
        var copy = terms; copy[k] = target; terms = copy
    }
    func forget(_ spoken: String) { var copy = terms; copy.removeValue(forKey: normalize(spoken)); terms = copy }
}

// MARK: - Grabaciones para reentrenar

/// Guarda cada dictada (audio + texto) y, al anotar, la tarjeta final: pares "lo que dije → lo que quedó bien".
/// Solo vive en el teléfono (Documents/voice_records); subirlas o usarlas para reentrenar es una fase posterior.
final class VoiceRecordStore {
    struct Entry: Codable, Equatable {
        var id: String
        var date: Date
        var roundId: String
        var hole: Int?
        var transcript: String
        var audioFile: String?
        /// Resumen de la tarjeta al terminar (nil mientras el hoyo sigue sin resolverse).
        var finalCard: String?
    }

    static let shared = VoiceRecordStore()
    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("voice_records", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    private func write(_ list: [Entry]) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) { try? data.write(to: indexURL, options: .atomic) }
    }

    /// Copia el audio (si hay) y agrega la entrada. Devuelve su id.
    @discardableResult
    func record(audio: URL?, transcript: String, roundId: String, hole: Int?) -> String {
        let id = UUID().uuidString
        var file: String?
        if let audio, FileManager.default.fileExists(atPath: audio.path) {
            let name = "\(id).\(audio.pathExtension.isEmpty ? "m4a" : audio.pathExtension)"
            if (try? FileManager.default.copyItem(at: audio, to: directory.appendingPathComponent(name))) != nil { file = name }
        }
        write(entries() + [Entry(id: id, date: Date(), roundId: roundId, hole: hole,
                                 transcript: transcript, audioFile: file, finalCard: nil)])
        return id
    }

    /// Frases anteriores de este usuario con lo que quiso decir (las de hoyos que costaron más de una dictada van primero):
    /// se mandan al LLM como ejemplos para que se calibre con su jerga.
    func examples(limit: Int) -> [[String: Any]] {
        struct Key: Hashable { let round: String; let hole: Int? }
        let resolved = entries().filter { $0.finalCard != nil }
        let groups = Dictionary(grouping: resolved, by: { Key(round: $0.roundId, hole: $0.hole) })
        let ordered = groups.values.sorted { a, b in
            if (a.count > 1) != (b.count > 1) { return a.count > 1 }
            return (a.map(\.date).max() ?? .distantPast) > (b.map(\.date).max() ?? .distantPast)
        }
        return ordered.prefix(limit).map { group in
            ["dijo": group.sorted { $0.date < $1.date }.map { String($0.transcript.prefix(200)) },
             "quedo": group.first?.finalCard ?? ""]
        }
    }

    /// Cómo va el aprendizaje: dictadas, hoyos resueltos y cuántos salieron a la primera.
    func stats() -> (dictations: Int, resolvedHoles: Int, firstTry: Int) {
        struct Key: Hashable { let round: String; let hole: Int? }
        let all = entries()
        let groups = Dictionary(grouping: all.filter { $0.finalCard != nil }, by: { Key(round: $0.roundId, hole: $0.hole) })
        return (all.count, groups.count, groups.values.filter { $0.count == 1 }.count)
    }

    /// Cuando el hoyo queda resuelto, todas las dictadas de esa sesión quedan ligadas a la tarjeta final.
    func resolve(ids: [String], finalCard: String) {
        var list = entries()
        for i in list.indices where ids.contains(list[i].id) { list[i].finalCard = finalCard }
        write(list)
    }
}

// MARK: - Pipeline

@MainActor
enum VoiceHolePipeline {
    typealias Extractor = (_ transcript: String, _ context: [String: Any]) async throws -> VoiceHoleExtraction

    static let liveExtractor: Extractor = { transcript, context in
        try await OpenAIService.shared.parseHole(transcript: transcript, context: context)
    }

    /// Unidades que se aceptan al dictar: las manuales del catálogo (Sandy par…) y también 3 Putt, 4 Putt y Hole Out,
    /// que no tienen botón pero sí se pueden decir. Por ahora solo se reciben; si cuentan o no se decide después.
    static func dictatableUnits(_ match: MatchManager) -> [(tag: String, name: String)] {
        var list = match.betCatalog.filter { $0.type == .individual && $0.mode == .manual && $0.tag.uppercased() != "OYES" }
            .map { ($0.tag.uppercased(), $0.name) }
        for (tag, name) in [("3P", "3 Putt"), ("4P", "4 Putt"), ("HO", "Hole Out")] where !list.contains(where: { $0.0 == tag }) {
            list.append((tag, name))
        }
        return list
    }

    /// Nombre del usuario (USER_NAME de caddie.env). Se puede cambiar en pruebas.
    static var userName: () -> String? = { AppConfig.userName }

    /// "Yo" siempre es el usuario de caddie.env, buscado entre los jugadores del Setup (por alias o por nombre).
    /// Si no hay USER_NAME o no está en el roster, se usa el "yo" del Setup.
    static func meAlias(_ match: MatchManager) -> String {
        if let name = userName(), let alias = match.resolveAliasDetailed(name).alias,
           match.players.contains(where: { $0.alias == alias }) { return alias }
        return match.yoAlias
    }

    /// Contexto que viaja al LLM: jugadores, "yo", hoyo, si es par 3 con oyes, unidades válidas y apodos aprendidos.
    static func context(match: MatchManager, hole: Int?, slang: VoiceSlangStore, records: VoiceRecordStore = .shared) -> [String: Any] {
        let h = hole ?? match.expectedNextHole()
        return [
            "jugadores": match.players.map { ["alias": $0.alias, "nombre": $0.name] },
            "yo_alias": meAlias(match),
            "hoyo_actual": h,
            "par": match.getHole(h)?.par ?? 4,
            "oyes_activo": match.isOyesEnabled && (match.getHole(h)?.par == 3),
            "unidades": dictatableUnits(match).map { ["codigo": $0.tag, "nombre": $0.name] },
            "apodos": slang.terms,
            "ejemplos": records.examples(limit: 5)
        ]
    }

    // MARK: Ayudar a la transcripción con lo que ya se sabe

    /// El texto que acompaña al audio para que se oigan bien los nombres y la jerga: vocabulario de golf, unidades del catálogo,
    /// frases y apodos aprendidos y, al final (lo que más pesa), los jugadores del Setup con su alias.
    static func transcriptionPrompt(match: MatchManager, slang: VoiceSlangStore = .shared) -> String {
        let vocab = "hoyo, par, bogey, doble bogey, birdie, eagle, putts, strokes, oyes, presión, vuelta, match, carry, F9, B9, se levantó, bola equivocada, tripoteó"
        let units = dictatableUnits(match).map(\.name).joined(separator: ", ")
        let learned = slang.terms.keys.sorted().prefix(30).joined(separator: ", ")
        let players = match.players.map { $0.name == $0.alias ? $0.name : "\($0.name) (\($0.alias))" }.joined(separator: ", ")
        var parts = ["Dictado de golf en español de México. No inventes texto.", "Palabras: \(vocab).", "Unidades: \(units)."]
        if !learned.isEmpty { parts.append("Jerga del grupo: \(learned).") }
        parts.append("Jugadores: \(players).")
        return parts.joined(separator: " ")
    }

    // MARK: Entender (una dictada → borrador nuevo)

    /// Una dictada nueva se suma al borrador que ya hay: lo más reciente gana en cada celda.
    /// `defaultHole` = el hoyo que se está jugando en pantalla: se usa si no dijeron otro ("hoyo 7…").
    static func propose(transcript: String, match: MatchManager, draft: VoiceHoleDraft = VoiceHoleDraft(), defaultHole: Int? = nil,
                        slang: VoiceSlangStore = .shared, records: VoiceRecordStore = .shared,
                        extractor: Extractor = liveExtractor) async throws -> VoiceHoleDraft {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw VoiceHoleError.emptyTranscript }
        var start = draft
        if start.hole == nil { start.hole = defaultHole }
        let extraction = try await extractor(text, context(match: match, hole: start.hole, slang: slang, records: records))
        // Una pregunta ("¿qué hizo Roberto en el 5?") se responde; no es un dato y no toca el borrador.
        if let q = extraction.consulta, extraction.scores.isEmpty, extraction.oyes.isEmpty, extraction.unidades.isEmpty,
           extraction.notas.isEmpty, extraction.corridas.isEmpty {
            throw VoiceHoleError.query(q)
        }
        let merged = merging(extraction, transcript: text, into: start, match: match, slang: slang)
        // Si la dictada no aportó nada nuevo (ruido, otra conversación), no se toca el borrador.
        var sameData = merged
        sameData.transcripts = start.transcripts
        if sameData == start { throw VoiceHoleError.nothingHeard }
        return merged
    }

    /// Normaliza alias ("yo", apodos aprendidos, nombres aproximados) y suma la extracción al borrador.
    /// Lo dicho con nombre manda; "los demás"/"todos" y par/bogey/birdie se calculan aquí con el par del hoyo.
    static func merging(_ extraction: VoiceHoleExtraction, transcript: String, into draft: VoiceHoleDraft,
                        match: MatchManager, slang: VoiceSlangStore = .shared) -> VoiceHoleDraft {
        var out = draft
        out.transcripts.append(transcript)
        let spoken = slang.normalize(transcript)
        out.doubts.removeValue(forKey: "?")          // se vuelven a calcular con lo nuevo
        out.doubts = out.doubts.filter { !$0.key.hasPrefix("corrida:") }
        out.doubts.removeValue(forKey: "oyes-par")

        // Hoyo: el del LLM cuenta si lo dijeron (con dígito o con letra) o si es el mismo que ya teníamos.
        if let hole = extraction.hoyo, (1...18).contains(hole), out.hole == hole || saidNumber(hole, in: spoken) { out.hole = hole }
        let par = out.hole.flatMap { match.getHole($0)?.par }

        // Scores y putts.
        var explicit: [String: (cell: VoiceHoleDraft.Cell, known: Bool, fuzzy: Bool)] = [:]
        var conflicts: [String: [Int]] = [:]
        var restGross: Int?          // "los demás cinco" / "todos par"
        for s in extraction.scores {
            let name = s.jugador.trimmingCharacters(in: .whitespacesAndNewlines)
            var gross = s.gross
            if gross == nil, let p = par, let d = relativeDelta(s.relativo) { gross = p + d }
            guard let g = gross else { continue }
            if ["demas", "resto", "otros", "los demas", "todos"].contains(slang.normalize(name)) { restGross = g; continue }
            if name.isEmpty {   // "Hizo cinco y dos putts": no se sabe de quién
                out.doubts["?"] = "Falta el jugador: \"\(g)\(s.putts.map { " y \($0) putts" } ?? "")\" ¿de quién?"
                continue
            }
            let who = resolveSpoken(name, match: match, slang: slang)
            if let prev = explicit[who.alias]?.cell.gross, prev != g { conflicts[who.alias, default: [prev]].append(g) }
            explicit[who.alias] = (.init(gross: g, putts: s.putts ?? out.cells[who.alias]?.putts), who.known, who.fuzzy)
        }
        for (alias, e) in explicit {
            out.doubts.removeValue(forKey: alias)    // lo nuevo reemplaza la duda anterior de ese jugador
            out.cells[alias] = e.cell
            markDoubts(&out, alias: alias, known: e.known, fuzzy: e.fuzzy)
            if let all = conflicts[alias] {
                out.doubts[alias] = "\(alias): dos scores distintos (\(all.map(String.init).joined(separator: " y "))), ¿cuál es?"
            }
        }
        // "Los demás …" / "todos …" (con número o con par/bogey/birdie): solo a quien no se dijo con nombre en esta dictada.
        let rest = restGross
        if let value = rest {
            for p in match.players where explicit[p.alias] == nil {
                out.cells[p.alias] = .init(gross: value, putts: out.cells[p.alias]?.putts)
            }
        }
        // Putts dictados sin golpes ("Rob dos putts") se suman a la celda si ya existe.
        for s in extraction.scores where s.gross == nil && s.relativo == nil {
            guard let p = s.putts, !s.jugador.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let who = resolveSpoken(s.jugador, match: match, slang: slang)
            var cell = out.cells[who.alias] ?? .init(gross: nil, putts: nil)
            cell.putts = p
            out.cells[who.alias] = cell
            markDoubts(&out, alias: who.alias, known: who.known, fuzzy: who.fuzzy)
        }

        // "Se levantó" / "perdió el hoyo" en el hoyo que se dicta.
        for sc in extraction.scores where sc.levanto == true {
            let name = sc.jugador.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let hole = out.hole else {
                if sc.levanto == true, sc.jugador.trimmingCharacters(in: .whitespaces).isEmpty { out.doubts["?"] = "Falta el jugador: ¿quién se levantó?" }
                continue
            }
            let who = resolveSpoken(name, match: match, slang: slang)
            setEdit(&out, .init(alias: who.alias, hole: hole, gross: nil, putts: nil, pickup: true, reason: reasonText(sc.motivo)))
            markDoubts(&out, alias: who.alias, known: who.known, fuzzy: who.fuzzy)
        }

        // Corridas: "del hoyo 5 al 8 Daniel tiró par, bogey, doble bogey y dos putts por hoyo".
        for run in extraction.corridas {
            let name = run.jugador.trimmingCharacters(in: .whitespacesAndNewlines)
            let holes = holeRange(run.desde, run.hasta)
            let label = "corrida:\(name.uppercased()):\(run.desde)-\(run.hasta)"
            guard !holes.isEmpty else { out.doubts[label] = "No entendí los hoyos \(run.desde) al \(run.hasta)"; continue }
            guard !name.isEmpty else { out.doubts["?"] = "Falta el jugador de los hoyos \(run.desde) al \(run.hasta)"; continue }
            let who = resolveSpoken(name, match: match, slang: slang)
            markDoubts(&out, alias: who.alias, known: who.known, fuzzy: who.fuzzy)
            // Un resultado por hoyo, o uno solo para todos; cualquier otra cuenta se pregunta, no se adivina.
            var results = run.resultados
            if results.isEmpty { results = [.init(levanto: run.levanto)] }
            if results.count == 1 { results = Array(repeating: results[0], count: holes.count) }
            guard results.count == holes.count else {
                out.doubts[label] = "Dijiste \(run.resultados.count) resultados para \(holes.count) hoyos (\(run.desde) al \(run.hasta)) de \(who.alias): ¿cuáles son?"
                continue
            }
            for (hole, r) in zip(holes, results) {
                let holePar = match.getHole(hole)?.par
                var gross = r.gross
                if gross == nil, let p = holePar, let d = relativeDelta(r.relativo) { gross = p + d }
                let pickup = r.levanto == true
                if gross == nil && run.putts == nil && !pickup { continue }
                setEdit(&out, .init(alias: who.alias, hole: hole, gross: pickup ? nil : gross, putts: run.putts, pickup: pickup,
                                    reason: pickup ? reasonText(run.motivo) : nil))
            }
        }

        // Oyes: solo en par 3, y solo si hablaron de oyes (el LLM a veces lo inventa con "hole out").
        let talkedAboutOyes = ["oye", "primero", "segundo", "tercero", "cerca"].contains { spoken.contains($0) }
        if talkedAboutOyes, !extraction.oyes.isEmpty {
            if let p = par, p != 3 {
                out.doubts["oyes-par"] = "El hoyo \(out.hole.map(String.init) ?? "?") es par \(p): los oyes solo se juegan en par 3"
            } else {
                for o in extraction.oyes where o.rank > 0 {
                    let who = resolveSpoken(o.jugador, match: match, slang: slang)
                    out.oyes[who.alias] = o.rank
                    markDoubts(&out, alias: who.alias, known: who.known, fuzzy: who.fuzzy)
                }
            }
        }
        // Dos jugadores en el mismo lugar: no se guarda un orden en conflicto.
        let ties = Dictionary(grouping: out.oyes.map { ($0.key, $0.value) }, by: { $0.1 }).filter { $0.value.count > 1 }
        if let (rank, tied) = ties.min(by: { $0.key < $1.key }) {
            out.doubts["oyes"] = "Empate en oyes: \(tied.map { $0.0 }.sorted().joined(separator: " y ")) en el lugar \(rank), ¿quién fue primero?"
        } else {
            out.doubts.removeValue(forKey: "oyes")
        }

        let valid = Set(dictatableUnits(match).map(\.tag))
        for u in extraction.unidades {
            let who = resolveSpoken(u.jugador, match: match, slang: slang)
            var code = u.codigo.uppercased().trimmingCharacters(in: .whitespaces)
            // Una frase que ya se enseñó ("tripoteó" = 3 Putt) se resuelve sola.
            if !valid.contains(code), let learned = slang.target(for: u.codigo)?.uppercased(), valid.contains(learned) { code = learned }
            if valid.contains(code) {
                out.units.removeAll { $0.alias == who.alias && $0.code == code }
                out.units.append(.init(alias: who.alias, code: code, units: max(1, u.cantidad ?? 1)))
                markDoubts(&out, alias: who.alias, known: who.known, fuzzy: who.fuzzy)
            } else {
                out.doubts["unidad:\(code.lowercased())"] = "No reconocí la unidad \"\(u.codigo)\" (no está activa en el catálogo)"
                out.unknownUnits.removeAll { $0.alias == who.alias && slang.normalize($0.spoken) == slang.normalize(u.codigo) }
                out.unknownUnits.append(.init(alias: who.alias, spoken: u.codigo, units: max(1, u.cantidad ?? 1)))
            }
        }

        for n in extraction.notas {
            let who = resolveSpoken(n.jugador.isEmpty ? meAlias(match) : n.jugador, match: match, slang: slang)
            let text = n.texto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            out.notes.removeAll { $0.alias == who.alias }
            out.notes.append(.init(alias: who.alias, text: text))
            markDoubts(&out, alias: who.alias, known: who.known, fuzzy: who.fuzzy)
        }
        return out
    }

    /// "bola equivocada" → "Bola equivocada" (nil si no dijeron motivo).
    private static func reasonText(_ raw: String?) -> String? {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private static func setEdit(_ d: inout VoiceHoleDraft, _ e: VoiceHoleDraft.Edit) {
        d.edits.removeAll { $0.alias == e.alias && $0.hole == e.hole }
        d.edits.append(e)
    }

    /// Hoyos de "del 5 al 8" (con vuelta: del 16 al 3 = 16, 17, 18, 1, 2, 3). Vacío si no son hoyos.
    private static func holeRange(_ from: Int, _ to: Int) -> [Int] {
        guard (1...18).contains(from), (1...18).contains(to) else { return [] }
        var out = [from]
        var h = from
        while h != to { h = h % 18 + 1; out.append(h) }
        return out
    }

    /// "par" 0, "birdie" −1, "eagle" −2, "albatros" −3, "bogey" +1, "doble bogey" +2.
    private static func relativeDelta(_ word: String?) -> Int? {
        guard let w = word?.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces), !w.isEmpty else { return nil }
        switch w {
        case "par": return 0
        case "birdie": return -1
        case "eagle", "aguila", "águila": return -2
        case "albatros": return -3
        case "bogey": return 1
        case "doble bogey", "double bogey", "doblebogey": return 2
        default: return nil
        }
    }

    /// ¿Dijeron este número de hoyo, con dígito o con letra? ("el dieciséis", "hoyo 7", "oyes del siete")
    private static func saidNumber(_ n: Int, in text: String) -> Bool {
        let words = ["", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce",
                     "trece", "catorce", "quince", "dieciseis", "diecisiete", "dieciocho"]
        for token in [String(n), words[n]] {
            if text.range(of: "\\b\(token)\\b", options: .regularExpression) != nil { return true }
        }
        return false
    }

    /// Un jugador dicho → alias del roster. `spoken` es el texto que se usará para volver a resolverlo en el intérprete.
    private static func resolveSpoken(_ raw: String, match: MatchManager, slang: VoiceSlangStore)
        -> (alias: String, spoken: String, known: Bool, fuzzy: Bool) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = slang.normalize(t)
        if ["yo", "me", "mi", "mio", "mia"].contains(low) { let me = meAlias(match); return (me, me, true, false) }
        if let learned = slang.target(for: t), match.players.contains(where: { $0.alias == learned }) {
            return (learned, learned, true, false)
        }
        let r = match.resolveAliasDetailed(t)
        if let alias = r.alias { return (alias, alias, true, r.usedFuzzy) }
        return (t.uppercased(), t, false, false)
    }

    private static func markDoubts(_ d: inout VoiceHoleDraft, alias: String, known: Bool, fuzzy: Bool) {
        if !known { d.doubts[alias] = "\(alias): jugador no reconocido" }
        else if fuzzy, d.doubts[alias] == nil { d.doubts[alias] = "\(alias): nombre aproximado, confírmalo" }
    }

    // MARK: Responder una pregunta sobre lo anotado

    /// El jugador de la pregunta se resuelve igual que al dictar ("yo" = USER_NAME, apodos, nombres aproximados).
    static func answer(_ q: ReadbackQueryV2, match: MatchManager, currentHole: Int, slang: VoiceSlangStore = .shared) -> String {
        var alias: String?
        if let who = q.jugador?.trimmingCharacters(in: .whitespacesAndNewlines), !who.isEmpty {
            let r = resolveSpoken(who, match: match, slang: slang)
            guard r.known else { return "No encontré a \"\(who)\" entre los jugadores." }
            alias = r.alias
        }
        var opponent: String?
        if let who = q.oponente?.trimmingCharacters(in: .whitespacesAndNewlines), !who.isEmpty {
            let r = resolveSpoken(who, match: match, slang: slang)
            guard r.known else { return "No encontré a \"\(who)\" entre los jugadores." }
            opponent = r.alias
        }
        let hole = q.hoyo.flatMap { (1...18).contains($0) ? $0 : nil }
        let to = q.hasta.flatMap { (1...18).contains($0) ? $0 : nil }
        return match.queryAnswerV2(q.tipo, alias: alias, hole: hole, currentHole: currentHole, segment: q.segmento,
                                   opponent: opponent, to: to)
    }

    // MARK: Reporte (qué entendí, qué falta)

    static func report(_ draft: VoiceHoleDraft, match: MatchManager) -> VoiceHoleReport {
        var understood: [String] = []
        var missing: [String] = []
        let order = match.players.map(\.alias)
        let unknown = draft.cells.keys.filter { !order.contains($0) }.sorted()

        if let hole = draft.hole { understood.append("hoyo \(hole)") } else { missing.append("el número de hoyo") }

        for alias in order + unknown {
            guard let c = draft.cells[alias] else { continue }
            if let g = c.gross { understood.append("\(alias) \(g)" + (c.putts.map { " (\($0) putts)" } ?? "")) }
        }
        let noScore = order.filter { draft.cells[$0]?.gross == nil }
        if !noScore.isEmpty { missing.append("score de \(noScore.joined(separator: ", "))") }
        let noPutts = order.filter { draft.cells[$0]?.gross != nil && draft.cells[$0]?.putts == nil }
        if !noPutts.isEmpty { missing.append("putts de \(noPutts.joined(separator: ", "))") }

        let par = draft.hole.flatMap { match.getHole($0)?.par }
        if par == 3, match.isOyesEnabled {
            let ranked = order.filter { draft.oyes[$0] != nil }
            if !ranked.isEmpty {
                understood.append("oyes " + ranked.sorted { draft.oyes[$0]! < draft.oyes[$1]! }
                    .map { "\(draft.oyes[$0]!)° \($0)" }.joined(separator: ", "))
            }
            let withScore = order.filter { draft.cells[$0]?.gross != nil }
            let contenders = withScore.isEmpty ? order : withScore
            let unranked = contenders.filter { draft.oyes[$0] == nil }
            if ranked.isEmpty { missing.append("orden de oyes (hoyo par 3)") }
            else if !unranked.isEmpty { missing.append("lugar de oyes de \(unranked.joined(separator: ", "))") }
        }

        for u in draft.units { understood.append("\(u.alias) \(unitName(u.code, match: match))" + (u.units > 1 ? " ×\(u.units)" : "")) }
        for n in draft.notes { understood.append("nota de \(n.alias)") }

        // Cambios en otros hoyos (corridas y "se levantó").
        let lines = editLines(draft, match: match)
        understood += lines.understood
        missing += lines.missing
        return VoiceHoleReport(understood: understood, missing: missing,
                               doubts: draft.doubts.keys.sorted().compactMap { draft.doubts[$0] })
    }

    /// Líneas de los cambios en uno o varios hoyos: lo entendido y lo que no se puede calcular todavía.
    static func editLines(_ draft: VoiceHoleDraft, match: MatchManager) -> (understood: [String], missing: [String]) {
        var understood: [String] = [], missing: [String] = []
        for alias in Set(draft.edits.map(\.alias)).sorted() {
            let mine = draft.edits.filter { $0.alias == alias }.sorted { $0.hole < $1.hole }
            let plain = mine.filter { !$0.pickup }
            if !plain.isEmpty {
                let body = plain.map { e in "h\(e.hole) " + (e.gross.map(String.init) ?? "—") + (e.putts.map { " (\($0)p)" } ?? "") }
                understood.append("\(alias) " + body.joined(separator: ", "))
            }
            for e in mine where e.pickup {
                if let g = pickupGross(draft: draft, match: match, alias: alias, hole: e.hole) {
                    understood.append("\(alias) " + (e.reason.map { "\($0.lowercased()) · pierde el " } ?? "se levantó en el ") + "\(e.hole) (se le pone \(g): más que el neto más alto de los demás, sin strokes, con ✕)")
                } else {
                    missing.append("scores de los demás en el hoyo \(e.hole) para calcular el \"se levantó\" de \(alias)")
                }
            }
        }
        return (understood, missing)
    }

    static func unitName(_ code: String, match: MatchManager) -> String {
        dictatableUnits(match).first { $0.tag == code }?.name ?? code
    }

    /// Resumen de una línea de la tarjeta final (se guarda junto a las grabaciones).
    static func cardSummary(_ draft: VoiceHoleDraft) -> String {
        var parts = draft.cells.keys.sorted().compactMap { a -> String? in
            guard let g = draft.cells[a]?.gross else { return nil }
            return "\(a) \(g)" + (draft.cells[a]?.putts.map { "/\($0)p" } ?? "")
        }
        if !draft.oyes.isEmpty { parts.append("oyes " + draft.oyes.sorted { $0.value < $1.value }.map { "\($0.value)=\($0.key)" }.joined(separator: ",")) }
        parts += draft.units.map { "\($0.alias):\($0.code)" + ($0.units > 1 ? "x\($0.units)" : "") }
        parts += draft.notes.map { "nota \($0.alias)" }
        return "H\(draft.hole.map(String.init) ?? "?") " + parts.joined(separator: " | ")
    }

    // MARK: Corregir un alias desde la tarjeta (y aprender el apodo)

    /// El usuario dice "ese 'Chino' es ROB": se mueve todo lo del alias dudoso al jugador correcto y se aprende el apodo.
    static func reassign(_ draft: VoiceHoleDraft, from wrong: String, to alias: String, spoken: String? = nil,
                         slang: VoiceSlangStore = .shared) -> VoiceHoleDraft {
        var d = draft
        if let c = d.cells.removeValue(forKey: wrong) { d.cells[alias] = d.cells[alias].map { _ in c } ?? c }
        if let o = d.oyes.removeValue(forKey: wrong) { d.oyes[alias] = o }
        d.units = d.units.map { var u = $0; if u.alias == wrong { u.alias = alias }; return u }
        d.notes = d.notes.map { var n = $0; if n.alias == wrong { n.alias = alias }; return n }
        d.doubts.removeValue(forKey: wrong)
        slang.learn(spoken ?? wrong, as: alias)
        return d
    }

    // MARK: Se levantó / perdió el hoyo

    /// Golpes que se le ponen a quien se levanta o pierde el hoyo: uno más que el neto más alto de los demás jugadores
    /// (el neto de cada quien con los strokes de SU match, individual y parejas). A él no se le aplica stroke en ese
    /// hoyo (queda con la cruz ✕ en la tarjeta), así su neto es el más alto y pierde. nil si no hay otro score con
    /// qué compararlo.
    static func pickupGross(draft: VoiceHoleDraft, match: MatchManager, alias: String, hole: Int) -> Int? {
        func gross(_ a: String) -> Int? {
            if hole == draft.hole, let g = draft.cells[a]?.gross { return g }
            if let e = draft.edits.first(where: { $0.alias == a && $0.hole == hole && !$0.pickup }), let g = e.gross { return g }
            if draft.edits.contains(where: { $0.alias == a && $0.hole == hole && $0.pickup }) { return nil }   // otro que también se levantó
            let g = match.getScore(hole: hole, player: a)
            return g > 0 ? g : nil
        }
        let me = match.yoAlias
        var highest: Double?
        func consider(_ net: Double) { highest = max(highest ?? net, net) }

        // Individual: cada match es yo contra un rival, con los strokes de ESE match.
        for opp in match.players.map(\.alias) where opp != me {
            guard alias == me || alias == opp else {
                // Match que no incluye a quien se levantó: el neto del rival contra yo cuenta como "los demás".
                if let g = gross(opp) { consider(Double(g) - match.individualMatchupStrokes(yoAlias: me, oppAlias: opp, hole: hole, carryAlias: nil).opp) }
                continue
            }
            let st = match.individualMatchupStrokes(yoAlias: me, oppAlias: opp, hole: hole, carryAlias: nil)
            let other = alias == me ? opp : me
            if let g = gross(other) { consider(Double(g) - (alias == me ? st.opp : st.yo)) }
        }
        // Parejas: la bola de cada jugador con el stroke de su pareja.
        for lane in match.activeLanes where lane.base.contains(alias) || lane.opp.contains(alias) {
            for other in (lane.base + lane.opp) where other != alias {
                if let g = gross(other) { consider(Double(g) - match.pairStrokeForPlayer(laneId: lane.id, alias: other, hole: hole)) }
            }
        }
        return highest.map { Int($0.rounded(.down)) + 1 }
    }

    /// "Ese 'chip raro' es Hole Out": la unidad pasa a su código y la app aprende la frase para la próxima.
    static func assignUnit(_ draft: VoiceHoleDraft, spoken: String, to code: String, slang: VoiceSlangStore = .shared) -> VoiceHoleDraft {
        var d = draft
        let pending = d.unknownUnits.filter { slang.normalize($0.spoken) == slang.normalize(spoken) }
        d.unknownUnits.removeAll { slang.normalize($0.spoken) == slang.normalize(spoken) }
        for u in pending {
            d.units.removeAll { $0.alias == u.alias && $0.code == code }
            d.units.append(.init(alias: u.alias, code: code, units: u.units))
        }
        let key = "unidad:\(spoken.uppercased().trimmingCharacters(in: .whitespaces).lowercased())"
        d.doubts.removeValue(forKey: key)
        slang.learn(spoken, as: code)
        return d
    }

    // MARK: Anotar y deshacer

    /// ¿Se puede anotar? Hay hoyo, nada dudoso y al menos un dato. (Lo que falta se avisa pero no bloquea.)
    static func canApply(_ draft: VoiceHoleDraft, match: MatchManager) -> Bool {
        draft.hole != nil && !draft.isEmpty && draft.doubts.isEmpty
            && draft.cells.keys.allSatisfy { alias in match.players.contains { $0.alias == alias } }
            && draft.edits.allSatisfy { e in
                match.players.contains { $0.alias == e.alias }
                    && (!e.pickup || pickupGross(draft: draft, match: match, alias: e.alias, hole: e.hole) != nil)
            }
    }

    @discardableResult
    static func apply(_ draft: VoiceHoleDraft, match: MatchManager) -> VoiceUndoToken? {
        guard let hole = draft.hole, canApply(draft, match: match) else { return nil }
        var before: [String: (gross: Int, putts: Int?)?] = [:]
        for p in match.players { before[p.alias] = p.scores[hole] }
        var token = VoiceUndoToken(hole: hole, scores: before, oyes: match.oyesRanksByHole[hole],
                                   unitEvents: match.unitEventsByHole[hole])

        for (alias, cell) in draft.cells {
            guard let gross = cell.gross else { continue }
            let putts = cell.putts ?? match.getPutts(hole: hole, player: alias)
            if match.cellOverride(alias: alias, hole: hole) == .lostHole { match.setCellOverride(alias: alias, hole: hole, override: .none) }
            match.applyHoleEntry(HoleEntryData(hole_number: hole, player_alias: alias, strokes: gross,
                                               putts: putts, units: nil, tags: nil))
            _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(player: alias, hole: hole, strokes: gross, putts: putts))
        }
        // Otros hoyos: foto, luego los golpes/putts de las corridas y al final los "se levantó" (necesitan los demás scores).
        for h in Set(draft.edits.map(\.hole)) where h != hole {
            token.otherHoles[h] = Dictionary(uniqueKeysWithValues: match.players.map { ($0.alias, $0.scores[h]) })
        }
        for h in Set(draft.edits.filter { $0.pickup && $0.reason != nil }.map(\.hole)) where h != hole {
            token.otherUnitEvents[h] = .some(match.unitEventsByHole[h])
        }
        for e in draft.edits {
            token.lostBefore["\(e.alias)#\(e.hole)"] = match.cellOverride(alias: e.alias, hole: e.hole)
        }
        for (alias, cell) in draft.cells where cell.gross != nil {
            token.lostBefore["\(alias)#\(hole)"] = match.cellOverride(alias: alias, hole: hole)
        }
        for e in draft.edits where !e.pickup {
            let current = match.getScore(hole: e.hole, player: e.alias)
            guard let g = e.gross ?? (current > 0 ? current : nil) else { continue }
            let p = e.putts ?? match.getPutts(hole: e.hole, player: e.alias)
            writeScore(match, alias: e.alias, hole: e.hole, gross: g, putts: p)
            if match.cellOverride(alias: e.alias, hole: e.hole) == .lostHole { match.setCellOverride(alias: e.alias, hole: e.hole, override: .none) }
        }
        for e in draft.edits where e.pickup {
            if let g = pickupGross(draft: draft, match: match, alias: e.alias, hole: e.hole) {
                writeScore(match, alias: e.alias, hole: e.hole, gross: g, putts: match.getPutts(hole: e.hole, player: e.alias))
                match.setCellOverride(alias: e.alias, hole: e.hole, override: .lostHole)   // sin strokes: pierde el hoyo
                if let reason = e.reason {   // el motivo queda de nota en ese hoyo, sin pisar una nota que ya hubiera
                    let hasNote = match.unitEventsByHole[e.hole]?.contains { $0.alias == e.alias && $0.code == "NOTA" } == true
                    if !hasNote { match.upsertUnitEvent(hole: e.hole, alias: e.alias, code: "NOTA", units: 0, note: reason) }
                }
            }
        }
        if !draft.oyes.isEmpty { match.setOyesRanks(hole: hole, ranksByAlias: draft.oyes) }
        for u in draft.units { match.upsertUnitEvent(hole: hole, alias: u.alias, code: u.code, units: u.units) }
        for n in draft.notes { match.upsertUnitEvent(hole: hole, alias: n.alias, code: "NOTA", units: 0, note: n.text) }
        return token
    }

    private static func writeScore(_ match: MatchManager, alias: String, hole: Int, gross: Int, putts: Int) {
        match.applyHoleEntry(HoleEntryData(hole_number: hole, player_alias: alias, strokes: gross, putts: putts, units: nil, tags: nil))
        _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(player: alias, hole: hole, strokes: gross, putts: putts))
    }

    static func undo(_ token: VoiceUndoToken, match: MatchManager) {
        for i in match.players.indices {
            let alias = match.players[i].alias
            guard let previous = token.scores[alias] else { continue }
            if let previous {
                match.players[i].scores[token.hole] = previous
                _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(
                    player: alias, hole: token.hole, strokes: previous.gross, putts: previous.putts ?? 0))
            } else {
                match.players[i].scores[token.hole] = nil
                ScoreManager.shared.removeScore(player: alias, hole: token.hole)
            }
        }
        for (h, snapshot) in token.otherHoles {
            for i in match.players.indices {
                let alias = match.players[i].alias
                guard let previous = snapshot[alias] else { continue }
                if let previous {
                    match.players[i].scores[h] = previous
                    _ = ScoreManager.shared.saveScore(record: GolfScoreRecord(player: alias, hole: h, strokes: previous.gross, putts: previous.putts ?? 0))
                } else {
                    match.players[i].scores[h] = nil
                    ScoreManager.shared.removeScore(player: alias, hole: h)
                }
            }
        }
        for (key, previous) in token.lostBefore {
            let parts = key.split(separator: "#")
            if parts.count == 2, let h = Int(parts[1]) { match.setCellOverride(alias: String(parts[0]), hole: h, override: previous) }
        }
        for (h, events) in token.otherUnitEvents { match.unitEventsByHole[h] = events ?? nil }
        match.oyesRanksByHole[token.hole] = token.oyes
        match.unitEventsByHole[token.hole] = token.unitEvents
    }
}
