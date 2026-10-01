extends RefCounted
## 使用正式 main_3d 验证手柄语义输入、空间焦点、COMM 仲裁与完整目的地入口。

const MAIN := preload("res://scenes/main/main_3d.tscn")


func run(t: Variant, tree: SceneTree) -> void:
	_test_input_map(t)
	var main := MAIN.instantiate()
	var cabin := main.get_node("三维操作舱") as CabinViewController3D
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.movement_duration_seconds = 0.01
	t.add_child(main)
	await _frames(tree)
	var interaction := cabin.get_node("交互控制器") as CabinInteractionController3D
	var router := main.find_child("操作台界面层", true, false) as CabinInterfaceRouter3D
	var console := router.get_main_interface()
	var comm := console.comm_view

	interaction._switch_to_gamepad_mode()
	interaction._establish_default_gamepad_focus()
	t.assert_true("手柄 / 主台进入时建立默认焦点",
			interaction._hovered_hotspot != null
			and interaction._hovered_hotspot.get_station_id() == &"main_console")
	t.assert_equal("手柄 / 低于 threshold 不产生方向", Vector2i.ZERO,
			interaction._quantize_navigation_direction(Vector2(0.54, 0.0)))
	t.assert_equal("手柄 / 越过 threshold 量化为单一方向", Vector2i.RIGHT,
			interaction._quantize_navigation_direction(Vector2(0.56, 0.2)))
	_assert_station_reachable(t, interaction, &"main_console", [
		&"open_microphone", &"open_door", &"close_door",
		&"select_camera_01", &"select_camera_02",
	])
	interaction._set_hovered_hotspot(
			_hotspot_for_action(interaction, &"select_camera_01"))
	cabin._is_turning = true
	interaction._on_turn_started(CabinViewController3D.FacingDirection.LEFT_CONSOLE, "左操作台")
	t.assert_equal("手柄 / 转向开始清除原台焦点", null, interaction._hovered_hotspot)
	var camera_before_turn := console.get_current_camera_index()
	interaction._handle_gamepad_confirm()
	t.assert_equal("手柄 / 转向期间 A 不执行热点", camera_before_turn,
			console.get_current_camera_index())
	cabin._is_turning = false
	interaction._establish_default_gamepad_focus()
	t.assert_true("手柄 / 转向结束可重建当前台焦点",
			interaction._hovered_hotspot != null)

	var mouse_hotspot := main.find_child("麦克风热点", true, false) as InteractionHotspot3D
	interaction._set_hovered_hotspot(mouse_hotspot)
	interaction._input_mode = CabinInteractionController3D.InputMode.MOUSE
	interaction._switch_to_gamepad_mode()
	t.assert_equal("手柄 / 切换设备清除旧鼠标热点", null, interaction._hovered_hotspot)
	interaction._establish_default_gamepad_focus()
	interaction._switch_to_mouse_mode()
	t.assert_equal("手柄 / 切回鼠标清除手柄焦点", null, interaction._hovered_hotspot)

	await _test_navigation_repeat(t, tree, interaction)
	await _test_left_console(t, tree, cabin, interaction, router)
	await _test_right_console(t, tree, cabin, interaction, router, manager)
	await _test_comm_priority(t, tree, interaction, comm)

	_release_test_actions()
	main.queue_free()
	await _frames(tree, 3)


