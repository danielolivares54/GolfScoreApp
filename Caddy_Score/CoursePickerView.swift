import SwiftUI

struct CoursePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        NavigationView {
            List {
                ForEach(CourseCatalog.all, id: \.id) { course in
                    Button(action: { matchManager.setCourse(course); dismiss() }) {
                        HStack {
                            Image(systemName: "flag.fill").resizable().scaledToFit().frame(width: 20, height: 20).foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).font(.headline)
                                Text("ID: \(course.id)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if course.id == matchManager.courseId {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Selecciona campo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
            }
        }
    }
}

struct StartHolePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var matchManager: MatchManager

    var body: some View {
        NavigationView {
            List {
                ForEach(1...18, id: \.self) { hole in
                    Button(action: { matchManager.updateStartHole(hole); dismiss() }) {
                        HStack {
                            Text("Hoyo \(hole)").font(.headline)
                            Spacer()
                            if hole == matchManager.startHole {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Hoyo inicial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
            }
        }
    }
}
