import Foundation

struct HoleEntryEvent: Codable {
    let type: String
    let data: HoleEntryData

    init(data: HoleEntryData) {
        self.type = "HOLE_ENTRY"
        self.data = data
    }
}

struct HoleEntryData: Codable {
    let hole_number: Int
    let player_alias: String
    let strokes: Int
    let putts: Int?
    let units: Double?
    let tags: [String]?
}

struct ValidationResult: Codable {
    let ok: Bool
    let missing_fields: [String]
    let error: String?
}

enum HoleEntryValidator {
    static func validate(_ event: HoleEntryEvent) -> ValidationResult {
        var missing: [String] = []
        var error: String? = nil

        if event.data.hole_number < 1 || event.data.hole_number > 18 {
            error = "hole_number inválido"
        }
        if event.data.player_alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("player_alias")
        }
        if event.data.strokes <= 0 {
            missing.append("strokes")
        }

        return ValidationResult(ok: missing.isEmpty && error == nil, missing_fields: missing, error: error)
    }
}
