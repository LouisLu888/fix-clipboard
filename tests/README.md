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


### v1.5.0-beta.1 商业化回归

默认 suite 新增 `--license-self-test`，使用 mock API 与内存 vault，不发出支付/激活请求、不访问钥匙串。覆盖 Free 默认状态、未配置关闭购买、商品匹配、名额满、重复激活、实例绑定、离线宽限及过期、撤销持久化、恢复授权、停用、存储失败回滚、表单编码与异常 HTTP/JSON。真实 merchant/test order、Keychain 升级访问、GUI 和登录项仍待验收；详见 docs/LEMONSQUEEZY_SETUP.md。

本机最终结果：8 项测试通过，授权自测包含 33 条断言；Apple Silicon/macOS 26.6.1。双架构编译与签名验证通过，Intel 未实机运行。此次 GUI 自动化再次连接超时，没有窗口点击验收证据。

### 真实测试订单与授权（2026-09-27）

在 panda Test mode 使用官方测试卡完成一笔 $9.99 测试订单。订单页确认 Paid，并生成一个永不过期的 License。`tests/LiveLicenseTest.swift` 使用生产 LicenseStore / LemonLicenseAPI 与独立命名空间的真实 macOS 钥匙串，验证激活、Pro/自动修复权限、持久化重载、实际实例联网验证、停用及清理，全部通过。测试 Key 不写入源码或日志。

这是按需联网集成测试，不加入默认 CI。使用测试配置，Key 从标准输入传入（不要把 Key 放进命令行参数或提交仓库）：

```sh
xcrun swiftc source/Licensing.swift tests/LiveLicenseTest.swift -o build/LiveLicenseTest -framework Security
build/LiveLicenseTest config/Commerce.json
```

该测试会短暂占用一个测试激活名额，随后停用释放，不改变 App 自身授权。当前未验证三台设备上限；GUI 自动化仍连接超时，不能把此测试当成菜单点击验收。未使用真实资金，不注册登录项、不执行剪贴板修复。


### v1.5.0-rc.1 发布加固

10 项默认回归测试通过，含 36 条授权断言。新增命令超时/大输出/启动失败测试、发布配置拒绝测试，以及停用后钥匙串删除失败的重载验证。实际 SwiftUI 视图使用 fixtures 生成静态深浅色预览；ImageRenderer 无法绘制部分 AppKit 控件，因此预览不代表 GUI 交互验收。原生 GUI 工具仍然连接超时。DMG 另行校验镜像、安装内容和签名。
