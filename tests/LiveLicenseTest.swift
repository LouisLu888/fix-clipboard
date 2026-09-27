// Opt-in test: consumes one TEST activation temporarily, then deactivates it.
// Compile together with source/Licensing.swift. Key is read from stdin, never logged.
import Foundation
private final class ObservedAPI: LicenseAPI {
    var last: LicenseResponse?
    func request(_ action: String, fields: [String: String]) async throws -> LicenseResponse {
        let result = try await LemonLicenseAPI().request(action, fields: fields)
        last = result
        return result
    }
}
@main struct LiveLicenseTest {
    @MainActor static func main() async {
        do {
            guard CommandLine.arguments.count == 2, let key = readLine(), !key.isEmpty else {
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Provide config path and test key on stdin"])
            }
            let config = try JSONDecoder().decode(CommerceConfig.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
            guard config.testMode && config.configured else { fatalError("Test configuration required") }
            let vault = KeychainVault(service: "local.louis.fixclipboard.license.e2e." + UUID().uuidString)
            let api = ObservedAPI()
            let model = LicenseStore(config: config, api: api, vault: vault)
            model.load()
            await model.activate(key)
            guard model.isPro && model.permitsAutomaticRepair else {
                try? vault.write(nil, account: "install-id")
                throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: model.message])
            }
            print("PASS: real API activation; Pro and automatic repair entitlement unlocked")
            if let limit = api.last?.license_key?.activation_limit { print("Provider activation limit: \(limit); expected: \(config.deviceLimit)") }
            let reloaded = LicenseStore(config: config, api: api, vault: vault)
            reloaded.load()
            let persisted = reloaded.isPro
            await reloaded.validate()
            let online = api.last?.valid == true && reloaded.isPro && reloaded.message == "Pro 授权有效。"
            // Always release the test slot before reporting any later assertion failure.
            await model.deactivate()
            guard !model.hasLicense && !model.isPro else {
                throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cleanup failed: " + model.message])
            }
            let keychainCleared = try vault.read("license") == nil
            try vault.write(nil, account: "install-id")
            guard persisted && online && keychainCleared else { throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Persistence/online validation/cleanup assertion failed"]) }
            print("PASS: Keychain save/reload; real instance validation; deactivation; local cleanup")
            print("No UI interaction or cross-device clipboard repair was tested.")
        } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
