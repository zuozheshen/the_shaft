# AGENTS.md

## 项目与入口

《The Shaft》是使用 Godot 4.7 制作的叙事型电梯操作员演示。玩家在电梯控制舱内工作，
根据记录、监控和乘客证词裁定路线；不要把项目改成可自由漫游的大楼探索游戏。

- 将包含 `project.godot` 的目录视为仓库根目录，不在仓库内创建第二个 Godot 项目，也不擅自移动入口文件。
- 用户输入 `Run issue #<number>` 时，按
  [Issue Runner](docs/development/the-shaft-issue-runner.md) 识别阶段、风险、审批和下一步。

## 上下文与事实源

开始任务默认只读取：

- 当前 GitHub Issue 正文及有效修订、审批。
- 本文件。
- 当前 repo/worktree 的 `git status`、branch、HEAD 和必要历史。

按任务需要再读取：

- [`PROJECT_STATE.md`](PROJECT_STATE.md)：入口、Manager、数据源、已实现结构和技术债。
- [`tests/README.md`](tests/README.md)：选择、运行或诊断测试。
- Issue 明确引用的设计文档。
- 与改动直接相关的脚本、场景和资源；仅在引用链或冲突需要时扩大读取范围。

GitHub Issue 是动态任务的唯一真相源；`PROJECT_STATE.md` 只记录慢变化事实；
实际 `project.godot`、场景、脚本和资源是可执行事实。发现冲突时报告，不猜测意图。
不要为了“保险”扫描整个项目、全部历史文档或所有场景。

## 工程边界

- 使用 Godot 4.7 兼容的 GDScript，不使用 Godot 3.x API；实现保持简单、明确、适合初学者。
- 重要状态、输入、信号、节点引用、数据和路线逻辑保留适量中文意图注释，不逐行翻译代码。
- 场景保持小巧可组合，职责和依赖显式；优先数据驱动乘客/派单内容，不在 UI 脚本硬编码内容文本。
- 不引入未经要求的大型依赖、插件、全局单例或未来系统。
- 一次只处理当前 Issue，做最小且有用的改动；不修改无关文件，不整库重排或重新设计。
- 除非同步更新全部引用，不重命名已有公共 API。
- 不重复创建 GameRuntime、DemoFlowManager、ContentRegistry、DialogueManager、第二业务状态机或第二 Godot root；
  当前职责以 `PROJECT_STATE.md` 和实际仓库为准。

玩法、美术、叙事、体验和范围由用户或负责设计审查的 ChatGPT 冻结。
实现中遇到未冻结的关键设计选择时停在可审阅方案，不自行扩展规格。

## Git 安全

- BUILD 使用当前 Issue 的独立分支和仓库外 worktree；默认分支名为 `dev/<issue-number>-<short-name>`。
- 创建 worktree 前核实 base commit、依赖历史、目标路径和现有工作区；无法安全隔离时停止报告。
- 保留用户未提交改动，不自动 stash，不为方便而 checkout/reset 覆盖，不在无关 checkout 直接开发。
- 允许在计划通过风险门后创建仅含当前 Issue 的本地 commit；显式逐文件暂存并审查 staged diff。
- 不自主 push、merge、force-push、删除远端分支或修改权限；不未经授权 reset/rebase 改写共享历史。
- 不提交 `.godot/`、导出产物、临时日志、缓存或编辑器备份。

## 风险门

| 等级 | 判断 | 行为 |
| --- | --- | --- |
| GREEN | 边界明确、局部、可逆且不影响结构或公共行为 | 给出具体计划后可直接 BUILD |
| AMBER | 场景关系、公共 API、UI 结构、Input/Camera/Interaction、运行时关系或工作流协议变化 | PLAN 写回 Issue，获得对应批准后 BUILD |
| RED | 大量删除/迁移、核心系统替换、权限或共享历史改写 | 人工主导，逐步明确授权 |

风险按实际影响判断，不按扩展名机械分类。批准必须对应计划版本、范围和约束；
已有有效批准不重复请求，范围或基线实质变化时重新过门。具体阶段路由由 Issue Runner 负责。

## 验证与交接

- 先运行受影响测试或最小复现；测试必须匹配实际改动。
- 正式 scene、runtime、public API、Input/Camera/Interaction、Manager、数据契约、资源加载或测试执行逻辑变化，
  在 REVIEW 前运行一次 [统一测试入口](tests/README.md)；Issue 可另行要求。
- 纯文档、注释、链接和不改变命令行为的说明默认不运行 Godot 全量测试。
- Circuit Breaker 的唯一详细规则在 Issue Runner；触发时停止变体尝试并报告，不循环重跑全量测试。
- Headless 通过不等于画面、焦点、字体、音频、手感或节奏验收；用户保留最终 Godot 体验验收。
- REVIEW 如实区分实现、自动测试、人工验收、commit、push/merge 和外部同步，列出文件、结果与限制。
- 默认停在 push/merge 前，由用户决定最终整合和发布。

## 开发日志与外部同步

开发日志和飞书操作遵循
[`the-shaft-devlog` skill](.agents/skills/the-shaft-devlog/SKILL.md) 与
[`docs/devlog/README.md`](docs/devlog/README.md)。
“整理开发日志”只生成本地草稿；只有用户明确说“同步开发日志”才允许写入已授权的飞书目标。
不得把 Token、Secret、Cookie 或登录信息写入仓库、日志或同步状态。
