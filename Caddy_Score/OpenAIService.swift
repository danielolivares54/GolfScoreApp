//
//  OpenAIService.swift
//  Caddy_Score
//
//  Created by daniel olivares on 2/14/26.
//
import Foundation

struct LLMResult: Codable {
    let ok: Bool
    let error: String?
    let intent: String?
    let entities: ScoreEntities
}

struct ScoreEntities: Codable {
    let hoyo: Int?
    let scores: [PlayerScore]?
}

struct PlayerScore: Codable {
    let jugador: String
    let gross: Int
    let putts: Int?
}

class OpenAIService {
    static let shared = OpenAIService()

    private var apiKey: String { AppConfig.value("OPENAI_API_KEY") ?? "" }
    
    func transcribeAudio(url: URL) async throws -> String {
        guard !apiKey.isEmpty, apiKey != "MISSING" else {
            throw NSError(domain: "Config", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Falta OPENAI_API_KEY en Info.plist"
            ])
        }
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        let audioData = try Data(contentsOf: url)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("gpt-4o-mini-transcribe\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("es\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append("Dictado de golf. Transcribe nombres propios y números con precisión. Palabras clave: hoyo, strokes, golpes, base, parejas, contra, versus, putts. No inventes texto.\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
        
        return response.text
    }
    
    func parseScore(transcript: String, matchState: [String: Any]) async throws -> LLMResult {
        guard !apiKey.isEmpty, apiKey != "MISSING" else {
            throw NSError(domain: "Config", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Falta OPENAI_API_KEY en Info.plist"
            ])
        }
        let systemPrompt = """
        Eres un asistente de golf que extrae información de transcripciones de voz.
        
        REGLAS:
        1. Extrae SOLO información explícita
        2. NO inventes jugadores o scores
        3. Valida contra MATCH_STATE (jugadores, yo_alias, base_team)
        4. Si el texto dice "yo", usa yo_alias
        5. Si el texto dice "todos", incluye todos los jugadores
        6. Si el texto dice "los demas", incluye todos menos los ya mencionados
        7. Retorna SOLO JSON
        
        ENTIDADES:
        - intent: "registro_score"
        - hoyo: número (1-18)
        - scores: [{ jugador: string, gross: number, putts: number|null }]
        """
        
        let matchStateJSON = try JSONSerialization.data(withJSONObject: matchState, options: .prettyPrinted)
        let matchStateString = String(data: matchStateJSON, encoding: .utf8) ?? ""
        
        let userPrompt = """
        CONTEXTO:
        \(matchStateString)
        
        TRANSCRIPCIÓN:
        "\(transcript)"
        
        Retorna JSON:
        {
          "ok": true,
          "intent": "registro_score",
          "entities": {
            "hoyo": <número>,
            "scores": [{ "jugador": "<NOMBRE>", "gross": <número>, "putts": <número|null> }]
          }
        }
        
        SOLO JSON.
        """
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.6,
            "max_tokens": 500
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GPTResponse.self, from: data)
        
