import SwiftUI

// MARK: - Design tokens (mirrors ContentView)
private extension Color {
    static let cBg       = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let cSurface  = Color.white
    static let cBorder   = Color(red: 0.890, green: 0.875, blue: 0.824)
    static let cRowDiv   = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let cInk      = Color(red: 0.110, green: 0.137, blue: 0.129)
    static let cMuted    = Color(red: 0.431, green: 0.416, blue: 0.361)
    static let cFairway  = Color(red: 0.114, green: 0.627, blue: 0.310) // #1DA04F, verde de marca (logo)
    static let cBrick    = Color(red: 0.659, green: 0.275, blue: 0.184)
    static let cGold     = Color(red: 0.784, green: 0.608, blue: 0.235)
    static let cSegBg    = Color(red: 0.906, green: 0.886, blue: 0.824)
}

// MARK: - Internal types

private enum MoneyUnitsScope: String, CaseIterable, Identifiable {
    case individual = "Individual"
    case parejas = "Parejas"
    var id: String { rawValue }
}

private enum MoneyUnitTarget: Identifiable {
    case individual(String)
    case parejas(UUID)
    var id: String {
        switch self {
        case .individual(let alias): return "IND-\(alias)"
        case .parejas(let laneId): return "PAR-\(laneId.uuidString)"
        }
    }
}

private struct MoneyUnitRow: Identifiable {
    let id = UUID()
    let label: String
    let f9: Int; let b9: Int; let total: Int; let amount: Int
    let target: MoneyUnitTarget
}

// MARK: - Main view

