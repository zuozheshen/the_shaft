extends RefCounted


const DEMO_SHIFT: ShiftDefinition = preload("res://data/shifts/demo_shift_001.tres")
const CONSOLE_SCENE: PackedScene = preload("res://scenes/ui/ConsoleInterface.tscn")
const BUILDING_TERMINAL_SCENE: PackedScene = preload(
	"res://scenes/ui/BuildingTerminalInterface.tscn"
)
const DESTINATION_CONTROL_SCENE: PackedScene = preload(
	"res://scenes/ui/DestinationControlInterface.tscn"
)


func run(test_runner: Variant, tree: SceneTree) -> void:
	await _test_initial_and_movement_state(test_runner, tree)
	await _test_phase_update_contract(test_runner, tree)
	await _test_pickup_lifecycle(test_runner, tree)
	await _test_delivery_and_dispatch_order(test_runner, tree)
	await _test_ui_compatibility(test_runner, tree)


func _test_initial_and_movement_state(test_runner: Variant, tree: SceneTree) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	test_runner.assert_equal("DemoFlowManager / 初始楼层正确", "900", manager.get_current_floor())
	test_runner.assert_false("DemoFlowManager / 初始舱门关闭", manager.is_cabin_door_open())
	test_runner.assert_false("DemoFlowManager / 初始不处于移动状态", manager.is_elevator_moving())
	test_runner.assert_equal(
		"DemoFlowManager / 第一条派单正常建立",
		"CASE_001",
		String(manager.get_active_dispatch().dispatch_id)
	)
	var runtime_component_count: int = manager.get_child_count()
	manager._initialize_runtime_components()
	test_runner.assert_equal(
		"DemoFlowManager / 重复初始化不创建重复组件",
		runtime_component_count,
		manager.get_child_count()
	)
	test_runner.assert_false(
		"DemoFlowManager / 空目标不能移动",
		manager.request_elevator_movement("  ")
	)
	test_runner.assert_false(
		"DemoFlowManager / 不存在的楼层不能移动",
		manager.request_elevator_movement("999999")
	)

	manager.set_cabin_door_open(true)
	test_runner.assert_false(
		"DemoFlowManager / 舱门开启时不能移动",
		manager.request_elevator_movement("612")
	)
	manager.set_cabin_door_open(false)

	test_runner.assert_true(
		"DemoFlowManager / 接乘前可自由移动到已登记楼层",
		manager.request_elevator_movement("742")
	)
	test_runner.assert_false(
		"DemoFlowManager / 移动中不能开始第二次移动",
		manager.request_elevator_movement("612")
	)
	await manager.elevator_movement_completed
	await _destroy_manager(manager, tree)


func _test_phase_update_contract(test_runner: Variant, tree: SceneTree) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	var update_counter := {"count": 0}
	manager.case_updated.connect(
		func() -> void:
			update_counter["count"] = int(update_counter["count"]) + 1
	)
	var original_phase: String = manager.get_case_phase()

	test_runner.assert_false(
		"DemoFlowManager / 无效目标阶段被拒绝",
		manager.try_set_case_phase("NOT_A_DISPATCH_PHASE")
	)
	test_runner.assert_equal(
		"DemoFlowManager / 无效目标不会修改当前阶段",
		original_phase,
		manager.get_case_phase()
	)
	test_runner.assert_false(
		"DemoFlowManager / 非法阶段转换被拒绝",
		manager.try_set_case_phase(DispatchPhase.PASSENGER_ONBOARD)
	)
	test_runner.assert_equal(
		"DemoFlowManager / 非法转换不会修改当前阶段",
		original_phase,
		manager.get_case_phase()
	)
	test_runner.assert_true(
		"DemoFlowManager / 同阶段重复设置视为成功",
		manager.try_set_case_phase(original_phase)
	)
	test_runner.assert_equal(
		"DemoFlowManager / 同阶段重复设置不触发更新",
		0,
		int(update_counter["count"])
	)
	test_runner.assert_true(
		"DemoFlowManager / 合法阶段转换成功",
		manager.try_set_case_phase(DispatchPhase.ARRIVED_AT_PICKUP)
	)
	test_runner.assert_equal(
		"DemoFlowManager / 合法转换只触发一次更新",
		1,
		int(update_counter["count"])
	)

	manager.clear_active_dispatch()
	test_runner.assert_false(
		"DemoFlowManager / 当前无派单时阶段设置失败",
		manager.try_set_case_phase(DispatchPhase.WAITING_FOR_PICKUP)
	)
	await _destroy_manager(manager, tree)


