extends RefCounted
const Fixture := preload("res://tests/fixtures/runtime/test_documents.gd")

func run(t: Variant) -> void:
	_test_initial_submission(t)
	var state := DispatchDocumentState.new()
	var session: int = state.session_id
	var documents: Array[DocumentDefinition] = Fixture.definitions()
	var identity: DocumentDefinition = documents[0]
	var second: DocumentDefinition = documents[1]
	var permit: DocumentDefinition = documents[2]
	var updated: DocumentDefinition = documents[3]
	var field_ref: Dictionary = Fixture.ref("identity", 1, "destination")
	t.assert_true("资料 / 未取得不产生缺件虚拟字段", state.get_field(session, field_ref).is_empty())
	t.assert_equal("资料 / 定义不是已收件", 0, state.get_documents(session).size())
	var invalid: DocumentDefinition = Fixture.document("invalid")
	invalid.version = 0
	t.assert_false("资料 / 整批包含坏版本时失败", state.receive(session, &"bad", [identity, invalid], "passenger").succeeded)
	t.assert_equal("资料 / 失败无部分快照", 0, state.get_documents(session).size())
	t.assert_equal("资料 / 失败无提交事件", 0, state.get_events(session).size())
	t.assert_true("资料 / 两份文件一次原子提交", state.receive(session, &"upload", [identity, second], "passenger", 123.0).changed)
	t.assert_equal("资料 / 原子提交后两份完整可查", 2, state.get_documents(session, true).size())
	t.assert_equal("资料 / 一批只有一个事件", 1, state.get_events(session).size())
	t.assert_equal("资料 / 时间注入可追溯", 123.0, state.get_field(session, field_ref).acquired_at)
	t.assert_equal("资料 / 001 保持字符串", "001", state.get_field(session, field_ref).comparable_value)
	t.assert_equal("资料 / 来源更新时间独立", "TEST_TIME_V1", state.get_field(session, field_ref).source.updated_at)
	for id: String in ["false", "zero", "empty"]:
		t.assert_true("资料 / 有值 " + id, state.get_field(session, Fixture.ref("identity", 1, id)).has_value)
	t.assert_equal("资料 / false 保持 bool", false, state.get_field(session, Fixture.ref("identity", 1, "false")).comparable_value)
	t.assert_equal("资料 / 0 保持 int", 0, state.get_field(session, Fixture.ref("identity", 1, "zero")).comparable_value)
	t.assert_equal("资料 / 空字符串保持有值", "", state.get_field(session, Fixture.ref("identity", 1, "empty")).comparable_value)
	t.assert_false("资料 / 缺值不同于空字符串", state.get_field(session, Fixture.ref("identity", 1, "missing")).has_value)
	t.assert_false("资料 / 同事件乱序重试幂等", state.receive(session, &"upload", [second, identity], "passenger").changed)
	t.assert_false("资料 / 新事件重复收件不污染", state.receive(session, &"repeat", [identity], "passenger").changed)
	t.assert_equal("资料 / 重复收件无新事件", 1, state.get_events(session).size())
	t.assert_equal("资料 / 同事件异载荷拒绝", "EVENT_CONFLICT", state.receive(session, &"upload", [identity], "passenger").code)
	var conflict: DocumentDefinition = Fixture.document("identity")
	conflict.title = "CHANGED SAME VERSION"
	t.assert_equal("资料 / 同版本不同内容拒绝", "VERSION_CONFLICT", state.receive(session, &"conflict", [conflict], "passenger").code)
	var new_doc: DocumentDefinition = Fixture.document("new")
	t.assert_false("资料 / 混合新件和冲突件整批拒绝", state.receive(session, &"mixed", [new_doc, conflict], "passenger").succeeded)
	t.assert_true("资料 / 混合失败没有新件", state.get_document(session, Fixture.ref("new")).is_empty())
	t.assert_false("资料 / 批内同文档两个版本拒绝", state.receive(session, &"two_versions", [permit, updated], "passenger").succeeded)
	t.assert_true("资料 / 补交 permit", state.receive(session, &"supplement", [permit], "passenger").changed)
	t.assert_true("资料 / 新版本追加", state.receive(session, &"update", [updated], "passenger").changed)
	t.assert_equal("资料 / 新版不改旧版", "001", state.get_field(session, Fixture.ref("permit", 1, "destination")).comparable_value)
	t.assert_equal("资料 / 新版有新值", "002", state.get_field(session, Fixture.ref("permit", 2, "destination")).comparable_value)
	t.assert_equal("资料 / 首次收件状态", "received", state.get_document(session, Fixture.ref("permit")).change_kind)
	t.assert_equal("资料 / 更新状态依据已有版本", "updated", state.get_document(session, Fixture.ref("permit", 2)).change_kind)
	var first_newer := DispatchDocumentState.new()
	first_newer.receive(first_newer.session_id, &"first_v2", [updated], "passenger")
	t.assert_equal("资料 / 首次取得 v2 不伪称更新", "received", first_newer.get_document(first_newer.session_id, Fixture.ref("permit", 2)).change_kind)
	t.assert_equal("资料 / 倒退提交拒绝", "STALE_VERSION", state.receive(session, &"stale", [permit], "passenger").code)
	t.assert_true("资料 / 旧事件重放仍幂等", state.receive(session, &"supplement", [permit], "passenger").succeeded)
	var copy: Dictionary = state.get_document(session, Fixture.ref("identity"))
	copy.document.fields.destination.comparable_value = "999"
	var events: Array[Dictionary] = state.get_events(session)
	events[0].document_refs.clear()
	identity.fields[0].comparable_value = ["888"]
	t.assert_equal("资料 / getter 和原 Resource 均不能改快照", "001", state.get_field(session, field_ref).comparable_value)
	t.assert_equal("资料 / 事件 getter 为深副本", 2, state.get_events(session)[0].document_refs.size())
	for document: DocumentDefinition in documents:
		var kind: String = String(document.source.kind)
		if kind == "passenger_upload":
			continue
		t.assert_equal("资料 / 上传不能绕过来源 " + kind, "SOURCE_ROUTE_DENIED", state.receive(session, StringName(kind), [document], "passenger").code)
	t.assert_true("资料 / 主台摘录契约可被正式取得记录使用", state.receive(session, &"excerpt", [documents[10]], "main").succeeded)
	t.assert_true("资料 / 缺件虚拟字段不能质疑", not state.record_challenge(session, &"virtual", Fixture.ref("missing", 1, "not_submitted"), field_ref).succeeded)
	t.assert_false("资料 / 缺值字段不能质疑", state.record_challenge(session, &"missing_value", Fixture.ref("identity", 1, "missing"), Fixture.ref("second", 1, "destination")).succeeded)
	t.assert_false("资料 / 同份资料不构成双份引用", state.record_challenge(session, &"same", field_ref, Fixture.ref("identity", 1, "false")).succeeded)
	t.assert_true("资料 / 跨来源双槽只记录质疑", state.record_challenge(session, &"challenge", field_ref, Fixture.ref("excerpt", 1, "destination")).changed)
	t.assert_false("资料 / 重复质疑幂等", state.record_challenge(session, &"challenge", field_ref, Fixture.ref("excerpt", 1, "destination")).changed)
	t.assert_equal("资料 / 质疑记录固定旧版本", 1, state.get_challenges(session)[0].a_ref.version)
	var challenge_copy: Array[Dictionary] = state.get_challenges(session)
	challenge_copy[0].a_ref.version = 99
	t.assert_equal("资料 / 质疑返回副本", 1, state.get_challenges(session)[0].a_ref.version)
	state.close()
	t.assert_equal("资料 / close 撤销会话", 0, state.session_id)
	t.assert_true("资料 / close 后引用失效", state.get_field(session, field_ref).is_empty())
	t.assert_false("资料 / 旧会话不能重新提交", state.receive(session, &"late", [second], "passenger").succeeded)
	t.assert_not_equal("资料 / 新实例会话不复用", session, DispatchDocumentState.new().session_id)
	print("DOCUMENT STATE TESTS COMPLETE")


