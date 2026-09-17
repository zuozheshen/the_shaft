extends RefCounted
## 使用正式 main_3d 接线和原 Dialogue；只在测试实例中缩短动画等待。

const MAIN := preload("res://scenes/main/main_3d.tscn")


func run(t: Variant, tree: SceneTree) -> void:
	var main := MAIN.instantiate()
	var cabin := main.get_node("三维操作舱") as CabinViewController3D
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	var stage := main.find_child("监控测试摄影棚", true, false) as MonitorStageController3D
	manager.movement_duration_seconds = 0.01
	cabin.turn_duration = 0.05
	stage.boarding_to_threshold_duration = 0.01
	stage.boarding_to_cabin_duration = 0.01
	stage.disembark_to_threshold_duration = 0.01
	stage.disembark_to_outside_duration = 0.01
	stage.disembark_to_exit_duration = 0.01
	t.add_child(main)
	await _frames(tree)
	var router := main.find_child("操作台界面层", true, false) as CabinInterfaceRouter3D
	var console := router.get_main_interface()
	var comm := console.comm_view
	var presentation := main.find_child("主台展示绑定", true, false) as MainConsolePresentation3D
	var interaction := main.find_child("交互控制器", true, false) as CabinInteractionController3D
	var viewport := cabin.get_node("监控渲染系统/监控视口") as SubViewport
	var camera := viewport.get_node("监控摄像机") as Camera3D
	var screen := presentation.get_node(presentation.screen_mesh_path) as MeshInstance3D
	var comm_light := presentation.get_node(presentation.comm_light_path) as Node3D
	var fault := presentation.get_node(presentation.fault_light_path) as Node3D
	var status := presentation.get_node(presentation.status_label_path) as Label3D
	t.assert_equal("主台 / 唯一 ConsoleInterface", 1, main.find_children("ConsoleInterface", "", true, false).size())
	t.assert_equal("主台 / 唯一 DialogueManagerAdapter", 1, main.find_children("DialogueManagerAdapter", "", true, false).size())
	t.assert_equal("主台 / 仅原监控和左台两个视口", 2, main.find_children("*", "SubViewport", true, false).size())
	t.assert_equal("主台 / 监控只有原摄像机", 1, viewport.find_children("*", "Camera3D", true, false).size())
	t.assert_equal("主台 / Mesh 直接使用原 ViewportTexture", viewport.get_texture(),
			(screen.material_override as StandardMaterial3D).albedo_texture)
	t.assert_false("主台 / 旧大面板隐藏", console.get_node("ConsoleLayout").is_visible_in_tree())
	for button: Button in [console.open_door_button, console.close_door_button,
			console.talk_button, console.previous_camera_button, console.next_camera_button,
			console.return_button]:
		t.assert_true("主台 / 旧入口禁用 " + str(button.name),
				not button.is_visible_in_tree() and button.disabled and button.focus_mode == Control.FOCUS_NONE)
	t.assert_true("主台 / 初始通讯与故障灯熄灭", not comm_light.visible and not fault.visible)
	t.assert_equal("主台 / 状态条复用展示数据", console.get_case_phase_display_text(), status.text)
	var microphone := main.find_child("麦克风热点", true, false) as InteractionHotspot3D
	var surface_root := main.find_child("斜台面新增控件根", true, false) as Node3D
	t.assert_true("主台 / 新增控件根精确复用 MIC 斜面 Basis",
			surface_root.transform.basis.is_equal_approx(microphone.transform.basis))
	var microphone_label := microphone.get_node("设备标识") as Label3D
	for device_name in ["CAM01热点", "CAM02热点", "COMM指示灯", "DOOR指示灯", "FAULT指示灯"]:
		var device := surface_root.get_node(device_name) as Node3D
		t.assert_true("主台 / 斜面设备局部旋转归零 " + device_name,
				device.transform.basis.is_equal_approx(Basis.IDENTITY))
		t.assert_true("主台 / 斜面设备落在公共局部平面 " + device_name,
				is_zero_approx(device.position.y))
		var label := device.find_child("标识", true, false) as Label3D
		t.assert_true("主台 / 斜面设备文字与旧控件朝向一致 " + device_name,
				label.global_transform.basis.is_equal_approx(microphone_label.global_transform.basis))
	for camera_name in ["CAM01热点", "CAM02热点"]:
		var camera_hotspot := surface_root.get_node(camera_name) as InteractionHotspot3D
		var collision := camera_hotspot.get_node("CollisionShape3D") as CollisionShape3D
		var base := camera_hotspot.get_node("视觉/底座") as MeshInstance3D
		t.assert_true("主台 / CAM Mesh 与碰撞使用同一斜面 Basis " + camera_name,
				collision.global_transform.basis.is_equal_approx(base.global_transform.basis))
	var cam_01_visual := main.find_child("CAM01热点", true, false).get_node("视觉")
	var cam_02_visual := main.find_child("CAM02热点", true, false).get_node("视觉")
	for part in ["底座", "按钮帽", "选中背光", "悬停高亮"]:
		var first := cam_01_visual.get_node(part) as MeshInstance3D
		var second := cam_02_visual.get_node(part) as MeshInstance3D
		t.assert_true("主台 / CAM 外形和材质可分别编辑 " + part,
				first.mesh != second.mesh and first.mesh.surface_get_material(0) != second.mesh.surface_get_material(0))
	await tree.physics_frame
	for name in ["麦克风热点", "CAM01热点", "CAM02热点", "开门热点", "关门热点"]:
		var hotspot := main.find_child(name, true, false) as InteractionHotspot3D
		var shape := hotspot.get_node("CollisionShape3D") as CollisionShape3D
		var player := cabin.get_node("玩家视角/摄像机旋转轴/玩家摄像机") as Camera3D
		t.assert_equal("主台 / 实体碰撞可射线命中 " + name, hotspot,
				interaction._raycast_hotspot(player.unproject_position(shape.global_position)))

	var phase := manager.get_case_phase()
	for index in [1, 0]:
		_action(main, interaction, "CAM0%d热点" % (index + 1))
		var anchor := cabin.get_node("监控摄影棚定位/监控测试摄影棚/摄像机锚点/" +
				("舱内摄像机锚点" if index == 0 else "门外摄像机锚点")) as Marker3D
		var passenger_anchor := stage.get_node(
				stage.cabin_position_anchor_path if index == 0 else stage.outside_wait_anchor_path
		) as Marker3D
		t.assert_equal("主台 / 实体 CAM 选择 " + str(index), index, console.get_current_camera_index())
		t.assert_true("主台 / 原摄像机跟随机位", camera.global_transform.is_equal_approx(anchor.global_transform))
		t.assert_true("主台 / CAM 平视 " + str(index),
				is_zero_approx(anchor.global_transform.basis.z.y))
		_assert_passenger_framing(t, camera, passenger_anchor.global_position, index)
		t.assert_equal("主台 / CAM 不改变阶段", phase, manager.get_case_phase())
		t.assert_equal("主台 / CAM 背光", index == 0,
				(presentation.get_node(presentation.cam_01_backlight_path) as Node3D).visible)
		t.assert_equal("主台 / CAM02 背光", index == 1,
				(presentation.get_node(presentation.cam_02_backlight_path) as Node3D).visible)
	console.request_select_camera(99)
	t.assert_equal("主台 / 无效机位不改变选择", 0, console.get_current_camera_index())
	t.assert_false("主台 / 无效机位不触发 FAULT", fault.visible)

	# Inspector 的几何布局不能被灯状态和 CAM 切换写回。
	var transform_before := screen.transform.translated(Vector3(0.01, 0.02, 0.0))
	screen.transform = transform_before
	var quad := screen.mesh.duplicate() as QuadMesh
	screen.mesh = quad
	quad.size *= 0.95
	var size_before := quad.size
	_action(main, interaction, "CAM02热点")
	t.assert_true("主台 / 状态刷新保留手调 Transform", screen.transform == transform_before)
	t.assert_equal("主台 / 状态刷新保留手调 Mesh", size_before, quad.size)

	await _test_global_comm(t, tree, cabin, router, console, viewport)
	var destination := router.get_right_interface()
	var completed: Array[StringName] = []
	manager.dispatch_completed.connect(func(result: DispatchResult) -> void:
		completed.append(result.dispatch_id)
	)
	var door_states: Array[int] = []
	stage.door_presentation_state_changed.connect(func(value: int) -> void:
		door_states.append(value)
		_check_door_light(t, presentation, value)
	)
	_check_door_light(t, presentation, stage.get_door_visual().get_door_state())
	for case_number in range(1, 4):
		if not manager.has_active_dispatch():
			t.assert_true("主台 / 三单不提前结束", false)
			break
		var dispatch := manager.get_active_dispatch()
		t.assert_equal("主台 / 三单顺序", StringName("CASE_%03d" % case_number), dispatch.dispatch_id)
		await _travel(destination, manager, String(dispatch.pickup_floor_id), false, tree)
		t.assert_true("主台 / 右台到达接乘点", manager.get_current_floor() == String(dispatch.pickup_floor_id))
		_action(main, interaction, "麦克风热点")
		await _frames(tree)
		t.assert_true("主台 / 实体 MIC 同步 COMM", console.mic_enabled and comm_light.visible)
		if case_number == 1:
			_action(main, interaction, "麦克风热点")
			t.assert_true("主台 / 关闭 MIC 熄灯并收起通讯", not console.mic_enabled
					and not comm_light.visible and comm.is_minimized())
			_action(main, interaction, "麦克风热点")
			await _frames(tree)
			t.assert_true("主台 / 重开 MIC 恢复通讯灯", console.mic_enabled and comm_light.visible)
		await _test_dialogue(t, tree, console, manager)
		_action(main, interaction, "开门热点")
		var door := stage.get_door_visual()
		t.assert_equal("主台 / 实体开门启动 OPENING", ElevatorDoorVisual3D.DoorPresentationState.OPENING, door.get_door_state())
		var animation := door.get_animation_player()
		var animation_position := animation.current_animation_position
		phase = manager.get_case_phase()
		_action(main, interaction, "CAM01热点")
		t.assert_equal("主台 / CAM 不重播门动画", animation_position, animation.current_animation_position)
		t.assert_equal("主台 / CAM 不改登舱阶段", phase, manager.get_case_phase())
		_action(main, interaction, "关门热点")
		t.assert_true("主台 / busy 拒绝有短提示且 FAULT 保持 OFF",
				console.rejection_toast.visible and not fault.visible and manager.is_cabin_door_open())
		animation.advance(2.0)
		var passenger_tween := stage._passenger_movement_tween
		_action(main, interaction, "CAM02热点")
		t.assert_equal("主台 / CAM 保留登舱 Tween", passenger_tween, stage._passenger_movement_tween)
		await _settle(stage, tree)
		t.assert_equal("主台 / 乘客完成登舱", MonitorStageController3D.PassengerPresentationState.CABIN,
				stage.get_passenger_presentation_state())
		_action(main, interaction, "关门热点")
		t.assert_equal("主台 / 实体关门启动 CLOSING", ElevatorDoorVisual3D.DoorPresentationState.CLOSING, door.get_door_state())
		await _settle(stage, tree)
		await _test_dialogue(t, tree, console, manager)
		router.get_left_interface()._show_transcript_tab()
		t.assert_true("主台 / 对话记录仍写入左台", not manager.get_front_dialogue_history().is_empty())
		t.assert_true("主台 / 系统判断仍写入左台", not manager.get_system_message_history().is_empty())
		await _travel(destination, manager, String(dispatch.default_destination_floor_id), true, tree)
		t.assert_equal("主台 / 右台抵达目标", DispatchPhase.ARRIVED_AT_DESTINATION, manager.get_case_phase())
		_action(main, interaction, "开门热点")
		await _frames(tree)
		await _settle(stage, tree)
		t.assert_equal("主台 / 原 DM 完成送达反馈", DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE, manager.get_case_phase())
		t.assert_equal("主台 / 乘客完成离舱", MonitorStageController3D.PassengerPresentationState.EXITED,
				stage.get_passenger_presentation_state())
		_action(main, interaction, "关门热点")
		await _settle(stage, tree)
		t.assert_true("主台 / 换单复位 MIC 和 COMM", not console.mic_enabled and not comm_light.visible)
		t.assert_false("主台 / 三单无虚假 FAULT", fault.visible)
	t.assert_equal("主台 / 三单全部结算", [&"CASE_001", &"CASE_002", &"CASE_003"], completed)
	t.assert_false("主台 / 值班结束", manager.has_active_dispatch())
	t.assert_equal("主台 / 结束后状态条不残留编号", "CASE — · 值班待命", status.text)
	for value in ElevatorDoorVisual3D.DoorPresentationState.values():
		t.assert_true("主台 / 实际门状态覆盖 " + str(value), value in door_states)
	console.toast_timer.timeout.emit()
	t.assert_false("主台 / 短提示到时消失", console.rejection_toast.visible)
	_action(main, interaction, "麦克风热点")
	t.assert_true("主台 / 无派单 MIC 拒绝有提示", console.rejection_toast.visible and not console.mic_enabled)
	t.assert_false("主台 / 无派单拒绝不触发 FAULT", fault.visible)
	main.queue_free()
	await _frames(tree)


