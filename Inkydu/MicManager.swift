import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class MicManager: ObservableObject {
    private struct BufferedMonitorChunk {
        let timestamp: Date
        let buffer: AVAudioPCMBuffer
    }

    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // tuned by testing, balances responsiveness vs false triggers
    private let silenceTimeoutSeconds: Double = 2.2
    private let minimumListeningSeconds: Double = 1.4
    private let speechMonitorWarmupSeconds: Double = 0.55
    private let speechMonitorMinimumTriggerLevel: Float = 0.02
    private let speechMonitorNoisePadding: Float = 0.01
    private let speechMonitorNoiseMultiplier: Float = 1.9
    private let speechMonitorRequiredHits = 5
    private let speechMonitorPrerollDurationSeconds: Double = 1.1

    private var audioEngine: AVAudioEngine?
    private var speechMonitorEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimerTask: Task<Void, Never>?
    private var deliveredFinalTranscript = false
    private var listeningStartedAt: Date?

    // state for passive handsfree detection
    private var isSpeechMonitorActive = false
    private var speechMonitorStartedAt: Date?
    private var speechMonitorConsecutiveHits = 0
    private var speechMonitorDidTrigger = false
    private var speechMonitorNoiseFloor: Float = 0
    private var speechMonitorRecentBuffers: [BufferedMonitorChunk] = []

    func startSpeechMonitor(
        onSpeechDetected: @escaping () -> Void,
        onUnavailable: @escaping (String) -> Void
    ) {
        guard !isListening, !isSpeechMonitorActive else { return }

        Task {
            guard await requestSpeechAuthorization() else {
                onUnavailable("Speech recognition is turned off.")
                return
            }

            guard await requestMicrophoneAccess() else {
                onUnavailable("Microphone access is turned off.")
                return
            }

            stopSpeechMonitor()

            do {
                try configureSpeechMonitorAudioSession()
            } catch {
                onUnavailable("I couldn't start hands-free listening.")
                stopSpeechMonitor()
                return
            }

            let engine = AVAudioEngine()
            speechMonitorEngine = engine

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            guard format.sampleRate > 0, format.channelCount > 0 else {
                onUnavailable("No microphone input is available.")
                stopSpeechMonitor()
                return
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }

                let level = self.rootMeanSquareLevel(from: buffer)
                let copiedBuffer = self.copyPCMBuffer(buffer)

                Task { @MainActor in
                    if let copiedBuffer {
                        self.storeSpeechMonitorBuffer(copiedBuffer)
                    }
                    self.handleSpeechMonitorLevel(level, onSpeechDetected: onSpeechDetected)
                }
            }

            engine.prepare()

            do {
                try engine.start()
            } catch {
                onUnavailable("I couldn't start hands-free listening.")
                stopSpeechMonitor()
                return
            }

            isSpeechMonitorActive = true
            speechMonitorDidTrigger = false
            speechMonitorConsecutiveHits = 0
            speechMonitorStartedAt = Date()
            speechMonitorNoiseFloor = 0
            speechMonitorRecentBuffers = []
        }
    }

    func startListening(
        onReady: @escaping () -> Void,
        onPartialTranscript: @escaping (String) -> Void,
        onTranscript: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) {
        guard !isListening else { return }

        Task {
            guard await requestSpeechAuthorization() else {
                onUnavailable("Speech recognition is turned off.")
                return
            }

            guard await requestMicrophoneAccess() else {
                onUnavailable("Microphone access is turned off.")
                return
            }

            guard let speechRecognizer, speechRecognizer.isAvailable else {
                onUnavailable("I can't listen right now.")
                return
            }

            // Pull in audio from just before trigger so we don't miss first word
            let prerollBuffers = consumeSpeechMonitorPrerollBuffers()

            stopRecognitionCapture(deactivateAudioSession: false)
            stopSpeechMonitor()

            transcript = ""
            deliveredFinalTranscript = false

            do {
                try configureRecognitionAudioSession()
            } catch {
                onUnavailable("I couldn't start the microphone.")
                stopListening()
                return
            }

            let engine = AVAudioEngine()
            audioEngine = engine

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
            recognitionRequest = request

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    let spokenText = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    Task { @MainActor in
                        self.transcript = spokenText
                        self.scheduleSilenceTimeout(onTranscript: onTranscript, onUnavailable: onUnavailable)

                        if !spokenText.isEmpty {
                            onPartialTranscript(spokenText)
                        }

                        if result.isFinal, !self.deliveredFinalTranscript {
                            self.deliveredFinalTranscript = true
                            self.finishCapture()
                            self.recognitionTask?.cancel()
                            self.recognitionTask = nil
                            self.recognitionRequest = nil

                            if spokenText.isEmpty {
                                onUnavailable("I didn't quite hear that.")
                            } else {
                                onTranscript(spokenText)
                            }
                        }
                    }
                }

                if error != nil {
                    Task { @MainActor in
                        guard !self.deliveredFinalTranscript else { return }

                        let cleanedTranscript = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

                        self.finishCapture()
                        self.recognitionTask?.cancel()
                        self.recognitionTask = nil
                        self.recognitionRequest = nil

                        if cleanedTranscript.isEmpty {
                            onUnavailable("I didn't quite hear that.")
                        } else {
                            self.deliveredFinalTranscript = true
                            onTranscript(cleanedTranscript)
                        }
                    }
                }
            }

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            guard format.sampleRate > 0, format.channelCount > 0 else {
                onUnavailable("No microphone input is available.")
                stopListening()
                return
            }

            appendPrerollBuffers(prerollBuffers, to: request, matching: format)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            engine.prepare()

            do {
                try engine.start()
            } catch {
                onUnavailable("I couldn't start listening.")
                stopListening()
                return
            }

            isListening = true
            listeningStartedAt = Date()
            onReady()

            scheduleSilenceTimeout(onTranscript: onTranscript, onUnavailable: onUnavailable)
        }
    }

    func stopListeningEarly(
        onTranscript: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) {
        guard isListening else { return }

        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        deliveredFinalTranscript = true

        finishCapture()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        if cleanedTranscript.isEmpty {
            onUnavailable("I didn't quite hear that.")
        } else {
            onTranscript(cleanedTranscript)
        }
    }

    func stopListening() {
        stopSpeechMonitor()
        stopRecognitionCapture(deactivateAudioSession: true)
    }

    func stopSpeechMonitor() {
        isSpeechMonitorActive = false
        speechMonitorDidTrigger = false
        speechMonitorConsecutiveHits = 0
        speechMonitorStartedAt = nil
        speechMonitorNoiseFloor = 0
        speechMonitorRecentBuffers = []

        if let speechMonitorEngine {
            if speechMonitorEngine.isRunning {
                speechMonitorEngine.stop()
            }

            speechMonitorEngine.inputNode.removeTap(onBus: 0)
            speechMonitorEngine.reset()
        }

        speechMonitorEngine = nil
    }

    private func stopRecognitionCapture(deactivateAudioSession: Bool) {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil

        isListening = false
        transcript = ""
        listeningStartedAt = nil

        if let audioEngine {
            if audioEngine.isRunning {
                audioEngine.stop()
            }

            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.reset()
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil

        if deactivateAudioSession {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to deactivate audio session: \(error.localizedDescription)")
            }
        }
    }

    private func finishCapture() {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        isListening = false

        if let audioEngine {
            if audioEngine.isRunning {
                audioEngine.stop()
            }

            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.reset()
        }

        recognitionRequest?.endAudio()
    }

    private func scheduleSilenceTimeout(
        onTranscript: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) {
        silenceTimerTask?.cancel()

        silenceTimerTask = Task { @MainActor in
            let elapsed = Date().timeIntervalSince(listeningStartedAt ?? Date())
            let remainingMinimum = max(0, minimumListeningSeconds - elapsed)
            let delay = max(silenceTimeoutSeconds, remainingMinimum)

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, isListening, !deliveredFinalTranscript else { return }

            let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

            finishCapture()
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil

            if cleanedTranscript.isEmpty {
                onUnavailable("I didn't quite hear that.")
            } else {
                deliveredFinalTranscript = true
                onTranscript(cleanedTranscript)
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    private func configureSpeechMonitorAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        if session.category != .playAndRecord {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
            )
        }

        try session.setPreferredSampleRate(44_100)
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func configureRecognitionAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
        )

        try session.setPreferredSampleRate(44_100)
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func handleSpeechMonitorLevel(
        _ level: Float,
        onSpeechDetected: @escaping () -> Void
    ) {
        guard isSpeechMonitorActive, !speechMonitorDidTrigger else { return }

        let elapsed = Date().timeIntervalSince(speechMonitorStartedAt ?? Date())
        updateSpeechMonitorNoiseFloor(with: level)

        guard elapsed >= speechMonitorWarmupSeconds else { return }

        let triggerLevel = max(
            speechMonitorMinimumTriggerLevel,
            speechMonitorNoiseFloor * speechMonitorNoiseMultiplier,
            speechMonitorNoiseFloor + speechMonitorNoisePadding
        )

        if level > triggerLevel {
            speechMonitorConsecutiveHits += 1
        } else {
            speechMonitorConsecutiveHits = 0
        }

        guard speechMonitorConsecutiveHits >= speechMonitorRequiredHits else { return }

        speechMonitorDidTrigger = true
        stopSpeechMonitor()
        onSpeechDetected()
    }

    private func updateSpeechMonitorNoiseFloor(with level: Float) {
        if speechMonitorNoiseFloor == 0 {
            speechMonitorNoiseFloor = level
            return
        }

        let smoothing: Float = 0.12

        speechMonitorNoiseFloor = max(
            0.001,
            (speechMonitorNoiseFloor * (1 - smoothing)) + (level * smoothing)
        )
    }

    private func storeSpeechMonitorBuffer(_ buffer: AVAudioPCMBuffer) {
        speechMonitorRecentBuffers.append(
            BufferedMonitorChunk(timestamp: Date(), buffer: buffer)
        )

        let cutoffDate = Date().addingTimeInterval(-speechMonitorPrerollDurationSeconds)
        speechMonitorRecentBuffers.removeAll { $0.timestamp < cutoffDate }
    }

    private func consumeSpeechMonitorPrerollBuffers() -> [AVAudioPCMBuffer] {
        let cutoffDate = Date().addingTimeInterval(-speechMonitorPrerollDurationSeconds)

        let buffers = speechMonitorRecentBuffers
            .filter { $0.timestamp >= cutoffDate }
            .map(\.buffer)

        speechMonitorRecentBuffers = []
        return buffers
    }

    private func appendPrerollBuffers(
        _ buffers: [AVAudioPCMBuffer],
        to request: SFSpeechAudioBufferRecognitionRequest,
        matching format: AVAudioFormat
    ) {
        for buffer in buffers {
            guard buffer.format.channelCount == format.channelCount else { continue }
            guard abs(buffer.format.sampleRate - format.sampleRate) < 1 else { continue }
            request.append(buffer)
        }
    }

    private nonisolated func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else {
            return nil
        }

        copy.frameLength = buffer.frameLength
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if let source = buffer.floatChannelData,
           let destination = copy.floatChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copy
        }

        if let source = buffer.int16ChannelData,
           let destination = copy.int16ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copy
        }

        if let source = buffer.int32ChannelData,
           let destination = copy.int32ChannelData {
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameLength)
            }
            return copy
        }

        return nil
    }

    private nonisolated func rootMeanSquareLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard
            let channelData = buffer.floatChannelData,
            buffer.frameLength > 0
        else {
            return 0
        }

        let channel = channelData[0]
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0

        for index in 0..<frameCount {
            let sample = channel[index]
            sum += sample * sample
        }

        return sqrt(sum / Float(frameCount))
    }
}
