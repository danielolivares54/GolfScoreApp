import SwiftUI

// Administración manual del directorio de jugadores (SSOT Sección 17, PLAYER_BET_TAGS) — el
// mini-search del Setup aprende solo, pero aquí se puede agregar/editar/borrar sin pasar por
// un match real, o corregir un stroke/tag que cambió de temporada a temporada.
struct PlayerDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlayerDirectoryStore.shared
    @ObservedObject private var templateStore = BetTemplateStore.shared
    @State private var editingEntry: PlayerDirectoryEntry?
    @State private var showingNew = false

    private var sortedEntries: [PlayerDirectoryEntry] {
        store.entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedEntries.isEmpty {
                    VStack(spacing: 8) {
                        Text("Sin jugadores en el directorio")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Se van agregando solos cuando los usas en un Setup, o agrégalos aquí manualmente.")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sortedEntries) { entry in
                            Button { editingEntry = entry } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(entry.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(entry.active ? .primary : .secondary)
                                            if !entry.active {
                                                Text("INACTIVO")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.15))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        Text(entry.alias)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Strokes \(formatStroke(entry.strokesVsBase))")
                                            .font(.system(size: 12, weight: .semibold))
                                        if let tagId = entry.preferredTagId,
                                           let tpl = templateStore.entries.first(where: { $0.id == tagId }) {
                                            Text(tpl.name)
                                                .font(.system(size: 11)).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for idx in offsets { store.remove(sortedEntries[idx]) }
                        }
                    }
                }
            }
            .navigationTitle("Directorio de jugadores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editingEntry) { entry in
                PlayerDirectoryEditView(entry: entry)
            }
            .sheet(isPresented: $showingNew) {
                PlayerDirectoryEditView(entry: nil)
            }
        }
    }

    private func formatStroke(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }
}

private struct PlayerDirectoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PlayerDirectoryStore.shared
    @ObservedObject private var templateStore = BetTemplateStore.shared
    let entry: PlayerDirectoryEntry?

    @State private var name: String = ""
    @State private var alias: String = ""
    @State private var strokesText: String = ""
    @State private var selectedTagId: String = ""
    @State private var isActive: Bool = true
    @State private var opponentTee: String = ""
    @State private var myTee: String = ""
    @State private var adjustmentNotes: String = ""
    @State private var comentario: String = ""
    @State private var strokeAntText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Jugador") {
                    TextField("Nombre", text: $name)
                    TextField("Alias (3 letras)", text: $alias)
                        .textInputAutocapitalization(.characters)
                    Toggle("Activo", isOn: $isActive)
                }
                Section("Strokes y apuesta") {
                    TextField("Strokes vs base", text: $strokesText)
                        .keyboardType(.decimalPad)
                    Picker("Plantilla preferida", selection: $selectedTagId) {
                        Text("Ninguna").tag("")
                        ForEach(templateStore.entries) { tpl in
                            Text(tpl.name).tag(tpl.id)
                        }
                    }
                    TextField("Stroke anterior", text: $strokeAntText)
                        .keyboardType(.decimalPad)
                }
                Section("Tees") {
                    TextField("Tee de salida (rival)", text: $opponentTee)
                    TextField("Mi tee", text: $myTee)
                }
                Section("Notas") {
                    TextField("Notas de ajuste", text: $adjustmentNotes)
                    TextField("Comentario", text: $comentario)
                }
                if entry != nil {
                    Section {
                        Button("Eliminar del directorio", role: .destructive) {
                            if let entry { store.remove(entry) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Nuevo jugador" : "Editar jugador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let entry {
                    name = entry.name
                    alias = entry.alias
                    strokesText = formatStroke(entry.strokesVsBase)
                    selectedTagId = entry.preferredTagId ?? ""
                    isActive = entry.active
                    opponentTee = entry.opponentTee ?? ""
                    myTee = entry.myTee ?? ""
                    adjustmentNotes = entry.adjustmentNotes ?? ""
                    comentario = entry.comentario ?? ""
                    strokeAntText = entry.strokeAnt.map { formatStroke($0) } ?? ""
                }
            }
        }
    }

    private func save() {
        let cleanAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let strokes = Double(strokesText) ?? 0
        // Si se renombró (nombre distinto al original), el match por nombre de upsert() no lo
        // encontraría — se borra la entrada vieja primero para no dejar un duplicado huérfano.
        if let entry, entry.name.caseInsensitiveCompare(name) != .orderedSame {
            store.remove(entry)
        }
        store.upsert(name: name, alias: cleanAlias, strokesVsBase: strokes, preferredTagId: selectedTagId.isEmpty ? nil : selectedTagId, active: isActive)
        if let saved = store.entries.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            let cleanOpponentTee = opponentTee.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanMyTee = myTee.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAdjustmentNotes = adjustmentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanComentario = comentario.trimmingCharacters(in: .whitespacesAndNewlines)
            store.setDetails(
                id: saved.id,
                opponentTee: cleanOpponentTee.isEmpty ? nil : cleanOpponentTee,
                myTee: cleanMyTee.isEmpty ? nil : cleanMyTee,
                adjustmentNotes: cleanAdjustmentNotes.isEmpty ? nil : cleanAdjustmentNotes,
                comentario: cleanComentario.isEmpty ? nil : cleanComentario,
                strokeAnt: Double(strokeAntText.trimmingCharacters(in: .whitespacesAndNewlines))
            )
        }
        dismiss()
    }

    private func formatStroke(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.001 ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }
}