struct MoneyTrackerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    @State private var scope: MoneyUnitsScope = .individual
    @State private var vueltaValueText: String = ""
    @State private var presionValueText: String = ""
    @State private var matchValueText: String = ""
    @State private var unitValueText: String = ""
    @State private var puttsUnitsText: String = ""
    @State private var puttsMode: PuttsBetMode = .hole18
    @State private var zoomTarget: MoneyUnitTarget?
    @State private var walletConfigTarget: MoneyUnitTarget?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        unitValueCard
                        resultadoPorRivalCard
                        walletCard
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Money Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.cInk)
                            .frame(width: 32, height: 32)
                            .background(Color.cSurface)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.cBorder, lineWidth: 1))
                    }
                }
            }
            .onAppear {
                if matchManager.vueltaValue <= 0 || matchManager.presionValue <= 0 || matchManager.matchValue <= 0 {
                    matchManager.setApuestaValues(vuelta: 50, presion: 50, match: 50)
                    if matchManager.unitValue <= 0 { matchManager.setUnitValue(25) }
                }
                vueltaValueText  = "\(matchManager.vueltaValue  > 0 ? matchManager.vueltaValue  : 50)"
                presionValueText = "\(matchManager.presionValue > 0 ? matchManager.presionValue : 50)"
                matchValueText   = "\(matchManager.matchValue   > 0 ? matchManager.matchValue   : 50)"
                unitValueText    = "\(matchManager.unitValue    > 0 ? matchManager.unitValue    : 25)"
                puttsUnitsText   = "\(matchManager.puttsBetUnits > 0 ? matchManager.puttsBetUnits : 2)"
                puttsMode = matchManager.puttsBetMode
            }
            .sheet(item: $zoomTarget) { target in
                NavigationStack {
                    UnitLogDetailView(title: zoomTitle(target), entries: detailEntries(target))
                }
            }
            .sheet(item: $walletConfigTarget) { target in
                NavigationStack { WalletMatchConfigView(matchManager: matchManager, target: target) }
            }
        }
    }

    // MARK: Unit value card

    private var unitValueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardLabel("VALOR UNIDAD")
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.cMuted)
                    TextField("25", text: $unitValueText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cInk)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cBg)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cBorder, lineWidth: 1))
                .cornerRadius(10)

                Button("Aplicar") { applyUnitValue() }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.cBg)
                    .frame(height: 44)
                    .padding(.horizontal, 18)
                    .background(Color.cFairway)
                    .cornerRadius(10)
            }

            HStack {
                HStack(spacing: 10) {
                    Text("Putts")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.cMuted)

                    HStack(spacing: 2) {
                        puttsSegBtn("F9",    .f9)
                        puttsSegBtn("B9",    .b9)
                        puttsSegBtn("H18",   .hole18)
                        puttsSegBtn("Vuelta", .byRound)
                    }
                    .padding(2)
                    .background(Color.cSegBg)
                    .cornerRadius(8)
                }
                Spacer()
                Text(puttsUnitsText.isEmpty ? "2" : puttsUnitsText)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.cInk)
            }
        }
        .padding(16)
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
    }

    // MARK: Resultado por rival

    private var resultadoPorRivalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardLabel("RESULTADO POR RIVAL")
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("RIVAL")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    colHeader("F9", 44)
                    colHeader("B9", 44)
                    colHeader("TOTAL", 50)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.cMuted)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.cBg)
                .overlay(Color.cBorder.frame(height: 1), alignment: .bottom)

                ForEach(Array(individualRows.enumerated()), id: \.offset) { idx, row in
                    Button { zoomTarget = row.target } label: {
                        HStack(spacing: 0) {
                            Text(row.label)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.cInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            monoCell(signed(row.f9), 44, color: unitColor(row.f9))
                            monoCell(signed(row.b9), 44, color: unitColor(row.b9))
                            monoCell(signed(row.total), 50, color: unitColor(row.total), bold: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Color.cSurface)
                    }
                    .buttonStyle(.plain)
                    if idx < individualRows.count - 1 {
                        Color.cRowDiv.frame(height: 1).padding(.horizontal, 14)
                    }
                }
            }
            .background(Color.cSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
            .clipped()
        }
    }

    // MARK: Wallet card

    private var walletCard: some View {
        let snap = wallet
        return VStack(alignment: .leading, spacing: 8) {
            cardLabel("WALLET (APUESTAS)")
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("RIVAL/PAREJA")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    colHeader("V", 30)
                    colHeader("P", 30)
                    colHeader("C", 30)
                    colHeader("M", 30)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.cMuted)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.cBg)
                .overlay(Color.cBorder.frame(height: 1), alignment: .bottom)

                ForEach(Array(snap.lines.enumerated()), id: \.offset) { idx, line in
                    let isPair = line.laneId != nil
                    Button { walletConfigTarget = walletTarget(for: line) } label: {
                        HStack(spacing: 0) {
                            Text(line.label)
                                .font(.system(size: isPair ? 12 : 12.5, weight: isPair ? .semibold : .regular))
                                .foregroundColor(.cInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            monoCell(moneyStr(line.vueltaMoney),  30, color: moneyColor(line.vueltaMoney),  bold: isPair)
                            monoCell(moneyStr(line.presionMoney), 30, color: moneyColor(line.presionMoney))
                            monoCell(line.carryActive ? moneyStr(line.carryMoney) : "–", 30, color: moneyColor(line.carryMoney))
                            monoCell(moneyStr(line.matchMoney),   30, color: moneyColor(line.matchMoney))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(isPair ? Color(red: 0.984, green: 0.969, blue: 0.914) : Color.cSurface)
                    }
                    .buttonStyle(.plain)
                    if idx < snap.lines.count - 1 {
                        Color.cRowDiv.frame(height: 1).padding(.horizontal, 14)
                    }
                }
            }
            .background(Color.cSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
            .clipped()
        }
    }

    // MARK: Shared sub-views

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.5)
            .foregroundColor(.cMuted)
    }

    private func colHeader(_ text: String, _ width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .center)
    }

    private func monoCell(_ text: String, _ width: CGFloat, color: Color = .cMuted, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: bold ? 14 : 13, weight: bold ? .bold : .regular, design: .monospaced))
            .foregroundColor(color)
            .frame(width: width, alignment: .center)
    }

    private func puttsSegBtn(_ label: String, _ mode: PuttsBetMode) -> some View {
        Button {
            puttsMode = mode
            applyPuttsValues()
        } label: {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(puttsMode == mode ? .cFairway : .cMuted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(puttsMode == mode ? Color.cSurface : Color.clear)
                .cornerRadius(6)
        }
    }

    // MARK: Data

    private var individualRows: [MoneyUnitRow] {
        let value = parsedUnitValue()
        return matchManager.players.map(\.alias).filter { $0 != matchManager.yoAlias }.map { opp in
            let f9  = matchManager.unitStakeForIndividual(opponentAlias: opp, segmentOverride: "F9")
            let b9  = matchManager.unitStakeForIndividual(opponentAlias: opp, segmentOverride: "B9")
            return MoneyUnitRow(label: "vs \(opp)", f9: f9, b9: b9, total: f9 + b9, amount: (f9 + b9) * value, target: .individual(opp))
        }
    }

    private var wallet: WalletSnapshot { matchManager.walletSnapshot() }

    // MARK: Helpers

    private func unitColor(_ v: Int) -> Color { v > 0 ? .cFairway : v < 0 ? .cBrick : .cMuted }
    private func moneyColor(_ v: Int) -> Color { v > 0 ? .cGold : v < 0 ? .cBrick : .cMuted }
    private func signed(_ v: Int)  -> String { v > 0 ? "+\(v)" : "\(v)" }
    private func moneyStr(_ v: Int) -> String { v == 0 ? "0" : (v > 0 ? "+\(v)" : "\(v)") }

    private func parsedUnitValue()   -> Int { max(0, Int(unitValueText)   ?? matchManager.unitValue) }
    private func parsedVueltaValue() -> Int { max(0, Int(vueltaValueText) ?? matchManager.vueltaValue) }
    private func parsedPresionValue()-> Int { max(0, Int(presionValueText) ?? matchManager.presionValue) }
    private func parsedMatchValue()  -> Int { max(0, Int(matchValueText)  ?? matchManager.matchValue) }
    private func parsedPuttsUnits()  -> Int { max(0, Int(puttsUnitsText)  ?? matchManager.puttsBetUnits) }

    private func applyUnitValue()   { matchManager.setUnitValue(parsedUnitValue()) }
    // Elegir el alcance (F9/B9/18) no abre la apuesta: encenderla se hace con el tag PUTTS del
    // Catálogo. Si está cerrada, solo se guarda el alcance.
    private func applyPuttsValues() {
        matchManager.setPuttsBet(mode: puttsMode, units: matchManager.puttsBetActive ? parsedPuttsUnits() : 0)
    }

    private func zoomTitle(_ target: MoneyUnitTarget) -> String {
        switch target {
        case .individual(let opp): return "\(matchManager.yoAlias) vs \(opp)"
        case .parejas(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return "Pareja" }
            return "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
        }
    }

    private func walletTarget(for line: WalletLine) -> MoneyUnitTarget? {
        if let opp    = line.opponentAlias { return .individual(opp) }
        if let laneId = line.laneId        { return .parejas(laneId) }
        return nil
    }

    private func detailEntries(_ target: MoneyUnitTarget) -> [UnitLogEntry] {
        switch target {
        case .individual(let opp):
            return matchManager.unitLogEntriesForZoom(segmentOverride: nil, includeIndividual: true, includePair: false)
                .filter { $0.scope == .individual && $0.vs == opp }
        case .parejas(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return [] }
            let player = lane.base.joined(separator: "+")
            let vs     = lane.opp.joined(separator: "+")
            return matchManager.unitLogEntriesForZoom(segmentOverride: nil, includeIndividual: false, includePair: true)
                .filter { $0.scope == .parejas && $0.player == player && $0.vs == vs }
        }
    }
}

