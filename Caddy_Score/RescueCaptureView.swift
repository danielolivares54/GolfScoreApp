import SwiftUI

struct RescueCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "mic.circle")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("Modo rescate")
                    .font(.title2.bold())
                Text("Pendiente Bloque 4")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .navigationTitle("Dictar largo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}
