import SwiftUI

struct ContentView: View {
    enum AppStage {
        case launch
        case library
        case story
        case end
    }

    @StateObject private var controller = StoryController()
    @StateObject private var micManager = MicManager()
    @StateObject private var narrationManager = NarrationManager()

    @State private var appStage: AppStage = .launch
    @State private var overlayMode: OverlayMode = .hidden
    @State private var inputEnabled = false
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var questionDelayTask: Task<Void, Never>?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var showReadyPopup = false
    @State private var isMicEnabled = true

    private let questionDelaySeconds: Double = 2.2
    private let feedbackDisplaySeconds: Double = 3.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch appStage {
                case .launch:
                    LaunchScreen {
                        appStage = .library
                    }
                    .onAppear {
                        OrientationLock.set(.portrait)
                    }

                case .library:
                    LibraryScreen(
                        onBookTap: {
                            controller.loadStoryJSON(named: "story")
                            controller.startStory()
                            overlayMode = .hidden
                            inputEnabled = false
                            isMicEnabled = true
                            showReadyPopup = true
                            appStage = .story
                        }
                    )
                    .onAppear {
                        OrientationLock.set(.portrait)
                    }

                case .story:
                    if let page = controller.currentPage {
                        StoryScreen(
                            page: page,
                            teacherLine: controller.teacherMessage,
                            speechStatus: storySpeechStatus,
                            isListening: isMicEnabled,
                            overlayMode: overlayMode,
                            canGoBack: controller.canGoBack,
                            canGoForward: controller.canGoForward,
                            inputEnabled: inputEnabled,
                            isNarrationActive: narrationManager.isSpeaking || narrationManager.isPaused,
                            isNarrationPaused: narrationManager.isPaused,
                            feedbackTitle: feedbackOverlayTitle,
                            showReadyPopup: showReadyPopup,
                            onAnswerTap: { selected in
                                handleSubmittedAnswer(selected)
                            },
                            onContinueTap: {
                                guard inputEnabled else { return }
                                moveToNextPage()
                            },
                            onRepeatTap: {
                                replayCurrentPage()
                            },
                            onBackTap: {
                                moveToPreviousPage()
                            },
                            onForwardTap: {
                                announceAndMoveToNextPage()
                            },
                            onPausePlayTap: {
                                togglePausePlay()
                            },
                            onReadyTap: {
                                showReadyPopup = false
                                startPageFlowForCurrentPage()
                            },
                            onHomeTap: {
                                returnToLibrary()
                            },
                            onMicToggleTap: {
                                toggleListeningForCurrentQuestion()
                            },
                            onQuestionCloseTap: {
                                closeQuestionOverlay()
                            }
                        )
                        .id(page.page_id)
                        .task(id: page.page_id) {
                            if !showReadyPopup {
                                startPageFlow(for: page)
                            }
                        }
                        .onAppear {
                            OrientationLock.set(.landscape)
                        }
                    }

                case .end:
                    EndScreen {
                        appStage = .library
                    }
                    .onAppear {
                        OrientationLock.set(.portrait)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var feedbackOverlayTitle: String {
        switch overlayMode {
        case .correctFeedback:
            return "Correct!"
        case .incorrectFeedback:
            return "Hmm let's try again!"
        case .hidden, .question:
            return controller.feedbackTitle
        }
    }

    private var storySpeechStatus: String {
        if !isMicEnabled {
            return "Microphone off"
        }

        if micManager.isListening {
            return "Listening..."
        }

        return controller.lastHeardSpeech
    }

    private func startPageFlowForCurrentPage() {
        guard let page = controller.currentPage else { return }
        startPageFlow(for: page)
    }

    private func startPageFlow(for page: StoryPage) {
        cancelPendingTasks()
        overlayMode = .hidden
        inputEnabled = false
        if isMicEnabled {
            beginAutomaticListening()
        } else {
            micManager.stopListening()
        }
        narrationManager.stop()
        controller.prepareCurrentPageForDisplay()

        narrationManager.speak(page.narration) {
            scheduleAutoAdvance(for: page.page_id)
            scheduleQuestionPrompt(for: page)
        }
    }

    private func replayCurrentPage() {
        guard let page = controller.currentPage else { return }

        cancelPendingTasks()
        overlayMode = .hidden
        inputEnabled = false
        if isMicEnabled {
            beginAutomaticListening()
        } else {
            micManager.stopListening()
        }
        narrationManager.stop()
        controller.prepareCurrentPageForDisplay()

        narrationManager.speak(page.narration) {
            scheduleAutoAdvance(for: page.page_id)
            scheduleQuestionPrompt(for: page)
        }
    }

    private func scheduleQuestionPrompt(for page: StoryPage) {
        guard page.question?.isEmpty == false else {
            inputEnabled = true
            return
        }

        questionDelayTask?.cancel()
        questionDelayTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(questionDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                showQuestion(for: page)
            }
        }
    }

    private func showQuestion(for page: StoryPage) {
        overlayMode = .question
        controller.clearFeedback()
        inputEnabled = true

        let optionsText = (page.choices ?? [])
            .enumerated()
            .map { index, choice in
                "Option \(index + 1): \(choice)."
            }
            .joined(separator: " ")

        let spokenText = [
            page.question ?? "",
            optionsText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        narrationManager.speak(spokenText)
    }

    private func handleSubmittedAnswer(_ selected: String) {
        guard inputEnabled else { return }

        cancelPendingTasks()
        micManager.stopListening()
        narrationManager.stop()
        inputEnabled = false

        controller.handleAnswer(selected)

        if controller.didAnswerCurrentPageCorrectly {
            overlayMode = .correctFeedback
            narrationManager.speak(controller.teacherMessage)
            handleCorrectFeedbackFlow()
        } else {
            overlayMode = .incorrectFeedback
            narrationManager.speak(controller.teacherMessage)
            handleIncorrectFeedbackFlow()
        }
    }

    private func handleIncorrectFeedbackFlow() {
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(feedbackDisplaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                overlayMode = .question
                inputEnabled = true
                if isMicEnabled {
                    beginAutomaticListening()
                }
            }
        }
    }

    private func handleCorrectFeedbackFlow() {
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(feedbackDisplaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                overlayMode = .hidden
                inputEnabled = false
                if isMicEnabled {
                    beginAutomaticListening()
                }
                scheduleAutoAdvance()
            }
        }
    }

