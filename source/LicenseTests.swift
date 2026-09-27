import Foundation

private final class MemoryVault: LicenseVault {
    var values: [String: Data] = [:]
    var failLicenseWrite = false
    func read(_ account: String) throws -> Data? { values[account] }
    func write(_ data: Data?, account: String) throws {
        if failLicenseWrite && account == "license" { throw LicenseFailure.storage }
        values[account] = data
    }
}
private final class MockLicenseAPI: LicenseAPI {
    var results: [Result<LicenseResponse, Error>] = []
    var calls: [(String, [String: String])] = []
    func request(_ action: String, fields: [String: String]) async throws -> LicenseResponse {
        calls.append((action, fields))
        guard !results.isEmpty else { fatalError("Unexpected API call") }
        return try results.removeFirst().get()
    }
}

@MainActor func runLicenseTests() async {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("License regression: " + name) }
        count += 1
    }
    let config = CommerceConfig(storeID: 11, productID: 22, variantID: 33, checkoutURL: "https://example.lemonsqueezy.com/buy/product", priceLabel: "test", deviceLimit: 3)
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    var clock = time
    func response(_ fields: String, product: Int = 22, status: String = "active", instance: String = "instance-test") -> LicenseResponse {
        let json = "{\(fields),\"license_key\":{\"status\":\"\(status)\"},\"instance\":{\"id\":\"\(instance)\"},\"meta\":{\"store_id\":11,\"product_id\":\(product),\"variant_id\":33}}"
        return try! JSONDecoder().decode(LicenseResponse.self, from: Data(json.utf8))
    }
    let valid = response("\"valid\":true")
    let activated = response("\"activated\":true")
    let invalid = response("\"valid\":false", status: "disabled")
    let vault = MemoryVault(); let api = MockLicenseAPI()
    let store = LicenseStore(config: config, api: api, vault: vault, now: { clock })
    store.load()
    check(!store.isPro && !store.permitsAutomaticRepair, "Free by default")
    check(config.checkout != nil, "Valid HTTPS checkout")
    let missing = CommerceConfig(storeID: 0, productID: 0, variantID: 0, checkoutURL: "https://example.lemonsqueezy.com/buy/p", priceLabel: "", deviceLimit: 3)
    check(!missing.configured && missing.checkout == nil, "Unconfigured checkout disabled")
    let evil = CommerceConfig(storeID: 11, productID: 22, variantID: 33, checkoutURL: "https://evil.example/?lemonsqueezy.com", priceLabel: "", deviceLimit: 3)
    check(evil.checkout == nil, "Reject non-provider checkout")
    let form = String(data: LemonLicenseAPI.form(["license_key": "a+b&c= d"]), encoding: .utf8)!
    check(form == "license_key=a%2Bb%26c%3D%20d", "Form escaping")
    let unconfigured = LicenseStore(config: missing, api: api, vault: MemoryVault())
    await unconfigured.activate("test")
    check(api.calls.isEmpty && !unconfigured.isPro, "No network without product configuration")
    api.results = [.success(response("\"valid\":true", product: 999))]
    await store.activate("test-key")
    check(!store.isPro && api.calls.count == 1 && api.calls.last?.0 == "validate", "Foreign product rejected before activation")
    api.results = [.success(valid), .success(response("\"activated\":false"))]
    await store.activate("test-key")
    check(!store.isPro && vault.values["license"] == nil, "Activation limit cannot unlock")
    api.results = [.success(valid), .success(activated)]
    await store.activate(" test-key ")
    check(store.isPro && store.permitsAutomaticRepair && store.hasLicense, "Successful activation")
    let id = String(data: vault.values["install-id"]!, encoding: .utf8)!
    check(UUID(uuidString: id) != nil && api.calls.last?.1["instance_name"] == "Fix Clipboard " + id, "Only random install label")
    check(api.calls.last?.1["license_key"] == "test-key", "Trim pasted key")
    let oldCalls = api.calls.count
    await store.activate("test-key")
    check(api.calls.count == oldCalls, "Repeated activation does not consume slots")
    let reloaded = LicenseStore(config: config, api: api, vault: vault, now: { clock })
    reloaded.load()
    check(reloaded.isPro, "Persisted offline entitlement")
    api.results = [.failure(LicenseFailure.network)]
    clock = time.addingTimeInterval(6 * 86400)
    await store.validate()
    check(store.isPro, "Network outage within grace")
    clock = time.addingTimeInterval(8 * 86400)
    check(!store.permitsAutomaticRepair, "Gate closes at deadline even without timer")
    api.results = [.failure(LicenseFailure.network)]
    await store.validate()
    check(!store.isPro, "Grace expires")
    api.results = [.success(valid)]
    await store.validate()
    check(store.isPro && api.calls.last?.1["instance_id"] == "instance-test", "Validation restores access and binds instance")
    api.results = [.success(invalid)]
    await store.validate()
    check(!store.isPro && !store.permitsAutomaticRepair, "Disabled license immediately revokes")
    reloaded.load()
    check(!reloaded.isPro, "Revocation survives restart")
    api.results = [.success(valid)]
    await store.validate()
    check(store.isPro, "Re-enabled license recovers")
    api.results = [.success(response("\"valid\":true", instance: "other-instance"))]
    await store.validate()
    check(!store.isPro, "Reject wrong activation instance")
    api.results = [.success(valid)]
    await store.validate()
    api.results = [.failure(LicenseFailure.network)]
    await store.deactivate()
    check(store.hasLicense && store.isPro, "Offline deactivation keeps recoverable record")
    api.results = [.success(response("\"deactivated\":true", status: "inactive"))]
    await store.deactivate()
    check(!store.isPro && !store.hasLicense && vault.values["license"] == nil, "Deactivation clears entitlement")
    vault.failLicenseWrite = true
    api.results = [.success(valid), .success(activated), .success(response("\"deactivated\":true"))]
    await store.activate("test-key")
    check(!store.isPro && api.calls.last?.0 == "deactivate", "Failed persistence rolls back activation")
    let record = SavedLicense(key: "test", instanceID: "i", storeID: 11, productID: 22, variantID: 33, validatedAt: time)
    check(!record.grantsPro(config: config, now: time.addingTimeInterval(-1000)), "Clock rollback fails closed")
    check(!record.grantsPro(config: missing, now: time), "Cached entitlement cannot bypass configuration")
    check((try? LemonLicenseAPI.decode(Data("{\"valid\":false}".utf8), status: 400))?.valid == false, "Parse provider rejection")
    check((try? LemonLicenseAPI.decode(Data("not JSON".utf8), status: 200)) == nil, "Malformed JSON rejected")
    check((try? LemonLicenseAPI.decode(Data("{}".utf8), status: 302)) == nil, "Redirect response rejected")
    check((try? LemonLicenseAPI.decode(Data("{}".utf8), status: 429)) == nil, "Rate limit rejected")
    vault.failLicenseWrite = false
    api.results = [.success(valid), .success(activated)]
    await store.activate("test-key")
    store.forgetInvalidLicense()
    check(store.isPro && store.hasLicense, "Valid record cannot be forgotten to skip deactivation")
    api.results = [.success(invalid)]
    await store.validate()
    check(store.hasLicense && !store.isPro, "Retain invalid record before explicit removal")
    store.forgetInvalidLicense()
    check(!store.hasLicense, "Invalid local record can be removed")
    print("PASS: \(count) license regression assertions; fake API and memory vault only. No payment, Keychain access or activation performed.")
}
