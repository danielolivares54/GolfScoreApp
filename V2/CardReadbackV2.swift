//
//  CardReadbackV2.swift
//  Caddie Score — v2t: el apuntador lee lo que ya está anotado, cuando el usuario lo pide
//
//  "¿Qué llevo?" → lee el hoyo (scores, putts, oyes, unidades, notas y lo que falta).
//  "¿Cómo vamos?" → lee la ronda (cuánto vas ganando o perdiendo con cada quien).
//  "¿Qué falta?" → solo lo que falta del hoyo.
//  Se pide con un botón en la hoja de voz o diciéndolo ("qué llevo", "léeme el hoyo", "cómo vamos", "qué falta").
//  Todo sale de lo ya anotado en MatchManager (lo mismo que ve la Tarjeta): no inventa ni calcula nada nuevo.
//

import SwiftUI
import AVFoundation
import Observation

// MARK: - Qué se pide

enum ReadbackIntentV2: Equatable {
    case hole, round, missing

    /// ¿Lo dicho es una petición de lectura? (se resuelve en el teléfono, sin LLM)
    static func detect(_ transcript: String) -> ReadbackIntentV2? {
        let t = transcript.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "es_MX"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        func has(_ phrases: [String]) -> Bool { phrases.contains { t.contains($0) } }
        if has(["que falta", "que me falta", "que nos falta", "falta algo"]) { return .missing }
        if has(["como vamos", "como voy", "como andamos", "cuanto llevo", "cuanto vamos", "como va la ronda", "resultado de la ronda"]) { return .round }
        if has(["que llevo", "que tengo anotado", "que hay anotado", "que llevamos", "leeme", "lee el hoyo", "lee lo que", "dime lo que llevo"]) { return .hole }
        return nil
    }
}

struct CardReadbackV2: Equatable {
    let text: String          // lo que se dice
    let missing: [String]     // lo que falta, por separado
}

// MARK: - El texto

extension MatchManager {

    func spokenName(_ alias: String) -> String {
        let full = players.first { $0.alias == alias }?.name ?? alias
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    func spokenList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " y " + items.last!
        }
    }

    func spokenUnitName(_ code: String) -> String {
        switch code.uppercased() {
        case "3P": return "tres putts"
        case "4P": return "cuatro putts"
        case "HO": return "hole out"
        default: return betCatalog.first { $0.tag.uppercased() == code.uppercased() }?.name ?? code
        }
    }

    func spokenOrdinal(_ n: Int) -> String {
        ["", "primero", "segundo", "tercero", "cuarto", "quinto"].indices.contains(n) ? ["", "primero", "segundo", "tercero", "cuarto", "quinto"][n] : "lugar \(n)"
    }

    /// Lo que lleva un hoyo: anotado y pendiente.
    func holeReadbackV2(_ hole: Int) -> CardReadbackV2 {
        let par = getHole(hole)?.par ?? 4
        let order = players.map(\.alias)
        var parts: [String] = ["Hoyo \(hole), par \(par)."]
        var missing: [String] = []

        // Scores y putts
        let scored = order.filter { getScore(hole: hole, player: $0) > 0 }
        for alias in scored {
            let gross = getScore(hole: hole, player: alias)
            let putts = getPutts(hole: hole, player: alias)
            var line = "\(spokenName(alias)) \(gross)"
            if putts > 0 { line += ", \(putts) putt\(putts == 1 ? "" : "s")" }
            if cellOverride(alias: alias, hole: hole) == .lostHole { line += ", se levantó, hoyo perdido" }
            parts.append(line + ".")
        }
        if scored.isEmpty { return .init(text: "El hoyo \(hole) todavía no tiene nada anotado.", missing: ["los scores del hoyo"]) }

        // Oyes (solo par 3 con Oyes activo)
        if par == 3, isOyesEnabled {
            let ranks = oyesRanksByHole[hole] ?? [:]
            let ranked = order.filter { ranks[$0] != nil }.sorted { ranks[$0]! < ranks[$1]! }
            if !ranked.isEmpty {
                parts.append("Oyes: " + spokenList(ranked.map { "\(spokenOrdinal(ranks[$0]!)) \(spokenName($0))" }) + ".")
            }
            let unranked = scored.filter { ranks[$0] == nil }
            if ranked.isEmpty { missing.append("el orden de oyes") }
            else if !unranked.isEmpty { missing.append("el lugar de oyes de " + spokenList(unranked.map(spokenName))) }
        }

        // Unidades y notas
        let events = (unitEventsByHole[hole] ?? []).filter { isUnitCodeActive($0.code) || $0.code.uppercased() == "NOTA" }
        for e in events where e.code.uppercased() != "NOTA" {
            parts.append("\(spokenName(e.alias)): \(spokenUnitName(e.code)).")
        }
        for e in events where e.code.uppercased() == "NOTA" {
            if let note = e.note, !note.isEmpty { parts.append("Nota de \(spokenName(e.alias)): \(note).") }
        }

        // Lo que falta
        let noScore = order.filter { getScore(hole: hole, player: $0) <= 0 }
        if !noScore.isEmpty { missing.insert("el score de " + spokenList(noScore.map(spokenName)), at: 0) }
        let noPutts = scored.filter { tracksPutts(alias: $0) && getPutts(hole: hole, player: $0) <= 0 }
        if !noPutts.isEmpty { missing.append("los putts de " + spokenList(noPutts.map(spokenName))) }

        parts.append(missing.isEmpty ? "Está completo." : "Falta " + spokenList(missing) + ".")
        return .init(text: parts.joined(separator: " "), missing: missing)
    }

    /// Cómo va la ronda: hoyos anotados y dinero con cada quien.
    func roundReadbackV2() -> String {
        let done = completedHolesCountV2()
        let rows = resultadoRowsV2()
        guard !rows.isEmpty else { return "Todavía no hay matches en la ronda." }
        var parts = ["Llevas \(done) hoyo\(done == 1 ? "" : "s") completo\(done == 1 ? "" : "s")."]
        func money(_ v: Int) -> String { v > 0 ? "ganando \(v) pesos" : v < 0 ? "perdiendo \(-v) pesos" : "a mano" }
        for row in rows {
            let who = row.isPair ? row.title : "contra " + spokenName(row.title)
            parts.append("\(who.prefix(1).uppercased() + who.dropFirst()), \(money(row.money)).")
        }
        let total = resultadoTotalV2()
        parts.append("En total, \(money(total)).")
        return parts.joined(separator: " ")
    }

    func readbackV2(_ intent: ReadbackIntentV2, hole: Int) -> String {
        switch intent {
        case .hole: return holeReadbackV2(hole).text
        case .round: return roundReadbackV2()
        case .missing:
            let r = holeReadbackV2(hole)
            return r.missing.isEmpty ? "En el hoyo \(hole) no falta nada." : "En el hoyo \(hole) falta " + spokenList(r.missing) + "."
        }
    }
}

