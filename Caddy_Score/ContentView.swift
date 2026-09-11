import SwiftUI

struct ContentView: View {
    @StateObject private var matchManager = MatchManager()
    @State private var showGuidedSetup = false
    @State private var showBetZoom = false
    @State private var showMoneyTracker = false
    @State private var showRescueCapture = false
    @State private var showCoursePicker = false
    @State private var showStartHolePicker = false

    private let appBgTop    = Color(red: 0.03, green: 0.12, blue: 0.08)
    private let appBgBottom = Color(red: 0.02, green: 0.08, blue: 0.06)

    var body: some View {
        VStack(spacing: 0) {
            headerView
            ScorecardGrid(matchManager: matchManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            holeSummaryBar
            bottomControls
        }
        .background(
            LinearGradient(colors: [appBgTop, appBgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showCoursePicker) {
            CoursePickerView(matchManager: matchManager)
        }
        .sheet(isPresented: $showStartHolePicker) {
            StartHolePickerView(matchManager: matchManager)
        }
        .sheet(isPresented: $showGuidedSetup) {
            GuidedSetupView(matchManager: matchManager)
                .caddySheetDetents()
        }
        .sheet(isPresented: $showBetZoom) {
            NavigationView {
                ScrollView {
                    BetZoomCard(matchManager: matchManager).padding()
                }
                .navigationTitle("Resultados")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showMoneyTracker) {
            NavigationView {
                MoneyTrackerView(matchManager: matchManager)
            }
        }
        .sheet(isPresented: $showRescueCapture) {
            IntentTestView(matchManager: matchManager)  // TEMPORAL: Mini-Bloque 3.5 test
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            Button { showCoursePicker = true } label: {
                HStack(spacing: 6) {
                    Image("CGMLogo")
                        .resizable().scaledToFit()
                        .frame(width: 18, height: 18)
                    Text(matchManager.courseId)
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(9)
            }
            .buttonStyle(.plain)

            Button { showStartHolePicker = true } label: {
                Text("H\(matchManager.startHole)")
                    .font(.headline)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(9)
            }
            .buttonStyle(.plain)

            Spacer()

            if let last = matchManager.lastCompleteHole() {
                Text("Ult \(last)")
                    .font(.caption).foregroundColor(.secondary)
            }
            if let next = matchManager.firstIncompleteHole() {
                Text("▶ \(next)")
                    .font(.caption.bold()).foregroundColor(.orange)
            }

            Button { showGuidedSetup = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 6)
        .background(Color(.systemBackground).ignoresSafeArea(edges: .top))
    }

    // MARK: - Hole Summary Bar (placeholder — Bloque 3)

    private var holeSummaryBar: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.blue).frame(width: 6, height: 6)
            Text("HOYO \(matchManager.expectedNextHole())")
                .font(.caption.bold())
            Spacer()
            Text("Resumen · Bloque 3")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 0) {
            controlButton(icon: "mic.fill",                 label: "Dictar")   { showRescueCapture = true }
            controlButton(icon: "arrow.uturn.backward",     label: "Deshacer") { /* Bloque 4 */ }
            controlButton(icon: "chart.bar.doc.horizontal", label: "Reporte")  { showBetZoom = true }
            controlButton(icon: "dollarsign.circle",        label: "Apuestas") { showMoneyTracker = true }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .padding(.bottom, bottomSafeArea)
        .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
    }

    private var bottomSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.bottom ?? 0
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
    }

    private func loadB3Test() {
        guard matchManager.players.count < 2 else { return }
        matchManager.setPlayers(names: ["Daniel","Anselmo","Roberto","Ricardo","DOA"])
        let h = matchManager.startHole
        zip(matchManager.players.map(\.alias), [5,3,4,6,7]).forEach { alias, strokes in
            matchManager.applyHoleEntry(HoleEntryData(hole_number: h, player_alias: alias, strokes: strokes, putts: 2, units: nil, tags: nil))
        }
        if let a0 = matchManager.players.first?.alias { matchManager.setCellOverride(alias: a0, hole: h, override: .lostHole) }
        if matchManager.players.count > 1 {
            let a1 = matchManager.players[1].alias; let h2 = (h % 18) + 1
            matchManager.applyHoleEntry(HoleEntryData(hole_number: h2, player_alias: a1, strokes: 5, putts: 2, units: nil, tags: nil))
            matchManager.setCellOverride(alias: a1, hole: h2, override: .penaltyStroke)
        }
        if matchManager.players.count > 2 { matchManager.upsertUnitEvent(hole: h, alias: matchManager.players[2].alias, code: "SANDY_PAR", units: 1) }
    }
}

// MARK: - Utilities

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension View {
    @ViewBuilder
    func caddySheetDetents() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.large])
        } else {
            self
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
