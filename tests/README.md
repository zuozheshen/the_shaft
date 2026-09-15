# 统一工程检查

仓库根目录执行：

```powershell
powershell.exe -NoProfile -File .\tests\run_all_tests.ps1
```

也支持 PowerShell 7 的 `pwsh -NoProfile -File .\tests\run_all_tests.ps1`，不要求安装它。
如果 Windows 执行策略禁止脚本，在获准后可仅对本次进程使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run_all_tests.ps1
```

该参数不修改系统执行策略。Godot 解析顺序：显式 `-GodotPath`、环境变量
`GODOT_BIN`、PATH 中的 `godot.cmd` / `godot` / `godot.exe`。
找不到或不是 4.7.x 时明确失败，不安装软件，也不使用本机 Steam 路径作为默认值。

```powershell
powershell.exe -NoProfile -File .\tests\run_all_tests.ps1 -GodotPath "D:\Your Godot Folder\godot.exe"
```

默认依次执行版本/唯一项目根检查、headless editor 导入、脚本和场景契约检查、
既有流程/内容/表现层测试、project.godot 配置的真实入口 smoke。
全部通过输出 `ALL CHECKS PASS` / exit 0；任何失败、ERROR、缺完成标记或超时返回 exit 1。
不能只看 Godot 子进程退出码：引擎有时输出 ERROR 后仍返回 0。
依赖阶段失败后剩余阶段标为未执行。每阶段默认 180 秒，可用 `-TimeoutSeconds` 调整。
日志写入控制台显示的系统临时目录；Warning 计数单列，ERROR 不做宽泛忽略。
Godot 4.7 在编辑器首次扫描 UID 缓存前可能对 project.godot 当前入口 UID 输出一条
`Unrecognized UID`；入口只精确允许配置中的这一条，并显示为 `allowed_diagnostics=1`。
随后 Validator 必须把同一 UID 解析为正式 main_3d 路径，真实入口 smoke 也必须通过，
否则全量检查仍失败。其他 UID、其他 ERROR 或任一后续失败都不被放行。
正常导入会生成 .godot 缓存，也可能更新 .import 元数据；不要将这些测试副作用混入提交。

排查时可在已导入项目中使用 `-Check Contracts`、`-Check Existing` 或 `-Check Smoke`
单独运行一项；输出明确标为 `PARTIAL CHECKS PASS`，不能当成全量通过。
这仍是同一 shell 入口，不自动修复失败的业务或配置。

## Scene Contract Validator v1

`project_check_runner.tscn` 是独立的最小结构宿主，按已批准约束保持既有
`run_flow_tests.gd` 不变。它只加载脚本、调用 Validator 和自测，不另建业务或通用测试框架。
显式加载 scripts/tests/addons 的 GDScript，检查未被主场景触及的脚本编译。

`structure/scene_contract_validator.gd` 从实际 project.godot、正式 PackedScene 和脚本检查：

- 入口 UID 解析、两个必需 Autoload 的名称/脚本/单例设置、重复 Autoload，以及代码使用的转向 action。
- 主场景 → GameRuntime → 唯一 DemoFlowManager；禁止在 Autoload 另建核心 Manager。
- 三台 Router 和 UI 的脚本、公共入口，以及固定名称查询实际需要的节点。
- 视角、交互、左台屏幕与监控 controller 的固定/导出 NodePath、目标类型。
- 摄影棚的楼层/乘客 mount、门和机位引用；乘客/楼层实例应位于负责移动/替换的 mount 下。
- 门脚本直接引用的三个动画名称、公共方法和信号。

覆盖主场景、运行层、操作舱、三个 UI、摄影棚、门、乘客、楼层切片共 10 个正式场景。
实例不加入 SceneTree，不调用业务 setup/getter/_ready。诊断包含场景路径、节点/属性、预期和实际。
固定路径来自代码，导出路径允许重新配置，Router 查询不固定多余的中间容器。
不读取 PROJECT_STATE 作为测试配置；不固定装饰、坐标、尺寸、颜色、材质或完整动画轨道。
方法/信号检查证明入口存在；初始化 smoke 捕获启动错误，二者均不等同于完整按钮交互验证。

`structure/scene_contract_tests.gd` 使用临时未入树实例验证缺节点、缺脚本、错误类型、
空/无效 NodePath、丢失 unique name、错误 mount、重复 Manager、方法/信号缺失、
错误入口/Autoload/Input。另验证正常调整导出路径、装饰和布局容器不会误报。
不在磁盘复制或改写正式乘客、派单、对白或场景。

可单独检验进程失败通路：

```powershell
godot.cmd --headless --path . --scene res://tests/project_check_runner.tscn -- --negative-control
```

此诊断仅在内存移除核心 Manager，应输出包含
`main_3d.tscn | 游戏运行层/演示流程管理器` 的失败信息并返回 exit 1；这不是通过命令。
唯一 project.godot 检查由 shell 完成，含未跟踪子目录，但不跟随目录链接或扫描 .git/.godot。

## 既有内容契约、统一流程命令与派单流程测试

这组测试保留 Issue 30 的派单流程基线和 Issue 31 的运行时职责拆分保护，
覆盖 Issue 32 的结构化流程命令入口，并加入 Issue 33 的内容资源契约校验。
既有测试只使用 Godot 4.7 自带的 headless 场景入口，不安装 GUT 或其他第三方依赖；
全量入口会另行启动正式 3D 主场景做有限帧 smoke。

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
- 监控摄影棚挂载、分层楼层、纸片乘客、独立双开门及乘客登/离舱表现时间线。
- 楼层视觉 Profile 与正式 Catalog/场景配置对应；前导零、重复/空配置、setup、实际到站先视觉后乘客、七层完整覆盖、fallback 与多层往返。
- Profile 切换保留门动画、乘客 Profile 与登/离舱 Tween；CAM 切换不重置楼层，门外灯倍率不累积且受光层与舱内/乘客隔离。Scene Contract 检查门外灯导出路径和楼层公共 API。

旧基线仍会实例化三个独立 UI 组件确认 `DemoFlowManager` 注入兼容性；命令专项测试
不会实例化正式 3D 操作台或 Dialogue Manager，也不会复制对话内容或伪装成完整
按钮交互测试。正式操作台的视觉、焦点、摄像头、麦克风和 Dialogue 上下文仍需手动验收。

既有运行器逐项输出测试名称和 `PASS` / `FAIL`，最后输出通过数与失败数；
统一入口将详细输出留在 existing-tests.log，控制台展示汇总。

## 已知限制与手动验证

自动测试不实例化正式 3D 操作台和 Dialogue Manager 对话，因此仍需在 Godot 4.7
中运行 `scenes/main/main_3d.tscn`，手动确认：

1. 到达接乘楼层后，无需门外通话也能直接开门接乘。
2. 摄像头切换不会限制麦克风开关。
3. 乘客登舱后，必须关门才可进入舱内正式询问。
4. 到达目标本身不触发反馈；首次开门触发反馈，重复开门不重复触发。
5. 乘客离舱并关门后结算，第一条派单结束后自动进入第二条。
6. 玩家可见文案、摄像头文本和乘客对白保持不变。
7. Q/E 转向、左台屏幕点击、主台两机位、门动画及乘客进出保持可用；
   Output 不应新增解析、缺节点、重复 Manager 或连接错误。无需编辑节点。

Headless 使用无画面驱动，不能证明 D3D12 画面、焦点、字体、音频或体验节奏正确。
楼层视觉还需人工确认：启动 CAM 02 与实际楼层一致，900→612→900→004→387
只在抵达后切换，FLOOR 004 编号完整，回访无纹理/显隐/色调残留；
接乘层先显示正确背景再出现乘客，门与乘客动画连续，CAM 01 舱内照明不受影响。
已有材质可能报告 triplanar / height mapping Warning；查看具体日志，不自动改美术来消除它。
