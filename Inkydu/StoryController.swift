//
//  StoryController.swift
//  Inkydu
//
//  Created by Riley Fisher on 4/19/26.
//

import Foundation
import SwiftUI
import Combine

final class StoryController: ObservableObject {
    enum FeedbackStyle {
        case none
        case prompt
        case listening
        case correct
        case incorrect
        case retry
        case unclear

        var title: String {
            switch self {
            case .none:
                return ""
            case .prompt:
                return "Your Turn"
            case .listening:
                return "Listening"
            case .correct:
                return "Correct!"
            case .incorrect:
                return "Try Again"
            case .retry:
                return "Let's Think"
            case .unclear:
                return "I Didn't Hear That"
            }
        }
    }

    @Published var pages: [StoryPage] = []
    @Published var currentPageIndex: Int = 0
    @Published var currentPage: StoryPage?
    @Published var teacherMessage: String = ""
    @Published var lastHeardSpeech: String = ""
    @Published var showFallbackButtons: Bool = true
    @Published var isStoryFinished: Bool = false
    @Published var didAnswerCurrentPageCorrectly: Bool = false
    @Published var feedbackStyle: FeedbackStyle = .none

    private var retryCount: Int = 0
    private let maxRetries: Int = 2

    var canGoBack: Bool {
        currentPageIndex > 0
    }

    var canGoForward: Bool {
        currentPage != nil
    }

    var feedbackTitle: String {
        feedbackStyle.title
    }

    var hasFeedback: Bool {
        feedbackStyle != .none && !teacherMessage.isEmpty
    }

    func loadStoryJSON(named fileName: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print("Could not find \(fileName).json in app bundle.")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(StoryDocument.self, from: data)
            pages = document.pages
            currentPageIndex = 0
            currentPage = nil
            teacherMessage = ""
            lastHeardSpeech = ""
            showFallbackButtons = true
            isStoryFinished = false
            retryCount = 0
            didAnswerCurrentPageCorrectly = false
            feedbackStyle = .none
        } catch {
            print("Failed to load or decode story JSON: \(error)")
        }
    }

    func startStory() {
        guard !pages.isEmpty else {
            print("No story pages loaded.")
            return
        }

        currentPageIndex = 0
        currentPage = pages[currentPageIndex]
        teacherMessage = ""
        lastHeardSpeech = ""
        showFallbackButtons = true
        retryCount = 0
        isStoryFinished = false
        didAnswerCurrentPageCorrectly = false
        feedbackStyle = .none
    }

    func prepareCurrentPageForDisplay() {
        teacherMessage = ""
        lastHeardSpeech = ""
        retryCount = 0
        didAnswerCurrentPageCorrectly = false
        showFallbackButtons = true
        feedbackStyle = .none
    }

    func clearFeedback() {
        teacherMessage = ""
        feedbackStyle = .none
    }

    func showQuestionPrompt() {
        feedbackStyle = .prompt
        teacherMessage = TeacherResponses.responseFallback()
    }

    func goToNextPage() {
        let nextIndex = currentPageIndex + 1

        if nextIndex < pages.count {
            currentPageIndex = nextIndex
            currentPage = pages[currentPageIndex]
            prepareCurrentPageForDisplay()
        } else {
            currentPage = nil
            teacherMessage = "The End!"
            lastHeardSpeech = ""
            showFallbackButtons = false
            isStoryFinished = true
            didAnswerCurrentPageCorrectly = false
            feedbackStyle = .none
        }
    }

    func goToPreviousPage() {
        let previousIndex = currentPageIndex - 1
        guard previousIndex >= 0 else { return }

        currentPageIndex = previousIndex
        currentPage = pages[currentPageIndex]
        isStoryFinished = false
        prepareCurrentPageForDisplay()
    }

    func continueFromNarrationOnlyPage() {
        goToNextPage()
    }

    func repeatPage() {
        guard currentPage != nil else { return }
        teacherMessage = TeacherResponses.responseFallback()
        feedbackStyle = .prompt
    }

    func beginListening() {
        teacherMessage = TeacherResponses.responseListeningPrompt()
        feedbackStyle = .listening
        lastHeardSpeech = ""
    }

    func handleSpeechUnavailable(_ message: String) {
        teacherMessage = TeacherResponses.responseSpeechUnclear()
        feedbackStyle = .unclear
        lastHeardSpeech = message
        showFallbackButtons = true
    }

    func handleRecognizedSpeech(_ transcript: String) {
        lastHeardSpeech = transcript
        handleAnswer(transcript)
    }

    func handleAnswer(_ selected: String) {
        guard let page = currentPage else { return }

        guard let correctAnswer = page.correct_answer else {
            teacherMessage = TeacherResponses.responseEncouragement()
            feedbackStyle = .correct
            didAnswerCurrentPageCorrectly = true
            return
        }

        let cleanedSelected = selected
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let cleanedCorrect = correctAnswer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let isCorrect =
            cleanedSelected == cleanedCorrect ||
            cleanedSelected.contains(cleanedCorrect)

        if isCorrect {
            teacherMessage = TeacherResponses.responseEncouragement()
            feedbackStyle = .correct
            retryCount = 0
            showFallbackButtons = true
            didAnswerCurrentPageCorrectly = true
        } else {
            retryCount += 1
            didAnswerCurrentPageCorrectly = false

            if retryCount >= maxRetries {
                teacherMessage = TeacherResponses.responseEncourageRetry()
                feedbackStyle = .retry
                showFallbackButtons = true
            } else {
                teacherMessage = TeacherResponses.responseIncorrectAnswer()
                feedbackStyle = .incorrect
                showFallbackButtons = true
            }
        }
    }
}
