# 派单流程测试

这组测试为 Issue 30 建立重构前的派单流程基线。测试只使用 Godot 4.7 自带的
headless 场景入口，不安装 GUT 或其他第三方依赖，也不会启动正式 3D 主场景。

测试使用最小的 `tests/flow_test_runner.tscn`，让项目 Autoload 在流程脚本编译前
完成注册；该场景只挂载测试运行器，不实例化或修改正式主场景。

## 覆盖范围

- `DispatchPhase` 的九个正式阶段、合法与非法转换、接乘楼层离开/返回转换及幂等设置。
- `DemoFlowManager` 的初始楼层、门控和移动保护。
- 接乘到达、可选的门外确认、直接登舱、离开与返回接乘楼层、关门后进入舱内阶段。
- 目标验证与选择、目标到达、反馈触发幂等、等待关门和派单结算。
- `CASE_001` 到 `CASE_002` 的顺序加载、派单运行时状态隔离和幂等值班结束。

测试直接调用当前公开状态方法来建立 UI 操作产生的结果。它不会复制
Dialogue Manager 对话内容，也不替代正式界面的按钮交互测试。

## Windows PowerShell 执行

Godot Steam 版可执行文件名为 `godot.windows.opt.tools.64.exe`。

```powershell
& "<Godot安装目录>\godot.windows.opt.tools.64.exe" `
  --headless `
  --path "F:\the_shaft" `
  --log-file "$env:TEMP\the-shaft-flow-tests.log" `
  --scene "res://tests/flow_test_runner.tscn"
```

退出码：

- `0`：全部测试通过。
- 非 `0`：至少存在一项失败或脚本加载错误。

运行器会逐项输出测试名称和 `PASS` / `FAIL`，最后输出通过数与失败数。

## 已知限制与手动验证

自动测试不实例化正式操作台和 Dialogue Manager 对话，因此仍需在 Godot 4.7
中运行 `scenes/main/main_3d.tscn`，手动确认：

1. 到达接乘楼层后，无需门外通话也能直接开门接乘。
2. 摄像头切换不会限制麦克风开关。
3. 乘客登舱后，必须关门才可进入舱内正式询问。
4. 到达目标本身不触发反馈；首次开门触发反馈，重复开门不重复触发。
5. 乘客离舱并关门后结算，第一条派单结束后自动进入第二条。
6. 玩家可见文案、摄像头文本和乘客对白保持不变。
