//
//  WatchShared.swift
//  Compartido por el iPhone y el Watch (mismo archivo en los dos targets).
//
//  El iPhone es el dueño del borrador del hoyo: transcribe, interpreta y aplica. El Watch solo graba, pinta
//  la tarjeta que recibe (`WatchCardDTO`) y manda órdenes (`WatchCommand`). Nada de lógica de golf aquí.
//

import Foundation

enum WatchKey {
    /// iPhone → Watch (applicationContext): la tarjeta propuesta y el hoyo en juego.
    static let card = "card"
    static let context = "context"
    /// iPhone → Watch: la respuesta a una pregunta ("cómo voy", "por qué").
    static let answer = "answer"
    /// Watch → iPhone (sendMessageData / transferFile metadata).
    static let command = "command"
    static let audioHole = "audioHole"
}

/// Lo que el Watch necesita para el inicio: hoyo en juego y par.
struct WatchContextDTO: Codable, Equatable {
    var hole: Int
    var par: Int
    var course: String
    var hasKey: Bool
    /// Distancia del hoyo desde el tee de salida. Por ahora fija (ver `WatchCardCoordinator.placeholderTeeDistance`); luego sale de la tarjeta del campo.
    var teeDistance: Int? = nil
}

/// La tarjeta del hoyo tal como se va a anotar. Todo se calcula en el iPhone.
struct WatchCardDTO: Codable, Equatable {
    /// `saved` = el hoyo ya tenía ese score anotado y la dictada no lo toca.
    enum State: String, Codable { case ok, doubt, missing, saved }

    struct Row: Codable, Equatable, Identifiable {
        var alias: String
        var name: String
        var gross: Int?
        var putts: Int?
        var state: State
        /// Lo que oyó el iPhone o por qué es dudoso ("¿Anselmo o Ansel?").
        var note: String?
        var id: String { alias }
    }

    struct Chip: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case unit, oyes, note }
        var id: String
        var kind: Kind
        var text: String
    }

    /// Se acaba de anotar: la pantalla de resultado con Deshacer.
    struct Applied: Codable, Equatable {
        var hole: Int
        var message: String
        var canUndo: Bool
    }

    var hole: Int?
    var par: Int?
    /// El hoyo ya tenía datos: anotar los reemplaza.
    var replaces: Bool
    var rows: [Row]
    var chips: [Chip]
    var heard: String
    /// Aviso sin bloquear (p. ej. nombres que no se entendieron y se descartaron).
    var notice: String? = nil
    var canApply: Bool
    /// Mensaje del iPhone cuando algo no salió ("No entendí datos del hoyo…", "Falta la clave de OpenAI…").
    var error: String?
    var processing: Bool
    var applied: Applied?
    /// Sube con cada cambio: el Watch ignora lo viejo.
    var revision: Int

    static let empty = WatchCardDTO(hole: nil, par: nil, replaces: false, rows: [], chips: [], heard: "",
                                    canApply: false, error: nil, processing: false, applied: nil, revision: 0)
}

/// La respuesta a una pregunta hablada: corta y objetiva. El reloj la pinta y la dice en voz alta (`spoken`).
/// Todo se calcula en el iPhone; el `id` cambia con cada respuesta para que el reloj no repita la voz.
struct WatchAnswerDTO: Codable, Equatable {
    struct Line: Codable, Equatable {
        /// Jugador, pareja u hoyo.
        var label: String
        /// Los números ("3 -1") o el resultado ("pierdes").
        var value: String
        /// Segunda línea más pequeña (golpes, neto…).
        var detail: String? = nil
        /// -1 va perdiendo, 0 parejo, 1 va ganando: el color del valor.
        var tone: Int = 0
        /// Encabezado de grupo (el rival, la pareja).
        var header: Bool = false
    }

    var id: String = UUID().uuidString
    var title: String
    var lines: [Line] = []
    /// Respuestas sin estructura (cualquier otra pregunta): solo texto.
    var text: String? = nil
    var spoken: String

    static func plain(_ text: String) -> WatchAnswerDTO { WatchAnswerDTO(title: "", text: text, spoken: text) }
}

/// Órdenes del Watch. `edit` es el lápiz, `clear` la goma.
enum WatchCommand: Codable, Equatable {
    case edit(alias: String, gross: Int, putts: Int?)
    case clear(alias: String)
    case removeChip(id: String)
    case apply
    case undo
    case discard
}
