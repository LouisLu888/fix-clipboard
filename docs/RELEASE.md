# 发布候选版与正式版

## 当前候选版

`v1.5.0-rc.3`。界面、稳定性和安装包已整理；仍使用 Lemon Squeezy 测试模式，不作为正式收费版发布。

```sh
bash source/build.sh --candidate
python3 tests/test_suite.py
bash scripts/package_dmg.sh
```

输出双架构 ZIP、可拖到 Applications 的 DMG 和 SHA256SUMS.txt。DMG 附安装/隐私说明。构建默认 ad-hoc 签名，没有 Apple 公证；不会要求付费开发者账户，也不会关闭系统安全保护。

## 正式发售前必须完成

1. 商店审核与 Live 商品：复制/创建正式商品后重新取得 Store/Product/Variant 和 checkout，确认价格、License 生成、3 台上限、无到期、退款处理与购买邮件。测试商品不会因修改 App 的 testMode 自动变成正式商品。
2. 验证实际 Live checkout 后，更新 Commerce.json，设 `testMode: false`。`bash source/build.sh --release` 会拒绝测试配置、缺失 ID 和非公开 HTTPS 支付地址；构建检查不能代替实际网页/订单验收。
3. 实机验收：全新安装和从旧版升级；蓝牙允许/拒绝；Free 手动修复；支付、激活、重启读取；自动修复和登录项；停用；深浅色、键盘与小屏幕显示。还需 Intel/macOS 13 等声明支持组合的实机验证，当前仅 Apple Silicon/macOS 26.6.1。
4. 先退出旧版，再安装正式包并从 Applications 启动。当前 GUI 自动化无法连接，静态视图渲染不能替代真实窗口操作验收。
5. 完成验收后才标记 GitHub release 为 latest。候选版保持 prerelease。

## 签名与更新

默认构建不需开发者年费。若以后拥有 Developer ID，可通过 `SIGNING_IDENTITY` 构建，脚本将启用 hardened runtime 和 timestamp。这只做签名，不自动公证；正式对外声称“已公证”前仍需 `notarytool` 提交并验证 ticket。不要在仓库中保存证书密码或商户 API Key。

更新入口打开 GitHub 稳定版下载页面；目前不自动下载、替换或重启。用户从菜单退出旧版后替换安装，偏好设置和钥匙串授权保留。候选版的更新入口也指向稳定版，请根据版本号选择，不自动降级。

源码继续 MIT。客户端付费限制不是防篡改 DRM。
