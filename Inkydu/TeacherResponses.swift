
// This file holds all the phrases Inkydu is allowed to say. 
// Apple's base library
import Foundation

struct TeacherResponses {
    // Encourages child to tap Let's Go and start book
    private static let readyToRead = [
        "Tap Let's Go and I will read with you.",
        "Tap Let's Go and I will start the story.",
        "Tap Let's Go and I will read us the book."
    ]

    // Future, when more books available
    private static let libraryPrompts = [
        "Pick a book and I will read with you.",
        "Choose a book and I will read it out loud.",
        "Pick a story and I will read with you."
    ]

    // Future ^
    private static let bookUnavailable = [
        "I couldn't open that book yet.",
        "That book is not ready yet.",
        "I need a moment before I can open that book."
    ]

    // End of book
    private static let storyFinished = [
        "The story is all done.",
        "We finished the story.",
        "That was the end of the book."
    ]

    // When Inkydu can hear child
    private static let listeningPrompts = [
        "I'm listening.",
        "Go ahead. I'm listening.",
        "Tell me what you think.",
        "I can hear you now."
    ]

    // Telling child they can hear them
    private static let handsFreePrompts = [
        "You can talk any time.",
        "I can listen if you want to talk.",
        "You can jump in and talk to me.",
        "I am ready if you want to say something."
    ]

    // Thinking
    private static let thinkingPrompts = [
        "Let me think.",
        "I'm thinking.",
        "Let me figure it out."
    ]

    // Mic off prompts
    private static let mutedPrompts = [
        "Listening is off right now.",
        "My listening ears are off right now.",
        "The microphone is off right now."
    ]

    private static let comfortPrompts = [
        "It's okay. We can figure it out together.",
        "You're safe with me. We can go slow.",
        "That's okay. I'm right here with you."
    ]

    private static let speechUnclear = [
        "I didn't quite hear that.",
        "Could you say that again?",
        "That was a little hard to hear.",
        "Can you try that one more time?"
    ]

    private static let retryPrefixes = [
        "Nice try.",
        "Good try.",
        "You are close.",
        "That was a good guess."
    ]

    private static let generalPraise = [
        "Yes, that's right!",
        "You got it!",
        "Great job!",
        "Nice work!"
    ]

    private static let revealReplies = [
        "It was Oinky the pig.",
        "The answer was Oinky.",
        "They became friends at the end.",
        "They pulled carrots from the garden."
    ]

    private static let replayReplies = [
        "Okay, we can hear it again.",
        "Sure, let's hear it again.",
        "Okay, I can read it again."
    ]

    private static let nextPageReplies = [
        "Okay, let's see the next page.",
        "Let's turn the page.",
        "Okay, here comes the next page."
    ]

    private static let oinkyReplies = [
        "Yes, that's Oinky the pig!",
        "Oinky was being very silly.",
        "That pig was very sneaky."
    ]

    private static let bunnyReplies = [
        "Yes, a bunny! Let's keep reading.",
        "That's a bunny! Let's read some more.",
        "You found the bunny! Let's keep going."
    ]

    private static let carrotReplies = [
        "Yes, carrots! Let's keep reading.",
        "Those are carrots! Let's read more.",
        "Carrots, yes! Let's keep going."
    ]

    private static let billyBobReplies = [
        "Billy Bob is trying to help.",
        "Billy Bob wants them to be kind.",
        "Billy Bob is a good helper."
    ]

    private static let friendReplies = [
        "Yes, they become friends.",
        "I like when they become friends.",
        "They turn into friends at the end."
    ]

    private static let loudReplies = [
        "They were being very loud.",
        "Yes, that was a noisy part.",
        "That part was loud and busy."
    ]

    private static let redirectReplies = [
        "I heard you. Let's try this question.",
        "That was a good thought. Now let's answer this one.",
        "Let's answer this question together."
    ]

    private static let kindnessReplies = [
        "I like it best when friends are kind.",
        "Kind words are better than fighting.",
        "I like when they make peace."
    ]

    private static let funnyReplies = [
        "That part made me smile too.",
        "I thought that part was funny too.",
        "That was a silly part."
    ]

    private static let sadReplies = [
        "It got better when they made peace.",
        "I was glad it turned out happy.",
        "I like the happy ending best."
    ]

    private static let whyReplies = [
        "They were upset before they talked it out.",
        "They needed to talk and calm down.",
        "They had a big mix-up at first."
    ]

