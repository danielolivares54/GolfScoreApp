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

    private var apiKey: String {
        let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
        return key
    }
    
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
            "model": "gpt-4-turbo-preview",
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
