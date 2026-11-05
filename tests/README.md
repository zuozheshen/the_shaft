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
既有流程/内容/表现层测试、project.godot 配置入口的初始化与正常关闭 smoke。
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

## 音频退出回归

`run_main_smoke.gd`在Autoload注册后读取project.godot当前配置入口并实例化，
将它设为current_scene，运行120帧以完成ready/延迟注入，确认环境MP3确实播放、
根窗口接线到RuntimeConnector3D.request_quit，再连续发送两次close_requested。
成功标记必须同时包含MAIN SMOKE READY和AUDIO SHUTDOWN COMPLETE；
仅进程退出码0、或仅初始化完成均不能通过。

正常关闭暂停业务以阻止新播放，停止2D/3D音频，使用WeakRef等待播放实例实际释放，
以真实时间限制最多1000ms；超时报ERROR并退出1，不忽略音频错误、不静音或删除资源。
AudioShutdown仅是无Autoload的释放辅助脚本，不拥有业务状态。

原`--quit-after`直接终止引擎，绕过正常关闭，仍可能触发Godot的音频退出问题；
不把此修复说成引擎本身已修复。当前smoke验收的是正式入口的正常退出路径。
Editor Stop/强制结束进程也不保证经过应用的关闭回调。

`runtime/audio_shutdown_tests.gd`覆盖MP3、2D/3D WAV、真实销毁、强引用超时和已移除节点。
flow runner在node_removed只记录弱引用，避免在退出树过程中重入stop；
原生PREDELETE负责停止已移除播放器，退出测试进程前统一等待这些实例释放。
专项诊断命令（不是全量检查）：

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --audio-shutdown-only
```

真实退出失败反例（应输出音频清理超时并返回exit 1，不能记作通过）：

```powershell
godot.cmd --headless --path . --script res://tests/run_main_smoke.gd -- --retain-audio-playback
```

该开关仅在测试宿主持有播放实例，不进入正式游戏。统一检查的ERROR过滤未放宽。

## Scene Contract Validator v1

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

## 人工体验验收

在 Godot 4.7 运行正式入口，确认初始318、空舱待机与三个台位。
使用 CAM 02 检查318；输入001、验证、执行，再前往002并返回318，
确认只在实际到站后切换视觉、编号前导零正确、过程中不能开门。
检查门、椅子转向、按钮、滚轮、键盘、验证及拨杆的已有音效；书本及其专属音效应消失。
左台显示中性空态/真实日志，MIC 提示“对话功能暂时停用”，右台不显示旧关联评估。
正式空舱不显示 COMM，也不创建对话适配器；鼠标和手柄均应能操作三台，转向后焦点正常恢复。
对话/UI 源文件保留，无剧情夹具在测试实例中单独启用，不影响正式操作舱的临时停用状态。

Headless 不验证字体可读性、D3D12 画面、音频或节奏；Godot AI 自检和用户人工验收分别记录。
当前 main 基线 e46053c 的两枚门按钮帽使用相同灰色素材，自动测试不再强制旧 OPEN/CLOSE 配色。

## 318 美术工具验证

以下命令用于独立美术制作流程，并非本次空舱内容重置的必跑项。

#75 Pass A/B 的只读布局门（不执行 Aseprite 或 PNG 导出）：

```powershell
godot.cmd --headless --path . --script res://tools/aseprite/validate_floor_profile.gd -- --check-layout
```

成功标记为 `LAYOUT CHECKS PASS`。它实例化正式 main_3d，对照
`art_source/floors/floor_slice_layout_v1.json` 检查七个 Quad、完整 Transform、
320×240 机位参数、固定遮挡、Marker、共享编号字号/描边/颜色/贴墙位置和规范化 LF 源文件 hash。
`--print-layout` 可附加输出当前几何 JSON；命令始终只读正式源和清单。
mask 来自 B 的实机校对与固定 Box 射线计算，命令不把几何一致性冒充截图验收。
几何门只读冻结清单；318 正式美术以 ART09 Darker R3 Profile 与 receipt 为准。

#75 Pass C 的真实 CLI / 导入校验（需本地 Aseprite 1.3.x，先设置 ASEPRITE_PATH）：

```powershell
powershell.exe -NoProfile -File .\tests\tools\aseprite_pipeline_tests.ps1 -AsepritePath "$env:ASEPRITE_PATH"
godot.cmd --headless --path . --script res://tools/aseprite/validate_floor_profile.gd -- --check-profile --density=64
```

CLI fixture 覆盖正式隐藏层违规、辅助层/参考层排除、RGB 精确 palette、
二值 alpha、固定空层、重复七图 hash/source 不变、新参考副本及拒绝覆盖、
部分发布失败回滚、未知输出与越界路径、未批准正式导出门。
Profile 检查实际七图导入尺寸/像素与 receipt、材质 Scissor 0.5、白色 × tint 和冻结几何。
运行时测试另验证 null/reset 恢复原透明模式、threshold 与 material_override。
CLI 不替代上方统一入口；截图与用户体验也不由 headless 代验。
318 正式源与测试 fixture 的色板不同；正式输入使用显式 Source/PaletteFile，禁止以诊断输入误覆盖正式美术。
完整命令和失败恢复见 [管线文档](../docs/development/aseprite-floor-pipeline.md)。


## 共享资料契约定向检查

在已完成导入的 Issue worktree 中执行：

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --documents-only
```

