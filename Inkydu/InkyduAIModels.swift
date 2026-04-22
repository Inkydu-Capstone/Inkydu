import Foundation

enum ChildIntent: String, Codable, Equatable {
    case answerQuestion
    case askQuestion
    case repeatRequest
    case nextPageRequest
    case emotionalReaction
    case comment
    case offTopic
    case unclear
}

enum TeachingMove: String, Codable, Equatable {
    case praise
    case giveHint
    case revealAnswer
    case repeatQuestion
    case answerChildQuestion
    case comfort
    case continueStory
}

struct InkyduTurnPlan: Codable, Equatable {
    let spokenReply: String
    let childIntent: ChildIntent
    let teachingMove: TeachingMove
    let isCorrect: Bool
    let shouldAdvance: Bool
    let shouldRepeatPage: Bool
    let wantsFollowUpQuestion: Bool
    let followUpQuestion: String?
    let extractedChildName: String?
    let notablePreference: String?

    static func fallback(
        spokenReply: String,
        childIntent: ChildIntent = .comment,
        teachingMove: TeachingMove = .continueStory,
        isCorrect: Bool = false,
        shouldAdvance: Bool = false,
        shouldRepeatPage: Bool = false,
        wantsFollowUpQuestion: Bool = false,
        followUpQuestion: String? = nil,
        extractedChildName: String? = nil,
        notablePreference: String? = nil
    ) -> InkyduTurnPlan {
        InkyduTurnPlan(
            spokenReply: spokenReply,
            childIntent: childIntent,
            teachingMove: teachingMove,
            isCorrect: isCorrect,
            shouldAdvance: shouldAdvance,
            shouldRepeatPage: shouldRepeatPage,
            wantsFollowUpQuestion: wantsFollowUpQuestion,
            followUpQuestion: followUpQuestion,
            extractedChildName: extractedChildName,
            notablePreference: notablePreference
        )
    }
}

struct StorySessionProfile: Codable, Equatable {
    var childName: String?
    var recentUtterances: [String] = []
    var likedTopics: [String] = []
    var recentMood: String?
    var lastIntent: ChildIntent?
    var lastAnswerWasCorrect: Bool?

    mutating func record(utterance: String, plan: InkyduTurnPlan) {
        let cleanedUtterance = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedUtterance.isEmpty {
            recentUtterances.append(cleanedUtterance)
            recentUtterances = Array(recentUtterances.suffix(4))
        }

        if let extractedChildName = plan.extractedChildName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extractedChildName.isEmpty {
            childName = extractedChildName
        }

        if let notablePreference = plan.notablePreference?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notablePreference.isEmpty,
           !likedTopics.contains(notablePreference) {
            likedTopics.append(notablePreference)
            likedTopics = Array(likedTopics.suffix(3))
        }

        lastIntent = plan.childIntent
        lastAnswerWasCorrect = plan.isCorrect

        switch plan.childIntent {
        case .emotionalReaction:
            recentMood = "emotional"
        case .askQuestion:
            recentMood = "curious"
        case .comment:
            recentMood = "engaged"
        case .unclear:
            recentMood = "unclear"
        default:
            break
        }
    }

    var contextSummary: String {
        let nameSummary = childName.map { "Child name: \($0)." } ?? "Child name: unknown."
        let recentSummary = recentUtterances.isEmpty
            ? "Recent child utterances: none."
            : "Recent child utterances: \(recentUtterances.joined(separator: " | "))."
        let preferenceSummary = likedTopics.isEmpty
            ? "Known likes: none yet."
            : "Known likes: \(likedTopics.joined(separator: ", "))."
        let moodSummary = recentMood.map { "Recent mood: \($0)." } ?? "Recent mood: unknown."
        let answerSummary = lastAnswerWasCorrect.map { "Last answer was correct: \($0 ? "yes" : "no")." }
            ?? "Last answer correctness: unknown."
        let intentSummary = lastIntent.map { "Last child intent: \($0.rawValue)." }
            ?? "Last child intent: unknown."

        return [
            nameSummary,
            recentSummary,
            preferenceSummary,
            moodSummary,
            answerSummary,
            intentSummary
        ].joined(separator: " ")
    }
}