func _test_input_map(t: Variant) -> void:
	t.assert_true("手柄 / turn_left 保留 Q", _has_key(&"turn_left", KEY_Q))
	t.assert_true("手柄 / turn_right 保留 E", _has_key(&"turn_right", KEY_E))
	t.assert_true("手柄 / turn_left 绑定左肩键", _has_button(&"turn_left", JOY_BUTTON_LEFT_SHOULDER))
	t.assert_true("手柄 / turn_right 绑定右肩键", _has_button(&"turn_right", JOY_BUTTON_RIGHT_SHOULDER))
	for action in [
		&"focus_left", &"focus_right", &"focus_up", &"focus_down",
		&"interact_confirm", &"interact_cancel", &"comm_toggle",
		&"context_scroll_up", &"context_scroll_down",
	]:
		t.assert_true("手柄 / InputMap 动作存在 " + action, InputMap.has_action(action))
	t.assert_true("手柄 / 左摇杆 X 支持左右",
			_has_axis(&"focus_left", JOY_AXIS_LEFT_X, -1.0)
			and _has_axis(&"focus_right", JOY_AXIS_LEFT_X, 1.0))
	t.assert_true("手柄 / 左摇杆 Y 支持上下",
			_has_axis(&"focus_up", JOY_AXIS_LEFT_Y, -1.0)
			and _has_axis(&"focus_down", JOY_AXIS_LEFT_Y, 1.0))
	t.assert_true("手柄 / D-pad 支持四方向",
			_has_button(&"focus_left", JOY_BUTTON_DPAD_LEFT)
			and _has_button(&"focus_right", JOY_BUTTON_DPAD_RIGHT)
			and _has_button(&"focus_up", JOY_BUTTON_DPAD_UP)
			and _has_button(&"focus_down", JOY_BUTTON_DPAD_DOWN))
	t.assert_true("手柄 / A B Y 使用语义动作",
			_has_button(&"interact_confirm", JOY_BUTTON_A)
			and _has_button(&"interact_cancel", JOY_BUTTON_B)
			and _has_button(&"comm_toggle", JOY_BUTTON_Y))
	t.assert_true("手柄 / 右摇杆 Y 支持上下滚动",
			_has_axis(&"context_scroll_up", JOY_AXIS_RIGHT_Y, -1.0)
			and _has_axis(&"context_scroll_down", JOY_AXIS_RIGHT_Y, 1.0))


func _test_navigation_repeat(
		t: Variant,
		tree: SceneTree,
		interaction: CabinInteractionController3D
) -> void:
	interaction._switch_to_gamepad_mode()
	var first := interaction._get_gamepad_candidates()[0]
	interaction._set_hovered_hotspot(first)
	Input.action_press(&"focus_right", 0.8)
	interaction._update_gamepad_navigation(0.0)
	var after_first := interaction._hovered_hotspot
	interaction._update_gamepad_navigation(0.10)
	t.assert_equal("手柄 / 首次触发后延迟期间不连跳", after_first,
			interaction._hovered_hotspot)
	interaction._update_gamepad_navigation(interaction.gamepad_initial_repeat_delay)
	t.assert_true("手柄 / 延迟后才允许固定节奏重复",
			interaction._hovered_hotspot != after_first or after_first == first)
	Input.action_release(&"focus_right")
	interaction._update_gamepad_navigation(0.0)
	t.assert_equal("手柄 / 摇杆回中解锁重复状态", Vector2i.ZERO,
			interaction._navigation_direction)
	await tree.process_frame


func _test_left_console(
		t: Variant,
		tree: SceneTree,
		cabin: CabinViewController3D,
		interaction: CabinInteractionController3D,
		router: CabinInterfaceRouter3D
) -> void:
	_turn_to(cabin, CabinViewController3D.FacingDirection.LEFT_CONSOLE)
	interaction._switch_to_gamepad_mode()
	interaction._establish_default_gamepad_focus()
	var actions: Array[StringName] = []
	for hotspot in interaction._get_gamepad_candidates():
		actions.append(hotspot.get_action_id())
	t.assert_false("手柄 / left_scroll 不进入焦点候选", &"left_scroll" in actions)
	t.assert_equal("手柄 / 左台只有三枚实体栏目键可聚焦", 3, actions.size())
	_assert_station_reachable(t, interaction, &"left_console", [
		&"left_passenger_record", &"left_transcript", &"left_system_log",
	])

	var terminal := router.get_left_interface()
	var long_lines := PackedStringArray()
	for index in 80:
		long_lines.append("手柄滚动行 %02d" % index)
	terminal.terminal_content_label.text = "\n".join(long_lines)
	await _frames(tree, 3)
	var left := cabin.get_node("操作台占位/左操作台定位") as LeftTerminalScreen3D
	var wheel := left.get_node(left.scroll_wheel_visual_path) as Node3D
	var wheel_before := wheel.transform.basis
	Input.action_press(&"context_scroll_down", 0.8)
	interaction._update_context_scroll(0.0)
	var scroll_after_first: int = terminal.content_scroll_container.scroll_vertical
	var wheel_after_first := wheel.transform.basis
	interaction._update_context_scroll(0.10)
	t.assert_true("手柄 / 右摇杆首次滚动驱动唯一内容与滚轮",
			scroll_after_first > 0 and wheel_after_first != wheel_before)
	t.assert_equal("手柄 / 滚动初始延迟期间不连续触发", wheel_after_first,
			wheel.transform.basis)
	Input.action_release(&"context_scroll_down")
	interaction._update_context_scroll(0.0)
	t.assert_equal("手柄 / 右摇杆回中解除滚动锁", 0, interaction._scroll_direction)


