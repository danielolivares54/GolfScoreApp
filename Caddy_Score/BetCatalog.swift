import Foundation

struct BetCatalogProfile {
    let tag: String
    let vueltaValue: Int
    let presionValue: Int
    let matchValue: Int
    let entries: [BetCatalogEntry]
}

struct BetCatalogEntry {
    let code: String
    let name: String
    let units: Int
}

enum BetCatalogStore {
    static let fdez = BetCatalogProfile(
        tag: "FDEZ",
        vueltaValue: 50,
        presionValue: 50,
        matchValue: 50,
        entries: [
            BetCatalogEntry(code: "VTA", name: "Vuelta", units: 1),
            BetCatalogEntry(code: "PRS", name: "Presión", units: 1),
            BetCatalogEntry(code: "MAT", name: "Match", units: 1),
            BetCatalogEntry(code: "BIRD", name: "Birdie", units: 1),
            BetCatalogEntry(code: "EAG", name: "Eagle", units: 1),
            BetCatalogEntry(code: "OYES", name: "Oyes", units: 1)
        ]
    )
}
