import Foundation
import CryptoKit

struct ManualLicensePayload: Codable {
    let version: Int
    let product: String
    let order: String
    let installation: String
}
enum ManualLicense {
    static func verify(_ token: String, publicKey: String, installation: String) -> Bool {
        guard token.count <= 2048 else { return false }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "FC1",
              let payload = Data(base64Encoded: String(parts[1])),
              let signature = Data(base64Encoded: String(parts[2])),
              let raw = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              key.isValidSignature(signature, for: payload),
              let value = try? JSONDecoder().decode(ManualLicensePayload.self, from: payload) else { return false }
        return value.version == 1 && value.product == "fix-clipboard-pro-v1" && !value.order.isEmpty &&
            UUID(uuidString: installation) != nil && value.installation == installation
    }
}
