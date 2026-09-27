import Foundation
import UIKit
import Vision

final class LocalVisionAnalyzer {

    func analyze(jpegData: Data, language: UserProfile.Language) async -> String {
        guard let image = UIImage(data: jpegData), let cgImage = image.cgImage else {
            return fallbackNoImage(language: language)
        }
        let classifications = await classifyImage(cgImage)
        return buildDescription(classifications: classifications, language: language)
    }

    // MARK: - Vision

    private func classifyImage(_ cgImage: CGImage) async -> [VNClassificationObservation] {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, _ in
                let results = (request.results as? [VNClassificationObservation] ?? [])
                    .filter { $0.confidence > 0.15 }
                    .prefix(5)
                continuation.resume(returning: Array(results))
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private func buildDescription(
        classifications: [VNClassificationObservation],
        language: UserProfile.Language
    ) -> String {
        guard !classifications.isEmpty else {
            return fallbackUnclear(language: language)
        }
        let labels = classifications.map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        let joined = labels.joined(separator: ", ")
        switch language {
        case .kazakh:
            return "Жергілікті талдау: \(joined)."
        case .russian:
            return "Локальный анализ: \(joined)."
        case .english:
            return "Local analysis: \(joined)."
        }
    }

    // MARK: - Fallback strings

    private func fallbackNoImage(language: UserProfile.Language) -> String {
        switch language {
        case .kazakh:  return "Сурет жоқ."
        case .russian: return "Изображение недоступно."
        case .english: return "No image available."
        }
    }

    private func fallbackUnclear(language: UserProfile.Language) -> String {
        switch language {
        case .kazakh:  return "Кескінді тани алмадым."
        case .russian: return "Не удалось распознать изображение."
        case .english: return "Could not recognize the image."
        }
    }
}
