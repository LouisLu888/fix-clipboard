# Fix Clipboard — Mac / iPhone 通用剪贴板修复工具

由 **LouisLu888** 发布的免费开源 macOS 菜单栏工具，用于重置 **Universal Clipboard（通用剪贴板）/ Handoff** 的 Mac 端服务：当 iPhone / iPad 与 Mac 的跨设备复制粘贴失灵时，一键重置 Mac 端共享服务。

**[项目主页](https://louislu888.github.io/fix-clipboard/)** · **[下载最新版](https://github.com/LouisLu888/fix-clipboard/releases/latest)** · [安装说明](INSTALL.md)

## 当前版本：v1.2.1

- **立即修复**：启用 Mac 剪贴板共享，重启当前用户的 `useractivityd`。
- **网络变化／睡眠唤醒后自动修复**：在菜单中按需开启，默认关闭。
- 显示上次执行时间、结果和触发原因。
- 已移除每 4 小时定时修复，升级后旧定时设置自动清理。

## 合盖再开盖，能自动修复吗？

可以，前提是 **合盖后 Mac 进入了睡眠，开盖后发生系统唤醒**，并且 app 正在运行、自动修复选项已开启。

```text
网络路径变化，或 Mac 从睡眠唤醒
→ 等待网络可用
→ 最后一次变化后等待 3 秒
→ 距上次修复完成至少 10 秒
→ 重启 Mac 端共享服务
```

连续变化会重新计时，冷却期内的变化会合并并延后执行。首次启动的网络回调只记录基线，不立即修复。手动修复也会更新冷却时间，但手动按钮本身不受冷却拦截。

监听的是系统唤醒：外接显示器等导致合盖未睡眠时，开盖不保证触发。网络监听也不保证覆盖所有 VPN、DNS 或路由变化，无法感知仅发生在 iPhone/iPad 上的变化。

## 如何使用

1. 打开 app，在屏幕顶部菜单栏找到剪贴板图标。它没有 Dock 主窗口。
2. 出现问题时，点击 **「立即修复」**，等待几秒，在手机上重新复制，再到 Mac 粘贴。
3. 希望开盖唤醒或网络变化后自动执行时，勾选 **「网络变化／睡眠唤醒后自动修复」**。
4. 自动修复只在 app 运行时生效。需要登录后启动，可自行将 app 加入 macOS 登录项。

升级时先从菜单退出旧版，再替换 app 并重新打开。已有网络自动修复开关设置会保留。

## 安装

下载 Release 中的 ZIP，解压后把 app 拖入「应用程序」。这是未公证的免费版本，首次运行可能需要在「系统设置 → 隐私与安全性」中选择「仍要打开」。完整步骤见 [INSTALL.md](INSTALL.md)。无需关闭系统安全保护。

Universal binary：Apple Silicon + Intel，最低部署目标 macOS 13。实机验证仅覆盖 Apple Silicon / macOS 26.6.1；其他组合欢迎反馈。当前界面为中文。

## 它做什么

执行以下两步（代码使用 Process 参数数组，不通过 shell 拼接）：

```sh
defaults write ~/Library/Preferences/com.apple.coreservices.useractivityd.plist ClipboardSharingEnabled -bool true
killall -u "$(id -un)" useractivityd
```

无需管理员权限。服务重启可能短暂影响 Handoff。不会读取、上传或保存剪贴板正文，不发送分析数据，不安装 LaunchAgent，不修改 VPN、路由或防火墙。网络监听仅观察路径变化。

此方法依赖 macOS 内部服务与偏好设置，未来系统更新可能改变行为。命令成功不代表跨设备连接已恢复，请双向复制粘贴验证。它不能修复 iPhone↔iPad，也不能消除 VPN 持续阻止本地通信的策略。

## 从源码构建

安装 Xcode Command Line Tools 后：

```sh
bash source/build.sh
```

输出位于 `dist/`。构建两种架构、合并为通用版、进行 ad-hoc 签名，并运行当前架构的自测。没有 Developer ID 签名或 Apple 公证。

```sh
'dist/Fix Clipboard.app/Contents/MacOS/FixClipboard' --self-test
'dist/Fix Clipboard.app/Contents/MacOS/FixClipboard' --network-test
```

自测使用替身命令，覆盖修复命令/错误路径、3 秒 debounce、10 秒 cooldown 和取消；网络测试只等待初始路径回调。两种测试都不重启系统服务。睡眠／唤醒事件处理已做代码核对；实际合盖、真实 VPN 切换及跨设备故障恢复尚未完成端到端验证。

## 反馈

请在 Issues 提供 macOS 版本、芯片类型、失败方向、VPN 客户端和复现步骤。请勿上传剪贴板正文、账号凭证或完整私人日志。

## License

MIT. See [LICENSE](LICENSE).
