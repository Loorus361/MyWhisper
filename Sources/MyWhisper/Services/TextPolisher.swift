import Foundation

enum TextPolisher {
    static func polish(_ rawText: String, language: AppLanguage) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let fillerWords = language == .german
            ? ["äh", "ähm", "hm", "hmm", "mhm"]
            : ["uh", "um", "erm", "hmm", "huh"]

        let filteredTokens = trimmed
            .split(whereSeparator: \.isWhitespace)
            .filter { token in
                let normalized = token
                    .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
                    .lowercased()
                return !fillerWords.contains(normalized)
            }

        var text = filteredTokens.joined(separator: " ")
        guard !text.isEmpty else { return trimmed }

        if let first = text.first {
            text.replaceSubrange(text.startIndex...text.startIndex, with: String(first).uppercased())
        }

        if
            text.count > 12,
            let last = text.last,
            last.isLetter || last.isNumber
        {
            text.append(".")
        }

        return text
    }
}
