import AppKit
import SwiftUI
import ServiceManagement
import Network
import CoreWLAN
import IOBluetooth
import CoreBluetooth

func repair(execute: (String, [String]) -> CommandResult = runCommand) -> String? {
    let preference = NSHomeDirectory() + "/Library/Preferences/com.apple.coreservices.useractivityd.plist"
    let write = execute("/usr/bin/defaults", ["write", preference, "ClipboardSharingEnabled", "-bool", "true"])
    guard write.status == 0 else { return "无法启用剪贴板共享：\(write.output)" }
    let listing = execute("/usr/bin/pgrep", ["-u", String(getuid()), "-x", "useractivityd"])
    guard listing.status == 0 || listing.status == 1 else { return "无法检查共享服务进程：\(listing.output)" }
    let pids = listing.output.split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }.filter { $0 > 1 }
    // Snapshot identity to avoid signaling a reused PID. No clipboard data is read.
    var originals: [(String, String)] = []
    for pid in pids {
        let identity = execute("/bin/ps", ["-p", String(pid), "-o", "uid=,lstart=,comm="])
        if identity.status == 0 { originals.append((String(pid), identity.output)) }
        else if identity.status != 1 || !identity.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "无法确认共享服务状态，请稍后重试。"
        }
    }
    let restart = execute("/usr/bin/killall", ["-u", NSUserName(), "useractivityd"])
    // Exit 1 means no matching process; it is already stopped and can be started on demand.
    guard restart.status == 0 || (restart.status == 1 && restart.output.contains("No matching processes")) else {
        return "无法重启共享服务：\(restart.output)"
    }
    for (pid, identity) in originals {
        let current = execute("/bin/ps", ["-p", pid, "-o", "uid=,lstart=,comm="])
        if current.status != 0 && (current.status != 1 || !current.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return "无法确认共享服务是否退出，请稍后重试。"
        }
        if current.status == 0 && current.output == identity {
            // SIGTERM remains pending on a SIGSTOP-paused process until it resumes.
            _ = execute("/bin/kill", ["-CONT", pid])
        }
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while !originals.isEmpty {
        var remaining: [(String, String)] = []
        for (pid, identity) in originals {
            let current = execute("/bin/ps", ["-p", pid, "-o", "uid=,lstart=,comm="])
            if current.status == 0 && current.output == identity { remaining.append((pid, identity)) }
            else if current.status != 0 && (current.status != 1 || !current.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                return "无法确认共享服务是否退出，请稍后重试。"
            }
        }
        originals = remaining
        if originals.isEmpty { break }
        if ProcessInfo.processInfo.systemUptime >= deadline { return "共享服务仍未退出，请稍后重试。" }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return nil
}

func handoffStatus(_ advertising: Bool?, _ receiving: Bool?) -> String {
    if advertising == false || receiving == false { return "✗ 偏好设置已关闭" }
    if advertising == true && receiving == true { return "✓ 偏好设置已开启" }
    return "? 未知，请在系统设置确认"
}

func vpnStatus(_ result: CommandResult) -> String {
    guard result.status == 0 else { return "? 无法读取" }
    if result.output.components(separatedBy: "\n").contains(where: { $0.contains("(Connected)") }) {
        return "Active（系统报告已连接）"
    }
    return "未发现已连接项（不排除其他 VPN／代理）"
}

// system_profiler reports the local controller without initializing our Bluetooth manager.
// Its schema is not guaranteed across macOS versions: unknown values must stay unknown.
func reportedBluetoothPower(_ result: CommandResult) -> UInt32? {
    guard result.status == 0, let data = result.output.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let entries = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
    let states = entries.compactMap { ($0["controller_properties"] as? [String: Any])?["controller_state"] as? String }
    guard states.count == 1 else { return nil }
    switch states[0] {
    case "attrib_on": return 1
    case "attrib_off": return 0
    default: return nil
    }
}

// Never initialize the controller until permission is granted: initialization can invoke TCC.
func bluetoothStatus(authorization: CBManagerAuthorization, power: () -> UInt32?) -> String {
    guard authorization == .allowedAlways else {
        return "? 未授权，电源状态未知；请在系统设置确认蓝牙开关"
    }
    switch power() {
    case 1: return "✓ 开启"
    case 0: return "✗ 关闭"
    default: return "? 未初始化或无法读取"
    }
}

func diagnosticSummary() -> String {
    let wifi: String
    if let interface = CWWiFiClient.shared().interface() {
        wifi = interface.powerOn() ? "✓ 开启" : "? 已关闭或读取失败"
    } else { wifi = "? 无法读取" }
    let reported = reportedBluetoothPower(runBoundedCommand("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 3))
    let bluetooth: String
    if let reported { bluetooth = reported == 1 ? "✓ 开启" : "✗ 关闭" }
    else {
        bluetooth = bluetoothStatus(authorization: CBManager.authorization) {
            IOBluetoothHostController.default()?.powerState.rawValue
        }
    }
    func preference(_ key: String) -> Bool? {
        let value = CFPreferencesCopyValue(key as CFString, "com.apple.coreservices.useractivityd" as CFString,
                                          kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() || CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        return (value as? NSNumber)?.boolValue
    }
    let handoff = handoffStatus(preference("ActivityAdvertisingAllowed"), preference("ActivityReceivingAllowed"))
    let vpn = vpnStatus(runCommand("/usr/sbin/scutil", ["--nc", "list"]))
    return "Wi-Fi        \(wifi)\nBluetooth    \(bluetooth)\nHandoff      \(handoff)\nVPN          \(vpn)\n\n排查建议：\n若 VPN 已连接，或问题发生在网络切换后，可能涉及 Continuity 连接状态。持续阻止本地通信的 VPN 设置需要单独调整。\n\n这里只检查本机基础状态，不代表跨设备连接正常。Handoff 来自未公开保证的本机偏好；VPN 检查可能漏掉第三方隧道或系统代理。"
}

// Monotonic clock values, independent of wall-clock adjustments.
struct NetworkRepairGate {
    var pendingAt: TimeInterval?
    var lastAttempt: TimeInterval?
    mutating func changed(at now: TimeInterval) { pendingAt = now + 3 }
    mutating func cancel() { pendingAt = nil }
    func delay(at now: TimeInterval) -> TimeInterval? {
        guard let pendingAt else { return nil }
        return max(0, max(pendingAt, (lastAttempt ?? -10) + 10) - now)
    }
    mutating func attempted(at now: TimeInterval) {
        lastAttempt = now
        pendingAt = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let homeModel = HomeModel()
    private var homeWindow: NSWindow?
    private var followWindow: NSWindow?
    private var diagnosticWindow: NSWindow?
    private let diagnosticModel = DiagnosticsModel()
    private let preferences = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var busy = false
    private let monitor = NWPathMonitor()
    private var previousPath: NWPath?
    private var pathReady = false
    private var sleeping = false
    private var networkGate = NetworkRepairGate()
    private var networkWork: DispatchWorkItem?
    private var networkEnabled: Bool { preferences.bool(forKey: "networkEnabled") }
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.fixclipboard")
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 20, height: 20)
            icon.isTemplate = false
            statusItem.button?.image = icon
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Fix Clipboard")
        }
        statusItem.button?.setAccessibilityLabel("Fix Clipboard")
        statusItem.button?.toolTip = "Fix Clipboard · 修复跨设备复制粘贴"
        preferences.removeObject(forKey: "autoEnabled")
        preferences.removeObject(forKey: "nextRun")
        homeModel.result = preferences.string(forKey: "lastResult")
        homeModel.failed = preferences.bool(forKey: "lastFailed")
        rebuildMenu()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.pathChanged(path) }
        }
        monitor.start(queue: DispatchQueue(label: "local.fixclipboard.network"))
        if !preferences.bool(forKey: "introducedHome") {
            preferences.set(true, forKey: "introducedHome")
            showHome()
        }
        if !preferences.bool(forKey: "loginConsentShown") {
            DispatchQueue.main.async { [weak self] in self?.offerLoginAtLaunch() }
        }
    }

    func offerLoginAtLaunch() {
        preferences.set(true, forKey: "loginConsentShown")
        guard SMAppService.mainApp.status == .notRegistered else { return }
        let alert = NSAlert()
        alert.messageText = "登录 Mac 后，让 Fix Clipboard 保持就绪"
        alert.informativeText = "登录时启动永久免费。你可以随时在主面板关闭；这不会自动开启自动修复。"
        let checkbox = NSButton(checkboxWithTitle: "登录时启动 Fix Clipboard", target: nil, action: nil)
        checkbox.state = .on
        alert.accessoryView = checkbox
        alert.addButton(withTitle: "确认")
        alert.addButton(withTitle: "暂不开启")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn && checkbox.state == .on { toggleLogin() }
    }

    func item(_ title: String, action: Selector? = nil) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: "")
        result.target = self
        return result
    }

    func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(item("Fix Clipboard · 全部功能免费"))
        menu.addItem(item("打开主面板…", action: #selector(showHome)))
        menu.addItem(.separator())
        let fix = item(busy ? "正在修复…" : "立即修复", action: #selector(fixNow))
        fix.isEnabled = !busy
        menu.addItem(fix)
        if let last = preferences.object(forKey: "lastAttempt") as? Date {
            menu.addItem(item("上次执行：\(formatted(last))"))
        }
        menu.addItem(.separator())
        let network = item("网络变化／睡眠唤醒后自动修复", action: #selector(toggleNetwork))
        network.state = networkEnabled ? .on : .off
        menu.addItem(network)

        if networkEnabled {
            menu.addItem(item(networkGate.pendingAt == nil ? "监听网络变化和唤醒 · 稳定 3 秒 / 冷却 10 秒" : "已检测变化 · 等待网络稳定及冷却结束"))
        }

        let login = item("登录时启动", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if SMAppService.mainApp.status == .requiresApproval { menu.addItem(item("登录项等待系统批准")) }
        menu.addItem(item("关注作者 · AI 与实用工具…", action: #selector(showFollow)))
        menu.addItem(.separator())
        menu.addItem(item("诊断…", action: #selector(showDiagnostics)))
        menu.addItem(item("使用说明…", action: #selector(showInfo)))
        menu.addItem(item("下载更新…", action: #selector(openUpdates)))
        menu.addItem(item("帮助与反馈…", action: #selector(openSupport)))
        menu.addItem(item("退出", action: #selector(quit)))
        menu.autoenablesItems = false
        for entry in menu.items where entry.action == nil { entry.isEnabled = false }
        statusItem.menu = menu
        homeModel.busy = busy
        diagnosticModel.repairing = busy
        homeModel.autoEnabled = networkEnabled
        homeModel.loginEnabled = SMAppService.mainApp.status == .enabled
        homeModel.loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        homeModel.status = busy ? "正在重置共享服务" : (networkEnabled ? (networkGate.pendingAt == nil ? "自动修复已开启" : "等待网络稳定后自动修复") : "随时可以手动修复")
        if let last = preferences.object(forKey: "lastAttempt") as? Date {
            homeModel.lastRun = "上次执行：\(formatted(last)) · \(preferences.string(forKey: "lastReason") ?? "手动修复")"
        }

    }

    @objc func toggleNetwork() {
        preferences.set(!networkEnabled, forKey: "networkEnabled")
        networkGate.cancel()
        networkWork?.cancel()
        rebuildMenu()
    }
    func pathChanged(_ path: NWPath) {
        let previous = previousPath
        previousPath = path
        pathReady = path.status == .satisfied
        // The initial callback is a baseline, not a network-change event.
        guard let previous else { return }
        guard previous != path else { return }
        guard networkEnabled, !sleeping else { return }
        networkGate.changed(at: uptime)
        scheduleNetworkRepair()
    }
    func scheduleNetworkRepair() {
        networkWork?.cancel()
        guard networkEnabled, !sleeping, pathReady,
              let delay = networkGate.delay(at: uptime) else { rebuildMenu(); return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.networkEnabled, !self.sleeping, self.pathReady else { return }
            if self.busy { return } // Completion will schedule any remaining work.
            guard let remaining = self.networkGate.delay(at: self.uptime) else { return }
            if remaining > 0 { self.scheduleNetworkRepair(); return }
            self.performRepair(manual: false, reason: "网络变化或唤醒")
        }
        networkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        rebuildMenu()
    }
    @objc func willSleep() {
        sleeping = true
        networkWork?.cancel()
        networkGate.cancel()
    }
    @objc func woke() {
        sleeping = false
        if networkEnabled {
            networkGate.changed(at: uptime)
            pathReady = monitor.currentPath.status == .satisfied
            scheduleNetworkRepair()
        }
    }
    @objc func fixNow() { showHome(); performRepair(manual: true) }
    func performRepair(manual: Bool, reason: String = "手动修复") {
        guard !busy, manual || networkEnabled else { return }
        busy = true
        homeModel.result = nil
        networkWork?.cancel()
        networkGate.attempted(at: uptime)
        preferences.set(reason, forKey: "lastReason")
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let error = repair()
            DispatchQueue.main.async {
                self.busy = false
                self.preferences.set(Date(), forKey: "lastAttempt")
                self.preferences.set(error != nil, forKey: "lastFailed")
                self.preferences.set(error == nil ? "修复命令已完成，请跨设备测试" : "上次重置未完成，请重新尝试或检查连接条件", forKey: "lastResult")
                // Start a fresh cooldown after completion as well, including failures.
                self.networkGate.lastAttempt = self.uptime
                self.scheduleNetworkRepair()
                self.rebuildMenu()
                self.homeModel.failed = error != nil
                self.homeModel.result = error ?? "重置已完成。请在另一台设备重新复制，并双向测试。"
                if manual {
                    self.showHome()

                }
            }
        }
    }
    @objc func openUpdates() { NSWorkspace.shared.open(AppLinks.releases) }
    @objc func openSupport() { NSWorkspace.shared.open(AppLinks.support) }
    @objc func showHome() {
        if homeWindow == nil {
            let view = HomeView(model: homeModel,
                repair: { [weak self] in self?.performRepair(manual: true) },
                diagnostics: { [weak self] in self?.showDiagnostics() },
                toggleAuto: { [weak self] in self?.toggleNetwork() },
                toggleLogin: { [weak self] in self?.toggleLogin() },
                showFollow: { [weak self] in self?.showFollow() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Fix Clipboard"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            homeWindow = window
        }
        homeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHome(); return true
    }
    @objc func showFollow() {
        if followWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: FollowView()))
            window.title = "关注作者"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            followWindow = window
        }
        followWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggleLogin() {
        // Login at launch is free and requires explicit consent.
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            rebuildMenu()
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法更新登录项"
            alert.informativeText = "请将 App 放入应用程序文件夹后重试，也可在系统设置 → 通用 → 登录项检查。\n" + error.localizedDescription
            alert.runModal()
        }
    }
    @objc func showDiagnostics() {
        if diagnosticWindow == nil {
            let view = DiagnosticsView(model: diagnosticModel, repair: { [weak self] in self?.performRepair(manual: true) })
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "Fix Clipboard"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            diagnosticWindow = window
            diagnosticModel.refresh = { [weak self] in self?.refreshDiagnostics() }
        }
        diagnosticWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshDiagnostics()
    }
    private func refreshDiagnostics() {
        guard !diagnosticModel.loading else { return }
        diagnosticModel.loading = true
        diagnosticModel.authorization = CBManager.authorization
        // Run hardware queries in an isolated helper, with a bounded lifetime.
        guard let executable = Bundle.main.executableURL else { diagnosticModel.loading = false; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runBoundedCommand(executable.path, ["--diagnostics"], timeout: 8)
            let summary: String
            if result.status == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { summary = result.output }
            else if result.status == -2 { summary = "诊断超时，部分系统状态无法读取。请稍后重新检查。" }
            else { summary = "诊断未完成（代码 \(result.status)）。请重新检查或更新 App。" }
            let text = summary
            DispatchQueue.main.async {
                self.diagnosticModel.summary = text
                self.diagnosticModel.authorization = CBManager.authorization
                self.diagnosticModel.loading = false
            }
        }
    }
    @objc func showInfo() {
        let alert = NSAlert()
        alert.messageText = "Fix Clipboard 已在菜单栏就绪"
        alert.informativeText = "点击菜单栏的剪贴板图标，再选「立即修复」。\n\n工具会启用 ClipboardSharingEnabled 并重启当前用户的 useractivityd，可能短暂中断 Handoff。无需管理员权限。\n\n网络变化／睡眠唤醒自动修复默认关闭：路径变化或唤醒后稳定 3 秒再执行，自动网络修复间隔至少 10 秒。离线时等待恢复；首次启动只记录基线。合盖进入睡眠后，开盖唤醒也会触发；合盖未睡眠时不保证触发。退出工具会停止自动修复。\n\n工具不会读取或保存剪贴板内容。网络变化不代表故障，监听也不保证捕获所有 VPN、DNS 或路由变化；手机端变化无法由 Mac 直接感知。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc func quit() {
        networkWork?.cancel()
        monitor.cancel()
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--process-self-test") {
    let started = ProcessInfo.processInfo.systemUptime
    assert(runBoundedCommand("/bin/sleep", ["5"], timeout: 0.05).status == -2)
    assert(ProcessInfo.processInfo.systemUptime - started < 3)
    let payload = String(repeating: "x", count: 80_000)
    let captured = runBoundedCommand("/usr/bin/printf", ["%s", payload])
    assert(captured.status == 0 && captured.output == payload)
    assert(runBoundedCommand("/path/that/does/not/exist", []).status == -1)
    print("PASS: bounded subprocess timeout, large output, launch error")
} else if CommandLine.arguments.contains("--self-test") {
    for authorization in [CBManagerAuthorization.notDetermined, .denied, .restricted] {
        assert(bluetoothStatus(authorization: authorization, power: { fatalError("Unauthorized hardware access") }).contains("未授权"))
    }
    for (state, expected) in [("attrib_on", UInt32(1)), ("attrib_off", UInt32(0))] {
        let json = "{\"SPBluetoothDataType\":[{\"controller_properties\":{\"controller_state\":\"\(state)\"}}]}"
        assert(reportedBluetoothPower(CommandResult(status: 0, output: json)) == expected)
    }
    assert(reportedBluetoothPower(CommandResult(status: 0, output: "{}")) == nil)
    assert(reportedBluetoothPower(CommandResult(status: -2, output: "timeout")) == nil)
    assert(reportedBluetoothPower(CommandResult(status: 0, output: "invalid JSON")) == nil)
    assert(bluetoothStatus(authorization: .allowedAlways, power: { 1 }).contains("开启"))
    assert(bluetoothStatus(authorization: .allowedAlways, power: { 0 }).contains("关闭"))
    assert(bluetoothStatus(authorization: .allowedAlways, power: { nil }).contains("无法读取"))
    assert(handoffStatus(nil, nil).contains("未知"))
    assert(handoffStatus(true, nil).contains("未知"))
    assert(handoffStatus(true, false).contains("关闭"))
    assert(handoffStatus(true, true).contains("开启"))
    assert(vpnStatus(CommandResult(status: 0, output: "* (Disconnected) sample")).contains("未发现"))
    assert(vpnStatus(CommandResult(status: 0, output: "* (Connected) sample")).hasPrefix("Active"))
    assert(vpnStatus(CommandResult(status: 1, output: "")).contains("无法读取"))
    var calls: [(String, [String])] = []
    assert(repair { path, args in calls.append((path, args)); return CommandResult(status: 0, output: "") } == nil)
    assert(calls.count == 3 && calls[2].1 == ["-u", NSUserName(), "useractivityd"])
    calls = []
    assert(repair { path, args in calls.append((path, args)); return CommandResult(status: 2, output: "denied") } != nil)
    assert(calls.count == 1)
    assert(repair { path, _ in CommandResult(status: path.hasSuffix("killall") ? 1 : 0, output: "No matching processes belonging to you were found") } == nil)
    assert(repair { path, _ in CommandResult(status: path.hasSuffix("killall") ? 1 : 0, output: "Operation not permitted") } != nil)
    assert(repair { path, _ in
        if path.hasSuffix("pgrep") { return CommandResult(status: 0, output: "12345") }
        if path.hasSuffix("ps") { return CommandResult(status: -2, output: "timeout") }
        return CommandResult(status: 0, output: "")
    } != nil) // A timed-out status probe must not report success.
    var gate = NetworkRepairGate()
    assert(gate.delay(at: 0) == nil)
    gate.changed(at: 10)
    assert(gate.delay(at: 10) == 3)
    gate.changed(at: 12)
    assert(gate.delay(at: 14) == 1) // trailing debounce
    assert(gate.delay(at: 15) == 0)
    gate.attempted(at: 15)
    gate.changed(at: 16)
    assert(gate.delay(at: 19) == 6) // retain event during cooldown
    assert(gate.delay(at: 25) == 0)
    gate.changed(at: 24)
    assert(gate.delay(at: 25) == 2) // latest debounce also respected
    gate.cancel()
    assert(gate.delay(at: 100) == nil)
    var probes = 0
    var resumed = false
    let stoppedResult = repair { path, args in
        if path.hasSuffix("pgrep") { return CommandResult(status: 0, output: "12345\n") }
        if path.hasSuffix("ps") {
            probes += 1
            return CommandResult(status: resumed ? 1 : 0, output: resumed ? "" : "501 start useractivityd")
        }
        if path == "/bin/kill" { assert(args == ["-CONT", "12345"]); resumed = true }
        return CommandResult(status: 0, output: "")
    }
    assert(stoppedResult == nil && resumed && probes >= 3)
    print("PASS: paused-process recovery; network debounce, cooldown, deferred changes, cancellation; repair commands, failure handling, user-scoped restart, scheduling guards. No system settings changed.")
} else if CommandLine.arguments.contains("--diagnostics") {
    print(diagnosticSummary())
} else if CommandLine.arguments.contains("--repair-test") {
    // Explicitly opted-in integration entry point: exactly the same repair as the menu.
    if let error = repair() { fputs(error + "\n", stderr); exit(1) }
    print("Repair commands completed; service recovery must be independently verified.")
} else if CommandLine.arguments.contains("--network-test") {
    let probe = NWPathMonitor()
    let received = DispatchSemaphore(value: 0)
    probe.pathUpdateHandler = { path in
        print("Network callback received; status: \(path.status). No repair executed.")
        received.signal()
    }
    probe.start(queue: DispatchQueue(label: "network.smoke.test"))
    let result = received.wait(timeout: .now() + 5)
    probe.cancel()
    if result == .timedOut { print("No callback within 5 seconds"); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
