extends Node
## 仅此预览替换终端脚本。正式场景和资料目录仍从项目正常加载。
const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Documents := preload("res://tests/fixtures/runtime/test_workspace_documents.gd")
const GateTerminal := preload("res://tests/preview/verification_3d_gate_terminal.gd")

var terminal: GateTerminal
var measuring := false
var evidence_dir: String

func _ready() -> void:
	Content.install(ContentRegistry)
	var definition := ContentRegistry.get_dispatch("TEST_CASE_001") as DispatchDefinition
	var documents := Documents.definitions()
	for document in documents:
		if document.document_id == &"preview/task":
			document.original_text += "\n" + ("本行用于检查较长中文句子换行后，鼠标位置、字形和选区是否一致。\n").repeat(14)
		if document.document_id == &"preview/identity":
			document.original_text += "\n" + ("证件来源与取得时间须分别核对，记录本身并不表示内容已经核实。\n").repeat(18)
	definition.documents = documents
	var main := preload("res://scenes/main/main_3d.tscn").instantiate()
	Content.prepare_scene(main)
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.initial_floor = "612"
	manager.initial_shift = null
	var node := main.find_child("核验终端", true, false) as VerificationTerminal3D
	var paths := [node.view_controller_path, node.interaction_controller_path, node.left_screen_path]
	node.set_script(GateTerminal)
	terminal = node as GateTerminal
	terminal.view_controller_path = paths[0]
	terminal.interaction_controller_path = paths[1]
	terminal.left_screen_path = paths[2]
	add_child.call_deferred(main)
	await get_tree().process_frame
	await main.get_node("值守入口").start_duty()
	manager.start_dispatch(&"TEST_CASE_001")
	var boarded := manager.request_open_cabin_door()
	if boarded.succeeded and manager.is_passenger_onboard():
		Documents.submit_initial(manager)
	Documents.acquire_floor(manager)
	var workspace := terminal.workspace
	# 仅任务表走现有原文选取预览；其余窗保留结构化字段。
	workspace.statement_documents = {
		"preview/task@1": [{"start": 0, "end": 4, "quote": "乘客提交", "field_id": ""}]
	}
	terminal.set_open(true)
	await get_tree().process_frame
	for id: String in ["identity", "task", "floor"]:
		workspace.open_document(Documents.ref(id))
	workspace.arrange_windows()
	print("W GATE READY / F6 CanvasLayer–3D / F7 第四窗 / F8 取样 / F9 透视 / F5 尺寸")
	print("W GATE renderer=", RenderingServer.get_current_rendering_method(), "/",
		RenderingServer.get_current_rendering_driver_name(), " / ", RenderingServer.get_video_adapter_name())
	_run_gate.call_deferred()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or terminal == null:
		return
	match event.keycode:
		KEY_F5:
			var sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]
			get_window().mode = Window.MODE_WINDOWED
			get_window().size = sizes[(sizes.find(get_window().size) + 1) % sizes.size()]
		KEY_F6: terminal.set_projected(not terminal.projected)
		KEY_F7:
			terminal.workspace.open_reference(Documents.ref("rules"))
			terminal.workspace.arrange_windows()
		KEY_F8: _measure()
		KEY_F9:
			terminal.tilted = not terminal.tilted
			terminal._update_layout()
		_: return
	get_viewport().set_input_as_handled()