func _test_dialogue(t: Variant, tree: SceneTree, console: ConsoleInterface,
		manager: DemoFlowManager) -> void:
	await _frames(tree)
	var comm := console.comm_view
	t.assert_true("COMM / 正式 DM 产生动态选项", not console.dm_choices.is_empty())
	if console.dm_choices.is_empty():
		return
	t.assert_equal("COMM / 正式选项数量不截断", console.dm_choices.size(), comm.choice_container.get_child_count())
	for index in console.dm_choices.size():
		var button := comm.choice_container.get_child(index) as Button
		t.assert_equal("COMM / 动态选项文本与次序", console.dm_choices[index].text, button.text)
		t.assert_equal("COMM / 动态选项允许状态", not bool(console.dm_choices[index].get("is_allowed", true)), button.disabled)
	var adapter := console.dialogue_manager_adapter
	var line := adapter.current_line
	comm.set_minimized(true)
	console._refresh_case_display()
	t.assert_true("COMM / 最小化不改 MIC 或 DM", console.mic_enabled and adapter == console.dialogue_manager_adapter
			and line == adapter.current_line and console.dm_dialogue_started and not console.dm_dialogue_finished)
	comm.set_minimized(false)
	console._refresh_comm_view()
	console._refresh_comm_view()
	var operators_before := _operator_count(manager)
	var button := comm.choice_container.get_child(0) as Button
	button.pressed.emit()
	comm.set_minimized(true)
	await _frames(tree)
	t.assert_equal("COMM / 多次刷新后单击仅一次响应", operators_before + 1, _operator_count(manager))
	t.assert_true("COMM / 普通新台词不抢展开", comm.is_minimized())
	t.assert_true("COMM / 原 DM 推进且当前发言更新", adapter.current_line != line
			and comm.speech_label.text == console.current_passenger_line)