// MARK: - Wallet config sheet (unchanged)

private struct WalletMatchConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager
    let target: MoneyUnitTarget

    var body: some View {
        Form {
            Section("Apuesta activa en este match") {
                Toggle("Vuelta",   isOn: binding(\.vuelta))
                Toggle("Presión",  isOn: binding(\.presion))
                Toggle("Carry B9", isOn: binding(\.carry))
                Toggle("Match",    isOn: binding(\.match))
                Toggle("Unidades", isOn: binding(\.units))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
    }

    private var title: String {
        switch target {
        case .individual(let opp): return "\(matchManager.yoAlias) vs \(opp)"
        case .parejas(let laneId):
            guard let lane = matchManager.lanes.first(where: { $0.id == laneId }) else { return "Pareja" }
            return "\(lane.base.joined(separator: "+")) vs \(lane.opp.joined(separator: "+"))"
        }
    }

    private func currentSwitches() -> MatchBetSwitches {
        switch target {
        case .individual(let opp):    return matchManager.betSwitchesForIndividual(opponentAlias: opp)
        case .parejas(let laneId):    return matchManager.betSwitchesForPair(laneId: laneId)
        }
    }

    private func saveSwitches(_ s: MatchBetSwitches) {
        switch target {
        case .individual(let opp):    matchManager.setBetSwitchesForIndividual(opponentAlias: opp, switches: s)
        case .parejas(let laneId):    matchManager.setBetSwitchesForPair(laneId: laneId, switches: s)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<MatchBetSwitches, Bool>) -> Binding<Bool> {
        Binding<Bool>(
            get: { currentSwitches()[keyPath: keyPath] },
            set: { v in var next = currentSwitches(); next[keyPath: keyPath] = v; saveSwitches(next) }
        )
    }
}

// MARK: - Unit log detail (Manual punto 14: hoyo, jugador, tipo, ganó/perdió)

struct UnitLogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let entries: [UnitLogEntry]

    // Hex fijos del Manual — no confundir con el sistema de colores de score (cFairwayL/cBrick).
    private let wonColor  = Color(red: 0x3F / 255.0, green: 0x6B / 255.0, blue: 0x4A / 255.0)  // #3F6B4A
    private let lostColor = Color(red: 0xA8 / 255.0, green: 0x46 / 255.0, blue: 0x2F / 255.0)  // #A8462F

    private var total: Int { entries.reduce(0) { $0 + $1.units } }
    // Oyes (OYES_RANK / OYESP_RANK) vs unidades de campo (birdie, S, etc.) — el Total es la suma de ambas.
    private var oyesTotal: Int { entries.filter { $0.type.hasPrefix("OYES") }.reduce(0) { $0 + $1.units } }
    private var campoTotal: Int { total - oyesTotal }
    private func signedLabel(_ v: Int) -> String { v > 0 ? "+\(v)" : "\(v)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if entries.isEmpty {
                    Text("Sin unidades registradas en este match.")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    // Total arriba — cuánto llevas ganado/perdido en unidades antes de entrar
                    // al detalle hoyo por hoyo.
                    HStack {
                        Text("Total").font(.system(size: 13, weight: .bold)).foregroundColor(.secondary)
                        Spacer()
                        Text(total > 0 ? "+\(total)" : "\(total)")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundColor(total > 0 ? wonColor : total < 0 ? lostColor : .secondary)
                    }
                    .padding(.bottom, 4)
                    // Desglose del total: unidades de campo + oyes = unidades hechas en este match.
                    HStack(spacing: 14) {
                        Text("Campo \(signedLabel(campoTotal))")
                        Text("Oyes \(signedLabel(oyesTotal))")
                        Spacer()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                    Divider()
                    ForEach(entries) { e in entryRow(e) }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
    }

    // Una sola línea por evento — quién la hizo, qué fue y contra quién, sin repetir en
    // columnas separadas (hoyo, tipo y rival ya caben en la misma oración).
    private func entryRow(_ e: UnitLogEntry) -> some View {
        let color = e.units > 0 ? wonColor : e.units < 0 ? lostColor : Color.secondary
        let verb = e.units > 0 ? "gana" : e.units < 0 ? "pierde" : "marca"
        let unitsLabel = e.units > 0 ? "+\(e.units)" : "\(e.units)"
        let typeLabel = e.detail ?? e.type
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("H\(e.hole)")
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .leading)
            HStack(spacing: 0) {
                Text("\(e.player) ").fontWeight(.bold)
                Text("\(verb) unidad (\(unitsLabel)) · \(typeLabel)\(e.vs.map { " vs \($0)" } ?? "")")
            }
            .font(.caption)
            .foregroundColor(color)
        }
    }
}

