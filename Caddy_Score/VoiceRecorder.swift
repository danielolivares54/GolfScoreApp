//
//  VoiceRecorder.swift
//  Caddy_Score
//
//  Created by daniel olivares on 2/14/26.
//

import Foundation
import AVFoundation
import Speech
import Combine

class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var lastError: String? = nil
    
    private var audioRecorder: AVAudioRecorder?
    private var audioURL: URL?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private var recognitionTask: SFSpeechRecognitionTask?
    
    override init() {
        super.init()
    }
    
    func requestPermissions() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { print("Microphone permission: \(granted)") }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { print("Microphone permission: \(granted)") }
            }
        }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { print("Speech permission: \(status.rawValue)") }
        }
    }

    // Single entry point: checks/requests mic permission then starts recording
    func requestMicrophoneAndStart(completion: @escaping @MainActor (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted { self.startRecording() }
                    Task { @MainActor in completion(granted) }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted { self.startRecording() }
                    Task { @MainActor in completion(granted) }
                }
            }
        }
    }
    
    // Call this only after permission has been confirmed by requestMicrophoneAndStart
    func startRecording() {
        lastError = nil
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Deactivate first to release any lock held by Siri or a previous session
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            try audioSession.setCategory(.playAndRecord, mode: .default,
                                         options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
        } catch {
            lastError = "No se pudo activar el micrófono: \(error.localizedDescription)"
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        audioURL = tempDir.appendingPathComponent("voice_\(Date().timeIntervalSince1970).m4a")
        
        guard let url = audioURL else { return }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            
            DispatchQueue.main.async {
                self.isRecording = true
                self.transcript = ""
            }
        } catch {
            lastError = "Error al iniciar grabación."
        }
    }
    
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        return audioURL
    }

    func transcribeWithApple(url: URL) async throws -> (text: String, confidence: Double) {
        try await withCheckedThrowingContinuation { continuation in
            guard let recognizer = speechRecognizer, recognizer.isAvailable else {
                continuation.resume(throwing: NSError(domain: "Speech", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Speech recognizer not available"
                ]))
                return
            }
            let request = SFSpeechURLRecognitionRequest(url: url)
            if #available(iOS 13.0, *) {
                request.requiresOnDeviceRecognition = false
            }
            recognitionTask?.cancel()
            var didFinish = false
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error = error, !didFinish {
                    didFinish = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result = result else { return }
                if result.isFinal && !didFinish {
                    didFinish = true
                    let text = result.bestTranscription.formattedString
                    let segments = result.bestTranscription.segments
                    let total = segments.reduce(0.0) { $0 + Double($1.confidence) }
                    let confidence = segments.isEmpty ? 0.0 : (total / Double(segments.count))
                    continuation.resume(returning: (text, confidence))
                }
            }
        }
    }
}