// MARK: - Preguntas sobre lo anotado ("¿qué hizo Roberto en el 5?", "¿qué oyes ha ganado Daniel?", "¿dónde hizo unidades Ricardo?")

/// Lo que el LLM entiende de una pregunta. La respuesta NUNCA la escribe el LLM: sale de lo anotado, abajo.
struct ReadbackQueryV2: Codable, Equatable {
    /// score · total · putts · oyes · unidades · notas
    var tipo: String
    var jugador: String? = nil
    var hoyo: Int? = nil
}

extension MatchManager {
    private func playIndex(_ hole: Int) -> Int { playOrder().firstIndex(of: hole) ?? hole }

    private func relativeWord(_ diff: Int) -> String {
        switch diff {
        case ...(-3): return "albatros"
        case -2: return "eagle"
        case -1: return "birdie"
        case 0: return "par"
        case 1: return "bogey"
        case 2: return "doble bogey"
        default: return "\(diff) sobre par"
        }
    }

    private func holesText(_ holes: [Int]) -> String {
        holes.count == 1 ? "el hoyo \(holes[0])" : "los hoyos " + spokenList(holes.map(String.init))
    }

    /// Responde una pregunta con lo que hay anotado. `alias` ya viene resuelto (nil = no dijeron de quién).
    func queryAnswerV2(_ kind: String, alias: String?, hole: Int?, currentHole: Int) -> String {
        let order = playOrder()
        let name = alias.map(spokenName)
        switch kind.lowercased() {
        case "score", "golpes":
            guard let alias, let name else { return holeReadbackV2(hole ?? currentHole).text }
            let h = hole ?? currentHole
            let gross = getScore(hole: h, player: alias)
            guard gross > 0 else { return "\(name) no tiene score en el hoyo \(h)." }
            let par = getHole(h)?.par ?? 4
            var text = "\(name) hizo \(gross) en el hoyo \(h), \(relativeWord(gross - par))"
            let putts = getPutts(hole: h, player: alias)
            if putts > 0 { text += ", con \(putts) putt\(putts == 1 ? "" : "s")" }
            if cellOverride(alias: alias, hole: h) == .lostHole { text += ". Se levantó: hoyo perdido" }
            return text + "."
        case "total":
            guard let alias, let name else { return roundReadbackV2() }
            let holes = order.filter { getScore(hole: $0, player: alias) > 0 }
            guard !holes.isEmpty else { return "\(name) todavía no tiene scores." }
            let sum = holes.reduce(0) { $0 + getScore(hole: $1, player: alias) }
            let pars = holes.reduce(0) { $0 + (getHole($1)?.par ?? 4) }
            let diff = sum - pars
            return "\(name) lleva \(sum) golpes en \(holes.count) hoyo\(holes.count == 1 ? "" : "s"), " +
                (diff == 0 ? "par del campo." : diff > 0 ? "\(diff) sobre par." : "\(-diff) bajo par.")
        case "putts":
            guard let alias, let name else { return "¿De quién quieres saber los putts?" }
            if let hole {
                let p = getPutts(hole: hole, player: alias)
                return p > 0 ? "\(name) hizo \(p) putt\(p == 1 ? "" : "s") en el hoyo \(hole)." : "\(name) no tiene putts anotados en el hoyo \(hole)."
            }
            let holes = order.filter { getPutts(hole: $0, player: alias) > 0 }
            guard !holes.isEmpty else { return "\(name) no tiene putts anotados." }
            let total = holes.reduce(0) { $0 + getPutts(hole: $1, player: alias) }
            return "\(name) lleva \(total) putts en \(holes.count) hoyo\(holes.count == 1 ? "" : "s")."
        case "oyes":
            guard isOyesEnabled else { return "Los oyes están apagados en el catálogo." }
            let par3 = order.filter { getHole($0)?.par == 3 && !(oyesRanksByHole[$0] ?? [:]).isEmpty }
            if let hole {
                guard let ranks = oyesRanksByHole[hole], !ranks.isEmpty else { return "El hoyo \(hole) no tiene oyes anotados." }
                let ranked = ranks.sorted { $0.value < $1.value }.map { "\(spokenOrdinal($0.value)) \(spokenName($0.key))" }
                return "Oyes del hoyo \(hole): " + spokenList(ranked) + "."
            }
            if let alias, let name {
                let won = par3.filter { oyesRanksByHole[$0]?[alias] == 1 }
                return won.isEmpty ? "\(name) no ha ganado ningún oyes." : "\(name) ganó el oyes en " + holesText(won) + "."
            }
            guard !par3.isEmpty else { return "Todavía no hay oyes anotados." }
            let lines = par3.compactMap { h -> String? in
                guard let w = oyesRanksByHole[h]?.first(where: { $0.value == 1 })?.key else { return nil }
                return "hoyo \(h), \(spokenName(w))"
            }
            return "Oyes ganados: " + lines.joined(separator: "; ") + "."
        case "unidades":
            func events(_ filter: (UnitEvent) -> Bool) -> [UnitEvent] {
                unitEventsByHole.values.flatMap { $0 }
                    .filter { $0.code.uppercased() != "NOTA" && isUnitCodeActive($0.code) && filter($0) }
                    .sorted { (playIndex($0.hole), $0.alias) < (playIndex($1.hole), $1.alias) }
            }
            func describe(_ e: UnitEvent) -> String { "\(spokenUnitName(e.code)) en el hoyo \(e.hole)" }
            if let hole {
                let list = events { $0.hole == hole && (alias == nil || $0.alias == alias) }
                return list.isEmpty ? "No hay unidades anotadas en el hoyo \(hole)." :
                    "En el hoyo \(hole): " + spokenList(list.map { "\(spokenName($0.alias)), \(spokenUnitName($0.code))" }) + "."
            }
            if let alias, let name {
                let list = events { $0.alias == alias }
                return list.isEmpty ? "\(name) no tiene unidades anotadas." : "\(name) hizo unidades: " + spokenList(list.map(describe)) + "."
            }
            let list = events { _ in true }
            guard !list.isEmpty else { return "Todavía no hay unidades anotadas." }
            let grouped = Dictionary(grouping: list, by: \.alias)
            return players.map(\.alias).compactMap { a -> String? in
                guard let es = grouped[a] else { return nil }
                return "\(spokenName(a)): " + spokenList(es.map(describe))
            }.joined(separator: ". ") + "."
        case "notas":
            let notes = unitEventsByHole.values.flatMap { $0 }
                .filter { $0.code.uppercased() == "NOTA" && ($0.note?.isEmpty == false) && (alias == nil || $0.alias == alias) && (hole == nil || $0.hole == hole) }
                .sorted { playIndex($0.hole) < playIndex($1.hole) }
            guard !notes.isEmpty else { return "No hay notas anotadas." }
            return spokenList(notes.map { "hoyo \($0.hole), \(spokenName($0.alias)): \($0.note ?? "")" }) + "."
        default:
            return holeReadbackV2(hole ?? currentHole).text
        }
    }
}

// MARK: - La voz

/// Lee un texto en voz alta (español de México) y se puede detener.
@MainActor @Observable
final class SpeechReadbackV2: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()
        // El micrófono deja la sesión en modo grabación: para hablar hace falta reproducción.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-MX") ?? AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
