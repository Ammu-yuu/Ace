import SwiftUI

/// Closures the window controller wires to the roaming engine / talk loop.
struct PetActions {
    var onTap: () -> Void = {}
    var onGrabStart: () -> Void = {}
    var onGrabMove: (CGSize) -> Void = { _ in }
    var onGrabEnd: () -> Void = {}
    var onQuit: () -> Void = {}
}

/// The pet: a speech bubble (only while talking) above a bottom-anchored
/// character you can **tap to talk** and **drag to move**. Right-click for a menu.
struct PetView: View {
    @ObservedObject var animator: PetAnimator
    @ObservedObject var vm: PetViewModel
    let actions: PetActions

    @State private var dragging = false
    private let dragThreshold: CGFloat = 6

    var body: some View {
        VStack(spacing: 6) {
            if vm.bubbleVisible {
                SpeechBubble(userText: vm.userText, reply: vm.replyText, status: vm.statusLine)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            character
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.2), value: vm.bubbleVisible)
    }

    @ViewBuilder
    private var character: some View {
        sprite
            .frame(width: 140, height: 140)
            .scaleEffect(x: animator.flipped ? -1 : 1, y: 1)   // face travel direction
            .contentShape(Rectangle())
            .gesture(dragOrTap)
            .contextMenu {
                Button(vm.isListening ? "Stop & send" : "Talk to Ace") { actions.onTap() }
                Divider()
                Button("Quit Ace") { actions.onQuit() }
            }
    }

    @ViewBuilder
    private var sprite: some View {
        if let image = animator.currentImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            PlaceholderPet()
        }
    }

    /// One gesture that distinguishes a tap (talk) from a drag (move).
    private var dragOrTap: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance > dragThreshold else { return }
                if !dragging {
                    dragging = true
                    actions.onGrabStart()
                }
                actions.onGrabMove(value.translation)
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if dragging {
                    dragging = false
                    actions.onGrabEnd()
                } else if distance <= dragThreshold {
                    actions.onTap()
                }
            }
    }
}

// MARK: - Speech bubble

private struct SpeechBubble: View {
    let userText: String
    let reply: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !userText.isEmpty {
                Text("You: \(userText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            if !status.isEmpty {
                Label(status, systemImage: "waveform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(reply)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .frame(width: 220)
    }
}

// MARK: - Placeholder (used when no sprites are present)

private struct PlaceholderPet: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.55, blue: 0.25),
                                 Color(red: 0.95, green: 0.35, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            Text("🐾").font(.system(size: 60))
        }
    }
}
