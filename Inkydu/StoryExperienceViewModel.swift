import Combine
import Foundation

@MainActor
final class StoryExperienceViewModel: ObservableObject {
    enum AppStage {
        case launch
        case library
        case story
        case end
    }

    private enum ListeningSource {
        case prompt
        case ambientMonitor
    }

    @Published var appStage: AppStage = .launch
    @Published var showReadyPopup = false
    @Published var bubbleText = TeacherResponses.responseReadyToRead()
    @Published var liveTranscript = ""
    @Published var characterMode: PenguinAnimationMode = .idle

    @Published private(set) var currentPage: StoryPage?
    @Published private(set) var isNarrationActive = false
    @Published private(set) var isNarrationPaused = false
    @Published private(set) var isNarrationMouthOpen = false
    @Published private(set) var isListening = false
    @Published private(set) var isThinking = false
    @Published private(set) var isMicrophoneMuted = false

    let controller = StoryController()
    let narrationManager = NarrationManager()
    let micManager = MicManager()

    private let aiTeacherService = AITeacherService()
    private let maxAnswerAttempts = 2

    private var autoAdvanceTask: Task<Void, Never>?
    private var retryListeningTask: Task<Void, Never>?
    private var characterResetTask: Task<Void, Never>?
    private var speechMonitorArmTask: Task<Void, Never>?
    private var isCelebrating = false
    private var answerAttempts: [String: Int] = [:]
    private var sessionProfile = StorySessionProfile()
    private var activeListeningSource: ListeningSource = .prompt
    private var shouldResumeNarrationAfterListening = false
    private var cancellables: Set<AnyCancellable> = []

    init() {
        bindManagers()
    }

    var canGoBack: Bool {
        controller.canGoBack
    }

    var canGoForward: Bool {
        controller.canGoForward
    }

    func openLibrary() {
        stopAllAudioAndTasks()
        controller.reset()
        currentPage = nil
        showReadyPopup = false
        bubbleText = TeacherResponses.responseLibraryPrompt()
        liveTranscript = ""
        sessionProfile = StorySessionProfile()
        appStage = .library
        refreshCharacterMode()
    }

    func startBook(named fileName: String) {
        stopAllAudioAndTasks()
        controller.loadStoryJSON(named: fileName)
        controller.startStory()
        currentPage = controller.currentPage

        guard currentPage != nil else {
            bubbleText = TeacherResponses.responseBookUnavailable()
            liveTranscript = ""
            appStage = .library
            refreshCharacterMode()
            return
        }

        showReadyPopup = true
        bubbleText = TeacherResponses.responseReadyToRead()
        liveTranscript = ""
        answerAttempts.removeAll()
        sessionProfile = StorySessionProfile()
        appStage = .story
        refreshCharacterMode()
    }

    func beginStoryPlayback() {
        showReadyPopup = false
        playCurrentPageFromStart(resetAttempts: true)
    }

    func replayCurrentPage() {
        playCurrentPageFromStart(resetAttempts: true)
    }

    func toggleMicrophoneMuted() {
        isMicrophoneMuted.toggle()

        if isMicrophoneMuted {
            speechMonitorArmTask?.cancel()
            speechMonitorArmTask = nil

            if micManager.isListening {
                micManager.stopListening()
            } else {
                micManager.stopSpeechMonitor()
            }

            bubbleText = TeacherResponses.responseMutedPrompt()
        } else {
            bubbleText = TeacherResponses.responseHandsFreePrompt()
            resumeListeningFlowIfNeeded()
        }

        refreshCharacterMode()
    }

    func togglePausePlay() {
        if isListening {
            stopListeningEarly()
            return
        }

        if narrationManager.isPaused {
            narrationManager.resume()
        } else if narrationManager.isSpeaking {
            cancelPendingTasks()
            narrationManager.pause()
        } else {
            replayCurrentPage()
        }
    }

    func moveToNextPage() {
        stopAllAudioAndTasks()
        controller.goToNextPage()
        currentPage = controller.currentPage

        if currentPage == nil {
            appStage = .end
            bubbleText = TeacherResponses.responseStoryFinished()
            refreshCharacterMode()
            return
        }

        liveTranscript = ""
        showReadyPopup = false
        playCurrentPageFromStart(resetAttempts: true)
    }

    func moveToPreviousPage() {
        guard controller.canGoBack else { return }

        stopAllAudioAndTasks()
        controller.goToPreviousPage()
        currentPage = controller.currentPage
        liveTranscript = ""
        showReadyPopup = false
        playCurrentPageFromStart(resetAttempts: true)
    }

    func returnToLibrary() {
        openLibrary()
    }

