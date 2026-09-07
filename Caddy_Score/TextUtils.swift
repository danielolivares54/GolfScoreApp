import Foundation
import NaturalLanguage

// Shared text/alias parsing utilities used by ContentView, SetupWizardView, and VoiceInputHandler.
// Static methods are pure (no dependencies). Instance methods require a MatchManager.
struct TextUtils {
    let matchManager: MatchManager

    // MARK: - Static (pure)

    static func containsNoiseDictation(_ text: String) -> Bool {
        text.contains("subtitles") || text.contains("caption") || text.contains("amara") ||
        text.contains("strokes, golpes, base, contra, versus, putts") ||
        hasWord(text, "subtitulo") || hasWord(text, "subtitulos") ||
        hasWord(text, "dictado") || hasWord(text, "transcribe") || hasWord(text, "transcribir") ||
        hasWord(text, "nombres") || hasWord(text, "propios") || hasWord(text, "numeros") ||
        hasWord(text, "precisión") || hasWord(text, "precision") ||
        hasWord(text, "palabras") || hasWord(text, "clave") ||
        hasWord(text, "inventes") || hasWord(text, "texto") || hasWord(text, "golf")
    }

    // NOTE: uses \\b (literal backslash-b) in regex — preserves original ContentView behavior.
    static func hasWord(_ text: String, _ word: String) -> Bool {
        let pattern = #"\\b"# + word + #"\\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func extractFirstNumber(from text: String) -> Int? {
        guard let range = text.range(of: #"(?i)\b(\d{1,2})\b"#, options: .regularExpression) else { return nil }
        return Int(String(text[range]))
    }

    static func extractFirstNumberDecimal(from text: String) -> Double? {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: ".")
        if let range = normalized.range(of: #"(?i)\b(\d{1,2}(?:\.5)?)\b"#, options: .regularExpression),
           let value = Double(String(normalized[range])) { return value }
        if normalized.contains("medio") || normalized.contains("media") || normalized.contains("punto cinco") {
            return Double(extractFirstNumber(from: normalized) ?? 0) + 0.5
        }
        return nil
    }

    static func containsWholePhrase(_ text: String, phrase: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return text.range(of: #"(?i)\b\#(escaped)\b"#, options: .regularExpression) != nil
    }

    static func stripStrokeClause(_ text: String) -> String {
        let pattern = #"(?i)\b(recibe|recibo|da|doy|lleva|llevo|llevas|llevan)\b.*$"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return text }
        return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func splitMatchup(_ text: String) -> (left: String, right: String)? {
        let pattern = #"(?i)\b(versus|contra|vs|v\.s\.)\b"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
    }

    static func substringAfterPattern(_ text: String, pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return after.isEmpty ? nil : after
    }

    static func disjointTeams(_ a: [String], _ b: [String]) -> Bool {
        Set(a).intersection(Set(b)).isEmpty
    }

    static var bannedNameTokens: Set<String> {
        ["el","la","los","las","un","una","unos","unas","de","del","al","por","para","con","sin","y","e","o","u",
         "yo","mi","mis","mio","mia","tu","tus","su","sus","nosotros","ustedes",
         "soy","somos","ser","estar","estoy","estas","esta","estan","juego","juega","juegan","jugamos","jugar",
         "base","companero","companeros","compañero","compañeros","pareja","parejas","contra","vs","versus",
         "recibe","recibo","recibes","da","doy","das","dame","lleva","llevo","llevas","llevan","strokes","golpe","golpes",
         "muy","bueno","malo","grande","pequeno","pequeño","nuevo","viejo","ultimo","último","primer","primero",
         "subtitulo","subtitulos","subtítulos","caption","subtitles","amara","org",
         "agrega","agregar","agrego","agregue","agregué","agregamos","agregan","añade","añadir","añado",
         "dictado","transcribe","transcribir","nombres","propios","numeros","precisión","precision",
         "palabras","clave","inventes","texto","golf"]
    }

    static var compoundNamePairs: Set<String> {
        ["juan carlos","juan pablo","juan manuel","juan jose","juan luis","juan diego",
         "jose luis","jose maria","jose manuel","jose antonio",
         "maria jose","maria carmen","maria fernanda","maria angeles","ana maria","ana sofia"]
    }

    // MARK: - Instance (matchManager-dependent)

    func isCompoundNamePair(first: String, second: String) -> Bool {
        let f = matchManager.normalizePlayerKey(first).lowercased()
        let s = matchManager.normalizePlayerKey(second).lowercased()
        return TextUtils.compoundNamePairs.contains("\(f) \(s)")
    }

    func isValidPlayerName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 30 { return false }
        let lower = matchManager.normalizePlayerKey(trimmed).lowercased()
        if TextUtils.containsNoiseDictation(lower) { return false }
        let tokens = lower.split(separator: " ").map { String($0) }
        if tokens.isEmpty || tokens.count > 3 { return false }
        if tokens.contains(where: { TextUtils.bannedNameTokens.contains($0) || $0.count < 2 }) { return false }
        if trimmed.range(of: #"\d"#, options: .regularExpression) != nil { return false }
        return !trimmed.filter({ $0.isLetter }).isEmpty
    }

    func extractNamesFromText(_ text: String) -> [String] {
        let lower = matchManager.normalizePlayerKey(text).lowercased()
        let hasListCue = lower.contains("juegan") || lower.contains("juega") || lower.contains("jugadores") ||
            lower.contains("son") || lower.contains("somos") || lower.contains("jugamos") ||
            lower.contains("agrego") || lower.contains("agrega") || lower.contains("agregar") ||
            lower.contains("añado") || lower.contains("añade")
        let proper = properNames(from: text)
        if proper.count >= 2 { return proper }
        if proper.count == 1, hasListCue || text.contains(",") || text.contains(";") ||
            lower.contains(" y ") || lower.contains(" e ") {
            let list = extractNamesFromList(text)
            return list.isEmpty ? proper : list
        }
        let list = extractNamesFromList(text)
        return list.isEmpty ? proper : list
    }

    func extractNamesFromList(_ text: String) -> [String] {
        var cleaned = text
        let removePattern = #"(?i)\b(agrega|agregar|agrego|agregue|agregué|agregamos|agregan|añade|añadir|añado|nuevo|jugador|jugadores|soy|somos|compañero|compañeros|companero|companeros|mi|mis|yo|base|contra|vs|versus|pareja|juegan|jugamos|los|lleva|llevo|llevas|llevan|strokes|golpes|recibe|recibo|da|doy|subtitulo|subtitulos|subtítulos|realizado|realizados|comunidad|amara|org|caption|subtitles|de|del|la|el|los|las|por|para|muy)\b"#
        cleaned = cleaned.replacingOccurrences(of: removePattern, with: " ", options: .regularExpression)
        for sep in [" y ", " e ", ",", ";", "&", "+", " con "] {
            cleaned = cleaned.replacingOccurrences(of: sep, with: ",")
        }
        var out: [String] = []
        for part in cleaned.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !part.isEmpty {
            let tokens = part.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
            var i = 0
            while i < tokens.count {
                if i + 1 < tokens.count, isCompoundNamePair(first: tokens[i], second: tokens[i + 1]) {
                    let combined = "\(tokens[i]) \(tokens[i + 1])"
                    if isValidPlayerName(combined) { out.append(combined); i += 2; continue }
                }
                if isValidPlayerName(tokens[i]) { out.append(tokens[i]) }
                i += 1
            }
        }
        return out
    }

    func extractAliasesFromText(_ text: String) -> [String] {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        var result: [String] = []
        for p in matchManager.players {
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey) && TextUtils.containsWholePhrase(t, phrase: aliasKey) {
                result.append(p.alias)
            }
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if !nameKey.isEmpty && TextUtils.containsWholePhrase(t, phrase: nameKey) {
                result.append(p.alias)
            }
        }
        for token in t.split(separator: " ").map({ String($0) }) {
            if !matchManager.isAmbiguousAliasToken(token), let a = matchManager.normalizeAlias(token) {
                result.append(a)
            }
        }
        if t.contains("yo") { result.append(matchManager.yoAlias) }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    func extractAliasesPreferNames(_ text: String) -> [String] {
        let byName = aliasesMatchedByName(text)
        return byName.isEmpty ? extractAliasesFromText(text) : byName
    }

    func aliasesMatchedByName(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        if normalized.isEmpty { return [] }
        var hits: [String] = []
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if !nameKey.isEmpty && TextUtils.containsWholePhrase(normalized, phrase: nameKey) {
                hits.append(p.alias)
            }
        }
        if !hits.isEmpty {
            var seen = Set<String>(); return hits.filter { seen.insert($0).inserted }
        }
        let uniqueFirst = uniqueFirstNameMap()
        for token in normalized.split(separator: " ").map({ String($0) }) {
            if let alias = uniqueFirst[token] { hits.append(alias) }
        }
        var seen = Set<String>(); return hits.filter { seen.insert($0).inserted }
    }

    func uniqueFirstNameMap() -> [String: String] {
        var buckets: [String: [String]] = [:]
        for p in matchManager.players {
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            guard let first = nameKey.split(separator: " ").first.map(String.init), !first.isEmpty else { continue }
            buckets[first, default: []].append(p.alias)
        }
        return buckets.compactMapValues { $0.count == 1 ? $0[0] : nil }
    }

    func orderedAliasesFromText(_ text: String) -> [String] {
        let normalized = matchManager.normalizePlayerKey(text).lowercased()
        var hits: [(alias: String, idx: Int)] = []
        for p in matchManager.players {
            let aliasKey = p.alias.lowercased()
            if !matchManager.isAmbiguousAliasToken(aliasKey), let r = normalized.range(of: aliasKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: r.lowerBound)))
            }
            let nameKey = matchManager.normalizePlayerKey(p.name).lowercased()
            if !nameKey.isEmpty, let r = normalized.range(of: nameKey) {
                hits.append((p.alias, normalized.distance(from: normalized.startIndex, to: r.lowerBound)))
            }
        }
        var seen = Set<String>(); var out: [String] = []
        for hit in hits.sorted(by: { $0.idx < $1.idx }) {
            if seen.insert(hit.alias).inserted { out.append(hit.alias) }
        }
        return out
    }

    func parseStrokeUpdates(_ text: String) -> [(alias: String, value: Double)] {
        var parts: [String] = [text]
        for sep in [",", ";", " y ", " e "] { parts = parts.flatMap { $0.components(separatedBy: sep) } }
        return parts.compactMap { parseStrokeUpdate($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    func parseStrokeUpdate(_ text: String) -> (alias: String, value: Double)? {
        let t = matchManager.normalizePlayerKey(text).lowercased()
        guard let num = TextUtils.extractFirstNumberDecimal(from: text) else { return nil }
        let hasReceive = TextUtils.hasWord(t, "recibe") || TextUtils.hasWord(t, "recibo") || TextUtils.hasWord(t, "recibes") ||
            t.contains("le dan") || t.contains("le da") ||
            TextUtils.hasWord(t, "tengo") || TextUtils.hasWord(t, "tiene") || TextUtils.hasWord(t, "tienen") ||
            TextUtils.hasWord(t, "lleva") || TextUtils.hasWord(t, "llevo") || TextUtils.hasWord(t, "llevan")
        let hasGive = TextUtils.hasWord(t, "da") || TextUtils.hasWord(t, "doy") || TextUtils.hasWord(t, "das") ||
            TextUtils.hasWord(t, "dame") || TextUtils.hasWord(t, "dan")
        if !hasReceive && !hasGive { return nil }
        var aliases = aliasesMatchedByName(text)
        if aliases.isEmpty { aliases = extractAliasesFromText(text) }
        if aliases.isEmpty { return nil }
        var target = aliases.first!
        let hasMe = TextUtils.hasWord(t, "me") || TextUtils.hasWord(t, "yo") || TextUtils.hasWord(t, "mi")
        if hasMe, let other = aliases.first(where: { $0 != matchManager.yoAlias }) { target = other }
        let receiverMode = hasReceive || t.contains(" a ") || t.contains(" para ")
        return (target, receiverMode ? num : -num)
    }

    // MARK: - Private

    private func properNames(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word,
                             scheme: .nameType, options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if tag == .personalName {
                let name = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidPlayerName(name) { names.append(name) }
            }
            return true
        }
        return names
    }
}