func _test_pickup_lifecycle(test_runner: Variant, tree: SceneTree) -> void:
	var direct_boarding_manager: DemoFlowManager = await _create_manager(tree)
	test_runner.assert_true(
		"接乘生命周期 / 可移动到接乘楼层",
		await _move_to(direct_boarding_manager, "612")
	)
	test_runner.assert_equal(
		"接乘生命周期 / 抵达后进入接乘到达阶段",
		DispatchPhase.ARRIVED_AT_PICKUP,
		direct_boarding_manager.get_case_phase()
	)

	direct_boarding_manager.set_cabin_door_open(true)
	direct_boarding_manager.set_passenger_onboard(true)
	test_runner.assert_true(
		"接乘生命周期 / 未门外通话仍可直接建立登舱阶段",
		direct_boarding_manager.try_set_case_phase(
			DispatchPhase.BOARDING_WAIT_DOOR_CLOSE
		)
	)
	test_runner.assert_true(
		"接乘生命周期 / 乘客登舱状态可以建立",
		direct_boarding_manager.is_passenger_onboard()
	)
	direct_boarding_manager.set_cabin_door_open(false)
	direct_boarding_manager.set_cabin_door_closed_after_boarding(true)
	test_runner.assert_true(
		"接乘生命周期 / 关门后进入舱内阶段",
		direct_boarding_manager.try_set_case_phase(DispatchPhase.PASSENGER_ONBOARD)
	)
	test_runner.assert_equal(
		"接乘生命周期 / 舱内阶段记录正确",
		DispatchPhase.PASSENGER_ONBOARD,
		direct_boarding_manager.get_case_phase()
	)
	await _destroy_manager(direct_boarding_manager, tree)

	var greeting_manager: DemoFlowManager = await _create_manager(tree)
	await _move_to(greeting_manager, "612")
	greeting_manager.set_door_greeting_done(true)
	test_runner.assert_true(
		"接乘生命周期 / 门外确认阶段可以记录",
		greeting_manager.try_set_case_phase(DispatchPhase.DOOR_GREETING_DONE)
	)
	test_runner.assert_true(
		"接乘生命周期 / 门外确认标记可以记录",
		greeting_manager.is_door_greeting_done()
	)
	await _move_to(greeting_manager, "900")
	test_runner.assert_equal(
		"接乘生命周期 / 离开接乘楼层后回到等待阶段",
		DispatchPhase.WAITING_FOR_PICKUP,
		greeting_manager.get_case_phase()
	)
	await _move_to(greeting_manager, "612")
	test_runner.assert_equal(
		"接乘生命周期 / 已确认后返回接乘楼层恢复确认阶段",
		DispatchPhase.DOOR_GREETING_DONE,
		greeting_manager.get_case_phase()
	)
	await _destroy_manager(greeting_manager, tree)