        guard let content = response.choices.first?.message.content else {
            throw NSError(domain: "GPT", code: -1)
        }
        
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let resultData = cleaned.data(using: .utf8)!
        return try JSONDecoder().decode(LLMResult.self, from: resultData)
    }

    /// Dictado integral de un hoyo: score, putts, orden de oyes, unidades y notas de todos los jugadores.
    /// `context` trae el roster, el hoyo, las unidades válidas y los apodos aprendidos (ver VoiceHolePipeline.context).
    func parseHole(transcript: String, context: [String: Any]) async throws -> VoiceHoleExtraction {
        guard !apiKey.isEmpty, apiKey != "MISSING" else {
            throw NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Falta OPENAI_API_KEY en Info.plist"])
        }
        let systemPrompt = """
        Eres el capturista de una tarjeta de golf. Extraes SOLO lo que el jugador dijo, en JSON.
        REGLAS:
        0. NO INVENTES NADA. Cada dato debe estar dicho explícitamente en la transcripción; lo que no se dijo va vacío o null.
        1. "jugador" es el alias del roster SOLO si lo dijeron igual o claramente igual (nombre o alias). Un apodo que no esté en "apodos" ni sea claramente un jugador ("el chino", "pelón") se copia tal cual, SIN adivinar a quién se refiere. Nunca inventes jugadores.
        2. "yo" = yo_alias. "apodos" mapea apodos ya aprendidos a un alias: úsalos.
        3. scores: un elemento por jugador mencionado con gross (golpes) y/o putts. Si dicen par/birdie/eagle/bogey/doble bogey SIN número, NO calcules: pon gross null y "relativo": "par"|"birdie"|"eagle"|"bogey"|"doble_bogey". Si dicen "hizo cinco" sin decir quién, jugador "" (NO asumas yo). "tripoteó" = putts 3, "cuatripoteo" = putts 4. Si se corrigen ("seis... no, cinco") deja solo el último valor.
        4. oyes: SOLO si oyes_activo Y dijeron el orden de oyes ("oyes primero…", "más cerca…"). Una unidad como hole out NO implica oyes. rank 1 = el más cerca del hoyo, 2 = segundo, etc. "Oyes primero Ricardo, segundo Daniel" -> [{Ricardo,1},{Daniel,2}].
        5. unidades: SOLO códigos de la lista "unidades" (sandy par, green en regulación…). Si dicen una que no está, usa el texto dicho como codigo. cantidad = 1 si no se dice.
        6. notas: comentarios o penalidades que no sean unidad ("se fue al agua"). jugador = quien se dijo tal cual, o "" si no se dice de quién.
        8. hoyo: SOLO si dijeron el número de hoyo; si no, null (no uses hoyo_actual).
        10. "los demás cinco" / "todos cinco": un elemento en scores con jugador "DEMAS" y ese gross. "los demás bogey" / "todos hicimos par": jugador "DEMAS", gross null, "relativo" correspondiente; NUNCA lo pongas como nota. "todos hicimos X" = DEMAS (la app lo reparte a quien no se nombró).
        11. Una corrección de OTRO hoyo ("corrige a Daniel: fueron cinco en el seis") es hoyo=6 con scores [{DAN,5}], no una nota.
        12. "se levantó", "recogió", "perdió el hoyo", "no terminó el hoyo", "bola equivocada" (jugó la bola de otro): en scores {jugador, gross null, levanto true, "motivo":"bola equivocada" si lo dijeron}. NO pongas gross (la app calcula uno que pierda el hoyo). Misma regla para todos.
        13. Corrección de VARIOS hoyos ("del hoyo 5 al 8 Daniel tiró par, bogey, doble bogey y dos putts por hoyo"): va en "corridas": [{"jugador","desde":5,"hasta":8,"resultados":[{"relativo":"par"},{"relativo":"bogey"},{"relativo":"doble_bogey"}],"putts":2}]. Un elemento de resultados por hoyo EN EL ORDEN DICHO, sin completar ni repetir los que no dijeron; con número: {"gross":5}; levantó o bola equivocada: {"levanto":true} y "motivo" en la corrida. "putts" = putts por hoyo si lo dijeron.
        9. Un jugador que solo aparece en una unidad o nota NO lleva elemento en scores.
        7. No incluyas listas vacías con datos inventados. Si no hay nada del hoyo, devuelve todo vacío.
        Responde SOLO JSON: {"hoyo":n|null,"scores":[{"jugador":"","gross":n|null,"putts":n|null,"relativo":""|null,"levanto":true|null,"motivo":""|null}],"oyes":[{"jugador":"","rank":n}],"unidades":[{"jugador":"","codigo":"","cantidad":n}],"notas":[{"jugador":"","texto":""}],"corridas":[]}
        """
        let contextData = try JSONSerialization.data(withJSONObject: context, options: [.sortedKeys])
        let userPrompt = "CONTEXTO:\n\(String(data: contextData, encoding: .utf8) ?? "{}")\n\nTRANSCRIPCIÓN:\n\"\(transcript)\"\n\nSOLO JSON."

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": userPrompt]],
            "temperature": 0.2,
            "max_tokens": 700,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GPTResponse.self, from: data)
        guard let content = response.choices.first?.message.content,
              let json = content.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            throw NSError(domain: "GPT", code: -1)
        }
        return try JSONDecoder().decode(VoiceHoleExtraction.self, from: json)
    }

    func confirmPlayerNames(candidates: [String], transcript: String) async throws -> NameConfirmResponse {
        guard !apiKey.isEmpty, apiKey != "MISSING" else {
            throw NSError(domain: "Config", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Falta OPENAI_API_KEY en Info.plist"
            ])
        }
        let systemPrompt = """
        Eres un asistente que valida nombres de jugadores de golf.
        REGLAS:
        1) Acepta SOLO sustantivos propios de personas.
        2) Rechaza verbos, adjetivos, palabras de relleno o frases.
        3) Si hay duda, rechaza.
        4) Mantén nombres compuestos (ej. "Juan Carlos").
        5) No inventes nombres.
        Responde SOLO JSON.
        """

        let userPrompt = """
        TRANSCRIPCION:
        "\(transcript)"

        CANDIDATOS:
        \(candidates)

        Responde JSON:
        {
          "ok": true,
          "accepted": ["..."],
          "rejected": ["..."],
          "notes": "..."
        }
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.6,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GPTResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw NSError(domain: "GPT", code: -1)
        }
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resultData = cleaned.data(using: .utf8)!
        return try JSONDecoder().decode(NameConfirmResponse.self, from: resultData)
    }
}

struct WhisperResponse: Codable {
    let text: String
}

struct GPTResponse: Codable {
    let choices: [GPTChoice]
}

struct GPTChoice: Codable {
    let message: GPTMessage
}

struct GPTMessage: Codable {
    let content: String
}

struct NameConfirmResponse: Codable {
    let ok: Bool
    let accepted: [String]
    let rejected: [String]?
    let notes: String?
}

// MARK: - Configuración local (caddie.env)

/// Claves y datos del usuario fuera del código: un archivo `caddie.env` con líneas CLAVE=valor (# = comentario).
/// Se busca en este orden: Documents del teléfono (se copia con la app Archivos o Finder; la app comparte
/// Documents), el bundle, y por último el Info.plist (OPENAI_API_KEY). El archivo real NO se sube a git.
/// Claves conocidas: OPENAI_API_KEY, USER_NAME.
enum AppConfig {
    static let fileName = "caddie.env"

    static func value(_ key: String) -> String? {
        let v = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v, !v.isEmpty, v != "MISSING", !v.hasPrefix("REPLACE_WITH") { return v }
        if let plist = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !plist.isEmpty, plist != "MISSING", !plist.hasPrefix("REPLACE_WITH") { return plist }
        return nil
    }

    /// Nombre del usuario ("yo") si está en el archivo; nil si no.
    static var userName: String? { value("USER_NAME") }

    static var hasOpenAIKey: Bool { value("OPENAI_API_KEY") != nil }

    static var values: [String: String] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
        let bundled = Bundle.main.url(forResource: "caddie", withExtension: "env")
        for url in [docs, bundled].compactMap({ $0 }) {
            if let text = try? String(contentsOf: url, encoding: .utf8) { return parse(text) }
        }
        return [:]
    }

    /// Texto → diccionario. Acepta comillas, `export `, espacios y comentarios.
    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line.removeFirst(7) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if val.count >= 2, let f = val.first, f == "\"" || f == "'", val.last == f { val = String(val.dropFirst().dropLast()) }
            if !key.isEmpty { out[key] = val }
        }
        return out
    }
}
