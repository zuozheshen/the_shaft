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
	await _test_initial_runtime_components(test_runner, tree)
	await _test_pickup_floor_leave_and_return(test_runner, tree)
	await _test_dispatch_order_state_isolation_and_signals(test_runner, tree)
	await _test_ui_manager_injection(test_runner, tree)


func _test_initial_runtime_components(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	test_runner.assert_equal(
		"DemoFlowManager / 初始楼层正确",
		"900",
		manager.get_current_floor()
	)
	test_runner.assert_false(
		"DemoFlowManager / 初始舱门关闭",
		manager.is_cabin_door_open()
	)
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
	await _destroy_manager(manager, tree)


func _test_pickup_floor_leave_and_return(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager: DemoFlowManager = await _create_manager(tree)
	test_runner.assert_true(
		"接乘楼层 / 可前往接乘楼层",
		await _move_to(manager, "612")
	)
	test_runner.assert_equal(
		"接乘楼层 / 抵达后进入接乘到达阶段",
		DispatchPhase.ARRIVED_AT_PICKUP,
		manager.get_case_phase()
	)
	test_runner.assert_true(
		"接乘楼层 / 门外确认使用正式命令完成",
		manager.request_complete_door_greeting().succeeded
	)

	test_runner.assert_true(
		"接乘楼层 / 可离开接乘楼层",
		await _move_to(manager, "900")
	)
	test_runner.assert_equal(
		"接乘楼层 / 离开后回到等待阶段",
		DispatchPhase.WAITING_FOR_PICKUP,
		manager.get_case_phase()
	)
	test_runner.assert_true(
		"接乘楼层 / 可返回接乘楼层",
		await _move_to(manager, "612")
	)
	test_runner.assert_equal(
		"接乘楼层 / 返回后恢复已完成的门外确认阶段",
		DispatchPhase.DOOR_GREETING_DONE,
		manager.get_case_phase()
	)
	await _destroy_manager(manager, tree)


func _test_dispatch_order_state_isolation_and_signals(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager: DemoFlowManager = _new_manager()
	var started_dispatch_ids: Array[StringName] = []
	var completed_results: Array[DispatchResult] = []
	var shift_completed_count := {"value": 0}
	var case_updated_count := {"value": 0}
	manager.dispatch_started.connect(
		func(dispatch_id: StringName) -> void:
			started_dispatch_ids.append(dispatch_id)
	)
	manager.dispatch_completed.connect(
		func(result: DispatchResult) -> void:
			completed_results.append(result)
	)
	manager.shift_completed.connect(
		func() -> void:
			shift_completed_count["value"] = \
					int(shift_completed_count["value"]) + 1
	)
	manager.case_updated.connect(
		func() -> void:
			case_updated_count["value"] = int(case_updated_count["value"]) + 1
	)
	tree.root.add_child(manager)
	await tree.process_frame

	test_runner.assert_true(
		"派单顺序 / 第一条派单通过正式流程完成",
		await _complete_dispatch(manager, "612", "900")
	)
	test_runner.assert_equal(
		"派单顺序 / 第一条完成后载入第二条",
		"CASE_002",
		String(manager.get_active_dispatch().dispatch_id)
	)
	_assert_fresh_dispatch_state(test_runner, manager, "第二条")

	test_runner.assert_true(
		"派单顺序 / 第二条派单通过正式流程完成",
		await _complete_dispatch(manager, "900", "742")
	)
	test_runner.assert_equal(
		"派单顺序 / 第二条完成后载入第三条",
		"CASE_003",
		String(manager.get_active_dispatch().dispatch_id)
	)
	_assert_fresh_dispatch_state(test_runner, manager, "第三条")

	test_runner.assert_true(
		"派单顺序 / 第三条派单通过正式流程完成",
		await _complete_dispatch(manager, "387", "547")
	)
	test_runner.assert_false(
		"派单顺序 / 三条派单完成后无活动派单",
		manager.has_active_dispatch()
	)
	test_runner.assert_equal(
		"派单顺序 / 值班结束后进入空闲阶段",
		DispatchPhase.SHIFT_IDLE,
		manager.get_case_phase()
	)
	test_runner.assert_equal(
		"流程信号 / 三条派单按顺序发送 dispatch_started",
		[&"CASE_001", &"CASE_002", &"CASE_003"],
		started_dispatch_ids
	)
	test_runner.assert_equal(
		"流程信号 / 三条派单各发送一次 dispatch_completed",
		3,
		completed_results.size()
	)
	test_runner.assert_equal(
		"流程信号 / 值班结束只发送一次 shift_completed",
		1,
		int(shift_completed_count["value"])
	)
	test_runner.assert_true(
		"流程信号 / 正式流程持续发送 case_updated",
		int(case_updated_count["value"]) > 0
	)
	await _destroy_manager(manager, tree)


func _assert_fresh_dispatch_state(
		test_runner: Variant,
		manager: DemoFlowManager,
		dispatch_label: String
) -> void:
	test_runner.assert_equal(
		"派单隔离 / %s不继承验证楼层" % dispatch_label,
		"",
		manager.get_validated_floor()
	)
	test_runner.assert_equal(
		"派单隔离 / %s不继承所选目标" % dispatch_label,
		"",
		manager.get_selected_target_floor()
	)
	test_runner.assert_false(
		"派单隔离 / %s不继承乘客状态" % dispatch_label,
		manager.is_passenger_onboard()
	)
	test_runner.assert_false(
		"派单隔离 / %s不继承门外确认标记" % dispatch_label,
		manager.is_door_greeting_done()
	)
	test_runner.assert_false(
		"派单隔离 / %s不继承到站反馈标记" % dispatch_label,
		manager.dispatch_lifecycle.is_arrival_triggered()
	)


func _test_ui_manager_injection(test_runner: Variant, tree: SceneTree) -> void:
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
		"UI 注入 / FRONT 通过 DemoFlowManager 接入",
		manager,
		console_interface.demo_flow_manager
	)
	test_runner.assert_equal(
		"UI 注入 / LEFT 通过 DemoFlowManager 接入",
		manager,
		building_terminal_interface.demo_flow_manager
	)
	test_runner.assert_equal(
		"UI 注入 / RIGHT 通过 DemoFlowManager 接入",
		manager,
		destination_control_interface.demo_flow_manager
	)

	console_interface.queue_free()
	building_terminal_interface.queue_free()
	destination_control_interface.queue_free()
	await _destroy_manager(manager, tree)


func _new_manager() -> DemoFlowManager:
	var manager := DemoFlowManager.new()
	manager.initial_floor = "900"
	manager.movement_duration_seconds = 0.01
	manager.initial_shift = DEMO_SHIFT
	return manager


func _create_manager(tree: SceneTree) -> DemoFlowManager:
	var manager: DemoFlowManager = _new_manager()
	tree.root.add_child(manager)
	await tree.process_frame
	return manager


func _destroy_manager(manager: DemoFlowManager, tree: SceneTree) -> void:
	manager.queue_free()
	await tree.process_frame


func _move_to(manager: DemoFlowManager, destination: String) -> bool:
	var result = manager.request_travel_to_floor(destination)
	if not result.succeeded:
		return false
	await manager.elevator_movement_completed
	return manager.get_current_floor() == destination


func _prepare_boarding(
		manager: DemoFlowManager,
		pickup_floor: String
) -> bool:
	if manager.get_current_floor() != pickup_floor:
		if not await _move_to(manager, pickup_floor):
			return false
	if not manager.request_open_cabin_door().succeeded:
		return false
	return manager.request_close_cabin_door().succeeded


func _complete_dispatch(
		manager: DemoFlowManager,
		pickup_floor: String,
		destination_floor: String
) -> bool:
	if not await _prepare_boarding(manager, pickup_floor):
		return false
	if not manager.request_validate_destination(destination_floor).succeeded:
		return false
	if not await _move_to(manager, destination_floor):
		return false
	if not manager.request_open_cabin_door().succeeded:
		return false
	if not manager.request_finish_dropoff_feedback().succeeded:
		return false
	return manager.request_close_cabin_door().succeeded