// MARK: - Resumen de match (Opción A · Tabla)

// Vista "Resumen de match" (Opción A · Tabla) — ver Caddie_MatchResumen_spec.
// Esta vista NO calcula nada: solo muestra valores ya calculados (MatchResumen).

// MARK: - Modelo (solo datos, sin cálculo)

struct ConceptoMatch: Identifiable {
    let id = UUID()
    var nombre: String          // "F9", "B9", "Match", "Carry", "Unidades"
    var chips: [String]         // ej. ["5","3","1"]
    var monto: Int              // pesos, ya calculado (+ gana jugador, − pierde)
    var detalle: [String]       // líneas del detalle al tocar
}

struct MatchResumen {
    var jugador: String
    var oponente: String
    var strokes: Int
    var tag: Int
    var carryActivo: Bool
    var dobleB9: Bool
    var f9: ConceptoMatch
    var b9: ConceptoMatch
    var match: ConceptoMatch
    var carry: ConceptoMatch
    var unidades: ConceptoMatch
    // Fila extra solo si Ajuste 50 está activo (no está en el spec original) — su dinero ya
    // forma parte del total de la billetera, así que se muestra para que la suma cuadre.
    var ajuste: ConceptoMatch? = nil

    var filas: [ConceptoMatch] {
        var b = b9
        b.nombre = dobleB9 ? "B9 ×2" : "B9"
        var r = [f9, b, match]
        if carryActivo { r.append(carry) }
        if let ajuste { r.append(ajuste) }
        r.append(unidades)
        return r
    }
    var total: Int { filas.reduce(0) { $0 + $1.monto } }
}

