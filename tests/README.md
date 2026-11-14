# 测试入口

先按改动选分组或专项，详细参数和验收步骤按下表查阅。下列命令均在仓库根目录执行。

## 常用命令

### 局部功能检查

在当前 worktree 已完成 Godot 导入后执行，按改动替换组名。

```powershell
powershell.exe -NoProfile -File .\tests\run_all_tests.ps1 -Check Existing -Group RightConsole
```

从[功能分组](#功能分组)选择最接近改动的组。直接调用 Godot 的旧专项命令见[专项导航](#按改动定位专项)。

`-Check Existing` 省略 `-Group` 会执行全部功能模块。结构和启动/正常退出可分别选
`-Check Contracts`、`-Check Smoke`。以上入口通过时均输出 `PARTIAL CHECKS PASS`。
参数组合、可用 Godot 路径、导入前提和失败日志见[运行器与故障诊断](docs/runner.md)。

### Issue 收尾统一检查

```powershell
powershell.exe -NoProfile -File .\tests\run_all_tests.ps1
```

PowerShell 7 可使用 `pwsh -NoProfile -File .\tests\run_all_tests.ps1`。

统一入口执行版本与唯一项目根检查、执行器自测、导入、脚本和场景契约、功能测试及正式入口 smoke。
统一通过需同时有 `ALL CHECKS PASS` 和退出码 0。错误、超时或缺少完成标记会导致失败，
具体判定和唯一允许的首次扫描 UID 诊断见[运行器说明](docs/runner.md#环境与统一入口)。

## 何时运行

执行时机以 [AGENTS.md 的验证与交接约定](../AGENTS.md#验证与交接)为准。

- **BUILD** 只做受影响的组、专项或最小复现。只改专用用例、断言或夹具时优先跑对应组；
  改到共享夹具或跨功能边界时补直接相关组。纯视觉小步优先复查相关场景。
- **选择示例** 右台按钮反馈跑 `RightConsole`，涉及手柄焦点加 `Gamepad`，影响验证后发车加 `Flow`。
- **最终 REVIEW 前** 在实现与局部验证完成后运行一次统一入口。纯文档、注释、链接等非行为变更默认静态检查，
  整个 Issue 均属此类时可省略 Godot 统一测试，并记录原因。
- **失败后** 先诊断首个失败阶段，按 [Circuit Breaker](../docs/development/the-shaft-issue-runner.md#circuit-breaker)局部复测。
  如果修复影响此前统一测试的结果，交接前须对最终版本重新运行统一入口。
- **交接** 如实记录局部测试、统一测试、退出码和人工验收。画面、字体、音频、手感和节奏由用户实机验收。
  Git 暂存、提交、推送、合并、变基以及分支和 worktree 清理由用户手动完成。

## 功能分组

组名用于 `-Check Existing -Group <组名>`。

| `-Group` | 优先覆盖的改动 |
| --- | --- |
| `Audio` | 音频播放实例的停止与释放 |
| `Content` | 内容校验、资源引用、正式空舱基线 |
| `Runtime` | 电梯状态、派单生命周期、值班、UI 历史、命令结果、共享资料状态 |
| `Flow` | 派单阶段、流程 Manager、流程命令、资料流程、通话摘录 |
| `Presentation` | 监控摄影棚、楼层外观、门动画、乘客时序、W 终端与工作区 |
| `MainConsole` | 主台按钮反馈、状态显示、COMM 界面 |
| `LeftConsole` | 左台栏目、滚动、乘客档案查询界面 |
| `RightConsole` | 右台数字查询、档案调阅、执行拨杆 |
| `Gamepad` | 手柄映射、焦点导航、滚动和通讯焦点 |

## 按改动定位专项

| 要验证的内容 | 入口与验收条件 |
| --- | --- |
| 版本、超时、日志、错误判定、执行器自测 | [运行器与故障诊断](docs/runner.md) |
| 场景结构、入口 UID、Autoload、节点与路径、失败反例 | [Scene Contract Validator](docs/runtime-and-structure.md#scene-contract-validator-v1) |
| 正式空舱、内容校验和无剧情夹具 | [空舱基线与通用框架测试](docs/runtime-and-structure.md#空舱基线与通用框架测试) |
| 音频释放、正式入口正常关闭与超时反例 | [音频退出回归](docs/runtime-and-structure.md#音频退出回归) |
| 休息菜单、设置返回、行驶 Timer 与输入保留 | [休息入口与开发者页](docs/runtime-and-structure.md#休息入口与开发者页) |
| 共享资料契约、派单资料状态与幂等 | [共享资料契约定向检查](docs/documents-and-consoles.md#共享资料契约定向检查) |
| W 开合、输入、焦点、拖选与资料工作区 | [W 呼出终端定向检查](docs/documents-and-consoles.md#w-呼出终端定向检查) |
| 左台乘客档案、版本与调阅 | [左台当前乘客档案定向检查](docs/documents-and-consoles.md#左台当前乘客档案定向检查) |
| 证据托盘、索证与质疑 | [W 审查专项](docs/documents-and-consoles.md#w-审查专项) |
| 主台通话摘录、换单与回执 | [主台通话摘录专项](docs/documents-and-consoles.md#主台通话摘录专项) |
| 右台档案、行驶联锁、运输改送与离舱 | [右台楼层档案](docs/documents-and-consoles.md#右台楼层档案)、[运输改送与离舱回执](docs/documents-and-consoles.md#运输改送与离舱回执) |
| 正式空舱人工验收、资料与操作台预览 | [人工体验与实机预览](docs/visual-and-manual.md) |
| 318 布局、Aseprite CLI、导入与 Profile | [318 美术工具验证](docs/visual-and-manual.md#318-美术工具验证) |
| 历史分组耗时、断言计数与素材记录 | [历史基线](docs/historical-baselines.md) |
