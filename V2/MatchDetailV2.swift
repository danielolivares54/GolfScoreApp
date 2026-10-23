//
//  MatchDetailV2.swift
//  Caddie Score — Vista v2, fase P1: detalle de UN match a pantalla completa
//
//  Muestra TODO lo que la v1 muestra y permite hacer en la pantalla de un match (individual o
//  pareja), más grande: encabezado con Tag, strokes, tabla de conceptos (F9, B9/B9×2, Match, Carry,
//  Ajuste 50, Unidades, Total con quién paga a quién), el estado del refresh de B9 y los botones
//  Carry / Ajuste 50 / Doble B9 (grandes), el selector de quién lleva el Carry en pareja, y los
//  enlaces al hoyo por hoyo, a la tarjeta Carry y al log de unidades (las pantallas de la v1).
//  Los datos y las acciones salen de MatchDetailDataV2.swift (mismas funciones que la v1).
//

import SwiftUI

struct MatchDetailV2: View {
    @ObservedObject var matchManager: MatchManager
    let row: MatchManager.ResultadoRowV2
    @Environment(\.dismiss) private var dismiss

    /// Filas de la tabla abiertas (por nombre de concepto).
    @State private var expanded: Set<String> = []
    /// Compañero elegido para el Carry de pareja.
    @State private var carryChoice: String?
    @State private var zoomSegment: String?
    @State private var showCarryCard = false
    @State private var unitLogSegment: String?

    private var target: UnitLogTarget { row.target }

