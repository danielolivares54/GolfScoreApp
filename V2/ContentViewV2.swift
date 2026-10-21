//
//  ContentViewV2.swift
//  Caddie Score — Vista v2: raíz
//
//  Usa EL MISMO MatchManager que la v1. La pantalla de inicio es HoleScreenV2 (captura a mano);
//  Tarjeta y Resultado se abren desde su barra inferior.
//

import SwiftUI

struct ContentViewV2: View {
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        HoleScreenV2(matchManager: matchManager)
            .onAppear {
                // Si la app abre directo en la v2, la v1 nunca corrió la carga inicial del match.
                if !matchManager.didRunInitialSetup { matchManager.loadInitialMatchState() }
            }
    }
}

#Preview("ContentViewV2 · demo") {
    ContentViewV2(matchManager: MatchManager())
}
