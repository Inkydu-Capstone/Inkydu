import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AITeacherError: Error {
    case invalidResponse
}

final class AITeacherService {
    func planTurn(
        page: StoryPage,
        childUtterance: String,
        sessionProfile: StorySessionProfile,
        attemptCount: Int
    ) async -> InkyduTurnPlan {
        let cleanedUtterance = childUtterance.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedUtterance.isEmpty else {
            return InkyduTurnPlan.fallback(
                spokenReply: TeacherResponses.responseSpeechUnclear(),
                childIntent: .unclear,
                teachingMove: .repeatQuestion
            )
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                return try await planTurnWithModel(
                    page: page,
                    childUtterance: cleanedUtterance,
                    sessionProfile: sessionProfile,
                    attemptCount: attemptCount
                )
            } catch {
                return fallbackPlan(
                    page: page,
                    childUtterance: cleanedUtterance,
                    sessionProfile: sessionProfile,
                    attemptCount: attemptCount
                )
            }
        }
        #endif

        return fallbackPlan(
            page: page,
            childUtterance: cleanedUtterance,
            sessionProfile: sessionProfile,
            attemptCount: attemptCount
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func planTurnWithModel(
        page: StoryPage,
        childUtterance: String,
        sessionProfile: StorySessionProfile,
        attemptCount: Int
    ) async throws -> InkyduTurnPlan {
        let session = LanguageModelSession(
            instructions: """
            You are Inkydu, a kind baby penguin reading teacher for children ages 3 to 5.

            Return only valid JSON.

            Always keep spokenReply to one short child-friendly sentence.
            Never be scary, harsh, or shaming.
            Stay grounded in the current story page.
            If the child is correct, praise briefly.
            If the child is incorrect, be gentle and use only one tiny hint unless it is time to reveal the answer.
            If the child says a short story word like bunny, pig, carrot, or friends, acknowledge that exact idea warmly.

            Use only these childIntent values:
            answerQuestion, askQuestion, repeatRequest, nextPageRequest, emotionalReaction, comment, offTopic, unclear

            Use only these teachingMove values:
            praise, giveHint, revealAnswer, repeatQuestion, answerChildQuestion, comfort, continueStory

            JSON keys must be exactly:
            spokenReply
            childIntent
            teachingMove
            isCorrect
            shouldAdvance
            shouldRepeatPage
            wantsFollowUpQuestion
            followUpQuestion
            extractedChildName
            notablePreference
            """
        )

        let interaction = StoryInteractionFactory.resolvedInteraction(for: page)
        let prompt = """
        Story page narration:
        \(page.narration)

        Current story interaction prompt:
        \(interaction?.prompt ?? "none")

        Expected answer:
        \(interaction?.expectedAnswer ?? "none")

        Acceptable alternate answers:
        \(interaction?.answerAliases.joined(separator: " | ") ?? "none")

        Available choices:
        \(interaction?.choices.joined(separator: " | ") ?? "none")

        Hint:
        \(interaction?.hint ?? "none")

        Reveal answer:
        \(interaction?.answerReveal ?? "none")

        Answer attempt count so far:
        \(attemptCount)

        Session context:
        \(sessionProfile.contextSummary)

        Child said:
        \(childUtterance)

        Guidance:
        - If the child asks to hear it again, set shouldRepeatPage to true.
        - If the child asks for the next page, set shouldAdvance to true.
        - If the child asks a question about the story, answer it simply.
        - If the child gives an answer with the same meaning as the correct answer, count it as correct.
        - If the page has a question and the child makes a related story comment instead of answering, respond to the comment and set wantsFollowUpQuestion to true.
        - If this is a second failed answer attempt, you may reveal the answer gently.
        - If there is no question on this page, respond conversationally and usually set shouldAdvance to true.
        - If the child says their name, extract it.
        - If the child reveals a preference like liking funny parts, note it briefly in notablePreference.

        Return JSON only.
        """

        let response = try await session.respond(to: prompt)
        return try parseTurnPlan(from: response.content)
    }
    #endif

    private func fallbackPlan(
        page: StoryPage,
        childUtterance: String,
        sessionProfile: StorySessionProfile,
        attemptCount: Int
    ) -> InkyduTurnPlan {
        let normalized = normalize(childUtterance)
        let interaction = StoryInteractionFactory.resolvedInteraction(for: page)
        let extractedChildName = extractChildName(from: childUtterance)
        let notablePreference = extractPreference(from: normalized)

        if normalized.isEmpty {
            return InkyduTurnPlan.fallback(
                spokenReply: TeacherResponses.responseSpeechUnclear(),
                childIntent: .unclear,
                teachingMove: .repeatQuestion,
                extractedChildName: extractedChildName,
                notablePreference: notablePreference
            )
        }

        if isRepeatRequest(normalized) {
            return InkyduTurnPlan.fallback(
                spokenReply: TeacherResponses.responseReplayRequest(),
                childIntent: .repeatRequest,
                teachingMove: .continueStory,
                shouldRepeatPage: true,
                extractedChildName: extractedChildName,
                notablePreference: notablePreference
            )
        }

        if isNextPageRequest(normalized) {
            return InkyduTurnPlan.fallback(
                spokenReply: TeacherResponses.responseNextPage(),
                childIntent: .nextPageRequest,
                teachingMove: .continueStory,
                shouldAdvance: true,
                extractedChildName: extractedChildName,
                notablePreference: notablePreference
            )
        }

        if isEmotionalReaction(normalized) {
            return InkyduTurnPlan.fallback(
                spokenReply: TeacherResponses.responseComfort(),
                childIntent: .emotionalReaction,
                teachingMove: .comfort,
                extractedChildName: extractedChildName,
                notablePreference: notablePreference
            )
        }

        if isQuestionIntent(normalized) {
            return InkyduTurnPlan.fallback(
                spokenReply: fallbackConversationReply(for: page, normalizedUtterance: normalized),
                childIntent: .askQuestion,
                teachingMove: .answerChildQuestion,
                shouldAdvance: interaction == nil,
                extractedChildName: extractedChildName,
                notablePreference: notablePreference
            )
        }

        if let interaction, interaction.expectedAnswer != nil {
            let isCorrect = meaningMatchesExpectedAnswer(
                childUtterance: childUtterance,
                interaction: interaction
            )

            if isCorrect {
                return InkyduTurnPlan.fallback(
                    spokenReply: TeacherResponses.responseCorrectAnswer(for: interaction.expectedAnswer),
                    childIntent: .answerQuestion,
                    teachingMove: .praise,
                    isCorrect: true,
                    shouldAdvance: true,
                    extractedChildName: extractedChildName,
                    notablePreference: notablePreference
                )
            }

            if !isLikelyAnswerAttempt(normalized, interaction: interaction) {
                return InkyduTurnPlan.fallback(
                    spokenReply: contextualStoryReply(for: normalized)
                        ?? TeacherResponses.responseQuestionRedirect(),
                    childIntent: .comment,
                    teachingMove: .continueStory,
                    wantsFollowUpQuestion: true,
                    followUpQuestion: interaction.prompt,
                    extractedChildName: extractedChildName,
                    notablePreference: notablePreference
                )
            }

            if attemptCount >= 1 {
                return InkyduTurnPlan.fallback(
                    spokenReply: interaction.answerReveal ?? TeacherResponses.responseRevealAnswer(),
                    childIntent: .answerQuestion,
                    teachingMove: .revealAnswer,
                    shouldAdvance: true,
                    extractedChildName: extractedChildName,
                    notablePreference: notablePreference
                )
            }

            return InkyduTurnPlan.fallback(
                spokenReply: TeacherResponses.responseIncorrectAnswer(hint: interaction.hint),
                childIntent: .answerQuestion,
                teachingMove: .giveHint,
                extractedChildName: extractedChildName,
                notablePreference: notablePreference
            )
        }

        let response = fallbackConversationReply(for: page, normalizedUtterance: normalized)
        let shouldAdvance = page.pageID != "12"

        return InkyduTurnPlan.fallback(
            spokenReply: response,
            childIntent: .comment,
            teachingMove: .continueStory,
            shouldAdvance: shouldAdvance,
            extractedChildName: extractedChildName ?? sessionProfile.childName,
            notablePreference: notablePreference
        )
    }

    private func parseTurnPlan(from raw: String) throws -> InkyduTurnPlan {
        let jsonString = try extractJSONObject(from: raw)
        let data = Data(jsonString.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(InkyduTurnPlan.self, from: data)
    }

    private func extractJSONObject(from raw: String) throws -> String {
        guard let startIndex = raw.firstIndex(of: "{") else {
            throw AITeacherError.invalidResponse
        }

        var braceDepth = 0
        var endIndex: String.Index?

        for index in raw[startIndex...].indices {
            if raw[index] == "{" {
                braceDepth += 1
            } else if raw[index] == "}" {
                braceDepth -= 1
                if braceDepth == 0 {
                    endIndex = index
                    break
                }
            }
        }

        guard let resolvedEndIndex = endIndex else {
            throw AITeacherError.invalidResponse
        }

        return String(raw[startIndex...resolvedEndIndex])
    }

    private func fallbackConversationReply(for page: StoryPage, normalizedUtterance: String) -> String {
        if let topicReply = storyTopicReply(for: normalizedUtterance) {
            return topicReply
        }

        if normalizedUtterance.contains("why") {
            return TeacherResponses.responseWhy()
        }

        if page.pageID == "12" {
            return TeacherResponses.responseFavoritePart()
        }

        return TeacherResponses.responseGenericConversation()
    }

    private func storyTopicReply(for normalizedUtterance: String) -> String? {
        if normalizedUtterance.contains("bunny") || normalizedUtterance.contains("rabbit") {
            return TeacherResponses.responseBunny()
        }

        if normalizedUtterance.contains("billy") || normalizedUtterance.contains("bob") {
            return TeacherResponses.responseBillyBob()
        }

        if normalizedUtterance.contains("pig") || normalizedUtterance.contains("oinky") {
            return TeacherResponses.responseOinky()
        }

        if normalizedUtterance.contains("carrot") {
            return TeacherResponses.responseCarrotsStory()
        }

        if normalizedUtterance.contains("friend")
            || normalizedUtterance.contains("pals")
            || normalizedUtterance.contains("truce") {
            return TeacherResponses.responseFriendsStory()
        }

        if normalizedUtterance.contains("loud")
            || normalizedUtterance.contains("noisy")
            || normalizedUtterance.contains("din")
            || normalizedUtterance.contains("ruckus") {
            return TeacherResponses.responseLoudStory()
        }

        if normalizedUtterance.contains("fight") || normalizedUtterance.contains("mad") {
            return TeacherResponses.responseKindness()
        }

        if normalizedUtterance.contains("funny") {
            return TeacherResponses.responseFunny()
        }

        if normalizedUtterance.contains("sad") {
            return TeacherResponses.responseSad()
        }

        return nil
    }

    private func contextualStoryReply(for normalizedUtterance: String) -> String? {
        storyTopicReply(for: normalizedUtterance)
    }

    private func meaningMatchesExpectedAnswer(
        childUtterance: String,
        interaction: StoryInteraction
    ) -> Bool {
        let normalizedChild = normalize(childUtterance)
        var acceptableAnswers = interaction.answerAliases
        if let expectedAnswer = interaction.expectedAnswer {
            acceptableAnswers.insert(expectedAnswer, at: 0)
        }

        let normalizedAnswers = acceptableAnswers
            .map(normalize)
            .filter { !$0.isEmpty }

        return normalizedAnswers.contains { candidate in
            candidate == normalizedChild
                || normalizedChild.contains(candidate)
                || candidate.contains(normalizedChild)
                || tokenOverlapScore(lhs: normalizedChild, rhs: candidate) >= 0.7
                || hasLooseTokenMatch(lhs: normalizedChild, rhs: candidate)
        }
    }

    private func isLikelyAnswerAttempt(_ normalized: String, interaction: StoryInteraction) -> Bool {
        var candidates = interaction.choices
        candidates.append(contentsOf: interaction.answerAliases)
        if let expectedAnswer = interaction.expectedAnswer {
            candidates.append(expectedAnswer)
        }

        let normalizedCandidates = candidates
            .map(normalize)
            .filter { !$0.isEmpty }

        if normalizedCandidates.contains(where: { candidate in
            candidate == normalized
                || normalized.contains(candidate)
                || candidate.contains(normalized)
                || tokenOverlapScore(lhs: normalized, rhs: candidate) >= 0.6
                || hasLooseTokenMatch(lhs: normalized, rhs: candidate)
        }) {
            return true
        }

        return false
    }

    private func isRepeatRequest(_ normalized: String) -> Bool {
        normalized.contains("again")
            || normalized.contains("repeat")
            || normalized.contains("read it again")
            || normalized.contains("say it again")
    }

    private func isNextPageRequest(_ normalized: String) -> Bool {
        normalized.contains("next page")
            || normalized.contains("turn the page")
            || normalized.contains("go next")
            || normalized == "next"
    }

    private func isQuestionIntent(_ normalized: String) -> Bool {
        normalized.hasPrefix("why")
            || normalized.hasPrefix("what")
            || normalized.hasPrefix("how")
            || normalized.hasPrefix("who")
            || normalized.hasPrefix("where")
    }

    private func isEmotionalReaction(_ normalized: String) -> Bool {
        normalized.contains("scared")
            || normalized.contains("sad")
            || normalized.contains("mad")
            || normalized.contains("upset")
            || normalized.contains("i dont like")
    }

    private func extractChildName(from utterance: String) -> String? {
        let lowercased = utterance.lowercased()
        let patterns = [
            "my name is ",
            "i am ",
            "i'm "
        ]

        for pattern in patterns {
            guard let range = lowercased.range(of: pattern) else { continue }
            let remainder = utterance[range.upperBound...]
            let name = remainder
                .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "!" || $0 == "?" || $0 == "," })
                .prefix(1)
                .joined()

            let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedName.count >= 2 {
                return cleanedName.prefix(1).uppercased() + cleanedName.dropFirst()
            }
        }

        return nil
    }

