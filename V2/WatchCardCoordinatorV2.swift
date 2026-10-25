//
//  WatchCardCoordinatorV2.swift
//  v2t · Watch: el borrador del hoyo vive aquí (iPhone). El reloj manda audio y órdenes (lápiz, goma, Anotar,
//  Deshacer) y recibe la tarjeta ya calculada (`WatchCardDTO`). Sin WatchConnectivity: eso está en WatchBridgeV2,
//  así esta lógica se prueba sola.
//

import Foundation

@MainActor
final class WatchCardCoordinator {
    typealias Transcriber = (_ audio: URL, _ match: MatchManager) async throws -> String

    private let match: MatchManager
    private let currentHole: () -> Int
    private let transcriber: Transcriber
    private let extractor: VoiceHolePipeline.Extractor
    private let slang: VoiceSlangStore
    private let hasKey: () -> Bool

    private(set) var draft = VoiceHoleDraft()
    private var undo: (hole: Int, token: VoiceUndoToken)?
    private var applied: WatchCardDTO.Applied?
    private var error: String?
    private var processing = false
    private var recordIds: [String] = []
    private(set) var revision = 0

    /// Se llama cada vez que la tarjeta cambia (el puente la manda al reloj).
    var onChange: (() -> Void)?

    init(match: MatchManager, currentHole: @escaping () -> Int,
         transcriber: @escaping Transcriber = { url, match in
             try await OpenAIService.shared.transcribeAudio(url: url, prompt: VoiceHolePipeline.transcriptionPrompt(match: match))
         },
         extractor: @escaping VoiceHolePipeline.Extractor = VoiceHolePipeline.liveExtractor,
         slang: VoiceSlangStore = .shared,
         hasKey: @escaping () -> Bool = { AppConfig.hasOpenAIKey }) {
        self.hasKey = hasKey
        self.match = match
        self.currentHole = currentHole
        self.transcriber = transcriber
        self.extractor = extractor
        self.slang = slang
    }

    // MARK: Audio → borrador

    /// Llega la grabación del reloj: se transcribe y se suma al borrador (lo más reciente gana en cada celda).
    func receiveAudio(_ url: URL) async {
        if applied != nil { draft = VoiceHoleDraft(); recordIds = []; undo = nil }   // otra dictada = otro hoyo
        applied = nil
        error = nil
        processing = true
        changed()
        defer { processing = false; changed() }
        guard hasKey() else {
            error = "Falta la clave de OpenAI en el iPhone."
            return
        }
        do {
            let text = try await transcriber(url, match)
            // Las preguntas y lecturas todavía no se contestan en el reloj.
            if ReadbackIntentV2.detect(text, names: match.players.flatMap { [$0.alias, $0.name.split(separator: " ").first.map(String.init) ?? $0.name] }) != nil {
                error = "Las preguntas todavía no están en el reloj. Pregunta en el iPhone."
                return
            }
            recordIds.append(VoiceRecordStore.shared.record(audio: url, transcript: text, roundId: match.roundId, hole: draft.hole))
            draft = try await VoiceHolePipeline.propose(transcript: text, match: match, draft: draft, defaultHole: currentHole(),
                                                        slang: slang, extractor: extractor)
        } catch VoiceHoleError.query {
            error = "Las preguntas todavía no están en el reloj. Pregunta en el iPhone."
        } catch let e as VoiceHoleError {
            error = e.message
        } catch {
            self.error = "No se pudo procesar: \(error.localizedDescription)"
        }
    }

    // MARK: Órdenes del reloj

    func handle(_ command: WatchCommand) {
        switch command {
        case .edit(let alias, let gross, let putts):
            guard match.players.contains(where: { $0.alias == alias }), (1...20).contains(gross) else { return }
            if draft.hole == nil { draft.hole = currentHole() }
            draft.cells[alias] = .init(gross: gross, putts: putts.map { min(max($0, 0), gross) })
            draft.doubts[alias] = nil   // el toque de lápiz confirma
        case .clear(let alias):
            draft.cells[alias] = nil
            draft.doubts[alias] = nil
        case .removeChip(let id):
            removeChip(id)
        case .apply:
            apply()
        case .undo:
            guard let u = undo else { return }
            VoiceHolePipeline.undo(u.token, match: match)
            undo = nil
            applied = nil
            draft = VoiceHoleDraft()
            recordIds = []
        case .discard:
            draft = VoiceHoleDraft()
            recordIds = []
            applied = nil
            error = nil
        }
        error = nil
        changed()
    }

