import SwiftUI

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
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Apuestas").font(.caption.bold()).frame(width: 64, alignment: .leading)
                tinyValueField("V", text: $vueltaValueText, width: 52)
                tinyValueField("P", text: $presionValueText, width: 52)
                tinyValueField("M", text: $matchValueText, width: 52)
                Button("Aplicar") { applyApuestaValues() }.buttonStyle(.borderedProminent)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Valor unidad").font(.caption.bold()).frame(width: 88, alignment: .leading)
                tinyValueField("U", text: $unitValueText, width: 52)
                Button("Aplicar") { applyUnitValue() }.buttonStyle(.borderedProminent)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Putts").font(.caption.bold()).frame(width: 64, alignment: .leading)
                Picker("Putts", selection: $puttsMode) {
                    Text("H18").tag(PuttsBetMode.hole18)
                    Text("Vuelta").tag(PuttsBetMode.byRound)
                }.pickerStyle(.segmented).frame(maxWidth: 180)
                tinyValueField("u", text: $puttsUnitsText, width: 52)
                Button("Aplicar") { applyPuttsValues() }.buttonStyle(.bordered)
                Spacer()
            }
            Picker("Scope", selection: $scope) {
                ForEach(MoneyUnitsScope.allCases) { item in Text(item.rawValue).tag(item) }
            }.pickerStyle(.segmented)

            if rows.isEmpty {
                Spacer()
                Text("Sin datos de unidades para mostrar.").font(.caption).foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            moneyHeaderCell("Rival/Pareja", 160)
                            moneyHeaderCell("F9", 40); moneyHeaderCell("B9", 40); moneyHeaderCell("Tot", 40)
                            moneyHeaderCell("$", 58); moneyHeaderCell("Zoom", 42)
                        }
                        ForEach(rows) { row in
                            HStack(spacing: 8) {
                                moneyDataCell(row.label, 160)
                                moneyDataCell(signed(row.f9), 40); moneyDataCell(signed(row.b9), 40)
                                moneyDataCell(signed(row.total), 40); moneyDataCell(signed(row.amount), 58)
                                Button(action: { zoomTarget = row.target }) {
                                    Image(systemName: "magnifyingglass").font(.caption)
                                }.buttonStyle(.plain).frame(width: 42, alignment: .leading)
                            }
                        }
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Wallet (Apuestas)").font(.caption.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            moneyHeaderCell("Rival/Pareja", 160)
                            moneyHeaderCell("V", 28); moneyHeaderCell("P", 28); moneyHeaderCell("C", 28)
                            moneyHeaderCell("M", 28); moneyHeaderCell("U", 28)
                            moneyHeaderCell("ON", 62); moneyHeaderCell("Cfg", 38); moneyHeaderCell("Total", 70)
                        }
                        ForEach(wallet.lines) { line in
                            HStack(spacing: 8) {
                                moneyDataCell(line.label, 160)
                                moneyDataCell(signed(line.vueltaMoney), 28); moneyDataCell(signed(line.presionMoney), 28)
                                moneyDataCell(signed(line.carryMoney), 28); moneyDataCell(signed(line.matchMoney), 28)
                                moneyDataCell(signed(line.unitsMoney), 28)
                                moneyDataCell(line.activationSummary, 62)
                                Button(action: { walletConfigTarget = walletTarget(for: line) }) {
                                    Image(systemName: "slider.horizontal.3").font(.caption)
                                }.buttonStyle(.plain).frame(width: 38, alignment: .leading)
                                moneyDataCell(signed(line.totalMoney), 70)
                            }
                        }
                        HStack(spacing: 8) {
                            moneyHeaderCell("TOTAL", 160)
                            moneyHeaderCell("", 28); moneyHeaderCell("", 28); moneyHeaderCell("", 28)
                            moneyHeaderCell("", 28); moneyHeaderCell("", 28)
                            moneyHeaderCell("", 62); moneyHeaderCell("", 38)
                            moneyHeaderCell(signed(wallet.totalMoney), 70)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle("Money Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
        }
        .onAppear {
            if matchManager.vueltaValue <= 0 || matchManager.presionValue <= 0 || matchManager.matchValue <= 0 {
                matchManager.setApuestaValues(vuelta: 50, presion: 50, match: 50)
                if matchManager.unitValue <= 0 { matchManager.setUnitValue(25) }
            }
            vueltaValueText = "\(matchManager.vueltaValue > 0 ? matchManager.vueltaValue : 50)"
            presionValueText = "\(matchManager.presionValue > 0 ? matchManager.presionValue : 50)"
            matchValueText = "\(matchManager.matchValue > 0 ? matchManager.matchValue : 50)"
            unitValueText = "\(matchManager.unitValue > 0 ? matchManager.unitValue : 25)"
            puttsUnitsText = "\(matchManager.puttsBetUnits > 0 ? matchManager.puttsBetUnits : 2)"
            puttsMode = matchManager.puttsBetMode
        }
        .sheet(item: $zoomTarget) { target in
            NavigationView {
                UnitLogDetailView(title: zoomTitle(target), entries: detailEntries(target))
            }
        }
        .sheet(item: $walletConfigTarget) { target in
            NavigationView { WalletMatchConfigView(matchManager: matchManager, target: target) }
        }
    }

    private var rows: [MoneyUnitRow] {
        switch scope {
        case .individual:
            let value = parsedUnitValue()
            return matchManager.players.map(\.alias).filter { $0 != matchManager.yoAlias }.map { opp in
                let f9 = matchManager.unitStakeForIndividual(opponentAlias: opp, segmentOverride: "F9")
                let b9 = matchManager.unitStakeForIndividual(opponentAlias: opp, segmentOverride: "B9")
                let total = f9 + b9
                return MoneyUnitRow(label: "vs \(opp)", f9: f9, b9: b9, total: total, amount: total * value, target: .individual(opp))
            }
        case .parejas:
            let value = parsedUnitValue()
            return matchManager.lanes.prefix(3).map { lane in
                let f9 = matchManager.unitStakeForPair(laneId: lane.id, segmentOverride: "F9")
                let b9 = matchManager.unitStakeForPair(laneId: lane.id, segmentOverride: "B9")
                let total = f9 + b9
                return MoneyUnitRow(
                    label: "\(lane.base.joined(separator: "+"))/\(lane.opp.joined(separator: "+"))",
                    f9: f9, b9: b9, total: total, amount: total * value, target: .parejas(lane.id)
                )
            }
        }
    }

    private var wallet: WalletSnapshot { matchManager.walletSnapshot() }
    private func parsedUnitValue() -> Int { max(0, Int(unitValueText) ?? matchManager.unitValue) }
    private func parsedVueltaValue() -> Int { max(0, Int(vueltaValueText) ?? matchManager.vueltaValue) }
    private func parsedPresionValue() -> Int { max(0, Int(presionValueText) ?? matchManager.presionValue) }
    private func parsedMatchValue() -> Int { max(0, Int(matchValueText) ?? matchManager.matchValue) }
    private func parsedPuttsUnits() -> Int { max(0, Int(puttsUnitsText) ?? matchManager.puttsBetUnits) }
    private func applyApuestaValues() { matchManager.setApuestaValues(vuelta: parsedVueltaValue(), presion: parsedPresionValue(), match: parsedMatchValue()) }
    private func applyUnitValue() { matchManager.setUnitValue(parsedUnitValue()) }
    private func applyPuttsValues() { matchManager.setPuttsBet(mode: puttsMode, units: parsedPuttsUnits()) }
    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    private func tinyValueField(_ placeholder: String, text: Binding<String>, width: CGFloat) -> some View {
        TextField(placeholder, text: text).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: width)
    }

    private func moneyHeaderCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(.caption2.bold()).foregroundColor(.secondary).frame(width: width, alignment: .leading)
    }

    private func moneyDataCell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(.caption.monospacedDigit()).foregroundColor(.primary).frame(width: width, alignment: .leading)
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
        if let opp = line.opponentAlias { return .individual(opp) }
        if let laneId = line.laneId { return .parejas(laneId) }
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
            let vs = lane.opp.joined(separator: "+")
            return matchManager.unitLogEntriesForZoom(segmentOverride: nil, includeIndividual: false, includePair: true)
                .filter { $0.scope == .parejas && $0.player == player && $0.vs == vs }
        }
    }
}

