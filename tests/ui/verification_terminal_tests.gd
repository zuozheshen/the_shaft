extends RefCounted
## 用正式场景和真实 Viewport 分发验证 W；无剧情夹具不进入正式 Catalog。
const WorkspaceDocs := preload("res://tests/fixtures/runtime/test_workspace_documents.gd")
const MAIN := preload("res://scenes/main/main_3d.tscn")
const TestContent := preload("res://tests/fixtures/runtime/test_content.gd")

func run(t: Variant, tree: SceneTree) -> void:
	var main := MAIN.instantiate()
	TestContent.prepare_scene(main)
	var cabin := main.get_node("三维操作舱") as CabinViewController3D
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	cabin.turn_duration = 0.025
	manager.movement_duration_seconds = 0.08
	t.add_child(main)
	await _frames(tree, 8)
	var terminal := cabin.find_child("核验终端", true, false) as VerificationTerminal3D
	var interaction := cabin.get_node("交互控制器") as CabinInteractionController3D
	var router := cabin.find_child("操作台界面层", true, false) as CabinInterfaceRouter3D
	var console := router.get_main_interface()
	var viewport := cabin.get_viewport()
	terminal.slide_duration = 0.025
	t.assert_true("W / 语义动作绑定物理W", _has_w_binding())
	var second_pad := InputEventJoypadButton.new()
	second_pad.device = 1
	second_pad.button_index = JOY_BUTTON_BACK
	second_pad.pressed = true
	t.assert_true("W / View绑定接受其他手柄设备", second_pad.is_action_pressed(VerificationTerminal3D.TOGGLE_ACTION))
	t.assert_equal("W / 保持原来三个SubViewport", 3, main.find_children("*", "SubViewport", true, false).size())
	t.assert_false("W / 端口不暴露上传入口", terminal._port.has("receive_passenger_batch"))
	t.assert_false("W / 初始不接管", terminal.is_input_captured())

	# 即使 ui_up 也映射 W，开关键不得顺便把焦点移到正文。
	var up_event := InputEventKey.new()
	up_event.physical_keycode = KEY_W
	var already_up := InputMap.action_has_event(&"ui_up", up_event)
	if not already_up:
		InputMap.action_add_event(&"ui_up", up_event)
	_key(viewport, KEY_W)
	await _settle(tree)
	t.assert_true("W / 真实按键打开且压过ui_up", terminal.target_open and terminal.close_button.has_focus())
	_key(viewport, KEY_W, true)
	t.assert_true("W / echo不反转", terminal.target_open)
	if not already_up:
		InputMap.action_erase_event(&"ui_up", up_event)
	_key(viewport, KEY_Q)
	_joy(viewport, JOY_BUTTON_Y)
	await _settle(tree)
	t.assert_equal("W / 展开期间Q不转向", CabinViewController3D.FacingDirection.MAIN_CONSOLE, cabin.get_current_direction())
	t.assert_false("W / 展开期间Y不改变后台COMM", console.comm_view.has_controller_choice_context())
	_key(viewport, KEY_W)
	await _settle(tree)

	# 反转从当前进度开始，旧完成回调不能迟到解锁。
	for n in 8:
		_key(viewport, KEY_W)
		await tree.process_frame
	_key(viewport, KEY_W) # 最终打开
	await _settle(tree)
	t.assert_true("W / 快速反转终点仍展开并接管", terminal.target_open and terminal.is_input_captured())
	_key(viewport, KEY_W)
	await _settle(tree)
	t.assert_true("W / 完全收起端点精确归零", not terminal.is_input_captured() and terminal.open_progress == 0.0)

	# B开始收起时按住A，持续输入不能命中先前CAM焦点。
	interaction._switch_to_gamepad_mode()
	var old_focus := _hotspot(interaction, &"select_camera_02")
	interaction._set_hovered_hotspot(old_focus)
	var cam_before := console.get_current_camera_index()
	_key(viewport, KEY_W)
	await _settle(tree)
	_joy(viewport, JOY_BUTTON_B, true, false)
	Input.action_press(&"interact_confirm")
	_joy(viewport, JOY_BUTTON_A, true, false)
	await _settle(tree)
	t.assert_equal("W / B收起期间及结束后A不穿透CAM", cam_before, console.get_current_camera_index())
	t.assert_equal("W / 有效原热点恢复", old_focus, interaction._hovered_hotspot)
	t.assert_true("W / 按住A维持回中保护", interaction._workspace_rearm)
	_joy(viewport, JOY_BUTTON_B, false, false)
	Input.action_release(&"interact_confirm")
	_joy(viewport, JOY_BUTTON_A, false, false)
	await _frames(tree, 3)
	_joy(viewport, JOY_BUTTON_A)
	t.assert_equal("W / 释放后新A重新操作原CAM", 1, console.get_current_camera_index())

	# 原焦点失效就使用当前台位默认焦点；不恢复失效对象。
	_key(viewport, KEY_W)
	await _settle(tree)
	old_focus.interaction_enabled = false
	terminal.close_button.grab_focus()
	_joy(viewport, JOY_BUTTON_A)
	await _settle(tree)
	t.assert_true("W / A收起不执行失效后台焦点", not terminal.is_input_captured() and console.get_current_camera_index() == 1)
	t.assert_true("W / 失效焦点降级到当前台位", interaction._hovered_hotspot != null and interaction._hovered_hotspot != old_focus)
	old_focus.interaction_enabled = true

	# W在转向中打开，原转向自然完成，关闭不回滚方向。
	_key(viewport, KEY_Q)
	_key(viewport, KEY_W)
	await _settle(tree)
	t.assert_equal("W / 转向中打开保留实际终点", CabinViewController3D.FacingDirection.LEFT_CONSOLE, cabin.get_current_direction())
	var left := router.get_left_interface()
	t.assert_false("W / 遮挡左台时不算主动阅读", left.is_actively_viewed())
	var before_scroll := left.content_scroll_container.scroll_vertical
	Input.action_press(&"context_scroll_down", 1.0)
	interaction._update_context_scroll(0.5)
	t.assert_equal("W / 后台轮询不滚动左台", before_scroll, left.content_scroll_container.scroll_vertical)
	Input.action_release(&"context_scroll_down")
	_key(viewport, KEY_W)
	await _settle(tree)
	t.assert_true("W / 收起后恢复左台阅读", left.is_actively_viewed())
	_key(viewport, KEY_E)
	await _settle(tree)
	_key(viewport, KEY_E)
	await _settle(tree)
	t.assert_equal("W / 原转向恢复到右台", CabinViewController3D.FacingDirection.RIGHT_CONSOLE, cabin.get_current_direction())
	_key(viewport, KEY_W)
	await _settle(tree)
	var right := router.get_right_interface()
	var old_input := str(right.get_destination_presentation().input)
	var digit := _hotspot(interaction, &"destination_digit_1")
	_click(viewport, terminal.get_parent().unproject_position(digit.global_position))
	interaction._execute_action(&"destination_digit_1")
	t.assert_equal("W / 背景鼠标与执行入口都无点穿", old_input, str(right.get_destination_presentation().input))

	# COMM刷新可以继续；不能从W抢走焦点或推进选择。
	console.comm_view.present(true, "TEST", [{"text":"TEST","is_allowed":true}], true, true)
	terminal.close_button.grab_focus()
	console.comm_view.present(true, "TEST UPDATE", [{"text":"TEST","is_allowed":true}], true, true)
	t.assert_true("W / 通讯继续刷新但不抢焦点", terminal.close_button.has_focus())
	t.assert_equal("W / 通讯正文继续更新", "TEST UPDATE", console.comm_view.speech_label.text)

	# 用W收起期间持有B，后台COMM不能被这次旧输入最小化。
	_key(viewport, KEY_W)
	Input.action_press(&"interact_cancel")
	_joy(viewport, JOY_BUTTON_B, true, false)
	await _settle(tree)
	t.assert_false("W / 持有B跨关闭边界不取消后台COMM", console.comm_view.is_minimized())
	Input.action_release(&"interact_cancel")
	_joy(viewport, JOY_BUTTON_B, false, false)
	await _frames(tree, 3)
	_joy(viewport, JOY_BUTTON_BACK)
	await _settle(tree)
	t.assert_true("W / View语义动作重新打开", terminal.target_open)

	# 使用真实资料窗验证同单阅读保留；换单撤销旧会话。
	var definition: DispatchDefinition = ContentRegistry.get_dispatch("TEST_CASE_001")
	var saved_documents: Array[DocumentDefinition] = definition.documents
	definition.documents = WorkspaceDocs.definitions(true)
	WorkspaceDocs.submit_initial(manager)
	terminal.workspace.open_document(WorkspaceDocs.ref("task"))
	await _frames(tree, 3)
	var reading_scroll: ScrollContainer = terminal.workspace.windows["preview/task@1"].scroll
	reading_scroll.scroll_vertical = 180
	reading_scroll.grab_focus()
	await _frames(tree, 2) # 布局可能夹紧请求值，保存实际可达滚动位置。
	var saved_scroll := reading_scroll.scroll_vertical
	var current_session := terminal._session_id
	_key(viewport, KEY_W)
	await _settle(tree)
	_key(viewport, KEY_W)
	await _settle(tree)
	t.assert_true("W / 保存的是实际非零滚动位置", saved_scroll > 0)
	t.assert_equal("W / 同单重开保留滚动", saved_scroll, reading_scroll.scroll_vertical)
	t.assert_true("W / 同单重开保留焦点", reading_scroll.has_focus())
	manager.start_dispatch(&"TEST_CASE_001")
	await _frames(tree, 2)
	t.assert_true("W / 同派单ID重开更换session", terminal._session_id != current_session)
	t.assert_equal("W / 换单清理资料窗口", 0, terminal.workspace.windows.size())
	definition.documents = saved_documents
	t.assert_true("W / 换单不强制收起", terminal.target_open)
	var door_before := manager.is_cabin_door_open()
	var result := manager.request_travel_to_floor(manager.get_pickup_floor())
	t.assert_true("W / 打开时仍可接受既有行驶命令", result.succeeded)
	await tree.create_timer(0.14).timeout
	t.assert_equal("W / 行驶持续推进到接乘层", manager.get_pickup_floor(), manager.get_current_floor())
	t.assert_equal("W / 开合不改门状态", door_before, manager.is_cabin_door_open())
	manager.clear_active_dispatch()
	t.assert_equal("W / clear撤销到空会话", 0, terminal._session_id)
	t.assert_true("W / 空舱仍可展开", terminal.target_open)
	await _test_sizes(t, tree, terminal)
	_key(viewport, KEY_W)
	await _settle(tree)
	for action in VerificationTerminal3D.PAD_ACTIONS:
		Input.action_release(action)
	main.queue_free()
	await _frames(tree, 4)
	print("VERIFICATION TERMINAL TESTS COMPLETE")

