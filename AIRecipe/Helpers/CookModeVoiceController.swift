import AVFoundation
import Combine
import Foundation
import Speech

enum CookVoiceCommand: Equatable {
    case none
    case next
    case back
    case setMinutes(Int)
    case pauseTimer
    case resumeTimer
}

/// Voice commands: **N minute(s)** → set timer and auto-start; **pause** → pause countdown; **start** → resume; **next** / **back** / **previous** → steps.
final class CookModeVoiceController: ObservableObject {
    @Published var statusText: String = ""
    @Published var isListening: Bool = false
    @Published var authorizationDenied: Bool = false
    @Published var issuedCommand: CookVoiceCommand = .none

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var lastCommandAt: Date = .distantPast
    private let commandCooldown: TimeInterval = 1.25

    func requestPermissionsAndStart() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            Task { @MainActor in
                self.statusText = "Speech recognition unavailable."
                self.authorizationDenied = true
            }
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            Task { @MainActor in
                switch status {
                case .authorized:
                    self.requestMicAndStart()
                case .denied, .restricted:
                    self.authorizationDenied = true
                    self.statusText = "Enable Speech Recognition in Settings for voice commands."
                case .notDetermined:
                    self.authorizationDenied = true
                    self.statusText = "Speech recognition not allowed."
                @unknown default:
                    self.authorizationDenied = true
                    self.statusText = "Speech recognition unavailable."
                }
            }
        }
    }

    private func requestMicAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                if granted {
                    self.beginListening()
                } else {
                    self.authorizationDenied = true
                    self.statusText = "Enable Microphone in Settings for voice commands."
                }
            }
        }
    }

    private func beginListening() {
        stopInternal()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Task { @MainActor in
                self.statusText = "Could not start audio session."
            }
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.handleTranscript(text)
                }
            }
            if error != nil {
                Task { @MainActor in
                    self.isListening = false
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Task { @MainActor in
                self.isListening = true
                self.statusText = "Say: next, back, “5 minutes”, pause, start…"
                self.authorizationDenied = false
            }
        } catch {
            Task { @MainActor in
                self.statusText = "Could not start microphone."
            }
            stopInternal()
        }
    }

    func stop() {
        Task { @MainActor in
            self.isListening = false
            self.statusText = ""
            self.issuedCommand = .none
        }
        stopInternal()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @MainActor
    func resetIssuedCommand() {
        issuedCommand = .none
    }

    private func stopInternal() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    @MainActor
    private func handleTranscript(_ fullText: String) {
        let lower = fullText.lowercased()
        /// Recent tail so the latest spoken phrase wins when the buffer still has older words.
        let tail = String(lower.suffix(96))
        let now = Date()
        guard now.timeIntervalSince(lastCommandAt) >= commandCooldown else { return }

        // 1) Set timer from spoken minutes (scan whole string; last match = most recent).
        if let mins = Self.extractMinutes(from: lower), mins > 0, mins <= 180 {
            lastCommandAt = now
            issuedCommand = .setMinutes(mins)
            return
        }

        // 2) Timer transport (tail so “… please pause” still matches).
        if Self.containsWord(tail, word: "pause") {
            lastCommandAt = now
            issuedCommand = .pauseTimer
            return
        }

        if Self.containsWord(tail, word: "start") || Self.containsWord(tail, word: "resume") {
            lastCommandAt = now
            issuedCommand = .resumeTimer
            return
        }

        // 3) Step navigation — check back before next so phrases like “next go back” favor back.
        if Self.containsWord(tail, word: "back") || Self.containsWord(tail, word: "previous") {
            lastCommandAt = now
            issuedCommand = .back
            return
        }

        if Self.containsWord(tail, word: "next") {
            lastCommandAt = now
            issuedCommand = .next
            return
        }
    }

    private static func extractMinutes(from text: String) -> Int? {
        let pattern = #"(\d+)\s*[-–—]*\s*minutes?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard let last = matches.last, last.numberOfRanges > 1,
              let r = Range(last.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    private static func containsWord(_ text: String, word: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
