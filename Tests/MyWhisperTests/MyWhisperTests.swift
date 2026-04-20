// Holds the Swift Testing target for MyWhisper logic as the app grows.
import Testing
@testable import MyWhisper

@Test func combineSegmentsWithFinalizedOnlyText() {
    let combined = DictationService.combineSegments(
        finalizedSegments: ["Hallo", "Welt"],
        volatileSegment: nil
    )

    #expect(combined == "Hallo Welt")
}

@Test func combineSegmentsWithVolatileOnlyText() {
    let combined = DictationService.combineSegments(
        finalizedSegments: [],
        volatileSegment: "Testing live preview"
    )

    #expect(combined == "Testing live preview")
}

@Test func combineSegmentsWithMixedText() {
    let combined = DictationService.combineSegments(
        finalizedSegments: ["SwiftUI", "ist"],
        volatileSegment: "schnell"
    )

    #expect(combined == "SwiftUI ist schnell")
}

@Test func combineSegmentsIgnoresEmptyParts() {
    let combined = DictationService.combineSegments(
        finalizedSegments: [" ", "Hallo"],
        volatileSegment: "   "
    )

    #expect(combined == "Hallo")
}

@Test func languageModelStatusFormats() {
    #expect(LanguageModelStatus.checking.displayText == "Checking Apple speech model...")
    #expect(
        LanguageModelStatus.downloading(progress: 0.42).displayText
            == "Downloading Apple speech model (42%)"
    )
    #expect(LanguageModelStatus.ready.displayText == "Apple speech model ready")
    #expect(
        LanguageModelStatus.failed("Network timeout").displayText
            == "Preparation failed: Network timeout"
    )
}
