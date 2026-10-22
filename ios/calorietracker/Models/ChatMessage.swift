import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let attachmentImageData: Data?
    /// Set on assistant bubbles the router answered without the Coach model.
    var routerAction: RouterChatAction? = nil

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = .now,
        attachmentImageData: Data? = nil,
        routerAction: RouterChatAction? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachmentImageData = attachmentImageData
        self.routerAction = routerAction
    }
}

enum RouterChatAction: Codable, Equatable, Sendable {
    case logFood(String)
    case logWorkout(String)
    case localAnswer
}
