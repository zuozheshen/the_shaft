extends RefCounted
const Fixture := preload("res://tests/fixtures/runtime/test_documents.gd")
const TestContent := preload("res://tests/fixtures/runtime/test_content.gd")

func run(t: Variant, tree: SceneTree) -> void:
	var definition: DispatchDefinition = ContentRegistry.get_dispatch("TEST_CASE_001")
	var saved: Array[DocumentDefinition] = definition.documents
	definition.documents = Fixture.definitions()
	await _test_initial_submission(t, tree)
	await _test_source_override(t, tree, definition)
	await _test_lookup_refresh(t, tree, definition)
	var manager := DemoFlowManager.new()
	tree.root.add_child(manager)
	manager.start_dispatch(&"TEST_CASE_001")
	var session: int = manager.get_document_session_id()
	var port: Dictionary = manager.get_document_workspace_port()
	for forbidden: String in ["accept_left_lookup_result", "accept_right_lookup_result", "receive_passenger_batch", "set_document_applicability_resolver", "get_document_definition"]:
		t.assert_false("W 端口 / 不暴露 " + forbidden, port.has(forbidden))
	t.assert_equal("取得边界 / 内容定义不会进入 W", 0, manager.get_acquired_documents(session).size())
	t.assert_true("取得边界 / 未读规程不能索证", not manager.request_material(session, &"unread", Fixture.ref("rules", 1, "applicable")).succeeded)
	t.assert_equal("取得边界 / 只列系统参考", 2, manager.get_system_references(session).size())
	t.assert_equal("取得边界 / 列参考不自动取得", 0, manager.get_acquired_documents(session).size())
	for id: String in ["personnel", "work", "floor", "registry/passenger/TEST_PERSON_001", "registry/floor/001"]:
		t.assert_true("取得边界 / Registry 可解析 " + id, ContentRegistry.get_document_definition("TEST_CASE_001", Fixture.ref(id)) != null)
		t.assert_true("取得边界 / W 未取得 " + id, manager.get_acquired_document(session, Fixture.ref(id)).is_empty())
		t.assert_false("取得边界 / W 参考入口不能绕路 " + id, manager.open_system_reference(session, Fixture.ref(id)).succeeded)
		t.assert_false("取得边界 / 上传不能导入 " + id, manager.receive_passenger_batch(session, StringName(id), [Fixture.ref(id)]).succeeded)
	t.assert_false("取得边界 / 右台不能取得人员资料", manager.accept_right_lookup_result(session, &"wrong_right", [Fixture.ref("personnel")]).succeeded)
	t.assert_false("取得边界 / 左台不能取得楼层资料", manager.accept_left_lookup_result(session, &"wrong_left", [Fixture.ref("floor")]).succeeded)
	t.assert_true("取得边界 / 主动左台结果", manager.accept_left_lookup_result(session, &"left", [Fixture.ref("personnel"), Fixture.ref("work"), Fixture.ref("registry/passenger/TEST_PERSON_001")]).succeeded)
	t.assert_true("取得边界 / 主动右台结果", manager.accept_right_lookup_result(session, &"right", [Fixture.ref("floor"), Fixture.ref("registry/floor/001")]).succeeded)
	t.assert_equal("取得边界 / 真实楼层编号前导零", "001", manager.get_acquired_field(session, Fixture.ref("registry/floor/001", 1, "floor_id")).comparable_value)
	t.assert_equal("取得边界 / 人员原文不解析为事实", "TEST ARCHIVE {dispatch}", manager.get_acquired_document(session, Fixture.ref("registry/passenger/TEST_PERSON_001")).document.original_text)
	var event_count: int = manager.get_document_events(session).size()
	port.get_acquired_document.call(session, Fixture.ref("floor"))
	port.get_acquired_document.call(session, Fixture.ref("floor"))
	t.assert_equal("取得边界 / 反复打开不重复查询事件", event_count, manager.get_document_events(session).size())
	t.assert_true("规则 / W 可打开通用规程", manager.open_system_reference(session, Fixture.ref("rules")).succeeded)
	t.assert_true("规则 / 样板可查", manager.open_system_reference(session, Fixture.ref("sample")).succeeded)
	t.assert_equal("规则 / 系统资料不是乘客收件", 0, manager.get_received_materials(session).size())
	var clause: Dictionary = Fixture.ref("rules", 1, "applicable")
	manager.receive_passenger_batch(session, &"initial-empty", [])
	t.assert_equal("规则 / 无正式判断器不默认适用", &"RULE_UNRESOLVED", manager.request_material(session, &"no_resolver", clause).code)
	manager.set_document_applicability_resolver(Fixture.applicability)
	t.assert_equal("规则 / 不适用条款不索证", &"RULE_NOT_APPLICABLE", manager.request_material(session, &"not_applicable", Fixture.ref("rules", 1, "not_applicable")).code)
	t.assert_equal("规则 / 未知条件不索证", &"RULE_UNRESOLVED", manager.request_material(session, &"unknown", Fixture.ref("rules", 1, "unknown")).code)
	t.assert_equal("规则 / 样板不能当条款", &"INVALID_CLAUSE", manager.request_material(session, &"sample", Fixture.ref("sample", 1, "destination")).code)
	t.assert_equal("规则 / 不合法请求无行为记录", 0, manager.get_material_requests(session).size())
	var observations: Array[int] = []
	var requested: Array[int] = []
	manager.documents_changed.connect(func(current: int) -> void:
		observations.append(manager.get_received_materials(current).size()))
	manager.material_requested.connect(func(current: int) -> void: requested.append(current))
	var refs: Array = [Fixture.ref("identity"), Fixture.ref("second")]
	t.assert_true("上传 / 一次上传两份文件", manager.receive_passenger_batch(session, &"upload", refs).succeeded)
	t.assert_equal("上传 / 通知只看到完整批次", [2], observations)
	t.assert_equal("上传 / W 没有自动缺件资料", 2, manager.get_received_materials(session).size())
	t.assert_true("上传 / 未上传 permit 无字段", manager.get_acquired_field(session, Fixture.ref("permit", 1, "destination")).is_empty())
	t.assert_true("上传 / 重试成功", manager.receive_passenger_batch(session, &"upload", refs).succeeded)
	t.assert_equal("上传 / 重试不发通知", [2], observations)
	t.assert_false("上传 / 混合不存在资料整批失败", manager.receive_passenger_batch(session, &"bad_batch", [Fixture.ref("permit"), Fixture.ref("unknown")]).succeeded)
	t.assert_true("上传 / 无半份补交", manager.get_acquired_document(session, Fixture.ref("permit")).is_empty())
	manager.receive_passenger_batch(session, &"other", [Fixture.ref("other_permit")])
	var recommendations: Array = manager.get_current_recommended_destinations()
	t.assert_equal("索证 / 适用规程请求缺少材料，样板/别人文件不算", &"MATERIAL_REQUESTED", manager.request_material(session, &"request", clause).code)
	t.assert_equal("索证 / 不自动补件", 3, manager.get_received_materials(session).size())
	t.assert_equal("索证 / 同要求重复不触发", &"REQUEST_ALREADY_RECORDED", manager.request_material(session, &"request_again", clause).code)
	t.assert_equal("索证 / 只发一次请求", [session], requested)
	t.assert_equal("索证 / 请求只有一条", 1, manager.get_material_requests(session).size())
	t.assert_equal("索证 / 通用条款绑定当前乘客", "TEST_PERSON_001", manager.get_material_requests(session)[0].target_subject.id)
	t.assert_true("质疑 / 两份已有跨来源内容", manager.record_contradiction_challenge(session, &"challenge", Fixture.ref("identity", 1, "destination"), Fixture.ref("floor", 1, "destination")).succeeded)
	t.assert_equal("质疑 / 不自动改变路线", recommendations, manager.get_current_recommended_destinations())
	var post_commit_review: Array[StringName] = []
	manager.documents_changed.connect(func(current: int) -> void:
		if manager.get_received_materials(current).size() == 4:
			post_commit_review.append(manager.request_material(current, &"after_commit", clause).code))
	t.assert_true("补件 / 新原子事件加入 permit", manager.receive_passenger_batch(session, &"supplement", [Fixture.ref("permit")]).succeeded)
	t.assert_equal("补件 / 通知中正式审查已看到整批生效", [&"ALREADY_PROVIDED"], post_commit_review)
	t.assert_equal("补件 / 不重放旧请求", [session], requested)
	t.assert_equal("补件 / 已交材料不再索取", &"ALREADY_PROVIDED", manager.request_material(session, &"already", clause).code)
	t.assert_equal("补件 / 历史索证不丢失", 1, manager.get_material_requests(session).size())
	t.assert_true("更新 / 保留版本快照", manager.receive_passenger_batch(session, &"v2", [Fixture.ref("permit", 2)]).succeeded)
	t.assert_equal("更新 / 旧版引用可读", "001", manager.get_acquired_field(session, Fixture.ref("permit", 1, "destination")).comparable_value)
	t.assert_equal("更新 / 最新版更新", "002", manager.get_acquired_field(session, Fixture.ref("permit", 2, "destination")).comparable_value)
	t.assert_equal("更新 / 正式质疑引用不漂移", 1, manager.get_contradiction_challenges(session)[0].a_ref.version)
	t.assert_equal("更新 / 旧请求不再次触发", [session], requested)
	var copy: Array[Dictionary] = manager.get_material_requests(session)
	copy[0].clause_ref.version = 42
	t.assert_equal("索证 / 记录深副本", 1, manager.get_material_requests(session)[0].clause_ref.version)
	# 判断器只能收到副本；恶意重入不能在判断过程中发起另一个资料命令。
	var reentrant: Array[StringName] = []
	manager.set_document_applicability_resolver(func(data: Dictionary, _context: Dictionary) -> StringName:
		data.required_material_type = "MUTATED"
		reentrant.append(manager.receive_passenger_batch(session, &"reenter", refs).code)
		return &"APPLICABLE")
	manager.request_material(session, &"reentrant", clause)
	t.assert_equal("规则 / 同步判断拒绝命令重入", [&"COMMAND_BUSY"], reentrant)
	t.assert_equal("规则 / 判断器不能改原条款", "TEST_WORK_PERMIT", manager.get_acquired_field(session, clause).required_material_type)
	manager.add_front_transcript_passenger("TEST PLAIN TEXT")
	t.assert_equal("转录 / 普通文字不自动成为资料", 4, manager.get_received_materials(session).size())
	var shadow: DocumentDefinition = Fixture.document("registry/floor/001")
	definition.documents.append(shadow)
	t.assert_false("取得边界 / 伪造保留 ID 不能把楼层档案变成上传件", manager.receive_passenger_batch(session, &"shadow", [Fixture.ref("registry/floor/001")]).succeeded)
	definition.documents.erase(shadow)
	manager.start_dispatch(&"TEST_CASE_001")
	var reopened: int = manager.get_document_session_id()
	t.assert_not_equal("会话 / 同 ID 重开产生新 session", session, reopened)
	t.assert_equal("会话 / 重开清空资料", 0, manager.get_acquired_documents(reopened).size())
	t.assert_equal("会话 / 重开清空索证", 0, manager.get_material_requests(reopened).size())
	t.assert_true("会话 / 旧引用读取拒绝", manager.get_acquired_field(session, clause).is_empty())
	t.assert_equal("会话 / 旧上传拒绝", &"STALE_SESSION", manager.receive_passenger_batch(session, &"late", refs).code)
	manager.start_dispatch(&"TEST_CASE_002")
	t.assert_equal("会话 / 换单清空", 0, manager.get_received_materials(manager.get_document_session_id()).size())
	manager.clear_active_dispatch()
	t.assert_equal("会话 / clear 清空身份", 0, manager.get_document_session_id())
	t.assert_false("会话 / 无派单不能索证", manager.request_material(reopened, &"idle", clause).succeeded)
	manager.start_shift(TestContent.shift())
	var final_session: int = manager.get_document_session_id()
	manager.receive_passenger_batch(final_session, &"final", refs)
	manager.finish_shift()
	t.assert_equal("会话 / 结束值班清理", 0, manager.get_document_session_id())
	t.assert_true("会话 / 结束后无旧收件", manager.get_received_materials(final_session).is_empty())
	# 使用正式完成命令分支（阶段前置条件由其他流程套件覆盖），观察结单通知时已释放资料。
	manager.start_shift(TestContent.shift())
	final_session = manager.get_document_session_id()
	manager.receive_passenger_batch(final_session, &"complete", refs)
	t.assert_true("结单 / 取得许可初版",
		manager.receive_passenger_batch(final_session, &"complete-v1", [Fixture.ref("permit", 1)]).succeeded)
	t.assert_true("结单 / 取得许可更新版",
		manager.receive_passenger_batch(final_session, &"complete-v2", [Fixture.ref("permit", 2)]).succeeded)
	var acquired: Array[Dictionary] = []
	for event: Dictionary in manager.get_document_events(final_session):
		for ref: Dictionary in event.document_refs:
			var receipt := manager.get_acquired_document(final_session, ref)
			acquired.append({"ref": ref, "source": receipt.document.source,
				"route": receipt.route, "event_id": receipt.event_id})
	var active: ActiveDispatchState = manager.dispatch_lifecycle.get_active_state()
	active.current_phase = DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE
	active.exited_floor_id = StringName(manager.get_current_floor())
	manager.complete_active_dispatch()
	var results := manager.shift_runner.get_completed_results()
	t.assert_true("结单 / 资料会话清理后保留取得引用、版本和来源",
		not results.is_empty() and acquired.size() == refs.size() + 2 and results[0].acquired_information == acquired)
	t.assert_equal("会话 / 正常结单销毁旧资料会话", 0, active.document_state.session_id)
	t.assert_true("会话 / 结单后旧事件拒绝", not manager.receive_passenger_batch(final_session, &"late_complete", refs).succeeded)
	manager.queue_free()
	await tree.process_frame
	definition.documents = saved
	print("DOCUMENT FLOW TESTS COMPLETE")