    private func togglePausePlay() {
        if narrationManager.isPaused {
            narrationManager.resume()
        } else if narrationManager.isSpeaking {
            narrationManager.pause()
        } else {
            replayCurrentPage()
        }
    }

    private func toggleListeningForCurrentQuestion() {
        guard appStage == .story else { return }

        isMicEnabled.toggle()

        if !isMicEnabled {
            micManager.stopListening()
            controller.lastHeardSpeech = "Microphone off"
            return
        }

        beginAutomaticListening()
    }

    private func beginAutomaticListening() {
        guard isMicEnabled, appStage == .story else { return }
        guard !micManager.isListening else { return }

        micManager.startListening(
            onReady: {
                controller.lastHeardSpeech = ""
            },
            onPartialTranscript: { transcript in
                handleLiveSpeechWhileNarrating(transcript)
            },
            onTranscript: { transcript in
                handleLiveTranscript(transcript)
            },
            onUnavailable: { message in
                controller.lastHeardSpeech = message
                if isMicEnabled && appStage == .story {
                    beginAutomaticListening()
                }
            }
        )
    }

    private func handleLiveSpeechWhileNarrating(_ transcript: String) {
        guard isMicEnabled, !transcript.isEmpty else { return }

        controller.lastHeardSpeech = transcript

        if narrationManager.isSpeaking {
            narrationManager.stop()
            autoAdvanceTask?.cancel()
            questionDelayTask?.cancel()

            if let page = controller.currentPage, page.question?.isEmpty == false {
                overlayMode = .question
                inputEnabled = true
            }
        }
    }