func _test_global_comm(t: Variant, tree: SceneTree, cabin: CabinViewController3D,
		router: CabinInterfaceRouter3D, console: ConsoleInterface, monitor: SubViewport) -> void:
	var comm := console.comm_view
	comm.set_minimized(false)
	comm.move_window_to(Vector2(-200, -200))
	t.assert_true("COMM / 拖动限制左上边界", comm.global_position.x >= 0 and comm.global_position.y >= 0)
	comm.move_window_to(Vector2(100000, 100000))
	await _frames(tree)
	t.assert_true("COMM / 拖动限制右下边界", comm.get_viewport_rect().encloses(comm.get_global_rect()))
	comm.move_window_to(Vector2(28, 100))
	var position_before := comm.global_position
	for direction in [1, 2, 3, 0]:
		cabin._start_turn(1)
		t.assert_true("COMM / 转身中保持全局可见", comm.is_visible_in_tree())
		t.assert_equal("COMM / 转身关闭监控渲染", SubViewport.UPDATE_DISABLED, monitor.render_target_update_mode)
		for frame in 90:
			if not cabin.is_turning():
				break
			await tree.process_frame
		t.assert_equal("COMM / 完成转向", direction, cabin.get_current_direction())
		t.assert_true("COMM / 四朝向保持可见", comm.is_visible_in_tree())
		t.assert_equal("COMM / 转向不重置位置", position_before, comm.global_position)
		t.assert_equal("COMM / 监控仅跟主台朝向", SubViewport.UPDATE_ALWAYS if direction == 0
				else SubViewport.UPDATE_DISABLED, monitor.render_target_update_mode)
		var render_mode := monitor.render_target_update_mode
		comm.set_minimized(true)
		comm.set_minimized(false)
		t.assert_equal("COMM / 收起展开不改变监控启停", render_mode, monitor.render_target_update_mode)
		if direction == 1:
			await _test_left_input(t, tree, cabin, comm)
		if direction == 3:
			t.assert_true("COMM / 右台界面仍可见", router.get_right_interface().is_visible_in_tree())
			await _test_right_input(t, tree, router.get_right_interface(), comm)
	comm.set_minimized(true)
	var blank := comm.global_position + Vector2(10, 170)
	t.assert_false("COMM / 最小化不留下隐形拦截区域", comm.blocks_pointer(blank))
	t.assert_false("COMM / 窗外不拦截鼠标", comm.blocks_pointer(Vector2(1, 1)))
	await _test_resize(t, tree, console)


