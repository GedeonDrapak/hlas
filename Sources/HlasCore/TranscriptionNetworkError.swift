import Foundation

public enum TranscriptionNetworkError: LocalizedError {
    case http(statusCode: Int, provider: String)
    case invalidResponse(provider: String)
    case offline
    case timedOut(provider: String)
    case unavailable(provider: String)

    public static func from(_ error: Error, provider: String) -> TranscriptionNetworkError {
        let urlError = error as? URLError
        switch urlError?.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return .offline
        case .timedOut:
            return .timedOut(provider: provider)
        default:
            return .unavailable(provider: provider)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .http(let statusCode, let provider):
            switch statusCode {
            case 401, 403:
                return "Your \(provider) API key was rejected. Check it in Settings."
            case 402:
                return "Your \(provider) account is out of credit. Top it up or choose another engine in Settings."
            case 413:
                return "This recording is too large for \(provider)."
            case 429:
                return "\(provider) has reached a limit. Try again in a moment."
            case 500...599:
                return "\(provider) is temporarily unavailable. Try again shortly."
            default:
                return "\(provider) could not transcribe this recording. Try again."
            }
        case .invalidResponse(let provider):
            return "\(provider) returned an unreadable response. Try again."
        case .offline:
            return "No internet connection. Choose Local in Settings or reconnect."
        case .timedOut(let provider):
            return "\(provider) took too long to respond. Try again."
        case .unavailable(let provider):
            return "Could not reach \(provider). Check your connection and try again."
        }
    }
}