    private func bindManagers() {
        narrationManager.$isSpeaking
            .receive(on: RunLoop.main)
            .sink { [weak self] isSpeaking in
                self?.isNarrationActive = isSpeaking
                self?.refreshCharacterMode()
            }
            .store(in: &cancellables)

        narrationManager.$isPaused
            .receive(on: RunLoop.main)
            .sink { [weak self] isPaused in
                self?.isNarrationPaused = isPaused
                self?.refreshCharacterMode()
            }
            .store(in: &cancellables)

        narrationManager.$isMouthOpen
            .receive(on: RunLoop.main)
            .sink { [weak self] isMouthOpen in
                self?.isNarrationMouthOpen = isMouthOpen
            }
            .store(in: &cancellables)

        micManager.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] isListening in
                self?.isListening = isListening
                self?.refreshCharacterMode()
            }
            .store(in: &cancellables)

        micManager.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.liveTranscript = text
            }
            .store(in: &cancellables)
    }

    private func playCurrentPageFromStart(resetAttempts: Bool) {
        guard let page = currentPage else { return }

        stopAllAudioAndTasks()
        if resetAttempts {
            answerAttempts[page.id] = 0
        }

        bubbleText = page.narration
        liveTranscript = ""
        armHandsFreeMonitor(for: page)

        narrationManager.speak(page.narration, style: .story) { [weak self] in
            Task { @MainActor in
                self?.afterNarrationFinished(for: page)
            }
        }
    }

    private func afterNarrationFinished(for page: StoryPage) {
        guard currentPage?.id == page.id else { return }

        if let interaction = StoryInteractionFactory.resolvedInteraction(for: page) {
            guard !isMicrophoneMuted else {
                bubbleText = TeacherResponses.responseMutedPrompt()
                scheduleAutoAdvance(for: page.id, after: 2.8)
                return
            }

            bubbleText = interaction.prompt
            armHandsFreeMonitor(for: page, after: 0.1)
            narrationManager.speak(interaction.prompt, style: .prompt) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.currentPage?.id == page.id else { return }

                    if interaction.autoListen {
                        self.beginListening(for: page, source: .prompt)
                    }
                }
            }
        } else {
            bubbleText = isMicrophoneMuted
                ? TeacherResponses.responseMutedPrompt()
                : TeacherResponses.responseHandsFreePrompt()
            scheduleAutoAdvance(for: page.id, after: 7.0)

            if !isMicrophoneMuted {
                armHandsFreeMonitor(for: page, after: 0.1)
            }
        }
    }

    private func beginListening(
        for page: StoryPage,
        source: ListeningSource = .prompt
    ) {
        guard currentPage?.id == page.id else { return }
        guard !isMicrophoneMuted else {
            bubbleText = TeacherResponses.responseMutedPrompt()
            return
        }

        cancelPendingTasks()
        activeListeningSource = source
        shouldResumeNarrationAfterListening = source == .ambientMonitor
            && narrationManager.isSpeaking
            && !narrationManager.isPaused

        if shouldResumeNarrationAfterListening {
            narrationManager.pause()
        } else {
            narrationManager.stop()
        }

        liveTranscript = ""
        if source == .ambientMonitor {
            bubbleText = TeacherResponses.responseListeningPrompt()
        } else {
            bubbleText = StoryInteractionFactory.resolvedInteraction(for: page)?.prompt
                ?? TeacherResponses.responseHandsFreePrompt()
        }
        refreshCharacterMode()

        micManager.startListening(
            onReady: { [weak self] in
                guard let self else { return }
                self.bubbleText = TeacherResponses.responseListeningPrompt()
            },
            onPartialTranscript: { _ in },
            onTranscript: { [weak self] transcript in
                Task { @MainActor in
                    self?.handleTranscript(transcript, for: page)
                }
            },
            onUnavailable: { [weak self] message in
                Task { @MainActor in
                    self?.handleUnavailableListening(message, for: page)
                }
            }
        )
    }

    private func handleTranscript(_ transcript: String, for page: StoryPage) {
        guard currentPage?.id == page.id else { return }

        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedTranscript.isEmpty else {
            handleUnavailableListening(TeacherResponses.responseSpeechUnclear(), for: page)
            return
        }

        liveTranscript = cleanedTranscript
        bubbleText = TeacherResponses.responseThinking()
        isThinking = true
        refreshCharacterMode()

        Task {
            let interaction = StoryInteractionFactory.resolvedInteraction(for: page)
            let attemptCount = self.answerAttempts[page.id] ?? 0
            let plan = await aiTeacherService.planTurn(
                page: page,
                childUtterance: cleanedTranscript,
                sessionProfile: self.sessionProfile,
                attemptCount: attemptCount
            )

            await MainActor.run {
                self.isThinking = false
                self.refreshCharacterMode()
                self.sessionProfile.record(utterance: cleanedTranscript, plan: plan)
                self.deliverTurnPlan(plan, for: page, interaction: interaction)
            }
        }
    }

    private func handleUnavailableListening(_ message: String, for page: StoryPage) {
        guard currentPage?.id == page.id else { return }

        let listeningSource = activeListeningSource
        let shouldResumeNarration = shouldResumeNarrationAfterListening
        activeListeningSource = .prompt
        shouldResumeNarrationAfterListening = false
        isThinking = false
        refreshCharacterMode()

        if listeningSource == .ambientMonitor, shouldSilentlyIgnoreAmbientMiss(message) {
            bubbleText = TeacherResponses.responseHandsFreePrompt()

            if shouldResumeNarration {
                narrationManager.resume()
            } else if !isMicrophoneMuted {
                armHandsFreeMonitor(for: page, after: 0.35)
            }
            return
        }

        bubbleText = message

        armHandsFreeMonitor(for: page, after: 0.1)
        narrationManager.speak(message, style: .feedback) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.currentPage?.id == page.id else { return }

                let interaction = StoryInteractionFactory.resolvedInteraction(for: page)
                self.bubbleText = interaction?.prompt ?? TeacherResponses.responseHandsFreePrompt()

                guard !self.isMicrophoneMuted else { return }
                guard self.shouldRetryListening(after: message) else { return }

                if interaction != nil {
                    self.armHandsFreeMonitor(for: page, after: 0.15)
                } else {
                    self.scheduleAutoAdvance(for: page.id, after: 7.0)
                    self.armHandsFreeMonitor(for: page, after: 0.15)
                }
            }
        }
    }

    private func deliverTurnPlan(
        _ plan: InkyduTurnPlan,
        for page: StoryPage,
        interaction: StoryInteraction?
    ) {
        guard currentPage?.id == page.id else { return }

        bubbleText = personalizedReply(from: plan)

        if plan.isCorrect {
            triggerCelebration()
            answerAttempts[page.id] = 0
        }

        armHandsFreeMonitor(for: page, after: 0.1)
        narrationManager.speak(bubbleText, style: .feedback) { [weak self] in
            Task { @MainActor in
                self?.afterTurnPlan(plan, for: page, interaction: interaction)
            }
        }
    }

    private func afterTurnPlan(
        _ plan: InkyduTurnPlan,
        for page: StoryPage,
        interaction: StoryInteraction?
    ) {
        guard currentPage?.id == page.id else { return }

        let shouldResumeNarration = shouldResumeNarrationAfterListening
        activeListeningSource = .prompt
        shouldResumeNarrationAfterListening = false

        if plan.shouldRepeatPage {
            replayCurrentPage()
            return
        }

        if plan.wantsFollowUpQuestion, let followUpQuestion = plan.followUpQuestion {
            bubbleText = followUpQuestion

            armHandsFreeMonitor(for: page, after: 0.1)
            narrationManager.speak(followUpQuestion, style: .prompt) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.currentPage?.id == page.id else { return }

                    if self.isMicrophoneMuted {
                        self.scheduleAutoAdvance(for: page.id, after: 2.0)
                    } else {
                        self.beginListening(for: page, source: .prompt)
                    }
                }
            }
            return
        }

        if shouldResumeNarration, interaction == nil {
            bubbleText = TeacherResponses.responseHandsFreePrompt()
            narrationManager.resume()
            return
        }

        if plan.shouldAdvance {
            scheduleAutoAdvance(for: page.id, after: 1.4)

            if interaction == nil, !isMicrophoneMuted {
                armHandsFreeMonitor(for: page, after: 0.1)
            }
            return
        }

        if interaction?.expectedAnswer != nil {
            let attemptCount = (answerAttempts[page.id] ?? 0) + 1
            answerAttempts[page.id] = attemptCount

            if plan.teachingMove == .revealAnswer || attemptCount >= maxAnswerAttempts {
                let revealText = interaction?.answerReveal ?? TeacherResponses.responseRevealAnswer()
                bubbleText = revealText

                armHandsFreeMonitor(for: page, after: 0.1)
                narrationManager.speak(revealText, style: .feedback) { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        guard self.currentPage?.id == page.id else { return }
                        self.scheduleAutoAdvance(for: page.id, after: 1.4)
                    }
                }
                return
            }

            bubbleText = interaction?.prompt ?? TeacherResponses.responseHandsFreePrompt()

            if isMicrophoneMuted {
                scheduleAutoAdvance(for: page.id, after: 2.0)
            } else {
                retryListeningTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled else { return }
                    guard self.currentPage?.id == page.id else { return }
                    self.beginListening(for: page, source: .prompt)
                }
            }
            return
        }

        if isMicrophoneMuted {
            scheduleAutoAdvance(for: page.id, after: 2.0)
        } else {
            scheduleAutoAdvance(for: page.id, after: 5.0)
            armHandsFreeMonitor(for: page, after: 0.1)
        }
    }

    private func stopListeningEarly() {
        guard let page = currentPage else { return }

        micManager.stopListeningEarly(
            onTranscript: { [weak self] transcript in
                Task { @MainActor in
                    self?.handleTranscript(transcript, for: page)
                }
            },
            onUnavailable: { [weak self] message in
                Task { @MainActor in
                    self?.handleUnavailableListening(message, for: page)
                }
            }
        )
    }

    private func armHandsFreeMonitor(for page: StoryPage, after delay: Double = 0.35) {
        speechMonitorArmTask?.cancel()

        speechMonitorArmTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self.currentPage?.id == page.id else { return }
            guard !self.micManager.isListening else { return }
            guard !self.isThinking else { return }
            guard !self.isMicrophoneMuted else { return }

            self.micManager.startSpeechMonitor(
                onSpeechDetected: { [weak self] in
                    Task { @MainActor in
                        self?.handleHandsFreeSpeechDetected(for: page)
                    }
                },
                onUnavailable: { _ in }
            )
        }
    }

    private func handleHandsFreeSpeechDetected(for page: StoryPage) {
        guard currentPage?.id == page.id else { return }
        guard !isListening, !isThinking else { return }
        guard !isMicrophoneMuted else { return }

        beginListening(for: page, source: .ambientMonitor)
    }

    private func personalizedReply(from plan: InkyduTurnPlan) -> String {
        let reply = plan.spokenReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            return TeacherResponses.responseGenericConversation()
        }

        let knownName = plan.extractedChildName ?? sessionProfile.childName
        guard let knownName, plan.isCorrect, !reply.lowercased().contains(knownName.lowercased()) else {
            return reply
        }

        return "\(knownName), \(reply)"
    }

    private func shouldRetryListening(after message: String) -> Bool {
        let normalized = message.lowercased()

        let blockingPhrases = [
            "speech recognition is turned off",
            "microphone access is turned off",
            "no microphone input is available",
            "i can't listen right now"
        ]

        return !blockingPhrases.contains { normalized.contains($0) }
    }

    private func shouldSilentlyIgnoreAmbientMiss(_ message: String) -> Bool {
        let normalized = message.lowercased()

        let retrySilentlyPhrases = [
            "i didn't quite hear that",
            "that was a little hard to hear",
            "can you try that one more time",
            "could you say that again"
        ]

        return retrySilentlyPhrases.contains { normalized.contains($0) }
    }

    private func resumeListeningFlowIfNeeded() {
        guard appStage == .story else { return }
        guard !showReadyPopup else { return }
        guard !isThinking else { return }
        guard let page = currentPage else { return }

        if let interaction = StoryInteractionFactory.resolvedInteraction(for: page),
           !narrationManager.isSpeaking,
           !narrationManager.isPaused,
           !micManager.isListening {
            cancelPendingTasks()
            bubbleText = interaction.prompt

            armHandsFreeMonitor(for: page, after: 0.1)
            narrationManager.speak(interaction.prompt, style: .prompt) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.currentPage?.id == page.id else { return }
                    guard !self.isMicrophoneMuted else { return }

                    if interaction.autoListen {
                        self.beginListening(for: page, source: .prompt)
                    }
                }
            }
        } else {
            armHandsFreeMonitor(for: page, after: narrationManager.isSpeaking ? 0.4 : 0.1)
        }
    }

    private func scheduleAutoAdvance(for pageID: String, after delay: Double) {
        cancelPendingTasks()

        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard self.currentPage?.id == pageID else { return }
            guard !self.narrationManager.isSpeaking else { return }
            guard !self.micManager.isListening else { return }
            self.moveToNextPage()
        }
    }

    private func triggerCelebration() {
        characterResetTask?.cancel()
        isCelebrating = true
        characterMode = .celebrating

        characterResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self.isCelebrating = false
            self.refreshCharacterMode()
        }
    }

    private func refreshCharacterMode() {
        if isCelebrating {
            return
        }

        if isThinking {
            characterMode = .thinking
        } else if micManager.isListening {
            characterMode = .listening
        } else if narrationManager.isSpeaking && !narrationManager.isPaused {
            characterMode = .speaking
        } else {
            characterMode = .idle
        }
    }

    private func stopAllAudioAndTasks() {
        cancelPendingTasks()
        micManager.stopListening()
        narrationManager.stop()
        activeListeningSource = .prompt
        shouldResumeNarrationAfterListening = false
        isThinking = false
        isCelebrating = false
        refreshCharacterMode()
    }

    private func cancelPendingTasks() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil

        retryListeningTask?.cancel()
        retryListeningTask = nil

        characterResetTask?.cancel()
        characterResetTask = nil

        speechMonitorArmTask?.cancel()
        speechMonitorArmTask = nil
    }
}
