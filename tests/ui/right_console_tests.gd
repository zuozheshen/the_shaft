extends RefCounted

const TestContent := preload("res://tests/fixtures/runtime/test_content.gd")
## 使用正式 main_3d 验证右台实体入口仍复用唯一 DestinationControlInterface。

const Archives := preload("res://tests/fixtures/runtime/test_right_lookup_documents.gd")
const MAIN := preload("res://scenes/main/main_3d.tscn")


func run(t: Variant, tree: SceneTree) -> void:
	var case := ContentRegistry.get_dispatch("TEST_CASE_001")
	var saved_documents := case.documents.duplicate()
	case.documents.append(Archives.document(&"004"))
	var blocked := Archives.install_blocked_floor()
	var main := MAIN.instantiate()
	TestContent.prepare_scene(main)
	t.add_child(main)
	await _frames(tree)
	var cabin := main.get_node("三维操作舱") as CabinViewController3D
	var router := main.find_child("操作台界面层", true, false) as CabinInterfaceRouter3D
	var destination := router.get_right_interface()
	var interaction := main.find_child(
		"交互控制器", true, false
	) as CabinInteractionController3D
	var presentation := main.find_child(
		"右台展示绑定", true, false
	) as RightConsolePresentation3D
	var right_root := cabin.get_node("操作台占位/右操作台定位") as Node3D
	var legacy_container := router.find_child(
		"右操作台界面容器", true, false
	) as Control

	t.assert_false("右台 / 旧 2D 覆盖入口隐藏", legacy_container.visible)
	t.assert_equal("右台 / 旧 LineEdit 已移除", 0, destination.find_children("*", "LineEdit", true, false).size())
	t.assert_equal("右台 / 旧推荐和提交按钮已移除", 0, destination.find_children("*", "Button", true, false).size())

	var expected_actions: Array[String] = [
		"destination_digit_1", "destination_digit_2", "destination_digit_3",
		"destination_digit_4", "destination_digit_5", "destination_digit_6",
		"destination_digit_7", "destination_digit_8", "destination_digit_9",
		"destination_clear", "destination_digit_0", "destination_backspace",
	]
	var key_names: Array[String] = [
		"数字1", "数字2", "数字3", "数字4", "数字5", "数字6",
		"数字7", "数字8", "数字9", "清空", "数字0", "退格",
	]
	# 紧凑布局必须在正式FOV70投影下命中各键；只读射线不改业务。
	cabin._start_turn(-1)
	await tree.create_timer(cabin.turn_duration + 0.05).timeout
	var camera := cabin.get_node(
			"玩家视角/摄像机旋转轴/玩家摄像机"
	) as Camera3D
	for index in key_names.size():
		var key := right_root.get_node("数字键盘/" + key_names[index]) \
				as InteractionHotspot3D
		var collision := key.get_node("CollisionShape3D") as CollisionShape3D
		var cap := key.get_node("视觉资产/按钮帽") as Node3D
		t.assert_equal("右台 / 4x3 动作映射 " + key_names[index],
				StringName(expected_actions[index]), key.get_action_id())
		t.assert_equal("右台 / 热点属于右台 " + key_names[index],
				&"right_console", key.get_station_id())
		t.assert_true("右台 / 视觉实例与碰撞跟随同一按键根 " + key_names[index],
				collision.global_transform.basis.is_equal_approx(
					cap.global_transform.basis
				))

		for local_point: Vector3 in [
			Vector3.ZERO, Vector3(-0.034, -0.06, -0.09),
			Vector3(-0.034, 0.06, 0.09),
		]:
			t.assert_equal("右台 / 紧凑键中心和边缘射线 " + key_names[index]
					+ str(local_point), key, interaction._raycast_hotspot(
						camera.unproject_position(key.to_global(local_point))
					))
	var verify := right_root.get_node(
			"数字显示组/验证楼层热点"
	) as InteractionHotspot3D
	t.assert_equal("右台 / 新核验模块 VERIFY 射线", verify,
			interaction._raycast_hotspot(camera.unproject_position(verify.global_position)))
	for digit in range(10):
		destination.clear_destination_input()
		interaction._execute_action(StringName("destination_digit_" + str(digit)))
		t.assert_equal("右台 / 每个数字输入 %d" % digit, str(digit),
				str(destination.get_destination_presentation().input))

	destination.clear_destination_input()
	for action: StringName in [
		&"destination_digit_0", &"destination_digit_0", &"destination_digit_4",
	]:
		interaction._execute_action(action)
	await _frames(tree, 2)
	t.assert_equal("右台 / 实体数字键复用原输入并保留 004", "004",
			str(destination.get_destination_presentation().input))
	t.assert_equal("右台 / LCD 读取同一字符串", "004",
			(presentation.get_node(presentation.input_label_path) as Label).text)
	var manager := destination.demo_flow_manager
	var session := manager.get_document_session_id()
	var terminal := main.find_child("核验终端", true, false) as VerificationTerminal3D
	var information := presentation.get_node(presentation.information_label_path) as Label
	var source := presentation.get_node(presentation.source_label_path) as Label
	var current := presentation.get_node(presentation.current_floor_label_path) as Label
	var target := presentation.get_node(presentation.execution_target_label_path) as Label
	var feedback := presentation.get_node(presentation.feedback_label_path) as Label
	var information_viewport := presentation.get_node(presentation.information_viewport_path) as SubViewport
	var input_viewport := presentation.get_node(presentation.input_viewport_path) as SubViewport
	var information_surface := presentation.get_node(presentation.information_screen_path) as ScreenSurface3D
	var input_surface := presentation.get_node(presentation.input_screen_path) as ScreenSurface3D
	var information_material := information_surface.material_override as StandardMaterial3D
	var input_material := input_surface.material_override as StandardMaterial3D
	t.assert_true("右台 / 摘要与数字分别绑定独立屏面和真实视口纹理",
			information_material != input_material
			and information_material.albedo_texture == information_viewport.get_texture()
			and input_material.albedo_texture == input_viewport.get_texture())
	var snapshot := destination.get_destination_presentation()
	t.assert_equal("右台 / 自动查询完整编号", "004", snapshot.query_floor)
	t.assert_true("右台 / 摘要显示当前功能、停靠、来源和日期",
		"设备维护" in information.text and "支持停靠" in information.text
		and "设施档案" in source.text and "2026-01-01" in source.text)
	t.assert_true("右台 / 摘要的末行与反馈区不重叠",
			information.position.y + information.get_minimum_size().y <= source.position.y
			and source.position.y + source.get_minimum_size().y <= feedback.position.y)
	t.assert_equal("右台 / 独立读数使用实际当前位置", snapshot.current_floor, current.text)
	t.assert_equal("右台 / 执行目标不等于查询号码", snapshot.execution_target, target.text)
	t.assert_equal("右台 / 无操作反馈时显示真实停靠状态", "已停靠", feedback.text)
	t.assert_true("右台 / 摘要不暗示推荐、行政批准或历史安全",
		"系统推荐" not in information.text and "须出示" in information.text
		and "物资周转" not in information.text and "获准" not in information.text)
	t.assert_equal("右台 / 查询本身不取得资料", 0, manager.get_acquired_documents(session).size())
	t.assert_true("右台 / 反馈位于实际摘要视口", information_viewport.is_ancestor_of(feedback))

	interaction._execute_action(&"destination_digit_7")
	t.assert_equal("右台 / 未知输入撤销旧查询", "unknown", destination.get_destination_presentation().query_status)
	interaction._execute_action(&"destination_verify")
	t.assert_equal("右台 / 未知输入不得取得 A", 0, manager.get_acquired_documents(session).size())
	t.assert_true("右台 / 未知地址与操作反馈同时显示",
			"未知地址" in information.text and "完整楼层编号" in feedback.text)
	interaction._execute_action(&"destination_backspace")
	interaction._execute_action(&"destination_verify")
	var first_ref := {"document_id": "right/floor/004", "version": 1}
	var receipt := manager.get_acquired_document(session, first_ref)
	t.assert_equal("右台 / 实体键经 right 渠道取得精确档案", "right", receipt.get("route"))
	t.assert_true("右台 / 实体键打开 W", terminal.target_open)
	t.assert_true("右台 / W 档案包含历史字段与来源",
		receipt.get("document", {}).get("fields", {}).has("historical_function")
		and receipt.get("document", {}).get("source", {}).get("source_version") == "1")
	await _close_workspace(terminal, tree)
	var initial_events := manager.get_document_events(session).size()
	case.documents.append(Archives.document(&"004", 2))
	interaction._execute_action(&"destination_verify")
	t.assert_equal("右台 / 源更新时不静默取得新版本", initial_events, manager.get_document_events(session).size())
	t.assert_equal("右台 / 源更新刷新摘要", "设施检修", destination.get_destination_presentation().current_function)
	interaction._execute_action(&"destination_verify")
	t.assert_equal("右台 / 再次按键取得 v2", "right",
		manager.get_acquired_document(session, {"document_id": "right/floor/004", "version": 2}).get("route"))
	await _close_workspace(terminal, tree)
	interaction._execute_action(&"destination_verify")
	t.assert_equal("右台 / 重复调阅不追加事件", initial_events + 1, manager.get_document_events(session).size())
	await _close_workspace(terminal, tree)
	interaction._execute_action(&"destination_clear")
	interaction._execute_action(&"destination_verify")
	t.assert_equal("右台 / 清空后不复用旧引用", initial_events + 1, manager.get_document_events(session).size())
	_input_floor(destination, "0")
	t.assert_equal("右台 / 已知前缀显示输入中", "prefix", destination.get_destination_presentation().query_status)
	_input_floor(destination, "005")
	t.assert_equal("右台 / 独立静态停靠状态", "不支持停靠", destination.get_destination_presentation().elevator_stop)
	var refused := manager.request_travel_to_floor("005")
	t.assert_equal("右台 / Manager 直调拒绝不支持停靠", &"FLOOR_NOT_ACCESSIBLE", refused.code)

	var pickup_result := manager.request_travel_to_floor(manager.get_pickup_floor())
	t.assert_true("右台 / 正式场景联锁已接线，可推进到接乘层", pickup_result.succeeded)
	if manager.is_elevator_moving():
		await manager.elevator_movement_completed
	_input_floor(destination, "900")
	var open_result := manager.request_open_cabin_door()
	destination.request_submit_destination()
	t.assert_true("右台 / 开门拒绝仍绑定当前输入与查询", open_result.succeeded
		and destination.get_destination_presentation().query_floor == "900"
		and destination.get_destination_presentation().execution_target == "---"
		and not manager.is_elevator_moving())
	destination.request_retrieve_floor_archive()
	t.assert_equal("右台 / 发车失败只允许调阅当前目标", "right",
		manager.get_acquired_document(session, {"document_id": "registry/floor/900", "version": 1}).get("route"))
	await _close_workspace(terminal, tree)
	var close_result := manager.request_close_cabin_door()
	t.assert_true("右台 / 测试乘客已进舱", close_result.succeeded and manager.is_passenger_onboard())
	var stage := main.find_child("监控测试摄影棚", true, false) as MonitorStageController3D
	var door_animation := stage.get_door_visual().get_animation_player()
	stage.request_door_open_presentation()
	door_animation.advance(2.0)
	stage.request_door_close_presentation()
	t.assert_equal("右台 / 正式场景直调 Manager 拒绝门动画期间发车",
		&"PRESENTATION_BUSY", manager.request_travel_to_floor("900").code)
	t.assert_false("右台 / busy 拒绝不启动移动", manager.is_elevator_moving())
	door_animation.advance(2.0)
	interaction._execute_action(&"destination_submit")
	t.assert_true("右台 / 乘客在舱无需验证可拨杆发车", manager.is_elevator_moving())
	var accepted_snapshot := destination.get_destination_presentation()
	t.assert_equal("右台 / 发车清空输入", "", accepted_snapshot.input)
	t.assert_equal("右台 / 发车撤销旧查询", "---", accepted_snapshot.query_floor)
	t.assert_equal("右台 / 实际目标独立展示", "900", accepted_snapshot.execution_target)
	var events_after_travel := manager.get_document_events(session).size()
	interaction._execute_action(&"destination_verify")
	t.assert_equal("右台 / 成功发车后立即调阅无旧事件", events_after_travel, manager.get_document_events(session).size())
	t.assert_false("右台 / 成功发车后立即调阅不重开旧窗", terminal.target_open)
	t.assert_equal("右台 / 运行中直调不能改目标", &"ELEVATOR_MOVING", manager.request_travel_to_floor("004").code)
	_input_floor(destination, "001")
	if manager.is_elevator_moving():
		await manager.elevator_movement_completed
	t.assert_equal("右台 / 到站不覆盖途中查询 B", "001", destination.get_destination_presentation().query_floor)
	t.assert_equal("右台 / 到站后清除执行目标", "---", destination.get_destination_presentation().execution_target)
	interaction._execute_action(&"destination_verify")
	t.assert_equal("右台 / 到站调阅取得 B", "right",
		manager.get_acquired_document(session, {"document_id": "registry/floor/001", "version": 1}).get("route"))
	t.assert_equal("右台 / 到站仍保留已取得旧版 A", receipt, manager.get_acquired_document(session, first_ref))
	await _close_workspace(terminal, tree)
	await tree.create_timer(presentation.lever_forward_duration + presentation.lever_return_duration + 0.05).timeout
	destination.clear_destination_input()

	var slope := right_root.get_node("下部斜面根") as Node3D
	t.assert_true("右台 / ART-06 冻结斜面为 12 度",
			is_equal_approx(rad_to_deg(absf(slope.rotation.z)), 12.0))
	var lever := right_root.get_node(
		"下部斜面根/执行拨杆热点"
	) as InteractionHotspot3D
	t.assert_equal("右台 / 拨杆调用提交动作", &"destination_submit",
			lever.get_action_id())
	var pivot := presentation.get_node(presentation.lever_pivot_path) as Node3D
	var rest_rotation := pivot.rotation
	var submit_results: Array[FlowCommandResult] = []
	destination.destination_travel_result.connect(func(result: FlowCommandResult) -> void:
		submit_results.append(result)
	)
	# 固定本次悬停意图，用真实展示 Tween 分段推进，避免帧率影响30°峰值断言。
	var was_processing := interaction.is_processing()
	interaction.set_process(false)
	interaction._set_hovered_hotspot(lever)
	var hover := lever.get_node(lever.hover_visual_path) as Node3D
	t.assert_true("右台 / 静止握柄可显示悬停", hover.visible)
	interaction._execute_action(&"destination_submit")
	interaction._execute_action(&"destination_submit")
	t.assert_true("右台 / 拨杆动作期间防重复触发", presentation.is_lever_animating())
	t.assert_equal("右台 / 连续触发只提交一次", 1, submit_results.size())
	t.assert_false("右台 / 动画开始立即收起握柄高亮", hover.visible)
	t.assert_true("右台 / 抑制高亮不禁用原热点", lever.can_interact())
	var tween := presentation.get("_lever_tween") as Tween
	tween.custom_step(presentation.lever_forward_duration * 0.5)
	t.assert_true("右台 / 真实 Tween 推动握柄前进",
			pivot.rotation.z > rest_rotation.z)
	lever.set_hovered(false)
	lever.set_hovered(true)
	t.assert_false("右台 / 前进中重新悬停不会点亮", hover.visible)
	tween.custom_step(presentation.lever_forward_duration * 0.5)
	t.assert_true("右台 / 冻结行程实际达到30度",
			is_equal_approx(rad_to_deg(pivot.rotation.z - rest_rotation.z), 30.0))
	t.assert_false("右台 / 前进行程顶点不高亮", hover.visible)
	tween.custom_step(presentation.lever_return_duration * 0.5)
	t.assert_true("右台 / 真实 Tween 正在自动回位",
			pivot.rotation.z > rest_rotation.z
			and rad_to_deg(pivot.rotation.z - rest_rotation.z) < 30.0)
	lever.set_hovered(true)
	t.assert_false("右台 / 回位中重复悬停仍不高亮", hover.visible)
	tween.custom_step(presentation.lever_return_duration * 0.5 + 0.001)
	t.assert_false("右台 / 拨杆自动回位后解锁", presentation.is_lever_animating())
	t.assert_equal("右台 / 回位不产生第二次提交", 1, submit_results.size())
	t.assert_true("右台 / 拨杆精确返回 Inspector 姿态",
			pivot.rotation.is_equal_approx(rest_rotation))
	t.assert_true("右台 / 回位后恢复仍在握柄上的悬停", hover.visible)
	interaction._execute_action(&"destination_submit")
	lever.set_hovered(false)
	tween = presentation.get("_lever_tween") as Tween
	tween.custom_step(
		presentation.lever_forward_duration + presentation.lever_return_duration + 0.001
	)
	t.assert_equal("右台 / 新动作也只新增一次提交", 2, submit_results.size())
	t.assert_false("右台 / 动画期间离开握柄后不恢复高亮", hover.visible)
	t.assert_false("右台 / 离开握柄不阻止自动回位", presentation.is_lever_animating())
	interaction.set_process(was_processing)
	await _frames(tree, 2)

	var coordinator := main.find_child("监控表现协调器", true, false) as MonitorPresentationCoordinator3D
	coordinator.queue_free()
	await _frames(tree, 2)
	t.assert_equal("右台 / 正式协调器失效时直调不能发车", &"TRAVEL_INTERLOCK_UNAVAILABLE",
		manager.request_travel_to_floor("004").code)
	t.assert_false("右台 / 联锁失效不启动 Timer", manager.is_elevator_moving())

	main.queue_free()
	await _frames(tree, 3)
	case.documents = saved_documents
	Archives.remove_blocked_floor(blocked)


func _frames(tree: SceneTree, count: int = 8) -> void:
	for frame in count:
		await tree.process_frame

func _input_floor(destination: DestinationControlInterface, floor_id: String) -> void:
	destination.clear_destination_input()
	for digit: String in floor_id:
		destination.append_destination_digit(digit)


func _close_workspace(terminal: VerificationTerminal3D, tree: SceneTree) -> void:
	terminal.set_open(false)
	await tree.create_timer(terminal.slide_duration + 0.05).timeout
	await _frames(tree, 2)