func _measure() -> void:
	if measuring or not terminal.target_open:
		return
	measuring = true
	var projected := terminal.projected
	for frame in 45:
		await RenderingServer.frame_post_draw
	var values: Array[float] = []
	var root_gpu: Array[float] = []
	var gui_gpu: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 300:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		values.append((now - previous) / 1000.0)
		root_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		if projected:
			gui_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(terminal.gui.get_viewport_rid()))
		previous = now
	values.sort()
	root_gpu.sort()
	gui_gpu.sort()
	print("W GATE PERF mode=", "3D" if projected else "CanvasLayer", " window=", get_window().size,
		" texture=", terminal.gui.size if projected else Vector2i.ZERO,
		" docs=", terminal.workspace.windows.size(), " frames=300 ms p50=", values[149],
		" p95=", values[284], " max=", values[-1],
		" root_gpu_p50=", root_gpu[149], " sub_gpu_p50=", gui_gpu[149] if projected else 0.0,
		" renderer_video_bytes=", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	measuring = false

func _run_gate() -> void:
	evidence_dir = OS.get_user_data_dir().path_join("issue-101-w-gate")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	print("W GATE evidence=", evidence_dir)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(terminal.gui.get_viewport_rid(), true)
	await get_tree().create_timer(0.5).timeout
	for requested: Vector2i in [get_window().size, Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]:
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = requested
		await get_tree().create_timer(0.3).timeout
		print("W GATE resolution requested=", requested, " actual=", get_window().size,
			" logical=", get_viewport().get_visible_rect().size)
		for value: bool in [false, true]:
			terminal.set_projected(value)
			await _measure()
			var frame := get_viewport().get_texture().get_image()
			var filename := "%dx%d-%s.png" % [frame.get_width(), frame.get_height(), "3d" if value else "canvas"]
			print("W GATE screenshot=", filename, " result=", frame.save_png(evidence_dir.path_join(filename)))
		if requested == Vector2i(1280, 720):
			terminal.workspace.open_reference(Documents.ref("rules"))
			terminal.workspace.arrange_windows()
	await _exercise_input()
	print("W GATE AUTOMATED SAMPLE COMPLETE")

func _exercise_input() -> void:
	var workspace := terminal.workspace
	var identity: DocumentWindow = workspace.windows["preview/identity@1"]
	var task: DocumentWindow = workspace.windows["preview/task@1"]
	var floor_doc: DocumentWindow = workspace.windows["preview/floor@1"]
	# 先用干净的鼠标捕获验证字段和选区，再查拖动后的同一条路径。
	await _exercise_clicks(task, floor_doc, "before_drag")
	workspace.raise_window("preview/identity@1")
	await get_tree().process_frame
	var position_before := identity.position
	var start := identity.title_label.get_global_rect().get_center()
	_button(start, true)
	_motion(start + Vector2(100, 45))
	_button(start + Vector2(100, 45), false)
	print("W GATE INPUT drag_moved=", identity.position != position_before,
		" released=", identity._drag_mode == 0)
	var grip := identity.get_children().back() as Control
	var size_before := identity.size
	start = grip.get_global_rect().get_center()
	_button(start, true)
	_motion(start + Vector2(70, 45))
	_button(start + Vector2(70, 45), false)
	print("W GATE INPUT resize_changed=", identity.size != size_before,
		" released=", identity._drag_mode == 0)
	start = identity.title_label.get_global_rect().get_center()
	_button(start, true)
	_motion(Vector2(-45, start.y))
	_button(Vector2(-45, start.y), false)
	print("W GATE INPUT outside_release=", not terminal._mouse_down and identity._drag_mode == 0)
	start = identity.scroll.get_global_rect().get_center()
	var before_scroll := identity.scroll.scroll_vertical
	for i in 3:
		_button(start, true, MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().process_frame
	print("W GATE INPUT wheel_scrolled=", identity.scroll.scroll_vertical > before_scroll)
	await _exercise_clicks(task, floor_doc, "after_drag")
	var frame: Image
	var focused := terminal.gui.gui_get_focus_owner()
	_key(KEY_TAB, true)
	_key(KEY_TAB, false)
	print("W GATE INPUT tab_changed=", focused != terminal.gui.gui_get_focus_owner())
	var tab_focus := terminal.gui.gui_get_focus_owner()
	_key(KEY_TAB, true, true)
	_key(KEY_TAB, false, true)
	print("W GATE INPUT shift_tab_restored=", terminal.gui.gui_get_focus_owner() == focused,
		" focus_valid=", is_instance_valid(tab_focus))
	var scroll_before := task.scroll.scroll_vertical
	Input.action_press(&"context_scroll_down")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(&"context_scroll_down")
	print("W GATE INPUT right_stick_action_scrolled=", task.scroll.scroll_vertical > scroll_before)
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	get_viewport().push_input(a, true)
	a = a.duplicate()
	a.pressed = false
	get_viewport().push_input(a, true)
	print("W GATE INPUT a_sent focus=", terminal.gui.gui_get_focus_owner())
	terminal.tilted = true
	terminal._update_layout()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	frame = get_viewport().get_texture().get_image()
	print("W GATE tilted screenshot result=", frame.save_png(evidence_dir.path_join("3d-tilted.png")))
	_key(KEY_W, true)
	_key(KEY_W, false)
	await get_tree().create_timer(0.5).timeout
	print("W GATE INPUT w_released_shield=", not terminal.is_input_captured(),
		" forwarded=", terminal._forwarded)

func _exercise_clicks(task: DocumentWindow, floor_doc: DocumentWindow, label: String) -> void:
	var workspace := terminal.workspace
	workspace.raise_window("preview/floor@1")
	floor_doc.position = Vector2.ZERO
	floor_doc.size = workspace.desk.size
	await get_tree().process_frame
	await get_tree().process_frame
	var field: Button = floor_doc._review_buttons.front()
	var submissions := [0]
	var count_submission := func(_ref: Dictionary) -> void: submissions[0] += 1
	floor_doc.review_field_requested.connect(count_submission)
	var start := field.get_global_rect().get_center()
	_button(start, true)
	_button(start, false)
	floor_doc.review_field_requested.disconnect(count_submission)
	print("W GATE INPUT field ", label, " actions=", submissions[0])
	workspace.raise_window("preview/task@1")
	task.position = Vector2.ZERO
	task.size = workspace.desk.size
	await get_tree().process_frame
	await get_tree().process_frame
	var quote := task._quote_body
	start = quote.get_global_rect().position + Vector2(10, 12)
	var last := start + Vector2(130, 52)
	_button(start, true)
	_motion(last)
	_button(last, false)
	await get_tree().process_frame
	print("W GATE INPUT quote ", label, " text=", quote.get_selected_text().replace("\n", "\\n"),
		" focused=", terminal.gui.gui_get_focus_owner() == quote)
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	print("W GATE selection screenshot result=", frame.save_png(evidence_dir.path_join("3d-selection-" + label + ".png")))

func _point(pos: Vector2) -> Vector2:
	var uv := pos / terminal.screen.size
	var extent := (terminal.surface.mesh as QuadMesh).size
	var local := Vector3((uv.x - 0.5) * extent.x, (0.5 - uv.y) * extent.y, 0.0)
	var camera := terminal.get_parent() as Camera3D
	return camera.unproject_position(terminal.surface.to_global(local))

func _button(pos: Vector2, pressed: bool, index := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = _point(pos)
	event.global_position = event.position
	get_viewport().push_input(event, true)

func _motion(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _point(pos)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)

func _key(code: Key, pressed: bool, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _exit_tree() -> void:
	Content.restore(ContentRegistry)
