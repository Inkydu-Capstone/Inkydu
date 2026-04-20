//
//  NarrationManager.swift
//  Inkydu
//
//  Created by Riley Fisher on 4/19/26.
//

import AVFoundation
import Foundation
import Combine

final class NarrationManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false

    private let synthesizer = AVSpeechSynthesizer()
    private var finishHandler: (() -> Void)?
    private var currentSpeechID = UUID()

    override init() {
        super.init()
        synthesizer.delegate = self
        
        // checks what voices are available
        //for voice in AVSpeechSynthesisVoice.speechVoices().filter({ $0.language.hasPrefix("en") }) {
            //     print("Name: \(voice.name) | Language: \(voice.language) | Identifier: \(voice.identifier)")
           // }
    }

    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        stop()

        currentSpeechID = UUID()
        finishHandler = onFinish
        isSpeaking = true
        isPaused = false

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)

        if let samanthaVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-US.Samantha") {
            utterance.voice = samanthaVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate = 0.27
        utterance.pitchMultiplier = 1.38
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }

    func stop() {
        currentSpeechID = UUID()

        if synthesizer.isSpeaking || isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        isSpeaking = false
        isPaused = false
        finishHandler = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let handler = finishHandler
        finishHandler = nil
        isSpeaking = false
        isPaused = false
        handler?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
        finishHandler = nil
    }
}
