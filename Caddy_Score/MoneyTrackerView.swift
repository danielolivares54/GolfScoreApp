import SwiftUI

// MARK: - Design tokens (mirrors ContentView)
private extension Color {
    static let cBg       = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let cSurface  = Color.white
    static let cBorder   = Color(red: 0.890, green: 0.875, blue: 0.824)
    static let cRowDiv   = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let cInk      = Color(red: 0.110, green: 0.137, blue: 0.129)
    static let cMuted    = Color(red: 0.431, green: 0.416, blue: 0.361)
    static let cFairway  = Color(red: 0.122, green: 0.239, blue: 0.169)
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
    private func applyPuttsValues() { matchManager.setPuttsBet(mode: puttsMode, units: parsedPuttsUnits()) }

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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    detailHeader("H", 30); detailHeader("Jugador", 76); detailHeader("Tipo", 88)
                    detailHeader("VS", 78); detailHeader("u", 32);       detailHeader("Detalle", 140)
                }
                if entries.isEmpty {
                    Text("Sin unidades registradas en este match.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                ForEach(entries) { e in
                    HStack(spacing: 8) {
                        detailData("\(e.hole)", 30);  detailData(e.player, 76); detailData(e.type, 88)
                        detailData(e.vs ?? "—", 78)
                        Text(e.units > 0 ? "+\(e.units)" : "\(e.units)")
                            .font(.caption.monospacedDigit().bold())
                            .foregroundColor(e.units > 0 ? wonColor : e.units < 0 ? lostColor : .secondary)
                            .frame(width: 32, alignment: .leading)
                        detailData(e.detail ?? "—", 140)
                    }
                }
            }.padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
    }

    private func detailHeader(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(.caption2.bold()).foregroundColor(.secondary).frame(width: width, alignment: .leading)
    }
    private func detailData(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(.caption.monospacedDigit()).frame(width: width, alignment: .leading)
    }
}
