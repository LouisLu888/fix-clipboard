import SwiftUI
import AppKit

struct ProView: View {
    @ObservedObject var license: LicenseStore
    @Environment(\.colorScheme) private var scheme
    @State private var key = ""
    @State private var confirmingDeactivation = false
    @State private var confirmingForget = false
    var body: some View {
        ScrollView { content }.frame(width: 550, height: 720)
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 5) {
                    Text(license.isPro ? "Fix Clipboard Pro" : "少一次手动，多一点省心").font(.system(size: 23, weight: .bold))
                    Text(license.isPro ? "自动修复，由你开启。" : "手动修复永久免费。自动处理，升级 Pro。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("network", "网络变化后自动修复", "包括系统能检测到的 Wi-Fi 与 VPN 路径变化")
                feature("sun.max", "Mac 唤醒后自动修复", "也包括合盖睡眠后的开盖唤醒")
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            if !license.isPro && license.config.manualSales {
                HStack(alignment: .top, spacing: 18) {
                    if let url = Bundle.main.url(forResource: "WeChatQR", withExtension: "jpg"), let image = NSImage(contentsOf: url) {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 180, height: 180)
                        }.buttonStyle(.plain).help("打开原图，方便微信扫码")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("前 50 名 ¥29").font(.system(size: 22, weight: .bold))
                        Text("正常价 ¥49 · 买断制").font(.headline)
                        Text("一次购买，长期使用 V1.x。个人最多 3 台 Mac，含 V1.x 更新。")
                        Text("微信扫一扫加我 → 确认优惠名额 → 微信转账 → 收到授权码后激活。")
                        Text("优惠名额按收款顺序确认，付款前请先咨询。")
                            .foregroundStyle(.secondary)
                    }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                Text("不想每次切换网络或开盖后再手动点修复？Pro 会在这些时机自动尝试重置共享服务，帮你少一次操作。手动修复、诊断和登录启动始终免费。")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("本机激活码").font(.caption)
                    Text(license.installationCode.isEmpty ? "请重新打开 App 生成" : license.installationCode).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(license.installationCode, forType: .string)
                    }.disabled(license.installationCode.isEmpty)
                }
                Text("把本机激活码发给卖家；它是随机标识，不是电脑序列号。每台 Mac 单独签发，换机请联系卖家。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !license.isPro {
                Button("打开购买页面") { if let url = license.config.checkout { NSWorkspace.shared.open(url) } }
                    .disabled(license.config.checkout == nil)
            }
            if license.config.testMode && !license.config.manualSales {
                Label("Lemon Squeezy 测试模式：非正式购买", systemImage: "testtube.2").foregroundStyle(.orange)
            }
            Divider()
            if license.hasLicense {
                HStack {
                    Label(license.isPro ? "此 Mac 已激活" : "此 Mac 的授权需要验证", systemImage: license.isPro ? "checkmark.seal.fill" : "exclamationmark.circle")
                        .foregroundStyle(license.isPro ? Color.green : Color.orange)
                    Spacer()
                    Button("重新验证") { Task { await license.validate() } }.disabled(license.busy)
                    Button("停用此 Mac") { confirmingDeactivation = true }.disabled(license.busy)
                }
                if !license.isPro {
                    Button("无法停用？移除本机失效记录…") { confirmingForget = true }.disabled(license.busy)
                }
            } else {
                Text("已经购买？输入 License Key").font(.system(size: 13, weight: .semibold))
                HStack {
                    SecureField("粘贴卖家发来的完整授权码", text: $key).textFieldStyle(.roundedBorder)
                        .onSubmit { activate() }
                    Button("激活") { activate() }.disabled(license.busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !license.config.configured)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                if license.busy { ProgressView().controlSize(.small) }
                Text(license.message).textSelection(.enabled).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(license.config.manualSales ? "微信授权在本机离线验证并保存在钥匙串，不向 Lemon Squeezy 发送授权码。本机激活码仅由你主动发给卖家。自动修复不能解除 VPN 的局域网限制，也不保证所有连接故障都能恢复。" : "Lemon Squeezy 授权需联网验证，离线宽限为 7 天。不发送剪贴板内容。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 550).background(Color(nsColor: .windowBackgroundColor))
            .alert("停用此 Mac？", isPresented: $confirmingDeactivation) {
                Button("取消", role: .cancel) {}
                Button("停用", role: .destructive) { Task { await license.deactivate() } }
            } message: { Text(license.config.manualSales ? "移除本机保存的授权，自动修复将停止。离线授权不会释放名额，换机请联系卖家。" : "需要联网释放激活名额。自动修复将停止，手动修复仍免费可用。") }
            .alert("移除本机失效授权记录？", isPresented: $confirmingForget) {
                Button("取消", role: .cancel) {}
                Button("移除记录", role: .destructive) { license.forgetInvalidLicense() }
            } message: { Text("这不会释放服务端激活名额。优先使用「停用此 Mac」；若授权被禁用而无法停用，请联系卖家管理名额。") }
    }
    private func activate() {
        guard !license.busy, license.config.configured else { return }
        let input = key
        Task {
            await license.activate(input)
            if license.isPro { key = "" }
        }
    }
    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(scheme == .dark ? Color(red: 0.50, green: 0.84, blue: 0.69) : Color(red: 0.08, green: 0.46, blue: 0.35)).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
