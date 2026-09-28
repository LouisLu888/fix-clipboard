# Fix Clipboard 隐私说明

更新日期：2026-09-27。

Fix Clipboard 不读取、保存或上传剪贴板正文，不扫描附近蓝牙设备，不收集分析事件，不发送使用统计。

## 本机数据

App 在本机保存自动修复偏好、上次修复时间/原因/结果。蓝牙授权仅用于读取电源状态；拒绝授权不影响手动修复。Wi-Fi、蓝牙、Handoff 偏好及系统 VPN 状态用于按需诊断，不会主动上传。

Pro License Key、激活实例、随机安装 UUID 与最近验证时间存入 macOS 钥匙串。安装 UUID 不取自硬件序列号、MAC 地址或 Apple ID。应用不保存 License API 响应中的客户姓名或邮箱，不把 Key 写入日志。

## 与第三方的通信

购买在 Lemon Squeezy 的浏览器页面完成。其支付和订单数据由 Lemon Squeezy 按[隐私政策](https://www.lemonsqueezy.com/privacy)处理，App 不接触银行卡信息。

激活、验证、停用时，App 向 `api.lemonsqueezy.com` 发送 License Key 与随机安装标识或服务端激活实例 ID。服务提供方也会收到连接所需的 IP 地址等网络信息。已有授权在启动、唤醒及每小时重新验证；未激活的 Free 用户不会发出 License 验证请求。

点击下载更新、帮助与反馈或隐私链接时，浏览器打开 GitHub。没有后台自动下载或自动安装更新。

## 删除与控制

可随时退出 App，关闭自动修复或登录启动。Pro 用户换机或卸载前，可使用「停用此 Mac」联网释放激活名额并删除本机 License 记录。随机安装 UUID 会保留在钥匙串，避免每次重装创建不同安装身份；如需彻底移除，可在“钥匙串访问”中删除 service 为 `local.louis.fixclipboard.license` 的对应条目。仅删除本机记录不会释放服务端名额。

问题反馈：[GitHub Issues](https://github.com/LouisLu888/fix-clipboard/issues)。请勿公开提交 License Key、购买邮箱、剪贴板内容或私人日志。需要处理订单或退款时，请通过购买回执中的商家联系入口沟通。

蓝牙诊断优先读取 macOS 系统信息报告中的控制器开关，仅显示开启/关闭。报告可能包含设备信息，程序不展示或上传这些信息；命令输出暂存在权限为 600 的临时文件，读取后删除。报告不可用时，用户可主动授权备用蓝牙接口。
