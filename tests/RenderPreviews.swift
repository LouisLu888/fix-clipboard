// Renders the actual SwiftUI views with fixtures; no network, Keychain or UI interaction.
import AppKit
import SwiftUI
private struct PreviewVault: LicenseVault {
    let record: SavedLicense
    func read(_ account: String) throws -> Data? { account == "license" ? try JSONEncoder().encode(record) : nil }
    func write(_ data: Data?, account: String) throws {}
}
@main struct RenderPreviews {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Provide icon and output directory") }
        _ = NSApplication.shared
        NSApp.applicationIconImage = NSImage(contentsOfFile: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = CommerceConfig(storeID: 1, productID: 2, variantID: 3, checkoutURL: "https://example.lemonsqueezy.com/checkout/buy/preview", priceLabel: "$9.99 · 以付款页为准", deviceLimit: 3)
        config.testMode = true
        let free = LicenseStore(config: config)
        let model = HomeModel()
        model.result = "重置已完成。请在另一台设备重新复制，并双向测试。"
        model.lastRun = "上次执行：今天 10:32 · 手动修复"
        model.offerPro = true
        let view = HomeView(model: model, license: free, repair: {}, diagnostics: {}, toggleAuto: {}, toggleLogin: {}, showPro: {}, version: "1.5.0-rc.1 (11)")
        try render(view.content, name: "home-light", scheme: .light, directory: directory)
        try render(view.content, name: "home-dark", scheme: .dark, directory: directory)
        try render(ProView(license: free), name: "pro-light", scheme: .light, directory: directory)
        let pro = LicenseStore(config: config, vault: PreviewVault(record: SavedLicense(key: "PREVIEW-NOT-A-LICENSE", instanceID: "preview", storeID: 1, productID: 2, variantID: 3, validatedAt: Date())))
        pro.load()
        try render(ProView(license: pro), name: "pro-active", scheme: .light, directory: directory)
        print("Rendered fixture previews; no live GUI acceptance implied.")
    }
    @MainActor static func render<V: View>(_ view: V, name: String, scheme: ColorScheme, directory: URL) throws {
        NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Render failed") }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
