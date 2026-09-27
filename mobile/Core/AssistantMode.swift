import Foundation
import SwiftUI

enum AssistantMode: String, CaseIterable {
    case idle
    case recording
    case processing
    case speaking
    case error

    var localizedTitle: String {
        let lang = OnboardingStore.shared.profile.language
        switch (self, lang) {
        case (.idle,       .kazakh):  return "Күту режимі"
        case (.idle,       .russian): return "Ожидание"
        case (.idle,       .english): return "Idle"
        case (.recording,  .kazakh):  return "Тыңдап тұр"
        case (.recording,  .russian): return "Слушаю"
        case (.recording,  .english): return "Listening"
        case (.processing, .kazakh):  return "Өңдеуде"
        case (.processing, .russian): return "Обрабатываю"
        case (.processing, .english): return "Processing"
        case (.speaking,   .kazakh):  return "Сөйлеп тұр"
        case (.speaking,   .russian): return "Говорю"
        case (.speaking,   .english): return "Speaking"
        case (.error,      .kazakh):  return "Қате"
        case (.error,      .russian): return "Ошибка"
        case (.error,      .english): return "Error"
        }
    }

    var sfSymbol: String {
        switch self {
        case .idle:       return "circle.fill"
        case .recording:  return "mic.fill"
        case .processing: return "waveform"
        case .speaking:   return "speaker.wave.3.fill"
        case .error:      return "exclamationmark.circle.fill"
        }
    }

    // Orb outer gradient colors (dark → vibrant)
    var gradientColors: [Color] {
        switch self {
        case .idle:       return [Color(hex: "334155"), Color(hex: "0F172A")]
        case .recording:  return [Color(hex: "F59E0B"), Color(hex: "92400E")]
        case .processing: return [Color(hex: "8B5CF6"), Color(hex: "4C1D95")]
        case .speaking:   return [Color(hex: "34D399"), Color(hex: "064E3B")]
        case .error:      return [Color(hex: "EF4444"), Color(hex: "7F1D1D")]
        }
    }

    // Glow and accent color
    var accentColor: Color {
        switch self {
        case .idle:       return Color(hex: "475569")
        case .recording:  return Color(hex: "F59E0B")
        case .processing: return Color(hex: "A78BFA")
        case .speaking:   return Color(hex: "34D399")
        case .error:      return Color(hex: "EF4444")
        }
    }

    // Inner circle fill
    var innerColor: Color {
        switch self {
        case .idle:       return Color(hex: "1E293B").opacity(0.82)
        case .recording:  return Color(hex: "1C0800").opacity(0.78)
        case .processing: return Color(hex: "1A0050").opacity(0.78)
        case .speaking:   return Color(hex: "012B1D").opacity(0.78)
        case .error:      return Color(hex: "1C0000").opacity(0.78)
        }
    }

    // Animation pulse strength (0 = static, 1 = max)
    var pulseFactor: Double {
        switch self {
        case .idle:       return 0.0
        case .recording:  return 0.9
        case .processing: return 0.7
        case .speaking:   return 0.7
        case .error:      return 0.2
        }
    }

    var isListening: Bool { self == .idle }
}