    private static let favoriteReplies = [
        "That is a wonderful favorite part.",
        "I like hearing your favorite part.",
        "That sounds like a fun part to love."
    ]

    private static let genericConversationReplies = [
        "I like hearing your idea. Let's keep reading.",
        "That is a good thought. Let's read more.",
        "I love hearing what you think. Let's keep going."
    ]

    static func responseReadyToRead() -> String {
        random(from: readyToRead, fallback: "Tap Let's Go and I will read with you.")
    }

    static func responseLibraryPrompt() -> String {
        random(from: libraryPrompts, fallback: "Pick a book and I will read with you.")
    }

    static func responseBookUnavailable() -> String {
        random(from: bookUnavailable, fallback: "I couldn't open that book yet.")
    }

    static func responseStoryFinished() -> String {
        random(from: storyFinished, fallback: "The story is all done.")
    }

    static func responseListeningPrompt() -> String {
        random(from: listeningPrompts, fallback: "I'm listening.")
    }

    static func responseHandsFreePrompt() -> String {
        random(from: handsFreePrompts, fallback: "You can talk any time.")
    }

    static func responseMutedPrompt() -> String {
        random(from: mutedPrompts, fallback: "Listening is off right now.")
    }

    static func responseThinking() -> String {
        random(from: thinkingPrompts, fallback: "Let me think.")
    }

    static func responseSpeechUnclear() -> String {
        random(from: speechUnclear, fallback: "I didn't quite hear that.")
    }

    static func responseComfort() -> String {
        random(from: comfortPrompts, fallback: "It's okay. We can figure it out together.")
    }

    // Incorrect
    static func responseIncorrectAnswer(hint: String?) -> String {
        let prefix = random(from: retryPrefixes, fallback: "Nice try.")
        let cleanedHint = hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !cleanedHint.isEmpty else {
            return prefix
        }

        return "\(prefix) \(cleanedHint)"
    }

    //  Correct
    static func responseCorrectAnswer(for expectedAnswer: String?) -> String {
        let normalizedExpected = normalize(expectedAnswer ?? "")

        switch normalizedExpected {
        case "loud":
            return "Yes, they were loud!"
        case "carrots", "carrot":
            return "Yes, they pulled carrots!"
        case "oinky", "pig":
            return "Yes, it was Oinky!"
        case "friends":
            return "Yes, they became friends!"
        default:
            return random(from: generalPraise, fallback: "Yes, that's right!")
        }
    }

    static func responseRevealAnswer() -> String {
        random(from: revealReplies, fallback: "Let's hear the answer together.")
    }

    static func responseReplayRequest() -> String {
        random(from: replayReplies, fallback: "Okay, we can hear it again.")
    }

    static func responseNextPage() -> String {
        random(from: nextPageReplies, fallback: "Okay, let's see the next page.")
    }

    static func responseOinky() -> String {
        random(from: oinkyReplies, fallback: "Oinky was being very silly.")
    }

    static func responseBunny() -> String {
        random(from: bunnyReplies, fallback: "Yes, a bunny! Let's keep reading.")
    }

    static func responseCarrotsStory() -> String {
        random(from: carrotReplies, fallback: "Yes, carrots! Let's keep reading.")
    }

    static func responseBillyBob() -> String {
        random(from: billyBobReplies, fallback: "Billy Bob is trying to help.")
    }

    static func responseFriendsStory() -> String {
        random(from: friendReplies, fallback: "Yes, they become friends.")
    }

    static func responseLoudStory() -> String {
        random(from: loudReplies, fallback: "They were being very loud.")
    }

    static func responseKindness() -> String {
        random(from: kindnessReplies, fallback: "I like it best when friends are kind.")
    }

    static func responseFunny() -> String {
        random(from: funnyReplies, fallback: "That part made me smile too.")
    }

    static func responseSad() -> String {
        random(from: sadReplies, fallback: "It got better when they made peace.")
    }

    static func responseWhy() -> String {
        random(from: whyReplies, fallback: "They were upset before they talked it out.")
    }

    static func responseFavoritePart() -> String {
        random(from: favoriteReplies, fallback: "That is a wonderful favorite part.")
    }

    static func responseQuestionRedirect() -> String {
        random(from: redirectReplies, fallback: "Let's answer this question together.")
    }

    static func responseGenericConversation() -> String {
        random(from: genericConversationReplies, fallback: "I like hearing your idea. Let's keep reading.")
    }

    private static func random(from values: [String], fallback: String) -> String {
        values.randomElement() ?? fallback
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
