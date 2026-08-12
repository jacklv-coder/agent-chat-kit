import Foundation

enum AgentStrings {
    static var input: String { String(localized: "Input", bundle: .module) }
    static var output: String { String(localized: "Output", bundle: .module) }
    static var image: String { String(localized: "Image", bundle: .module) }
    static var results: String { String(localized: "results", bundle: .module) }
    static var payload: String { String(localized: "Payload", bundle: .module) }
    static var command: String { String(localized: "Command", bundle: .module) }
    static var fileSearch: String { String(localized: "File search", bundle: .module) }
    static var changes: String { String(localized: "Changes", bundle: .module) }
    static var risk: String { String(localized: "Risk", bundle: .module) }
    static var open: String { String(localized: "Open", bundle: .module) }
    static var retry: String { String(localized: "Retry", bundle: .module) }
    static var outputTruncated: String { String(localized: "Output truncated", bundle: .module) }
    static var imageProvidedByHost: String {
        String(localized: "Image provided by host", bundle: .module)
    }
    static var imageUnavailable: String {
        String(localized: "Image unavailable", bundle: .module)
    }
    static var loadingImage: String {
        String(localized: "Loading image", bundle: .module)
    }
    static var queued: String { String(localized: "Queued", bundle: .module) }
    static var streaming: String { String(localized: "Streaming", bundle: .module) }
    static var running: String { String(localized: "Running", bundle: .module) }
    static var waitingForApproval: String {
        String(localized: "Waiting for approval", bundle: .module)
    }
    static var succeeded: String { String(localized: "Succeeded", bundle: .module) }
    static var failed: String { String(localized: "Failed", bundle: .module) }
    static var cancelled: String { String(localized: "Cancelled", bundle: .module) }
    static var messagePlaceholder: String { String(localized: "Message", bundle: .module) }
    static var send: String { String(localized: "Send", bundle: .module) }
    static var stop: String { String(localized: "Stop", bundle: .module) }
    static var attach: String { String(localized: "Attach", bundle: .module) }
    static var uploading: String { String(localized: "Uploading", bundle: .module) }
    static var removeAttachment: String {
        String(localized: "Remove attachment", bundle: .module)
    }
    static var jumpToLatest: String { String(localized: "Jump to latest", bundle: .module) }
    static var offline: String { String(localized: "Offline", bundle: .module) }
    static var connecting: String { String(localized: "Connecting", bundle: .module) }
    static var you: String { String(localized: "You", bundle: .module) }
    static var assistant: String { String(localized: "Assistant", bundle: .module) }
    static var system: String { String(localized: "System", bundle: .module) }
    static var copyRawPayload: String { String(localized: "Copy raw payload", bundle: .module) }
    static var collapse: String { String(localized: "Collapse", bundle: .module) }
    static var created: String { String(localized: "Created", bundle: .module) }
    static var deleted: String { String(localized: "Deleted", bundle: .module) }
    static var edited: String { String(localized: "Edited", bundle: .module) }
    static var expand: String { String(localized: "Expand", bundle: .module) }
    static var moved: String { String(localized: "Moved", bundle: .module) }
    static var ran: String { String(localized: "Ran", bundle: .module) }
    static var read: String { String(localized: "Read", bundle: .module) }
    static var thinking: String { String(localized: "Thinking", bundle: .module) }
    static var thought: String { String(localized: "Thought", bundle: .module) }
    static var thinkingFailed: String {
        String(localized: "Thinking failed", bundle: .module)
    }
    static var thinkingCancelled: String {
        String(localized: "Thinking cancelled", bundle: .module)
    }
}
