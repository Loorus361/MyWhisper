// Renders the floating overlay that reflects the current dictation state and audio level.
import SwiftUI

struct OverlayView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if model.dictationState == .listening {
                listeningBody
            } else {
                statusBody
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(width: 460)
        .background(overlayBackground)
        .overlay(overlayBorder)
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .shadow(color: .white.opacity(0.08), radius: 2, y: 1)
    }

    private var header: some View {
        HStack(spacing: 10) {
            overlayPill(title: model.settings.selectedLanguage.shortCode, emphasized: true)
            overlayPill(title: modeLabel, emphasized: false)

            Spacer(minLength: 0)

            Image(systemName: statusSymbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.12), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
                }
        }
    }

    private var listeningBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.liveTranscriptPreview.isEmpty {
                listeningPlaceholder
            } else {
                LiveTranscriptFlowView(text: model.liveTranscriptPreview)
            }

            AudioLevelMeterView(level: model.audioLevel)
        }
    }

    private var listeningPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listening")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.92))

            Text("Start speaking and the newest words will glide through here.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var statusBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.overlayStatusText)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(statusCaption)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var overlayBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.20),
                                .white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }

    private var overlayBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.30),
                        .white.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var modeLabel: String {
        switch model.dictationState {
        case .listening:
            return "Live"
        case .preparing:
            return "Preparing"
        case .processing:
            return "Finalizing"
        case .inserted:
            return "Inserted"
        case .error:
            return "Error"
        case .idle:
            return model.overlayModeLabel
        }
    }

    private var statusSymbolName: String {
        switch model.dictationState {
        case .listening:
            return "waveform.badge.mic"
        case .preparing:
            return "arrow.trianglehead.2.clockwise"
        case .processing:
            return "ellipsis.circle"
        case .inserted:
            return "checkmark"
        case .error:
            return "exclamationmark.triangle"
        case .idle:
            return "mic"
        }
    }

    private var statusCaption: String {
        switch model.dictationState {
        case .preparing:
            return "The selected language model is being prepared locally on this Mac."
        case .processing:
            return "The recording stopped. MyWhisper is polishing the final text before pasting."
        case .inserted:
            return "The final text has been inserted into the focused app."
        case .error:
            return "The dictation session ended early. Check the message above for the failing step."
        case .idle:
            return "Hold Control + Option + S to start dictation."
        case .listening:
            return ""
        }
    }

    @ViewBuilder
    private func overlayPill(title: String, emphasized: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: emphasized ? .semibold : .medium, design: .rounded))
            .foregroundStyle(
                emphasized
                    ? AnyShapeStyle(.primary.opacity(0.95))
                    : AnyShapeStyle(.secondary)
            )
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.white.opacity(emphasized ? 0.16 : 0.08), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(emphasized ? 0.18 : 0.10), lineWidth: 0.8)
            }
    }
}
