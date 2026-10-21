//
//  ContentViewV2.swift
//  Caddie Score — Vista v2 (fase P0: solo el marco)
//
//  Por ahora es un marcador: demuestra que la Vista v2 usa EL MISMO MatchManager que la v1
//  (los números de abajo salen del match compartido) y permite volver a la v1. Las pantallas
//  reales (Resultado, Tarjeta, Historial, Hoyo, Setup) se construyen en las fases siguientes.
//  Solo lectura: no modifica el match.
//

import SwiftUI

struct ContentViewV2: View {
    @ObservedObject var matchManager: MatchManager
    @AppStorage("uiVersion") private var uiVersion = "v1"
    // P1: la pantalla Resultado v2 se abre desde aquí hasta que exista la barra inferior (RoundBarV2).
    @State private var showResultado = false

    private var scoresEntered: Int { matchManager.players.first?.scores.count ?? 0 }
    private var oyesHoles: Int { matchManager.oyesRanksByHole.count }
    private var eventCount: Int { matchManager.unitEventsByHole.values.reduce(0) { $0 + $1.count } }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: CSV2.s2) {
                HStack {
                    Text("\(matchManager.courseName) · Sale H\(matchManager.startHole)")
                        .font(.v2Name).foregroundStyle(CSV2.ink)
                    Spacer()
                    PrimaryButtonV2(title: "Vista v1") { uiVersion = "v1" }
                }

                CardV2 {
                    VStack(alignment: .leading, spacing: CSV2.s1) {
                        Text("Vista v2 — en construcción")
                            .font(.v2Name).foregroundStyle(CSV2.ink)
                        Text("Mismo match que la v1. Estos números salen del match compartido:")
                            .font(.v2Label).foregroundStyle(CSV2.secondary)
                        row("Jugadores", "\(matchManager.players.count)")
                        row("Hoyos con score", "\(scoresEntered) de 18")
                        row("Hoyos con oyes", "\(oyesHoles)")
                        row("Eventos de unidad", "\(eventCount)")
                        HStack {
                            Text("Total en curso").font(.v2Body).foregroundStyle(CSV2.secondary)
                            Spacer()
                            MoneyTextV2(amount: matchManager.walletSnapshot().totalMoney, size: 20, weight: .bold)
                        }
                    }
                    .padding(CSV2.s2)
                }

                PrimaryButtonV2(title: "Resultado") { showResultado = true }

                Spacer()
            }
            .padding(CSV2.s2)
        }
        .sheet(isPresented: $showResultado) {
            ResultadoV2(matchManager: matchManager)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.v2Body).foregroundStyle(CSV2.secondary)
            Spacer()
            Text(value).font(.v2Body).foregroundStyle(CSV2.ink)
        }
    }
}

#Preview("ContentViewV2 · demo") {
    ContentViewV2(matchManager: MatchManager())
}
