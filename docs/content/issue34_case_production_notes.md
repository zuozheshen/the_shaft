# Issue 34 案例生产试跑记录

## 实际范围

本次试跑新增 `passenger_003`、`CASE_003` 和对应 Dialogue，把它们接入现有 Catalog、`DEMO_SHIFT_001`、翻译提取列表、ContentValidator 与三单流程测试。没有新增 Schema、楼层、摄像头系统、多轮对话或后果系统，也没有改写前两个案例。

实际新增文件：

- `data/passengers/passenger_003.tres`
- `data/dispatches/case_003.tres`
- `dialogues/passengers/passenger_003.dialogue`
- `dialogues/passengers/passenger_003.dialogue.import`（Godot 4.7 导入元数据）
- `tests/content/case_003_content_tests.gd`
- `tests/content/case_003_content_tests.gd.uid`（Godot 4.7 脚本 UID）
- `docs/content/case_authoring_checklist.md`
- `docs/content/issue34_case_production_notes.md`

实际修改文件：

- `data/catalogs/passenger_catalog.tres`
- `data/catalogs/dispatch_catalog.tres`
- `data/shifts/demo_shift_001.tres`
- `project.godot`
- `tests/run_flow_tests.gd`
- `tests/runtime/shift_runner_tests.gd`
- `tests/flow/demo_flow_manager_tests.gd`
- `tests/flow/flow_command_tests.gd`
- `tests/README.md`

## 最容易漏的字段和连接

- `pickup_data` 有七个固定 key，且不仅要求存在，还要求值为非空 String。
- `camera_feeds` 和 `front_phase_texts` 都要完整覆盖八个活动阶段；前者每阶段必须恰好两个画面，后者每阶段必须同时有 `state` 与 `task`。
- 每条 relation 的 `stability_preview` 容易在复制后保持默认空值；初始推荐与可推荐资格还必须成对有效。
- 默认目标、Dialogue 解锁目标和所有需要反馈的正式楼层，都必须同时具备楼层登记、relation 和对应 destination 标题。
- `004` 必须在资源、Dialogue、测试和运行时状态中始终作为字符串保留前导零。
- 新资源建完仍需分别登记到 PassengerCatalog、DispatchCatalog、ShiftDefinition 和翻译提取列表；这些连接分散在四处。

## 重复复制较多的步骤

- 七条 `DispatchFloorRelation` 子资源结构相同，只替换五个业务值。
- 八阶段 `camera_feeds` 重复阶段键和双画面骨架。
- 八阶段 `front_phase_texts` 重复阶段键及 `state` / `task` 骨架。
- 七个 `destination_<floor_id>` 重复标题、状态提示、乘客反馈和结束跳转骨架。
- Catalog、Shift、翻译列表与测试入口都是稳定但分散的登记步骤。

这些重复项适合生成结构，不适合自动生成叙事内容。

## 现有校验器和自动测试能发现的问题

ContentValidator 能发现：

- 空值、重复 ID、无效乘客/楼层/值班引用。
- `pickup_data` 缺 key 或值类型/内容无效。
- 摄像头阶段缺失、画面数量不是两个或文本为空。
- 前台阶段缺失、`state` / `task` 缺失、未知占位符。
- 默认目标缺 relation，relation 重复、范围错误、稳定性为空、推荐组合无效。
- Dialogue 文件不可读，`pickup_start`、`onboard_start`、默认/推荐 destination 缺失。
- `unlock_floor` 指向不存在的楼层、缺 relation 或不可推荐 relation。

本次新增的契约与流程测试还能发现：

- `passenger_003` / `CASE_003` 未登记、接乘层或默认目标错误。
- relation 数量错误、004 / 900 不可推荐、547 不是初始推荐。
- `004` 前导零丢失、Dialogue 文件或七个 destination 标题缺失/重复。
- 正式内容数量或值班顺序错误。
- CASE_002 完成后过早结束值班。
- CASE_003 继承上一单的验证楼层、选择目标、乘客状态、门外确认或到站反馈状态。
- 第三单完成结果数量不为 3，或 `shift_completed` 重复触发。

## 只能通过手动游玩确认的问题

- 对话按钮在正式 Dialogue Manager UI 中的可读性、顺序、焦点和实际触发手感。
- 不进行门外通话时，正式 3D 操作台是否仍允许直接开门接乘。
- 询问不同问题后，004 与 900 的推荐按钮是否在界面上以预期时机出现。
- 八个阶段的摄像头文字虽然结构合法，是否在实际操作节奏中产生位置矛盾或提前泄露信息。
- 七个 destination 反馈在正式界面上的显示、结束时机和玩家理解。
- 连续完成三单时的节奏、状态提示和最终无第四单的可见表现。

自动流程测试模拟了三单闭环，但本次未把它冒充为正式 3D 场景的用户验收。

## 试跑中实际发现的边界

第三单刚建立且乘客尚未登舱时，`DemoFlowManager.get_current_recommended_destinations()` 按既有 UI 规则返回接乘层 387；底层 `DispatchLifecycle` 的路线初始推荐仍正确地只有 547。测试因此改为直接检查运行时路线推荐状态，没有为了满足测试而修改既有 UI 或模板语义。

CASE_003 的摄像头文案通过逐阶段避免人物瞬移、提前出现和多目标并列来减少物理矛盾，但这只是案例内容约束，不代表摄像头上下文问题已经系统性解决。

## 是否建议制作案例脚手架生成器

建议下一步只制作一个小型、可预览的案例骨架生成器，原因是本次最耗重复劳动且最易漏的是固定结构：七个 relation、两个八阶段字典、Dialogue 标题集合及四处登记。生成器不应尝试写叙事、推断推荐值或扩展 Schema。

建议生成器最多生成：

- 一个只含既有字段的 PassengerDefinition 骨架。
- 一个含所选正式楼层 relation、七个 `pickup_data` key、八阶段 camera/front 空骨架的 DispatchDefinition。
- 含 `pickup_start`、`onboard_start` 和已选楼层 `destination_<floor_id>` 的 Dialogue 骨架。
- 一份待人工确认的 Catalog / Shift / 翻译登记清单或补丁预览。

不建议让生成器直接覆盖 Catalog、Shift 或 `project.godot`，也不建议生成正式台词、摄像头证据和路线后果。所有输出仍必须经过 ContentValidator、自动测试和手动游玩。
