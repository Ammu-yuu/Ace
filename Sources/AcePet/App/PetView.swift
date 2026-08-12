import SwiftUI

/// The pet itself. Renders the current animation frame when a sprite sheet is
/// present, otherwise an animated code-drawn placeholder. A gentle idle "bob"
/// gives it life in both modes.
struct PetView: View {
    @ObservedObject var animator: PetAnimator
    @State private var bob = false

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let image = animator.currentImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                } else {
                    PlaceholderPet()
                }
            }
            .offset(y: bob ? -6 : 0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: bob)

            Text("Ace")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(20)
        .onAppear { bob = true }
    }
}

/// Code-drawn stand-in used until you drop your own sprite sheet into `assets/`.
/// Nothing copyrighted ships in the app.
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
                .frame(width: 150, height: 150)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            Text("🐾")
                .font(.system(size: 68))
        }
    }
}
