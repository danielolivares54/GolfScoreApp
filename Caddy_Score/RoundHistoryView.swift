import SwiftUI

// MARK: - Design tokens (mismos valores que HoleAuditView/ContentView)

private extension Color {
    static let cBg      = Color(red: 0.965, green: 0.953, blue: 0.925)
    static let cSurface = Color.white
    static let cBorder  = Color(red: 0.890, green: 0.875, blue: 0.824)
    static let cRowDiv  = Color(red: 0.941, green: 0.929, blue: 0.898)
    static let cInk     = Color(red: 0.110, green: 0.137, blue: 0.129)
    static let cMuted   = Color(red: 0.431, green: 0.416, blue: 0.361)
    static let cFairway = Color(red: 0.114, green: 0.627, blue: 0.310)
    static let cBrick   = Color(red: 0.659, green: 0.275, blue: 0.184)
    static let cGold    = Color(red: 0.784, green: 0.608, blue: 0.235)
    static let cDisabled = Color(red: 0.855, green: 0.835, blue: 0.769)
    static let cErrBg   = Color(red: 0.992, green: 0.910, blue: 0.894)
}

// MARK: - Historial de rondas cerradas
//
// Lee closed_rounds/*.json (App Group) — cada ronda cerrada queda archivada ahí desde que se
// implementó "Cerrar Ronda" (CAMBIOS_CADDIE_v2.md #6), pero hasta ahora nada en la app los leía
// de vuelta. Esta pantalla filtra por rival individual y muestra los strokes vigentes en esa
// ronda, resaltados — si alguno salió en 0 debe notarse a simple vista, no perderse en el gris.

