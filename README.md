# Fix Clipboard

一个免费的原生 macOS 菜单栏小工具：当 iPhone / iPad 与 Mac 的跨设备复制粘贴失灵时，一键重置 Mac 端共享服务。

**[下载最新版](https://github.com/LouisLu888/fix-clipboard/releases/latest)** · [安装说明](INSTALL.md)

## 功能

- 一键修复：启用 Mac 剪贴板共享，重启当前用户的 `useractivityd`。
- 可选网络变化/睡眠唤醒自动修复：3 秒 debounce、10 秒 cooldown；冷却期内事件合并并延后执行。
- 自动修复默认关闭，仅在工具运行时生效；不再提供每 4 小时定时修复。
- 显示上次执行时间、结果和触发原因。

首次监听回调只建立基线；离线时等待网络恢复。手动修复也更新网络修复的冷却时间。手动按钮不受网络触发冷却拦截。合盖进入睡眠后，开盖唤醒会触发自动修复；若外接显示器等原因使合盖没有进入睡眠，则不保证触发。监听的是系统唤醒，而不是盖子传感器。

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

自测使用替身命令，覆盖修复命令/错误路径、3 秒 debounce、10 秒 cooldown 和取消；网络测试只等待初始路径回调。两种测试都不重启系统服务。尚未在真实 VPN 切换或真实跨设备故障中完成端到端验证。

## 反馈

请在 Issues 提供 macOS 版本、芯片类型、失败方向、VPN 客户端和复现步骤。请勿上传剪贴板正文、账号凭证或完整私人日志。

## License

MIT. See [LICENSE](LICENSE).
