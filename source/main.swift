import AppKit
import Network
import CoreWLAN
import IOBluetooth
import CoreBluetooth

struct CommandResult {
    let status: Int32
    let output: String
}

func runCommand(_ path: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(data: data, encoding: .utf8) ?? "")
    } catch {
        return CommandResult(status: -1, output: error.localizedDescription)
    }
}

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
    }
    let restart = execute("/usr/bin/killall", ["-u", NSUserName(), "useractivityd"])
    // Exit 1 means no matching process; it is already stopped and can be started on demand.
    guard restart.status == 0 || (restart.status == 1 && restart.output.contains("No matching processes")) else {
        return "无法重启共享服务：\(restart.output)"
    }
    for (pid, identity) in originals {
        let current = execute("/bin/ps", ["-p", pid, "-o", "uid=,lstart=,comm="])
        if current.status == 0 && current.output == identity {
            // SIGTERM remains pending on a SIGSTOP-paused process until it resumes.
            _ = execute("/bin/kill", ["-CONT", pid])
        }
    }
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while !originals.isEmpty {
        originals = originals.filter { pid, identity in
            let current = execute("/bin/ps", ["-p", pid, "-o", "uid=,lstart=,comm="])
            return current.status == 0 && current.output == identity
        }
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

// Never initialize the controller until permission is granted: initialization can invoke TCC.
func bluetoothStatus(authorization: CBManagerAuthorization, power: () -> UInt32?) -> String {
    guard authorization == .allowedAlways else {
        return "? 未授权，电源状态未知；请在系统设置确认蓝牙开关"
    }
    switch power() {
    case 1: return "✓ 电源开启"
    case 0: return "✗ 电源关闭"
    default: return "? 未初始化或无法读取"
    }
}

func diagnosticSummary() -> String {
    let wifi: String
    if let interface = CWWiFiClient.shared().interface() {
        wifi = interface.powerOn() ? "✓ 电源开启" : "? 已关闭或读取失败"
    } else { wifi = "? 无法读取" }
    let bluetooth = bluetoothStatus(authorization: CBManager.authorization) {
        IOBluetoothHostController.default()?.powerState.rawValue
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
        statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Fix Clipboard")
        statusItem.button?.toolTip = "Fix Clipboard · 修复跨设备复制粘贴"
        preferences.removeObject(forKey: "autoEnabled")
        preferences.removeObject(forKey: "nextRun")
        rebuildMenu()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.pathChanged(path) }
        }
        monitor.start(queue: DispatchQueue(label: "local.fixclipboard.network"))
        if !preferences.bool(forKey: "introduced") {
            preferences.set(true, forKey: "introduced")
            showInfo()
        }
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
        menu.addItem(item("Fix Clipboard"))
        menu.addItem(item("跨设备复制粘贴修复"))
        menu.addItem(.separator())
        let fix = item(busy ? "正在修复…" : "立即修复", action: #selector(fixNow))
        fix.isEnabled = !busy
        menu.addItem(fix)
        if let last = preferences.object(forKey: "lastAttempt") as? Date {
            menu.addItem(item("上次执行：\(formatted(last))"))
            menu.addItem(item(preferences.string(forKey: "lastResult") ?? ""))
        } else { menu.addItem(item("尚未执行修复")) }
        menu.addItem(.separator())
        let network = item("网络变化／睡眠唤醒后自动修复", action: #selector(toggleNetwork))
        network.state = networkEnabled ? .on : .off
        menu.addItem(network)
        menu.addItem(item("含合盖睡眠后的开盖唤醒"))
        if networkEnabled {
            menu.addItem(item(networkGate.pendingAt == nil ? "监听网络变化和唤醒 · 稳定 3 秒 / 冷却 10 秒" : "已检测变化 · 等待网络稳定及冷却结束"))
        }
        if let reason = preferences.string(forKey: "lastReason") { menu.addItem(item("触发原因：\(reason)")) }
        menu.addItem(item("自动修复仅在本工具运行时生效"))
        menu.addItem(.separator())
        menu.addItem(item("诊断…", action: #selector(showDiagnostics)))
        menu.addItem(item("使用说明…", action: #selector(showInfo)))
        menu.addItem(item("退出", action: #selector(quit)))
        menu.autoenablesItems = false
        for entry in menu.items where entry.action == nil { entry.isEnabled = false }
        statusItem.menu = menu
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
    @objc func fixNow() { performRepair(manual: true) }
    func performRepair(manual: Bool, reason: String = "手动修复") {
        guard !busy else { return }
        busy = true
        networkWork?.cancel()
        networkGate.attempted(at: uptime)
        preferences.set(reason, forKey: "lastReason")
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let error = repair()
            DispatchQueue.main.async {
                self.busy = false
                self.preferences.set(Date(), forKey: "lastAttempt")
                self.preferences.set(error == nil ? "修复命令已完成，请跨设备测试" : "执行失败，请点击立即修复查看详情", forKey: "lastResult")
                // Start a fresh cooldown after completion as well, including failures.
                self.networkGate.lastAttempt = self.uptime
                self.scheduleNetworkRepair()
                self.rebuildMenu()
                if manual {
                    let alert = NSAlert()
                    alert.messageText = error == nil ? "修复命令已完成" : "修复未完成"
                    alert.informativeText = error ?? "请等几秒，再测试 iPhone → Mac 和 Mac → iPhone 的复制粘贴。命令执行成功不代表跨设备连接已恢复。"
                    alert.alertStyle = error == nil ? .informational : .warning
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        }
    }
    @objc func showDiagnostics() {
        // Run hardware queries in an isolated helper, with a bounded lifetime.
        guard let executable = Bundle.main.executableURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--diagnostics"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            var summary = "诊断未返回有效结果，请重新打开 App 后重试。"
            do {
                try process.run()
                if finished.wait(timeout: .now() + 8) == .timedOut {
                    process.terminate()
                    if finished.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
                    summary = "诊断超时，部分系统状态无法读取。没有修改系统设置。"
                } else if process.terminationStatus == 0 {
                    summary = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? summary
                } else {
                    summary = "诊断子进程异常退出（代码 \(process.terminationStatus)）。请更新 App；若仍失败，请提供此代码。"
                }
            } catch { summary = "无法启动诊断：\(error.localizedDescription)" }
            let text = summary
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Continuity 诊断"
                alert.informativeText = text
                alert.addButton(withTitle: "关闭")
                alert.addButton(withTitle: "立即修复")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertSecondButtonReturn { self.performRepair(manual: true) }
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

if CommandLine.arguments.contains("--self-test") {
    for authorization in [CBManagerAuthorization.notDetermined, .denied, .restricted] {
        assert(bluetoothStatus(authorization: authorization, power: { fatalError("Unauthorized hardware access") }).contains("未授权"))
    }
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