func _test_left_input(t: Variant, tree: SceneTree, cabin: CabinViewController3D, comm: FloatingCommUI) -> void:
	var left := cabin.get_node("操作台占位/左操作台定位") as LeftTerminalScreen3D
	var player := cabin.get_node("玩家视角/摄像机旋转轴/玩家摄像机") as Camera3D
	var screen := left.get_node(left.screen_mesh_path) as MeshInstance3D
	var pointer := player.unproject_position(screen.global_position)
	await tree.physics_frame
	comm.move_window_to(pointer - Vector2(30, 20))
	await _frames(tree)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	left._input(motion)
	t.assert_false("COMM / 覆盖左台时不转发 hover", left._pointer_inside)
	# 先在无遮挡屏幕按下，再由浮窗覆盖，验证左台 pressed 收尾。
	comm.move_window_to(Vector2(0, 0))
	left._input(motion)
	t.assert_true("COMM / 窗外仍可命中左台", left._pointer_inside)
	var press := InputEventMouseButton.new()
	press.position = pointer
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	left._input(press)
	t.assert_true("COMM / 左台记录已转发按下", MOUSE_BUTTON_LEFT in left._forwarded_buttons)
	comm.move_window_to(pointer - Vector2(30, 20))
	left._input(motion)
	t.assert_true("COMM / 覆盖后清理左台 pressed 与 hover", left._forwarded_buttons.is_empty() and not left._pointer_inside)
	var old_minimized := comm.is_minimized()
	_click(comm.get_viewport(), comm.minimize_button.get_global_rect().get_center())
	await _frames(tree)
	t.assert_equal("COMM / 覆盖左台时 GUI 最小化可点击", not old_minimized, comm.is_minimized())
	comm.set_minimized(false)
	await _frames(tree)
	var before_drag := comm.global_position
	var header_point := comm.title_bar.get_global_rect().get_center()
	_mouse_button(comm.get_viewport(), header_point, true)
	var drag := InputEventMouseMotion.new()
	drag.position = header_point + Vector2(70, 40)
	drag.global_position = drag.position
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	comm.get_viewport().push_input(drag, true)
	_mouse_button(comm.get_viewport(), drag.position, false)
	await _frames(tree)
	t.assert_true("COMM / 标题栏拖动实际移动窗口", comm.global_position != before_drag)
	t.assert_true("COMM / 拖动释放不穿透左台", left._forwarded_buttons.is_empty() and not comm._dragging)
	comm.move_window_to(Vector2(28, 100))


