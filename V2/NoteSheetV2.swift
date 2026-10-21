//
//  NoteSheetV2.swift
//  Caddie Score — Vista v2, Paso 4: nota o penalidad del hoyo
//
//  Misma escritura que la v1 (campo "penalidad o comentario…"): upsertUnitEvent con código "NOTA"
//  (0 unidades) y removeUnitEvent si el texto queda vacío.
//

import SwiftUI

struct NoteSheetV2: View {
    @ObservedObject var matchManager: MatchManager
    let hole: Int
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAlias: String?
    @State private var text = ""

    private var alias: String? { selectedAlias ?? matchManager.players.first?.alias }

    private func savedNote(for alias: String?) -> String {
        (matchManager.unitEventsByHole[hole] ?? [])
            .first { $0.alias == alias && $0.code == "NOTA" }?.note ?? ""
    }

    var body: some View {
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: CSV2.s2) {
                HStack {
                    Text("Nota · hoyo \(hole)").font(.v2Name).foregroundStyle(CSV2.ink)
                    Spacer()
                    PrimaryButtonV2(title: "Guardar") { save(); dismiss() }
                }
                if matchManager.players.isEmpty {
                    Text("Configura jugadores en Setup.").font(.v2Body).foregroundStyle(CSV2.secondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(matchManager.players, id: \.id) { player in
                            let on = player.alias == alias
                            Button {
                                save()
                                selectedAlias = player.alias
                                text = savedNote(for: player.alias)
                            } label: {
                                Text(player.alias).font(.v2Body).foregroundStyle(on ? .white : CSV2.ink)
                                    .frame(maxWidth: .infinity, minHeight: CSV2.minTap)
                                    .background(on ? CSV2.green : CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCell))
                                    .overlay(RoundedRectangle(cornerRadius: CSV2.rCell).stroke(on ? CSV2.green : CSV2.line))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("penalidad o comentario…", text: $text, axis: .vertical)
                        .font(.v2Body).lineLimit(3...6)
                        .padding(CSV2.s2)
                        .background(CSV2.surface, in: RoundedRectangle(cornerRadius: CSV2.rCard))
                        .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).stroke(CSV2.line))
                    Text("Dejarla vacía borra la nota de este jugador en este hoyo.")
                        .font(.v2Label).foregroundStyle(CSV2.secondary)
                }
                Spacer()
            }
            .padding(CSV2.s2)
        }
        .onAppear { text = savedNote(for: alias) }
    }

    private func save() {
        guard let alias else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            matchManager.removeUnitEvent(hole: hole, alias: alias, code: "NOTA")
        } else {
            matchManager.upsertUnitEvent(hole: hole, alias: alias, code: "NOTA", units: 0, note: trimmed)
        }
    }
}

#if DEBUG
#Preview("NoteSheetV2 · hoyo 14") {
    let manager = MatchManager()
    manager.loadDemo18()
    manager.upsertUnitEvent(hole: 14, alias: "DAN", code: "NOTA", units: 0, note: "Penalidad: bola al agua")
    return NoteSheetV2(matchManager: manager, hole: 14)
}
#endif
