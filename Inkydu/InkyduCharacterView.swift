import SwiftUI

enum PenguinAnimationMode: Equatable {
    case idle
    case speaking
    case listening
    case thinking
    case celebrating
}

struct InkyduCharacterView: View {
    let mode: PenguinAnimationMode
    let isMouthOpen: Bool
    let animateEntrance: Bool

    @State private var isPulseExpanded = false
    @State private var isCelebrating = false
    @State private var xOffset: CGFloat = -140

    var body: some View {
        ZStack {
            if mode == .listening {
                listeningRings
            }

            if mode == .celebrating {
                celebrationConfetti
            }

            Ellipse()
                .fill(Color.black.opacity(0.15))
                .frame(width: 138, height: 24)
                .offset(y: 84)
                .scaleEffect(mode == .celebrating ? 0.78 : 1.0)

            Image(currentImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .scaleEffect(scaleEffect)
                .rotationEffect(.degrees(rotationDegrees))
                .offset(x: xOffset, y: verticalOffset)
                .overlay(alignment: .topTrailing) {
                    if mode == .thinking {
                        ThinkingDots()
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .frame(width: 260, height: 260)
        .onAppear {
            withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) {
                isPulseExpanded = true
            }

            // slide in from the left on first appearance
            if animateEntrance {
                xOffset = -140
                withAnimation(.interpolatingSpring(stiffness: 130, damping: 15)) {
                    xOffset = 0
                }
            } else {
                xOffset = 0
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .celebrating {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.45).repeatForever(autoreverses: true)) {
                    isCelebrating = true
                }
            } else {
                isCelebrating = false
            }
        }
    }

    private var currentImageName: String {
        switch mode {
        case .speaking:
            return isMouthOpen ? "inkyduMouthOpen" : "inkyduMouthClosed"
        case .idle, .listening, .thinking, .celebrating:
            return "inkyduMouthClosed"
        }
    }

    private var scaleEffect: CGFloat {
        mode == .celebrating ? 1.06 : 1.0
    }

    private var verticalOffset: CGFloat {
        switch mode {
        case .celebrating:
            return isCelebrating ? -18 : 6
        default:
            return 0
        }
    }

    private var rotationDegrees: Double {
        switch mode {
        case .celebrating:
            return isCelebrating ? 4.0 : -4.0
        default:
            return 0
        }
    }

    // subtle pulsing rings when listening
    private var listeningRings: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(Color.blue.opacity(index == 0 ? 0.45 : 0.24), lineWidth: 8)
                    .frame(width: index == 0 ? 188 : 220, height: index == 0 ? 188 : 220)
                    .scaleEffect(isPulseExpanded ? 1.08 : 0.78)
                    .opacity(isPulseExpanded ? 0.12 : 0.45)
            }
        }
    }

    // simple confetti burst around the character
    private var celebrationConfetti: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(confettiColor(for: index))
                    .frame(width: 12, height: 12)
                    .offset(confettiOffset(for: index))
            }
        }
    }

    private func confettiColor(for index: Int) -> Color {
        let colors: [Color] = [.yellow, .mint, .blue, .orange, .pink, .green]
        return colors[index % colors.count]
    }

    private func confettiOffset(for index: Int) -> CGSize {
        let positions: [CGSize] = [
            CGSize(width: -84, height: -82),
            CGSize(width: -48, height: -110),
            CGSize(width: -4, height: -92),
            CGSize(width: 42, height: -116),
            CGSize(width: 78, height: -86),
            CGSize(width: 18, height: -130)
        ]

        let base = positions[index % positions.count]
        return isCelebrating
            ? CGSize(width: base.width, height: base.height - 10)
            : CGSize(width: base.width, height: base.height + 6)
    }
}

private struct ThinkingDots: View {
    @State private var highlightedIndex = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == highlightedIndex ? Color.blue : Color.blue.opacity(0.28))
                    .frame(width: 10, height: 10)
                    .scaleEffect(index == highlightedIndex ? 1.05 : 0.82)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.92))
        .clipShape(Capsule())
        .task {
            while !Task.isCancelled {
                highlightedIndex = (highlightedIndex + 1) % 3
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.15).ignoresSafeArea()
        InkyduCharacterView(mode: .listening, isMouthOpen: false, animateEntrance: true)
    }
}
