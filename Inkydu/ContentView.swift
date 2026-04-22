import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = StoryExperienceViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch viewModel.appStage {
                case .launch:
                    LaunchScreen {
                        viewModel.openLibrary()
                    }
                    .onAppear {
                        OrientationLock.set(.portrait)
                    }

                case .library:
                    LibraryScreen {
                        viewModel.startBook(named: "story")
                    }
                    .onAppear {
                        OrientationLock.set(.portrait)
                    }

                case .story:
                    if let page = viewModel.currentPage {
                        StoryScreen(
                            page: page,
                            canGoBack: viewModel.canGoBack,
                            canGoForward: viewModel.canGoForward,
                            isNarrationActive: viewModel.isNarrationActive,
                            isNarrationPaused: viewModel.isNarrationPaused,
                            isNarrationMouthOpen: viewModel.isNarrationMouthOpen,
                            isListening: viewModel.isListening,
                            isThinking: viewModel.isThinking,
                            isMicrophoneMuted: viewModel.isMicrophoneMuted,
                            liveTranscript: viewModel.liveTranscript,
                            penguinMode: viewModel.characterMode,
                            showReadyPopup: viewModel.showReadyPopup,
                            onRepeatTap: {
                                viewModel.replayCurrentPage()
                            },
                            onBackTap: {
                                viewModel.moveToPreviousPage()
                            },
                            onForwardTap: {
                                viewModel.moveToNextPage()
                            },
                            onPausePlayTap: {
                                viewModel.togglePausePlay()
                            },
                            onMuteTap: {
                                viewModel.toggleMicrophoneMuted()
                            },
                            onReadyTap: {
                                viewModel.beginStoryPlayback()
                            },
                            onHomeTap: {
                                viewModel.returnToLibrary()
                            }
                        )
                        .id(page.id)
                        .onAppear {
                            OrientationLock.set(.landscape)
                        }
                    }

                case .end:
                    EndScreen {
                        viewModel.openLibrary()
                    }
                    .onAppear {
                        OrientationLock.set(.portrait)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
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

                Image("inkyduMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)

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
    let canGoBack: Bool
    let canGoForward: Bool
    let isNarrationActive: Bool
    let isNarrationPaused: Bool
    let isNarrationMouthOpen: Bool
    let isListening: Bool
    let isThinking: Bool
    let isMicrophoneMuted: Bool
    let liveTranscript: String
    let penguinMode: PenguinAnimationMode
    let showReadyPopup: Bool
    let onRepeatTap: () -> Void
    let onBackTap: () -> Void
    let onForwardTap: () -> Void
    let onPausePlayTap: () -> Void
    let onMuteTap: () -> Void
    let onReadyTap: () -> Void
    let onHomeTap: () -> Void

    private var pausePlayIconName: String {
        if isNarrationPaused {
            return "play.fill"
        }
        return isNarrationActive ? "pause.fill" : "play.fill"
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
                    }

                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .zIndex(2)

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
                    .zIndex(3)
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
                    .zIndex(3)
                }

                if !showReadyPopup {
                    VStack {
                        Spacer()

                        HStack(alignment: .bottom, spacing: 16) {
                            InkyduCharacterView(
                                mode: penguinMode,
                                isMouthOpen: isNarrationMouthOpen,
                                animateEntrance: page.pageID == "1"
                            )
                            .padding(.leading, 18)

                            Spacer(minLength: 20)
                        }
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 10) {
                                if isListening || isThinking || isMicrophoneMuted {
                                    StoryStatusBadge(
                                        isListening: isListening,
                                        isThinking: isThinking,
                                        isMicrophoneMuted: isMicrophoneMuted
                                    )
                                }

                                if shouldShowTranscript {
                                    TranscriptBadge(
                                        transcript: liveTranscript,
                                        isListening: isListening,
                                        isThinking: isThinking
                                    )
                                }
                            }
                            .padding(.leading, 166)
                            .padding(.bottom, 160)
                        }
                    }
                }

                VStack {
                    Spacer()

                    HStack(spacing: 18) {
                        Button(action: onRepeatTap) {
                            OutlinedSymbol(
                                systemName: "arrow.clockwise",
                                size: 20,
                                padding: 10
                            )
                        }

                        Button(action: onPausePlayTap) {
                            OutlinedSymbol(
                                systemName: pausePlayIconName,
                                size: 20,
                                padding: 10
                            )
                        }

                        Button(action: onMuteTap) {
                            OutlinedSymbol(
                                systemName: isMicrophoneMuted ? "mic.slash.fill" : "mic.fill",
                                size: 20,
                                padding: 10
                            )
                        }
                    }
                    .padding(.bottom, 42)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .zIndex(2)

                if showReadyPopup {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .zIndex(8)

                    ReadyPopup(onReadyTap: onReadyTap)
                        .padding(.horizontal, 120)
                        .zIndex(9)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private var shouldShowTranscript: Bool {
        let cleanedTranscript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanedTranscript.isEmpty
    }
}

struct ReadyPopup: View {
    let onReadyTap: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image("inkyduMouthClosed")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)

            Text("Ready to Read?")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)

            Text("Inkydu will read, listen, and talk with you.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.black.opacity(0.74))

            Button("Let's Go!") {
                onReadyTap()
            }
            .font(.title3.bold())
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: 460)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .shadow(radius: 18)
    }
}

struct StoryStatusBadge: View {
    let isListening: Bool
    let isThinking: Bool
    let isMicrophoneMuted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)

            Text(statusText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.94))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private var statusText: String {
        if isMicrophoneMuted {
            return "Mic Off"
        }

        if isListening {
            return "Listening"
        }

        return "Thinking"
    }

    private var iconName: String {
        if isMicrophoneMuted {
            return "mic.slash.fill"
        }

        if isListening {
            return "waveform"
        }

        return "sparkles"
    }

    private var iconColor: Color {
        if isMicrophoneMuted {
            return .red
        }

        if isListening {
            return .blue
        }

        return .mint
    }
}

struct TranscriptBadge: View {
    let transcript: String
    let isListening: Bool
    let isThinking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerText)
                .font(.caption.weight(.bold))
                .foregroundStyle(headerColor)

            Text(cleanedTranscript)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 280, alignment: .leading)
        .background(.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    private var cleanedTranscript: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var headerText: String {
        if isListening {
            return "Inkydu Heard"
        }

        if isThinking {
            return "Thinking About"
        }

        return "You Said"
    }

    private var headerColor: Color {
        if isListening {
            return .blue
        }

        if isThinking {
            return .mint
        }

        return .teal
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
            .frame(width: 64, height: 64)
        }
        .contentShape(Rectangle())
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
