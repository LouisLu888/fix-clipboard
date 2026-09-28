import AppKit
import SwiftUI

final class HomeModel: ObservableObject {
    @Published var busy = false
    @Published var autoEnabled = false
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var status = "随时可以手动修复"
    @Published var lastRun = "尚未执行修复"
    @Published var result: String?
    @Published var failed = false
    @Published var offerPro = false
}

enum AppLinks {
    static let releases = URL(string: "https://github.com/LouisLu888/fix-clipboard/releases/latest")!
    static let support = URL(string: "https://github.com/LouisLu888/fix-clipboard/issues/new/choose")!
    static let privacy = URL(string: "https://github.com/LouisLu888/fix-clipboard/blob/main/docs/PRIVACY.md")!
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let channel = Bundle.main.object(forInfoDictionaryKey: "FCReleaseChannel") as? String ?? "release"
        return "\(short)\(channel == "release" ? "" : "-" + channel) (\(build))"
    }
}

struct HomeView: View {
    @ObservedObject var model: HomeModel
    @ObservedObject var license: LicenseStore
    var repair: () -> Void
    var diagnostics: () -> Void
    var toggleAuto: () -> Void
    var toggleLogin: () -> Void
    var showPro: () -> Void
    @Environment(\.colorScheme) private var scheme
    var version: String = AppLinks.version
    private let buttonColor = Color(red: 0.08, green: 0.46, blue: 0.35)
    private var accent: Color { scheme == .dark ? Color(red: 0.50, green: 0.84, blue: 0.69) : buttonColor }
    var body: some View {
        ScrollView { content }
            .frame(width: 560, height: 690).background(Color(nsColor: .windowBackgroundColor))
    }
    var content: some View {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 68, height: 68).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Fix Clipboard").font(.system(size: 25, weight: .bold, design: .rounded))
                            Text(license.isPro ? "PRO" : "FREE").font(.system(size: 10, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 4)
                                .background(accent.opacity(0.12), in: Capsule()).foregroundStyle(accent)
                        }
                        Text("让 Mac 与 iPhone，再次接上话。")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label(model.status, systemImage: model.busy ? "arrow.triangle.2.circlepath" : (model.autoEnabled ? "bolt.circle.fill" : "hand.tap"))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(accent)
                    Text("复制了，粘贴不过来？").font(.system(size: 22, weight: .semibold))
                    Text("重置 Mac 端共享服务，然后在另一台设备重新复制。")
                        .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button(action: repair) {
                            HStack(spacing: 8) {
                                if model.busy { ProgressView().controlSize(.small) }
                                else { Image(systemName: "arrow.clockwise") }
                                Text(model.busy ? "正在重置…" : "立即修复")
                            }.frame(minWidth: 140)
                        }.buttonStyle(.borderedProminent).tint(buttonColor).controlSize(.large).disabled(model.busy)
                            .keyboardShortcut(.return, modifiers: [])
                        Button("检查连接条件", action: diagnostics).controlSize(.large)
                    }
                    if let result = model.result {
                        Label(result, systemImage: model.failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(model.failed ? Color.orange : accent)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    Text(model.lastRun).font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("自动修复").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if !license.isPro { Label("Pro", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                    setting("网络变化与 Mac 唤醒", detail: "包含可检测到的 VPN / Wi-Fi 变化及开盖唤醒", enabled: model.autoEnabled, action: toggleAuto)
                }
                Divider()
                setting("登录时启动 · 免费", detail: model.loginNeedsApproval ? "需要在系统设置中允许登录项" : "登录 Mac 后，在菜单栏保持就绪", enabled: model.loginEnabled, requiresPro: false, action: toggleLogin)
                HStack {
                    Button(license.isPro ? "管理 Pro 授权" : (model.offerPro ? "下次自动处理 · 了解 Pro" : "了解 Pro / 激活 License"), action: showPro)
                    Spacer()
                    if license.config.manualSales { Text("微信购买 · 买断授权").font(.caption).foregroundStyle(.secondary) }
                    else if license.config.testMode { Text("测试版 · 非正式购买").font(.caption).foregroundStyle(.orange) }
                }
                Divider()
                HStack(spacing: 16) {
                    Text("v\(version)").foregroundStyle(.secondary)
                    Spacer()
                    Button("下载更新") { NSWorkspace.shared.open(AppLinks.releases) }.buttonStyle(.plain).foregroundStyle(accent)
                    Button("帮助与反馈") { NSWorkspace.shared.open(AppLinks.support) }.buttonStyle(.plain).foregroundStyle(accent)
                    Button("隐私") { NSWorkspace.shared.open(AppLinks.privacy) }.buttonStyle(.plain).foregroundStyle(accent)
                }.font(.system(size: 11))
                Text("无需管理员权限，不读取剪贴板内容。重置可能短暂中断 Handoff；完成后请双向测试复制粘贴。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(28).frame(width: 560).background(Color(nsColor: .windowBackgroundColor))
    }
    private func setting(_ title: String, detail: String, enabled: Bool, requiresPro: Bool = true, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !requiresPro || license.isPro || enabled {
                Toggle(title, isOn: Binding(get: { enabled }, set: { _ in action() })).labelsHidden().toggleStyle(.switch).controlSize(.small)
            } else {
                Button(action: action) { Image(systemName: "lock.fill").frame(width: 28) }.help("了解 Pro 自动修复")
                    .accessibilityLabel("解锁" + title)
            }
        }
    }
}
