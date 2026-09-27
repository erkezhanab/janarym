import Foundation
import FirebaseAuth

/// Supplies the Firebase ID token that authenticates every call to the Janarym
/// OpenAI proxy. The OpenAI key itself lives only in Cloudflare Worker secrets.
enum ProxyAuth {
    static func authorize(_ request: inout URLRequest) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AppError.missingAPIKey
        }
        let token: String
        do {
            token = try await user.getIDToken()
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
