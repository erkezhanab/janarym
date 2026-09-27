import Foundation

enum AppError: LocalizedError {
    case permissionDenied(String)
    case cameraUnavailable
    case microphoneUnavailable
    case recordingFailed(String)
    case voiceInputFailed(String)
    case assistantResponseFailed(String)
    case ttsFailed(String)
    case missingAPIKey
    case networkError(String)

    var errorDescription: String? {
        let language = OnboardingStore.shared.currentLanguage
        switch self {
        case .permissionDenied(let detail):
            return AppText.pick("Рұқсат берілмеді: \(detail)", "Доступ не предоставлен: \(detail)", en: "Permission denied: \(detail)", language: language)
        case .cameraUnavailable:
            return AppText.pick("Камера қолжетімсіз", "Камера недоступна", en: "Camera unavailable", language: language)
        case .microphoneUnavailable:
            return AppText.pick("Микрофон қолжетімсіз", "Микрофон недоступен", en: "Microphone unavailable", language: language)
        case .recordingFailed(let detail):
            return AppText.pick("Жазу қатесі: \(detail)", "Ошибка записи: \(detail)", en: "Recording failed: \(detail)", language: language)
        case .voiceInputFailed(let detail):
            return AppText.pick("Дауыс енгізу қатесі: \(detail)", "Ошибка голосового ввода: \(detail)", en: "Voice input failed: \(detail)", language: language)
        case .assistantResponseFailed(let detail):
            return AppText.pick("Ассистент жауабының қатесі: \(detail)", "Ошибка ответа ассистента: \(detail)", en: "Assistant response failed: \(detail)", language: language)
        case .ttsFailed(let detail):
            return AppText.pick("TTS қатесі: \(detail)", "Ошибка TTS: \(detail)", en: "Text-to-speech failed: \(detail)", language: language)
        case .missingAPIKey:
            return AppText.pick("Қызметке қосылу қатесі. Баптауларды тексеріңіз", "Ошибка подключения к сервису. Проверьте настройки", en: "Service connection error. Check your settings", language: language)
        case .networkError(let detail):
            return AppText.pick("Желі қатесі: \(detail)", "Сетевая ошибка: \(detail)", en: "Network error: \(detail)", language: language)
        }
    }
}
