extends RefCounted
## 三份测试资料仅在预览进程内安装，生产派单与资料契约不包含陈述映射。

const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Docs := preload("res://tests/fixtures/runtime/test_documents.gd")
const MAIN := preload("res://scenes/main/main_3d.tscn")
const CASE := &"TEST_CASE_001"

const APPLICATION := "申请进入 001 层处理维修任务。"
const TASK := "本班维修任务范围已完整列出，仅包括 002 层。"
const REGULATION := "本次维修申请须提供覆盖申请楼层的工作许可。"


static func ref(id: String, field_id: String = "") -> Dictionary:
	return Docs.ref("statement/" + id, 1, field_id)


static func prepare() -> Node:
	var dispatches: Dictionary = ContentRegistry.get("_dispatches_by_id").duplicate()
	var definition := (dispatches[CASE] as DispatchDefinition).duplicate() as DispatchDefinition
	definition.dialogue_path = ""
	definition.dialogue_events = {}
	definition.review_rules = []

	var application := Docs.document("statement/application")
	application.title = "维修申请"
	application.original_text = APPLICATION + "\n现场记录 [待填写]。"
	var task := Docs.document("statement/task", &"duty_record")
	task.title = "当班任务单"
	task.original_text = TASK + "\n记录供本班交接使用。"
	task.fields[0].comparable_value = ["002"]
	task.fields.append(Docs.field("complete", true, "bool"))
	task.fields.append(Docs.field("current", true, "bool"))
	var rules := Docs.regulation()
	rules.document_id = &"statement/regulation"
	rules.title = "维修核验规程"
	rules.original_text = REGULATION + "\n查阅时请核对适用范围。"
	rules.fields.resize(1)
	definition.documents = [application, task, rules]
	dispatches[CASE] = definition
	ContentRegistry.set("_dispatches_by_id", dispatches)

	var main := MAIN.instantiate()
	Content.prepare_scene(main)
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.initial_floor = "612"
	manager.initial_shift = null
	return main


static func open_preview(main: Node) -> VerificationTerminal3D:
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	var terminal := main.find_child("核验终端", true, false) as VerificationTerminal3D
	terminal.workspace.statement_documents = {
		"statement/application@1": [_statement("destination", APPLICATION)],
		"statement/task@1": [_statement("destination", TASK)],
		"statement/regulation@1": [_statement("applicable", REGULATION)],
	}
	manager.start_dispatch(CASE)
	var session := manager.get_document_session_id()
	manager.receive_passenger_batch(session, &"statement-preview-upload", [ref("application")])
	manager.accept_left_lookup_result(session, &"statement-preview-left", [ref("task")])
	terminal.set_open(true)
	return terminal


static func _statement(field_id: String, quote: String) -> Dictionary:
	return {"start": 0, "end": quote.length(), "field_id": field_id, "quote": quote}
