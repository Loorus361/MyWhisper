// Captures audio for push-to-talk dictation with Apple SpeechAnalyzer and returns finalized local text.
@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import OSLog
import Speech

final class DictationService: @unchecked Sendable {
    var onAudioLevel: (@Sendable (Double) -> Void)?
    var onLiveTranscript: (@Sendable (String) -> Void)?
    var onLanguageModelStatus: (@Sendable (LanguageModelStatus) -> Void)?

    private let contextualStrings: [String]
    private let stateLock = NSLock()
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "Dictation")

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var analysisContext: AnalysisContext?
    private var analysisFormat: AVAudioFormat?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Error>?
    private var submittedBufferCount: Int = 0
    private var submittedSampleCount: Int64 = 0
    private var finalSegments: [String] = []
    private var volatileSegment: String?
    private var pipelineError: Error?
    private var isCapturing = false
    private var languageStatusGeneration: UInt64 = 0

    init(contextualStrings: [String]) {
        self.contextualStrings = contextualStrings
    }

    func prepare(language: AppLanguage) async throws {
        let generation = nextLanguageStatusGeneration()
        emitLanguageModelStatus(.checking, generation: generation)
        logger.info("Preparing speech model for language \(language.localeIdentifier, privacy: .public)")

        do {
            let locale = try await resolvedLocale(for: language)
            let transcriber = Self.makeTranscriber(locale: locale)
            let modules: [any SpeechModule] = [transcriber]
            let status = await AssetInventory.status(forModules: modules)

            if status == .unsupported {
                throw DictationError.unsupportedLanguage(language.menuTitle)
            }

            if status == .installed {
                emitLanguageModelStatus(.ready, generation: generation)
                return
            }

            if status == .downloading {
                emitLanguageModelStatus(.downloading(progress: nil), generation: generation)
            }

            let request = try await AssetInventory.assetInstallationRequest(supporting: modules)

            guard let request else {
                let refreshedStatus = await AssetInventory.status(forModules: modules)
                guard refreshedStatus == .installed else {
                    throw DictationError.modelPreparationFailed(
                        "Apple speech assets are not available right now."
                    )
                }

                emitLanguageModelStatus(.ready, generation: generation)
                return
            }

            let progressTask = makeInstallationProgressTask(for: request, generation: generation)
            defer { progressTask.cancel() }

            try await request.downloadAndInstall()

            let refreshedStatus = await AssetInventory.status(forModules: modules)
            guard refreshedStatus == .installed else {
                throw DictationError.modelPreparationFailed(
                    "Apple speech assets are still not installed."
                )
            }

            emitLanguageModelStatus(.ready, generation: generation)
            logger.info("Speech model ready for language \(language.localeIdentifier, privacy: .public)")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Speech model preparation failed: \(error.localizedDescription, privacy: .public)")
            emitLanguageModelStatus(.failed(error.localizedDescription), generation: generation)
            throw error
        }
    }

    func startCapture(language: AppLanguage) async throws {
        guard !withStateLock({ isCapturing }) else {
            throw DictationError.alreadyCapturing
        }

        let locale = try await resolvedLocale(for: language)
        let transcriber = Self.makeTranscriber(locale: locale)
        let modules: [any SpeechModule] = [transcriber]

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let tapFormat = Self.preferredTapFormat(for: inputNode, fallback: inputFormat)

        guard tapFormat.channelCount > 0, tapFormat.sampleRate > 0 else {
            throw DictationError.noInputDevice
        }

        guard
            let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: modules,
                considering: tapFormat
            )
        else {
            throw DictationError.analyzerSetupFailed
        }

        let analysisContext = AnalysisContext()
        analysisContext.contextualStrings[.general] = contextualStrings

        let analyzer = SpeechAnalyzer(modules: modules)
        try await analyzer.setContext(analysisContext)
        try await analyzer.prepareToAnalyze(in: analysisFormat)

        let inputStream = AsyncStream<AnalyzerInput>(bufferingPolicy: .unbounded) { continuation in
            self.withStateLock {
                self.inputContinuation = continuation
            }
        }
        try await analyzer.start(inputSequence: inputStream)

        let resultsTask = makeResultsTask(for: transcriber)
        logger.info(
            """
            Started dictation capture for \(language.localeIdentifier, privacy: .public) \
            with input \(inputFormat.sampleRate, privacy: .public)Hz/\(inputFormat.channelCount, privacy: .public)ch, \
            tap \(tapFormat.sampleRate, privacy: .public)Hz/\(tapFormat.channelCount, privacy: .public)ch, \
            analyzer \(analysisFormat.sampleRate, privacy: .public)Hz/\(analysisFormat.channelCount, privacy: .public)ch
            """
        )

        withStateLock {
            self.audioEngine = audioEngine
            self.analyzer = analyzer
            self.transcriber = transcriber
            self.analysisContext = analysisContext
            self.analysisFormat = analysisFormat
            self.resultsTask = resultsTask
            self.submittedBufferCount = 0
            self.submittedSampleCount = 0
            self.finalSegments = []
            self.volatileSegment = nil
            self.pipelineError = nil
            self.isCapturing = true
        }

        onAudioLevel?(0)
        onLiveTranscript?("")

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.reset()
            finishInputStream()
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            resetSessionState()
            logger.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func finishCapture() async throws -> String {
        guard withStateLock({ isCapturing }) else {
            throw DictationError.notCapturing
        }

        let session = stopCaptureSession()
        onAudioLevel?(0)
        logger.info("Finishing dictation capture")

        do {
            if let analyzer = session.analyzer {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }

            try await session.resultsTask?.value

            if let pipelineError = withStateLock({ self.pipelineError }) {
                throw pipelineError
            }

            let rawText = withStateLock {
                Self.combineSegments(finalizedSegments: finalSegments, volatileSegment: nil)
            }

            guard !rawText.isEmpty else {
                logger.error("Dictation finished without recognized speech")
                throw DictationError.noSpeechDetected
            }

            logger.info("Dictation finalized with \(rawText.count, privacy: .public) characters")
            resetSessionState()
            return rawText
        } catch {
            session.resultsTask?.cancel()

            if let analyzer = session.analyzer {
                await analyzer.cancelAndFinishNow()
            }

            resetSessionState()
            logger.error("Dictation finalization failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func cancelCapture() async {
        let session = stopCaptureSession()
        session.resultsTask?.cancel()

        if let analyzer = session.analyzer {
            await analyzer.cancelAndFinishNow()
        }

        logger.info("Dictation capture cancelled")
        resetSessionState()
    }

    static func combineSegments(finalizedSegments: [String], volatileSegment: String?) -> String {
        let pieces = finalizedSegments + [volatileSegment]
        return pieces
            .compactMap { segment in
                guard let segment else { return nil }

                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedLocale(for language: AppLanguage) async throws -> Locale {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: language.locale) else {
            throw DictationError.unsupportedLanguage(language.menuTitle)
        }

        return locale
    }

    private func makeInstallationProgressTask(
        for request: AssetInstallationRequest,
        generation: UInt64
    ) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                self?.emitLanguageModelStatus(
                    .downloading(progress: Self.normalizedProgress(from: request.progress)),
                    generation: generation
                )

                if request.progress.isFinished {
                    break
                }

                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func makeResultsTask(for transcriber: SpeechTranscriber) -> Task<Void, Error> {
        Task { [weak self] in
            guard let self else { return }

            for try await result in transcriber.results {
                try Task.checkCancellation()
                consume(result: result)
            }
        }
    }

    private func consume(result: SpeechTranscriber.Result) {
        let segment = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !segment.isEmpty else { return }

        let livePreview = withStateLock {
            if result.isFinal {
                finalSegments.append(segment)
                volatileSegment = nil
            } else {
                volatileSegment = segment
            }

            return Self.combineSegments(
                finalizedSegments: finalSegments,
                volatileSegment: volatileSegment
            )
        }

        logger.debug(
            "Received \(result.isFinal ? "final" : "volatile", privacy: .public) segment with \(segment.count, privacy: .public) characters"
        )
        onLiveTranscript?(livePreview)
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        onAudioLevel?(Self.normalizedLevel(for: buffer))

        do {
            guard let analyzerInput = try makeAnalyzerInput(from: buffer) else { return }
            let continuation = withStateLock { inputContinuation }
            continuation?.yield(analyzerInput)
        } catch {
            storePipelineError(error)
            finishInputStream()
        }
    }

    private func makeAnalyzerInput(from buffer: AVAudioPCMBuffer) throws -> AnalyzerInput? {
        guard let analysisFormat = withStateLock({ analysisFormat }) else {
            throw DictationError.analyzerSetupFailed
        }

        let analyzerBuffer: AVAudioPCMBuffer

        if Self.formatsMatch(buffer.format, analysisFormat) {
            analyzerBuffer = try Self.copyBuffer(buffer)
        } else {
            guard let convertedBuffer = try Self.convertBuffer(buffer, to: analysisFormat) else {
                return nil
            }

            analyzerBuffer = convertedBuffer
        }

        let state = withStateLock {
            submittedBufferCount += 1
            let bufferIndex = submittedBufferCount
            let startSample = submittedSampleCount
            submittedSampleCount += Int64(analyzerBuffer.frameLength)
            let bufferStartTime = Self.makeBufferStartTime(
                sampleIndex: startSample,
                sampleRate: analysisFormat.sampleRate
            )
            let shouldLog = bufferIndex <= 3 || bufferIndex.isMultiple(of: 50)
            return (bufferIndex, shouldLog, bufferStartTime)
        }

        if state.1 {
            logger.debug(
                "Submitting audio buffer #\(state.0, privacy: .public) with \(analyzerBuffer.frameLength, privacy: .public) frames from \(buffer.format.sampleRate, privacy: .public)Hz to \(analysisFormat.sampleRate, privacy: .public)Hz"
            )
        }

        guard analyzerBuffer.frameLength > 0 else {
            return nil
        }

        return AnalyzerInput(buffer: analyzerBuffer, bufferStartTime: state.2)
    }

    private func stopCaptureSession() -> SessionSnapshot {
        let audioEngine = withStateLock { self.audioEngine }
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.reset()
        finishInputStream()

        return withStateLock {
            isCapturing = false

            return SessionSnapshot(
                analyzer: analyzer,
                resultsTask: resultsTask
            )
        }
    }

    private func finishInputStream() {
        let continuation = withStateLock {
            let continuation = inputContinuation
            inputContinuation = nil
            return continuation
        }

        continuation?.finish()
    }

    private func resetSessionState() {
        withStateLock {
            audioEngine = nil
            analyzer = nil
            transcriber = nil
            analysisContext = nil
            analysisFormat = nil
            inputContinuation = nil
            resultsTask = nil
            submittedBufferCount = 0
            submittedSampleCount = 0
            finalSegments = []
            volatileSegment = nil
            pipelineError = nil
            isCapturing = false
        }

        onAudioLevel?(0)
        onLiveTranscript?("")
    }

    private func storePipelineError(_ error: Error) {
        withStateLock {
            if pipelineError == nil {
                pipelineError = error
            }
        }

        logger.error("Audio pipeline failed: \(error.localizedDescription, privacy: .public)")
    }

    private func nextLanguageStatusGeneration() -> UInt64 {
        withStateLock {
            languageStatusGeneration += 1
            return languageStatusGeneration
        }
    }

    private func emitLanguageModelStatus(_ status: LanguageModelStatus, generation: UInt64) {
        let callback: (@Sendable (LanguageModelStatus) -> Void)? = withStateLock {
            guard languageStatusGeneration == generation else { return nil }
            return onLanguageModelStatus
        }

        callback?(status)
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
    }

    private static func normalizedProgress(from progress: Progress) -> Double? {
        guard progress.totalUnitCount > 0 else { return nil }

        let fraction = progress.fractionCompleted
        guard fraction.isFinite else { return nil }

        return max(0, min(1, fraction))
    }

    private static func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        to outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            throw DictationError.audioConversionFailed
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let estimatedFrameCapacity = max(1, Int(ceil(Double(buffer.frameLength) * ratio)))

        guard
            let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(estimatedFrameCapacity)
            )
        else {
            throw DictationError.audioConversionFailed
        }

        let sourceBuffer = BufferBox(buffer)
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if let buffer = sourceBuffer.buffer {
                outStatus.pointee = .haveData
                sourceBuffer.buffer = nil
                return buffer
            }

            outStatus.pointee = .endOfStream
            return nil
        }

        if let conversionError {
            throw conversionError
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return convertedBuffer.frameLength > 0 ? convertedBuffer : nil
        case .error:
            throw DictationError.audioConversionFailed
        @unknown default:
            throw DictationError.audioConversionFailed
        }
    }

    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard
            let copiedBuffer = AVAudioPCMBuffer(
                pcmFormat: buffer.format,
                frameCapacity: buffer.frameLength
            )
        else {
            throw DictationError.audioConversionFailed
        }

        copiedBuffer.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copiedBuffer.mutableAudioBufferList)

        guard sourceBuffers.count == destinationBuffers.count else {
            throw DictationError.audioConversionFailed
        }

        for index in 0..<sourceBuffers.count {
            let sourceBuffer = sourceBuffers[index]
            let destinationBuffer = destinationBuffers[index]

            guard
                let sourceData = sourceBuffer.mData,
                let destinationData = destinationBuffer.mData
            else {
                throw DictationError.audioConversionFailed
            }

            let byteCount = Int(sourceBuffer.mDataByteSize)
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffer.mDataByteSize
        }

        return copiedBuffer
    }

    private static func makeBufferStartTime(
        sampleIndex: Int64,
        sampleRate: Double
    ) -> CMTime? {
        guard sampleIndex >= 0, sampleRate.isFinite, sampleRate > 0 else { return nil }

        let roundedSampleRate = Int32(sampleRate.rounded())
        guard roundedSampleRate > 0 else { return nil }

        return CMTime(value: sampleIndex, timescale: roundedSampleRate)
    }

    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate &&
        lhs.channelCount == rhs.channelCount &&
        lhs.commonFormat == rhs.commonFormat &&
        lhs.isInterleaved == rhs.isInterleaved
    }

    private static func preferredTapFormat(
        for inputNode: AVAudioInputNode,
        fallback inputFormat: AVAudioFormat
    ) -> AVAudioFormat {
        let outputFormat = inputNode.outputFormat(forBus: 0)

        guard outputFormat.channelCount > 0, outputFormat.sampleRate > 0 else {
            return inputFormat
        }

        return outputFormat
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

private struct SessionSnapshot {
    let analyzer: SpeechAnalyzer?
    let resultsTask: Task<Void, Error>?
}

private final class BufferBox: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

private enum DictationError: LocalizedError {
    case alreadyCapturing
    case notCapturing
    case noInputDevice
    case unsupportedLanguage(String)
    case modelPreparationFailed(String)
    case audioConversionFailed
    case analyzerSetupFailed
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .alreadyCapturing:
            return "A dictation capture is already in progress."
        case .notCapturing:
            return "No dictation capture is currently running."
        case .noInputDevice:
            return "No microphone input device is available."
        case .unsupportedLanguage(let language):
            return "Apple on-device transcription is not available for \(language) on this Mac."
        case .modelPreparationFailed(let message):
            return message
        case .audioConversionFailed:
            return "MyWhisper couldn't prepare microphone audio for transcription."
        case .analyzerSetupFailed:
            return "MyWhisper couldn't start Apple's speech analyzer."
        case .noSpeechDetected:
            return "No speech was detected."
        }
    }
}
