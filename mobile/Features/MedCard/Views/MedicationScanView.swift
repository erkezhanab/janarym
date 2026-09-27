import SwiftUI
import UIKit

// MARK: - MedicationScanView
// Camera/gallery picker → base64 JPEG → OpenAI GPT-4.1 Vision → JSON parse → pre-fill form.

struct MedicationScanView: View {

    @Environment(\.dismiss) private var dismiss
    let onScanned: (Medication) -> Void

    private var kk: Bool { OnboardingStore.shared.profile.language == .kazakh }

    @State private var showPicker    = false
    @State private var pickerSource: UIImagePickerController.SourceType = .camera
    @State private var capturedImage: UIImage?  = nil
    @State private var isAnalyzing   = false
    @State private var errorMessage: String?    = nil
    @State private var result: Medication?      = nil

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Navigation bar ───────────────────────────────────
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(10)
                            .background(Color.white.opacity(0.09))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kk ? "Жабу" : "Закрыть")

                    Spacer()
                    Text(kk ? "Дәрі сканері" : "Сканер препарата")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36) // balance
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                // ── Image preview / placeholder ──────────────────────
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
                        )

                    if let img = capturedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 17))
                            .padding(4)
                            .accessibilityLabel(kk ? "Түсірілген сурет" : "Сделанный снимок")
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "pill.circle")
                                .font(.system(size: 58))
                                .foregroundStyle(Color.green.opacity(0.5))
                                .accessibilityHidden(true)
                            Text(kk
                                 ? "Дәрінің орамасын немесе\nрецептін суретке түсіріңіз"
                                 : "Сфотографируйте упаковку\nили рецепт препарата")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.45))
                                .multilineTextAlignment(.center)
                        }
                    }

                    // Analyzing spinner
                    if isAnalyzing {
                        RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.6))
                        VStack(spacing: 14) {
                            ProgressView().tint(.green).scaleEffect(1.4)
                            Text(kk ? "GPT талдап жатыр…" : "GPT анализирует…")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 270)
                .padding(.horizontal, 20)

                // ── Error ────────────────────────────────────────────
                if let err = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                // ── Scanned result card ──────────────────────────────
                if let med = result {
                    ScanResultCard(med: med, kk: kk)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }

                Spacer()

                // ── Action buttons ───────────────────────────────────
                VStack(spacing: 12) {
                    if result == nil {
                        // Camera
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            ScanActionButton(
                                label: kk ? "Камерамен түсіру" : "Снять камерой",
                                icon: "camera.fill",
                                color: .green
                            ) {
                                pickerSource = .camera
                                showPicker   = true
                                errorMessage = nil
                            }
                        }
                        // Gallery
                        ScanActionButton(
                            label: kk ? "Галереядан таңдау" : "Выбрать из галереи",
                            icon: "photo.on.rectangle",
                            color: Color(red: 0.4, green: 0.6, blue: 1.0)
                        ) {
                            pickerSource = .photoLibrary
                            showPicker   = true
                            errorMessage = nil
                        }
                    } else {
                        // Confirm
                        ScanActionButton(
                            label: kk ? "Тізімге қосу" : "Добавить в список",
                            icon: "checkmark.circle.fill",
                            color: .green
                        ) {
                            if let med = result { onScanned(med) }
                            dismiss()
                        }
                        // Retry
                        Button {
                            result = nil
                            capturedImage = nil
                            errorMessage = nil
                        } label: {
                            Text(kk ? "Қайта сканерлеу" : "Сканировать снова")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPicker) {
            ImagePickerBridge(image: $capturedImage, sourceType: pickerSource)
                .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { img in
            guard let img else { return }
            Task { await analyzeImage(img) }
        }
    }

    // MARK: - OpenAI Vision call

    private func analyzeImage(_ image: UIImage) async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        guard let jpeg = image.jpegData(compressionQuality: 0.75) else {
            errorMessage = kk ? "Суретті кодтау қатесі" : "Ошибка кодирования изображения"
            return
        }

        let prompt = """
        Extract medication information from this image. \
        Return ONLY a raw JSON object — no markdown, no code fences, no explanation: \
        {"name":"","dosage":"","morning":false,"afternoon":false,"evening":false,"night":false,"notes":""}
        """

        let payload: [String: Any] = [
            "model": AppConfig.openAIVisionModel,
            "max_tokens": 300,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]
                    ],
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ]]
        ]

        do {
            let data = try await sendMedScanRequest(payload: payload)

            guard
                let root    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = root["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let text    = message["content"] as? String
            else {
                errorMessage = kk ? "Жауапты оқу қатесі" : "Не удалось прочитать ответ"
                return
            }

            if let med = parseMedication(from: text) {
                result = med
            } else {
                errorMessage = kk ? "Дәрі ақпараты анықталмады" : "Информация о препарате не найдена"
            }
        } catch {
            errorMessage = kk
                ? "Желі қатесі: \(error.localizedDescription)"
                : "Ошибка сети: \(error.localizedDescription)"
        }
    }

    // MARK: - Network

    private func sendMedScanRequest(payload: [String: Any]) async throws -> Data {
        // All AI traffic goes through the authenticated proxy — the app never holds an OpenAI key.
        guard !AppConfig.openAIProxyURL.isEmpty, let proxyURL = URL(string: AppConfig.openAIProxyURL) else {
            throw AppError.missingAPIKey
        }

        let content = (payload["messages"] as? [[String: Any]])
            .flatMap { $0.first?["content"] as? [[String: Any]] }
        let jpegBase64 = content
            .flatMap { $0.first(where: { $0["type"] as? String == "image_url" }) }
            .flatMap { ($0["image_url"] as? [String: String])?["url"] }
            .flatMap { $0.components(separatedBy: "base64,").last } ?? ""
        let instruction = content
            .flatMap { $0.first(where: { $0["type"] as? String == "text" })?["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let proxyPayload: [String: Any] = [
            // The proxy needs a non-empty instruction even when the frame carries the information.
            "text": instruction ?? Self.defaultScanInstruction,
            "prompt": "You are a medication scanner. Extract medication info from the image and return JSON only.",
            "language": "ru",
            "output_language": "Russian",
            "response_model": AppConfig.openAIVisionModel,
            "image_base64": jpegBase64,
            "include_audio": false
        ]

        var req = URLRequest(url: proxyURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: proxyPayload)
        try await ProxyAuth.authorize(&req)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AppError.networkError("HTTP error")
        }
        // Proxy returns {response_text:...} — wrap into choices format for unified parse
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["response_text"] as? String ?? json["response"] as? String else {
            throw AppError.assistantResponseFailed("Empty proxy response")
        }
        return try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text]]]])
    }

    private static let defaultScanInstruction =
        "Определи лекарство на изображении и верни только JSON."

    // MARK: - Parse

    private func parseMedication(from text: String) -> Medication? {
        // Strip accidental markdown fences
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract the first {...} block if there's surrounding prose
        if let start = cleaned.firstIndex(of: "{"),
           let end   = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        guard
            let data = cleaned.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var med       = Medication()
        med.name      = (json["name"]      as? String) ?? ""
        med.dosage    = (json["dosage"]    as? String) ?? ""
        med.morning   = (json["morning"]   as? Bool)   ?? false
        med.afternoon = (json["afternoon"] as? Bool)   ?? false
        med.evening   = (json["evening"]   as? Bool)   ?? false
        med.night     = (json["night"]     as? Bool)   ?? false
        med.notes     = (json["notes"]     as? String) ?? ""
        return med.name.isEmpty ? nil : med
    }
}

// MARK: - ScanResultCard

private struct ScanResultCard: View {
    let med: Medication
    let kk: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(kk ? "Анықталды" : "Распознано")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
            }
            Text(med.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            if !med.dosage.isEmpty {
                Text(med.dosage)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Text(med.scheduleString(kk: kk))
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
            if !med.notes.isEmpty {
                Text(med.notes)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.green.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(kk ? "Анықталды" : "Распознано"): \(med.name), \(med.dosage), \(med.scheduleString(kk: kk))"
        )
    }
}

// MARK: - ScanActionButton

private struct ScanActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - UIImagePickerController wrapper

struct ImagePickerBridge: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType     = sourceType
        vc.delegate       = context.coordinator
        vc.allowsEditing  = false
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject,
                              UIImagePickerControllerDelegate,
                              UINavigationControllerDelegate {
        let parent: ImagePickerBridge
        init(_ p: ImagePickerBridge) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
