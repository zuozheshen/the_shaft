extends RefCounted
## 使用正式 main_3d 验证右台实体入口仍复用唯一 DestinationControlInterface。

const MAIN := preload("res://scenes/main/main_3d.tscn")


func run(t: Variant, tree: SceneTree) -> void:
	var main := MAIN.instantiate()
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
			(presentation.get_node(presentation.input_label_path) as Label3D).text)
	interaction._execute_action(&"destination_verify")
	await _frames(tree, 2)
	var snapshot := destination.get_destination_presentation()
	t.assert_equal("右台 / 验证按钮调用原验证入口", "004",
			str(snapshot.validated_floor))
	t.assert_equal("右台 / 验证状态驱动信息屏", "已验证",
			str(snapshot.address_status))
	var information := presentation.get_node(
		presentation.information_label_path
	) as Label3D
	t.assert_true("右台 / 信息屏显示已验证目标",
			"目标楼层：004" in information.text)

	interaction._execute_action(&"destination_digit_7")
	await _frames(tree, 2)
	t.assert_equal("右台 / 输入改变使旧验证失效", "---",
			str(destination.get_destination_presentation().validated_floor))
	interaction._execute_action(&"destination_backspace")
	t.assert_equal("右台 / 退格删除末位", "004",
			str(destination.get_destination_presentation().input))
	interaction._execute_action(&"destination_clear")
	t.assert_equal("右台 / CLR 清空输入", "",
			str(destination.get_destination_presentation().input))

	var manager := destination.demo_flow_manager
	var pickup_result := manager.request_travel_to_floor(manager.get_pickup_floor())
	t.assert_true("右台 / 可推进到乘客接乘层", pickup_result.succeeded)
	if manager.is_elevator_moving():
		await manager.elevator_movement_completed
	var open_result := manager.request_open_cabin_door()
	var close_result := manager.request_close_cabin_door()
	t.assert_true("右台 / 测试乘客已进舱", open_result.succeeded \
			and close_result.succeeded and manager.is_passenger_onboard())
	for digit: String in ["9", "0", "0"]:
		destination.append_destination_digit(digit)
	interaction._execute_action(&"destination_submit")
	await _frames(tree, 2)
	var rejection_snapshot := destination.get_destination_presentation()
	t.assert_false("右台 / 未验证提交不启动移动", manager.is_elevator_moving())
	t.assert_equal("右台 / 未验证拒绝保留输入以便重试", "900",
			str(rejection_snapshot.input))
	t.assert_equal("右台 / 未验证拒绝写入上屏状态",
			"未验证｜请先验证楼层", str(rejection_snapshot.address_status))
	t.assert_true("右台 / 上屏显示未验证拒绝",
			"地址状态：未验证｜请先验证楼层" in information.text)
	t.assert_true("右台 / 未验证拒绝触发 Verify 提示",
			presentation.is_verify_attention_active())
	await tree.create_timer(
		presentation.lever_forward_duration + presentation.lever_return_duration + 0.05
	).timeout
	interaction._execute_action(&"destination_verify")
	await _frames(tree, 2)
	t.assert_equal("右台 / 验证成功恢复地址状态", "已验证",
			str(destination.get_destination_presentation().address_status))
	destination.request_submit_destination()
	t.assert_true("右台 / 验证后可沿既有流程移动", manager.is_elevator_moving())
	var accepted_snapshot := destination.get_destination_presentation()
	t.assert_equal("右台 / 行驶请求成功后清空 LCD 输入", "",
			str(accepted_snapshot.input))
	t.assert_equal("右台 / 清空 LCD 不清除本次验证", "900",
			str(accepted_snapshot.validated_floor))

	var slope := right_root.get_node("下部斜面根") as Node3D
	t.assert_true("右台 / ART-06 冻结斜面为 12 度",
			is_equal_approx(rad_to_deg(absf(slope.rotation.z)), 12.0))
	t.assert_equal("右台 / 导引书常态继承斜面根", slope,
			right_root.get_node("下部斜面根/楼层导引书").get_parent())
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

	main.queue_free()
	await _frames(tree, 3)


func _frames(tree: SceneTree, count: int = 8) -> void:
	for frame in count:
		await tree.process_frame
