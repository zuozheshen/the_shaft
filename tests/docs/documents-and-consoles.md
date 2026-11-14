# 资料与操作台专项回归

[返回测试索引](../README.md)

从仓库根目录运行。直接调用 headless 专项前须完成当前 worktree 的导入，并按[定向结果判定](runner.md#定向结果判定)核对退出码、汇总和完整输出。以下专项和分组只覆盖各自范围。各夹具的启动与操作步骤见[实机预览](visual-and-manual.md#实机预览)。

## 共享资料契约定向检查

在已完成导入的 Issue worktree 中执行：

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --documents-only
```

定向检查运行内容校验、资料状态、派单生命周期和资料流程集成。
按上方定向判定，并核对 `DOCUMENT STATE TESTS COMPLETE` 和 `DOCUMENT FLOW TESTS COMPLETE`。

覆盖多文件原子上传/整批回滚、无缺件虚拟字段、左右台取得边界和W端口、来源/版本/取得时间、
适用性Callable接入口（无正式判断器时不放行）、已提供/不适用/未知规程、索证幂等与补件、
跨来源质疑、旧版本固定引用、深副本、001前导零、旧会话拒绝及换单/结单/结束清理。
无剧情test_documents只在测试注入，不注册正式Catalog；适用性fixture不代表正式规则引擎。
此处 `call_excerpt` 的覆盖范围限于资料类型及内部取得契约。主台按钮及对白相关验证见[通话摘录专项](#主台通话摘录专项)，W 和查询 UI 见下方各专项。

独立审查回归还覆盖：尚未初始提交时禁止索证/质疑，允许首个空文件批次原子记录完成事件；
失败提交和系统查询不能满足此门。跨出处覆盖须保留source_note，字段source与acquisition分离，
引用系统记录不等于取得原件。左右台query_id按一次查询事件分配，新查询/刷新使用新ID，回调重试复用原ID/版本；
重复查询、新版本刷新和延迟回调均验证幂等且不回退资料。

## W 呼出终端定向检查

在已导入的 worktree 中执行：

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --verification-terminal-only
```

沿用现有宿主，运行 VerificationTerminalTests、VerificationWorkspaceTests 和既有 GamepadSupportTests。
按上方定向判定，并核对 `VERIFICATION TERMINAL TESTS COMPLETE` 和 `VERIFICATION WORKSPACE TESTS COMPLETE`。

覆盖真实 Viewport 的 W/View/A/B 输入、W/ui_up冲突、echo/快速反转、
转向中打开、事件与轮询阻断、A/B持有到收起后、有效/失效焦点恢复、COMM刷新、左台阅读状态、
同单UI保留与session清理、行驶持续推进、六种窗口尺寸的机身包络、等比缩放、16:9 屏口及动画中 resize。
滚动保存以布局稳定后实际可达的位置为准，不把超出ScrollContainer上限的请求值当作保留基准。

正式空舱可使用W或手柄View打开终端，B或收起按钮关闭；参数在核验终端Inspector中调整。
W 机壳按固定比例整体缩放，CanvasLayer 由实际 16:9 屏口四角投影定位，从画面下方垂直升起或收回。开合过程中接管持续生效，资料操作在完全打开后恢复。
W 左侧目录有乘客材料、规程与样板、人员记录、楼层档案和陈述摘录。点击目录里的已开版本找回并置顶原窗。「整理窗口」收折目录并排资料。每窗可独立滚动、拖动、单角柄缩放、关闭与恢复。键盘Tab/Shift+Tab与方向导航，Enter/Space确认；正文Up/Down、PageUp/PageDown、
Home/End滚动。手柄A确认，右摇杆滚动当前资料，B收起；开合和刷新不执行索证/质疑。

工作区测试使用明确的1920×1080窗口和实际溢出的阅读窗，避免headless默认窗口/缩放令正文无需滚动。
覆盖资料通知、原子收件、目录找回同一版本、键鼠/手柄焦点、文档内旧版重开、固定 FieldRef、鼠标标题拖动/角柄、参考资料同屏与会话撤销。证据托盘两框各自清空，主体定位精确字段或原文。单个有效规程可在任一框提交索证，双字段质疑沿用原规则。交付失败显示「回应未送达」，界面无重试入口。

三文件陈述拖选原型使用 `-Check Existing -Group Presentation`，见[原型预览步骤](visual-and-manual.md#三文件陈述拖选原型)。

## 左台当前乘客档案定向检查

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --left-lookup-only
```

使用正式场景和进程内无剧情夹具，覆盖真实鼠标档案键、手柄调阅键、三份循环切换与独立滚动、
每份未读、单份取得、旧版/新版本和 session 撤销。按上方定向判定，并核对 `LEFT LOOKUP TESTS COMPLETE`。

## W 审查专项

```powershell
.\tests\run_all_tests.ps1 -Check Existing -Group Flow
```

Flow 覆盖规则、等价依据、当前已取得版本、交付失败重试、补件去重和换单隔离。手动步骤见 [W 审查预览](visual-and-manual.md#w-审查预览)。

## 主台通话摘录专项

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --call-excerpt-only
```

专项覆盖 Dialogue Manager 的 wait 期间换单、旧回执、来源与幂等。手动步骤见[主台通话摘录预览](visual-and-manual.md#主台通话摘录预览)。

## 右台楼层档案

右台定向选择 `RightConsole`，业务行驶联锁选择 `Flow` 和 `Presentation`。操作步骤见[右台楼层档案预览](visual-and-manual.md#右台楼层档案预览)。

## 运输改送与离舱回执

Flow 覆盖未调查发车、到站改送、结果快照和旧回执隔离。Presentation 覆盖实际乘客动作、离舱失败、恢复后重试与门控顺序。无表现层的测试显式提交测试回执。手动步骤见[运输改送预览](visual-and-manual.md#运输改送预览)。