// MARK: - Helpers

private func formatoMonto(_ n: Int) -> String {
    let s = n > 0 ? "+" : (n < 0 ? "−" : "")
    return "\(s)$\(abs(n).formatted(.number.locale(Locale(identifier: "es_MX"))))"
}
private func colorMonto(_ n: Int) -> Color {
    n > 0 ? .green : (n < 0 ? .red : .secondary)
}

// MARK: - Vista

struct MatchResumenView: View {
    let resumen: MatchResumen
    // Zoom al concepto (F9, B9, Match, Carry, Unidades) — recibe el nombre de la fila. nil = sin botón.
    var onZoom: ((String) -> Void)? = nil
    @State private var abiertos: Set<UUID> = []

    private var condiciones: String {
        var p = ["Strokes \(resumen.strokes)"]
        if resumen.carryActivo { p.append("Carry activo") }
        if resumen.dobleB9 { p.append("Doble B9") }
        return p.joined(separator: " · ")
    }
    private var quienPaga: String {
        let t = resumen.total
        if t > 0 { return "\(resumen.oponente) paga a \(resumen.jugador)" }
        if t < 0 { return "\(resumen.jugador) paga a \(resumen.oponente)" }
        return "Empate"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Encabezado
            HStack {
                Text("\(resumen.jugador) vs \(resumen.oponente)")
                    .font(.headline)
                Spacer()
                Text("Tag $\(resumen.tag)")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color.accentColor)
            }
            Text(condiciones)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2).padding(.bottom, 10)

            // Títulos de columnas
            HStack {
                Text("Concepto").frame(width: 80, alignment: .leading)
                Text("Resultado")
                Spacer()
                Text("$")
                Color.clear.frame(width: 20)
            }
            .font(.caption2).foregroundStyle(.tertiary)
            .padding(.bottom, 4)
            Divider()

            // Filas
            ForEach(resumen.filas) { fila in
                filaView(fila)
                Divider()
            }

            // Total
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total").font(.subheadline.weight(.semibold))
                    Text(quienPaga).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatoMonto(resumen.total))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(colorMonto(resumen.total))
                Color.clear.frame(width: 20)
            }
            .padding(.top, 10)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func filaView(_ fila: ConceptoMatch) -> some View {
        let abierto = abiertos.contains(fila.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(fila.nombre).frame(width: 80, alignment: .leading)
                HStack(spacing: 4) {
                    ForEach(Array(fila.chips.enumerated()), id: \.offset) { _, c in
                        Text(c)
                            .font(.footnote.monospacedDigit())
                            .frame(minWidth: 22)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                Spacer()
                Text(formatoMonto(fila.monto))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(colorMonto(fila.monto))
                Image(systemName: abierto ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
            }
            .font(.subheadline)

            if abierto {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(fila.detalle, id: \.self) { Text($0) }
                    if let onZoom {
                        Button {
                            onZoom(fila.nombre)
                        } label: {
                            Label(fila.nombre == "Carry" ? "Ver tarjeta Carry B9 vs B9" : "Ver \(fila.nombre.replacingOccurrences(of: " ×2", with: "")) hoyo por hoyo", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 4)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if abierto { abiertos.remove(fila.id) } else { abiertos.insert(fila.id) }
            }
        }
    }
}

// MARK: - Preview con datos de ejemplo

extension MatchResumen {
    static let ejemplo = MatchResumen(
        jugador: "Dan", oponente: "Fer", strokes: 3, tag: 100,
        carryActivo: true, dobleB9: true,
        f9: .init(nombre: "F9", chips: ["5","3","1"], monto: 300, detalle: ["Presiones F9: 5 · 3 · 1"]),
        b9: .init(nombre: "B9", chips: ["4","2"], monto: -200, detalle: ["Presiones B9: 4 · 2"]),
        match: .init(nombre: "Match", chips: ["9"], monto: 100, detalle: ["Match 9"]),
        carry: .init(nombre: "Carry", chips: ["2"], monto: 200, detalle: ["Carry de ronda anterior"]),
        unidades: .init(nombre: "Unidades", chips: ["3"], monto: -100,
                        detalle: ["Hoyo 4 · Dan · Birdie", "Hoyo 7 · Fer · Oyes", "Hoyo 12 · Dan · Oyes"])
    )
}

#Preview("Doble y carry activos") {
    MatchResumenView(resumen: .ejemplo).padding()
}

#Preview("Sin doble, sin carry") {
    var r = MatchResumen.ejemplo
    r.dobleB9 = false
    r.carryActivo = false
    return MatchResumenView(resumen: r).padding()
}

// MARK: - Tarjeta Carry B9 (B9 normal vs B9 con el stroke del Carry)

struct CarryB9CardView: View {
    let data: CarryCardData
    let moneyB9: Int
    let moneyCarry: Int

    private let gold = Color.cGold

    private func signed(_ v: Int) -> String { v == 0 ? "E" : (v > 0 ? "+\(v)" : "\(v)") }
    private func presLabel(_ p: [Int]) -> String { p.isEmpty ? "—" : p.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: " ") }
    private func money(_ n: Int) -> String { n == 0 ? "$0" : (n > 0 ? "+$\(n)" : "−$\(abs(n))") }
    private func fmt(_ v: Double) -> String { abs(v - v.rounded()) < 0.01 ? "\(Int(v.rounded()))" : String(format: "%.1f", v) }

    // Orden de juego de los hoyos de la tarjeta, para atenuar los hoyos previos al cambio.
    private var changeIndex: Int? {
        guard let h = data.changeHole else { return nil }
        return data.rows.firstIndex { $0.hole == h }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                ventajaCard
                resultadoCard
                tabla
                leyenda
            }
            .padding(14)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Encabezado
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Carry B9").font(.title3.weight(.bold))
            Text("\(data.title) · pide el carry: \(data.requester)")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: Ventaja — lo que hace distinto al carry vs B9
    private var ventajaCard: some View {
        let delta = data.carryStrokes - data.normalStrokes
        return VStack(alignment: .leading, spacing: 6) {
            Text("VENTAJA").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Strokes en B9").font(.subheadline)
                Spacer()
                Text("\(fmt(data.normalStrokes))").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text("\(fmt(data.carryStrokes))").font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(gold)
                if abs(delta) > 0.001 {
                    Text(delta > 0 ? "+\(fmt(delta))" : "\(fmt(delta))")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(gold.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(gold)
                }
            }
            if let h = data.changeHole, let r = data.changeRank {
                let added = delta > 0
                let who = (added ? data.receiverCarry : data.receiverNormal) ?? ""
                Text(added
                     ? "\(who) recibe un stroke más: cae en H\(h) (ventaja \(r) de B9). Antes de ese hoyo las dos tarjetas son iguales."
                     : "Se quita un stroke a \(who): el de H\(h) (ventaja \(r) de B9). Antes de ese hoyo las dos tarjetas son iguales.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("El carry no cambia los strokes de B9.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Resultado B9 vs Carry
    private var resultadoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RESULTADO").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            HStack {
                Spacer().frame(width: 74)
                Text("B9").font(.caption.weight(.bold)).frame(maxWidth: .infinity)
                Text("Carry").font(.caption.weight(.bold)).foregroundStyle(gold).frame(maxWidth: .infinity)
            }
            compareRow("Vuelta", signed(data.vueltaNormal), signed(data.vueltaCarry), changed: data.vueltaNormal != data.vueltaCarry)
            compareRow("Presiones", presLabel(data.presNormal), presLabel(data.presCarry), changed: data.presNormal != data.presCarry)
            compareRow("Dinero", money(moneyB9), money(moneyCarry), changed: moneyB9 != moneyCarry)
            if !data.hasDifference {
                Text("El stroke extra no cambió ningún hoyo: el Carry da igual que B9 (se cobra aparte, como otra apuesta).")
                    .font(.caption).foregroundStyle(gold)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func compareRow(_ label: String, _ a: String, _ b: String, changed: Bool) -> some View {
        HStack {
            Text(label).font(.subheadline).frame(width: 74, alignment: .leading)
            Text(a).font(.subheadline.weight(.semibold).monospacedDigit()).frame(maxWidth: .infinity)
            Text(b).font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(changed ? gold : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(changed ? gold.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Tabla hoyo por hoyo
    private var tabla: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("H").frame(width: 30, alignment: .leading)
                Text("Golpes").frame(maxWidth: .infinity, alignment: .leading)
                Text("B9").frame(width: 36)
                Text("Carry").frame(width: 40).foregroundStyle(gold)
                Text("Acum B9").frame(width: 56)
                Text("Acum C").frame(width: 56).foregroundStyle(gold)
            }
            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()
            ForEach(Array(data.rows.enumerated()), id: \.element.id) { idx, row in
                let before = (changeIndex.map { idx < $0 } ?? false)
                filaTabla(row).opacity(before ? 0.45 : 1)
                Divider()
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func filaTabla(_ r: CarryCardRow) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(r.hole)").font(.subheadline.weight(.bold).monospacedDigit())
                Text("H\(r.si)").font(.system(size: 9)).foregroundStyle(gold)
            }
            .frame(width: 30, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(r.players) { p in playerCell(p) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(signed(r.resultNormal)).font(.subheadline.monospacedDigit())
                .foregroundStyle(color(r.resultNormal)).frame(width: 36)
            Text(signed(r.resultCarry)).font(.subheadline.weight(r.diverges ? .bold : .regular).monospacedDigit())
                .foregroundStyle(r.diverges ? gold : color(r.resultCarry)).frame(width: 40)
            VStack(spacing: 0) {
                Text(signed(r.accumNormal)).font(.subheadline.monospacedDigit()).foregroundStyle(color(r.accumNormal))
                if !r.presNormal.isEmpty { Text(presLabel(r.presNormal)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary) }
            }.frame(width: 56)
            VStack(spacing: 0) {
                Text(signed(r.accumCarry)).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(gold)
                if !r.presCarry.isEmpty { Text(presLabel(r.presCarry)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(gold) }
            }.frame(width: 56)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background((r.diverges || abs(r.strokeChange) > 0.001) ? gold.opacity(0.14) : .clear)
    }

    private func playerCell(_ p: CarryCardPlayer) -> some View {
        let added = p.strokesCarry > p.strokesNormal + 0.001
        let removed = p.strokesCarry < p.strokesNormal - 0.001
        return VStack(spacing: 0) {
            Text(p.gross > 0 ? "\(p.gross)" : "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(p.isMySide ? Color.green : Color.red)
            Text(p.alias).font(.system(size: 8)).foregroundStyle(.secondary)
            if added {
                Text("●+").font(.system(size: 10, weight: .bold)).foregroundStyle(gold)
            } else if removed {
                Text("●−").font(.system(size: 10, weight: .bold)).foregroundStyle(gold).strikethrough()
            } else if p.strokesNormal > 0.001 {
                Text("●").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text(" ").font(.system(size: 10))
            }
        }
        .frame(minWidth: 28)
    }

    private func color(_ v: Int) -> Color { v > 0 ? .green : (v < 0 ? .red : .secondary) }

    private var leyenda: some View {
        Text("● stroke de B9 · ●+ stroke que agrega el carry · ●− stroke que quita el carry. Los hoyos en dorado son donde el carry cambia el resultado; los hoyos atenuados son anteriores al cambio y las dos tarjetas son iguales.")
            .font(.caption2).foregroundStyle(.secondary)
    }
}
