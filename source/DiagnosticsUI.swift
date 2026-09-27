import AppKit
import SwiftUI
import CoreBluetooth

final class DiagnosticsModel: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var summary = ""
    @Published var loading = false
    @Published var repairing = false
    @Published var authorization = CBManager.authorization
    private var manager: CBCentralManager?
    var refresh: (() -> Void)?
    func authorize() {
        authorization = CBManager.authorization
        switch authorization {
        case .notDetermined:
            // Only an explicit button click may trigger the system permission prompt.
            manager = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false])
        case .allowedAlways: refresh?()
        default:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        authorization = CBManager.authorization
        refresh?()
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel
    let repair: () -> Void
    private let labels = ["Wi-Fi", "Bluetooth", "Handoff"]
    private let symbols = ["wifi", "antenna.radiowaves.left.and.right", "laptopcomputer.and.iphone", "network"]
    private func status(_ name: String) -> String {
        guard let line = model.summary.components(separatedBy: "\n").first(where: { $0.hasPrefix(name + " ") }) else { return "等待检查" }
        let raw = String(line.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
        if raw.contains("未授权") { return "未授权 · 状态未知" }
        if raw.hasPrefix("Active") { return "已连接" }
        if raw.hasPrefix("未发现") { return "未发现系统 VPN" }
        return raw.replacingOccurrences(of: "✓ ", with: "").replacingOccurrences(of: "✗ ", with: "").replacingOccurrences(of: "? ", with: "")
    }
    private func appearance(_ name: String) -> (String, Color) {
        let line = model.summary.components(separatedBy: "\n").first(where: { $0.hasPrefix(name + " ") }) ?? ""
        if line.contains("✓") { return ("checkmark.circle.fill", .green) }
        if line.contains("✗") { return ("exclamationmark.circle.fill", .orange) }
        if name == "VPN", !line.isEmpty, !line.contains("无法读取") { return ("info.circle.fill", .blue) }
        return ("questionmark.circle.fill", .secondary)
    }
    var body: some View {
        ScrollView { content }.frame(width: 540, height: 690)
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 5) {
                    Text("让复制粘贴重新连接").font(.system(size: 23, weight: .bold))
                    Text("Fix Clipboard · 本机诊断").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 12) {
                        Image(systemName: symbols[index]).font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 25)
                        Text(label).font(.system(size: 14, weight: .semibold)).frame(width: 78, alignment: .leading)
                        Spacer(minLength: 8)
                        if model.loading { ProgressView().controlSize(.small) }
                        else {
                            let style = appearance(label)
                            Image(systemName: style.0).foregroundStyle(style.1)
                            Text(status(label)).font(.system(size: 12)).foregroundStyle(.primary)
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 17)
                    if index < labels.count - 1 { Divider().padding(.leading, 55) }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            if model.authorization != .allowedAlways {
                HStack(alignment: .center, spacing: 16) {
                    Text("允许读取蓝牙状态，即可检查开关。\n不扫描附近设备，也不影响一键修复。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(model.authorization == .notDetermined ? "授权蓝牙" : "打开权限设置") { model.authorize() }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("可能影响连接 · VPN", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
                if model.loading { ProgressView().controlSize(.small) }
                else { Text(status("VPN")).fontWeight(.medium) }
                Text("VPN 不是接力功能的必要条件。若它阻止本地网络通信，可能影响通用剪贴板；已连接不代表一定有故障。")
                Text("在 Mac 和 iPhone / iPad 的 VPN App 中，查找并开启“允许局域网访问 / Allow LAN”或“允许本地网络 / Local Network Sharing”等选项。名称因 App 而异；若没有此选项，请查看其帮助或联系管理员。")
                Text("调整后重新复制并测试。重置共享服务不能解除 VPN 的网络限制。本机检查也可能漏掉第三方隧道、代理及其他设备上的 VPN。")
                    .foregroundStyle(.secondary)
                Link("Apple 官方说明：通用剪贴板与 VPN", destination: URL(string: "https://support.apple.com/zh-cn/guide/iphone/iph220ea8dca/ios")!)
            }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            if !model.summary.isEmpty && !model.summary.contains("Wi-Fi") {
                Text(model.summary).font(.system(size: 12)).foregroundStyle(.orange)
            }
            Text("绿勾仅表示本机开关或偏好已开启，不能确认跨设备连通。VPN 检查可能遗漏第三方代理；Handoff 偏好仅供参考。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { model.refresh?() } label: { Label("重新检查", systemImage: "arrow.clockwise") }.disabled(model.loading)
                Spacer()
                Button(model.repairing ? "正在修复…" : "立即修复", action: repair).disabled(model.repairing).buttonStyle(.borderedProminent).tint(Color(red: 0.08, green: 0.46, blue: 0.35)).controlSize(.large)
            }
        }
        .padding(28).frame(width: 540).background(Color(nsColor: .windowBackgroundColor))
    }
}