func _test_right_input(t: Variant, tree: SceneTree, right: DestinationControlInterface,
		comm: FloatingCommUI) -> void:
	# 用索引书按钮的实际打开行为验证输入恢复。
	var field := right.open_floor_book_button
	var pointer := field.get_global_rect().get_center()
	field.release_focus()
	comm.move_window_to(pointer - Vector2(30, 90))
	await _frames(tree)
	var received: Array[InputEvent] = []
	var record := func(event: InputEvent) -> void: received.append(event)
	field.gui_input.connect(record)
	_click(comm.get_viewport(), pointer)
	var wheel := InputEventMouseButton.new()
	wheel.position = pointer
	wheel.global_position = pointer
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	comm.get_viewport().push_input(wheel, true)
	# 合成滚轮也要补齐释放，避免测试自身把 GUI 的 mouse focus 留在浮窗。
	wheel = wheel.duplicate()
	wheel.pressed = false
	comm.get_viewport().push_input(wheel, true)
	await _frames(tree)
	t.assert_true("COMM / 覆盖右台时点击和滚轮不穿透",
			received.is_empty() and not right.floor_book_page.is_visible_in_tree())
	comm.move_window_to(Vector2(0, 0))
	await _frames(tree)
	_click(comm.get_viewport(), pointer)
	await _frames(tree)
	t.assert_true("COMM / 移开后右台按钮实际打开索引书",
			not received.is_empty() and right.floor_book_page.is_visible_in_tree())
	right.close_floor_book_button.pressed.emit()
	field.gui_input.disconnect(record)
	field.release_focus()
	comm.move_window_to(Vector2(28, 100))


