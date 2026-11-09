extends Node
## 只装配无剧情档案。右台查询、调阅和拨杆由玩家实际操作。

const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Archives := preload("res://tests/fixtures/runtime/test_right_lookup_documents.gd")

var _dispatch: DispatchDefinition


func _ready() -> void:
	Content.install(ContentRegistry)
	Archives.install_blocked_floor()
	_dispatch = ContentRegistry.get_dispatch("TEST_CASE_001")
	_dispatch.documents = [Archives.document(&"001"), Archives.document(&"005")]
	var main := preload("res://scenes/main/main_3d.tscn").instantiate()
	Content.prepare_scene(main)
	main.find_child("ConsoleInterface", true, false).dialogue_enabled = false
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.initial_floor = "318"
	manager.initial_shift = null
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	manager.start_dispatch(_dispatch.dispatch_id)
	print("RIGHT LOOKUP PREVIEW READY / 001 档案 / 005 不支持停靠 / F6 更新 001 档案")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F6 and event.pressed and not event.echo \
			and _dispatch.documents.size() == 2:
		_dispatch.documents.append(Archives.document(&"001", 2))
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	Content.restore(ContentRegistry)