func _test_initial_submission(t: Variant, tree: SceneTree) -> void:
	var manager := DemoFlowManager.new()
	tree.root.add_child(manager)
	manager.start_dispatch(&"TEST_CASE_001")
	var session: int = manager.get_document_session_id()
	var clause: Dictionary = Fixture.ref("rules", 1, "applicable")
	var fields: Array[Dictionary] = [Fixture.ref("work", 1, "destination"), Fixture.ref("floor", 1, "destination")]
	manager.open_system_reference(session, Fixture.ref("rules"))
	manager.accept_left_lookup_result(session, &"left:initial:1", [Fixture.ref("work")])
	manager.accept_right_lookup_result(session, &"right:initial:1", [Fixture.ref("floor")])
	var resolver_calls: Array[int] = []
	manager.set_document_applicability_resolver(func(_clause: Dictionary, _context: Dictionary) -> StringName:
		resolver_calls.append(1)
		return &"APPLICABLE")
	t.assert_equal("初始提交 / 尚未提交不能因空收件箱索证", &"INITIAL_SUBMISSION_REQUIRED", manager.request_material(session, &"premature", clause).code)
	t.assert_equal("初始提交 / 已有两份系统资料仍不能提前正式质疑", &"INITIAL_SUBMISSION_REQUIRED", manager.record_contradiction_challenge(session, &"premature", fields[0], fields[1]).code)
	t.assert_equal("初始提交 / 前置条件失败不调用规则依赖", 0, resolver_calls.size())
	t.assert_equal("初始提交 / 前置条件失败无正式记录", 0, manager.get_material_requests(session).size() + manager.get_contradiction_challenges(session).size())
	t.assert_false("初始提交 / 空的左台结果不能伪装提交完成", manager.accept_left_lookup_result(session, &"left:empty", []).succeeded)
	t.assert_false("初始提交 / 失败上传不满足前置条件", manager.receive_passenger_batch(session, &"bad", [Fixture.ref("missing")]).succeeded)
	t.assert_equal("初始提交 / 失败上传后仍禁止索证", &"INITIAL_SUBMISSION_REQUIRED", manager.request_material(session, &"still_pending", clause).code)
	var events_before: int = manager.get_document_events(session).size()
	var notice_counts: Array[int] = []
	var review_in_notice: Array[StringName] = []
	manager.documents_changed.connect(func(current: int) -> void:
		notice_counts.append(manager.get_received_materials(current).size())
		review_in_notice.append(manager.request_material(current, &"after_empty_commit", clause).code))
	t.assert_true("初始提交 / 空文件批次原子完成", manager.receive_passenger_batch(session, &"initial-empty", []).succeeded)
	t.assert_equal("初始提交 / 空批完成后才允许通知内正式索证", [&"MATERIAL_REQUESTED"], review_in_notice)
	t.assert_equal("初始提交 / 空批无虚拟文件", [0], notice_counts)
	t.assert_equal("初始提交 / 空批保留完成事件", events_before + 1, manager.get_document_events(session).size())
	t.assert_equal("初始提交 / 完成事件引用为空", [], manager.get_document_events(session).back().document_refs)
	manager.receive_passenger_batch(session, &"initial-empty", [])
	manager.receive_passenger_batch(session, &"another-empty", [])
	t.assert_equal("初始提交 / 空批重试与重复完成不重发通知", [0], notice_counts)
	t.assert_equal("初始提交 / 空批完成记录不重复", events_before + 1, manager.get_document_events(session).size())
	t.assert_equal("初始提交 / 完成后合法两份资料可质疑", &"CHALLENGE_RECORDED", manager.record_contradiction_challenge(session, &"after_empty", fields[0], fields[1]).code)
	t.assert_false("初始提交 / 完成后仍拒绝未取得字段", manager.record_contradiction_challenge(session, &"missing", Fixture.ref("identity", 1, "destination"), fields[1]).succeeded)
	t.assert_equal("初始提交 / 空批 ID 不能复用于补件载荷", &"EVENT_CONFLICT", manager.receive_passenger_batch(session, &"initial-empty", [Fixture.ref("permit")]).code)
	t.assert_true("初始提交 / 新事件可合法补件", manager.receive_passenger_batch(session, &"supplement-after-empty", [Fixture.ref("permit")]).succeeded)
	t.assert_equal("初始提交 / 补件后已提供", &"ALREADY_PROVIDED", manager.request_material(session, &"after_supplement", clause).code)
	manager.start_dispatch(&"TEST_CASE_001")
	var reopened: int = manager.get_document_session_id()
	manager.open_system_reference(reopened, Fixture.ref("rules"))
	t.assert_equal("初始提交 / 同 ID 重开不会继承提交完成", &"INITIAL_SUBMISSION_REQUIRED", manager.request_material(reopened, &"reopened", clause).code)
	t.assert_equal("初始提交 / 旧空批回调拒绝", &"STALE_SESSION", manager.receive_passenger_batch(session, &"late-empty", []).code)
	manager.queue_free()
	await tree.process_frame


