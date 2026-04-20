import AVFoundation
import Speech
import SwiftUI
import Combine

final class MicManager: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""

    private var audioEngine: AVAudioEngine?
    private let speechToTextRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private let silenceTimeoutSeconds: Double = 2.25
    private let minimumListeningSeconds: Double = 1.5

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimerTask: Task<Void, Never>?
    private var deliveredFinalTranscript = false
    private var lastPartialTranscript = ""
    private var listeningStartedAt: Date?

    func startListening(
        onReady: @escaping () -> Void,
        onPartialTranscript: @escaping (String) -> Void,
        onTranscript: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) {
        guard !isListening else { return }

        Task { @MainActor in
            await startListeningInternal(
                onReady: onReady,
                onPartialTranscript: onPartialTranscript,
                onTranscript: onTranscript,
                onUnavailable: onUnavailable
            )
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
        silenceTimerTask?.cancel()
        silenceTimerTask = nil

        isListening = false
        transcript = ""
        lastPartialTranscript = ""
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

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error.localizedDescription)")
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

    @MainActor
    private func startListeningInternal(
        onReady: @escaping () -> Void,
        onPartialTranscript: @escaping (String) -> Void,
        onTranscript: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void
    ) async {
        guard await requestSpeechAuthorization() else {
            onUnavailable("Speech recognition permission is turned off.")
            return
        }

        guard await requestMicrophoneAccess() else {
            onUnavailable("Microphone access is turned off.")
            return
        }

        guard let speechToTextRecognizer, speechToTextRecognizer.isAvailable else {
            onUnavailable("Speech recognition is not available right now.")
            return
        }

        stopListening()

        transcript = ""
        deliveredFinalTranscript = false
        lastPartialTranscript = ""
        listeningStartedAt = nil

        do {
            let session = AVAudioSession.sharedInstance()

            // .measurement is usually more stable for speech recognition than .voiceChat
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )

            try session.setPreferredSampleRate(44_100)
            try session.setPreferredIOBufferDuration(0.0058)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onUnavailable("I couldn't set up the microphone.")
            stopListening()
            return
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            onUnavailable("Microphone input is not available right now.")
            stopListening()
            return
        }

        // Extra simulator guard
        #if targetEnvironment(simulator)
        let route = AVAudioSession.sharedInstance().currentRoute
        if route.inputs.isEmpty {
            onUnavailable("No microphone input is available in the simulator. Try a real device.")
            stopListening()
            return
        }
        #endif

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

        recognitionTask = speechToTextRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let spokenText = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    self.transcript = spokenText
                    self.scheduleSilenceTimeout(onTranscript: onTranscript, onUnavailable: onUnavailable)

                    if !spokenText.isEmpty, spokenText != self.lastPartialTranscript {
                        self.lastPartialTranscript = spokenText
                        onPartialTranscript(spokenText)
                    }
                }

                if result.isFinal {
                    DispatchQueue.main.async {
                        guard !self.deliveredFinalTranscript else { return }

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
                DispatchQueue.main.async {
                    guard !self.deliveredFinalTranscript else { return }

                    let cleanedTranscript = self.transcript
                        .trimmingCharacters(in: .whitespacesAndNewlines)

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
}