    private func handleLiveTranscript(_ transcript: String) {
        guard isMicEnabled else { return }
        controller.lastHeardSpeech = transcript

        guard let page = controller.currentPage else { return }

        if page.correct_answer != nil {
            if overlayMode != .question {
                overlayMode = .question
            }
            inputEnabled = true
            handleSubmittedAnswer(transcript)
            return
        }

        if !transcript.isEmpty {
            narrationManager.stop()
            controller.teacherMessage = "I heard you."
            overlayMode = .incorrectFeedback

            feedbackTask?.cancel()
            feedbackTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(feedbackDisplaySeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    overlayMode = .hidden
                    if isMicEnabled && appStage == .story {
                        beginAutomaticListening()
                    }
                }
            }
        }
    }

    private func scheduleAutoAdvance(for pageID: String? = nil) {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard appStage == .story else { return }
                if let pageID, controller.currentPage?.page_id != pageID { return }

                if pageID != nil || controller.didAnswerCurrentPageCorrectly {
                    moveToNextPage()
                }
            }
        }
    }

    private func moveToNextPage() {
        cancelPendingTasks()
        narrationManager.stop()
        if !isMicEnabled {
            micManager.stopListening()
        }
        overlayMode = .hidden
        inputEnabled = false

        if controller.currentPageIndex == controller.pages.count - 1 {
            appStage = .end
        } else {
            controller.goToNextPage()
        }
    }

    private func announceAndMoveToNextPage() {
        cancelPendingTasks()
        narrationManager.stop()
        if !isMicEnabled {
            micManager.stopListening()
        }
        overlayMode = .hidden
        inputEnabled = false

        narrationManager.speak("next page") {
            moveToNextPage()
        }
    }

    private func moveToPreviousPage() {
        cancelPendingTasks()
        narrationManager.stop()
        if !isMicEnabled {
            micManager.stopListening()
        }
        overlayMode = .hidden
        inputEnabled = false
        controller.goToPreviousPage()
    }

    private func returnToLibrary() {
        cancelPendingTasks()
        narrationManager.stop()
        micManager.stopListening()
        overlayMode = .hidden
        inputEnabled = false
        isMicEnabled = true
        showReadyPopup = false
        appStage = .library
    }

    private func closeQuestionOverlay() {
        micManager.stopListening()
        controller.clearFeedback()
        overlayMode = .hidden
        inputEnabled = false
    }

    private func cancelPendingTasks() {
        autoAdvanceTask?.cancel()
        questionDelayTask?.cancel()
        feedbackTask?.cancel()
    }
}

enum OverlayMode {
    case hidden
    case question
    case correctFeedback
    case incorrectFeedback
}

struct LaunchScreen: View {
    let onStart: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("inkyduLaunch")
                    .resizable()
                    .scaledToFill()
                    .offset(x: -20)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    Button("My Library") {
                        onStart()
                    }
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.blue.opacity(0.82))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.7), lineWidth: 2)
                    )
                    .shadow(radius: 8)
                    .padding(.bottom, geometry.size.height * 0.18)
                }
            }
        }
    }
}

struct LibraryScreen: View {
    let onBookTap: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.91, blue: 1.0),
                    Color(red: 0.90, green: 0.98, blue: 0.86),
                    Color(red: 1.0, green: 0.95, blue: 0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("My Library")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color(red: 0.23, green: 0.42, blue: 0.86))
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                Spacer()

                LibraryShelf(bookTap: onBookTap)

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
    }
}