struct RoundHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var directory = PlayerDirectoryStore.shared
    @State private var rounds: [RoundResultFile] = []
    @State private var selectedPlayerName: String
    @State private var showingMyHistory = false
    @State private var showingPlayerPicker = false

    // Permite abrir el Log ya filtrado a un jugador específico — ej. desde la ficha de ese
    // jugador en el Directorio, para resolver una disputa de stroke sin tener que buscarlo.
    init(initialPlayerName: String = "Todos") {
        self._selectedPlayerName = State(initialValue: initialPlayerName)
    }

    // Nombre real del rival, no el alias — un mismo rival puede haber tenido distinto alias
    // en rondas viejas si cambió el roster. round.players trae el alias vigente DE ESA ronda.
    private func name(for round: RoundResultFile, alias: String?) -> String? {
        guard let alias else { return nil }
        return round.players.first { $0.alias == alias }?.name
    }

    // Filtra por nombre, no solo por quien ya aparece en el log — también se puede filtrar por
    // cualquier jugador activo del Directorio aunque todavía no tenga rondas cerradas.
    private var playerNames: [String] {
        var names = Set<String>()
        for round in rounds {
            for line in round.lines where line.scope == "individual" {
                if let n = name(for: round, alias: line.opponentAlias) { names.insert(n) }
            }
        }
        for entry in directory.entries where entry.active { names.insert(entry.name) }
        return ["Todos"] + names.sorted()
    }

    private var filteredRounds: [RoundResultFile] {
        guard selectedPlayerName != "Todos" else { return rounds }
        return rounds.filter { round in
            round.lines.contains { $0.scope == "individual" && name(for: round, alias: $0.opponentAlias) == selectedPlayerName }
        }
    }

    // La ronda más reciente contra cada rival es la que define el stroke del próximo match
    // (ver ContentView.applyInterMatchStrokeCarry) — rounds ya viene ordenado por closedAt desc.
    private var mostRecentRoundIdByName: [String: String] {
        var out: [String: String] = [:]
        for round in rounds {
            for line in round.lines where line.scope == "individual" {
                if let n = name(for: round, alias: line.opponentAlias), out[n] == nil {
                    out[n] = round.roundId
                }
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cBg.ignoresSafeArea()
                if filteredRounds.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(filteredRounds, id: \.roundId) { round in
                                roundCard(round)
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 14)
                    }
                }
            }
            .navigationTitle("Historial de Rondas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // El selector de rival ya no vive en la pantalla principal — se abre aparte,
                // como una lista vertical (igual que el Directorio), no chips horizontales.
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingPlayerPicker = true } label: {
                        HStack(spacing: 4) {
                            Text(selectedPlayerName)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 14, weight: .bold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingMyHistory = true } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPlayerPicker) { playerPicker }
            .sheet(isPresented: $showingMyHistory) { MyHistoryView() }
        }
        .onAppear { rounds = RoundResultFile.loadAll() }
    }

    // MARK: Selector de rival — lista vertical, como el Directorio de jugadores

    private var playerPicker: some View {
        NavigationStack {
            List {
                ForEach(playerNames, id: \.self) { name in
                    let sel = selectedPlayerName == name
                    Button {
                        selectedPlayerName = name
                        showingPlayerPicker = false
                    } label: {
                        HStack {
                            Text(name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.cInk)
                            Spacer()
                            if sel {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.cFairway)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Filtrar por rival")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { showingPlayerPicker = false }
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 52)).foregroundColor(.cDisabled)
            Text("Sin rondas cerradas todavía")
                .font(.system(size: 15)).foregroundColor(.cMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Round card

    private func roundCard(_ round: RoundResultFile) -> some View {
        let shownLines = round.lines.filter { line in
            guard line.scope == "individual" else { return false }
            return selectedPlayerName == "Todos" || name(for: round, alias: line.opponentAlias) == selectedPlayerName
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(round.date)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.cInk)
                    Text("\(round.courseName) · Sale H\(round.startHole)")
                        .font(.system(size: 11.5)).foregroundColor(.cMuted)
                }
                Spacer()
                Text(caddyMoneyStr(round.totalMoney))
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(round.totalMoney >= 0 ? .cFairway : .cBrick)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Color.cRowDiv.frame(height: 1)

            ForEach(Array(shownLines.enumerated()), id: \.offset) { idx, line in
                opponentRow(round: round, line: line)
                if idx < shownLines.count - 1 { Color.cRowDiv.frame(height: 1).padding(.leading, 14) }
            }
        }
        .background(Color.cSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
    }

    // MARK: Fila por rival — resultado + strokes vigentes esa ronda, resaltados

    private func opponentRow(round: RoundResultFile, line: RoundResultLine) -> some View {
        let strokes = round.players.first { $0.alias == line.opponentAlias }?.strokesVsBase ?? 0
        let isZero = abs(strokes) < 0.001
        let playerName = name(for: round, alias: line.opponentAlias)
        // La ronda más reciente contra este rival es la que define el stroke del próximo
        // match — se marca "VIGENTE" y se muestra el stroke vivo del Directorio (no el
        // strokesVsBase archivado de esta ronda, que ya pudo moverse desde entonces).
        let isCurrent = playerName.map { mostRecentRoundIdByName[$0] == round.roundId } ?? false
        let liveStrokes = playerName.flatMap { n in directory.entries.first { $0.name == n }?.strokesVsBase }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(playerName ?? line.opponentAlias ?? "—")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.cInk)
                        if isCurrent {
                            Text("VIGENTE")
                                .font(.system(size: 8, weight: .black)).kerning(0.4)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.cFairway)
                                .cornerRadius(5)
                        }
                    }
                    Text("Vuelta \(line.vueltaPoints >= 0 ? "+" : "")\(line.vueltaPoints) · Match \(line.matchPoints >= 0 ? "+" : "")\(line.matchPoints)")
                        .font(.system(size: 11)).foregroundColor(resultColor(line.matchPoints))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Strokes esa ronda")
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.cMuted)
                    Text(strokeStr(strokes))
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(isZero ? .cBrick : .cGold)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(isZero ? Color.cErrBg : Color.cGold.opacity(0.12))
                .cornerRadius(8)
            }

            HStack(spacing: 8) {
                segmentBadge("F9", points: line.f9Points)
                segmentBadge("B9", points: line.b9Points)
                moneyBadge(line.totalMoney)
                Spacer()
                if isCurrent, let liveStrokes {
                    Text("Próximo match: \(strokeStr(liveStrokes)) strokes")
                        .font(.system(size: 10.5, weight: .semibold)).foregroundColor(.cFairway)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func resultColor(_ points: Int) -> Color {
        points > 0 ? .cFairway : points < 0 ? .cBrick : .cMuted
    }

    private func segmentBadge(_ label: String, points: Int?) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .black)).foregroundColor(.cMuted)
            Text(points.map { "\($0 >= 0 ? "+" : "")\($0)" } ?? "—")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(points.map(resultColor) ?? .cDisabled)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.cBg)
        .cornerRadius(6)
    }

    // Dinero ganado/perdido contra ESTE rival específico (line.totalMoney) — distinto del total
    // de la ronda que ya se ve arriba en roundCard, que puede sumar varios rivales a la vez.
    private func moneyBadge(_ value: Int) -> some View {
        Text(caddyMoneyStr(value))
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(resultColor(value))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.cBg)
            .cornerRadius(6)
    }

    private func strokeStr(_ v: Double) -> String {
        let sign = v > 0 ? "+" : ""
        return v.truncatingRemainder(dividingBy: 1) == 0 ? "\(sign)\(Int(v))" : String(format: "%@%.1f", sign, v)
    }

    private func caddyMoneyStr(_ v: Int) -> String {
        (v >= 0 ? "+$" : "-$") + "\(abs(v))"
    }
}