func _test_source_override(t: Variant, tree: SceneTree, definition: DispatchDefinition) -> void:
	var document: DocumentDefinition = Fixture.document("quoted_work")
	var work: DocumentDefinition = ContentRegistry.get_document_definition("TEST_CASE_001", Fixture.ref("work"))
	document.fields[0].source = work.source
	var report := ContentValidationReport.new()
	ContentValidator.validate_documents([document], report)
	t.assert_true("字段出处 / 跨出处覆盖须有引用说明", report.has_errors())
	document.fields[0].source_note = "TEST：乘客文件引用当班记录，尚未从左台取得原件。"
	report = ContentValidationReport.new()
	ContentValidator.validate_documents([document], report)
	t.assert_false("字段出处 / 合理引用转述允许保留原始出处", report.has_errors())
	definition.documents.append(document)
	var manager := DemoFlowManager.new()
	tree.root.add_child(manager)
	manager.start_dispatch(&"TEST_CASE_001")
	var session: int = manager.get_document_session_id()
	t.assert_true("字段出处 / 引用当班记录的乘客文件可上传", manager.receive_passenger_batch(session, &"quoted-upload", [Fixture.ref("quoted_work")]).succeeded)
	var field: Dictionary = manager.get_acquired_field(session, Fixture.ref("quoted_work", 1, "destination"))
	t.assert_equal("字段出处 / 原始出处保留 duty_record", "duty_record", field.source.kind)
	t.assert_equal("字段出处 / 引用说明保留", document.fields[0].source_note, field.source_note)
	t.assert_true("字段出处 / 读取包含独立取得上下文", field.has("acquisition"))
	if field.has("acquisition"):
		t.assert_equal("字段出处 / 取得渠道仍为乘客上传", "passenger", field.acquisition.route)
		t.assert_equal("字段出处 / 所属文档来源未提升", "passenger_upload", field.acquisition.document_source.kind)
		t.assert_equal("字段出处 / 引用仍绑定乘客文档", Fixture.ref("quoted_work"), field.acquisition.document_ref)
	t.assert_true("字段出处 / 被引当班原件仍未取得", manager.get_acquired_document(session, Fixture.ref("work")).is_empty())
	t.assert_equal("字段出处 / 没有额外系统资料或事件", 1, manager.get_acquired_documents(session).size())
	t.assert_false("字段出处 / 不能把上传字段当系统条款索证", manager.request_material(session, &"quoted-clause", Fixture.ref("quoted_work", 1, "destination")).succeeded)
	manager.accept_left_lookup_result(session, &"left:work:1", [Fixture.ref("work")])
	var original: Dictionary = manager.get_acquired_field(session, Fixture.ref("work", 1, "destination"))
	if original.has("acquisition"):
		t.assert_equal("字段出处 / 原件独立取得后为 left", "left", original.acquisition.route)
		t.assert_equal("字段出处 / 原件独立身份为 duty_record", "duty_record", original.acquisition.document_source.kind)
	manager.queue_free()
	await tree.process_frame
	definition.documents.erase(document)


