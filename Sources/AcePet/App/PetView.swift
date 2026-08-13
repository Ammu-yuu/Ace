import SwiftUI

/// The full pet UI: a speech bubble on top, the animated character in the
/// middle, and a push-to-talk mic button at the bottom.
struct PetView: View {
    @ObservedObject var animator: PetAnimator
    @ObservedObject var vm: PetViewModel
    @State private var bob = false

    var body: some View {
        VStack(spacing: 8) {
            SpeechBubble(userText: vm.userText,
                         reply: vm.replyText,
                         status: vm.statusLine)

            character
                .offset(y: bob ? -6 : 0)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bob)

            MicButton(isListening: vm.isListening) {
                vm.micTapped()
            }
        }
        .padding(16)
        .onAppear { bob = true }
    }

    @ViewBuilder
    private var character: some View {
        if let image = animator.currentImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
        } else {
            PlaceholderPet()
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
        .frame(width: 240)
    }
}

// MARK: - Mic button

private struct MicButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(isListening ? Color.red : Color.accentColor)
                )
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .help(isListening ? "Stop and send" : "Push to talk")
    }
}

// MARK: - Placeholder (used when no sprite sheet is present)

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
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            Text("🐾").font(.system(size: 64))
        }
    }
}
