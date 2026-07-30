extends RefCounted


const MONITOR_STAGE_SCENE: PackedScene = preload(
	"res://scenes/presentation/monitor_test_stage_3d.tscn"
)
const LAYERED_SLICE_SCENE: PackedScene = preload(
	"res://scenes/presentation/layered_floor_slice_2_5d.tscn"
)
const CONSOLE_SCENE: PackedScene = preload(
	"res://scenes/ui/ConsoleInterface.tscn"
)
const DESTINATION_SCENE: PackedScene = preload(
	"res://scenes/ui/DestinationControlInterface.tscn"
)
const DEMO_SHIFT: ShiftDefinition = preload(
	"res://data/shifts/demo_shift_001.tres"
)
const PASSENGER_PROFILE_001: PassengerVisualProfile = preload(
	"res://data/presentation/passenger_visuals/passenger_001_visual.tres"
)
const PASSENGER_PROFILE_002: PassengerVisualProfile = preload(
	"res://data/presentation/passenger_visuals/passenger_002_visual.tres"
)
const PASSENGER_PROFILE_003: PassengerVisualProfile = preload(
	"res://data/presentation/passenger_visuals/passenger_003_visual.tres"
)


func run(test_runner: Variant, tree: SceneTree) -> void:
	await _test_low_level_passenger_timeline(test_runner, tree)
	await _test_coordinator_complete_shift(test_runner, tree)
	await _test_missing_presentation_degradation(test_runner, tree)


