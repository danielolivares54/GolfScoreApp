import Foundation

struct InterpreterResult {
    let entities: ScoreEntities
    let error: String?
    let usedFuzzy: Bool
}

enum MatchInterpreter {
    static func apply(transcript: String, entities: ScoreEntities, match: MatchManager) -> InterpreterResult {
        var updated = entities
        let text = transcript.lowercased()
        let mentionedAliases = detectMentionedAliases(text, match: match)

        // Fill missing hole from transcript if possible
        if updated.hoyo == nil, let h = extractHole(from: text) {
            updated = ScoreEntities(hoyo: h, scores: updated.scores)
        }

        // Normalize player names to aliases
        var fuzzyUsed = false
        let normalizedScores: [PlayerScore] = (updated.scores ?? []).map { score in
            let resolved = match.resolveAliasDetailed(score.jugador)
            if resolved.usedFuzzy { fuzzyUsed = true }
            let alias = resolved.alias ?? score.jugador.uppercased()
            return PlayerScore(jugador: alias, gross: score.gross, putts: score.putts)
        }
        updated = ScoreEntities(hoyo: updated.hoyo, scores: normalizedScores)

        // Map "yo" -> yoAlias
        let yoAlias = match.yoAlias
        let remappedScores: [PlayerScore] = (updated.scores ?? []).map { s in
            let j = s.jugador.lowercased()
            if j == "yo" || j == "me" || j == "mi" || j == "mio" || j == "mia" {
                return PlayerScore(jugador: yoAlias, gross: s.gross, putts: s.putts)
            }
            return s
        }
        let normalizedTranscript = match.normalizePlayerKey(transcript).lowercased()
        let filteredScores: [PlayerScore] = remappedScores.filter { s in
            if match.isAmbiguousAliasToken(s.jugador) {
                guard let player = match.players.first(where: { $0.alias == s.jugador }) else {
                    return false
                }
                let nameKey = match.normalizePlayerKey(player.name).lowercased()
                return !nameKey.isEmpty && containsWholePhrase(normalizedTranscript, phrase: nameKey)
            }
            return true
        }
        updated = ScoreEntities(hoyo: updated.hoyo, scores: filteredScores)

        // "tres putts"/"3 putts" -> apply putts count
        if let puttsCount = extractPuttsCount(from: text) {
            if var scores = updated.scores, !scores.isEmpty {
                let targets = mentionedAliases.isEmpty ? Set(scores.map { $0.jugador }) : Set(mentionedAliases)
                scores = scores.map { s in
                    if targets.contains(s.jugador) && s.putts == nil {
                        return PlayerScore(jugador: s.jugador, gross: s.gross, putts: puttsCount)
                    }
                    return s
                }
                updated = ScoreEntities(hoyo: updated.hoyo, scores: scores)
            }
        }

        // "todos" -> expand to all players
        if text.contains("todos") {
            if let baseScore = updated.scores?.first {
                let expanded = match.players.map { p in
                    PlayerScore(jugador: p.alias, gross: baseScore.gross, putts: baseScore.putts)
                }
                updated = ScoreEntities(hoyo: updated.hoyo, scores: expanded)
            } else if let hole = updated.hoyo, let par = match.getHole(hole)?.par, let delta = relativeScoreFromText(text) {
                let expanded = match.players.map { p in
                    PlayerScore(jugador: p.alias, gross: par + delta, putts: nil)
                }
                updated = ScoreEntities(hoyo: hole, scores: expanded)
            }
        }

        // "los demas" -> expand to remaining players
        if text.contains("los demas") || text.contains("los demás") {
            if var scores = updated.scores {
                let explicit = Set(scores.map { $0.jugador })
                if let resto = scores.first(where: { ["DEMAS", "RESTO", "OTROS", "LOS DEMAS"].contains($0.jugador.uppercased()) }) {
                    scores.removeAll { $0.jugador.uppercased() == "DEMAS" || $0.jugador.uppercased() == "RESTO" || $0.jugador.uppercased() == "OTROS" || $0.jugador.uppercased() == "LOS DEMAS" }
                    let remaining = match.players.filter { !explicit.contains($0.alias) }
                    let expanded = remaining.map { p in
                        PlayerScore(jugador: p.alias, gross: resto.gross, putts: resto.putts)
                    }
                    scores.append(contentsOf: expanded)
                    updated = ScoreEntities(hoyo: updated.hoyo, scores: scores)
                }
            }
        }

        // "perdio el hoyo" / "se levanto" -> max+3
        if text.contains("perdio el hoyo") || text.contains("perdió el hoyo") || text.contains("se levanto") || text.contains("se levantó") {
            let mentioned = match.players.filter { p in
                text.contains(p.alias.lowercased()) || text.contains(p.name.lowercased())
            }
            guard let target = mentioned.first else {
                return InterpreterResult(entities: updated, error: "Falta jugador (perdio el hoyo)", usedFuzzy: fuzzyUsed)
            }
            guard let scores = updated.scores, !scores.isEmpty else {
                return InterpreterResult(entities: updated, error: "Faltan scores de los demas para calcular perdio el hoyo", usedFuzzy: fuzzyUsed)
            }
            let others = scores.filter { $0.jugador != target.alias }.map { $0.gross }
            guard let maxOther = others.max() else {
                return InterpreterResult(entities: updated, error: "Faltan scores de otros jugadores", usedFuzzy: fuzzyUsed)
            }
            var newScores = scores.filter { $0.jugador != target.alias }
            newScores.append(PlayerScore(jugador: target.alias, gross: maxOther + 3, putts: nil))
            updated = ScoreEntities(hoyo: updated.hoyo, scores: newScores)
        }

        // Bogey/Birdie/Eagle -> derive strokes from par if needed
        if let hole = updated.hoyo, let par = match.getHole(hole)?.par {
            let rel = relativeScoreFromText(text)
            if let delta = rel {
                // If no explicit gross provided, apply to mentioned players or all
                if (updated.scores ?? []).isEmpty {
                    let targets = mentionedAliases.isEmpty ? match.players.map { $0.alias } : mentionedAliases
                    let derived = targets.map { alias in
                        PlayerScore(jugador: alias, gross: par + delta, putts: nil)
                    }
                    updated = ScoreEntities(hoyo: hole, scores: derived)
                }
            }
        }

        // Noise filter: if no hole, no scores, no mentioned players -> noise
        if updated.hoyo == nil && (updated.scores == nil || updated.scores?.isEmpty == true) && mentionedAliases.isEmpty {
            return InterpreterResult(entities: updated, error: "NOISE", usedFuzzy: fuzzyUsed)
        }

        return InterpreterResult(entities: updated, error: nil, usedFuzzy: fuzzyUsed)
    }

