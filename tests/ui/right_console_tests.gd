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
	t.assert_false("右台 / 旧 LineEdit 不可编辑", destination.manual_destination_line_edit.editable)
	for button: Button in destination.recommended_destination_buttons:
		t.assert_true("右台 / 推荐楼层只显示不可点击 " + button.name, button.disabled)

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
	for index in key_names.size():
		var key := right_root.get_node("数字键盘/" + key_names[index]) \
				as InteractionHotspot3D
		var collision := key.get_node("CollisionShape3D") as CollisionShape3D
		var cap := key.get_node("按钮帽") as MeshInstance3D
		t.assert_equal("右台 / 4x3 动作映射 " + key_names[index],
				StringName(expected_actions[index]), key.get_action_id())
		t.assert_equal("右台 / 热点属于右台 " + key_names[index],
				&"right_console", key.get_station_id())
		t.assert_true("右台 / Mesh 与碰撞跟随同一按键根 " + key_names[index],
				collision.global_transform.basis.is_equal_approx(
					cap.global_transform.basis
				))

	destination.clear_destination_input()
	for action: StringName in [
		&"destination_digit_0", &"destination_digit_0", &"destination_digit_4",
	]:
		interaction._execute_action(action)
	await _frames(tree, 2)
	t.assert_equal("右台 / 实体数字键复用原输入并保留 004", "004",
			destination.manual_destination_line_edit.text)
	t.assert_equal("右台 / LCD 读取同一字符串", "004",
			str(destination.get_destination_presentation().input))
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
			destination.manual_destination_line_edit.text)
	interaction._execute_action(&"destination_clear")
	t.assert_equal("右台 / CLR 清空输入", "",
			destination.manual_destination_line_edit.text)
	destination._select_recommended_destination(0)
	t.assert_equal("右台 / 旧推荐入口不能填入", "",
			destination.manual_destination_line_edit.text)

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
	t.assert_true("右台 / 斜面初始约 20 度",
			is_equal_approx(rad_to_deg(absf(slope.rotation.z)), 20.0))
	t.assert_equal("右台 / 静态书继承斜面根", slope,
			right_root.get_node("下部斜面根/楼层导引书").get_parent())
	var lever := right_root.get_node(
		"下部斜面根/执行拨杆热点"
	) as InteractionHotspot3D
	t.assert_equal("右台 / 拨杆调用提交动作", &"destination_submit",
			lever.get_action_id())
	var pivot := presentation.get_node(presentation.lever_pivot_path) as Node3D
	var rest_rotation := pivot.rotation
	interaction._execute_action(&"destination_submit")
	interaction._execute_action(&"destination_submit")
	t.assert_true("右台 / 拨杆动作期间防重复触发", presentation.is_lever_animating())
	await tree.create_timer(
		presentation.lever_forward_duration + presentation.lever_return_duration + 0.05
	).timeout
	await _frames(tree, 2)
	t.assert_false("右台 / 拨杆自动回位后解锁", presentation.is_lever_animating())
	t.assert_true("右台 / 拨杆精确返回 Inspector 姿态",
			pivot.rotation.is_equal_approx(rest_rotation))

	main.queue_free()
	await _frames(tree, 3)


func _frames(tree: SceneTree, count: int = 8) -> void:
	for frame in count:
		await tree.process_frame
