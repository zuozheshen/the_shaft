# Blender → Godot 视觉资产边界

正式入口仍为 `scenes/main/main_3d.tscn`。玩家始终在固定操作舱工作；更换美术不改变路线、输入、UI 或业务状态。

## 源文件与运行资产

- 主操作台 V2 的正式源文件为 `art_source/main_console_v2.blend`，与运行资产一起沿用仓库现有 Git LFS 规则跟踪；`art_source/.gdignore` 阻止 Godot 自动导入 .blend，局部 `.gitignore` 排除 Blender 备份。源文件与 GLB 的用途、来源、大小和 SHA-256 记录在对应 Issue REVIEW；新增其他资产或改变跟踪规则仍需对应方案，不将临时项目外探针目录作为正式源位置。
- 临时管线探针可使用项目外的 Blender 测试源文件，不提交；不保存或覆盖用户已有正式源文件。
- 运行资产使用 `assets/art/models/<asset>.glb`，小写 snake_case，例如 `main_console_shell.glb`。只有具体正式资产 Issue 批准后才添加二进制文件。
- 本地导入探针使用 `assets/art/models/_pipeline_probe/`。该目录及其 `.import` sidecar 不提交；截图、日志、`.godot/`、Blender 备份和测试导出同样不提交。

## Godot 拥有稳定的节点

现有主、左、右“操作台定位”是稳定的台位根。保留当前 Transform 和 Gameplay 路径，只有存在实际耦合时才迁移，不要求所有物件拥有相同的中间层级。

- 台体、背板和边框可放在台位根的“视觉资产”子树。
- 热点 `Area3D`、`CollisionShape3D`、action_id、Label3D、SubViewport、动态屏面与指示灯是 Godot 自有节点，留在可替换模型之外。
- MIC/OPEN/CLOSE 的现有视觉子树及 CAM 的“视觉”仅负责外形；“交互反馈”独立负责悬停/选中反馈。不能把它们重新放入 GLB 内。
- 左台“滚轮转轴”由 Godot 驱动；其“视觉资产”装滚轮外形，碰撞不随滚动旋转。
- 右台拨杆轴保留 Godot 所有，其“视觉资产”装杆柄；执行热点、busy 和业务提交不依赖杆柄内部结构。
- 信息屏底面、LCD 底面、文字、书的动态页面继续由 Godot 管理。Blender 提供外壳、边框、玻璃等静态外形。
- 已有楼层书移动根、封面/翻页轴、视口和热点，以及摄影棚门的动画根与 Mesh 子节点边界保持原职责。不为层级统一重建这些组件，也不移动舱壁/地板或重做灯光。

允许表现脚本更新自己负责的 Godot 动态 Mesh/Label；禁止业务脚本读取可替换 GLB 内部的节点名称、层级或材质槽来决定行为。

## 替换与重导入

1. 保留 Godot 台位、热点、动画轴与动态显示节点。只在对应视觉挂载下替换外形子节点；不能替换包含 Gameplay 的台位根。
2. 当前灰盒可直接留在挂载下。需要可复用 wrapper 时使用 `scenes/visuals/<asset>_visual.tscn`，新增 Godot 节点使用中文；不复制业务控制器或另建完整舱体。
3. Blender 使用米制尺寸，静态台体相对台位本地原点制作，滚轮/拨杆等组件相对 Godot 稳定轴制作。保留当前台位缩放；先核对世界尺寸再导出。
4. 使用标准 glTF 导出坐标转换；不额外添加未经核实的 90° 补偿，不修改项目坐标体系。不得顺手 Apply 用户已有正式对象的 Transform/Modifier。
5. 仅导出批准的对象，默认不导出 Camera/Light。不得使用触发碰撞生成的命名后缀或把业务 metadata 放入模型；需要真实碰撞时在 Godot 单独维护。
6. 重导出到同一 GLB 路径并触发 Godot import。内部对象名、数量和层级可改变，现有 Gameplay NodePath 不应需要重新绑定。
7. 在正式 `main_3d` 的实际玩家视角验证，不以 Blender 视口或 headless 退出码替代视觉验收。

## 临时探针与验收

先核实 Blender MCP、当前 `.blend`、Scene、Collection、未保存修改、导出范围和路径。只新增本任务的 `AgentGenerated_ART01_PipelineProbe` Collection；默认不修改、删除或保存已有用户对象。

验证两轮：导出简单外壳 → Godot import → 临时替换主台外壳 → 正式场景运行；修改探针尺寸/内部名称 → 覆盖同一个临时 GLB → reimport → 再运行。每轮检查热点射线、MIC/CAM/OPEN/CLOSE、监控纹理与状态条、左右台、书和手柄动作，以及脚本/viewport/动画轴身份和路径。

验证结束恢复原灰盒，并清理仅本次生成的临时接线/导出。只有确认测试 Collection 归本任务且没有用户追加修改时才清理它。正式资产的保存、导出、覆盖和二进制提交需要其对应 Issue 的批准范围。

REVIEW 分别记录自动逻辑检查、Godot AI 视觉/运行时自检和用户体验验收；任何一项不能冒充另一项。

## 主操作台 V2 Blockout（#62）

- 源 Scene 为“主操作台体块”，模型范围为 `AgentGenerated_ART02_1_Blockout`；使用米制单位、主台局部原点与标准 glTF Y-up 转换。只导出外壳模型，不导出 Camera、Light、碰撞、动态屏面或业务 metadata。
- `main_console_shell.glb` 包含机身、CRT/CASE 外壳及 COMM/CAMERA/DOOR 板壳；通过 `scenes/visuals/main_console_shell_visual.tscn` 接入既有主台“视觉资产”。所有 Gameplay、热点、反馈、CASE Label3D 和监控纹理链保持 Godot 所有。
- #62 PLAN v3 将 CRT 物理开口等比缩小 10% 为 1.44×1.08 米（4:3），中心在主台局部 (0, 1.86, -1.535)。本阶段保留 640×360 feed；原主监视器节点 Transform 不变，仅 QuadMesh 使用 1.44×0.81 米与 `center_offset=(0, 0.16913, 0)`，将完整 16:9 内容居中显示，深灰占位衬底预留上下空间。#65 可在同一节点扩展为 1.44×1.08 米动态屏面，并替换临时衬底。
- 主台控件斜面为 55°（相对水平），下端约 Y=0.823 米；前方接约 15 厘米水平托台和 4.5 厘米厚前沿。既有控件、反馈与五个热点同步校准姿态，CASE 中心抬至 Y=1.23 米；节点名、NodePath、action_id 与纹理/业务接线保留。当前台位整体位置、玩家与 FOV 不变。
- 当前仅有中性灰 Blockout 材质，无 UV、贴图、按钮/麦克风精模、CRT shader 或 CASE 最终材质。后续 Controls / Material / Screen 阶段沿用源文件，但各自按对应 Issue 审批。
- #62 审批允许 Codex 新建该专用文件，并只保存自身生成的修改；写前仍核对 filepath、Scene、Collection、对象与用户未保存修改。禁止覆盖身份不明的源文件、将用户已有场景 Save As 到正式源路径，或对用户文件 Revert。
