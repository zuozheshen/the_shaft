# Godot AI 开发管线

The Shaft 将官方 `hi-godot/godot-ai` v4.1.0 的 canonical addon tree 版本化在
`addons/godot_ai/`。来源固定为 GitHub Release `v4.1.0`、source commit
`7968ada03044473372a8ab4beadd975c60b9d94a`；canonical ZIP SHA-256 为
`535d8a7541871af8d991b07fe5031550dd6121a31b844400476b334a70612831`。安装或升级前必须验证
官方签名 manifest、ZIP 的大小/SHA-256 和解压后的完整文件清单。插件升级必须另开 DEV Issue，
不在 gameplay Issue 中进行。

## 仓库与本机边界

仓库跟踪 addon、`project.godot` 的 plugin enabled 状态和 `_mcp_game_helper`。helper 只为编辑器启动的
游戏进程提供截图、日志和运行时检查；官方 export plugin 会在导出快照中剥离它。DialogueManager、
ContentRegistry、主场景、Input 和 gameplay 内容不由此工具改变。

以下内容只属于用户机器，绝不提交：

- Codex 的 `config.toml`（默认在用户 `.codex` 目录，设置 `CODEX_HOME` 时跟随该目录）；
- Godot EditorSettings 中的端口、client scope、遥测、日志和 allow-hosts；
- 本机 capability 记录、Godot `user://` 更新下载、`addons/.godot_ai_update/`；
- `.godot/`、import 缓存、临时截图、运行日志、Token、Secret、Cookie 和认证材料。

Codex 配置由 Godot AI Dock 的 Configure 管理。Agent 不直接重写全局配置。插件版本、端口或 launch 参数
变化会令客户端条目成为 `configured_mismatch`；只有 Dock 明确报告未配置/不匹配，或客户端不能重新加载时，
才由用户确认 Configure 或重启客户端。正常切换同版本 worktree 不应重复 Configure。

## Visual preflight

视觉 BUILD / REVIEW 必须在任何场景写入前完成：

1. 默认先关闭或退出其他项目/worktree 的 Godot Editor，只保留当前 Issue worktree 的一个活动实例。
2. 记录 `git status --short --branch`、`git rev-parse HEAD` 与 `git rev-parse --show-toplevel`。
3. 从该 worktree 的 `project.godot` 打开 Godot 4.7，确认 Godot AI Dock 显示 server connected。
4. 确认 Codex 可调用 Godot AI，并读取 live session/project path。
5. 将 Godot AI 报告的规范化绝对 project path 与 worktree root 完全比对；身份不一致立即停止。
6. 读取当前 Scene Tree；视觉任务再运行正式 `res://scenes/main/main_3d.tscn` 并捕获 game view。
7. 按需检查 runtime Scene Tree、属性和 editor/game 日志，再开始修改。

连接失败先诊断工具链。不得退回文本猜视觉、创建替代 helper，或把临时工具修复混入 gameplay commit。
同一连接/reconfigure 根因达到 Issue Runner 的 Circuit Breaker 后停止并报告。

## BUILD 与 REVIEW

视觉循环为：小范围修改 → 运行真实正式场景 → 截图 / runtime Scene Tree / 属性 / 日志 → 对照 Issue
冻结要求 → 下一次小范围修改。纯 Transform、Inspector、材质、布局与可见性优先视觉复查；Input、signal、
presentation refresh、业务 wrapper、公共行为或数据契约变化仍跑受影响测试。视觉循环不反复跑全量；符合
项目规则时在 REVIEW 前运行一次统一测试入口。

REVIEW 必须分开记录：

- Automated logic verification：受影响测试、Scene Contract、最终统一入口及退出码；
- Godot AI visual/runtime verification：worktree/path、正式 scene、camera/station/view、截图与运行时发现；
- Human validation：已完成、待完成，或失败并回到 BUILD。

## #53 后续迁移

DEV-04 合入 main 后，保留 `dev/53-right-console-physical` 已提交实现，不搬运旧 worktree 的 `.import`、
临时插件或 `project.godot` 污染。从该分支重建干净的仓库外 worktree，在 #53 写 Remediation PLAN v2，
再用 `git merge main` 引入 DEV-04；不 rebase 或改写已共享历史。完成本页 preflight 后继续 #53 的人工验收修复。
