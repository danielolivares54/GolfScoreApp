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
                } else if let answer = model.answer {
                    AnswerView(model: model, answer: answer)
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
                    Text(ctx.course.isEmpty ? "ESPERANDO" : ctx.course.uppercased()).font(.wCaps).foregroundStyle(CSW.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    Text("HOYO \(ctx.hole)").font(.system(.title2, weight: .heavy).monospacedDigit()).foregroundStyle(CSW.ink)
                    Text("PAR \(ctx.par)" + (ctx.teeDistance.map { " · \($0) yd" } ?? "")).font(.wCaps).foregroundStyle(CSW.secondary)
                    if ctx.teeDistance == nil {   // sin tee elegido no hay distancia: se dice dónde elegirlo
                        Text("Elige tu tee en el iPhone").font(.wCaps).foregroundStyle(CSW.warning).multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Esperando el hoyo \(ctx.hole), par \(ctx.par)" + (ctx.teeDistance.map { ", \($0) de distancia" } ?? ""))
            } else {
                Text("Abre Caddie Score en el iPhone").font(.wBody).foregroundStyle(CSW.secondary).multilineTextAlignment(.center)
            }
            WatchPrimaryButton(title: "Dictar") { model.startRecording() }
                .disabled(model.context == nil || !model.reachable)
            if model.context != nil, !model.reachable {
                Text("Abre Caddie Score en el iPhone").font(.wCaps).foregroundStyle(CSW.warning).multilineTextAlignment(.center)
            }
            if let message = model.card.error ?? failure {
                Text(message).font(.wCaps).foregroundStyle(CSW.red).multilineTextAlignment(.center)
                if model.card.error != nil, !model.card.heard.isEmpty {   // lo oído no se pierde: se ve para decidir
                    Text("Oí: «\(model.card.heard)»").font(.wCaps).foregroundStyle(CSW.secondary).multilineTextAlignment(.center)
                }
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

// MARK: - Respuesta a una pregunta

private struct AnswerView: View {
    @Bindable var model: WatchModel
    let answer: WatchAnswerDTO

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                AnswerLines(answer: answer)
                HStack {
                    Button("Dictar") { model.dismissAnswer(); model.startRecording() }
                    Spacer()
                    Button("Listo") { model.dismissAnswer() }.foregroundStyle(CSW.secondary)
                }
                .font(.wCaps)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }
}

/// Título, texto y líneas de una respuesta (la usan la respuesta a una pregunta y el update después de anotar).
private struct AnswerLines: View {
    let answer: WatchAnswerDTO

    var body: some View {
        VStack(spacing: 6) {
            if !answer.title.isEmpty {
                Text(answer.title.uppercased()).font(.wCaps).foregroundStyle(CSW.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let text = answer.text {
                Text(text).font(.wBody).foregroundStyle(CSW.ink).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(answer.lines.enumerated()), id: \.offset) { _, line in
                if line.header {
                    HStack {
                        Text(line.label.uppercased()).font(.wCaps).foregroundStyle(CSW.secondary)
                        Spacer(minLength: 2)
                        if !line.value.isEmpty {
                            Text(line.value).font(.wCaps).foregroundStyle(line.tone > 0 ? CSW.green : line.tone < 0 ? CSW.red : CSW.ink)
                        }
                    }.padding(.top, 4)
                } else {
                    LineView(line: line)
                }
            }
        }
    }
}

private struct LineView: View {
    let line: WatchAnswerDTO.Line

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(line.label).font(.wName).foregroundStyle(CSW.ink)
                Spacer(minLength: 2)
                if !line.value.isEmpty {
                    Text(line.value).font(.wScore).foregroundStyle(color)
                }
            }
            if let detail = line.detail { Text(detail).font(.wCaps).foregroundStyle(CSW.secondary) }
        }
        .padding(8)
        .background(CSW.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CSW.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var color: Color { line.tone > 0 ? CSW.green : line.tone < 0 ? CSW.red : CSW.ink }
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
                    Text("HOYO \(card.hole.map(String.init) ?? "?")" + (card.par.map { " · PAR \($0)" } ?? "")
                         + (model.context?.teeDistance.map { " · \($0) yd" } ?? "")).font(.wCaps)
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
                if case .failed(let text) = model.phase {   // antes un fallo al mandar una orden no se veía y parecía "trabado"
                    Text(text).font(.wCaps).foregroundStyle(CSW.red).multilineTextAlignment(.center)
                }
                if let notice = card.notice {
                    Text(notice).font(.wCaps).foregroundStyle(CSW.warning)
                }
                // Siempre se ve lo que se oyó (mientras el slang de golf no está entrenado, oyes, notas y unidades pueden no reconocerse): nada se pierde en silencio.
                if !card.heard.isEmpty {
                    Text("Oí: «\(card.heard)»").font(.wCaps).foregroundStyle(CSW.secondary).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

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
        // Anotar siempre a la vista: con 5 jugadores y fichas, el botón quedaba abajo del scroll.
        .safeAreaInset(edge: .bottom) {
            WatchPrimaryButton(title: "Anotar") { model.send(.apply) }
                .disabled(!card.canApply)
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

    // Pensada para la caja de 42 mm: el score (strokes) es lo grande; putts en chico; sin botones fijos por fila.
    // Tocar la fila edita; mantener presionada quita lo dictado (lo ya anotado no se borra desde un borrador).
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(color).font(.system(size: 10))
                Text(row.name).font(.wName).foregroundStyle(CSW.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if let gross = row.gross {
                    if let putts = row.putts { Text("\(putts)p").font(.wCaps).foregroundStyle(CSW.secondary) }
                    Text("\(gross)").font(.wScore).foregroundStyle(row.state == .saved ? CSW.secondary : CSW.ink)
                } else {
                    Text("falta").font(.wCaps).foregroundStyle(CSW.warning)
                }
            }
            if let note = row.note { Text(note).font(.wCaps).foregroundStyle(CSW.warning) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(CSW.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(row.state == .doubt ? CSW.warning : CSW.line, lineWidth: row.state == .doubt ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: edit)
        .contextMenu {
            if row.gross != nil, row.state != .saved {
                Button("Quitar \(row.name)", systemImage: "eraser", role: .destructive, action: clear)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Toca para editar")
    }

    private var icon: String {
        switch row.state { case .ok: "checkmark.circle.fill"; case .doubt: "questionmark.circle.fill"; case .missing: "minus.circle"; case .saved: "checkmark.circle" }
    }
    private var color: Color {
        switch row.state { case .ok: CSW.green; case .doubt: CSW.warning; case .missing, .saved: CSW.secondary }
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

/// Después de anotar: el update de los matches con ese hoyo (números). Ampliar = los hoyos anteriores. Si no se mira en un minuto
/// (o la pantalla se apaga) se cierra sola y el reloj queda listo para el siguiente dictado; lo anotado ya está guardado.
private struct ResultView: View {
    @Bindable var model: WatchModel
    let applied: WatchCardDTO.Applied
    @Environment(\.scenePhase) private var scenePhase
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(applied.message).font(.wName).foregroundStyle(CSW.green).frame(maxWidth: .infinity, alignment: .leading)
                if let answer = model.answer { AnswerLines(answer: answer) }
                HStack {
                    if !expanded {
                        Button("Ampliar") { expanded = true; model.send(.explain) }
                    }
                    Spacer()
                    Button("Dictar") { model.startRecording() }
                }
                .font(.wCaps)
                .padding(.top, 4)
                if applied.canUndo {
                    Button("Deshacer") { model.send(.undo) }.font(.wCaps).foregroundStyle(CSW.red)
                }
            }
            .padding(.horizontal, 4)
        }
        .task(id: applied.hole) {
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled { model.send(.discard) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.send(.discard) }
        }
    }
}

#Preview("Tarjeta · 5 jugadores") {
    let model = WatchModel()
    model.card = WatchCardDTO(
        hole: 16, par: 3, replaces: false,
        rows: [
            .init(alias: "DAN", name: "Daniel", gross: 3, putts: 2, state: .ok, note: nil),
            .init(alias: "ROB", name: "Roberto", gross: 4, putts: nil, state: .ok, note: nil),
            .init(alias: "ANS", name: "Anselmo", gross: 5, putts: 3, state: .doubt, note: "¿5 o 6?"),
            .init(alias: "RIC", name: "Ricardo", gross: nil, putts: nil, state: .missing, note: nil),
            .init(alias: "FER", name: "Fernando", gross: 2, putts: 1, state: .saved, note: nil)
        ],
        chips: [.init(id: "o", kind: .oyes, text: "Oyes 1 FER · 2 DAN"), .init(id: "u:DAN:sandy", kind: .unit, text: "Sandy DAN")],
        heard: "", canApply: false, error: nil, processing: false, applied: nil, revision: 1)
    return ContentView(model: model)
}