    static func extractHole(from text: String) -> Int? {
        // Numeric: "hoyo 8" or "oyo 8"
        let patterns = [
            #"hoyo\s*(\d{1,2})"#,
            #"oyo\s*(\d{1,2})"#,
            #"ollo\s*(\d{1,2})"#,
            #"agujero\s*(\d{1,2})"#,
            #"ahujero\s*(\d{1,2})"#,
            #"hueco\s*(\d{1,2})"#
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                let digits = match.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
                if let h = Int(digits), h >= 1, h <= 18 { return h }
            }
        }
        // Worded numbers
        let words: [String: Int] = [
            "uno":1,"dos":2,"tres":3,"cuatro":4,"cinco":5,"seis":6,"siete":7,"ocho":8,"nueve":9,
            "diez":10,"once":11,"doce":12,"trece":13,"catorce":14,"quince":15,"dieciseis":16,"dieciséis":16,
            "diecisiete":17,"dieciocho":18
        ]
        for (w, n) in words {
            if text.contains("hoyo \(w)") || text.contains("oyo \(w)") {
                return n
            }
        }
        return nil
    }

    private static func detectMentionedAliases(_ text: String, match: MatchManager) -> [String] {
        var result: [String] = []
        let normalizedText = match.normalizePlayerKey(text).lowercased()
        for p in match.players {
            let nameKey = match.normalizePlayerKey(p.name).lowercased()
            if !nameKey.isEmpty && containsWholePhrase(normalizedText, phrase: nameKey) {
                result.append(p.alias)
            }
            let aliasKey = p.alias.lowercased()
            if !match.isAmbiguousAliasToken(aliasKey) && containsWholePhrase(normalizedText, phrase: aliasKey) {
                result.append(p.alias)
            }
        }
        let tokens = normalizedText.split(separator: " ").map { String($0) }
        for token in tokens {
            if match.isAmbiguousAliasToken(token) { continue }
            if let alias = match.normalizeAlias(token) {
                result.append(alias)
            }
        }
        if normalizedText.contains("yo") || normalizedText.contains("mi") || normalizedText.contains("mio") || normalizedText.contains("mia") {
            result.append(match.yoAlias)
        }
        return Array(Set(result))
    }

    private static func containsWholePhrase(_ text: String, phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        let pattern = #"(?i)\b\#(escaped)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func relativeScoreFromText(_ text: String) -> Int? {
        if text.contains("doble bogey") || text.contains("doble boggi") || text.contains("doble boogie") || text.contains("doble boggy") || text.contains("doble buggy") {
            return 2
        }
        if text.contains("bogey") || text.contains("boggi") || text.contains("boogie") || text.contains("boggy") || text.contains("buggy") || text.contains("bogie") {
            return 1
        }
        if text.contains("birdie") {
            return -1
        }
        if text.contains("eagle") {
            return -2
        }
        return nil
    }

    private static func extractPuttsCount(from text: String) -> Int? {
        // Slang de campo
        if text.contains("cuatripoteo") || text.contains("cuatripott") || text.contains("cuatri putt") || text.contains("cuatro putt") {
            return 4
        }
        if text.contains("tripoteo") || text.contains("trípotéo") || text.contains("tripeo") || text.contains("tripot") || text.contains("tripott") {
            return 3
        }

        let patterns = [
            (#"(\\d)\\s*(putts|putt|puts|put)"#, { (s: String) in Int(s) }),
            (#"(uno|dos|tres|cuatro|cinco)\\s*(putts|putt|puts|put)"#, { (s: String) in
                switch s {
                case "uno": return 1
                case "dos": return 2
                case "tres": return 3
                case "cuatro": return 4
                case "cinco": return 5
                default: return nil
                }
            })
        ]
        for (pattern, mapper) in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                let first = match.components(separatedBy: " ").first ?? match
                if let value = mapper(first) {
                    return value
                }
            }
        }
        return nil
    }
}
