# The Shaft：稳定项目事实

仅在真实结构变化时更新；动态任务、审批、分支与执行结果记录在 GitHub Issue。
以下事实块供人和 Agent 阅读，不是游戏运行时配置；可执行事实来自 project.godot 和资源。

```json
{
  "godot_version": "4.7",
  "main_scene": "res://scenes/main/main_3d.tscn",
  "autoloads": {
    "DialogueManager": "res://addons/dialogue_manager/dialogue_manager.gd",
    "ContentRegistry": "res://scripts/data/content_registry.gd",
    "_mcp_game_helper": "res://addons/godot_ai/runtime/game_helper.gd"
  }
}
```

## 核心与结构

- 玩家是操作员：接调度 → 到接乘楼层 → 查看记录/监控/通话 → 开门接乘并关门 → 判断目的地与路线 → 到站开门反馈 → 离舱关门结算 → 后续记录反馈。日志和记录承担责任，不是好坏计分。
- `scenes/main/main_3d.tscn` 组合游戏运行层、三维操作舱和 RuntimeConnector3D。入口 UID 由 Godot 解析。
- `scenes/runtime/game_runtime.tscn` / GameRuntime 持有唯一 DemoFlowManager；后者协调 ElevatorRuntimeState、DispatchLifecycle、ShiftRunner 和 UIHistoryState。
- `scenes/elevator/elevator_cabin_3d.tscn` 提供固定视角/交互。CabinInterfaceRouter3D 暴露主、左、右三台；左台位于 3D 屏幕 SubViewport。主台使用实体监视器、MIC/CAM/门按钮、三灯与 CASE/PHASE 状态条；右台使用实体信息屏、独立 LCD、验证键、4×3 键盘、静态楼层书和执行拨杆。
- MainConsolePresentation3D 将原监控 SubViewport 纹理绑定到主屏 Mesh，并订阅现有摄像头、MIC、门表现与派单展示数据；几何、碰撞、材质和布局保存在场景中，可在 Inspector 调整。MonitorCameraController3D 继续只负责原监控摄像机、机位和视口启停。
- 唯一 ConsoleInterface 位于 CanvasLayer 的全局通讯容器中，持有原 DialogueManagerAdapter；其 FloatingCommUI 只呈现当前发言和动态选项，可拖动/最小化，四个朝向及转身时持续可见。左台转发鼠标前避让通讯窗，主台旧大面板及旧按钮在 3D 模式禁用；拒绝原因使用短暂提示。
- 右台旧 DestinationControlInterface 在 3D 模式隐藏并禁用输入，但继续作为唯一目的地业务适配层；RightConsolePresentation3D 只把其展示快照映射到实体屏幕，并负责拨杆回位动画。CabinInteractionController3D 将右台热点转发到同一输入、验证和行驶入口。
- `scenes/ui/` 下 ConsoleInterface、BuildingTerminalInterface、DestinationControlInterface 通过显式注入和流程命令访问业务。
- ContentRegistry 从 `data/catalogs/` 的四个 Catalog 加载楼层、乘客、派单、值班资源。当前演示有三条正式派单；对白位于 `dialogues/passengers/`，通过 DialogueManagerAdapter 接入现有插件。
- `scenes/presentation/monitor_test_stage_3d.tscn` 是正式主场景当前使用的监控摄影棚：可替换楼层切片、纸片乘客、双开门。MonitorCameraController3D 使用同一个世界和一台监控摄像机切换两个机位；MonitorPresentationCoordinator3D 协调门与乘客动作。
- 楼层视觉由独立 FloorVisualProfile Resource 配置，位于 `data/presentation/floor_visuals/`。现有协调器在 setup 和实际到站时先应用楼层视觉，再同步乘客；移动中保持上一楼层。正式 Profile 与 fallback 由操作舱场景显式注入。
- 监控舱内、固定门区与乘客使用渲染层 2；门外环境使用层 3 和一盏共用门外灯。监控摄像机可见层 2+3，玩家摄像机排除这两层。七层保持 Unshaded，主要依靠 Profile tint 区分楼层。

## 已实现与冻结职责

- 已有内容契约校验、统一流程命令结果、三单值班顺序、派单阶段和状态隔离。
- 已有三台 UI、实时监控、分层 2.5D 切片、纸片乘客、门动画和登/离舱表现。
- 正式业务状态归运行层；表现层不另存派单数据库或决定业务结果。摄像头提供证据，乘客内容来自资源而非 UI 硬编码。
- 不重复创建 GameRuntime、DemoFlowManager、ContentRegistry、DialogueManager、第二套业务状态机或第二 Godot 项目。
- 测试基础设施只验证项目，不参与游戏运行时。测试入口与限制见 `tests/README.md`。
- `addons/godot_ai/` 固定为官方 Godot AI v4.1.0 开发基础设施；`_mcp_game_helper` 只为编辑器启动的游戏进程提供截图、日志和运行时检查，不是 gameplay Manager，导出时由插件剥离。

## 已知技术债与验证边界

- 监控摄影棚的资源文件名仍包含 test，但已被主场景引用，不能当作可删除的测试夹具。
- RuntimeConnector3D 的若干表现依赖缺失时会降级；结构检查应指出正式接线丢失，不能仅以进程正常退出判断健康。
- Headless 检查不验证 D3D12 实际画面、鼠标焦点、字体可读性、音频或体验节奏；仍需 Godot 人工体验验收。
- 操作舱和监控采用简化/占位美术；不得把现有装饰层级、坐标或材质冻结成结构 API。
