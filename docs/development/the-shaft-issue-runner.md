# the-shaft-issue-runner

`Run issue #<number>` 的项目路由协议。它依赖人工启动和已有工具，不是后台服务。

## 最短路由

1. 读取当前 Issue 正文与有效评论、`AGENTS.md`，检查 repo/worktree 的 status、branch、HEAD。
2. 识别冻结规格、当前阶段、风险、计划版本、有效审批及最新约束；已有对应批准时直接续接。
3. 渐进加载上下文：需要结构事实才读 `PROJECT_STATE.md`；准备测试才读 `tests/README.md`；
   设计文档仅在 Issue 引用或设计决策需要时读取；代码、场景和资源只读相关范围。
4. 按风险门进入 DESIGN、PLAN 或已批准的 BUILD；规格、基线或范围冲突时报告并重新过门。
5. 先运行受影响测试或最小复现；风险或验收要求需要时，只做一次最终统一验证。
6. 完成 REVIEW 和范围内本地 commit，写回当前 Issue，停在 push/merge 前。

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
- 测试选择遵循 `AGENTS.md`：受影响测试优先；正式结构/运行时/公共行为或 Issue 要求时，
  REVIEW 前运行一次 `tests/run_all_tests.ps1`。文档-only 默认不跑游戏全量测试。
- commit 前检查 diff、显式暂存当前 Issue 文件、检查 staged diff；失败或未完成不写成成功。

## Circuit Breaker

这是测试重试的唯一权威定义：

- 失败先缩小到首个失败阶段或最小复现，不从头循环全量入口。
- 同一根因最多自动重试 2 次；第 3 次出现立即停止并写回诊断，未经新批准不换更多变体继续。
- 重复权限请求、重复命令或测试阶段重入也触发停止。
- 不因清除已确认无内容差异的 Git mechanical modified 状态重新运行全量测试。

诊断记录首个稳定失败、精确错误、已重试次数、已完成步骤和下一步最小建议。

## REVIEW 与停止点

REVIEW 写回当前 Issue，包含：实际文件和行为、相对 base 的 diff、各验证结果与退出码、
计划偏差、已知限制、人工体验点、base/branch/commit/PR，以及未执行事项。
写回前读取最新评论避免重复；失败时标记“未同步”，恢复后先查询是否已写入。

只有本地 commit 时明确“未 push”，不伪造远端链接。默认不自主 push、merge 或改写历史；
用户决定体验验收、最终整合和发布。开发日志/飞书同步不由本路由自动触发。
