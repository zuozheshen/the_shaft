extends Node
## 手动预览只装配真实 main_3d；F6 是测试驱动，不进入正式输入映射。
const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Documents := preload("res://tests/fixtures/runtime/test_workspace_documents.gd")
var main: Node
var manager: DemoFlowManager

func _ready() -> void:
	Content.install(ContentRegistry)
	ContentRegistry.get_dispatch("TEST_CASE_001").documents = Documents.definitions()
	main = load("res://scenes/main/main_3d.tscn").instantiate()
	Content.prepare_scene(main)
	main.find_child("ConsoleInterface", true, false).dialogue_enabled = false
	manager = main.get_node("游戏运行层/演示流程管理器")
	manager.initial_floor = "612"
	manager.initial_shift = null
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	manager.start_dispatch(&"TEST_CASE_001")
	# 真正登舱成功后才提交乘客原子批次；楼层档案经独立右台完成入口取得。
	var boarded := manager.request_open_cabin_door()
	if boarded.succeeded and manager.is_passenger_onboard():
		Documents.submit_initial(manager)
	Documents.acquire_floor(manager)
	var terminal := main.find_child("核验终端", true, false) as VerificationTerminal3D
	terminal.set_open(true)
	await get_tree().process_frame
	var workspace: VerificationWorkspace = terminal.workspace
	for id: String in ["identity", "task", "floor"]:
		workspace.open_document(Documents.ref(id))
	workspace.arrange_windows()
	print("WORKSPACE PREVIEW READY / F6 补交维修任务表 v2")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F6:
		if event.pressed and not event.echo:
			Documents.supplement(manager)
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	Content.restore(ContentRegistry)