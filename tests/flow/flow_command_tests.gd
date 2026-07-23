extends RefCounted


const DEMO_SHIFT: ShiftDefinition = preload("res://data/shifts/demo_shift_001.tres")
const FlowCommandResultScript := preload(
	"res://scripts/runtime/commands/flow_command_result.gd"
)


func run(test_runner: Variant, tree: SceneTree) -> void:
	await _test_open_close_and_greeting_commands(test_runner, tree)
	await _test_validation_and_travel_commands(test_runner, tree)
	await _test_dropoff_and_shift_completion_commands(test_runner, tree)
	_test_ui_command_boundary(test_runner)


func _test_open_close_and_greeting_commands(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	var moving_result = manager.request_travel_to_floor("742")
	test_runner.assert_true(
		"流程命令 / 自由移动可以开始",
		moving_result.succeeded
	)
	var phase_before_open: String = manager.get_case_phase()
	var moving_open_result = manager.request_open_cabin_door()
	test_runner.assert_false(
		"流程命令 / 运行中开门失败",
		moving_open_result.succeeded
	)
	test_runner.assert_false(
		"流程命令 / 运行中开门失败不改变门状态",
		manager.is_cabin_door_open()
	)
	test_runner.assert_equal(
		"流程命令 / 运行中开门失败不改变阶段",
		phase_before_open,
		manager.get_case_phase()
	)
	await manager.elevator_movement_completed
	await _travel_and_wait(manager, "612")

	var update_counter := {"count": 0}
	manager.case_updated.connect(
		func() -> void:
			update_counter["count"] = int(update_counter["count"]) + 1
	)
	var direct_open_result = manager.request_open_cabin_door()
	test_runner.assert_true(
		"流程命令 / 不通话可直接开门接乘",
		direct_open_result.succeeded
	)
	test_runner.assert_true(
		"流程命令 / 直接接乘返回登舱效果",
		direct_open_result.has_effect(
			FlowCommandResultScript.PASSENGER_BOARDED
		)
	)
	test_runner.assert_true(
		"流程命令 / 直接接乘返回开门效果",
		direct_open_result.has_effect(FlowCommandResultScript.DOOR_OPENED)
	)
	test_runner.assert_equal(
		"流程命令 / 直接接乘原子进入等待关门",
		DispatchPhase.BOARDING_WAIT_DOOR_CLOSE,
		manager.get_case_phase()
	)
	test_runner.assert_true(
		"流程命令 / 直接接乘写入乘客状态",
		manager.is_passenger_onboard()
	)
	test_runner.assert_equal(
		"流程命令 / 开门命令只发送一次最终更新",
		1,
		int(update_counter["count"])
	)

	update_counter["count"] = 0
	var close_result = manager.request_close_cabin_door()
	test_runner.assert_true(
		"流程命令 / 登舱后关门成功",
		close_result.succeeded
	)
	test_runner.assert_true(
		"流程命令 / 关门解锁舱内对话效果",
		close_result.has_effect(
			FlowCommandResultScript.ONBOARD_DIALOGUE_AVAILABLE
		)
	)
	test_runner.assert_true(
		"流程命令 / 登舱关门返回关门效果",
		close_result.has_effect(FlowCommandResultScript.DOOR_CLOSED)
	)
	test_runner.assert_equal(
		"流程命令 / 登舱后关门进入舱内阶段",
		DispatchPhase.PASSENGER_ONBOARD,
		manager.get_case_phase()
	)
	test_runner.assert_equal(
		"流程命令 / 关门命令只发送一次最终更新",
		1,
		int(update_counter["count"])
	)
	await _destroy_manager(manager, tree)

	var greeting_manager: DemoFlowManager = await _create_manager(tree)
	await _travel_and_wait(greeting_manager, "612")
	var greeting_result = greeting_manager.request_complete_door_greeting()
	test_runner.assert_true(
		"流程命令 / 门外确认命令成功",
		greeting_result.succeeded
	)
	test_runner.assert_true(
		"流程命令 / 门外确认同时写入标记",
		greeting_manager.is_door_greeting_done()
	)
	test_runner.assert_true(
		"流程命令 / 门外确认返回完成效果",
		greeting_result.has_effect(
			FlowCommandResultScript.DOOR_GREETING_COMPLETED
		)
	)
	test_runner.assert_equal(
		"流程命令 / 门外确认同时转换阶段",
		DispatchPhase.DOOR_GREETING_DONE,
		greeting_manager.get_case_phase()
	)
	var repeated_greeting_result = \
			greeting_manager.request_complete_door_greeting()
	test_runner.assert_false(
		"流程命令 / 重复门外确认被拒绝",
		repeated_greeting_result.succeeded
	)
	test_runner.assert_equal(
		"流程命令 / 失败门外确认不改变阶段",
		DispatchPhase.DOOR_GREETING_DONE,
		greeting_manager.get_case_phase()
	)
	var greeting_open_result = greeting_manager.request_open_cabin_door()
	test_runner.assert_true(
		"流程命令 / 门外确认后仍可开门接乘",
		greeting_open_result.has_effect(
			FlowCommandResultScript.PASSENGER_BOARDED
		)
	)
	await _destroy_manager(greeting_manager, tree)


func _test_validation_and_travel_commands(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	manager.request_validate_destination("900")
	var empty_result = manager.request_validate_destination("   ")
	test_runner.assert_false("地址命令 / 空地址失败", empty_result.succeeded)
	test_runner.assert_equal(
		"地址命令 / 空地址清除旧验证",
		"",
		manager.get_validated_floor()
	)
	manager.request_validate_destination("900")
	var unknown_result = manager.request_validate_destination("999999")
	test_runner.assert_false("地址命令 / 未知地址失败", unknown_result.succeeded)
	test_runner.assert_equal(
		"地址命令 / 未知地址清除旧验证",
		"",
		manager.get_validated_floor()
	)
	var leading_zero_result = manager.request_validate_destination(" 004 ")
	test_runner.assert_true(
		"地址命令 / 004 可以通过验证",
		leading_zero_result.succeeded
	)
	test_runner.assert_equal(
		"地址命令 / 004 不转换为整数",
		"004",
		leading_zero_result.floor_id
	)
	test_runner.assert_true(
		"地址命令 / 验证成功返回验证效果",
		leading_zero_result.has_effect(
			FlowCommandResultScript.DESTINATION_VALIDATED
		)
	)
	manager.request_clear_destination_validation()

	var free_move_result = manager.request_travel_to_floor("742")
	test_runner.assert_true(
		"移动命令 / 无乘客无需验证即可移动",
		free_move_result.succeeded
	)
	test_runner.assert_true(
		"移动命令 / 自由移动返回开始效果",
		free_move_result.has_effect(FlowCommandResultScript.MOVEMENT_STARTED)
	)
	test_runner.assert_false(
		"移动命令 / 自由移动不返回派单目标效果",
		free_move_result.has_effect(
			FlowCommandResultScript.DISPATCH_TARGET_SELECTED
		)
	)
	test_runner.assert_equal(
		"移动命令 / 自由移动不写入派单目标",
		"",
		manager.get_selected_target_floor()
	)
	await manager.elevator_movement_completed
	await _travel_and_wait(manager, "612")
	manager.request_open_cabin_door()
	manager.request_close_cabin_door()

	manager.select_target_floor("900")
	var unvalidated_move_result = manager.request_travel_to_floor("742")
	test_runner.assert_false(
		"移动命令 / 搭载乘客时必须先验证",
		unvalidated_move_result.succeeded
	)
	test_runner.assert_equal(
		"移动命令 / 失败移动保留原派单目标",
		"900",
		manager.get_selected_target_floor()
	)
	test_runner.assert_false(
		"移动命令 / 验证失败不会开始移动",
		manager.is_elevator_moving()
	)

	manager.request_validate_destination("742")
	var passenger_move_result = manager.request_travel_to_floor("742")
	test_runner.assert_true(
		"移动命令 / 验证后搭载乘客可以移动",
		passenger_move_result.succeeded
	)
	test_runner.assert_true(
		"移动命令 / 搭载移动原子选择派单目标",
		passenger_move_result.has_effect(
			FlowCommandResultScript.DISPATCH_TARGET_SELECTED
		)
	)
	test_runner.assert_equal(
		"移动命令 / 搭载移动写入所选目标",
		"742",
		manager.get_selected_target_floor()
	)
	test_runner.assert_equal(
		"移动命令 / 成功提示保持原有文案",
		"目标楼层已确认：742。电梯正在前往该楼层。",
		passenger_move_result.message
	)
	await manager.elevator_movement_completed
	await _destroy_manager(manager, tree)

	var no_dispatch_manager: DemoFlowManager = await _create_manager(tree)
	no_dispatch_manager.clear_active_dispatch()
	var static_validation_result = \
			no_dispatch_manager.request_validate_destination("004")
	test_runner.assert_true(
		"地址命令 / 无派单时静态验证仍成功",
		static_validation_result.succeeded
	)
	test_runner.assert_equal(
		"地址命令 / 无派单静态验证不写派单状态",
		"",
		no_dispatch_manager.get_validated_floor()
	)
	var safe_clear_result = \
			no_dispatch_manager.request_clear_destination_validation()
	test_runner.assert_true(
		"地址命令 / 无派单清除验证安全成功",
		safe_clear_result.succeeded
	)
	test_runner.assert_true(
		"地址命令 / 清除验证返回清除效果",
		safe_clear_result.has_effect(
			FlowCommandResultScript.VALIDATION_CLEARED
		)
	)
	await _destroy_manager(no_dispatch_manager, tree)


func _test_dropoff_and_shift_completion_commands(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	await _board_at_pickup(manager, "612")
	manager.request_validate_destination("900")
	await _travel_and_wait(manager, "900")

	var destination_open_result = manager.request_open_cabin_door()
	test_runner.assert_true(
		"结算命令 / 目标楼层开门开始反馈",
		destination_open_result.has_effect(
			FlowCommandResultScript.DROPOFF_FEEDBACK_REQUESTED
		)
	)
	test_runner.assert_true(
		"结算命令 / 开门原子标记反馈已触发",
		manager.dispatch_lifecycle.is_arrival_triggered()
	)
	var repeated_destination_open = manager.request_open_cabin_door()
	test_runner.assert_false(
		"结算命令 / 目标反馈不能由重复开门再次触发",
		repeated_destination_open.succeeded
	)
	test_runner.assert_false(
		"结算命令 / 重复开门不返回反馈效果",
		repeated_destination_open.has_effect(
			FlowCommandResultScript.DROPOFF_FEEDBACK_REQUESTED
		)
	)

	var early_close_result = manager.request_close_cabin_door()
	test_runner.assert_false(
		"结算命令 / 反馈阶段不能提前关门",
		early_close_result.succeeded
	)
	test_runner.assert_true(
		"结算命令 / 提前关门失败保持舱门开启",
		manager.is_cabin_door_open()
	)
	test_runner.assert_equal(
		"结算命令 / 提前关门失败保持反馈阶段",
		DispatchPhase.DROPOFF_FEEDBACK,
		manager.get_case_phase()
	)

	var finish_feedback_result = manager.request_finish_dropoff_feedback()
	test_runner.assert_true(
		"结算命令 / 反馈结束命令成功",
		finish_feedback_result.has_effect(
			FlowCommandResultScript.DROPOFF_FEEDBACK_FINISHED
		)
	)
	var completion_update_counter := {"count": 0}
	manager.case_updated.connect(
		func() -> void:
			completion_update_counter["count"] = \
					int(completion_update_counter["count"]) + 1
	)
	var first_completion_result = manager.request_close_cabin_door()
	test_runner.assert_true(
		"结算命令 / 离舱关门完成第一单",
		first_completion_result.succeeded
	)
	test_runner.assert_true(
		"结算命令 / 第一单返回完成效果",
		first_completion_result.has_effect(
			FlowCommandResultScript.DISPATCH_COMPLETED
		)
	)
	test_runner.assert_true(
		"结算命令 / 第一单返回下一单开始效果",
		first_completion_result.has_effect(
			FlowCommandResultScript.NEXT_DISPATCH_STARTED
		)
	)
	test_runner.assert_equal(
		"结算命令 / 首单关门只发送一次最终更新",
		1,
		int(completion_update_counter["count"])
	)
	test_runner.assert_equal(
		"结算命令 / 第一单结束后载入第二单",
		"CASE_002",
		String(manager.get_active_dispatch().dispatch_id)
	)
	test_runner.assert_equal(
		"结算命令 / 第二单不继承验证楼层",
		"",
		manager.get_validated_floor()
	)
	test_runner.assert_equal(
		"结算命令 / 第二单不继承派单目标",
		"",
		manager.get_selected_target_floor()
	)
	test_runner.assert_false(
		"结算命令 / 第二单不继承反馈标记",
		manager.dispatch_lifecycle.is_arrival_triggered()
	)
	test_runner.assert_false(
		"结算命令 / 第二单不继承乘客状态",
		manager.is_passenger_onboard()
	)

	await _board_at_pickup(manager, "900")
	manager.request_validate_destination("742")
	await _travel_and_wait(manager, "742")
	manager.request_open_cabin_door()
	manager.request_finish_dropoff_feedback()
	var shift_signal_counter := {"count": 0}
	manager.shift_completed.connect(
		func() -> void:
			shift_signal_counter["count"] = \
					int(shift_signal_counter["count"]) + 1
	)
	var final_completion_result = manager.request_close_cabin_door()
	test_runner.assert_true(
		"结算命令 / 最后一单关门不能误报失败",
		final_completion_result.succeeded
	)
	test_runner.assert_true(
		"结算命令 / 最后一单返回值班结束效果",
		final_completion_result.has_effect(
			FlowCommandResultScript.SHIFT_COMPLETED
		)
	)
	test_runner.assert_false(
		"结算命令 / 最后一单不虚构下一单效果",
		final_completion_result.has_effect(
			FlowCommandResultScript.NEXT_DISPATCH_STARTED
		)
	)
	test_runner.assert_false(
		"结算命令 / 值班结束后无活动派单",
		manager.has_active_dispatch()
	)
	manager.finish_shift()
	test_runner.assert_equal(
		"结算命令 / 值班结束信号只发送一次",
		1,
		int(shift_signal_counter["count"])
	)
	await _destroy_manager(manager, tree)


func _test_ui_command_boundary(test_runner: Variant) -> void:
	var console_source: String = FileAccess.get_file_as_string(
		"res://scripts/ui/console_interface.gd"
	)
	var destination_source: String = FileAccess.get_file_as_string(
		"res://scripts/ui/destination_control_interface.gd"
	)
	var console_forbidden_calls: Array[String] = [
		".set_cabin_door_open(",
		".set_passenger_onboard(",
		".set_cabin_door_closed_after_boarding(",
		".set_door_greeting_done(",
		".set_case_phase(",
		".try_mark_arrival_triggered(",
		".mark_dropoff_feedback_finished(",
		".complete_active_dispatch(",
	]
	var destination_forbidden_calls: Array[String] = [
		".set_validated_floor(",
		".request_elevator_movement(",
		".select_target_floor(",
		"ContentRegistry.has_floor(",
	]
	test_runner.assert_true(
		"UI 边界 / 主台不再组合低级业务接口",
		_contains_none(console_source, console_forbidden_calls)
	)
	test_runner.assert_true(
		"UI 边界 / 右台不再组合低级业务接口",
		_contains_none(destination_source, destination_forbidden_calls)
	)
	test_runner.assert_true(
		"UI 边界 / 主台调用结构化门控命令",
		"request_open_cabin_door(" in console_source \
			and "request_close_cabin_door(" in console_source
	)
	test_runner.assert_true(
		"UI 边界 / 右台调用结构化验证与移动命令",
		"request_validate_destination(" in destination_source \
			and "request_travel_to_floor(" in destination_source
	)


func _contains_none(source: String, forbidden_fragments: Array[String]) -> bool:
	for fragment: String in forbidden_fragments:
		if fragment in source:
			return false
	return true


func _create_manager(tree: SceneTree) -> DemoFlowManager:
	var manager := DemoFlowManager.new()
	manager.initial_floor = "900"
	manager.movement_duration_seconds = 0.01
	manager.initial_shift = DEMO_SHIFT
	tree.root.add_child(manager)
	await tree.process_frame
	return manager


func _destroy_manager(manager: DemoFlowManager, tree: SceneTree) -> void:
	manager.queue_free()
	await tree.process_frame


func _travel_and_wait(
		manager: DemoFlowManager,
		destination: String
) -> bool:
	var result = manager.request_travel_to_floor(destination)
	if not result.succeeded:
		return false
	await manager.elevator_movement_completed
	return manager.get_current_floor() == destination


func _board_at_pickup(
		manager: DemoFlowManager,
		pickup_floor: String
) -> bool:
	if manager.get_current_floor() != pickup_floor:
		if not await _travel_and_wait(manager, pickup_floor):
			return false
	var open_result = manager.request_open_cabin_door()
	if not open_result.succeeded:
		return false
	return manager.request_close_cabin_door().succeeded