func _test_lookup_refresh(t: Variant, tree: SceneTree, definition: DispatchDefinition) -> void:
	var work_v2: DocumentDefinition = Fixture.document("work", &"duty_record", 2)
	var floor_v2: DocumentDefinition = Fixture.document("floor", &"floor_archive", 2)
	definition.documents.append(work_v2)
	definition.documents.append(floor_v2)
	var manager := DemoFlowManager.new()
	tree.root.add_child(manager)
	manager.start_dispatch(&"TEST_CASE_001")
	var session: int = manager.get_document_session_id()
	for route: String in ["left", "right"]:
		var accept: Callable = manager.accept_left_lookup_result if route == "left" else manager.accept_right_lookup_result
		var id: String = "work" if route == "left" else "floor"
		# 每次查询分配新的事件 ID，关键词/文档 ID 相同也不复用；同一回调重试保留原 ID。
		var first_id := StringName("%s:%d:1" % [route, session])
		var repeat_id := StringName("%s:%d:2" % [route, session])
		var refresh_id := StringName("%s:%d:3" % [route, session])
		t.assert_true("查询 ID / 首次 " + route, accept.call(session, first_id, [Fixture.ref(id)]).succeeded)
		var count: int = manager.get_document_events(session).size()
		t.assert_equal("查询 ID / 同一完成事件重试幂等 " + route, &"UNCHANGED", accept.call(session, first_id, [Fixture.ref(id)]).code)
		t.assert_equal("查询 ID / 相同查询的新事件允许 " + route, &"UNCHANGED", accept.call(session, repeat_id, [Fixture.ref(id)]).code)
		t.assert_equal("查询 ID / 同版本反复查询不重复取得 " + route, count, manager.get_document_events(session).size())
		t.assert_equal("查询 ID / 不误用旧事件发布新载荷 " + route, &"EVENT_CONFLICT", accept.call(session, first_id, [Fixture.ref(id, 2)]).code)
		t.assert_equal("查询 ID / 新事件合法刷新到 v2 " + route, &"DOCUMENTS_ACQUIRED", accept.call(session, refresh_id, [Fixture.ref(id, 2)]).code)
		t.assert_equal("查询 ID / 更新只多一条事件 " + route, count + 1, manager.get_document_events(session).size())
		t.assert_equal("查询 ID / v1 引用不漂移 " + route, "001", manager.get_acquired_field(session, Fixture.ref(id, 1, "destination")).comparable_value)
		t.assert_equal("查询 ID / v2 新值可读 " + route, "002", manager.get_acquired_field(session, Fixture.ref(id, 2, "destination")).comparable_value)
		t.assert_equal("查询 ID / v2 回调重试幂等 " + route, &"UNCHANGED", accept.call(session, refresh_id, [Fixture.ref(id, 2)]).code)
		t.assert_equal("查询 ID / 延迟 v1 原回调仍幂等 " + route, &"UNCHANGED", accept.call(session, first_id, [Fixture.ref(id)]).code)
		t.assert_equal("查询 ID / 延迟重试不回退当前版本 " + route, 2, manager.get_acquired_documents(session).back().document.version)
	manager.queue_free()
	await tree.process_frame
	definition.documents.erase(work_v2)
	definition.documents.erase(floor_v2)