func _test_low_level_passenger_timeline(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var stage := _create_fast_stage()
	var console := CONSOLE_SCENE.instantiate() as ConsoleInterface
	test_runner.add_child(stage)
	test_runner.add_child(console)
	await tree.process_frame

	var passenger := stage.get_current_passenger_visual()
	var passenger_mount := stage.get_node(
		"乘客视觉区域/当前乘客挂载点"
	) as Node3D
	var cabin_anchor := stage.get_passenger_position_anchor(
		MonitorStageController3D.PASSENGER_POSITION_CABIN
	)
	var exit_anchor := stage.get_passenger_position_anchor(
		MonitorStageController3D.PASSENGER_POSITION_EXIT
	)
	test_runner.assert_not_equal(
		"乘客时间线 / 可取得门外离场点",
		null,
		exit_anchor
	)
	test_runner.assert_true(
		"乘客时间线 / 初始稳定状态为 HIDDEN",
		stage.get_passenger_presentation_state()
				== MonitorStageController3D.PassengerPresentationState.HIDDEN
				and not passenger.visible
				and not passenger.idle_enabled
	)

	var state_changes: Array[int] = []
	var busy_changes: Array[bool] = []
	var boarded_count := {"value": 0}
	var exited_count := {"value": 0}
	stage.passenger_presentation_state_changed.connect(
		func(state: int) -> void:
			state_changes.append(state)
	)
	stage.passenger_presentation_busy_changed.connect(
		func(is_busy: bool) -> void:
			busy_changes.append(is_busy)
	)
	stage.passenger_boarded.connect(
		func() -> void:
			boarded_count["value"] = int(boarded_count["value"]) + 1
	)
	stage.passenger_exited.connect(
		func() -> void:
			exited_count["value"] = int(exited_count["value"]) + 1
	)

	test_runner.assert_true(
		"乘客时间线 / snap outside 显示乘客并启用待机",
		stage.snap_passenger_outside_waiting()
				and passenger.visible
				and passenger.idle_enabled
	)
	test_runner.assert_false(
		"乘客时间线 / 门未开启时拒绝登舱",
		stage.request_passenger_boarding()
	)
	test_runner.assert_true(
		"乘客时间线 / 可同步为完全开门",
		stage.sync_door_presentation(true)
	)
	test_runner.assert_true(
		"乘客时间线 / 只从 OUTSIDE_WAITING 启动登舱",
		stage.request_passenger_boarding()
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.BOARDING
				and stage.is_passenger_presentation_busy()
				and not passenger.idle_enabled
	)

	# 楼层切片与摄像头切换只改变观察内容，不应终止正在运行的乘客 Tween。
	var replacement_slice := stage.replace_floor_slice(LAYERED_SLICE_SCENE)
	console._select_camera(1)
	test_runner.assert_true(
		"乘客时间线 / 切换楼层与摄像头不取消登舱 Tween",
		replacement_slice != null
				and console.get_current_camera_index() == 1
				and stage.is_passenger_presentation_busy()
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.BOARDING
	)
	await _wait_for_short_tween(tree)

	test_runner.assert_equal(
		"乘客时间线 / 登舱状态顺序",
		[
			MonitorStageController3D.PassengerPresentationState.OUTSIDE_WAITING,
			MonitorStageController3D.PassengerPresentationState.BOARDING,
			MonitorStageController3D.PassengerPresentationState.CABIN,
		],
		state_changes
	)
	test_runner.assert_equal(
		"乘客时间线 / 登舱 busy 顺序",
		[true, false],
		busy_changes
	)
	test_runner.assert_true(
		"乘客时间线 / 登舱结束精确对齐舱内并恢复待机",
		passenger_mount.global_position.is_equal_approx(cabin_anchor.global_position)
				and passenger.idle_enabled
				and not stage.is_passenger_presentation_busy()
				and int(boarded_count["value"]) == 1
	)
	test_runner.assert_true(
		"乘客时间线 / 乘客 Tween 不修改门状态",
		stage.get_door_visual().is_open()
	)
	test_runner.assert_false(
		"乘客时间线 / CABIN 状态拒绝再次登舱",
		stage.request_passenger_boarding()
	)

	stage.sync_door_presentation(false)
	test_runner.assert_false(
		"乘客时间线 / 门未开启时拒绝离舱",
		stage.request_passenger_disembark()
	)
	stage.sync_door_presentation(true)
	state_changes.clear()
	busy_changes.clear()
	test_runner.assert_true(
		"乘客时间线 / 只从 CABIN 启动离舱",
		stage.request_passenger_disembark()
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.DISEMBARKING
				and stage.is_passenger_presentation_busy()
				and not passenger.idle_enabled
	)
	stage.cancel_passenger_movement()
	test_runner.assert_true(
		"乘客时间线 / cancel 停止 Tween 并解除 busy",
		not stage.is_passenger_presentation_busy()
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.DISEMBARKING
				and busy_changes == [true, false]
	)

	test_runner.assert_true(
		"乘客时间线 / snap cabin 恢复稳定舱内位置",
		stage.snap_passenger_cabin()
				and passenger_mount.global_position.is_equal_approx(
					cabin_anchor.global_position
				)
				and passenger.visible
				and passenger.idle_enabled
	)
	state_changes.clear()
	busy_changes.clear()
	test_runner.assert_true(
		"乘客时间线 / 可重新启动完整离舱",
		stage.request_passenger_disembark()
	)
	console._select_camera(0)
	test_runner.assert_true(
		"乘客时间线 / 摄像头切换不取消离舱 Tween",
		console.get_current_camera_index() == 0
				and stage.is_passenger_presentation_busy()
	)
	await _wait_for_short_tween(tree)

	test_runner.assert_equal(
		"乘客时间线 / 离舱状态顺序",
		[
			MonitorStageController3D.PassengerPresentationState.DISEMBARKING,
			MonitorStageController3D.PassengerPresentationState.EXITED,
		],
		state_changes
	)
	test_runner.assert_equal(
		"乘客时间线 / 离舱 busy 顺序",
		[true, false],
		busy_changes
	)
	test_runner.assert_true(
		"乘客时间线 / 离舱结束精确对齐离场点并隐藏",
		passenger_mount.global_position.is_equal_approx(exit_anchor.global_position)
				and not passenger.visible
				and not passenger.idle_enabled
				and int(exited_count["value"]) == 1
				and stage.get_door_visual().is_open()
	)
	test_runner.assert_false(
		"乘客时间线 / EXITED 状态拒绝再次离舱",
		stage.request_passenger_disembark()
	)
	test_runner.assert_true(
		"乘客时间线 / snap hidden 保持节点并切换 HIDDEN",
		stage.snap_passenger_hidden()
				and is_instance_valid(passenger)
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.HIDDEN
	)

	console.queue_free()
	stage.queue_free()
	await tree.process_frame


func _test_coordinator_complete_shift(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager := _create_fast_manager()
	var stage := _create_fast_stage()
	var console := CONSOLE_SCENE.instantiate() as ConsoleInterface
	var destination := DESTINATION_SCENE.instantiate() \
			as DestinationControlInterface
	var coordinator := MonitorPresentationCoordinator3D.new()
	var duplicate_profile := PassengerVisualProfile.new()
	duplicate_profile.passenger_id = PASSENGER_PROFILE_001.passenger_id
	duplicate_profile.texture = PASSENGER_PROFILE_001.texture
	var profiles: Array[PassengerVisualProfile] = [
		PASSENGER_PROFILE_001,
		duplicate_profile,
		PASSENGER_PROFILE_002,
		PASSENGER_PROFILE_003,
	]
	coordinator.passenger_visual_profiles = profiles

	test_runner.add_child(manager)
	test_runner.add_child(stage)
	test_runner.add_child(console)
	test_runner.add_child(destination)
	test_runner.add_child(coordinator)
	await tree.process_frame

	console.set_demo_flow_manager(manager)
	console.set_monitor_stage_controller(stage)
	destination.set_demo_flow_manager(manager)
	coordinator.setup(manager, console, destination, stage)
	console.set_monitor_presentation_coordinator(coordinator)
	destination.set_monitor_presentation_coordinator(coordinator)

	var passenger := stage.get_current_passenger_visual()
	test_runner.assert_true(
		"表现协调器 / setup 应用 passenger_001 且初始隐藏",
		passenger.get_current_profile() == PASSENGER_PROFILE_001
				and passenger.get_passenger_id() == &"passenger_001"
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.HIDDEN
				and not coordinator.is_presentation_busy()
	)

	var completed_ids: Array[StringName] = []
	var started_ids: Array[StringName] = []
	var shift_completed_count := {"value": 0}
	manager.dispatch_completed.connect(
		func(result: DispatchResult) -> void:
			completed_ids.append(result.dispatch_id)
	)
	manager.dispatch_started.connect(
		func(dispatch_id: StringName) -> void:
			started_ids.append(dispatch_id)
	)
	manager.shift_completed.connect(
		func() -> void:
			shift_completed_count["value"] = \
					int(shift_completed_count["value"]) + 1
	)

	# 第一单先到接乘层；MOVEMENT_STARTED 保持隐藏，到站信号再显示门外乘客。
	await _travel_with_destination(destination, manager, "612", false)
	test_runner.assert_true(
		"表现协调器 / 到达接乘层显示门外乘客",
		stage.get_passenger_presentation_state()
				== MonitorStageController3D \
						.PassengerPresentationState.OUTSIDE_WAITING
				and passenger.visible
				and stage.get_door_visual().is_closed()
	)

	destination.manual_destination_line_edit.text = "900"
	console.request_open_door()
	test_runner.assert_true(
		"表现协调器 / PASSENGER_BOARDED 在门开完前保持 pending",
		manager.is_passenger_onboard()
				and stage.get_door_visual().get_door_state()
						== ElevatorDoorVisual3D.DoorPresentationState.OPENING
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.OUTSIDE_WAITING
				and coordinator.is_presentation_busy()
	)
	test_runner.assert_true(
		"统一表现锁 / 登舱 pending 禁用门控与行驶按钮",
		console.open_door_button.disabled
				and console.close_door_button.disabled
				and destination.submit_destination_button.disabled
				and not console.next_camera_button.disabled
	)

	console.request_close_door()
	var busy_hint_after_close := console.system_hint_label.text
	destination._submit_destination()
	console._select_camera(1)
	test_runner.assert_true(
		"统一表现锁 / pending 时统一入口不调用关门或行驶",
		manager.is_cabin_door_open()
				and not manager.is_elevator_moving()
				and destination.manual_destination_line_edit.text == "900"
				and destination.destination_feedback_label.text
						== DestinationControlInterface.PRESENTATION_BUSY_HINT
				and console.get_current_camera_index() == 1
	)
	test_runner.assert_equal(
		"统一表现锁 / 主台显示统一 busy 提示",
		ConsoleInterface.PRESENTATION_BUSY_HINT,
		busy_hint_after_close
	)

	_advance_door_animation(stage)
	test_runner.assert_true(
		"表现协调器 / 门完全开启后才启动登舱 Tween",
		stage.get_passenger_presentation_state()
				== MonitorStageController3D \
						.PassengerPresentationState.BOARDING
				and stage.is_passenger_presentation_busy()
				and coordinator.is_presentation_busy()
	)
	await _wait_for_short_tween(tree)
	test_runner.assert_true(
		"表现协调器 / 登舱结束释放统一 busy",
		stage.get_passenger_presentation_state()
				== MonitorStageController3D.PassengerPresentationState.CABIN
				and not coordinator.is_presentation_busy()
				and not destination.submit_destination_button.disabled
				and passenger.idle_enabled
	)

	console.request_close_door()
	test_runner.assert_true(
		"统一表现锁 / 关门动画纳入协调器 busy",
		coordinator.is_presentation_busy()
				and stage.get_door_visual().get_door_state()
						== ElevatorDoorVisual3D.DoorPresentationState.CLOSING
	)
	_advance_door_animation(stage)
	test_runner.assert_false(
		"统一表现锁 / 关门完成自动恢复",
		coordinator.is_presentation_busy()
	)

	await _travel_with_destination(destination, manager, "900", true)
	test_runner.assert_true(
		"表现协调器 / MOVEMENT_STARTED 保持 CABIN 乘客",
		stage.get_passenger_presentation_state()
				== MonitorStageController3D.PassengerPresentationState.CABIN
				and passenger.visible
				and passenger.idle_enabled
	)

	var dropoff_open_result := manager.request_open_cabin_door()
	stage.request_door_open_presentation()
	console.presentation_effects_requested.emit(
		dropoff_open_result.get_effects()
	)
	_advance_door_animation(stage)
	test_runner.assert_true(
		"表现协调器 / DROPOFF_FEEDBACK_REQUESTED 不触发离舱",
		dropoff_open_result.succeeded
				and dropoff_open_result.has_effect(
					FlowCommandResult.DROPOFF_FEEDBACK_REQUESTED
				)
				and manager.get_case_phase() == DispatchPhase.DROPOFF_FEEDBACK
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.CABIN
				and not coordinator.is_presentation_busy()
	)

	console.current_dialogue_context = ConsoleInterface.DialogueContext.DESTINATION
	console.current_dialogue_context_finished = false
	console._finish_current_dialogue_context()
	test_runner.assert_true(
		"表现协调器 / DROPOFF_FEEDBACK_FINISHED 触发离舱",
		manager.get_case_phase() == DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.DISEMBARKING
				and coordinator.is_presentation_busy()
	)
	console.request_close_door()
	test_runner.assert_true(
		"统一表现锁 / 离舱期间关门不改变业务门状态",
		manager.is_cabin_door_open()
				and console.system_hint_label.text
						== ConsoleInterface.PRESENTATION_BUSY_HINT
	)
	await _wait_for_short_tween(tree)
	test_runner.assert_true(
		"表现协调器 / 离舱结束隐藏并释放 busy",
		stage.get_passenger_presentation_state()
				== MonitorStageController3D.PassengerPresentationState.EXITED
				and not passenger.visible
				and not coordinator.is_presentation_busy()
	)

	console.request_close_door()
	test_runner.assert_true(
		"表现协调器 / 关门期间隐藏新派单乘客并应用 passenger_002",
		manager.has_active_dispatch()
				and manager.get_active_dispatch().dispatch_id == &"CASE_002"
				and passenger.get_current_profile() == PASSENGER_PROFILE_002
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.HIDDEN
				and not passenger.visible
				and coordinator.is_presentation_busy()
	)
	_advance_door_animation(stage)
	test_runner.assert_true(
		"表现协调器 / 门完全关闭后才显示同层接乘的新乘客",
		stage.get_passenger_presentation_state()
				== MonitorStageController3D \
						.PassengerPresentationState.OUTSIDE_WAITING
				and passenger.visible
				and not coordinator.is_presentation_busy()
	)

	await _complete_current_dispatch(
		test_runner,
		tree,
		manager,
		stage,
		console,
		destination,
		"742"
	)
	test_runner.assert_true(
		"表现协调器 / 第二单完成后应用 passenger_003 且未到接乘层时隐藏",
		manager.has_active_dispatch()
				and manager.get_active_dispatch().dispatch_id == &"CASE_003"
				and passenger.get_current_profile() == PASSENGER_PROFILE_003
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.HIDDEN
	)

	await _complete_current_dispatch(
		test_runner,
		tree,
		manager,
		stage,
		console,
		destination,
		"547"
	)
	test_runner.assert_true(
		"表现协调器 / 三单完整完成后隐藏乘客并解除 busy",
		not manager.has_active_dispatch()
				and manager.get_case_phase() == DispatchPhase.SHIFT_IDLE
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.HIDDEN
				and not coordinator.is_presentation_busy()
				and completed_ids == [&"CASE_001", &"CASE_002", &"CASE_003"]
				and started_ids == [&"CASE_002", &"CASE_003"]
				and int(shift_completed_count["value"]) == 1
	)

	coordinator.queue_free()
	destination.queue_free()
	console.queue_free()
	stage.queue_free()
	manager.queue_free()
	await tree.process_frame


func _test_missing_presentation_degradation(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager := _create_fast_manager()
	var destination := DESTINATION_SCENE.instantiate() \
			as DestinationControlInterface
	var coordinator := MonitorPresentationCoordinator3D.new()
	test_runner.add_child(manager)
	test_runner.add_child(destination)
	test_runner.add_child(coordinator)
	await tree.process_frame
	destination.set_demo_flow_manager(manager)

	coordinator.setup(manager, null, destination, null)
	destination.set_monitor_presentation_coordinator(coordinator)
	var boarding_effects: Array[StringName] = [
		FlowCommandResult.PASSENGER_BOARDED,
	]
	destination.presentation_effects_requested.emit(boarding_effects)
	test_runner.assert_false(
		"表现降级 / 缺少摄影棚时登舱 effect 不会永久 busy",
		coordinator.is_presentation_busy()
	)
	var disembark_effects: Array[StringName] = [
		FlowCommandResult.DROPOFF_FEEDBACK_FINISHED,
	]
	destination.presentation_effects_requested.emit(disembark_effects)
	test_runner.assert_false(
		"表现降级 / 缺少摄影棚时离舱 effect 不会永久 busy",
		coordinator.is_presentation_busy()
	)

	destination.set_monitor_presentation_coordinator(null)
	destination.manual_destination_line_edit.text = "612"
	destination._submit_destination()
	test_runner.assert_true(
		"表现降级 / 没有协调器时右台保留原行驶行为",
		manager.is_elevator_moving()
	)
	await manager.elevator_movement_completed

	coordinator.queue_free()
	destination.queue_free()
	manager.queue_free()
	await tree.process_frame


func _complete_current_dispatch(
		test_runner: Variant,
		tree: SceneTree,
		manager: DemoFlowManager,
		stage: MonitorStageController3D,
		console: ConsoleInterface,
	destination: DestinationControlInterface,
	destination_floor: String
) -> void:
	var pickup_floor := manager.get_pickup_floor()
	if manager.get_current_floor() != pickup_floor:
		await _travel_with_destination(
			destination,
			manager,
			pickup_floor,
			false
		)
	test_runner.assert_true(
		"完整表现流程 / 接乘层显示当前 Profile 乘客",
		stage.get_passenger_presentation_state()
				== MonitorStageController3D \
						.PassengerPresentationState.OUTSIDE_WAITING
	)

	console.request_open_door()
	_advance_door_animation(stage)
	await _wait_for_short_tween(tree)
	test_runner.assert_equal(
		"完整表现流程 / 门开完后完成登舱",
		MonitorStageController3D.PassengerPresentationState.CABIN,
		stage.get_passenger_presentation_state()
	)
	console.request_close_door()
	_advance_door_animation(stage)

	await _travel_with_destination(
		destination,
		manager,
		destination_floor,
		true
	)
	var dropoff_open_result := manager.request_open_cabin_door()
	stage.request_door_open_presentation()
	console.presentation_effects_requested.emit(
		dropoff_open_result.get_effects()
	)
	_advance_door_animation(stage)
	test_runner.assert_true(
		"完整表现流程 / destination 对话完成前保持舱内",
		dropoff_open_result.succeeded
				and dropoff_open_result.has_effect(
					FlowCommandResult.DROPOFF_FEEDBACK_REQUESTED
				)
				and stage.get_passenger_presentation_state()
						== MonitorStageController3D \
								.PassengerPresentationState.CABIN
	)
	console.current_dialogue_context = ConsoleInterface.DialogueContext.DESTINATION
	console.current_dialogue_context_finished = false
	console._finish_current_dialogue_context()
	await _wait_for_short_tween(tree)
	test_runner.assert_equal(
		"完整表现流程 / destination 完成后离场",
		MonitorStageController3D.PassengerPresentationState.EXITED,
		stage.get_passenger_presentation_state()
	)
	console.request_close_door()
	_advance_door_animation(stage)


func _travel_with_destination(
		destination: DestinationControlInterface,
		manager: DemoFlowManager,
		floor_id: String,
		should_validate: bool
) -> void:
	destination.manual_destination_line_edit.text = floor_id
	if should_validate:
		destination._verify_destination()
	destination._submit_destination()
	if manager.is_elevator_moving():
		await manager.elevator_movement_completed


func _advance_door_animation(stage: MonitorStageController3D) -> void:
	var door := stage.get_door_visual()
	if door == null:
		return
	var animation_player := door.get_animation_player()
	if animation_player != null and animation_player.is_playing():
		animation_player.advance(2.0)


func _wait_for_short_tween(tree: SceneTree) -> void:
	# 测试实例只把时长调到 0.01 秒；正式场景仍保留 0.5/0.35 秒默认值。
	for _frame_index in 8:
		await tree.process_frame


func _create_fast_stage() -> MonitorStageController3D:
	var stage := MONITOR_STAGE_SCENE.instantiate() as MonitorStageController3D
	stage.boarding_to_threshold_duration = 0.01
	stage.boarding_to_cabin_duration = 0.01
	stage.disembark_to_threshold_duration = 0.01
	stage.disembark_to_outside_duration = 0.01
	stage.disembark_to_exit_duration = 0.01
	return stage


func _create_fast_manager() -> DemoFlowManager:
	var manager := DemoFlowManager.new()
	manager.initial_floor = "900"
	manager.movement_duration_seconds = 0.01
	manager.initial_shift = DEMO_SHIFT
	return manager
