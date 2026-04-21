// Renders a compact, flowing live transcript style for the overlay while dictation is active.
import SwiftUI

struct LiveTranscriptFlowView: View {
    let text: String

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(displayText)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.95))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .contentTransition(.opacity)
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: displayText)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.12),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }

            LivePulseView()
        }
        .padding(.vertical, 4)
    }

    private var displayText: String {
        Self.trailingExcerpt(from: text, maxCharacters: 94, maxWords: 15)
    }

    private static func trailingExcerpt(
        from text: String,
        maxCharacters: Int,
        maxWords: Int
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        let tailWords = words.suffix(maxWords).joined(separator: " ")
        guard tailWords.count > maxCharacters else { return tailWords }

        let tailCharacters = tailWords.suffix(maxCharacters)
        guard let firstVisibleSpace = tailCharacters.firstIndex(of: " ") else {
            return String(tailCharacters)
        }

        return String(tailCharacters[tailWords.index(after: firstVisibleSpace)...])
    }
}

private struct LivePulseView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.9)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            let scale = 0.84 + (phase * 0.26)
            let opacity = 0.35 + ((1 - phase) * 0.55)

            Circle()
                .fill(Color.accentColor.opacity(0.92))
                .frame(width: 11, height: 11)
                .scaleEffect(scale)
                .overlay {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.28), lineWidth: 5)
                        .scaleEffect(scale + 0.25)
                        .opacity(opacity * 0.45)
                }
                .shadow(color: Color.accentColor.opacity(0.35), radius: 8)
        }
        .frame(width: 18, height: 18)
        .padding(.bottom, 4)
    }
}