func _click(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		_mouse_button(viewport, position, pressed)


func _mouse_button(viewport: Viewport, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	viewport.push_input(event, true)


func _test_resize(t: Variant, tree: SceneTree, console: ConsoleInterface) -> void:
	# 临时纯 2D 视口仅测窗口布局，不属于正式监控场景，也不创建业务状态。
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(640, 360)
	console.add_child(viewport)
	var window := preload("res://scenes/ui/FloatingCommUI.tscn").instantiate() as FloatingCommUI
	viewport.add_child(window)
	window.set_minimized(false)
	await _frames(tree)
	window.move_window_to(Vector2(900, 900))
	viewport.size = Vector2i(320, 180)
	await _frames(tree)
	t.assert_true("COMM / viewport 缩小时完整窗口仍在边界内",
			Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(window.get_global_rect()))
	window.set_minimized(true)
	await _frames(tree)
	t.assert_true("COMM / 小视口仍可收起",
			window.size.y < window.expanded_size.y and window.size.x <= viewport.size.x)
	viewport.queue_free()
	await _frames(tree)


func _assert_passenger_framing(t: Variant, camera: Camera3D,
		passenger_position: Vector3, camera_index: int) -> void:
	# 1.47m 覆盖三个 Profile 的最大 Y 缩放及待机起伏；只校验留在画面内，
	# 最终构图和观感仍由 Godot 人工视觉验收决定。
	var frame_size := Vector2(camera.get_viewport().get_visible_rect().size)
	var feet := camera.unproject_position(passenger_position)
	var head := camera.unproject_position(passenger_position + Vector3.UP * 1.47)
	var center := camera.unproject_position(passenger_position + Vector3.UP * 0.74)
	t.assert_true("主台 / CAM 人物完整入画 " + str(camera_index),
			head.y >= 4.0 and feet.y <= frame_size.y - 4.0 and head.y < feet.y)
	t.assert_true("主台 / CAM 人物位于中央附近 " + str(camera_index),
			absf(center.x - frame_size.x * 0.5) <= frame_size.x * 0.1
			and absf(center.y - frame_size.y * 0.5) <= frame_size.y * 0.15)


func _action(main: Node, interaction: CabinInteractionController3D, hotspot_name: String) -> void:
	var hotspot := main.find_child(hotspot_name, true, false) as InteractionHotspot3D
	interaction._execute_action(hotspot.get_action_id())


func _operator_count(manager: DemoFlowManager) -> int:
	var count: int = 0
	for text in manager.get_front_dialogue_history():
		if text.begins_with("操作员："):
			count += 1
	return count


func _check_door_light(t: Variant, presentation: MainConsolePresentation3D, state: int) -> void:
	var expected := presentation.door_moving_material
	if state == ElevatorDoorVisual3D.DoorPresentationState.CLOSED:
		expected = presentation.door_closed_material
	elif state == ElevatorDoorVisual3D.DoorPresentationState.OPEN:
		expected = presentation.door_open_material
	var lamp := presentation.get_node(presentation.door_light_path) as MeshInstance3D
	t.assert_equal("主台 / DOOR 跟随真实四态 " + str(state), expected, lamp.material_override)


func _travel(destination: DestinationControlInterface, manager: DemoFlowManager,
		floor: String, validate: bool, tree: SceneTree) -> void:
	destination.manual_destination_line_edit.text = floor
	if validate:
		destination._verify_destination()
	destination._submit_destination()
	for frame in 180:
		if not manager.is_elevator_moving():
			break
		await tree.process_frame
	await _frames(tree)


func _settle(stage: MonitorStageController3D, tree: SceneTree) -> void:
	var animation := stage.get_door_visual().get_animation_player()
	if animation.is_playing():
		animation.advance(2.0)
	for frame in 180:
		if not stage.is_door_presentation_busy() and not stage.is_passenger_presentation_busy():
			break
		await tree.process_frame
	await _frames(tree)


func _frames(tree: SceneTree, count: int = 8) -> void:
	for frame in count:
		await tree.process_frame
