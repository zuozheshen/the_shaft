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
- REVIEW 仍停在 push/merge 前；整合、删除 worktree 和删除本地分支是独立动作。只有用户授权整合且成功、
  `main` 已包含目标 commit、目标外部 worktree 归属明确且 clean 后，才安全移除 worktree 和已合并的本地分支；删除远端分支须另行明确授权。
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

## Godot AI 视觉验证

- `addons/godot_ai/` 是固定版本的项目开发基础设施；普通 Issue 不删除、替换、降级或顺手更新它，也不提交用户级 Codex 配置、认证 capability、`.godot/`、截图或日志。
- 3D、UI、Camera、Interaction、布局、字体与可读性等视觉 BUILD 开始前，默认只保留当前 Issue worktree 对应的一个活动 Godot Editor，再按 [`docs/development/godot-ai.md`](docs/development/godot-ai.md) 执行 preflight。Godot AI 报告的 project path 或 live session 身份与 worktree 不一致时立即停止，不等待多实例歧义实际发生。
- 视觉修改采用“小步修改 → 真实正式场景 → 截图 / runtime Scene Tree / 属性 / 日志 → 对照冻结要求”的循环。纯视觉调整不反复跑全量测试；逻辑变化仍先跑受影响测试，REVIEW 前的统一测试规则不变。
- REVIEW 分开记录自动逻辑验证、Godot AI 视觉/运行时自检和用户人工体验验收；任何一项不得冒充另一项。

## Blender MCP 与 3D 资产工作流

Blender MCP 是项目允许使用的本地 3D 制作工具，但它只负责执行已经冻结的设计，
不得自行扩大玩法、美术方向或资产范围。

### 设计与执行边界

- 玩法、美术语言、操作台功能、空间比例与最终体验由用户或负责设计审查的 ChatGPT 冻结。
- Codex 在 Blender 中负责实现、检查、迭代和导出，不自行决定关键设计。
- 遇到未冻结的造型、布局、功能或风格选择时，先给出可审阅方案，不自行扩展。
- 正式资产修改默认采用：
  `检查现状 → 描述计划 → 用户/Issue 批准 → 小步修改 → Blender 自检 → Godot 实机验证`。

### Blender 会话确认

开始任何 Blender BUILD 前先确认：

- Blender MCP 已连接。
- 当前打开的 `.blend` 文件或未保存场景是否确实属于本次任务。
- 当前 Scene、目标 Collection 和目标对象与计划一致。
- 当前场景是否存在未保存的用户修改。
- 本次任务是否允许保存 `.blend`、导出资产或覆盖已有文件。

发现 Blender 文件、项目 worktree、Issue 或目标对象身份不一致时立即停止，不猜测。

### Blender 风险门

GREEN：

- 在独立 Collection 中创建新的简单对象。
- 新增按钮、灯、螺丝、边框、小型道具等局部可逆资产。
- 调整明确指定的新建对象的尺寸、位置、材质参数。
- 只读检查 Scene、Mesh、Material、Camera、Light 和 Transform。

GREEN 修改仍需先说明具体计划，但计划明确后可以直接执行。

AMBER：

- 修改已有正式 Mesh、Material、UV、Modifier、Origin 或层级。
- 修改操作台、舱体、门、Camera、Light 或已有导出对象。
- Apply Transform / Modifier。
- 保存或覆盖正式 `.blend`。
- 导出 `.glb/.gltf` 并接入 Godot。
- 改变 Blender → Godot 的坐标、命名、层级或导出规则。

AMBER 必须先给出：

1. 将修改的已有对象；
2. 将创建的新对象；
3. 将保留不动的对象；
4. 是否保存或导出；
5. 回滚方式。

获得对应批准后再 BUILD。

RED：

- 大量删除已有对象。
- 重建整个电梯舱或核心操作台。
- 批量应用不可逆 Modifier。
- 改变整个资产坐标系、根层级或导出体系。
- 覆盖唯一正式源资产。
- 批量替换 Godot 中已有正式模型。

RED 由人工主导，逐步明确授权，不一次性自动执行。

### 非破坏性修改原则

- 已有正式对象默认保留，优先：
  `duplicate → modify → compare → replace`
  而不是：
  `delete → rebuild`。
- 新的实验对象优先放入清晰命名的独立 Collection，例如 `AgentGenerated_*`。
- 未经批准不删除用户已有对象、Collection、Camera、Light、Material 或 Modifier。
- 未经批准不调用 Save / Save As 覆盖正式 Blender 源文件。
- 不因为“整理场景”而顺手重命名、合并、Apply 或删除无关内容。

### Blender 自动验证

每次 Blender BUILD 完成后必须重新读取场景并检查至少：

- Object 名称；
- Collection 归属；
- Location / Rotation / Scale；
- Origin；
- Mesh normals；
- Material slots；
- Modifier；
- 重复对象；
- 隐藏对象；
- 导出对象范围。

自动检查通过不等于美术验收。
比例、轮廓、工业设计语言、材质质感和构图由用户最终判断。

### Blender → Godot

Blender 中看起来正确不等于游戏中正确。

正式 3D 资产必须经过：

`Blender 验证 → 导出 → Godot 导入 → 正式场景 → 实际玩家视角验证`

导出前必须确认：

- 目标 Godot 资产路径；
- 导出对象范围；
- 是否需要 Camera / Light；
- Transform 与 Origin；
- 材质命名；
- 是否会覆盖已有资产。

不要因为 Blender 修改完成就直接覆盖 Godot 正式资产。

Godot 中继续遵循现有 Godot AI 视觉验证规则。
Shader、FOV、摄像机距离、像素化、灯光和运行时交互均属于最终验收的一部分。

### Git 与二进制资产

- 不因为 Blender MCP 可用就自动把 `.blend`、`.glb` 或大型贴图加入 Git。
- 新增二进制资产目录、Git LFS 或新的资产管理规则属于独立设计决定。
- 若 Issue 要求提交二进制资产，先确认文件用途、来源、大小和跟踪方式。
- 不提交 Blender 临时文件、自动备份、缓存和测试导出物。

## 开发日志与外部同步

开发日志和飞书操作遵循
[`the-shaft-devlog` skill](.agents/skills/the-shaft-devlog/SKILL.md) 与
[`docs/devlog/README.md`](docs/devlog/README.md)。
“整理开发日志”只生成本地草稿；只有用户明确说“同步开发日志”才允许写入已授权的飞书目标。
不得把 Token、Secret、Cookie 或登录信息写入仓库、日志或同步状态。
