// Renders the actual SwiftUI views with fixtures; no network, Keychain or UI interaction.
import AppKit
import SwiftUI
@main struct RenderPreviews {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Provide icon and output directory") }
        _ = NSApplication.shared
        NSApp.applicationIconImage = NSImage(contentsOfFile: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = HomeModel()
        model.result = "重置已完成。请在另一台设备重新复制，并双向测试。"
        model.lastRun = "上次执行：今天 10:32 · 手动修复"
        let view = HomeView(model: model, repair: {}, diagnostics: {}, toggleAuto: {}, toggleLogin: {}, showFollow: {}, version: "1.6.0-rc.1 (15)")
        try render(view.content, name: "home-light", scheme: .light, directory: directory)
        try render(view.content, name: "home-dark", scheme: .dark, directory: directory)
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
