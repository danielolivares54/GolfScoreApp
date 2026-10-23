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

    private func spokenName(_ alias: String) -> String {
        let full = players.first { $0.alias == alias }?.name ?? alias
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    private func spokenList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " y " + items.last!
        }
    }

    private func spokenUnitName(_ code: String) -> String {
        switch code.uppercased() {
        case "3P": return "tres putts"
        case "4P": return "cuatro putts"
        case "HO": return "hole out"
        default: return betCatalog.first { $0.tag.uppercased() == code.uppercased() }?.name ?? code
        }
    }

    private func ordinal(_ n: Int) -> String {
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
                parts.append("Oyes: " + spokenList(ranked.map { "\(ordinal(ranks[$0]!)) \(spokenName($0))" }) + ".")
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