func _test_delivery_and_dispatch_order(test_runner: Variant, tree: SceneTree) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	var completed_results: Array[DispatchResult] = []
	var dispatch_started_counter := {"count": 0}
	manager.dispatch_completed.connect(
		func(result: DispatchResult) -> void:
			completed_results.append(result)
	)
	manager.dispatch_started.connect(
		func(_dispatch_id: StringName) -> void:
			dispatch_started_counter["count"] = int(dispatch_started_counter["count"]) + 1
	)
	await _move_to(manager, "612")
	_board_passenger(manager)

	test_runner.assert_true(
		"送达流程 / 有效目标可以被验证",
		manager.set_validated_floor("900")
	)
	test_runner.assert_true(
		"送达流程 / 有效目标可以被选择",
		manager.select_target_floor("900")
	)
	test_runner.assert_true("送达流程 / 可前往所选目标", await _move_to(manager, "900"))
	test_runner.assert_equal(
		"送达流程 / 抵达目标后进入目标到达阶段",
		DispatchPhase.ARRIVED_AT_DESTINATION,
		manager.get_case_phase()
	)
	test_runner.assert_false(
		"送达流程 / 未完成反馈时不能结算",
		manager.complete_active_dispatch()
	)
	test_runner.assert_true(
		"送达流程 / 到达本身未触发反馈且首次标记成功",
		manager.try_mark_arrival_triggered()
	)
	test_runner.assert_false(
		"送达流程 / 到站反馈标记不能重复",
		manager.try_mark_arrival_triggered()
	)

	manager.set_cabin_door_open(true)
	test_runner.assert_true(
		"送达流程 / 开门后可进入反馈阶段",
		manager.try_set_case_phase(DispatchPhase.DROPOFF_FEEDBACK)
	)
	test_runner.assert_true(
		"送达流程 / 反馈完成后进入等待关门阶段",
		manager.mark_dropoff_feedback_finished()
	)
	test_runner.assert_equal(
		"送达流程 / 反馈完成阶段记录正确",
		DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE,
		manager.get_case_phase()
	)
	test_runner.assert_false(
		"送达流程 / 舱门开启时不能完成派单",
		manager.complete_active_dispatch()
	)

	manager.set_cabin_door_open(false)
	test_runner.assert_true(
		"派单顺序 / 第一条派单完成后载入第二条",
		manager.complete_active_dispatch()
	)
	test_runner.assert_equal(
		"派单顺序 / 第二条派单 ID 正确",
		"CASE_002",
		String(manager.get_active_dispatch().dispatch_id)
	)
	test_runner.assert_equal(
		"派单顺序 / 第二条派单继续发送 dispatch_started",
		1,
		int(dispatch_started_counter["count"])
	)
	test_runner.assert_equal(
		"派单顺序 / 第二条不继承验证楼层",
		"",
		manager.get_validated_floor()
	)
	test_runner.assert_equal(
		"派单顺序 / 第二条不继承选择目标",
		"",
		manager.get_selected_target_floor()
	)
	test_runner.assert_false(
		"派单顺序 / 第二条不继承乘客进舱状态",
		manager.is_passenger_onboard()
	)
	test_runner.assert_true(
		"派单顺序 / 第二条不继承到站反馈标记",
		manager.try_mark_arrival_triggered()
	)
	_board_passenger(manager)
	test_runner.assert_equal(
		"派单顺序 / 第二条只保留自身运行时推荐楼层",
		["742"],
		manager.get_current_recommended_destinations()
	)

	var shift_signal_counter := {"count": 0}
	manager.shift_completed.connect(
		func() -> void:
			shift_signal_counter["count"] = int(shift_signal_counter["count"]) + 1
	)
	manager.set_validated_floor("742")
	manager.select_target_floor("742")
	await _move_to(manager, "742")
	manager.try_mark_arrival_triggered()
	manager.set_cabin_door_open(true)
	manager.try_set_case_phase(DispatchPhase.DROPOFF_FEEDBACK)
	manager.mark_dropoff_feedback_finished()
	manager.set_cabin_door_open(false)
	manager.complete_active_dispatch()

	test_runner.assert_equal(
		"派单顺序 / 两条派单结果均已记录",
		2,
		completed_results.size()
	)
	test_runner.assert_equal(
		"派单顺序 / 值班结束后无活动派单",
		DispatchPhase.SHIFT_IDLE,
		manager.get_case_phase()
	)
	manager.finish_shift()
	manager.finish_shift()
	test_runner.assert_equal(
		"派单顺序 / 重复结束不会重复发出值班结束",
		1,
		int(shift_signal_counter["count"])
	)
	await _destroy_manager(manager, tree)


func _test_ui_compatibility(test_runner: Variant, tree: SceneTree) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	var console_interface = CONSOLE_SCENE.instantiate()
	var building_terminal_interface = BUILDING_TERMINAL_SCENE.instantiate()
	var destination_control_interface = DESTINATION_CONTROL_SCENE.instantiate()
	tree.root.add_child(console_interface)
	tree.root.add_child(building_terminal_interface)
	tree.root.add_child(destination_control_interface)
	await tree.process_frame

	console_interface.set_demo_flow_manager(manager)
	building_terminal_interface.set_demo_flow_manager(manager)
	destination_control_interface.set_demo_flow_manager(manager)
	test_runner.assert_equal(
		"UI 兼容 / FRONT 仍通过 DemoFlowManager 接入",
		manager,
		console_interface.demo_flow_manager
	)
	test_runner.assert_equal(
		"UI 兼容 / LEFT 仍通过 DemoFlowManager 接入",
		manager,
		building_terminal_interface.demo_flow_manager
	)
	test_runner.assert_equal(
		"UI 兼容 / RIGHT 仍通过 DemoFlowManager 接入",
		manager,
		destination_control_interface.demo_flow_manager
	)

	console_interface.queue_free()
	building_terminal_interface.queue_free()
	destination_control_interface.queue_free()
	await _destroy_manager(manager, tree)


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


func _move_to(manager: DemoFlowManager, destination: String) -> bool:
	if not manager.request_elevator_movement(destination):
		return false
	await manager.elevator_movement_completed
	return manager.get_current_floor() == destination


func _board_passenger(manager: DemoFlowManager) -> void:
	# 测试通过现有公开状态方法建立门控结果，不复制 UI 内的按钮判断。
	manager.set_cabin_door_open(true)
	manager.set_passenger_onboard(true)
	manager.set_cabin_door_closed_after_boarding(false)
	manager.try_set_case_phase(DispatchPhase.BOARDING_WAIT_DOOR_CLOSE)
	manager.set_cabin_door_open(false)
	manager.set_cabin_door_closed_after_boarding(true)
	manager.try_set_case_phase(DispatchPhase.PASSENGER_ONBOARD)
