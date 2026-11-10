extends Node
## 在正式操作舱中手动使用左台键。F6/F7 只改变测试数据，不代替玩家查询或调阅。

const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Archive := preload("res://tests/fixtures/runtime/test_left_lookup_documents.gd")
const Workspace := preload("res://tests/fixtures/runtime/test_workspace_documents.gd")

var _manager: DemoFlowManager
var _case: DispatchDefinition


func _ready() -> void:
	Content.install(ContentRegistry)
	_case = ContentRegistry.get_dispatch("TEST_CASE_001")
	var person := ContentRegistry.get_passenger(String(_case.passenger_id)).duplicate() as PassengerDefinition
	person.passenger_id = &"P-017"
	ContentRegistry.get("_passengers_by_id")[person.passenger_id] = person
	_case.passenger_id = person.passenger_id
	_case.documents = Archive.definitions(person.passenger_id)
	for document: DocumentDefinition in Workspace.definitions():
		if document.source.kind == &"floor_archive" or document.source.kind == &"system_reference":
			_case.documents.append(document)

	var main := preload("res://scenes/main/main_3d.tscn").instantiate()
	Content.prepare_scene(main)
	_manager = main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	_manager.initial_shift = null
	_manager.initial_floor = "612"
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	_manager.start_dispatch(_case.dispatch_id)
	# 只为同屏演示准备右台来源资料，左台文档必须用实体键调阅。
	Workspace.acquire_floor(_manager)
	print("LEFT LOOKUP PREVIEW READY / F6 更新工作表 / F7 切到无工作记录乘客")


func _input(event: InputEvent) -> void:
	if _manager == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F6:
			var revised := Archive.revised_work(_case.documents)
			if revised != null and not _case.documents.any(func(doc: DocumentDefinition) -> bool:
				return doc.document_id == revised.document_id and doc.version == revised.version):
				_case.documents.append(revised)
		KEY_F7:
			_manager.clear_active_dispatch()
			_manager.start_dispatch(&"TEST_CASE_002")
		_:
			return
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	Content.restore(ContentRegistry)