struct LibraryShelf: View {
    let bookTap: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            shelfRow(active: true)
            shelfRow(active: false)
            shelfRow(active: false)
            shelfRow(active: false)
            shelfRow(active: false)
        }
    }

    @ViewBuilder
    private func shelfRow(active: Bool) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.73, green: 0.47, blue: 0.23),
                            Color(red: 0.56, green: 0.33, blue: 0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 18)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 4)

            HStack(spacing: 24) {
                if active {
                    Button(action: bookTap) {
                        VStack(spacing: 10) {
                            Image("page1")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 132, height: 84)
                                .offset(x: 10)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                                )
                                .shadow(radius: 8)

                            Text("Bunnyfield VS McFluff")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color(red: 0.21, green: 0.39, blue: 0.82))
                        }
                        .frame(width: 132)
                    }
                    .buttonStyle(.plain)

                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 92, height: 68)
                    }
                } else {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 92, height: 68)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EndScreen: View {
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("The End!")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Button("My Library", action: onRestart)
                    .font(.title2.bold())
                    .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
        }
    }
}

struct StoryScreen: View {
    let page: StoryPage
    let teacherLine: String
    let speechStatus: String
    let isListening: Bool
    let overlayMode: OverlayMode
    let canGoBack: Bool
    let canGoForward: Bool
    let inputEnabled: Bool
    let isNarrationActive: Bool
    let isNarrationPaused: Bool
    let feedbackTitle: String
    let showReadyPopup: Bool
    let onAnswerTap: (String) -> Void
    let onContinueTap: () -> Void
    let onRepeatTap: () -> Void
    let onBackTap: () -> Void
    let onForwardTap: () -> Void
    let onPausePlayTap: () -> Void
    let onReadyTap: () -> Void
    let onHomeTap: () -> Void
    let onMicToggleTap: () -> Void
    let onQuestionCloseTap: () -> Void

    private var pausePlayIconName: String {
        if isNarrationPaused {
            return "play.fill"
        }

        return isNarrationActive ? "pause.fill" : "play.fill"
    }