private struct WalletMatchConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager
    let target: MoneyUnitTarget

    var body: some View {
        Form {
            Section("Apuesta activa en este match") {
                Toggle("Vuelta", isOn: binding(\.vuelta))
                Toggle("Presión", isOn: binding(\.presion))
                Toggle("Carry B9", isOn: binding(\.carry))
                Toggle("Match", isOn: binding(\.match))
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
        case .individual(let opp): return matchManager.betSwitchesForIndividual(opponentAlias: opp)
        case .parejas(let laneId): return matchManager.betSwitchesForPair(laneId: laneId)
        }
    }

    private func saveSwitches(_ switches: MatchBetSwitches) {
        switch target {
        case .individual(let opp): matchManager.setBetSwitchesForIndividual(opponentAlias: opp, switches: switches)
        case .parejas(let laneId): matchManager.setBetSwitchesForPair(laneId: laneId, switches: switches)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<MatchBetSwitches, Bool>) -> Binding<Bool> {
        Binding<Bool>(
            get: { currentSwitches()[keyPath: keyPath] },
            set: { newValue in var next = currentSwitches(); next[keyPath: keyPath] = newValue; saveSwitches(next) }
        )
    }
}

struct UnitLogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let entries: [UnitLogEntry]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    detailHeader("H", 30); detailHeader("Jugador", 76); detailHeader("Tipo", 88)
                    detailHeader("VS", 78); detailHeader("u", 24); detailHeader("Detalle", 140)
                }
                ForEach(entries) { e in
                    HStack(spacing: 8) {
                        detailData("\(e.hole)", 30); detailData(e.player, 76); detailData(e.type, 88)
                        detailData(e.vs ?? "—", 78)
                        detailData(e.units > 0 ? "+\(e.units)" : "\(e.units)", 24)
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
