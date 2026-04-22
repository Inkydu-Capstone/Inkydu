//
//  StoryModel.swift
//  Inkydu
//
//  Created by Riley Fisher on 4/21/26.
//

import Foundation

struct StoryDocument: Codable {
    let pages: [StoryPage]
}

struct StoryPage: Codable, Identifiable, Equatable {
    let pageID: String
    let narration: String
    let imageName: String?
    let interaction: StoryInteraction?

    var id: String { pageID }
    var page_id: String { pageID }

    enum CodingKeys: String, CodingKey {
        case pageID = "page_id"
        case narration
        case imageName
        case interaction
    }

    init(
        pageID: String,
        narration: String,
        imageName: String? = nil,
        interaction: StoryInteraction? = nil
    ) {
        self.pageID = pageID
        self.narration = narration
        self.imageName = imageName
        self.interaction = interaction
    }
}

struct StoryInteraction: Codable, Equatable {
    let prompt: String
    let expectedAnswer: String?
    let answerAliases: [String]
    let choices: [String]
    let hint: String?
    let answerReveal: String?
    let allowFreeResponse: Bool
    let autoListen: Bool

    init(
        prompt: String,
        expectedAnswer: String? = nil,
        answerAliases: [String] = [],
        choices: [String] = [],
        hint: String? = nil,
        answerReveal: String? = nil,
        allowFreeResponse: Bool = false,
        autoListen: Bool = true
    ) {
        self.prompt = prompt
        self.expectedAnswer = expectedAnswer
        self.answerAliases = answerAliases
        self.choices = choices
        self.hint = hint
        self.answerReveal = answerReveal
        self.allowFreeResponse = allowFreeResponse
        self.autoListen = autoListen
    }
}

enum StoryInteractionFactory {
    static func resolvedInteraction(for page: StoryPage) -> StoryInteraction? {
        if let interaction = page.interaction {
            return interaction
        }

        switch page.pageID {
        case "2":
            return StoryInteraction(
                prompt: "Were the bunnies quiet or loud?",
                expectedAnswer: "loud",
                answerAliases: ["noisy", "very loud", "they were loud"],
                choices: ["quiet", "loud"],
                hint: "They made a big din.",
                answerReveal: "They were loud and noisy."
            )

        case "5":
            return StoryInteraction(
                prompt: "What did they pull from the garden?",
                expectedAnswer: "carrots",
                answerAliases: ["a carrot", "the carrots", "carrot"],
                choices: ["carrots", "flowers"],
                hint: "It was orange and crunchy.",
                answerReveal: "They pulled up carrots."
            )

        case "9":
            return StoryInteraction(
                prompt: "Who ran away and came back?",
                expectedAnswer: "Oinky",
                answerAliases: ["the pig", "pig", "oinky the pig"],
                choices: ["Oinky", "Billy Bob"],
                hint: "It was the pet pig.",
                answerReveal: "Oinky the pig ran away and came back."
            )

        case "11":
            return StoryInteraction(
                prompt: "At the end, were the families fighting or friends?",
                expectedAnswer: "friends",
                answerAliases: ["they were friends", "friends now", "pals"],
                choices: ["fighting", "friends"],
                hint: "They made a truce.",
                answerReveal: "They became friends."
            )

        case "12":
            return StoryInteraction(
                prompt: "What was your favorite part of the story?",
                allowFreeResponse: true,
                autoListen: true
            )

        default:
            return nil
        }
    }
}
