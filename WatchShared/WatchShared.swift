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
    enum State: String, Codable { case ok, doubt, missing }

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

/// Órdenes del Watch. `edit` es el lápiz, `clear` la goma.
enum WatchCommand: Codable, Equatable {
    case edit(alias: String, gross: Int, putts: Int?)
    case clear(alias: String)
    case removeChip(id: String)
    case apply
    case undo
    case discard
}