    private var micIconName: String {
        isListening ? "mic.fill" : "mic.slash.fill"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.ignoresSafeArea()

                if let imageName = page.imageName, !imageName.isEmpty {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea()
                }

                VStack {
                    HStack {
                        HomeButton(action: onHomeTap)
                            .padding(.leading, 38)
                            .padding(.top, 24)

                        Spacer()

                        MicToggleButton(
                            systemName: micIconName,
                            action: onMicToggleTap
                        )
                        .padding(.trailing, 38)
                        .padding(.top, 24)
                    }

                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .zIndex(1)

                if canGoBack {
                    HStack {
                        ArrowButton(
                            systemName: "chevron.left",
                            isEnabled: true,
                            action: onBackTap
                        )
                        .padding(.leading, 52)

                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                if canGoForward {
                    HStack {
                        Spacer()

                        ArrowButton(
                            systemName: "chevron.right",
                            isEnabled: true,
                            action: onForwardTap
                        )
                        .padding(.trailing, 52)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                if !showReadyPopup {
                    VStack {
                        Spacer()

                        HStack(alignment: .bottom) {
                            Image("inkyduMascot")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 228, height: 228)
                                .padding(.leading, 18)

                            Spacer()
                        }
                        .padding(.bottom, 10)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                VStack {
                    Spacer()

                    Button(action: onPausePlayTap) {
                        OutlinedSymbol(
                            systemName: pausePlayIconName,
                            size: 20,
                            padding: 10
                        )
                    }
                    .padding(.bottom, 42)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .zIndex(1)

                if showReadyPopup {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .zIndex(8)

                    ReadyPopup(onReadyTap: onReadyTap)
                        .padding(.horizontal, 120)
                        .zIndex(9)
                } else if overlayMode != .hidden {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .zIndex(8)

                    switch overlayMode {
                    case .question:
                        QuestionOverlay(
                            page: page,
                            teacherLine: teacherLine,
                            speechStatus: speechStatus,
                            isListening: isListening,
                            inputEnabled: inputEnabled,
                            onAnswerTap: onAnswerTap,
                            onContinueTap: onContinueTap,
                            onRepeatTap: onRepeatTap,
                            onCloseTap: onQuestionCloseTap
                        )
                        .padding(.horizontal, 54)
                        .padding(.vertical, 24)
                        .zIndex(9)

                    case .correctFeedback:
                        MascotFeedbackOverlay(
                            title: feedbackTitle,
                            imageName: "inkyduHappy",
                            titleColor: .green
                        )
                        .padding(.horizontal, 120)
                        .padding(.vertical, 70)
                        .zIndex(9)

                    case .incorrectFeedback:
                        MascotFeedbackOverlay(
                            title: feedbackTitle,
                            imageName: "inkyduQuestion",
                            titleColor: .primary
                        )
                        .padding(.horizontal, 120)
                        .padding(.vertical, 70)
                        .zIndex(9)

                    case .hidden:
                        EmptyView()
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}

struct ReadyPopup: View {
    let onReadyTap: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image("inkyduMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)

            Text("Ready to Read?")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)

            Button("Let's Go!") {
                onReadyTap()
            }
            .font(.title3.bold())
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .shadow(radius: 18)
    }
}

struct QuestionOverlay: View {
    let page: StoryPage
    let teacherLine: String
    let speechStatus: String
    let isListening: Bool
    let inputEnabled: Bool
    let onAnswerTap: (String) -> Void
    let onContinueTap: () -> Void
    let onRepeatTap: () -> Void
    let onCloseTap: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()

                Button(action: onCloseTap) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                }
            }

            Text(page.question ?? "")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)

            if let choices = page.choices, !choices.isEmpty {
                ForEach(choices, id: \.self) { choice in
                    Button(choice) {
                        onAnswerTap(choice)
                    }
                    .disabled(!inputEnabled)
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(inputEnabled ? Color.blue.opacity(0.10) : Color.gray.opacity(0.18))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            } else {
                Button("Continue") {
                    onContinueTap()
                }
                .disabled(!inputEnabled)
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(inputEnabled ? Color.blue.opacity(0.10) : Color.gray.opacity(0.18))
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Button("Read Page Again") {
                onRepeatTap()
            }
            .font(.headline)
            .foregroundStyle(.blue)

            if !teacherLine.isEmpty {
                Text(teacherLine)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.blue)
                    .padding(.top, 4)
            }

            if !speechStatus.isEmpty {
                Text(speechStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: 700)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(radius: 18)
    }
}

struct MascotFeedbackOverlay: View {
    let title: String
    let imageName: String
    let titleColor: Color

    var body: some View {
        VStack(spacing: 18) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(titleColor)
        }
        .padding(28)
        .frame(maxWidth: 520)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .shadow(radius: 20)
    }
}

struct ArrowButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OutlinedSymbol(
                systemName: systemName,
                size: 28,
                padding: 6
            )
        }
        .disabled(!isEnabled)
    }
}

struct HomeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OutlinedSymbol(
                systemName: "house.fill",
                size: 24,
                padding: 4
            )
        }
    }
}

struct MicToggleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OutlinedSymbol(
                systemName: systemName,
                size: 24,
                padding: 4
            )
        }
    }
}

struct OutlinedSymbol: View {
    let systemName: String
    let size: CGFloat
    let padding: CGFloat

    var body: some View {
        ZStack {
            symbol(color: .black, x: -0.6, y: 0)
            symbol(color: .black, x: 0.6, y: 0)
            symbol(color: .black, x: 0, y: -0.6)
            symbol(color: .black, x: 0, y: 0.6)
            symbol(color: .white, x: 0, y: 0)
        }
        .padding(padding)
    }

    private func symbol(color: Color, x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .offset(x: x, y: y)
    }
}

#Preview {
    ContentView()
}
