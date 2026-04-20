//
//  TeacherResponses.swift
//  Inkydu
//
//  Created by Riley Fisher on 4/19/26.
//

import Foundation

struct TeacherResponses {
    static let encouragement = [
        "Nice job!",
        "Keep up the great work!",
        "Good thinking!",
        "You're doing amazing!",
        "Great work!",
        "Awesome job!",
        "Way to go!",
        "Brilliant!",
        "Super job!",
        "Excellent work!"
    ]

    static let incorrectAnswer = [
        "That's okay, let's try again.",
        "Nice try! Give it another shot.",
        "Almost there, try one more time!",
        "Good effort! Let's think about it again.",
        "You're close! Try again.",
        "That was a good attempt. Try once more!",
        "Not quite, but you're learning!",
        "Let's try that one again.",
        "You're on the right track, try again!",
        "Mistakes help us learn. Try again!",
        "Take your time and try again.",
        "Almost! Give it another go.",
        "Oops! Let's try again.",
        "You're getting warmer! Try again!",
        "Let's give it another try!"
    ]

    static let speechUnclear = [
        "I didn't quite hear that.",
        "Could you try saying that again?",
        "You can also tap one of the answers.",
        "Hmm, I didn't catch that. Can you say it again?",
        "I'm not sure I heard you clearly.",
        "Can you say that one more time?",
        "I didn't quite understand. Can you say it again?",
        "That was a little hard to hear.",
        "Could you say it a bit louder?",
        "Try saying your answer again.",
        "I'm listening. Go ahead and say it again.",
        "You can say it again or tap your answer.",
        "Let me hear that one more time.",
        "It's okay. Try saying it again!"
    ]

    static let listeningPrompt = [
        "Go ahead and tell me your answer.",
        "I'm listening!",
        "Whenever you're ready, tell me your answer.",
        "You can say your answer out loud.",
        "Tell me what you think.",
        "What's your answer?",
        "Give it a try! What do you think?",
        "Say your answer when you're ready.",
        "Go ahead, I'm listening to you.",
        "What do you think the answer is?",
        "You can tell me your idea.",
        "Try saying your answer.",
        "Let me know what you think."
    ]

    static let encourageRetry = [
        "Let's figure this out together.",
        "We can work through this.",
        "Take your time then try again.",
        "Let's think about it step by step.",
        "Let's give it another look together.",
        "We're learning together!",
        "Let's see if we can solve it.",
        "Think it through and try again.",
        "You're doing great, keep thinking!",
        "Let's take another look at it.",
        "We can solve this together!",
        "Let's slow down and think about it.",
        "Let's work on it.",
        "Let's explore this together."
    ]

    static let fallback = [
        "Listen to the question, then tap an answer or use the microphone.",
        "When the question is done, choose an answer or say it out loud.",
        "Wait for the question to finish, then pick your answer.",
        "You can tap an answer after the question is read."
    ]

    static func responseEncouragement() -> String {
        encouragement.randomElement() ?? "Nice job!"
    }

    static func responseIncorrectAnswer() -> String {
        incorrectAnswer.randomElement() ?? "That's okay, let's try again."
    }

    static func responseSpeechUnclear() -> String {
        speechUnclear.randomElement() ?? "I didn't quite hear that."
    }

    static func responseListeningPrompt() -> String {
        listeningPrompt.randomElement() ?? "I'm listening!"
    }

    static func responseEncourageRetry() -> String {
        encourageRetry.randomElement() ?? "Let's try that again together."
    }

    static func responseFallback() -> String {
        fallback.randomElement() ?? "Listen to the question, then choose your answer."
    }
}
