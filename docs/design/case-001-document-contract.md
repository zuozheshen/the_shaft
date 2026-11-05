# Case 001 Preparation：共享资料契约

实现依据 [Issue #91 PLAN v2](https://github.com/zuozheshen/the_shaft/issues/91#issuecomment-6659341776)，
基线 `3165afb1cb4467dfd76c03b983dea2f763fdcf8e`。本契约服务后续资料查询、W 工作区、索证与质疑接线；
本轮不制作正式剧情、W/查询 UI、转录按钮、规则引擎或自动推理。

## main 现状与旧方案审计

基线的正式入口是 `scenes/main/main_3d.tscn`，仅 318、001、002 三层，Passenger/Dispatch/Shift Catalog 为空。
正式 `dialogue_enabled = false`，不创建 Adapter/COMM；无剧情夹具单独启用保留的对白框架。
GameRuntime 中的唯一 DemoFlowManager 协调 ElevatorRuntimeState、DispatchLifecycle、ShiftRunner、UIHistoryState。
FloorDefinition 仅有 floor_id/display_name；PassengerDefinition.archive_text 是纯文本；
UIHistoryState 的转录/日志只保存最近 20 行，不是可比字段库或完整材料库。

旧 #84–#90 均以 `not_planned` 关闭且无评论。审计了基线相关实现、测试、本地 refs/相关提交关键词与 GitHub 分支清单，
未发现旧调查 API/测试或对应命名实现分支；不由关闭状态或未检查的不可达历史推定功能已经存在。

| 旧 Issue / 内部编号 | 可复用 | 缺失、冲突与迁移决定 |
| --- | --- | --- |
| [#84 / 40](https://github.com/zuozheshen/the_shaft/issues/84) | Registry、ActiveDispatchState、DispatchLifecycle、Manager 生命周期 | 没有 InvestigationState 或 add_evidence/confirm_fact/add_topic/add_claim/reset_for_case。保留稳定 ID/来源/隔离原则，不恢复 Evidence→Fact→Topic→Claim。 |
| [#85 / 41](https://github.com/zuozheshen/the_shaft/issues/85) | BuildingTerminalInterface 三栏、日志/档案/转录 getter 与更新信号 | 没有 QUERY/MARK。旧左台调查工作台与新职责冲突；保留阅读功能，后续左台主动查人/查当班记录。 |
| [#86 / 42](https://github.com/zuozheshen/the_shaft/issues/86) | 无旧 Compare/Claim 实现 | 改为已有内容引用与正式质疑记录；不实现自动判矛盾/正确 Claim。缺件不进双槽。 |
| [#87 / 43](https://github.com/zuozheshen/the_shaft/issues/87) | Adapter.start_dialogue/choose_response/show_title、既有信号 | 没有 Topic Query/NORMAL/GUARDED；继续唯一 Dialogue Manager，本轮不修改 Adapter/ConsoleInterface。 |
| [#88 / 44](https://github.com/zuozheshen/the_shaft/issues/88) | CAM 选择、唯一监控链和门/乘客表现 | 没有 INSPECT/MARK/hotspot；不接旧视觉 Evidence→QUERY 链。 |
| [#89 / 45](https://github.com/zuozheshen/the_shaft/issues/89) | 原开关门 request 与时序 | 无旧提案的正常派单自动门控。本轮维持原门控。 |
| [#90 / 46](https://github.com/zuozheshen/the_shaft/issues/90) | 无剧情三单 runtime 夹具 | 没有旧 Vertical Slice。旧正式三单已移除；以空舱和框架夹具回归，不制作替代剧情。 |

无上述旧调查代码需要删除；基础框架保留，不做清理式迁移。

## 定义与快照

三个 Resource 定义位于 `scripts/data/definitions/document_*_definition.gd`。

| 类型 | 字段与含义 |
| --- | --- |
| DocumentDefinition | document_id、正整数 version、owner_type/owner_id、material_type、title/original_text、source、fields。版本只在文档身份内递增。 |
| DocumentFieldDefinition | 文档内稳定 field_id、subject_type/subject_id、comparison_key、display_value、value_type、has_value、comparable_value、可选 source。 |
| DocumentSourceDefinition | source_id、kind、origin_ref、source_version、updated_at。updated_at 未知可留空，不用取得时间冒充原始更新时间。 |
| 规程条款元数据 | 可选 requirement_key/required_material_type/applicability_key；三者一起填写，仅系统参考条款允许。样板不填这些字段。 |

对象类型为 passenger/floor/dispatch/system；前三类 ID 引用现有 Registry，不另建身份/路线数据库。
`value_type` 为 string/floor_id/bool/int/float。Godot Resource 为存储不同标量使用单元素 Array：
例如 `comparable_value = [false]`；运行时快照解包为 bool 标量。缺值必须 `has_value = false` 且 Array 为空；
有值的 false、0、空字符串有效。floor_id 的值必须是字符串，001 不转整数。
字段默认继承 Document.source，可显式覆盖以保留原始出处；覆盖后的出处与文档出处不同时，
必须填写 source_note，说明引用或转述关系。相同出处的显式覆盖无需重复说明。
覆盖只改变字段出处展示，不改变包含它的 Document 身份、取得渠道、权限或核实程度；
例如乘客文件引用 duty_record，仍是乘客上传的引述，不是独立取得的系统当班记录。

`DocumentRef = {document_id, version}`；`FieldRef = {document_id, version, field_id}`。
所有查询/写入另带当前 session_id，不使用显示文本或列表位置作键。
文档/字段快照只含值；Resource、getter 返回值或适用性回调参数的后续修改不会改写已取得快照。
get_acquired_field 还返回完整 ref、有效出处 source、source_note 和 acquired_at；版本在 ref 中。
另有 acquisition = {document_ref, route, document_source}，明确该字段属于哪份已取得文档、
从哪个渠道取得及该文档的来源。渠道/资料类别判断使用 acquisition，不能把字段 source.kind 当成取得身份。
引用当班记录不会生成/解锁当班原件；原件仍须由左台另行查询取得。

取得记录是 `{document, session_id, acquired_at, sequence, route, event_id, change_kind}`。
首次取得 change_kind=received；已有版本之后的新版本为 updated，首次收到 v2 也仍是 received。
未提交材料没有虚拟 Document/Field，没有 W 缺件清单；内部选定规程后才检查实际收件。
**来源记载/乘客陈述不等于已核实事实**，取得、阅读、转录或提出质疑均不确认真伪、不改变推荐路线。

## 来源与取得边界

DispatchDefinition.documents 默认空，只装配定义，不表示玩家取得或材料齐全。
共享规程可引用同一 Resource；要求来自通用规程条款及其 applicability_key，不使用 Case 001 预设缺件 ID。

| 来源 kind | 取得入口/权限 |
| --- | --- |
| passenger_upload | receive_passenger_batch 整批成功后直接进入 W 收件箱。 |
| system_reference | W 可列出规程/样板的引用和标题，open_system_reference 固定所读版本；不算乘客收件。 |
| personnel_record / duty_record | 仅 accept_left_lookup_result，代表左台主动查询完成。 |
| floor_archive | 仅 accept_right_lookup_result，代表右台主动查询/调阅完成。 |
| call_excerpt | 保留类型和内部 main 路由的契约测试；本轮无 Manager 转录入口、按钮或对白桥接。 |

Manager.get_document_workspace_port 返回仅含 W 读取、系统参考打开和审查命令的 Callable 字典。
后续 W 只注入此端口，不传完整 Manager/Registry，不把左右台完成入口、上传或判断器配置交给 W。
左右台端口是应用层主动查询完成回调；本轮夹具模拟，真实查询交互后续接线，不能声称已做 UI 权限体验验收。
端口用于明确游戏内部职责，不是针对任意 GDScript 代码的沙箱。

Registry.get_document_definition 只解析当前派单声明或现有身份视图，不改变取得状态。
保留 `registry/passenger/<id>`、`registry/floor/<id>`：分别只读适配既有档案原文/名称和楼层编号/名称。
视图 Document.version=1 是当前适配视图版本，source_version=legacy-unversioned、更新时间未知留空；
不伪造旧数据的修订历史。档案原文不解析成事实，楼层不补写不存在的丰富资料，未经对应台位取得不能在 W 调阅。
authored documents 禁用 registry/ 前缀，运行时也不让此类声明覆盖原身份视图。

## 原子收件与版本

唯一 DispatchDocumentState 是 ActiveDispatchState 的 RefCounted 成员；没有额外 Node/Autoload。
DemoFlowManager 提供 receive_passenger_batch、open_system_reference、accept_left_lookup_result、accept_right_lookup_result。
这些命令均校验 session、完整引用、Registry 对象、来源路由和内容契约。

整批先在局部构造候选快照，检查全部版本/来源/冲突后再提交；内部无 await 或逐文件信号。
成功后一次更新所有快照和最新索引，再发 documents_changed(session)。
正式索证和质疑还有初始提交门：在本单至少一次乘客提交成功之前返回 INITIAL_SUBMISSION_REQUIRED，
不调用适用性依赖、不记录正式审查行为；系统资料取得/查询结果不满足该前置条件。
允许首个上传批次为空：仍原子记录 passenger 完成事件（document_refs=[]），再通知订阅者；
此时可正式审查，但不表示材料齐全。后续相同空批重试或无新文件的空提交保持幂等，不重发完成通知。
完成依据直接取自本单提交事件，不引入接收中状态、上传步骤或第二份完成标记。
非空提交失败不完成此门；换单/同 ID 重开/clear/结单/结束值班清除事件，门随之重置。
任一项错误则无部分收件/事件/通知；不设置“接收中”、进度条、结束确认或“材料齐全”状态。

事件 ID 在每个取得渠道内幂等：同 ID 同载荷（忽略批内顺序）重放无变化，同 ID 异载荷 EVENT_CONFLICT。
新事件重复同文档/版本也不增加业务事件；同版本异内容 VERSION_CONFLICT，倒退提交 STALE_VERSION。
左右台 query_id 是**一次主动查询的唯一完成事件 ID**，不是查询关键词、人物名、楼层号或固定文档 ID。
同关键词重新查询、主动刷新、新版本取得均分配新 query_id；同一次完成回调的重试才复用原 ID 与原版本载荷。
例如应用层对每次新查询增加 session 内序号，使用 left:<session>:<sequence> / right:<session>:<sequence>，
并把该 ID 随查询结果保存到回调中。新 ID + 同版本为成功无变化；新 ID + v2 为合法更新；
旧 ID 携带新版本仍为 EVENT_CONFLICT，避免把新的刷新冒充旧回调。延迟的原 v1 回调重试保持幂等，不回退 v2。
query_id 的生成属于查询调用方约定；本轮不新增 UI、查询服务或 ID 分配系统。
批内同文档重复声明拒绝；文档 ID 对应的所属对象、材料类型和来源身份不能借升级更换。
保留旧版本；新版本只更新最新索引。读取旧版本与重交旧版本不同：旧版本仍可引用，不能回退当前资料。
get_received_materials 只列最新的乘客实收文件；get_acquired_documents 列最新已取得资料；
get_acquired_document/get_acquired_field 按精确版本读，get_document_events 返回取得历史。

## 两类正式行为

命令结果沿用 FlowCommandResult；资料命令不添加门控/路线 effects。

### 单条规程索证

`request_material(session_id, request_id, clause_ref)` 要求初始提交已完成，且只接受已取得的完整规程条款。
判断器通过应用层 set_document_applicability_resolver(Callable) 注入，不在 W 端口中。
输入为条款快照副本和 `{session_id, dispatch_id, passenger_id, floor_id}`；
同步返回 APPLICABLE / NOT_APPLICABLE / UNRESOLVED。
没有判断器、未知条件或其他返回类型均 RULE_UNRESOLVED；不默认适用，不记录正式索证。
本轮只有测试判断器，正式规程条件与完整判断实现后续处理。

规程本身可属于 system，不写死某个乘客。#91 索取目标绑定当前派单乘客；
适用后按 required_material_type + 当前乘客 ID 检查真实 passenger 路由收件。
样板、人员/楼层系统记录或别人的文件不算乘客已经提交；已收到也不等于内容合格。
已收返回 ALREADY_PROVIDED，中性反馈；未收才新增材料请求并发 material_requested(session)。
同 requirement_key + 目标对象重复请求返回 REQUEST_ALREADY_RECORDED，不重复触发乘客补件。
请求日志保留 request_id、requirement_key、clause_ref、target_subject、required_material_type、created_at。
补件是新的原子收件事件，不删除/重发历史索证；后续再请求已交材料返回 ALREADY_PROVIDED。
get_material_requests 只返回副本。没有自动补交、自动展示缺件答案或正式乘客回应。

### 双槽内容质疑

`record_contradiction_challenge(session_id, challenge_id, a_ref, b_ref)` 要求初始提交已完成，两端均为已取得、有值字段，
且不在同一份相同版本资料中；可以跨文档/来源/版本。不存在或未取得的资料、缺值、虚拟缺件字段均拒绝。
仅记录 `{challenge_id, a_ref, b_ref, created_at}`，不运行比较器、不确认矛盾成立、不生成 Fact/Claim/正确答案。
同 ID 同引用幂等，异引用 EVENT_CONFLICT；get_contradiction_challenges 返回深副本。
历史引用固定版本，不随之后的补交/更新漂移。

## 会话与持久化

| 状态 | 同单隐藏/重开 W | 换单、同 ID 重开派单、clear、结单/结束值班 |
| --- | --- | --- |
| 已取得资料/版本、提交/取得事件、正式索证/质疑 | 保留 | 清空并撤销旧 session；迟到命令/读取拒绝 |
| 当前 A/B、打开窗口、坐标/层级/滚动/焦点 | 后续 W 工作区自己保留引用/UI 会话 | 工作区订阅 document_session_changed 清理；业务层不存这些值 |
| 静态内容定义/共享规程、既有值班结算 | 沿用既有职责 | 定义继续可用，结算由 ShiftRunner 管理；不增加跨单材料库/存档 |

资料状态 close 会销毁自身内容和 session，即使其他内部代码还持有旧状态对象也无法继续读取本单资料。
Manager 写命令在同步适用性回调期间拒绝资料命令重入，回调返回后重查 session；通知仅在提交完成后发出。
正式场景、输入、对白适配器、左右台 UI 和 Catalog 正式内容没有接入本轮的新接口。

## 验证与后续限制

定向测试见 tests/README.md：原子成功/整批失败、无虚拟缺件、来源渠道、通用规程接入口、
已有/不适用/未知条件、索证幂等与补件、跨来源质疑、版本/副本/前导零、迟到事件和生命周期。
独立审查回归另覆盖：初始提交前审查拒绝、首个空批提交/通知/重试、失败上传不完成、
跨出处引用说明和取得上下文分离、原当班记录未解锁，以及左右台唯一 query_id 下重复查询/v2刷新/延迟重试。
统一入口继续覆盖正式空舱、门控/乘客、三台、手柄和正常关闭 smoke。
测试适用性注入不是正式规则引擎；查询完成回调测试不代表已经制作真实查询 UI。
Headless 通过不代替 Godot AI 视觉或用户人工验收。正式玩法接线仍需后续 Issue。
