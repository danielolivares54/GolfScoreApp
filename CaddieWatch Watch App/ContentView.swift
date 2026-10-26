//
//  ContentView.swift
//  Inicio → Dictando → Tarjeta (lápiz y goma, Anotar) → Resultado (Deshacer).
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: WatchModel

    var body: some View {
        NavigationStack {
            Group {
                if let applied = model.card.applied {
                    ResultView(model: model, applied: applied)
                } else if model.phase == .recording {
                    RecordingView(model: model)
                } else if model.isWorking {
                    WorkingView()
                } else if model.hasDraft {
                    CardView(model: model)
                } else {
                    HomeView(model: model)
                }
            }
            .background(CSW.background)
        }
        .tint(CSW.green)
        .onAppear { model.requestState() }
    }
}

// MARK: - Inicio

private struct HomeView: View {
    @Bindable var model: WatchModel

    var body: some View {
        ScrollView {
        VStack(spacing: 8) {
            if let ctx = model.context {
                VStack(spacing: 0) {
                    Text("ESPERANDO").font(.wCaps).foregroundStyle(CSW.secondary)
                    Text("HOYO \(ctx.hole)").font(.system(.title2, weight: .heavy).monospacedDigit()).foregroundStyle(CSW.ink)
                    Text("PAR \(ctx.par)" + (ctx.teeDistance.map { " · \($0)" } ?? "")).font(.wCaps).foregroundStyle(CSW.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Esperando el hoyo \(ctx.hole), par \(ctx.par)" + (ctx.teeDistance.map { ", \($0) de distancia" } ?? ""))
            } else {
                Text("Abre Caddie Score en el iPhone").font(.wBody).foregroundStyle(CSW.secondary).multilineTextAlignment(.center)
            }
            WatchPrimaryButton(title: "Dictar") { model.startRecording() }
                .disabled(model.context == nil)
            if let message = model.card.error ?? failure {
                Text(message).font(.wCaps).foregroundStyle(CSW.red).multilineTextAlignment(.center)
            } else if model.context?.hasKey == false {
                Text("Falta la clave de OpenAI en el iPhone").font(.wCaps).foregroundStyle(CSW.warning).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 6)
        }
    }

    private var failure: String? {
        if case .failed(let text) = model.phase { return text }
        return nil
    }
}

// MARK: - Dictando y enviando

private struct RecordingView: View {
    @Bindable var model: WatchModel

    var body: some View {
        VStack(spacing: 10) {
            Label("Escuchando…", systemImage: "waveform").font(.wName).foregroundStyle(CSW.red)
            if let ctx = model.context { Text("HOYO \(ctx.hole) · PAR \(ctx.par)").font(.wCaps).foregroundStyle(CSW.ink) }
            Text("Di el hoyo completo: golpes, putts, oyes y unidades.").font(.wCaps).foregroundStyle(CSW.secondary).multilineTextAlignment(.center)
            WatchPrimaryButton(title: "Terminar") { model.stopAndSend() }
            Button("Cancelar") { model.cancelRecording() }.font(.wCaps).foregroundStyle(CSW.secondary)
        }
        .padding(.horizontal, 6)
    }
}

private struct WorkingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Interpretando…").font(.wBody).foregroundStyle(CSW.secondary)
        }
    }
}

// MARK: - Tarjeta propuesta

private struct CardView: View {
    @Bindable var model: WatchModel
    @State private var editing: WatchCardDTO.Row?

    private var card: WatchCardDTO { model.card }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack {
                    Text("HOYO \(card.hole.map(String.init) ?? "?")" + (card.par.map { " · PAR \($0)" } ?? "")).font(.wCaps)
                    Spacer()
                    if card.replaces { Text("REEMPLAZA").font(.wCaps).foregroundStyle(CSW.warning) }
                }
                .foregroundStyle(CSW.secondary)

                ForEach(card.rows) { row in
                    RowView(row: row, edit: { editing = row }, clear: { model.send(.clear(alias: row.alias)) })
                }

                ForEach(card.chips) { chip in
                    ChipView(chip: chip) { model.send(.removeChip(id: chip.id)) }
                }

                if let error = card.error {
                    Text(error).font(.wCaps).foregroundStyle(CSW.red)
                }
                if let notice = card.notice {
                    Text(notice).font(.wCaps).foregroundStyle(CSW.warning)
                }

