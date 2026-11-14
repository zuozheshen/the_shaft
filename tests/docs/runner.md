# 统一运行器与故障诊断

[返回测试索引](../README.md)

命令均从仓库根目录执行。

## 环境与统一入口

默认统一命令见[常用命令](../README.md#issue-收尾统一检查)。也支持 PowerShell 7 的 `pwsh -NoProfile -File .\tests\run_all_tests.ps1`，不要求安装它。
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

默认依次执行版本/唯一项目根检查、执行器自测、headless editor 导入、脚本和场景契约检查、
既有流程/内容/表现层测试、project.godot 配置入口的初始化与正常关闭 smoke。
全部通过输出 `ALL CHECKS PASS` 并返回 exit 0。阶段失败、未放行的 `ERROR`、缺完成标记或超时均返回 exit 1。
Godot 子进程可能在输出 `ERROR` 后仍返回 0，须结合完整日志及完成标记判定。
依赖阶段失败后剩余阶段标为未执行。每阶段默认 180 秒，可用 `-TimeoutSeconds` 调整（1–1800 秒）。
日志写入控制台显示的系统临时目录；Warning 计数单列，ERROR 不做宽泛忽略。
Godot 4.7 在编辑器首次扫描 UID 缓存前可能对 project.godot 当前入口 UID 输出一条
`Unrecognized UID`；入口只精确允许配置中的这一条，并显示为 `allowed_diagnostics=1`。
随后 Validator 必须把同一 UID 解析为正式 main_3d 路径，真实入口 smoke 也必须通过，
否则全量检查仍失败。其他 UID、其他 ERROR 或任一后续失败都不被放行。
正常导入会生成 .godot 缓存，也可能更新 .import 元数据；不要将这些测试副作用混入提交。

## 局部阶段与分组参数

局部阶段要求当前 worktree 已完成导入，运行器会检查版本和唯一项目根。

| 参数 | 运行范围 |
| --- | --- |
| `-Check Contracts` | 脚本编译、场景契约与结构宿主自测 |
| `-Check Existing` | 功能模块，可搭配 `-Group` |
| `-Check Smoke` | 正式入口初始化与正常关闭 |

阶段通过时输出 `PARTIAL CHECKS PASS`。统一通过仍以 `ALL CHECKS PASS` 为准。
运行器报告检测到的失败，不自动修复业务或配置。

`-Group` 默认为 `All`。非 `All` 的组只允许配合 `-Check Existing`；空值、未知组或冲突参数返回非零。
`-Check Existing` 不传组时仍执行全部功能模块，并报告局部通过。每个组独立准备所需的测试内容，
执行后还原内容并等待音频清理。直接调用 flow runner 时可指定分组。

```powershell
godot.cmd --headless --path . --scene res://tests/flow_test_runner.tscn -- --group=RightConsole
```

音频、休息入口、共享资料、W 终端、左台查询和通话摘录保留各自的专项入口。专项参数与非兼容的分组参数不可混用。

### 定向结果判定

直接运行 flow runner 时，要求退出码 0、测试汇总失败 0、指定的专项完成标记（如有），且完整输出无 `SCRIPT ERROR`、`ERROR` 或 `FAIL`。检查 `MODULE SUMMARY` 中已选模块均完成。预期失败的反例按各自章节核对诊断和 exit 1。

## 结果与日志

控制台报告各阶段和整次命令的 `elapsed_ms`。功能测试分别显示选中、完成和未选中的模块数、
断言通过/失败数、最慢五个模块。完整功能日志保留逐模块开始/结束、耗时、断言计数和夹具记录。
模块耗时含该模块等待，进程启动、导入、公共夹具和收尾计入所在阶段或总耗时。
`SCENES CHECKED` 属于独立的结构检查，不能和模块数或断言数相加。

失败显示阶段、退出码、耗时、诊断数、尚未完成的模块（如有）和完整日志路径。
摘要最多摘录前 10 条诊断及各自前后两行，正文上限 80 行、12,000 字符，长行最多展示 1,000 字符。
没有匹配诊断时显示日志末尾；截断有提示。错误判定始终使用完整日志，依赖失败后标明后续阶段未执行。

默认全量包含小型执行器自测。单独验证错误判定、摘要和超时时可运行：

```powershell
powershell.exe -NoProfile -File .\tests\runner_execution_tests.ps1
```

测试重试和停止条件见 [Issue Runner 的 Circuit Breaker](../../docs/development/the-shaft-issue-runner.md#circuit-breaker)。