func _test_right_console(
		t: Variant,
		tree: SceneTree,
		cabin: CabinViewController3D,
		interaction: CabinInteractionController3D,
		router: CabinInterfaceRouter3D,
		manager: DemoFlowManager
) -> void:
	_turn_to(cabin, CabinViewController3D.FacingDirection.RIGHT_CONSOLE)
	interaction._switch_to_gamepad_mode()
	interaction._establish_default_gamepad_focus()
	_assert_station_reachable(t, interaction, &"right_console", [
		&"destination_verify", &"destination_digit_1", &"destination_digit_2",
		&"destination_digit_3", &"destination_digit_4", &"destination_digit_5",
		&"destination_digit_6", &"destination_digit_7", &"destination_digit_8",
		&"destination_digit_9", &"destination_clear", &"destination_digit_0",
		&"destination_backspace", &"destination_submit",
	])
	var digit_two := _hotspot_for_action(interaction, &"destination_digit_2")
	digit_two.interaction_enabled = false
	t.assert_false("手柄 / disabled 热点从候选移除",
			digit_two in interaction._get_gamepad_candidates())
	digit_two.interaction_enabled = true

	var destination := router.get_right_interface()
	var pickup_result := manager.request_travel_to_floor(manager.get_pickup_floor())
	t.assert_true("手柄 / 测试可推进到接乘层", pickup_result.succeeded)
	if manager.is_elevator_moving():
		await manager.elevator_movement_completed
	_turn_to(cabin, CabinViewController3D.FacingDirection.MAIN_CONSOLE)
	interaction._switch_to_gamepad_mode()
	for action in [&"select_camera_01", &"select_camera_02"]:
		interaction._set_hovered_hotspot(_hotspot_for_action(interaction, action))
		t.assert_true("手柄 / A 操作主台 " + action,
				interaction._handle_gamepad_confirm())
	var console := router.get_main_interface()
	t.assert_equal("手柄 / 主台 CAM 02 经焦点切换", 1,
			console.get_current_camera_index())
	interaction._set_hovered_hotspot(_hotspot_for_action(interaction, &"open_door"))
	t.assert_true("手柄 / A 操作主台开门", interaction._handle_gamepad_confirm())
	t.assert_true("手柄 / 主台开门进入接乘状态", manager.is_cabin_door_open())
	var stage := cabin.get_parent().find_child("监控测试摄影棚", true, false) \
			as MonitorStageController3D
	await _settle_presentation(stage, tree)
	interaction._set_hovered_hotspot(_hotspot_for_action(interaction, &"close_door"))
	t.assert_true("手柄 / A 操作主台关门", interaction._handle_gamepad_confirm())
	await _settle_presentation(stage, tree)
	t.assert_true("手柄 / 主台关门后乘客已进舱",
			not manager.is_cabin_door_open() and manager.is_passenger_onboard())
	interaction._set_hovered_hotspot(_hotspot_for_action(interaction, &"open_microphone"))
	t.assert_true("手柄 / A 操作主台 MIC", interaction._handle_gamepad_confirm())
	t.assert_true("手柄 / 主台 MIC 接通原通讯", console.mic_enabled)
	console.request_toggle_microphone()
	_turn_to(cabin, CabinViewController3D.FacingDirection.RIGHT_CONSOLE)
	interaction._establish_default_gamepad_focus()
	destination.clear_destination_input()
	for action in [
		&"destination_digit_9", &"destination_digit_0", &"destination_digit_0",
		&"destination_verify", &"destination_submit",
	]:
		interaction._set_hovered_hotspot(_hotspot_for_action(interaction, action))
		t.assert_true("手柄 / A 确认当前焦点 " + action,
				interaction._handle_gamepad_confirm())
		await _frames(tree, 2)
	if manager.is_elevator_moving():
		await manager.elevator_movement_completed
	t.assert_equal("手柄 / 数字→VERIFY→SUBMIT 完成正常行驶", "900",
			manager.get_current_floor())
	t.assert_equal("手柄 / 行驶启动后沿用原清空规则", "",
			destination.manual_destination_line_edit.text)


