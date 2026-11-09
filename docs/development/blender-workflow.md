# Blender MCP 与 3D 资产工作流

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

## 按需关联文档

本页承接根目录 AGENTS.md 的 Blender 专项规则；使用 Blender MCP 或修改、保存、导出 3D 资产前必须读取。
涉及 Blender → Godot 接入时，再读 [资产边界与现有资产约定](blender-godot-assets.md) 的相关章节；
Godot 视觉 BUILD / REVIEW 前按 [Godot AI 开发管线](godot-ai.md) 执行 preflight 与正式场景验证。