func _test_initial_submission(t: Variant) -> void:
	var state := DispatchDocumentState.new()
	var session: int = state.session_id
	var clause: Dictionary = Fixture.ref("rules", 1, "applicable")
	state.receive(session, &"system", [Fixture.regulation()], "system")
	state.receive(session, &"left", [Fixture.document("work", &"duty_record")], "left")
	state.receive(session, &"right", [Fixture.document("floor", &"floor_archive")], "right")
	t.assert_false("资料状态 / 系统取得不代表初始提交完成", state.has_initial_submission(session))
	t.assert_equal("资料状态 / 不能绕过 Manager 提前索证", "INITIAL_SUBMISSION_REQUIRED", state.record_material_request(session, &"early", clause, {"type": "passenger", "id": "TEST_PERSON_001"}).code)
	t.assert_equal("资料状态 / 不能绕过 Manager 提前质疑", "INITIAL_SUBMISSION_REQUIRED", state.record_challenge(session, &"early", Fixture.ref("work", 1, "destination"), Fixture.ref("floor", 1, "destination")).code)
	var bad := Fixture.document("invalid")
	bad.version = 0
	state.receive(session, &"bad", [bad], "passenger")
	t.assert_false("资料状态 / 失败原子提交不越过初始门", state.has_initial_submission(session))
	t.assert_equal("资料状态 / 首个空批记录完成", "INITIAL_SUBMISSION_COMPLETED", state.receive(session, &"empty", [], "passenger", 123.0).code)
	t.assert_true("资料状态 / 空批事件是完成依据", state.has_initial_submission(session))
	t.assert_equal("资料状态 / 空批不是虚拟资料", 0, state.get_documents(session, true).size())
	t.assert_equal("资料状态 / 初始完成事件取得时间", 123.0, state.get_events(session).back().committed_at)
	t.assert_true("资料状态 / 完成后缺件可索证", state.record_material_request(session, &"ready", clause, {"type": "passenger", "id": "TEST_PERSON_001"}).succeeded)
	state.close()
	t.assert_false("资料状态 / close 清除完成依据", state.has_initial_submission(session))