    var body: some View {
        // Se recalcula en cada cambio del match (los botones escriben en matchManager).
        let resumen = matchManager.matchResumenV2(for: target)
        let refresh = matchManager.refreshStateV2(for: target)
        ZStack {
            CSV2.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, CSV2.s2)
                ScrollView {
                    VStack(spacing: CSV2.s2) {
                        if let resumen {
                            titleBlock(resumen)
                            strokesBlock(resumen)
                            // Igual que la v1: el refresh de B9 aparece cuando ya se juega el segundo nueve.
                            if matchManager.currentSegmentV2 == "B9" { refreshBlock(refresh) }
                            conceptsCard(resumen)
                            totalCard(resumen)
                            linksBlock(resumen, refresh: refresh)
                        } else {
                            Text("Este match ya no existe en la ronda.")
                                .font(.v2Body).foregroundStyle(CSV2.secondary).padding(CSV2.s3)
                        }
                    }
                    .padding(.horizontal, CSV2.s2).padding(.bottom, CSV2.s3)
                }
            }
        }
        .sheet(isPresented: Binding(get: { zoomSegment != nil }, set: { if !$0 { zoomSegment = nil } })) {
            MatchZoomView(matchManager: matchManager, target: target, initialSegment: zoomSegment ?? "F9")
        }
        .sheet(isPresented: $showCarryCard) { carryCardSheet }
        .sheet(isPresented: Binding(get: { unitLogSegment != nil }, set: { if !$0 { unitLogSegment = nil } })) {
            NavigationStack {
                UnitLogDetailView(title: matchManager.unitLogTitleV2(target),
                                  entries: matchManager.unitLogEntriesV2(target, segment: unitLogSegment))
            }
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text("Volver").font(.v2Body)
                }
                .foregroundStyle(CSV2.ink)
                .frame(minHeight: CSV2.minTap)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func titleBlock(_ resumen: MatchResumen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.system(size: 32, weight: .bold)).foregroundStyle(CSV2.ink)
                Spacer()
                // "Tag $50": el valor de la apuesta de este match (v1: Tag).
                Text("Tag $\(resumen.tag)").font(.v2Body).foregroundStyle(CSV2.secondary)
            }
            if let rivals = row.rivalsText {
                Text(rivals).font(.v2Body).foregroundStyle(CSV2.secondary)
            }
            if let bet = row.betText { Text(bet).font(.v2Body).foregroundStyle(CSV2.ink) }
            Text(conditions(resumen)).font(.v2Label).foregroundStyle(CSV2.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// v1: "Strokes 8 · Carry activo · Doble B9".
    private func conditions(_ resumen: MatchResumen) -> String {
        var parts = ["Strokes \(resumen.strokes)"]
        if resumen.carryActivo { parts.append("Carry activo") }
        if resumen.dobleB9 { parts.append("Doble B9") }
        return parts.joined(separator: " · ")
    }

    // MARK: Strokes (en palabras + la línea de la v1)

    private func strokesBlock(_ resumen: MatchResumen) -> some View {
        CardV2 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Strokes").font(.v2Caps).textCase(.uppercase).foregroundStyle(CSV2.secondary)
                if let receiver = row.strokesReceiver {
                    StrokeTextV2(receiver: receiver, amount: row.strokesAmount)
                        .font(.v2Body)
                } else {
                    Text("sin strokes").font(.v2Body).foregroundStyle(CSV2.secondary)
                }
                if let line = matchManager.strokesSummaryV2(for: target) {
                    Text(line)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CSV2.stroke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CSV2.s2)
        }
    }

    // MARK: Refresh de B9: Carry / Ajuste 50 / Doble B9 (botones grandes)

    private func refreshBlock(_ state: MatchManager.RefreshStateV2) -> some View {
        CardV2 {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Refresh de B9").font(.v2Caps).textCase(.uppercase)
                }
                .foregroundStyle(CSV2.secondary)

                Text(state.statusText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(state.f9Tied ? CSV2.secondary : CSV2.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    RefreshTileV2(title: "Carry", state: tileState(on: state.carryActive, tied: state.f9Tied),
                                  isOn: state.carryActive, isDisabled: state.f9Tied) {
                        matchManager.toggleCarryV2(for: target, requester: carryChoice)
                    }
                    RefreshTileV2(title: "Ajuste 50", state: tileState(on: state.adjust50Active, tied: state.f9Tied),
                                  isOn: state.adjust50Active, isDisabled: state.f9Tied) {
                        matchManager.toggleAdjust50V2(for: target)
                    }
                    RefreshTileV2(title: "Doble B9", state: tileState(on: state.doublePressActive, tied: state.f9Tied),
                                  isOn: state.doublePressActive, isDisabled: state.f9Tied) {
                        matchManager.toggleDoublePressV2(for: target)
                    }
                }

                // Solo en pareja hay más de un candidato (los dos compañeros del lado que perdió el F9).
                if state.candidates.count > 1 { carryPicker(state) }
            }
            .padding(CSV2.s2)
        }
    }

    private func tileState(on: Bool, tied: Bool) -> String {
        on ? "Activo" : (tied ? "No aplica" : "Apagado")
    }

    private func carryPicker(_ state: MatchManager.RefreshStateV2) -> some View {
        let selected = carryChoice ?? state.carryRequester ?? state.candidates.first
        return VStack(alignment: .leading, spacing: 8) {
            Text("¿Quién lleva el Carry?").font(.v2Label).foregroundStyle(CSV2.secondary)
            HStack(spacing: 10) {
                ForEach(state.candidates, id: \.self) { alias in
                    Button {
                        carryChoice = alias
                        // Si el Carry ya está activo, el cambio se aplica al momento (misma acción que activarlo).
                        if state.carryActive, case .pair(let laneId) = target {
                            matchManager.setPairCarryRequest(laneId: laneId, requesterAlias: alias)
                        }
                    } label: {
                        Text(alias).font(.system(size: 18, weight: .bold))
                            .foregroundStyle(alias == selected ? .white : CSV2.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background { RoundedRectangle(cornerRadius: CSV2.rCell).fill(alias == selected ? CSV2.ink : CSV2.background) }
                            .overlay(RoundedRectangle(cornerRadius: CSV2.rCell).stroke(CSV2.line))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Tabla de conceptos

    private func conceptsCard(_ resumen: MatchResumen) -> some View {
        CardV2 {
            VStack(spacing: 0) {
                ForEach(Array(resumen.filas.enumerated()), id: \.element.id) { index, fila in
                    if index > 0 { Rectangle().fill(CSV2.rowLine).frame(height: 1) }
                    conceptRow(fila)
                }
            }
        }
    }

    private func conceptRow(_ fila: ConceptoMatch) -> some View {
        let isOpen = expanded.contains(fila.nombre)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(fila.nombre) } else { expanded.insert(fila.nombre) }
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fila.nombre).font(.system(size: 20, weight: .bold)).foregroundStyle(CSV2.ink)
                        chipsLine(fila.chips)
                    }
                    Spacer(minLength: 8)
                    MoneyTextV2(amount: fila.monto, size: 22, weight: .semibold)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(CSV2.secondary)
                        .frame(width: 20)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fila.detalle, id: \.self) { line in
                        Text(line).font(.system(size: 15)).foregroundStyle(CSV2.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let link = zoomLink(for: fila) {
                        Button(action: link.action) {
                            Label(link.title, systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(CSV2.green)
                                .frame(minHeight: CSV2.minTap, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, CSV2.s2).padding(.vertical, 10)
    }

    /// Primer chip = vuelta (grande); los siguientes = presiones. El signo da el color.
    private func chipsLine(_ chips: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                Text(chip.replacingOccurrences(of: "-", with: "−"))
                    .font(.system(size: index == 0 ? 20 : 17, weight: index == 0 ? .heavy : .semibold).monospacedDigit())
                    .foregroundStyle(chipColor(chip))
            }
        }
    }

    private func chipColor(_ chip: String) -> Color {
        if chip.hasPrefix("+") { return CSV2.green }
        if chip.hasPrefix("-") || chip.hasPrefix("−") { return CSV2.red }
        return CSV2.secondary
    }

    /// Mismos destinos que la v1: F9/B9/Match → hoyo por hoyo; Carry → tarjeta Carry; Unidades → log.
    private func zoomLink(for fila: ConceptoMatch) -> (title: String, action: () -> Void)? {
        let name = fila.nombre.replacingOccurrences(of: " ×2", with: "")
        if name.hasPrefix("Carry") { return ("Ver tarjeta Carry B9 vs B9", { showCarryCard = true }) }
        if name.hasPrefix("Unidades") { return ("Ver unidades", { unitLogSegment = "ALL" }) }
        if name.hasPrefix("Ajuste") { return nil }
        let segment = name.hasPrefix("F9") ? "F9" : (name.hasPrefix("Match") ? matchManager.currentSegmentV2 : "B9")
        return ("Ver \(name) hoyo por hoyo", { zoomSegment = segment })
    }

    // MARK: Total

    private func totalCard(_ resumen: MatchResumen) -> some View {
        let total = resumen.total
        let payer: String = total > 0 ? "\(resumen.oponente) paga a \(resumen.jugador)"
            : total < 0 ? "\(resumen.jugador) paga a \(resumen.oponente)" : "Empate"
        return CardV2 {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total").font(.system(size: 20, weight: .bold)).foregroundStyle(CSV2.ink)
                    Text(payer).font(.v2Label).foregroundStyle(CSV2.secondary)
                }
                Spacer()
                MoneyTextV2(amount: total, size: 32, weight: .semibold)
            }
            .padding(CSV2.s2)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Enlaces a las pantallas de la v1

    private func linksBlock(_ resumen: MatchResumen, refresh: MatchManager.RefreshStateV2) -> some View {
        VStack(spacing: 10) {
            linkButton("Ver hoyo a hoyo", systemImage: "list.number") { zoomSegment = matchManager.currentSegmentV2 }
            linkButton("Ver unidades", systemImage: "plus.circle") { unitLogSegment = "ALL" }
            if refresh.carryActive {
                linkButton("Ver tarjeta Carry", systemImage: "rectangle.on.rectangle") { showCarryCard = true }
            }
        }
    }

    private func linkButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage).font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(CSV2.ink)
            .padding(.horizontal, CSV2.s2)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background { RoundedRectangle(cornerRadius: CSV2.rCard).fill(CSV2.surface) }
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).stroke(CSV2.line))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var carryCardSheet: some View {
        NavigationStack {
            Group {
                if let data = matchManager.carryCardData(target: target) {
                    let line = matchManager.walletSnapshot().lines.first { l in
                        switch target {
                        case .individual(let opp): return l.opponentAlias == opp
                        case .pair(let id): return l.laneId == id
                        }
                    }
                    CarryB9CardView(data: data, moneyB9: line?.b9Money ?? 0, moneyCarry: line?.carryMoney ?? 0)
                } else {
                    Text("El Carry no está activo en este match.").foregroundStyle(.secondary).padding()
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { showCarryCard = false } } }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Botón grande de refresh de B9 (Carry / Ajuste 50 / Doble B9): activo = fondo oscuro; gris si no aplica.
private struct RefreshTileV2: View {
    let title: String
    let state: String
    let isOn: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(.system(size: 20, weight: .bold)).minimumScaleFactor(0.8).lineLimit(1)
                Text(state).font(.v2Label)
            }
            .foregroundStyle(isOn ? Color.white : CSV2.ink)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background { RoundedRectangle(cornerRadius: CSV2.rCard).fill(isOn ? CSV2.ink : CSV2.surface) }
            .overlay(RoundedRectangle(cornerRadius: CSV2.rCard).stroke(isOn ? CSV2.ink : CSV2.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel("\(title), \(state)")
    }
}

#if DEBUG
#Preview("MatchDetailV2 · ROB (individual)") {
    let manager = MatchManager()
    manager.loadDemo18()
    let row = manager.resultadoRowsV2().first { $0.title == "ROB" }!
    return MatchDetailV2(matchManager: manager, row: row)
}

#Preview("MatchDetailV2 · pareja RIC – ANS") {
    let manager = MatchManager()
    manager.loadDemo18()
    let row = manager.resultadoRowsV2().first { $0.rivalsText == "RIC – ANS" }!
    return MatchDetailV2(matchManager: manager, row: row)
}
#endif
