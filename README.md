# Fix Clipboard · Mac / iPhone 通用剪贴板修复

**全部功能免费、开源。无需注册、付费、授权码或关注验证。**

[产品首页与下载](https://www.jiabinlu.com/products/fix-clipboard/) · [完整安装手册](https://www.jiabinlu.com/products/fix-clipboard/guide.html)

- 手动一键重置 Mac 共享服务。
- 免费自动修复：可检测到的网络路径变化、Mac 睡眠唤醒后自动尝试重置。
- Wi-Fi / Bluetooth / Handoff / VPN 本机诊断。
- 免费登录时启动，首次确认后开启。

自动修复默认关闭，请主动开启。它会等待网络可用、稳定 3 秒，并满足 10 秒冷却。网络变化不代表故障，工具不能保证修复所有原因。VPN 阻止本地通信时仍需允许 Local Network Sharing / Allow LAN。合盖未实际睡眠时，开盖不保证触发。

支持 macOS 13+，包含 Apple Silicon / Intel 架构。当前免费候选版 `v1.6.0-rc.1`，未经过 Apple 公证。安装到 Applications 后首次尝试打开，如系统提示无法验证开发者，核对来源后前往 **系统设置 → 隐私与安全性 → 仍要打开**。详见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。不用关闭 Gatekeeper 或 SIP。

## 为什么做这个工具

我在小红书分享 Mac / iPhone 复制粘贴失效的问题后，发现不少人也有同样困扰，于是把重置步骤做成了一个按钮。现在自动修复也免费开放，希望大家少花时间处理这些小故障。

如果它对你有帮助，欢迎自愿关注：[小红书原帖（点击作者头像关注）](https://xhslink.cn/o/9uYJj82pMFu) · [公众号二维码](https://www.jiabinlu.com/products/fix-clipboard/#follow)。继续分享实用工具，以及 AI、产品和自动化的实际做法。关注不是使用条件。

## 升级与隐私

从 1.5 升级后自动获得全部功能，无需旧授权。保留已有自动修复与登录启动设置，不访问或删除旧授权钥匙串。未开启自动修复的用户仍需自己开启。

不读取剪贴板内容，不上传诊断信息，没有遥测。[隐私说明](docs/PRIVACY.md)。旧购买方案已停止使用；有旧订单问题可通过原购买渠道联系作者。

## 构建与验证

```sh
bash source/build.sh
python3 tests/test_suite.py
bash scripts/package_dmg.sh
```

[测试说明](tests/README.md) · [安装说明](INSTALL.md) · [发布验收](docs/RELEASE.md)。源码 MIT。
