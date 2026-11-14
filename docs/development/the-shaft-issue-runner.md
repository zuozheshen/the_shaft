# the-shaft-issue-runner

`Run issue #<number>` 的项目路由协议。它依赖人工启动和已有工具，不是后台服务。

## 最短路由

1. 读取当前 Issue 正文与有效评论、`AGENTS.md`，检查 repo/worktree 的 status、branch、HEAD。
2. 识别冻结规格、当前阶段、风险、计划版本、有效审批及最新约束；已有对应批准时直接续接。
3. 渐进加载上下文：需要结构事实才读 `PROJECT_STATE.md`；准备测试才读 `tests/README.md`；
   设计文档仅在 Issue 引用或设计决策需要时读取；代码、场景和资源只读相关范围。
4. 按风险门进入 DESIGN、PLAN 或已批准的 BUILD；规格、基线或范围冲突时报告并重新过门。
5. BUILD 期间只运行受影响测试或最小复现；当前 Issue 收尾、最终 REVIEW 前统一验证一次（纯文档等非行为变更除外）。
6. 完成 REVIEW 并写回当前 Issue，汇报 branch/worktree、diff、测试和建议 commit message；**不执行 git add/commit/push/merge/清理**，交由用户手动处理。

不要重排 Issue 正文来制造冗长 PLAN，也不要为了“保险”枚举整个项目或读取全部历史文档。
GitHub 连接不可用时报告动态事实缺口，不猜 Issue、不索取凭据、不伪造同步。

## 阶段与风险

风险定义和长期 Git 边界以 `AGENTS.md` 为准：

- 需求未冻结：DESIGN，只读分析并等待设计决定。
- GREEN：给出具体、可验证的计划后可 BUILD，不新增人工门。
- AMBER：无对应批准时把 PLAN 写回 Issue 并停止；已有批准且基线/范围相符时续接 BUILD。
- RED：只执行人工逐步明确授权的动作。

PLAN 只补充 Issue 尚未说明、但实施必须知道的内容：目标与非目标、实际基线、风险理由、
预计文件及原因、隔离/base/依赖、测试和验收、冲突与未知项。

## 隔离 BUILD

- 使用当前 Issue 的仓库外 worktree 和独立 `dev/<number>-<short-name>` 分支；创建前核实归属、base 和路径。
- 保留用户改动，不自动 stash/reset，不切换无关 checkout 开发，不顺手修范围外问题。
- 只实现获批范围；变更超出计划时重新过门。
- BUILD 只做与本次改动有关的局部测试、最小复现或定向诊断；不因正式结构、运行时、公共行为或测试执行器变化而在中途运行默认统一全量。
- 实现和局部验证完成后，在最终 REVIEW / 人工交接前执行一次 `tests/run_all_tests.ps1`；整个 Issue 仅为文档等不改变行为的改动时可免跑并记录。失败先按 Circuit Breaker 缩小范围并局部复测；若修复改变最终可执行版本，须再跑一次全量确认，不交付未经验证的修改。
- REVIEW 前以只读方式检查 `git diff --stat`、相关文件 diff 和当前 status；列明应提交的文件及建议 commit message。**Codex 不执行 git add/commit/push/merge/rebase/reset/stash/clean 或 worktree/分支删除**。

### Visual preflight 与 BUILD loop

视觉类 Issue 在修改前默认只保留当前 Issue worktree 对应的一个活动 Godot Editor，并按
[`godot-ai.md`](godot-ai.md) 完成 branch/HEAD/worktree、server connected、client 调用、live project path、
Scene Tree 和真实 game view 检查。project path 或 live session 身份不一致时立即停止；不得等到多实例冲突后才处理，
也不得改用文本猜画面或自行补 helper。

BUILD 按“小步修改 → 针对性局部验证 → 对照冻结要求”推进。视觉修改按 `godot-ai.md` 的必要范围检查截图、runtime Scene Tree、属性和简短日志；Godot 游戏的 GUI、声音及交互体验验收由用户自行运行并反馈。不要为等待 Editor/游戏窗口退出而进行高频 `wait` 轮询。
纯 Transform、Inspector 和视觉布局优先相关场景视觉复查；输入、signal、presentation refresh、wrapper、业务逻辑与数据契约变化只跑受影响的局部测试。**任何 BUILD 迭代都不触发默认统一全量；统一入口只在 Issue 收尾执行**。

## Circuit Breaker

这是测试重试的唯一权威定义：

- 失败先缩小到首个失败阶段或最小复现，不从头循环全量入口。
- 同一根因最多自动重试 2 次；第 3 次出现立即停止并写回诊断，未经新批准不换更多变体继续。
- 重复权限请求、重复命令或测试阶段重入也触发停止。
- 不因清除已确认无内容差异的 Git mechanical modified 状态重新运行全量测试；若最终全量后有影响结果的实质修改，必须为最终版本重新运行。

诊断记录首个稳定失败、精确错误、已重试次数、已完成步骤和下一步最小建议。

## REVIEW 与停止点

REVIEW 写回当前 Issue，包含：实际文件和行为、相对 base 的 diff、局部验证与 Issue 收尾统一测试的结果及退出码、
计划偏差、已知限制、人工体验点、base/branch/worktree/HEAD、建议 commit message，以及 Git 未执行事项。只有实际存在时才列 commit/PR。
视觉类 REVIEW 另分为 Automated logic verification、Godot AI visual/runtime verification 和 Human validation；
前两者不能写成用户人工验收已通过。
写回前读取最新评论避免重复；失败时标记“未同步”，恢复后先查询是否已写入。

Codex 默认不执行 Git 暂存、提交、推送、合并、变基或清理，不伪造本地 commit、PR 或远端链接；
用户决定体验验收、Git 操作、最终整合和发布。

## Post-integration cleanup（用户手动）

此节是**给用户的安全检查清单，不是 Codex 的自动执行阶段**。REVIEW 完成后，Codex 停止 Git 写操作；即使用户已完成 push/merge，也不自动删除任何 worktree、分支或远端资源。仅在用户询问时提供只读检查结果及具体操作建议。

用户手动清理前依次确认：

1. 目标 commit 的完整 SHA 已合入 `main`（可用 `git merge-base --is-ancestor <target-commit> main` 核实），并检查 `main` / `origin/main` 的实际状态。
2. 使用 `git worktree list --porcelain` 核对目标绝对路径、分支及 `locked` 状态；用 `git -C "<path>" status --porcelain=v1 --untracked-files=all` 确认目标 worktree 干净，且不是主工作区或其他 Issue 的工作区。
3. 确认无未提交或未跟踪的重要内容后，**由用户本人**选择是否运行 `git worktree remove "<明确的-worktree-绝对路径>"`，不默认使用 `--force`；仅在 worktree 已不存在且存在陈旧元数据时考虑 `git worktree prune`。
4. worktree 已移除且分支确实合入 `main` 后，**由用户本人**选择是否运行 `git branch -d dev/<issue-number>-<short-name>`；不使用 `-D` 绕过保护。删除远端分支也由用户自行决定。

路径、归属、合入状态或干净状态不明时，先报告风险，不提供强制清理建议。用户完成后可读取 `git worktree list`、`git branch --list "dev/<issue-number>-<short-name>"` 核实状态，但 Codex 不代为清理或声称已完成。
