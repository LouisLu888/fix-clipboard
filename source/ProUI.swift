import SwiftUI
import AppKit

struct ProView: View {
    @ObservedObject var license: LicenseStore
    @Environment(\.colorScheme) private var scheme
    @State private var key = ""
    @State private var confirmingDeactivation = false
    @State private var confirmingForget = false
    var body: some View {
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
                feature("power", "登录时启动", "登录 Mac 后，让工具在菜单栏就绪")
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            if !license.isPro {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(license.config.priceLabel.isEmpty ? "Pro 即将开放" : license.config.priceLabel).font(.headline)
                        Text("个人使用 · 最多 \(license.config.deviceLimit) 台 Mac · V1.x 更新")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(license.config.checkout == nil ? "购买暂未开放" : (license.config.testMode ? "打开测试支付" : "升级 Pro")) {
                        if let url = license.config.checkout { NSWorkspace.shared.open(url) }
                    }.buttonStyle(.borderedProminent).tint(Color(red: 0.08, green: 0.46, blue: 0.35))
                        .controlSize(.large).disabled(license.config.checkout == nil)
                }
                Text("价格与税费以付款页为准。浏览器支付，无需注册 App 账号。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if license.config.testMode {
                Label("测试模式：仅用于联调，不是正式购买。", systemImage: "testtube.2")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
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
                    SecureField("购买邮件中的 License Key", text: $key).textFieldStyle(.roundedBorder)
                        .onSubmit { activate() }
                    Button("激活") { activate() }.disabled(license.busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !license.config.configured)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                if license.busy { ProgressView().controlSize(.small) }
                Text(license.message).textSelection(.enabled).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("激活与验证会向 Lemon Squeezy 发送 License 和随机安装标识／激活实例，不发送剪贴板内容。授权保存在钥匙串；离线宽限为最近验证后的 7 天。自动修复不保证跨设备连接恢复。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 550).background(Color(nsColor: .windowBackgroundColor))
            .alert("停用此 Mac？", isPresented: $confirmingDeactivation) {
                Button("取消", role: .cancel) {}
                Button("停用", role: .destructive) { Task { await license.deactivate() } }
            } message: { Text("需要联网释放激活名额。自动修复将停止，手动修复仍免费可用。") }
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
