import SwiftUI

/// Placeholder pet for Step A.
///
/// This is deliberately simple: a rounded "body" with an emoji face and a name
/// tag, drawn entirely in code so we ship nothing copyrighted. Step B replaces
/// this with a real sprite-sheet animation renderer (idle frames), and later
/// steps add the speech bubble and listening / thinking / speaking states.
struct PetView: View {
    var body: some View {
        VStack(spacing: 10) {
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

            Text("Ace")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(20)
    }
}

#Preview {
    PetView()
}