// MARK: - Mi Historial de Golf
//
// Estadísticas vitalicias calculadas sobre todas las rondas cerradas (closed_rounds/*.json) —
// no se guarda nada nuevo aquí salvo oyesWinsByAlias (RoundResultFile), todo lo demás se deriva
// de scores/strokesVsBase ya archivados + los pares/SI del campo (CourseCatalog).
// Vive en este archivo (no en uno propio) porque el proyecto no registra automáticamente
// Target Membership para archivos .swift nuevos vía herramientas — mismo problema que AppIcon.
struct MyHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rounds: [RoundResultFile] = []

    private enum HoleResult { case win, tie, loss }

    private struct Stats {
        var eagleOrBetter = 0, birdie = 0, par = 0, bogey = 0, doubleOrWorse = 0
        var oyesWins = 0
        var moneyIndividual = 0
        var moneyParejas = 0
        // Hoyos donde YO recibí el stroke de ese rival
        var receiveDecidedWin = 0, receiveDecidedTie = 0, receiveNoFactor = 0
        // Hoyos donde YO le di el stroke a ese rival
        var giveWinOrTie = 0, giveTotal = 0
        var matchesCounted = 0
        // Diferencial (gross - par) de cada hoyo que jugué, agrupado por tipo de hoyo —
        // para el promedio y desviación estándar por par 3/4/5.
        var diffsByPar: [Int: [Int]] = [3: [], 4: [], 5: []]

        var moneyTotal: Int { moneyIndividual + moneyParejas }
        var receiveTotal: Int { receiveDecidedWin + receiveDecidedTie + receiveNoFactor }
        var receiveWinOrTiePct: Double {
            guard receiveTotal > 0 else { return 0 }
            return Double(receiveDecidedWin + receiveDecidedTie + (receiveNoFactor / 2)) / Double(receiveTotal)
        }
        var giveWinOrTiePct: Double {
            guard giveTotal > 0 else { return 0 }
            return Double(giveWinOrTie) / Double(giveTotal)
        }

        func average(forPar par: Int) -> Double? {
            let diffs = diffsByPar[par] ?? []
            guard !diffs.isEmpty else { return nil }
            return Double(diffs.reduce(0, +)) / Double(diffs.count)
        }

        // Desviación estándar poblacional — qué tan parejo juegas ese tipo de hoyo (bajo = consistente).
        func stdDev(forPar par: Int) -> Double? {
            let diffs = diffsByPar[par] ?? []
            guard diffs.count > 1, let mean = average(forPar: par) else { return nil }
            let variance = diffs.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(diffs.count)
            return variance.squareRoot()
        }
    }

    private var stats: Stats {
        var s = Stats()
        s.matchesCounted = rounds.count
        for round in rounds {
            guard let yo = round.players.first,
                  let course = CourseCatalog.all.first(where: { $0.id == round.courseId }) else { continue }
            let holesByNumber = Dictionary(uniqueKeysWithValues: course.holes.map { ($0.number, $0) })

            for (holeStr, gross) in yo.scores {
                guard let holeNum = Int(holeStr), let hole = holesByNumber[holeNum] else { continue }
                let diff = gross - hole.par
                switch diff {
                case ..<(-1): s.eagleOrBetter += 1
                case -1:      s.birdie += 1
                case 0:       s.par += 1
                case 1:       s.bogey += 1
                default:      s.doubleOrWorse += 1
                }
                s.diffsByPar[hole.par, default: []].append(diff)
            }

            s.oyesWins += round.oyesWinsByAlias?[yo.alias] ?? 0

            // Dinero — individual y parejas por separado, se muestran los dos.
            for line in round.lines {
                if line.scope == "individual" { s.moneyIndividual += line.totalMoney }
                else if line.scope == "parejas" { s.moneyParejas += line.totalMoney }
            }

            for opp in round.players where opp.alias != yo.alias {
                for (holeStr, oppGross) in opp.scores {
                    guard let holeNum = Int(holeStr), let hole = holesByNumber[holeNum],
                          let yoGross = yo.scores[holeStr] else { continue }
                    let strokeCount = Self.distributedStrokes(total: abs(opp.strokesVsBase), hole: hole)
                    guard strokeCount > 0.001 else { continue }
                    let yoReceives = opp.strokesVsBase < 0  // negativo = él me da el golpe a mí
                    let rawResult = Self.result(yoGross: Double(yoGross), oppGross: Double(oppGross))

                    if yoReceives {
                        let adjResult = Self.result(yoGross: Double(yoGross) - strokeCount, oppGross: Double(oppGross))
                        if rawResult == .loss, adjResult == .win {
                            s.receiveDecidedWin += 1
                        } else if rawResult == .loss, adjResult == .tie {
                            s.receiveDecidedTie += 1
                        } else {
                            s.receiveNoFactor += 1
                        }
                    } else {
                        s.giveTotal += 1
                        if rawResult == .win || rawResult == .tie { s.giveWinOrTie += 1 }
                    }
                }
            }
        }
        return s
    }

    private static func result(yoGross: Double, oppGross: Double) -> HoleResult {
        if yoGross < oppGross - 0.001 { return .win }
        if yoGross > oppGross + 0.001 { return .loss }
        return .tie
    }

    // Misma fórmula que MatchManager.distributedStrokes — se duplica aquí porque esta vista
    // trabaja sobre rondas ya cerradas, sin una instancia viva de MatchManager.
    private static func distributedStrokes(total: Double, hole: HoleModel) -> Double {
        guard total > 0 else { return 0 }
        let fullRounds = Int(total / 18.0)
        let remainder = total - Double(fullRounds * 18)
        let whole = Int(floor(remainder))
        let fraction = remainder - Double(whole)
        var strokes = Double(fullRounds)
        if hole.si <= whole {
            strokes += 1
        } else if fraction >= 0.5, hole.si == whole + 1 {
            strokes += 0.5
        }
        return strokes
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cBg.ignoresSafeArea()
                if rounds.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            headerCard
                            histogramCard
                            parTypeCard
                            strokeImpactCard
                            oyesMoneyCard
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("Mi Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
            }
        }
        .onAppear { rounds = RoundResultFile.loadAll() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill").font(.system(size: 52)).foregroundColor(.cBorder)
            Text("Sin rondas cerradas todavía").font(.system(size: 15)).foregroundColor(.cMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerCard: some View {
        Text("MI HISTORIAL · \(stats.matchesCounted) match\(stats.matchesCounted == 1 ? "" : "es")")
            .font(.system(size: 13, weight: .bold)).kerning(0.5)
            .foregroundColor(.cMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ content: some View) -> some View {
        content
            .padding(16)
            .background(Color.cSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cBorder, lineWidth: 1))
    }

    private func statRow(_ label: String, _ value: Int, color: Color = .cInk) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundColor(.cMuted)
            Spacer()
            Text("\(value)").font(.system(size: 22, weight: .black, design: .monospaced)).foregroundColor(color)
        }
    }

    private var histogramCard: some View {
        card(
            VStack(spacing: 10) {
                statRow("Águila o mejor", stats.eagleOrBetter, color: .cFairway)
                statRow("Birdie", stats.birdie, color: .cFairway)
                statRow("Par", stats.par, color: .cInk)
                statRow("Bogey", stats.bogey, color: .cBrick)
                statRow("Doble o peor", stats.doubleOrWorse, color: .cBrick)
            }
        )
    }

    private func parTypeRow(_ label: String, par: Int) -> some View {
        let avg = stats.average(forPar: par)
        let dev = stats.stdDev(forPar: par)
        return HStack {
            Text(label).font(.system(size: 15)).foregroundColor(.cMuted)
            Spacer()
            if let avg {
                Text(avg >= 0 ? "+\(String(format: "%.1f", avg))" : String(format: "%.1f", avg))
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(avg > 0.05 ? .cBrick : avg < -0.05 ? .cFairway : .cInk)
                if let dev {
                    Text("± \(String(format: "%.1f", dev))")
                        .font(.system(size: 12)).foregroundColor(.cMuted)
                }
            } else {
                Text("—").font(.system(size: 20, weight: .black, design: .monospaced)).foregroundColor(.cMuted)
            }
        }
    }

    private var parTypeCard: some View {
        card(
            VStack(alignment: .leading, spacing: 10) {
                Text("PROMEDIO VS. PAR POR TIPO DE HOYO").font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundColor(.cMuted)
                parTypeRow("Par 3", par: 3)
                parTypeRow("Par 4", par: 4)
                parTypeRow("Par 5", par: 5)
                Text("Promedio de golpes vs. par · ± desviación estándar (qué tan parejo juegas ese tipo de hoyo).")
                    .font(.system(size: 11)).foregroundColor(.cMuted).lineSpacing(3)
            }
        )
    }

    private var strokeImpactCard: some View {
        card(
            VStack(alignment: .leading, spacing: 12) {
                Text("IMPACTO DEL STROKE").font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundColor(.cMuted)

                VStack(spacing: 8) {
                    HStack {
                        Text("Cuando recibo — gano o empato")
                            .font(.system(size: 13)).foregroundColor(.cMuted)
                        Spacer()
                        Text("\(Int((stats.receiveWinOrTiePct * 100).rounded()))%")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(.cFairway)
                    }
                    statRow("  Decidió victoria", stats.receiveDecidedWin, color: .cFairway)
                    statRow("  Decidió empate", stats.receiveDecidedTie, color: .cGold)
                    statRow("  No fue factor", stats.receiveNoFactor, color: .cMuted)
                }

                Color.cBorder.frame(height: 1)

                HStack {
                    Text("Cuando doy — igual gano o empato")
                        .font(.system(size: 13)).foregroundColor(.cMuted)
                    Spacer()
                    Text("\(Int((stats.giveWinOrTiePct * 100).rounded()))%")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.cFairway)
                }
                Text("(de \(stats.giveTotal) hoyos donde le di stroke a un rival)")
                    .font(.system(size: 11)).foregroundColor(.cMuted)
            }
        )
    }

    private func moneyRow(_ label: String, _ value: Int, big: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: big ? 15 : 13)).foregroundColor(.cMuted)
            Spacer()
            Text(caddyMoneyStr(value))
                .font(.system(size: big ? 22 : 16, weight: .black, design: .monospaced))
                .foregroundColor(value >= 0 ? .cFairway : .cBrick)
        }
    }

    private var oyesMoneyCard: some View {
        card(
            VStack(spacing: 10) {
                statRow("Oyes ganados", stats.oyesWins, color: .cGold)
                Color.cBorder.frame(height: 1)
                moneyRow("Individual", stats.moneyIndividual)
                moneyRow("Parejas", stats.moneyParejas)
                moneyRow("Total acumulado", stats.moneyTotal, big: true)
            }
        )
    }

    private func caddyMoneyStr(_ v: Int) -> String {
        (v >= 0 ? "+$" : "-$") + "\(abs(v))"
    }
}
