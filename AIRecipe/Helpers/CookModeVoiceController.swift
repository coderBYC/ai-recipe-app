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
    /// Full transcript already consumed for command detection.
    private var lastProcessedText: String = ""
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
        lastProcessedText = ""

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
        // Only process the NEW part since the last command we handled.
        // SFSpeech partial results frequently include older words repeatedly.
        let newPart: String
        if lower.hasPrefix(lastProcessedText) {
            newPart = String(lower.dropFirst(lastProcessedText.count))
        } else {
            // Recognizer likely reset/rewrote transcript; treat full text as new baseline.
            newPart = lower
        }
        let candidate = newPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        let now = Date()
        guard now.timeIntervalSince(lastCommandAt) >= commandCooldown else { return }

        var detectedCommand: CookVoiceCommand = .none
        if let mins = Self.extractMinutes(from: candidate), mins > 0, mins <= 180 {
            detectedCommand = .setMinutes(mins)
        } else if Self.containsWord(candidate, word: "pause") {
            detectedCommand = .pauseTimer
        } else if Self.containsWord(candidate, word: "start") || Self.containsWord(candidate, word: "resume") {
            detectedCommand = .resumeTimer
        } else if Self.containsWord(candidate, word: "back") || Self.containsWord(candidate, word: "previous") {
            detectedCommand = .back
        } else if Self.containsWord(candidate, word: "next") {
            detectedCommand = .next
        }

        if detectedCommand != .none {
            lastCommandAt = now
            issuedCommand = detectedCommand
            // Mark everything spoken up to this point as consumed.
            lastProcessedText = lower
        }
    }

    private static func extractMinutes(from text: String) -> Int? {
        // numeric form: "5 minutes", "5 min", "5 mins"
        let numericPattern = #"(\d+)\s*[-–—]?\s*(?:minutes?|mins?|min)\b"#
        if let regex = try? NSRegularExpression(pattern: numericPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            if let last = matches.last, last.numberOfRanges > 1,
               let r = Range(last.range(at: 1), in: text),
               let v = Int(text[r]) {
                return v
            }
        }

        // word form: "five minutes", "ten min"
        let words: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
            "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
        ]
        let tokens = text
            .replacingOccurrences(of: "-", with: " ")
            .split { !$0.isLetter }
            .map { String($0).lowercased() }

        guard !tokens.isEmpty else { return nil }
        for i in stride(from: tokens.count - 1, through: 0, by: -1) {
            let t = tokens[i]
            guard t == "minute" || t == "minutes" || t == "min" || t == "mins" else { continue }
            if i > 0, let v = words[tokens[i - 1]] {
                // support "twenty five minutes"
                if i > 1, let tens = words[tokens[i - 2]], tens >= 20, tens % 10 == 0, v < 10 {
                    return tens + v
                }
                return v
            }
        }
        return nil
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
