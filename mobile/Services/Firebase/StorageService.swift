import Foundation
import FirebaseStorage
import UIKit

// MARK: - Storage Service
final class StorageService {

    static let shared = StorageService()
    private let storage = Storage.storage()

    private init() {}

    private static func log(_ message: String) {
        print("StorageService:", message)
    }

    // MARK: - Upload Document
    /// PDF немесе суретті Storage-ке жүктейді және download URL қайтарады
    func uploadDocument(data: Data, userId: String, fileName: String) async throws -> String {
        let path = "documents/\(userId)/\(fileName)"
        let ref  = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "application/pdf"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    // MARK: - Upload Profile Image
    func uploadProfileImage(_ image: UIImage, userId: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "StorageService", code: 400,
                         userInfo: [NSLocalizedDescriptionKey: "Image conversion failed"])
        }
        let path = "avatars/\(userId)/profile.jpg"
        let ref  = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    // MARK: - Upload Last Photo (ата-ана бақылауы)
    /// Соңғы камера кадрын Storage-ке жүктейді → URL қайтарады
    func uploadLastPhoto(data: Data, userId: String) async -> String? {
        let path = "presence/\(userId)/lastPhoto.jpg"
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        do {
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let baseURL = try await ref.downloadURL().absoluteString
            Self.log("last photo uploaded for \(userId)")
            return "\(baseURL)&ts=\(Int(Date().timeIntervalSince1970 * 1000))"
        } catch {
            Self.log("last photo upload failed for \(userId): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete File
    func deleteFile(at urlString: String) async throws {
        let ref = storage.reference(forURL: urlString)
        try await ref.delete()
    }
}