    private func extractPreference(from normalized: String) -> String? {
        if normalized.contains("funny") {
            return "funny parts"
        }

        if normalized.contains("pig") || normalized.contains("oinky") {
            return "Oinky"
        }

        if normalized.contains("carrot") {
            return "carrots"
        }

        if normalized.contains("bunny") || normalized.contains("rabbit") {
            return "bunnies"
        }

        return nil
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func tokenOverlapScore(lhs: String, rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))

        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
            return 0
        }

        let sharedCount = lhsTokens.intersection(rhsTokens).count
        return Double(sharedCount) / Double(max(lhsTokens.count, rhsTokens.count))
    }

    private func hasLooseTokenMatch(lhs: String, rhs: String) -> Bool {
        let lhsTokens = lhs.split(separator: " ").map(String.init)
        let rhsTokens = rhs.split(separator: " ").map(String.init)

        for lhsToken in lhsTokens {
            for rhsToken in rhsTokens {
                let shorterLength = min(lhsToken.count, rhsToken.count)
                guard shorterLength >= 3 else { continue }

                if lhsToken.hasPrefix(rhsToken) || rhsToken.hasPrefix(lhsToken) {
                    return true
                }

                let lhsPrefix = String(lhsToken.prefix(3))
                let rhsPrefix = String(rhsToken.prefix(3))
                if lhsPrefix == rhsPrefix && abs(lhsToken.count - rhsToken.count) <= 3 {
                    return true
                }
            }
        }

        return false
    }
}