func _test_comm_priority(
		t: Variant,
		tree: SceneTree,
		interaction: CabinInteractionController3D,
		comm: FloatingCommUI
) -> void:
	var selected: Array[int] = []
	comm.choice_selected.connect(func(index: int) -> void: selected.append(index))
	comm.present(true, "手柄通讯测试", [
		{"text": "选项一", "is_allowed": true},
		{"text": "禁用项", "is_allowed": false},
		{"text": "选项三", "is_allowed": true},
	], true, true)
	comm.set_minimized(false)
	interaction._switch_to_gamepad_mode()
	interaction._establish_default_gamepad_focus()
	t.assert_true("手柄 / COMM 展开且有选项时取得优先上下文",
			comm.has_controller_choice_context())
	t.assert_equal("手柄 / COMM 优先时不保留背后 3D 焦点", null,
			interaction._hovered_hotspot)
	t.assert_true("手柄 / COMM 建立首个 enabled focus", comm.focus_controller_choice(0))
	t.assert_true("手柄 / COMM 导航跳过 disabled 选项", comm.focus_controller_choice(1))
	# 真实事件经过 Viewport：Control 同时绑定 ui_accept，必须只由交互控制器消费一次。
	_push_joypad_button(comm.get_viewport(), JOY_BUTTON_A)
	t.assert_equal("手柄 / COMM 单次确认且不穿透", [2], selected)
	t.assert_true("手柄 / B 在展开 COMM 中消费返回", comm.cancel_controller_context())
	t.assert_true("手柄 / B 最小化 COMM", comm.is_minimized())
	t.assert_false("手柄 / B 在无上下文时保持无动作", comm.cancel_controller_context())
	interaction._establish_default_gamepad_focus()
	t.assert_true("手柄 / COMM 最小化后恢复 3D 焦点",
			interaction._hovered_hotspot != null)
	await tree.process_frame


func _assert_station_reachable(
		t: Variant,
		interaction: CabinInteractionController3D,
		station_id: StringName,
		expected_actions: Array
) -> void:
	var candidates := interaction._get_gamepad_candidates()
	var queue: Array[InteractionHotspot3D] = []
	var visited: Dictionary = {}
	if not candidates.is_empty():
		queue.append(candidates[0])
	while not queue.is_empty():
		var current: InteractionHotspot3D = queue.pop_front()
		if visited.has(current.get_action_id()):
			continue
		visited[current.get_action_id()] = true
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := interaction._find_directional_hotspot(current, direction)
			if next != null and not visited.has(next.get_action_id()):
				queue.append(next)
	for action in expected_actions:
		t.assert_true("手柄 / %s 空间导航可达 %s" % [station_id, action],
				visited.has(action))


func _hotspot_for_action(
		interaction: CabinInteractionController3D,
		action: StringName
) -> InteractionHotspot3D:
	for hotspot in interaction._get_gamepad_candidates():
		if hotspot.get_action_id() == action:
			return hotspot
	return null


func _turn_to(cabin: CabinViewController3D, direction: int) -> void:
	var anchor := cabin.get_node(CabinViewController3D.DIRECTION_ANCHOR_PATHS[direction]) \
			as Marker3D
	cabin._finish_turn(direction, anchor.rotation.y)


func _settle_presentation(stage: MonitorStageController3D, tree: SceneTree) -> void:
	var animation := stage.get_door_visual().get_animation_player()
	if animation.is_playing():
		animation.advance(2.0)
	for frame in 180:
		if not stage.is_presentation_busy():
			break
		await tree.process_frame
	await _frames(tree)


func _has_key(action: StringName, physical_keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == physical_keycode:
			return true
	return false


func _has_button(action: StringName, button_index: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button_index:
			return true
	return false


func _has_axis(action: StringName, axis: JoyAxis, value: float) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis \
				and is_equal_approx(event.axis_value, value):
			return true
	return false


func _push_joypad_button(viewport: Viewport, button_index: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = button_index
		event.pressed = pressed
		viewport.push_input(event, true)


func _release_test_actions() -> void:
	for action in [
		&"focus_left", &"focus_right", &"focus_up", &"focus_down",
		&"context_scroll_up", &"context_scroll_down",
	]:
		Input.action_release(action)


func _frames(tree: SceneTree, count: int = 8) -> void:
	for frame in count:
		await tree.process_frame
