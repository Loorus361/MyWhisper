// Reads and requests the microphone, speech, and accessibility permissions used by the app.
import AVFoundation
import ApplicationServices
import Foundation
import Speech

final class PermissionService: @unchecked Sendable {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: microphonePermission(),
            speech: speechPermission(),
            accessibility: accessibilityPermission()
        )
    }

    func microphonePermission() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func speechPermission() -> PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func accessibilityPermission() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    func requestMicrophonePermission() async -> PermissionState {
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                continuation.resume(returning: allowed)
            }
        }

        return granted ? .granted : .denied
    }

    func requestSpeechPermission() async -> PermissionState {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func promptForAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
