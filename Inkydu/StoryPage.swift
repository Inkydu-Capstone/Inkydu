import Foundation

struct TeacherResponseBank: Codable {
    let encouragement: [String]
    let retry: [String]
    let fallback: [String]
}

struct StoryDocument: Codable {
    let teacher_responses: TeacherResponseBank
    let pages: [StoryPage]
}

struct StoryPage: Codable {
    let page_id: String
    let narration: String
    let question: String?
    let choices: [String]?
    let correct_answer: String?
    let allowSpeech: Bool?
    let imageName: String?
}
