# Test suite

Build: `bash source/build.sh`

Safe default: `python3 tests/test_suite.py`

Covers Swift repair/scheduler regression checks, a real NWPathMonitor initial callback, both binary architectures, and the app signature. The Swift repair checks use fake commands and do not change system state. GitHub Actions runs this safe suite only.

## Opt-in fault injection (real Mac)

`python3 tests/test_suite.py --fault-injection`

This temporarily pauses the current user's useractivityd and invokes the exact repair function used by the menu via `--repair-test`. It may interrupt Handoff. It requires exactly one running, non-paused current-user daemon. It does not read clipboard content.

An independent watchdog acknowledges readiness before SIGSTOP and sends SIGCONT after 12 seconds if the same process identity still exists. A finally block also resumes the process on failure. PID identity includes owner, start time and executable to reduce PID reuse risk. Do not run alongside other service-debugging tools.

The test checks that the original PID identity disappears, then explicitly asks launchd to activate the service and verifies the replacement is not stopped. This proves termination and launchability; it does not prove the app itself eagerly restarts the daemon or that cross-device transfer works. The actual repair enables ClipboardSharingEnabled and does not undo that setting.

## Result: 2026-09-27, Apple Silicon / macOS 26.6.1

Before fix: 4 safe tests passed, fault-injection test failed. SIGTERM returned success but the SIGSTOP-paused daemon remained present. Cleanup resumed it.

After fix: all 5 tests passed. Repair now snapshots original processes, sends SIGTERM, resumes any surviving original process with SIGCONT, and waits up to 2 seconds for those identities to disappear. It reports failure when they remain; it does not escalate to SIGKILL.

No claim of iPhone↔Mac end-to-end success: a human must copy a fresh harmless marker in each direction. Real lid close/open and VPN transition tests are still manual and have not been executed by this suite.

Diagnostics regression cases are included in --self-test: missing/partial Handoff preferences stay unknown; explicit off remains off; Connected is distinguished from Disconnected; query failures remain unknown. On the development Mac, a live read-only diagnostic returned Wi-Fi on, Bluetooth on, Handoff preferences on and system VPN connected. Hardware-off, denied permission and the dialog timeout path have not been tested on-device.

### v1.3.1 蓝牙权限回归

真实 GUI 崩溃报告确认 v1.3.0 缺少 NSBluetoothAlwaysUsageDescription，IOBluetooth 初始化被 TCC 终止。新增安装包声明检查、诊断输出检查，以及未确定/拒绝/受限授权时绝不调用硬件读取的断言。默认共 6 项测试，在沙箱与真实 macOS 环境均通过。CLI 实测四项均返回；GUI 自动化连接超时，尚未完成新版本菜单点击验证。CLI 权限归属与 GUI 不同，不能替代此验收。未授权会显示蓝牙状态未知，不弹权限申请；需自行在系统设置确认蓝牙开关。

### v1.4.0 原生面板与授权

新增 SwiftUI 诊断窗口、状态颜色与文字双重标记、可重现生成的 AppIcon。授权按钮只在用户点击时创建 CBCentralManager；拒绝后引导系统设置，授权状态回调刷新诊断。构建覆盖 arm64/x86_64，默认回归测试仍为 6 项。真实 GUI 与系统授权弹窗验收尚未完成：自动审批阻止启动本地构建的 App，等待用户允许；不以 CLI 测试替代 GUI 验收。
