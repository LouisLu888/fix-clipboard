import Foundation
import Security
import Combine

struct CommerceConfig: Codable, Equatable {
    let storeID: Int
    let productID: Int
    let variantID: Int
    let checkoutURL: String
    let priceLabel: String
    let deviceLimit: Int
    var testMode: Bool = false
    var configured: Bool { storeID > 0 && productID > 0 && variantID > 0 }
    var checkout: URL? {
        guard configured, let url = URL(string: checkoutURL), url.scheme == "https",
              let host = url.host, host.hasSuffix(".lemonsqueezy.com"), url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func load() -> CommerceConfig {
        guard let url = Bundle.main.url(forResource: "Commerce", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return CommerceConfig(storeID: 0, productID: 0, variantID: 0, checkoutURL: "", priceLabel: "", deviceLimit: 3)
        }
        return value
    }
}

struct LicenseResponse: Decodable {
    struct Key: Decodable { let status: String }
    struct Instance: Decodable { let id: String }
    struct Meta: Decodable { let store_id: Int; let product_id: Int; let variant_id: Int }
    let activated: Bool?
    let valid: Bool?
    let deactivated: Bool?
    let license_key: Key?
    let instance: Instance?
    let meta: Meta?
    func belongs(to config: CommerceConfig) -> Bool {
        config.configured && meta?.store_id == config.storeID && meta?.product_id == config.productID && meta?.variant_id == config.variantID
    }
}

enum LicenseFailure: LocalizedError {
    case network, response, rejected, product, storage, unconfigured
    var errorDescription: String? {
        switch self {
        case .network: return "暂时无法连接验证服务，请检查网络后重试。已有授权在最近验证后保留 7 天离线宽限。"
        case .response: return "验证服务返回异常，未解锁 Pro。请稍后重试。"
        case .rejected: return "License 无效、已停用或激活名额已满。请检查购买邮件，或联系卖家管理激活设备。"
        case .product: return "此 License 不属于当前 Pro 商品。请检查购买邮件。"
        case .storage: return "无法读写钥匙串。请解锁登录钥匙串后重试；没有保存成功的授权不会解锁 Pro。"
        case .unconfigured: return "Pro 尚未开放购买和激活，请等待商店配置完成。"
        }
    }
}

protocol LicenseAPI {
    func request(_ action: String, fields: [String: String]) async throws -> LicenseResponse
}
private final class LicenseRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward license credentials through redirects.
    }
}
struct LemonLicenseAPI: LicenseAPI {
    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return fields.keys.sorted().map { key in
            key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + fields[key]!.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&").data(using: .utf8)!
    }
    func request(_ action: String, fields: [String: String]) async throws -> LicenseResponse {
        guard ["activate", "validate", "deactivate"].contains(action) else { throw LicenseFailure.response }
        var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/" + action)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        // No customer email or response body is logged or persisted.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: LicenseRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw LicenseFailure.network }
        guard let http = response as? HTTPURLResponse else { throw LicenseFailure.response }
        return try Self.decode(data, status: http.statusCode)
    }
    static func decode(_ data: Data, status: Int) throws -> LicenseResponse {
        if status == 429 || status >= 500 { throw LicenseFailure.network }
        guard (200..<300).contains(status) || [400, 404, 422].contains(status), data.count < 100_000,
              let decoded = try? JSONDecoder().decode(LicenseResponse.self, from: data) else { throw LicenseFailure.response }
        return decoded
    }
}

protocol LicenseVault {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data?, account: String) throws
}
struct KeychainVault: LicenseVault {
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.louis.fixclipboard.license", kSecAttrAccount as String: account]
    }
    func read(_ account: String) throws -> Data? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let code = SecItemCopyMatching(q as CFDictionary, &result)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = result as? Data else { throw LicenseFailure.storage }
        return data
    }
    func write(_ data: Data?, account: String) throws {
        let q = query(account)
        guard let data else {
            let code = SecItemDelete(q as CFDictionary)
            guard code == errSecSuccess || code == errSecItemNotFound else { throw LicenseFailure.storage }
            return
        }
        let code = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if code == errSecItemNotFound {
            var addition = q; addition[kSecValueData as String] = data
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else { throw LicenseFailure.storage }
        } else if code != errSecSuccess { throw LicenseFailure.storage }
    }
}

struct SavedLicense: Codable {
    let key: String
    let instanceID: String
    let storeID: Int
    let productID: Int
    let variantID: Int
    var validatedAt: Date
    var revoked: Bool = false
    func grantsPro(config: CommerceConfig, now: Date) -> Bool {
        let age = now.timeIntervalSince(validatedAt)
        return !revoked && config.configured && storeID == config.storeID && productID == config.productID && variantID == config.variantID && !instanceID.isEmpty && age >= -300 && age <= 7 * 86400
    }
}

