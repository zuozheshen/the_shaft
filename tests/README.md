# 内容契约、统一流程命令与派单流程测试

这组测试保留 Issue 30 的派单流程基线和 Issue 31 的运行时职责拆分保护，
覆盖 Issue 32 的结构化流程命令入口，并加入 Issue 33 的内容资源契约校验。
测试只使用 Godot 4.7 自带的 headless 场景入口，不安装 GUT 或其他第三方依赖，
也不会启动正式 3D 主场景。

测试使用最小的 `tests/flow_test_runner.tscn`，让项目 Autoload 在流程脚本编译前
完成注册；该场景只挂载测试运行器，不实例化或修改正式主场景。

## 覆盖范围

- `ContentValidationReport` 的 Error / Warning 分离、格式、统计和数组副本。
- Floor、Passenger、Dispatch、DispatchFloorRelation 与 Shift 的 ID、引用和字段契约。
- `pickup_data`、八个活动阶段的摄像头双画面及前台 state / task 契约。
- Dialogue 标题、`destination_<floor>` 和双引号 `unlock_floor("<floor>")` 的轻量扫描。
- 未被值班引用的派单、未被派单引用的乘客和普通楼层缺反馈的 Warning。
- `ContentRegistry.validate_all_content()` 对正式 Catalog 原始数组执行自检，Error 会使测试失败。
- `DispatchPhase` 的九个正式阶段、合法与非法转换、接乘楼层离开/返回转换及幂等设置。
- `ElevatorRuntimeState` 的初始化、门控、移动、到站状态和信号。
- `DispatchLifecycle` 的状态隔离、阶段转换、乘客状态、反馈标记和推荐去重。
- `DispatchLifecycle` 的门外确认、登舱、关门确认和到站反馈四个原子操作。
- `ShiftRunner` 的派单顺序、结果副本、空值班、重启和幂等结束。
- `UIHistoryState` 的对话/日志分离、短提示、长度裁剪、数组副本和清理。
- `FlowCommandResult` 的字段、成功/失败结果、效果查询和数组副本。
- `DemoFlowManager` 的初始楼层、门控和移动保护。
- 接乘到达、可选的门外确认、直接登舱、离开与返回接乘楼层、关门后进入舱内阶段。
- 目标验证与选择、目标到达、反馈触发幂等、等待关门和派单结算。
- `CASE_001` 到 `CASE_003` 的三单顺序加载、派单运行时状态隔离和幂等值班结束。
- 七个流程命令的成功、失败、原子状态与中性 effects。
- 命令失败结果在确实清除旧状态时可携带清理类 effect；空状态不虚构清理。
- 空地址、未知地址、`004`、自由移动、搭载验证和失败移动目标保护。
- 前两单关门启动下一单、第三单关门成功结束值班，以及一次最终 `case_updated`。
- 三个操作台继续通过 `DemoFlowManager` 的兼容 API 接入。
- 源码边界检查确保主台和右台不再组合被禁止的低级状态写入。

旧基线仍会实例化三个独立 UI 组件确认 `DemoFlowManager` 注入兼容性；命令专项测试
不会实例化正式 3D 操作台或 Dialogue Manager，也不会复制对话内容或伪装成完整
按钮交互测试。正式操作台的视觉、焦点、摄像头、麦克风和 Dialogue 上下文仍需手动验收。

## Windows PowerShell 执行

Godot Steam 版可执行文件名为 `godot.windows.opt.tools.64.exe`。

```powershell
$godotPath = "<Godot安装目录>\godot.windows.opt.tools.64.exe"
$testLog = Join-Path $env:TEMP "the-shaft-flow-tests.log"
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $godotPath
$startInfo.Arguments = "--headless --path `"F:\the_shaft`" --log-file `"$testLog`" --scene `"res://tests/flow_test_runner.tscn`""
$startInfo.UseShellExecute = $false
$process = [System.Diagnostics.Process]::Start($startInfo)
if (-not $process.WaitForExit(120000)) {
  $process.Kill()
  throw "Godot tests exceeded 120 seconds."
}
exit $process.ExitCode
```

`WaitForExit(120000)` 为所有自动测试提供 120 秒超时保护。

退出码：

- `0`：全部测试通过。
- 非 `0`：至少存在一项失败或脚本加载错误。

运行器会逐项输出测试名称和 `PASS` / `FAIL`，最后输出通过数与失败数。

## 已知限制与手动验证

自动测试不实例化正式 3D 操作台和 Dialogue Manager 对话，因此仍需在 Godot 4.7
中运行 `scenes/main/main_3d.tscn`，手动确认：

1. 到达接乘楼层后，无需门外通话也能直接开门接乘。
2. 摄像头切换不会限制麦克风开关。
3. 乘客登舱后，必须关门才可进入舱内正式询问。
4. 到达目标本身不触发反馈；首次开门触发反馈，重复开门不重复触发。
5. 乘客离舱并关门后结算，第一条派单结束后自动进入第二条。
6. 玩家可见文案、摄像头文本和乘客对白保持不变。
