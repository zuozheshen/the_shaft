# 运行时与场景结构回归

[返回测试索引](../README.md)

直接运行 headless 专项前，先确认 worktree 已导入并了解[结果判定](runner.md#定向结果判定)。

## Scene Contract Validator v1

常规局部验证使用 `-Check Contracts`。结构宿主通过时输出 `PROJECT CHECKS PASS`，外层运行器再报告 `PARTIAL CHECKS PASS`。

`project_check_runner.tscn` 是独立的最小结构宿主；`run_flow_tests.gd` 继续用
既有 preload + run 模式注册功能测试。结构宿主只加载脚本、调用 Validator 和自测，不另建业务或通用测试框架。
显式加载 scripts/tests/addons 的 GDScript，检查未被主场景触及的脚本编译。

`structure/scene_contract_validator.gd` 从实际 project.godot、正式 PackedScene 和脚本检查：

- 入口 UID 解析、两个必需 Autoload 的名称/脚本/单例设置、重复 Autoload，以及代码使用的转向 action。
- 主场景 → GameRuntime → 唯一 DemoFlowManager；禁止在 Autoload 另建核心 Manager。
- 三台 Router 和 UI 的脚本、公共入口，以及固定名称查询实际需要的节点。
- 视角、交互、左台屏幕与监控 controller 的固定/导出 NodePath、目标类型。
- 摄影棚的楼层/乘客 mount、门和机位引用；乘客/楼层实例应位于负责移动/替换的 mount 下。
- 门脚本直接引用的三个动画名称、公共方法和信号。
- 主台/右台展示绑定、全局通讯窗和左右台输入避让的路径、类型、方法及信号；右台实体键盘、验证键、执行拨杆和关键实例唯一性。

覆盖主场景、运行层、操作舱、三个操作台 UI、通讯窗、摄影棚、门、乘客、楼层切片共 11 个正式场景。
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

## 空舱基线与通用框架测试

`content/content_reset_tests.gd` 使用未注入夹具的正式 main_3d，验证：

- 正式楼层恰好为 318、001、002，人物/派单/值班 Catalog 为空。
- 正常空闲启动于318；没有自动派单、人物或假结算。
- 真实三台接线、CAM、门控保护、地址验证、前导零和三层往返。
- 未登记楼层拒绝，楼层索引书及其视口已移除，运行音效组件保留。

通用框架测试随后由 `fixtures/runtime/test_content.gd` 在内存临时注入无剧情数据，
覆盖派单状态隔离、三次连续结算、对话适配器、门/乘客时序、楼层覆盖与 fallback、
通讯窗焦点、键鼠/手柄以及美术外形替换。测试结束恢复原 Registry。
这些夹具中的额外编号仅用于边界测试，不改变正式 Catalog，不代表正式内容。
测试对白为 `fixtures/runtime/test_passenger.dialogue`，不复制已移除的故事。

内容验证器继续验证 ID、资源引用、派单字段、对白标题、推荐资格等通用契约；
已移除 camera_feeds 数据、相应校验及仅断言旧剧情内容的测试。
楼层书专项与书本输入锁/热点契约随功能一起删除，其余设备输入验证继续保留。

运行器以正式最小测试场景启动，使 Autoload 在脚本编译前完成注册；
场景契约、运行流程与入口 smoke 分别报告，不能互相替代。

## 音频退出回归

正式入口 smoke 可用 `-Check Smoke` 局部验证。

`run_main_smoke.gd` 在Autoload注册后读取project.godot当前配置入口并实例化，
将它设为current_scene，运行120帧以完成ready/延迟注入，确认环境MP3确实播放、
根窗口接线到RuntimeConnector3D.request_quit，再连续发送两次close_requested。
成功要求退出码 0、完整日志无错误，并依次出现 `MAIN SMOKE READY` 和 `AUDIO SHUTDOWN COMPLETE`。

正常关闭暂停业务以阻止新播放，停止2D/3D音频，使用WeakRef等待播放实例实际释放，
以真实时间限制最多1000ms；超时报ERROR并退出1，不忽略音频错误、不静音或删除资源。
AudioShutdown仅是无Autoload的释放辅助脚本，不拥有业务状态。

原`--quit-after`直接终止引擎，绕过正常关闭，仍可能触发Godot的音频退出问题；
不把此修复说成引擎本身已修复。当前smoke验收的是正式入口的正常退出路径。
Editor Stop/强制结束进程也不保证经过应用的关闭回调。

`runtime/audio_shutdown_tests.gd`覆盖MP3、2D/3D WAV、真实销毁、强引用超时和已移除节点。
flow runner在node_removed只记录弱引用，避免在退出树过程中重入stop；
原生PREDELETE负责停止已移除播放器，退出测试进程前统一等待这些实例释放。
专项定向诊断命令

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --audio-shutdown-only
```

以下是实际退出路径的失败反例，预期输出 `音频退出清理超时：仍有播放实例未释放。` 并返回 exit 1。

```powershell
godot.cmd --headless --path . --script res://tests/run_main_smoke.gd -- --retain-audio-playback
```

该开关仅在测试宿主持有播放实例，不进入正式游戏。统一检查的ERROR过滤未放宽。

## 休息入口与开发者页

正式场景从仰躺休息菜单开始。点「开始值守」坐起并进入原主台。Esc 或手柄 Menu / Start 从休息菜单、台位或 W 文书进入同一个设置页，再按一次原路返回。退出、显示预览、改键确认先处理自己的取消操作。普通文书仍用 W / View 开合，B 保留原文书取消。

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --cabin-entry-only
```

专项覆盖三条返回路径、实际行驶 Timer、设置存储和输入保留。W 定向测试覆盖原文选区与焦点，通话摘录定向测试覆盖设置暂停期间到期的对白回调。相关人工步骤见[休息入口与设置页](visual-and-manual.md#休息入口与设置页)。
