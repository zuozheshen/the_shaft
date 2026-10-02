extends RefCounted
## 使用正式 main_3d 接线和原 Dialogue；只在测试实例中缩短动画等待。

const MAIN := preload("res://scenes/main/main_3d.tscn")
const ConsoleButtonVisualScript := preload("res://scripts/presentation/console_button_visual_3d.gd")


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
	t.assert_equal("主台 / 原监控、左台及楼层书两页共四个视口", 4, main.find_children("*", "SubViewport", true, false).size())
	t.assert_equal("主台 / 监控只有原摄像机", 1, viewport.find_children("*", "Camera3D", true, false).size())
	t.assert_equal("主台 / Mesh 直接使用原 ViewportTexture", viewport.get_texture(),
			(screen.material_override as StandardMaterial3D).albedo_texture)
	t.assert_false("主台 / 旧大面板已移除", console.has_node("ConsoleLayout"))
	t.assert_equal("主台 / 只保留 COMM 的实际按钮", comm.find_children("*", "Button", true, false).size(),
			console.find_children("*", "Button", true, false).size())
	t.assert_true("主台 / 初始通讯与故障灯熄灭", not comm_light.visible and not fault.visible)
	t.assert_equal("主台 / 状态条复用展示数据", console.get_case_phase_display_text(), status.text)
	var microphone := main.find_child("麦克风热点", true, false) as InteractionHotspot3D
	var surface_root := main.find_child("斜台面新增控件根", true, false) as Node3D
	t.assert_true("主台 / 新增控件根精确复用 MIC 斜面 Basis",
			surface_root.transform.basis.is_equal_approx(microphone.transform.basis))
	var microphone_label := microphone.get_node("设备标识") as Label3D
	t.assert_false("主台 / 大号 MIC 标识不再显示", microphone_label.visible)
	for device_name in ["CAM01热点", "CAM02热点", "COMM指示灯", "DOOR指示灯", "FAULT指示灯"]:
		var device := surface_root.get_node(device_name) as Node3D
		t.assert_true("主台 / 斜面设备局部旋转归零 " + device_name,
				device.transform.basis.is_equal_approx(Basis.IDENTITY))
		# 指示灯可按台面和控件体积避让；CAM 热点仍保持原来的公共局部平面。
		if device_name in ["CAM01热点", "CAM02热点"]:
			t.assert_true("主台 / 斜面设备落在公共局部平面 " + device_name,
					is_zero_approx(device.position.y))
		var label := device.find_child("标识", true, false) as Label3D
		t.assert_true("主台 / 斜面设备文字与旧控件朝向一致 " + device_name,
				label.global_transform.basis.is_equal_approx(microphone_label.global_transform.basis))
	for camera_name in ["CAM01热点", "CAM02热点"]:
		var camera_hotspot := surface_root.get_node(camera_name) as InteractionHotspot3D
		var collision := camera_hotspot.get_node("CollisionShape3D") as CollisionShape3D
		var visual := camera_hotspot.get_node("视觉/方形按钮") as Node3D
		t.assert_true("主台 / CAM 外形与碰撞使用同一斜面朝向 " + camera_name,
				collision.global_transform.basis.orthonormalized().is_equal_approx(
					visual.global_transform.basis.orthonormalized()))
	var cam_01 := surface_root.get_node("CAM01热点") as InteractionHotspot3D
	var cam_02 := surface_root.get_node("CAM02热点") as InteractionHotspot3D
	_assert_shared_button_meshes(t, cam_01.get_node("视觉/方形按钮"),
			cam_02.get_node("视觉/方形按钮"), "CAM")
	var cam_01_label := cam_01.find_child("标识", true, false) as Label3D
	var cam_02_label := cam_02.find_child("标识", true, false) as Label3D
	t.assert_true("主台 / 共用 CAM 外形仍保留独立标识",
			cam_01_label != cam_02_label and cam_01_label.text != cam_02_label.text)
	for camera_hotspot in [cam_01, cam_02]:
		var marker := camera_hotspot.get_node("交互反馈/选中背光") as Node3D
		t.assert_true("主台 / CAM 原选中路径不再显示下方横条",
				not marker is MeshInstance3D
				and marker.find_children("*", "MeshInstance3D", true, false).is_empty())
	for part in ["交互反馈/悬停高亮"]:
		var first := cam_01.get_node(part) as MeshInstance3D
		var second := cam_02.get_node(part) as MeshInstance3D
		t.assert_true("主台 / CAM 原有反馈保持独立 " + part,
				first.mesh != second.mesh and first.mesh.surface_get_material(0) != second.mesh.surface_get_material(0))
	var open_button := main.find_child("开门热点", true, false).get_node("开门视觉/大型按钮")
	var close_button := main.find_child("关门热点", true, false).get_node("关门视觉/大型按钮")
	_assert_shared_button_meshes(t, open_button, close_button, "DOOR")
	var open_caps := open_button.get_node("按钮按压轴/按钮帽模型").find_children("*", "MeshInstance3D", true, false)
	var close_caps := close_button.get_node("按钮按压轴/按钮帽模型").find_children("*", "MeshInstance3D", true, false)
	var distinct_door_colors := false
	for index in mini(open_caps.size(), close_caps.size()):
		var open_material := (open_caps[index] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		var close_material := (close_caps[index] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if open_material != null and close_material != null:
			distinct_door_colors = distinct_door_colors or open_material.albedo_color != close_material.albedo_color
	t.assert_true("主台 / 共用门按钮几何仍区分 OPEN 和 CLOSE 颜色", distinct_door_colors)
	await tree.physics_frame
	for name in ["麦克风热点", "CAM01热点", "CAM02热点", "开门热点", "关门热点"]:
		var hotspot := main.find_child(name, true, false) as InteractionHotspot3D
		var shape := hotspot.get_node("CollisionShape3D") as CollisionShape3D
		var player := cabin.get_node("玩家视角/摄像机旋转轴/玩家摄像机") as Camera3D
		t.assert_equal("主台 / 实体碰撞可射线命中 " + name, hotspot,
				interaction._raycast_hotspot(player.unproject_position(shape.global_position)))

	await _test_button_feedback(t, tree, main, interaction, console, manager)
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
		if index == 1:
			var door := stage.get_door_visual()
			var door_leaf := door.get_node(
					"门扇根/左门扇动画根/左门扇"
			) as MeshInstance3D
			var door_half_depth := (door_leaf.mesh as BoxMesh).size.z * 0.5
			t.assert_true("主台 / CAM02 位于关闭门扇外侧",
					door.to_local(anchor.global_position).z < -door_half_depth)
		t.assert_equal("主台 / CAM 不改变阶段", phase, manager.get_case_phase())
		t.assert_equal("主台 / CAM 原选择标记", index == 0,
				(presentation.get_node(presentation.cam_01_backlight_path) as Node3D).visible)
		t.assert_equal("主台 / CAM02 原选择标记", index == 1,
				(presentation.get_node(presentation.cam_02_backlight_path) as Node3D).visible)
		_assert_camera_cap_selection(t,
				(cam_01 if index == 0 else cam_02).get_node("视觉/方形按钮"),
				(cam_02 if index == 0 else cam_01).get_node("视觉/方形按钮"), index)
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

	await _test_global_comm(t, tree, cabin, router, console, interaction, viewport)
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
	await _test_visual_replacement(t, tree)


func _assert_shared_button_meshes(t: Variant, first: Node3D, second: Node3D, label: String) -> void:
	t.assert_true("主台 / " + label + " 复用同一按钮场景",
			not first.scene_file_path.is_empty() and first.scene_file_path == second.scene_file_path)
	# 只读稳定 wrapper；不把 GLB 的内部对象名变成接线契约。
	for part in ["固定安装框", "按钮按压轴/按钮帽模型"]:
		var first_meshes := first.get_node(part).find_children("*", "MeshInstance3D", true, false)
		var second_meshes := second.get_node(part).find_children("*", "MeshInstance3D", true, false)
		t.assert_true("主台 / " + label + " 共用部件存在 " + part, not first_meshes.is_empty())
		t.assert_equal("主台 / " + label + " 共用部件 Mesh 数量 " + part,
				first_meshes.size(), second_meshes.size())
		for index in mini(first_meshes.size(), second_meshes.size()):
			t.assert_equal("主台 / " + label + " 共用 Mesh " + part + str(index),
					(first_meshes[index] as MeshInstance3D).mesh,
					(second_meshes[index] as MeshInstance3D).mesh)


func _assert_camera_cap_selection(t: Variant, selected: Node3D, unselected: Node3D,
		camera_index: int) -> void:
	# 从 Godot 自有帽 mount 读取实际材质，不把 GLB 内部对象名当成业务契约。
	var selected_caps := selected.get_node("按钮按压轴/按钮帽模型").find_children(
			"*", "MeshInstance3D", true, false)
	var unselected_caps := unselected.get_node("按钮按压轴/按钮帽模型").find_children(
			"*", "MeshInstance3D", true, false)
	t.assert_true("主台 / CAM 选择显示在实际按钮帽 " + str(camera_index),
			not selected_caps.is_empty() and not unselected_caps.is_empty())
	if selected_caps.is_empty() or unselected_caps.is_empty():
		return
	var lit := (selected_caps[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	var dark := (unselected_caps[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	t.assert_true("主台 / CAM 帽选择使用独立可配置材质", lit != null and dark != null and lit != dark)
	if lit == null or dark == null:
		return
	var lit_color := lit.albedo_color
	var dark_color := dark.albedo_color
	t.assert_true("主台 / 所选 CAM 帽比另一帽更亮 " + str(camera_index),
			lit_color.r + lit_color.g + lit_color.b > dark_color.r + dark_color.g + dark_color.b)
	t.assert_true("主台 / 所选 CAM 帽内部发光，未选中帽保持暗态 " + str(camera_index),
			lit.emission_enabled and lit.emission_energy_multiplier > 0.0
			and lit.emission.r + lit.emission.g + lit.emission.b > 0.0 and not dark.emission_enabled)


func _test_button_feedback(t: Variant, tree: SceneTree, main: Node,
		interaction: CabinInteractionController3D, console: ConsoleInterface,
		manager: DemoFlowManager) -> void:
	var mounts := {
		"CAM01热点": "视觉/方形按钮", "CAM02热点": "视觉/方形按钮",
		"开门热点": "开门视觉/大型按钮", "关门热点": "关门视觉/大型按钮",
	}
	var buttons: Array[ConsoleButtonVisualScript] = []
	var rest_positions: Array[Vector3] = []
	var initial_wait := 0.0
	for hotspot_name: String in mounts:
		var button := main.find_child(hotspot_name, true, false).get_node(mounts[hotspot_name]) as ConsoleButtonVisualScript
		buttons.append(button)
		rest_positions.append((button.get_node(button.press_axis_path) as Node3D).position)
		initial_wait = maxf(initial_wait, button.press_down_duration + button.press_return_duration)
	await tree.create_timer(initial_wait + 0.05).timeout
	var phase_before := manager.get_case_phase()
	var camera_before := console.get_current_camera_index()
	var index := 0
	for hotspot_name: String in mounts:
		var button := buttons[index]
		var axis := button.get_node(button.press_axis_path) as Node3D
		var frame := button.get_node("固定安装框") as Node3D
		var hotspot := main.find_child(hotspot_name, true, false) as InteractionHotspot3D
		var collision := hotspot.get_node("CollisionShape3D") as CollisionShape3D
		var frame_before := frame.global_transform
		var hotspot_before := hotspot.global_transform
		var collision_before := collision.global_transform
		var action_before := hotspot.get_action_id()
		var label := button.find_child(
				"设备标识" if hotspot_name in ["开门热点", "关门热点"] else "标识", true, false) as Label3D
		var label_before := label.global_transform if label != null else Transform3D.IDENTITY
		t.assert_true("按压 / 功能文字属于固定铭牌 " + hotspot_name,
				label != null and not axis.is_ancestor_of(label)
				and axis.find_children("*", "Label3D", true, false).is_empty())
		# 验证适配后帽的实际投影仍命中原热点，而不是只点击碰撞中心。
		var cap_mesh := axis.get_node("按钮帽模型").find_children(
				"*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var cap_center := cap_mesh.global_transform * cap_mesh.mesh.get_aabb().get_center()
		var player := main.find_child("玩家摄像机", true, false) as Camera3D
		t.assert_equal("按压 / 实际按钮帽仍命中原热点 " + hotspot_name,
				hotspot, interaction._raycast_hotspot(player.unproject_position(cap_center)))
		var rest := rest_positions[index]
		t.assert_true("按压 / 初始静止 " + hotspot_name, axis.position.is_equal_approx(rest))
		button.play_press()
		await tree.create_timer(button.press_down_duration * 0.5).timeout
		t.assert_true("按压 / 只有稳定轴沿局部法线下沉 " + hotspot_name,
				axis.position.y < rest.y and is_equal_approx(axis.position.x, rest.x)
				and is_equal_approx(axis.position.z, rest.z))
		t.assert_true("按压 / 安装框、热点、碰撞及 action 保持不变 " + hotspot_name,
				frame.global_transform.is_equal_approx(frame_before)
				and hotspot.global_transform.is_equal_approx(hotspot_before)
				and collision.global_transform.is_equal_approx(collision_before)
				and hotspot.get_action_id() == action_before)
		t.assert_true("按压 / 面板铭牌文字保持静止 " + hotspot_name,
				label != null and label.global_transform.is_equal_approx(label_before))
		# 连续按压覆盖正在执行的 Tween，返回初始姿态而非累加位移。
		button.play_press()
		button.play_press()
		await tree.create_timer(button.press_down_duration + button.press_return_duration + 0.05).timeout
		t.assert_true("按压 / 连续按压无漂移并自动回位 " + hotspot_name,
				axis.position.is_equal_approx(rest))
		t.assert_true("按压 / 视觉调用不改变业务 " + hotspot_name,
				manager.get_case_phase() == phase_before and console.get_current_camera_index() == camera_before)
		index += 1
	var cam_02 := buttons[1]
	var cam_02_axis := cam_02.get_node(cam_02.press_axis_path) as Node3D
	_action(main, interaction, "CAM02热点")
	await tree.create_timer(cam_02.press_down_duration * 0.5).timeout
	t.assert_true("按压 / 正式 CAM 选择触发视觉反馈", cam_02_axis.position.y < rest_positions[1].y)
	await tree.create_timer(cam_02.press_down_duration + cam_02.press_return_duration + 0.05).timeout
	_action(main, interaction, "CAM01热点")
	cam_02.feedback_enabled = false
	_action(main, interaction, "CAM02热点")
	await tree.create_timer(cam_02.press_down_duration + cam_02.press_return_duration + 0.05).timeout
	t.assert_true("按压 / 禁用视觉反馈仍正常切换 CAM",
			cam_02_axis.position.is_equal_approx(rest_positions[1])
			and console.get_current_camera_index() == 1 and manager.get_case_phase() == phase_before)
	cam_02.feedback_enabled = true
	_action(main, interaction, "CAM01热点")
	await tree.create_timer(buttons[0].press_down_duration + buttons[0].press_return_duration + 0.05).timeout

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
		router: CabinInterfaceRouter3D, console: ConsoleInterface,
		interaction: CabinInteractionController3D, monitor: SubViewport) -> void:
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
			t.assert_false("COMM / 右台旧界面保持隐藏",
				router.find_child("右操作台界面容器", true, false).visible)
			await _test_right_input(t, tree, cabin, interaction, comm)
	comm.set_minimized(true)
	var blank := comm.global_position + Vector2(10, 170)
	t.assert_false("COMM / 最小化不留下隐形拦截区域", comm.blocks_pointer(blank))
	t.assert_false("COMM / 窗外不拦截鼠标", comm.blocks_pointer(Vector2(1, 1)))
	await _test_resize(t, tree, console)


func _test_left_input(t: Variant, tree: SceneTree, cabin: CabinViewController3D, comm: FloatingCommUI) -> void:
	var interaction := cabin.get_node("交互控制器") as CabinInteractionController3D
	var key := cabin.get_node(
		"操作台占位/左操作台定位/栏目控制区/乘客档案"
	) as InteractionHotspot3D
	var shape := key.get_node("CollisionShape3D") as CollisionShape3D
	var player := cabin.get_node("玩家视角/摄像机旋转轴/玩家摄像机") as Camera3D
	var pointer := player.unproject_position(shape.global_position)
	await tree.physics_frame
	t.assert_equal("COMM / 左台实体键射线可命中", key,
			interaction._raycast_hotspot(pointer))
	comm.move_window_to(pointer - Vector2(30, 70))
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	motion.global_position = pointer
	comm.get_viewport().push_input(motion, true)
	await _frames(tree)
	interaction._update_hovered_hotspot()
	t.assert_true("COMM / 覆盖左台时阻止实体热点",
			interaction._is_pointer_over_blocking_gui()
			and interaction._hovered_hotspot == null)
	comm.move_window_to(Vector2(0, 0))
	comm.get_viewport().push_input(motion, true)
	await _frames(tree)
	t.assert_true("COMM / 移开后不遮挡左台实体键", not comm.blocks_pointer(pointer))
	t.assert_equal("COMM / 移开后左台实体键仍可射线命中", key,
			interaction._raycast_hotspot(pointer))
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
	t.assert_true("COMM / 拖动释放不穿透左台", not comm._dragging)
	interaction._clear_hovered_hotspot()
	comm.move_window_to(Vector2(28, 100))


func _test_right_input(t: Variant, tree: SceneTree, cabin: CabinViewController3D,
		interaction: CabinInteractionController3D, comm: FloatingCommUI) -> void:
	var key := cabin.get_node(
		"操作台占位/右操作台定位/数字键盘/数字5"
	) as InteractionHotspot3D
	var shape := key.get_node("CollisionShape3D") as CollisionShape3D
	var player := cabin.get_node(
		"玩家视角/摄像机旋转轴/玩家摄像机"
	) as Camera3D
	var pointer := player.unproject_position(shape.global_position)
	await tree.physics_frame
	t.assert_equal("COMM / 右台实体键射线可命中", key,
			interaction._raycast_hotspot(pointer))
	comm.move_window_to(pointer - Vector2(30, 70))
	var motion := InputEventMouseMotion.new()
	motion.position = pointer
	motion.global_position = pointer
	comm.get_viewport().push_input(motion, true)
	await _frames(tree)
	interaction._update_hovered_hotspot()
	t.assert_true("COMM / 覆盖右台时阻止实体热点",
			interaction._is_pointer_over_blocking_gui()
			and interaction._hovered_hotspot == null)
	comm.move_window_to(Vector2(0, 0))
	comm.get_viewport().push_input(motion, true)
	await _frames(tree)
	t.assert_true("COMM / 移开后不遮挡右台实体键", not comm.blocks_pointer(pointer))
	t.assert_equal("COMM / 移开后右台实体键仍可射线命中", key,
			interaction._raycast_hotspot(pointer))
	interaction._clear_hovered_hotspot()
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
	destination.clear_destination_input()
	for digit: String in floor:
		destination.append_destination_digit(digit)
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

# 把所有台体/按钮/轴外形换成不同内部结构，证明业务不读取模型子节点。
func _test_visual_replacement(t: Variant, tree: SceneTree) -> void:
	var main := MAIN.instantiate()
	var mounts := main.find_children("视觉资产", "Node3D", true, false)
	for part_name in ["麦克风视觉", "开门视觉", "关门视觉"]:
		mounts.append(main.find_child(part_name, true, false))
	for camera_name in ["CAM01热点", "CAM02热点"]:
		var button := main.find_child(camera_name, true, false).get_node("视觉/方形按钮") as ConsoleButtonVisualScript
		# 保留可选脚本但替换全部内部外形，同时覆盖空路径和不存在的按压轴。
		button.press_axis_path = NodePath("") if camera_name == "CAM01热点" else NodePath("不存在的按压轴")
		mounts.append(button)
	for mount: Node3D in mounts:
		for child: Node in mount.get_children():
			mount.remove_child(child)
			child.free()
		var replacement := MeshInstance3D.new()
		replacement.name = "不同内部外形"
		replacement.mesh = BoxMesh.new()
		mount.add_child(replacement)
	t.add_child(main)
	await _frames(tree)
	var cabin := main.get_node("三维操作舱") as CabinViewController3D
	var router := main.find_child("操作台界面层", true, false) as CabinInterfaceRouter3D
	var interaction := main.find_child("交互控制器", true, false) as CabinInteractionController3D
	var console := router.get_main_interface()
	var destination := router.get_right_interface()
	var presentation := main.find_child("主台展示绑定", true, false) as MainConsolePresentation3D
	var viewport := cabin.get_node("监控渲染系统/监控视口") as SubViewport
	t.assert_true("美术解耦 / 三台存在可替换外形", mounts.size() > 15)
	for hotspot: InteractionHotspot3D in main.find_children("*", "Area3D", true, false):
		if hotspot is InteractionHotspot3D:
			t.assert_equal("美术解耦 / 热点碰撞保留 " + str(hotspot.get_action_id()), 1,
					hotspot.find_children("*", "CollisionShape3D", false, false).size())
	interaction._execute_action(&"select_camera_01")
	t.assert_equal("美术解耦 / 空按压轴不阻断 CAM 命令", 0, console.get_current_camera_index())
	interaction._execute_action(&"select_camera_02")
	t.assert_equal("美术解耦 / CAM 命令不依赖内部外形", 1, console.get_current_camera_index())
	interaction._execute_action(&"destination_digit_0")
	interaction._execute_action(&"destination_digit_0")
	interaction._execute_action(&"destination_digit_4")
	interaction._execute_action(&"destination_verify")
	t.assert_equal("美术解耦 / 数字与验证仍保留前导零", "004",
			str(destination.get_destination_presentation().validated_floor))
	t.assert_equal("美术解耦 / 动态屏继续使用原视口纹理", viewport.get_texture(),
			(presentation.get_node(presentation.screen_mesh_path).material_override as StandardMaterial3D).albedo_texture)
	var wheel := main.find_child("左操作台定位", true, false) as LeftTerminalScreen3D
	var axis := wheel.get_node(wheel.scroll_wheel_visual_path) as Node3D
	var rotation_before := axis.rotation
	wheel.rotate_scroll_wheel(1)
	t.assert_false("美术解耦 / 新滚轮外形由稳定轴驱动", axis.rotation.is_equal_approx(rotation_before))
	var right := main.find_child("右台展示绑定", true, false) as RightConsolePresentation3D
	t.assert_true("美术解耦 / 执行拨杆轴保留", right.get_node(right.lever_pivot_path) is Node3D)
	interaction._execute_action(&"left_passenger_record")
	t.assert_equal("美术解耦 / 左台栏目命令保留", BuildingTerminalInterface.Section.PASSENGER_RECORD,
			router.get_left_interface().get_current_section())
	main.queue_free()
	await _frames(tree)
