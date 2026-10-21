//
//  DemoFixture.swift
//  Caddy_ScoreTests
//
//  La ronda demo del CGM (caso de estudio) con TODO lo que influye en el dinero definido aquí,
//  para que las pruebas no dependan de lo que haya guardado en el dispositivo:
//  valores de apuesta del propio demo (vuelta/presión/match $50, unidad $25) y un catálogo de
//  unidades fijo.
//
//  Correr solo en simulador: loadDemo18() guarda la config de apuestas (saveBetConfig).
//

import Testing
@testable import Caddy_Score

@MainActor
enum DemoFixture {
    /// Ronda demo recién cargada: CGM, sale en el hoyo 1, ROB da 8 a DAN,
    /// pareja DAN+FER vs RIC+ANS con 12 (lleva ANS), Carry y Doble B9 contra ROB.
    static func make() -> MatchManager {
        let m = MatchManager()
        m.loadDemo18()
        m.betCatalog = defaultCatalog()
        return m
    }

    static func defaultCatalog() -> [BetDefinition] {
        [
            BetDefinition(tag: "BIRD", name: "Birdie", type: .individual, mode: .calculado, units: 1, description: ""),
            BetDefinition(tag: "EAG", name: "Águila", type: .individual, mode: .calculado, units: 1, description: ""),
            BetDefinition(tag: "ALB", name: "Albatros", type: .individual, mode: .calculado, units: 1, description: ""),
            BetDefinition(tag: "HIO", name: "Hole in One", type: .individual, mode: .calculado, units: 1, description: ""),
            BetDefinition(tag: "B18", name: "Birdie en 18", type: .individual, mode: .calculado, units: 1, description: ""),
            BetDefinition(tag: "3P", name: "3 Putt", type: .individual, mode: .manual, units: 1, description: ""),
            BetDefinition(tag: "HO", name: "Hole Out", type: .individual, mode: .manual, units: 1, description: ""),
            BetDefinition(tag: "OYES", name: "Oyes Rank", type: .individual, mode: .manual, units: 1, description: ""),
            BetDefinition(tag: "PAIR", name: "Match Parejas", type: .parejas, mode: .manual, units: 1, description: ""),
            BetDefinition(tag: "OYESP", name: "Oyes Rank Parejas", type: .parejas, mode: .manual, units: 1, description: ""),
        ]
    }
}
