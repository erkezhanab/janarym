import Combine
import Foundation

/// Provides offline-capable AI analysis using on-device Vision.
/// Use when network is unavailable or as a lightweight fallback.
final class LocalAIService: ObservableObject {

    static let shared = LocalAIService()

    private let visionAnalyzer = LocalVisionAnalyzer()

    var isNetworkAvailable: Bool { NetworkMonitor.shared.isConnected }

    private init() {}

    /// Analyse a camera frame locally and return a text description.
    func analyzeFrame(_ jpegData: Data?) async -> String {
        let language = OnboardingStore.shared.profile.language
        guard let data = jpegData, !data.isEmpty else {
            return noFrameMessage(language: language)
        }
        return await visionAnalyzer.analyze(jpegData: data, language: language)
    }

    // MARK: - Localised helpers

    private func noFrameMessage(language: UserProfile.Language) -> String {
        switch language {
        case .kazakh:  return "Камерадан сурет алынбады."
        case .russian: return "Кадр с камеры недоступен."
        case .english: return "No camera frame available."
        }
    }
}