// UI operations are serialized on the main queue; test doubles never touch Keychain or the network.
final class LicenseStore: ObservableObject {
    let config: CommerceConfig
    private let api: LicenseAPI
    private let vault: LicenseVault
    private let now: () -> Date
    private var saved: SavedLicense?
    @Published private(set) var isPro = false
    @Published private(set) var busy = false
    @Published private(set) var message = "手动修复和基础诊断永久免费。"
    @Published private(set) var hasLicense = false
    var permitsAutomaticRepair: Bool { saved?.grantsPro(config: config, now: now()) == true }
    var onChange: (() -> Void)?
    init(config: CommerceConfig = .load(), api: LicenseAPI = LemonLicenseAPI(), vault: LicenseVault = KeychainVault(), now: @escaping () -> Date = Date.init) {
        self.config = config; self.api = api; self.vault = vault; self.now = now
    }
    func load() {
        saved = nil
        do {
            if let data = try vault.read("license") { saved = try JSONDecoder().decode(SavedLicense.self, from: data) }
            updateAccess()
        } catch { updateAccess(); message = LicenseFailure.storage.localizedDescription }
    }
    func updateAccess() {
        isPro = saved?.grantsPro(config: config, now: now()) == true
        hasLicense = saved != nil
        onChange?()
    }
    private func persist(_ value: SavedLicense) throws {
        try vault.write(JSONEncoder().encode(value), account: "license")
        saved = value
        updateAccess()
    }
    private func installID() throws -> String {
        if let data = try vault.read("install-id"), let value = String(data: data, encoding: .utf8), UUID(uuidString: value) != nil { return value }
        let value = UUID().uuidString
        try vault.write(Data(value.utf8), account: "install-id")
        return value
    }
    @MainActor func activate(_ input: String) async {
        guard !busy else { return }
        guard config.configured else { message = LicenseFailure.unconfigured.localizedDescription; return }
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 256 else { message = "请输入购买邮件中的 License Key。"; return }
        if saved != nil { message = "此 Mac 已保存授权。请先重新验证，或停用当前授权后再输入新 Key。"; return }
        busy = true; defer { busy = false }
        do {
            let id = try installID()
            // Preflight rejects keys for another product before consuming an activation slot.
            let check = try await api.request("validate", fields: ["license_key": key])
            guard check.valid == true else { throw LicenseFailure.rejected }
            guard check.belongs(to: config) else { throw LicenseFailure.product }
            let response = try await api.request("activate", fields: ["license_key": key, "instance_name": "Fix Clipboard " + id])
            guard response.activated == true, response.license_key?.status == "active", let instance = response.instance, !instance.id.isEmpty else { throw LicenseFailure.rejected }
            guard response.belongs(to: config) else { throw LicenseFailure.product }
            let record = SavedLicense(key: key, instanceID: instance.id, storeID: config.storeID, productID: config.productID, variantID: config.variantID, validatedAt: now())
            do { try persist(record) }
            catch {
                // Do not leave an unused paid slot behind when local persistence fails.
                _ = try? await api.request("deactivate", fields: ["license_key": key, "instance_id": instance.id])
                throw LicenseFailure.storage
            }
            message = "Pro 已激活。现在可以在菜单中开启自动修复。"
        } catch {
            message = error.localizedDescription + " 如激活时网络中断，请先在商店确认名额，避免重复激活。"
        }
    }
    @MainActor func validate() async {
        guard !busy else { return }
        updateAccess()
        guard config.configured, var record = saved else { return }
        busy = true; defer { busy = false }
        do {
            let response = try await api.request("validate", fields: ["license_key": record.key, "instance_id": record.instanceID])
            guard let valid = response.valid else { throw LicenseFailure.response }
            if !valid || !response.belongs(to: config) || response.license_key?.status != "active" || response.instance?.id != record.instanceID {
                record.revoked = true
                // Revoke in memory even when the Keychain is temporarily unavailable.
                saved = record; updateAccess()
                try persist(record)
                message = "授权已失效，自动修复已暂停。手动修复仍可使用。"
                return
            }
            record.revoked = false; record.validatedAt = now()
            try persist(record)
            message = "Pro 授权有效。"
        } catch { updateAccess(); message = error.localizedDescription }
    }
    func forgetInvalidLicense() {
        guard !busy, !permitsAutomaticRepair else { return }
        do {
            try vault.write(nil, account: "license")
            saved = nil; updateAccess()
            message = "本机授权记录已移除。这不会释放服务端名额；如有需要，请联系卖家处理。"
        } catch { message = error.localizedDescription }
    }
    @MainActor func deactivate() async {
        guard !busy, let record = saved else { return }
        busy = true; defer { busy = false }
        do {
            let result = try await api.request("deactivate", fields: ["license_key": record.key, "instance_id": record.instanceID])
            guard result.deactivated == true else { throw LicenseFailure.rejected }
            saved = nil; updateAccess()
            try vault.write(nil, account: "license")
            message = "此 Mac 已停用，激活名额已释放。"
        } catch { message = error.localizedDescription }
    }
}
