import SwiftUI

struct OverlayView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.settings.selectedLanguage.shortCode)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                Text("·")
                    .foregroundStyle(.secondary)

                Text(model.overlayModeLabel)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Group {
                if model.dictationState == .listening {
                    AudioLevelMeterView(level: model.audioLevel)
                } else {
                    Text(model.overlayStatusText)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
