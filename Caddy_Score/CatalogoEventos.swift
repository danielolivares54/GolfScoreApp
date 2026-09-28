import Foundation

// Modelo del catálogo único de eventos (catalogo_eventos_caddie.json).
// Fuente de verdad para símbolos, colores, unidades y palabras de voz.
// No reemplaza aún el catálogo hardcodeado de MatchManager — ver punto 20 de
// CAMBIOS_CADDIE_v2.md, requiere autorización explícita antes de conectarlo.

enum ReglaDiff: Codable, Equatable {
    case exact(Int)
    case atLeast(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .exact(intValue)
            return
        }
        let stringValue = try container.decode(String.self)
        if stringValue.hasPrefix(">="), let n = Int(stringValue.dropFirst(2)) {
            self = .atLeast(n)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "regla_diff_par inválida: \(stringValue)"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .exact(let n): try container.encode(n)
        case .atLeast(let n): try container.encode(">=\(n)")
        }
    }

    func matches(diffVsPar: Int) -> Bool {
        switch self {
        case .exact(let n): return diffVsPar == n
        case .atLeast(let n): return diffVsPar >= n
        }
    }
}

struct EventoCalculado: Codable, Identifiable, Equatable {
    let id: String
    let nombre: String
    let reglaDiffPar: ReglaDiff
    let simbolo: String
    let color: String
    let unidades: Int?
    let voz: [String]

    enum CodingKeys: String, CodingKey {
        case id, nombre, simbolo, color, unidades, voz
        case reglaDiffPar = "regla_diff_par"
    }
}

struct UnidadManual: Codable, Identifiable, Equatable {
    let id: String
    let nombre: String
    let descripcion: String
    let soloHoyosPar: [Int]?
    let unidades: Int?
    let requiere: [String]
    let voz: [String]

    enum CodingKeys: String, CodingKey {
        case id, nombre, descripcion, unidades, requiere, voz
        case soloHoyosPar = "solo_hoyos_par"
    }
}

struct ReglasCatalogo: Codable, Equatable {
    let aplicaA: String
    let baseCalculo: String
    let unidadColorGana: String
    let unidadColorPierde: String

    enum CodingKeys: String, CodingKey {
        case aplicaA = "aplica_a"
        case baseCalculo = "base_calculo"
        case unidadColorGana = "unidad_color_gana"
        case unidadColorPierde = "unidad_color_pierde"
    }
}

struct CatalogoEventos: Codable, Equatable {
    let version: Int
    let descripcion: String
    let reglas: ReglasCatalogo
    let eventosCalculados: [EventoCalculado]
    let unidadesManuales: [UnidadManual]

    enum CodingKeys: String, CodingKey {
        case version, descripcion, reglas
        case eventosCalculados = "eventos_calculados"
        case unidadesManuales = "unidades_manuales"
    }
}

enum CatalogoEventosLoader {
    // Carga catalogo_eventos_caddie.json desde el bundle de la app.
    static func load() -> CatalogoEventos? {
        guard let url = Bundle.main.url(forResource: "catalogo_eventos_caddie", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CatalogoEventos.self, from: data)
        } catch {
            return nil
        }
    }

    // Evento calculado cuyo regla_diff_par coincide con diffVsPar (golpes brutos - par),
    // según lo que confirmaste: birdie/eagle se calculan en bruto.
    static func eventoCalculado(diffVsPar: Int, in catalogo: CatalogoEventos) -> EventoCalculado? {
        catalogo.eventosCalculados.first { $0.reglaDiffPar.matches(diffVsPar: diffVsPar) }
    }
}