沿用同一测试宿主，只运行内容校验、资料状态、派单生命周期和资料流程集成。
确认 DOCUMENT STATE TESTS COMPLETE、DOCUMENT FLOW TESTS COMPLETE、测试汇总失败0、进程exit0，
并检查没有 SCRIPT ERROR / ERROR / FAIL；Godot可能在脚本异常后仍返回0，不能单看退出码或断言汇总。
该定向检查不等于统一入口 ALL CHECKS PASS。

覆盖多文件原子上传/整批回滚、无缺件虚拟字段、左右台取得边界和W端口、来源/版本/取得时间、
适用性Callable接入口（无正式判断器时不放行）、已提供/不适用/未知规程、索证幂等与补件、
跨来源质疑、旧版本固定引用、深副本、001前导零、旧会话拒绝及换单/结单/结束清理。
无剧情test_documents只在测试注入，不注册正式Catalog；适用性fixture不代表正式规则引擎。
call_excerpt只验证类型/内部取得契约，未接主台按钮或对白；没有W/查询UI或视觉修改。


独立审查回归还覆盖：尚未初始提交时禁止索证/质疑，允许首个空文件批次原子记录完成事件；
失败提交和系统查询不能满足此门。跨出处覆盖须保留source_note，字段source与acquisition分离，
引用系统记录不等于取得原件。左右台query_id按一次查询事件分配，新查询/刷新使用新ID，回调重试复用原ID/版本；
重复查询、新版本刷新和延迟回调均验证幂等且不回退资料。

## W 呼出终端定向检查

在已导入的 worktree 中执行：

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --verification-terminal-only
```

沿用现有宿主，运行 VerificationTerminalTests 和既有 GamepadSupportTests。
核对 VERIFICATION TERMINAL TESTS COMPLETE、汇总失败0、无 SCRIPT ERROR/ERROR/FAIL 与进程exit0；
这不是统一入口 ALL CHECKS PASS。覆盖真实 Viewport 的 W/View/A/B 输入、W/ui_up冲突、echo/快速反转、
转向中打开、事件与轮询阻断、A/B持有到收起后、有效/失效焦点恢复、COMM刷新、左台阅读状态、
同单UI保留与session清理、行驶持续推进、四种分辨率及动画中resize。
滚动保存以布局稳定后实际可达的位置为准，不把超出ScrollContainer上限的请求值当作保留基准。

正式空舱可使用W或手柄View打开终端，B或收起按钮关闭；参数在核验终端Inspector中调整。
灰盒按视口宽度约75%–80%校准，实际机身厚度、支座、遮挡、字体与动效仍需Godot AI和用户实机验收。
本Issue只有单一占位面板；资料收件箱、多窗口和正式审查操作未接入。
