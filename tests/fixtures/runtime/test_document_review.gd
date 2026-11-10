extends RefCounted

const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Docs := preload("res://tests/fixtures/runtime/test_documents.gd")
const MAIN := preload("res://scenes/main/main_3d.tscn")
const DIALOGUE := "res://tests/fixtures/runtime/test_document_review.dialogue"
const CASE := &"TEST_CASE_001"


static func ref(id: String, field_id := "", version := 1) -> Dictionary:
	return Docs.ref("review/" + id, version, field_id)


static func prepare() -> Node:
	var dispatches: Dictionary = ContentRegistry.get("_dispatches_by_id").duplicate()
	var definition := (dispatches[CASE] as DispatchDefinition).duplicate() as DispatchDefinition
	definition.dialogue_path = DIALOGUE
	definition.dialogue_events = {}
	var application := Docs.document("review/application")
	application.title = "维修申请"
	application.original_text = "申请进入 001 处理维修任务。"
	application.fields[0].display_value = "申请楼层：001"
	var task := Docs.document("review/task", &"duty_record")
	task.title = "当班任务单"
	task.original_text = "当班工作范围已完整列出。"
	task.fields[0].display_value = "本单维修范围：002"
	task.fields[0].comparable_value = ["002"]
	task.fields.append(Docs.field("complete", true, "bool"))
	task.fields.append(Docs.field("current", true, "bool"))
	task.fields[1].display_value = "工作范围：完整"
	task.fields[2].display_value = "当班状态：有效"
	var revised := task.duplicate(true) as DocumentDefinition
	revised.version = 2
	revised.source.source_version = "2"
	revised.fields[0].display_value = "本单维修范围：001"
	revised.fields[0].comparable_value = ["001"]
	var access := Docs.document("review/access", &"floor_archive")
	access.owner_type = &"floor"
	access.owner_id = &"001"
	access.title = "楼层维修许可"
	access.original_text = "仅可凭覆盖本层的当班任务进入。"
	access.fields[0].display_value = "许可核对楼层：001"
	var rules := Docs.regulation()
	rules.document_id = &"review/regulation"
	rules.title = "维修核验规程"
	rules.original_text = "维修申请应按适用条款核验。"
	rules.fields.resize(1)
	rules.fields[0].display_value = "本次维修申请须提供工作许可。"
	var permit := Docs.document("review/permit", &"passenger_upload", 1, &"TEST_WORK_PERMIT")
	permit.title = "工作许可补件"
	permit.original_text = "乘客补交的工作许可。"
	permit.fields[0].display_value = "许可核验资料"

	var request := DocumentReviewRule.new()
	request.question_id = &"verify_work_permit"
	request.response_title = "provide_permit"
	request.requirement_key = &"TEST_REQUIRE_PERMIT"
	request.applicability_key = &"applicable"
	request.context = [_field("application", "destination", "passenger", "passenger_upload", "001")]
	request.supplement_action = "permit"
	request.supplement_refs = [ref("permit")]
	var challenge := DocumentReviewRule.new()
	challenge.question_id = &"verify_scope"
	challenge.response_title = "clarify_scope"
	var scope := _field("task", "destination", "left", "duty_record", "002")
	challenge.context = [_field("task", "complete", "left", "duty_record", true),
		_field("task", "current", "left", "duty_record", true)]
	challenge.pairs = [
		{"a": request.context[0], "b": scope},
		{"a": _field("access", "destination", "right", "floor_archive", "001"), "b": scope,
			"context": [request.context[0]]},
	]
	definition.documents = [application, task, revised, access, rules, permit]
	definition.review_rules = [request, challenge]
	dispatches[CASE] = definition
	ContentRegistry.set("_dispatches_by_id", dispatches)
	var main := MAIN.instantiate()
	Content.prepare_scene(main)
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.initial_shift = null
	manager.initial_floor = "612"
	return main


static func submit_fixture_documents(manager: DemoFlowManager, version := 1) -> void:
	var session := manager.get_document_session_id()
	manager.receive_passenger_batch(session, &"initial-review-fixture", [ref("application")])
	manager.accept_left_lookup_result(session, &"review-fixture-left", [ref("task", "", version)])
	manager.accept_right_lookup_result(session, &"review-fixture-right", [ref("access")])


static func _field(id: String, field_id: String, route: String, kind: String, value: Variant) -> Dictionary:
	return {"ref": ref(id, field_id), "route": route, "source_kind": kind, "value": value}
