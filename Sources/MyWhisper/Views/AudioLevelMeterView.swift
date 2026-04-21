// Renders the minimal live audio level meter used while the user is dictating.
import SwiftUI

struct AudioLevelMeterView: View {
    let level: Double

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<12, id: \.self) { index in
                let threshold = Double(index + 1) / 12
                let isActive = level >= threshold - 0.08
                let height = barHeight(for: index, isActive: isActive)

                Capsule(style: .continuous)
                    .fill(barFill(isActive: isActive, index: index))
                    .frame(width: 10, height: height)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(isActive ? 0.18 : 0.08), lineWidth: 0.8)
                    }
                    .shadow(
                        color: isActive ? Color.accentColor.opacity(0.18) : .clear,
                        radius: 8,
                        y: 2
                    )
                    .animation(.spring(response: 0.2, dampingFraction: 0.72), value: level)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barHeight(for index: Int, isActive: Bool) -> CGFloat {
        let baseHeights: [CGFloat] = [10, 14, 18, 23, 28, 33, 33, 28, 23, 18, 14, 10]
        let base = baseHeights[index]
        return isActive ? base : max(8, base * 0.42)
    }

    private func barFill(isActive: Bool, index: Int) -> some ShapeStyle {
        if isActive {
            let hueShift = Double(index) / 24
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.55 + hueShift * 0.18),
                        .white.opacity(0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(.white.opacity(0.16))
    }
}