    private func apply() {
        guard let hole = draft.hole, VoiceHolePipeline.canApply(draft, match: match),
              let token = VoiceHolePipeline.apply(draft, match: match) else { return }
        VoiceRecordStore.shared.resolve(ids: recordIds, finalCard: VoiceHolePipeline.cardSummary(draft))
        undo = (hole, token)
        applied = .init(hole: hole, message: "Hoyo \(hole) anotado", canUndo: true)
        draft = VoiceHoleDraft()
        recordIds = []
    }

    private func removeChip(_ id: String) {
        let parts = id.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch parts.first {
        case "u" where parts.count == 3:
            draft.units.removeAll { $0.alias == parts[1] && $0.code == parts[2] }
        case "n" where parts.count >= 2:
            draft.notes.removeAll { $0.alias == parts[1] }
        case "o":
            draft.oyes = [:]
        case "d" where parts.count >= 2:
            let key = parts.dropFirst().joined(separator: ":")
            draft.doubts[key] = nil
            draft.unknownUnits.removeAll { "unidad:\($0.spoken)" == key }
        default: break
        }
    }

    // MARK: La tarjeta que ve el reloj

    func card() -> WatchCardDTO {
        let hole = draft.hole ?? (applied == nil ? currentHole() : nil)
        let order = match.players.map(\.alias)
        var rows: [WatchCardDTO.Row] = []
        for p in match.players {
            let cell = draft.cells[p.alias]
            let state: WatchCardDTO.State = draft.doubts[p.alias] != nil ? .doubt : (cell?.gross == nil ? .missing : .ok)
            rows.append(.init(alias: p.alias, name: p.name.split(separator: " ").first.map(String.init) ?? p.name,
                              gross: cell?.gross, putts: cell?.putts, state: state, note: draft.doubts[p.alias]))
        }
        // Alias que no están en el roster (nombre mal oído): dudosos hasta reasignarlos en el iPhone o quitarlos con la goma.
        for alias in draft.cells.keys.filter({ !order.contains($0) }).sorted() {
            let cell = draft.cells[alias]
            rows.append(.init(alias: alias, name: alias, gross: cell?.gross, putts: cell?.putts, state: .doubt,
                              note: draft.doubts[alias] ?? "No está en el grupo"))
        }

        var chips: [WatchCardDTO.Chip] = []
        let par = hole.flatMap { match.getHole($0)?.par }
        if !draft.oyes.isEmpty {
            let text = draft.oyes.sorted { $0.value < $1.value }.map { "\($0.value) \($0.key)" }.joined(separator: " · ")
            chips.append(.init(id: "o", kind: .oyes, text: "Oyes " + text))
        }
        for u in draft.units {
            chips.append(.init(id: "u:\(u.alias):\(u.code)", kind: .unit,
                               text: "\(VoiceHolePipeline.unitName(u.code, match: match)) \(u.alias)" + (u.units > 1 ? " ×\(u.units)" : "")))
        }
        for n in draft.notes { chips.append(.init(id: "n:\(n.alias)", kind: .note, text: "Nota \(n.alias)")) }
        for key in draft.doubts.keys.sorted() where !draft.cells.keys.contains(key) && !order.contains(key) {
            chips.append(.init(id: "d:\(key)", kind: .note, text: draft.doubts[key] ?? key))
        }

        let replaces = hole.map { h in draft.cells.keys.contains { match.getScore(hole: h, player: $0) > 0 } } ?? false
        return WatchCardDTO(hole: hole, par: par, replaces: replaces, rows: rows, chips: chips,
                            heard: draft.transcripts.last ?? "",
                            canApply: VoiceHolePipeline.canApply(draft, match: match),
                            error: error, processing: processing, applied: applied, revision: revision)
    }

    func context(course: String) -> WatchContextDTO {
        let hole = currentHole()
        return WatchContextDTO(hole: hole, par: match.getHole(hole)?.par ?? 4, course: course, hasKey: AppConfig.hasOpenAIKey)
    }

    private func changed() {
        revision += 1
        onChange?()
    }
}
