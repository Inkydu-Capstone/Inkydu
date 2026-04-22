import AVFoundation
import Combine
import Foundation

enum NarrationStyle {
    case story
    case prompt
    case feedback

    var rate: Float {
        switch self {
        case .story:
            return 0.31
        case .prompt:
            return 0.35
        case .feedback:
            return 0.34
        }
    }

    var pitchMultiplier: Float {
        switch self {
        case .story:
            return 1.12
        case .prompt:
            return 1.16
        case .feedback:
            return 1.1
        }
    }

    var preUtteranceDelay: TimeInterval {
        switch self {
        case .story:
            return 0.03
        case .prompt:
            return 0.02
        case .feedback:
            return 0.01
        }
    }

    var postUtteranceDelay: TimeInterval {
        switch self {
        case .story:
            return 0.14
        case .prompt:
            return 0.08
        case .feedback:
            return 0.06
        }
    }
}

final class NarrationManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var isMouthOpen = false

    private let synthesizer = AVSpeechSynthesizer()
    private var finishHandler: (() -> Void)?
    private var currentStyle: NarrationStyle = .story
    private var mouthCloseTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        _ text: String,
        style: NarrationStyle = .story,
        onFinish: (() -> Void)? = nil
    ) {
        stop()

        finishHandler = onFinish
        currentStyle = style
        isSpeaking = true
        isPaused = false
        isMouthOpen = false

        configureAudioSessionForSpeech()

        let utterance = AVSpeechUtterance(string: speechOptimizedText(from: text, style: style))
        utterance.voice = preferredSamanthaVoice()

        utterance.rate = style.rate
        utterance.pitchMultiplier = style.pitchMultiplier
        utterance.volume = 0.96
        utterance.preUtteranceDelay = style.preUtteranceDelay
        utterance.postUtteranceDelay = style.postUtteranceDelay

        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        _ = synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        configureAudioSessionForSpeech()
        _ = synthesizer.continueSpeaking()
    }

    func stop() {
        mouthCloseTask?.cancel()
        mouthCloseTask = nil

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        isSpeaking = false
        isPaused = false
        isMouthOpen = false
        finishHandler = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
        isPaused = false
        isMouthOpen = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        mouthCloseTask?.cancel()
        mouthCloseTask = nil
        isSpeaking = true
        isPaused = true
        isMouthOpen = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        isSpeaking = true
        isPaused = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        mouthCloseTask?.cancel()
        mouthCloseTask = nil
        isSpeaking = false
        isPaused = false
        isMouthOpen = false

        let handler = finishHandler
        finishHandler = nil
        handler?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        mouthCloseTask?.cancel()
        mouthCloseTask = nil
        isSpeaking = false
        isPaused = false
        isMouthOpen = false
        finishHandler = nil
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let utteranceText = utterance.speechString as NSString
        let token = utteranceText.substring(with: characterRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else { return }

        if token.rangeOfCharacter(from: .alphanumerics) == nil {
            mouthCloseTask?.cancel()
            mouthCloseTask = nil
            isMouthOpen = false
            return
        }

        isMouthOpen = true
        scheduleMouthClose(for: token)
    }

    private func configureAudioSessionForSpeech() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    private func speechOptimizedText(from text: String, style: NarrationStyle) -> String {
        var spokenText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Smooth out common visual-text patterns that sound robotic in TTS.
        spokenText = spokenText.replacingOccurrences(of: " VS ", with: " versus ")
        spokenText = spokenText.replacingOccurrences(of: "&", with: " and ")
        spokenText = spokenText.replacingOccurrences(of: "McFluff's", with: "McFluffs")
        spokenText = spokenText.replacingOccurrences(of: "PUT THOSE RIGHT BACK!", with: "Put those right back!")

        // Add a little extra breathing room for narration without changing the displayed text.
        spokenText = spokenText.replacingOccurrences(of: ": ", with: ". ")
        spokenText = spokenText.replacingOccurrences(of: " - ", with: ", ")
        spokenText = spokenText.replacingOccurrences(of: "—", with: ", ")
        spokenText = spokenText.replacingOccurrences(of: ";", with: ".")

        if style == .story {
            spokenText = spokenText.replacingOccurrences(of: "! ", with: "!  ")
            spokenText = spokenText.replacingOccurrences(of: "? ", with: "?  ")
            spokenText = spokenText.replacingOccurrences(of: ". ", with: ".  ")
        }

        while spokenText.contains("   ") {
            spokenText = spokenText.replacingOccurrences(of: "   ", with: "  ")
        }

        return spokenText
    }

    private func preferredSamanthaVoice() -> AVSpeechSynthesisVoice? {
        let samanthaVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                voice.name == "Samantha" && voice.language.hasPrefix("en-US")
            }
            .sorted { qualityRank(for: $0.quality) > qualityRank(for: $1.quality) }

        return samanthaVoices.first
            ?? AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-US.Samantha")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func qualityRank(for quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium:
            return 3
        case .enhanced:
            return 2
        default:
            return 1
        }
    }

    private func scheduleMouthClose(for token: String) {
        mouthCloseTask?.cancel()

        let delay = estimatedMouthOpenDuration(for: token)
        mouthCloseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self.isSpeaking, !self.isPaused else { return }
            self.isMouthOpen = false
        }
    }

    private func estimatedMouthOpenDuration(for token: String) -> TimeInterval {
        let cleanedCount = token
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
            .count

        let baseDuration: TimeInterval
        switch currentStyle {
        case .story:
            baseDuration = 0.18
        case .prompt:
            baseDuration = 0.15
        case .feedback:
            baseDuration = 0.14
        }

        let extraDuration = min(Double(cleanedCount), 10.0) * 0.012
        return min(max(baseDuration + extraDuration, 0.14), 0.34)
    }
}
