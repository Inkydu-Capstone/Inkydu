import Combine
import Foundation

@MainActor
final class StoryController: ObservableObject {
    @Published private(set) var pages: [StoryPage] = []
    @Published private(set) var currentPageIndex: Int = 0
    @Published private(set) var currentPage: StoryPage?

    var canGoBack: Bool {
        currentPageIndex > 0
    }

    var canGoForward: Bool {
        currentPage != nil
    }

    func loadStoryJSON(named fileName: String, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: fileName, withExtension: "json") else {
            print("Could not find \(fileName).json in the app bundle.")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(StoryDocument.self, from: data)
            pages = document.pages
            currentPageIndex = 0
            currentPage = nil
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
    }

    func goToNextPage() {
        let nextIndex = currentPageIndex + 1

        if nextIndex < pages.count {
            currentPageIndex = nextIndex
            currentPage = pages[currentPageIndex]
        } else {
            currentPage = nil
        }
    }

    func goToPreviousPage() {
        let previousIndex = currentPageIndex - 1
        guard previousIndex >= 0 else { return }

        currentPageIndex = previousIndex
        currentPage = pages[currentPageIndex]
    }

    func reset() {
        currentPageIndex = 0
        currentPage = nil
    }
}
