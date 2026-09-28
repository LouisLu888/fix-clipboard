# Fix Clipboard · Mac / iPhone 通用剪贴板修复

菜单栏小工具：免费手动重置 Mac 共享服务，Pro 在网络变化和 Mac 唤醒后自动尝试修复。不读取剪贴板内容。

## 下载安装

[下载 v1.5.0-rc.4 候选版](https://github.com/LouisLu888/fix-clipboard/releases/tag/v1.5.0-rc.4)。支持 Apple Silicon / Intel，最低 macOS 13。拖入 Applications 后启动。当前为 ad-hoc 签名，未公证；首次打开按 [安装说明](INSTALL.md) 操作。

## Free 与 Pro

| 功能 | Free | Pro |
| --- | --- | --- |
| 手动修复、基础诊断 | ✓ | ✓ |
| 登录时启动（首次确认后开启） | ✓ | ✓ |
| 网络变化后自动修复 | — | ✓ |
| Mac 唤醒后自动修复 | — | ✓ |

Pro 正常价 **¥49 买断**，前 50 名 **¥29**。个人最多 3 台 Mac，长期使用 V1.x，含 V1.x 更新。App 内扫码添加微信，确认优惠名额后转账，把本机激活码发给卖家，获得授权码后粘贴激活。Lemon Squeezy 尚未开放正式购买，当前使用微信与离线签名授权。[购买与发码说明](docs/WECHAT_SALES.md)

如果手动修复对你有帮助，Pro 可以减少网络切换、开盖唤醒后反复打开工具的操作。自动选项默认关闭，激活后由用户开启。

## 能检测什么

Wi-Fi、Bluetooth 和 Handoff 显示本机状态；绿色不代表跨设备连接已恢复。蓝牙优先读取系统报告，报告不可用时提供授权备用检查。VPN 未检测到连接显示绿色，检测到连接显示橙色及局域网共享设置建议，读取失败显示未知。检测可能遗漏第三方代理和其他设备上的 VPN。

[Apple 官方通用剪贴板说明](https://support.apple.com/zh-cn/guide/iphone/iph220ea8dca/ios)：VPN 配置不能阻止局域网通信。工具无法解除 VPN 的网络限制，也不能确认 useractivityd 内部是否卡住。

网络变化/唤醒后，等待网络可用、稳定 3 秒并满足 10 秒冷却后重置当前用户共享服务。合盖必须实际进入睡眠才会触发唤醒修复。没有每 4 小时定时任务。执行成功仅代表命令完成，请在另一设备重新复制并双向测试。

## 开发与验证

```sh
bash source/build.sh
python3 tests/test_suite.py
bash scripts/package_dmg.sh
```

[测试说明](tests/README.md) · [隐私说明](docs/PRIVACY.md) · [发布验收](docs/RELEASE.md)。源码 MIT。
