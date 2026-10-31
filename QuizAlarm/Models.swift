import Foundation

struct AlarmSettings: Codable, Equatable {
    var hour: Int = 7
    var minute: Int = 0
    var isEnabled: Bool = false
    var requiredCorrect: Int = 3
    var qrEnabled: Bool = false
    var qrCode: String = "QA-\(UUID().uuidString)"
    var lastSolved: Date = Date()
}

struct Card: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var front: String
    var back: String
    var added: Date = Date()
    var due: Date = Date()
    var box: Int = 0
    var wrong: Int = 0

    static let boxIntervalsDays: [Int] = [0, 1, 2, 4, 8, 16]
}

struct ParsedQuestion {
    let isCloze: Bool
    let displayPrompt: String
    let rawAnswer: String
    let acceptedAnswers: [String]

    static func parse(from card: Card) -> ParsedQuestion {
        let frontText = card.front
        let nsFront = frontText as NSString
        let fullRange = NSRange(location: 0, length: nsFront.length)

        guard let regex = try? NSRegularExpression(pattern: "\\{\\{([^{}]+)\\}\\}", options: []) else {
            return makeTwoSided(card: card)
        }

        let matches = regex.matches(in: frontText, options: [], range: fullRange)
        guard let firstMatch = matches.first, firstMatch.numberOfRanges > 1 else {
            return makeTwoSided(card: card)
        }

        let firstInner = nsFront.substring(with: firstMatch.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if firstInner.isEmpty {
            return makeTwoSided(card: card)
        }

        let mutableDisplay = NSMutableString(string: frontText)
        for (index, match) in matches.enumerated().reversed() {
            if index == 0 {
                mutableDisplay.replaceCharacters(in: match.range, with: "_____")
            } else if match.numberOfRanges > 1 {
                let inner = nsFront.substring(with: match.range(at: 1))
                mutableDisplay.replaceCharacters(in: match.range, with: inner)
            }
        }

        let answers = splitAnswers(firstInner)
        return ParsedQuestion(
            isCloze: true,
            displayPrompt: String(mutableDisplay),
            rawAnswer: firstInner,
            acceptedAnswers: answers.isEmpty ? [firstInner] : answers
        )
    }

    private static func makeTwoSided(card: Card) -> ParsedQuestion {
        let answers = splitAnswers(card.back)
        return ParsedQuestion(
            isCloze: false,
            displayPrompt: card.front,
            rawAnswer: card.back,
            acceptedAnswers: answers.isEmpty ? [card.back] : answers
        )
    }

    private static func splitAnswers(_ raw: String) -> [String] {
        raw.split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func matches(_ userInput: String) -> Bool {
        let normalizedInput = userInput.normalizedForQuiz()
        guard !normalizedInput.isEmpty else { return false }
        return acceptedAnswers.contains { candidate in
            candidate.normalizedForQuiz() == normalizedInput
        }
    }
}

extension String {
    /// Chuẩn hóa chuỗi để so khớp không phân biệt hoa thường, dấu tiếng Việt và chữ "đ/Đ"
    func normalizedForQuiz() -> String {
        let dReplaced = self
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")

        let folded = dReplaced.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "vi_VN")
        )

        let words = folded
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        return words.joined(separator: " ")
    }
}