// Captures audio buffers for push-to-talk dictation and resolves a final on-device speech result.
import AVFoundation
import Foundation
import Speech

final class DictationService: @unchecked Sendable {
    var onAudioLevel: (@Sendable (Double) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let contextualStrings: [String]

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var resultBridge: RecognitionBridge?
    private var isCapturing = false

    init(contextualStrings: [String]) {
        self.contextualStrings = contextualStrings
    }

    func warmUp(language: AppLanguage) async throws {
        guard let recognizer = SFSpeechRecognizer(locale: language.locale) else {
            throw DictationError.unsupportedLanguage
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw DictationError.onDeviceRecognitionUnavailable
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.channelCount > 0 else {
            throw DictationError.noInputDevice
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { _, _ in }
        audioEngine.prepare()
        try audioEngine.start()
        try? await Task.sleep(nanoseconds: 150_000_000)
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation

        let task = recognizer.recognitionTask(with: request) { _, _ in }
        request.endAudio()

        try? await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
    }

    func startCapture(language: AppLanguage) throws {
        guard !isCapturing else {
            throw DictationError.alreadyCapturing
        }

        guard let recognizer = SFSpeechRecognizer(locale: language.locale) else {
            throw DictationError.unsupportedLanguage
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw DictationError.onDeviceRecognitionUnavailable
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.channelCount > 0 else {
            throw DictationError.noInputDevice
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation

        let bridge = RecognitionBridge()
        let audioLevelHandler = onAudioLevel

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                bridge.deliver(.failure(error))
                return
            }

            guard let result, result.isFinal else { return }

            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if text.isEmpty {
                bridge.deliver(.failure(DictationError.noSpeechDetected))
            } else {
                bridge.deliver(.success(text))
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            request.append(buffer)
            audioLevelHandler?(Self.normalizedLevel(for: buffer))
        }

        speechRecognizer = recognizer
        recognitionRequest = request
        recognitionTask = task
        resultBridge = bridge
        isCapturing = true

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            cleanupRecognition(cancelTask: true)
            throw error
        }
    }

    func finishCapture() async throws -> String {
        guard isCapturing else {
            throw DictationError.notCapturing
        }

        guard
            let recognitionRequest,
            let resultBridge
        else {
            cleanupRecognition(cancelTask: true)
            throw DictationError.noCapturedAudio
        }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest.endAudio()
        isCapturing = false
        onAudioLevel?(0)

        do {
            let text = try await resultBridge.awaitResult(timeoutNanoseconds: 6_000_000_000)
            cleanupRecognition(cancelTask: false)
            return text
        } catch {
            cleanupRecognition(cancelTask: true)
            throw error
        }
    }

    private func cleanupRecognition(cancelTask: Bool) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        if cancelTask {
            recognitionTask?.cancel()
        }

        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        resultBridge = nil
        isCapturing = false
        onAudioLevel?(0)
    }

    private static func normalizedLevel(for buffer: AVAudioPCMBuffer) -> Double {
        guard
            let channelData = buffer.floatChannelData?[0]
        else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 0.000_01))
        return max(0, min(1, Double((db + 50) / 50)))
    }
}

private final class RecognitionBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<String, Error>?
    private var continuation: CheckedContinuation<String, Error>?

    func deliver(_ result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }

        guard storedResult == nil else { return }

        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            storedResult = result
        }
    }

    func awaitResult(timeoutNanoseconds: UInt64) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.waitForResult()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw DictationError.timeout
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private func waitForResult() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            if let storedResult {
                continuation.resume(with: storedResult)
            } else {
                self.continuation = continuation
            }
        }
    }
}

private enum DictationError: LocalizedError {
    case alreadyCapturing
    case notCapturing
    case noInputDevice
    case noCapturedAudio
    case unsupportedLanguage
    case onDeviceRecognitionUnavailable
    case noSpeechDetected
    case timeout

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "A dictation capture is already in progress."
        case .notCapturing:
            return "No dictation capture is currently running."
        case .noInputDevice:
            return "No microphone input device is available."
        case .noCapturedAudio:
            return "No audio was captured."
        case .unsupportedLanguage:
            return "This language is not available for local dictation."
        case .onDeviceRecognitionUnavailable:
            return "On-device dictation is not available for the selected language."
        case .noSpeechDetected:
            return "No speech was detected."
        case .timeout:
            return "Transcription timed out."
        }
    }
}