                WatchPrimaryButton(title: "Anotar") { model.send(.apply) }
                    .disabled(!card.canApply)
                    .padding(.top, 4)
                if !card.canApply, card.rows.contains(where: { $0.state == .doubt }) || card.chips.contains(where: { $0.id.hasPrefix("d:") }) {
                    Text("Toca ✎ en lo dudoso para confirmarlo").font(.wCaps).foregroundStyle(CSW.warning).multilineTextAlignment(.center)
                }
                HStack {
                    Button("Dictar más") { model.startRecording() }
                    Spacer()
                    Button("Descartar") { model.send(.discard) }.foregroundStyle(CSW.secondary)
                }
                .font(.wCaps)
            }
            .padding(.horizontal, 4)
        }
        .sheet(item: $editing) { row in
            EditRowView(row: row, par: card.par ?? 4) { gross, putts in
                model.send(.edit(alias: row.alias, gross: gross, putts: putts))
                editing = nil
            }
        }
    }
}

private struct RowView: View {
    let row: WatchCardDTO.Row
    let edit: () -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color).font(.caption)
                Text(row.name).font(.wName).foregroundStyle(CSW.ink).lineLimit(1)
                Spacer(minLength: 2)
                if let gross = row.gross {
                    Text("\(gross)").font(.wScore).foregroundStyle(CSW.ink)
                    if let putts = row.putts { Text("·\(putts)p").font(.wBody).foregroundStyle(CSW.secondary) }
                } else {
                    Text("falta").font(.wBody).foregroundStyle(CSW.warning)
                }
                Button(action: edit) { Image(systemName: "pencil") }.buttonStyle(.plain).foregroundStyle(CSW.green)
                    .accessibilityLabel("Editar \(row.name)")
                if row.gross != nil {
                    Button(action: clear) { Image(systemName: "eraser") }.buttonStyle(.plain).foregroundStyle(CSW.red)
                        .accessibilityLabel("Quitar \(row.name)")
                }
            }
            if let note = row.note { Text(note).font(.wCaps).foregroundStyle(CSW.warning) }
        }
        .padding(8)
        .background(CSW.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(row.state == .doubt ? CSW.warning : CSW.line, lineWidth: row.state == .doubt ? 2 : 1))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch row.state { case .ok: "checkmark.circle.fill"; case .doubt: "questionmark.circle.fill"; case .missing: "minus.circle" }
    }
    private var color: Color {
        switch row.state { case .ok: CSW.green; case .doubt: CSW.warning; case .missing: CSW.secondary }
    }
}

private struct ChipView: View {
    let chip: WatchCardDTO.Chip
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(chip.text).font(.wCaps).foregroundStyle(CSW.unitFg).lineLimit(2)
            Spacer(minLength: 2)
            Button(action: remove) { Image(systemName: "eraser") }.buttonStyle(.plain).foregroundStyle(CSW.red)
                .accessibilityLabel("Quitar \(chip.text)")
        }
        .padding(8)
        .background(CSW.unitBg, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Editar una fila (lápiz)

private struct EditRowView: View {
    let row: WatchCardDTO.Row
    let par: Int
    let done: (Int, Int?) -> Void
    @State private var gross: Int
    @State private var putts: Int?

    init(row: WatchCardDTO.Row, par: Int, done: @escaping (Int, Int?) -> Void) {
        self.row = row
        self.par = par
        self.done = done
        _gross = State(initialValue: row.gross ?? par)
        _putts = State(initialValue: row.putts)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("\(row.name) · GOLPES").font(.wCaps).foregroundStyle(CSW.secondary)
                stepper(value: gross, minus: { gross = max(1, gross - 1) }, plus: { gross = min(15, gross + 1) })
                Text("PUTTS").font(.wCaps).foregroundStyle(CSW.secondary)
                stepper(text: putts.map(String.init) ?? "—",
                        minus: { putts = (putts ?? 1) <= 0 ? nil : (putts ?? 1) - 1 },
                        plus: { putts = min(gross, (putts ?? -1) + 1) })
                WatchPrimaryButton(title: "Listo") { done(gross, putts.map { min($0, gross) }) }
            }
            .padding(.horizontal, 6)
        }
    }

    private func stepper(value: Int, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        stepper(text: "\(value)", minus: minus, plus: plus)
    }

    private func stepper(text: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Button(action: minus) { Image(systemName: "minus") }.buttonStyle(.bordered)
            Text(text).font(.wScore).frame(minWidth: 40)
            Button(action: plus) { Image(systemName: "plus") }.buttonStyle(.bordered)
        }
    }
}

// MARK: - Resultado

private struct ResultView: View {
    @Bindable var model: WatchModel
    let applied: WatchCardDTO.Applied

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(CSW.green)
            Text(applied.message).font(.wName).foregroundStyle(CSW.ink).multilineTextAlignment(.center)
            if applied.canUndo { WatchPrimaryButton(title: "Deshacer", color: CSW.red) { model.send(.undo) } }
            Button("Listo") { model.send(.discard) }.font(.wCaps).foregroundStyle(CSW.secondary)
        }
        .padding(.horizontal, 6)
    }
}
