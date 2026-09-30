# 免费版测试

先 `bash source/build.sh`，再 `python3 tests/test_suite.py`。

默认安全测试不发出守护进程信号，不修改系统设置，覆盖：免费包不残留购买资源/授权模块、进程超时、修复与调度回归、真实网络回调、双架构、蓝牙声明、诊断入口、签名。

`--self-test` 使用伪命令验证故障处理、去抖、冷却和调度取消。`--process-self-test` 仅运行测试子进程。需要实际故障注入时单独使用 `python3 tests/test_suite.py --fault-injection`，它会短暂暂停当前用户共享服务并验证恢复，有独立 watchdog；不要作为默认 CI 执行。

首次安装、旧版升级、登录项、蓝牙备用授权、真实窗口和跨设备复制粘贴仍需人工验证。静态 SwiftUI 预览不代表真实 GUI 验收。