func _test_sizes(t: Variant, tree: SceneTree, terminal: VerificationTerminal3D) -> void:
	var window := tree.root
	var original_size := window.size
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(1280,1024)]:
		window.size = size
		await _frames(tree, 3)
		terminal._update_layout()
		var rect := terminal.get_screen_rect()
		var available := terminal.get_viewport().get_visible_rect().size
		t.assert_true("W / 屏口在可视范围内 " + str(size), rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= available.x and rect.end.y <= available.y)
		t.assert_true("W / Control与3D屏口投影对齐 " + str(size), terminal.screen.position.distance_to(rect.position) < 1.0 and terminal.screen.size.distance_to(rect.size) < 1.0)
	# resize发生在动画途中时，保留进度并重算位置，不累加旧像素偏移。
	terminal.slide_duration = 0.2
	terminal.set_open(false)
	await tree.process_frame
	var mid_progress := terminal.open_progress
	window.size = Vector2i(1600, 900)
	terminal._update_layout()
	t.assert_equal("W / resize不重置动画进度", mid_progress, terminal.open_progress)
	terminal.set_open(true)
	await tree.create_timer(0.24).timeout
	t.assert_true("W / resize后可反转回精确展开端点", terminal.open_progress == 1.0 and terminal.is_input_captured())
	window.size = original_size
	terminal.slide_duration = 0.025
	await _frames(tree, 3)

func _has_w_binding() -> bool:
	for event in InputMap.action_get_events(VerificationTerminal3D.TOGGLE_ACTION):
		if event is InputEventKey and event.physical_keycode == KEY_W:
			return true
	return false

func _hotspot(interaction: CabinInteractionController3D, action: StringName) -> InteractionHotspot3D:
	for node in interaction.get_parent().find_children("*", "Area3D", true, false):
		if node is InteractionHotspot3D and node.get_action_id() == action:
			return node
	return null

func _key(viewport: Viewport, code: Key, echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		event.echo = echo
		viewport.push_input(event, true)

func _joy(viewport: Viewport, button: JoyButton, pressed: bool = true, release: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	viewport.push_input(event, true)
	if release and pressed:
		event = event.duplicate()
		event.pressed = false
		viewport.push_input(event, true)

func _click(viewport: Viewport, point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)

func _settle(tree: SceneTree) -> void:
	await tree.create_timer(0.08).timeout

func _frames(tree: SceneTree, count: int) -> void:
	for n in count:
		await tree.process_frame
