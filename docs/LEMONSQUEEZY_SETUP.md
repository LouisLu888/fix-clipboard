# Lemon Squeezy 接入清单

代码已支持浏览器付款、手动 License 激活、按实例验证、停用释放名额。当前 `config/Commerce.json` 未配置，购买与激活都关闭。商户注册、审核、收款信息和真实付款由店主处理。

## 注册之后给开发者的四项公开配置

1. Checkout URL（Lemon Squeezy 商品支付链接，HTTPS，域名以 `.lemonsqueezy.com` 结尾）。
2. Store ID。
3. Product ID。
4. Variant ID（本次 Pro 授权对应的具体 variant）。

**不需要提供商户 API Key、密码、银行卡或客户 license。** 客户端仅调用公开的 License API，不使用管理 API。

## 商品配置

- 名称：Fix Clipboard Pro。
- 一次性付款；界面目前预设 `¥19.9 · 一次购买`，实际定价、可用货币和税费以商店配置与 checkout 为准，发布前同步 `priceLabel`。
- 开启 License Key 生成，激活上限设为 3，个人使用。
- 授权不设置到期日；说明包含 V1.x 更新，不承诺所有未来大版本。
- 购买完成页面/邮件明确说明：回到 App →「升级 Pro / 输入 License」→ 粘贴 Key → 激活。
- 当前不实现付款回跳自动激活，也没有用户账号系统。
- 准备买家可访问的支持联系方式、退款说明和隐私说明，完成平台要求的店铺审核。

## 修改与构建

修改 `config/Commerce.json`，ID 为数字：

```json
{
  "storeID": 123,
  "productID": 456,
  "variantID": 789,
  "checkoutURL": "https://your-store.lemonsqueezy.com/buy/your-product",
  "priceLabel": "¥19.9 · 一次购买",
  "deviceLimit": 3
}
```

上述值只是格式示例。使用真实商品值后重新构建；配置会复制到 App 资源目录。`deviceLimit` 只控制文案，真正的名额限制必须在商店设置。金额同理，App 不处理支付或计费。

```sh
bash source/build.sh
python3 tests/test_suite.py
```

## 正式发布前的测试订单验收

先用 Lemon Squeezy 测试模式及对应商品配置构建，不向用户发布测试配置：

- Free 手动修复与诊断可用，自动修复无法执行。
- 点击升级打开正确商品 checkout；完成测试付款后能取得 Key。
- 正确 Key 激活；相同 Mac 重复操作不新增实例；错误商品 Key 在激活前被拒绝。
- 三个独立测试安装实例激活后，第四个因名额限制被拒绝。
- 停用某个实例后释放名额，旧实例自动修复停止。
- 后台禁用 Key 后重新验证：自动修复关闭，免费功能继续可用。按商店实际退款策略验证退款是否禁用 license，不能假定任何退款都自动撤销。
- 断网时：最近成功验证后 7 天内保留 Pro，超过期限暂停自动修复，恢复网络验证后可再次启用。
- 登录启动需要在实际安装到 Applications 的 App 上测试，并检查 macOS 登录项授权。
- 最后切换正式商品配置，核对 checkout/价格/Store/Product/Variant 一致，再发布正式版。

目前完成的是 mock API + 内存存储测试，尚未完成真实测试订单、钥匙串跨版本访问、系统登录项和界面交互验收。

## 授权实现与限制

- 激活前 validate key 校验 Store/Product/Variant；activate 使用随机安装 UUID 作为 `instance_name`。Provider 返回的 `instance.id`（不是安装 UUID）用于后续 validate/deactivate。
- Key、实例 ID、最近验证时间和安装 UUID 存于本机钥匙串，不存硬件序列号、Apple ID、MAC 地址或客户邮箱。API 响应不写日志。
- 启动、唤醒和每小时验证。执行自动修复时也检查 7 天期限；明确无效立即撤销，不给予失效 license 离线宽限。
- 激活超时可能已在服务端占用名额：没有幂等激活保证，不自动重试 activate。应在商店后台确认并清理孤立实例，再重试。
- 停用失败保留本机记录供重试。失效记录可显式移除，但不会释放服务端名额。卸载前应先停用。
- 无 Developer ID / 公证的 ad-hoc 版本升级可能再次请求钥匙串访问；需要真实升级测试。不要为了方便改成明文存储。
- 源码继续使用现有 MIT License。客户端付费限制并非防篡改 DRM；公开源码允许他人修改构建。付费产品是官方分发版本的权益与服务，不更改已经授予的开源许可。

## 官方参考

- [License API](https://docs.lemonsqueezy.com/api/license-api)
- [Activate](https://docs.lemonsqueezy.com/api/license-api/activate-license-key)
- [Validate](https://docs.lemonsqueezy.com/api/license-api/validate-license-key)
- [Deactivate](https://docs.lemonsqueezy.com/api/license-api/deactivate-license-key)
- [商品校验与实例保存](https://docs.lemonsqueezy.com/guides/tutorials/license-keys)
- [macOS SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
