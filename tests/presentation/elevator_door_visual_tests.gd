extends RefCounted


const DOOR_SCENE: PackedScene = preload(
	"res://scenes/presentation/elevator_door_visual_3d.tscn"
)
const MONITOR_STAGE_SCENE: PackedScene = preload(
	"res://scenes/presentation/monitor_test_stage_3d.tscn"
)
const LAYERED_SLICE_SCENE: PackedScene = preload(
	"res://scenes/presentation/layered_floor_slice_2_5d.tscn"
)
const PASSENGER_VISUAL_SCENE: PackedScene = preload(
	"res://scenes/presentation/passenger_visual_3d.tscn"
)
const CONSOLE_SCENE: PackedScene = preload(
	"res://scenes/ui/ConsoleInterface.tscn"
)
const DEMO_SHIFT: ShiftDefinition = preload(
	"res://data/shifts/demo_shift_001.tres"
)


func run(test_runner: Variant, tree: SceneTree) -> void:
	await _test_door_state_machine(test_runner, tree)
	await _test_stage_door_module(test_runner, tree)
	await _test_console_door_integration(test_runner, tree)


func _test_door_state_machine(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var door_candidate := DOOR_SCENE.instantiate()
	test_runner.assert_true(
		"ElevatorDoorVisual3D / 门场景可加载",
		door_candidate is ElevatorDoorVisual3D
	)
	if not door_candidate is ElevatorDoorVisual3D:
		door_candidate.free()
		return

	var door := door_candidate as ElevatorDoorVisual3D
	test_runner.add_child(door)
	await tree.process_frame

	var animation_player := door.get_animation_player()
	var left_door_root := door.get_node(
		"门扇根/左门扇动画根"
	) as Node3D
	var right_door_root := door.get_node(
		"门扇根/右门扇动画根"
	) as Node3D
	test_runner.assert_true(
		"ElevatorDoorVisual3D / 动画播放器与左右门扇可取得",
		animation_player != null
				and left_door_root != null
				and right_door_root != null
	)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / 初始状态为 CLOSED",
		ElevatorDoorVisual3D.DoorPresentationState.CLOSED,
		door.get_door_state()
	)
	test_runner.assert_false(
		"ElevatorDoorVisual3D / 初始状态不 busy",
		door.is_busy()
	)
	test_runner.assert_true(
		"ElevatorDoorVisual3D / 初始状态可接收命令",
		door.is_ready_for_commands()
	)

	var closed_left_position := left_door_root.position
	var closed_right_position := right_door_root.position
	var state_changes: Array[int] = []
	var busy_changes: Array[bool] = []
	var finished_animations: Array[StringName] = []
	var opened_count := {"value": 0}
	var closed_count := {"value": 0}
	door.door_state_changed.connect(
		func(state: int) -> void:
			state_changes.append(state)
	)
	door.door_busy_changed.connect(
		func(is_busy: bool) -> void:
			busy_changes.append(is_busy)
	)
	door.door_opened.connect(
		func() -> void:
			opened_count["value"] = int(opened_count["value"]) + 1
	)
	door.door_closed.connect(
		func() -> void:
			closed_count["value"] = int(closed_count["value"]) + 1
	)
	animation_player.animation_finished.connect(
		func(animation_name: StringName) -> void:
			finished_animations.append(animation_name)
	)

	test_runner.assert_false(
		"ElevatorDoorVisual3D / CLOSED 时拒绝 request_close",
		door.request_close()
	)
	test_runner.assert_true(
		"ElevatorDoorVisual3D / CLOSED 时 request_open 成功",
		door.request_open()
	)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / 开门开始后进入 OPENING",
		ElevatorDoorVisual3D.DoorPresentationState.OPENING,
		door.get_door_state()
	)
	test_runner.assert_true(
		"ElevatorDoorVisual3D / OPENING 时 busy",
		door.is_busy()
	)

	# 先推进到动画中段，再发出非法命令，验证拒绝不会重播或跳帧。
	animation_player.advance(0.25)
	var opening_position := animation_player.current_animation_position
	var opening_left_position := left_door_root.position
	var opening_right_position := right_door_root.position
	test_runner.assert_false(
		"ElevatorDoorVisual3D / OPENING 时拒绝重复 request_open",
		door.request_open()
	)
	test_runner.assert_false(
		"ElevatorDoorVisual3D / OPENING 时拒绝 request_close",
		door.request_close()
	)
	test_runner.assert_true(
		"ElevatorDoorVisual3D / OPENING 拒绝命令不改变动画进度",
		is_equal_approx(
			opening_position,
			animation_player.current_animation_position
		)
				and left_door_root.position.is_equal_approx(
					opening_left_position
				)
				and right_door_root.position.is_equal_approx(
					opening_right_position
				)
	)

	animation_player.advance(2.0)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / door_open 结束后进入 OPEN",
		ElevatorDoorVisual3D.DoorPresentationState.OPEN,
		door.get_door_state()
	)
	test_runner.assert_false(
		"ElevatorDoorVisual3D / OPEN 状态不 busy",
		door.is_busy()
	)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / 开门完成信号只发送一次",
		1,
		int(opened_count["value"])
	)
	var open_left_position := left_door_root.position
	var open_right_position := right_door_root.position
	test_runner.assert_false(
		"ElevatorDoorVisual3D / OPEN 时拒绝 request_open",
		door.request_open()
	)
	test_runner.assert_true(
		"ElevatorDoorVisual3D / OPEN 时 request_close 成功",
		door.request_close()
	)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / 关门开始后进入 CLOSING",
		ElevatorDoorVisual3D.DoorPresentationState.CLOSING,
		door.get_door_state()
	)

	animation_player.advance(0.25)
	var closing_position := animation_player.current_animation_position
	var closing_left_position := left_door_root.position
	var closing_right_position := right_door_root.position
	test_runner.assert_false(
		"ElevatorDoorVisual3D / CLOSING 时拒绝 request_open",
		door.request_open()
	)
	test_runner.assert_false(
		"ElevatorDoorVisual3D / CLOSING 时拒绝重复 request_close",
		door.request_close()
	)
	test_runner.assert_true(
		"ElevatorDoorVisual3D / CLOSING 拒绝命令不改变动画进度",
		is_equal_approx(
			closing_position,
			animation_player.current_animation_position
		)
				and left_door_root.position.is_equal_approx(
					closing_left_position
				)
				and right_door_root.position.is_equal_approx(
					closing_right_position
				)
	)

	animation_player.advance(2.0)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / door_close 结束后回到 CLOSED",
		ElevatorDoorVisual3D.DoorPresentationState.CLOSED,
		door.get_door_state()
	)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / 关门完成信号只发送一次",
		1,
		int(closed_count["value"])
	)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / 完整状态转换顺序正确",
		[
			ElevatorDoorVisual3D.DoorPresentationState.OPENING,
			ElevatorDoorVisual3D.DoorPresentationState.OPEN,
			ElevatorDoorVisual3D.DoorPresentationState.CLOSING,
			ElevatorDoorVisual3D.DoorPresentationState.CLOSED,
		],
		state_changes
	)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / busy 信号与两段动画同步",
		[true, false, true, false],
		busy_changes
	)
	test_runner.assert_equal(
		"ElevatorDoorVisual3D / AnimationPlayer 发出开关门完成信号",
		[
			ElevatorDoorVisual3D.ANIMATION_OPEN,
			ElevatorDoorVisual3D.ANIMATION_CLOSE,
		],
		finished_animations
	)

	test_runner.assert_true(
		"ElevatorDoorVisual3D / 可再次开始开门以验证 snap",
		door.request_open()
	)
	animation_player.advance(0.25)
	door.snap_open()
	test_runner.assert_true(
		"ElevatorDoorVisual3D / snap_open 立即停止动画并进入 OPEN",
		door.is_open()
				and not door.is_busy()
				and not animation_player.is_playing()
				and left_door_root.position.is_equal_approx(
					open_left_position
				)
				and right_door_root.position.is_equal_approx(
					open_right_position
				)
	)
	door.snap_closed()
	test_runner.assert_true(
		"ElevatorDoorVisual3D / snap_closed 立即恢复关闭姿态",
		door.is_closed()
				and not door.is_busy()
				and not animation_player.is_playing()
				and left_door_root.position.is_equal_approx(
					closed_left_position
				)
				and right_door_root.position.is_equal_approx(
					closed_right_position
				)
	)

	door.queue_free()
	await tree.process_frame


func _test_stage_door_module(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var stage_candidate := MONITOR_STAGE_SCENE.instantiate()
	test_runner.assert_true(
		"MonitorStageController3D / 摄影棚场景可加载",
		stage_candidate is MonitorStageController3D
	)
	if not stage_candidate is MonitorStageController3D:
		stage_candidate.free()
		return

	var stage := stage_candidate as MonitorStageController3D
	test_runner.add_child(stage)
	await tree.process_frame

	var door := stage.get_door_visual()
	test_runner.assert_true(
		"MonitorStageController3D / 可取得独立双开门视觉",
		door != null and door.is_ready_for_commands()
	)
	if door == null:
		stage.queue_free()
		await tree.process_frame
		return

	var door_parent := door.get_parent()
	var replacement_slice := stage.replace_floor_slice(
		LAYERED_SLICE_SCENE
	)
	var replacement_passenger := stage.replace_passenger_visual(
		PASSENGER_VISUAL_SCENE
	)
	await tree.process_frame
	test_runner.assert_true(
		"MonitorStageController3D / 替换楼层切片不会删除门",
		replacement_slice != null
				and is_instance_valid(door)
				and stage.get_door_visual() == door
				and door.get_parent() == door_parent
	)
	test_runner.assert_true(
		"MonitorStageController3D / 替换乘客视觉不会删除门",
		replacement_passenger != null
				and is_instance_valid(door)
				and stage.get_door_visual() == door
	)

	test_runner.assert_true(
		"MonitorStageController3D / sync(true) 立即同步为开启",
		stage.sync_door_presentation(true)
				and door.is_open()
				and not stage.is_door_presentation_busy()
	)
	test_runner.assert_true(
		"MonitorStageController3D / sync(false) 立即同步为关闭",
		stage.sync_door_presentation(false)
				and door.is_closed()
				and not stage.is_door_presentation_busy()
	)

	var state_changes: Array[int] = []
	var busy_changes: Array[bool] = []
	var opened_count := {"value": 0}
	var closed_count := {"value": 0}
	stage.door_presentation_state_changed.connect(
		func(state: int) -> void:
			state_changes.append(state)
	)
	stage.door_presentation_busy_changed.connect(
		func(is_busy: bool) -> void:
			busy_changes.append(is_busy)
	)
	stage.door_presentation_opened.connect(
		func() -> void:
			opened_count["value"] = int(opened_count["value"]) + 1
	)
	stage.door_presentation_closed.connect(
		func() -> void:
			closed_count["value"] = int(closed_count["value"]) + 1
	)

	test_runner.assert_true(
		"MonitorStageController3D / 可代理开门请求",
		stage.request_door_open_presentation()
	)
	test_runner.assert_true(
		"MonitorStageController3D / 开门动画期间代理 busy",
		stage.is_door_presentation_busy()
	)
	var animation_player := door.get_animation_player()
	animation_player.advance(0.25)
	var animation_position := animation_player.current_animation_position
	var stage_left_door_root := door.get_node(
		"门扇根/左门扇动画根"
	) as Node3D
	var leaf_position: Vector3 = stage_left_door_root.position
	test_runner.assert_true(
		"MonitorStageController3D / 楼层与乘客操作不重置门动画",
		stage.set_floor_display_id(&"612")
				and stage.set_passenger_position(
					MonitorStageController3D.PASSENGER_POSITION_OUTSIDE
				)
				and door.get_door_state()
						== ElevatorDoorVisual3D.DoorPresentationState.OPENING
				and is_equal_approx(
					animation_position,
					animation_player.current_animation_position
				)
				and stage_left_door_root.position.is_equal_approx(
					leaf_position
				)
	)
	animation_player.advance(2.0)
	test_runner.assert_true(
		"MonitorStageController3D / 可代理关门请求",
		stage.request_door_close_presentation()
	)
	animation_player.advance(2.0)
	test_runner.assert_equal(
		"MonitorStageController3D / 门状态信号完整转发",
		[
			ElevatorDoorVisual3D.DoorPresentationState.OPENING,
			ElevatorDoorVisual3D.DoorPresentationState.OPEN,
			ElevatorDoorVisual3D.DoorPresentationState.CLOSING,
			ElevatorDoorVisual3D.DoorPresentationState.CLOSED,
		],
		state_changes
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 门 busy 信号完整转发",
		[true, false, true, false],
		busy_changes
	)
	test_runner.assert_true(
		"MonitorStageController3D / 开关门完成信号完整转发",
		int(opened_count["value"]) == 1
				and int(closed_count["value"]) == 1
	)

	stage.queue_free()
	await tree.process_frame


func _test_console_door_integration(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var manager := await _create_manager(test_runner, tree)
	var stage := MONITOR_STAGE_SCENE.instantiate() as MonitorStageController3D
	var console := CONSOLE_SCENE.instantiate() as ConsoleInterface
	test_runner.add_child(stage)
	test_runner.add_child(console)
	await tree.process_frame
	console.set_demo_flow_manager(manager)
	console.set_monitor_stage_controller(stage)

	var door := stage.get_door_visual()
	var animation_player := door.get_animation_player()
	console.request_open_door()
	test_runner.assert_true(
		"ConsoleInterface / DOOR_OPENED effect 触发开门动画",
		manager.is_cabin_door_open()
				and door.get_door_state()
						== ElevatorDoorVisual3D.DoorPresentationState.OPENING
	)
	test_runner.assert_true(
		"ConsoleInterface / 动画 busy 时两个按钮统一禁用",
		console.open_door_button.disabled
				and console.close_door_button.disabled
	)

	animation_player.advance(0.25)
	var opening_position := animation_player.current_animation_position
	console.request_close_door()
	test_runner.assert_true(
		"ConsoleInterface / OPENING 时统一入口拒绝业务关门",
		manager.is_cabin_door_open()
				and door.get_door_state()
						== ElevatorDoorVisual3D.DoorPresentationState.OPENING
				and is_equal_approx(
					opening_position,
					animation_player.current_animation_position
				)
				and console.system_hint_label.text
						== ConsoleInterface.DOOR_PRESENTATION_BUSY_HINT
	)
	animation_player.advance(2.0)

	console.request_close_door()
	test_runner.assert_true(
		"ConsoleInterface / DOOR_CLOSED effect 触发关门动画",
		not manager.is_cabin_door_open()
				and door.get_door_state()
						== ElevatorDoorVisual3D.DoorPresentationState.CLOSING
	)
	animation_player.advance(0.25)
	var closing_position := animation_player.current_animation_position
	console.request_open_door()
	test_runner.assert_true(
		"ConsoleInterface / CLOSING 时统一入口拒绝业务开门",
		not manager.is_cabin_door_open()
				and door.get_door_state()
						== ElevatorDoorVisual3D.DoorPresentationState.CLOSING
				and is_equal_approx(
					closing_position,
					animation_player.current_animation_position
				)
				and console.system_hint_label.text
						== ConsoleInterface.DOOR_PRESENTATION_BUSY_HINT
	)
	animation_player.advance(2.0)

	var movement_result := manager.request_travel_to_floor("612")
	console.request_open_door()
	test_runner.assert_true(
		"ConsoleInterface / 业务开门失败时不播放动画",
		movement_result.succeeded
				and manager.is_elevator_moving()
				and not manager.is_cabin_door_open()
				and door.is_closed()
				and not animation_player.is_playing()
	)
	await manager.elevator_movement_completed

	# 移除表现层后，接乘层开关门仍通过原业务命令推进。
	console.set_monitor_stage_controller(null)
	console.request_open_door()
	test_runner.assert_true(
		"ConsoleInterface / 无 MonitorStage 时业务开门正常降级",
		manager.is_cabin_door_open()
				and manager.is_passenger_onboard()
	)
	console.request_close_door()
	test_runner.assert_true(
		"ConsoleInterface / 无 MonitorStage 时业务关门正常降级",
		not manager.is_cabin_door_open()
				and manager.is_cabin_door_closed_after_boarding()
	)

	test_runner.assert_true(
		"ConsoleInterface / 派单结算前目标楼层验证成功",
		manager.request_validate_destination("900").succeeded
	)
	test_runner.assert_true(
		"ConsoleInterface / 派单结算前可前往目标楼层",
		await _move_to(manager, "900")
	)
	console.set_monitor_stage_controller(stage)
	console.request_open_door()
	animation_player.advance(2.0)
	if manager.get_case_phase() == DispatchPhase.DROPOFF_FEEDBACK:
		manager.request_finish_dropoff_feedback()
	test_runner.assert_true(
		"ConsoleInterface / 到站反馈进入等待关门阶段",
		manager.get_case_phase() == DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE
	)
	console.request_close_door()
	test_runner.assert_true(
		"ConsoleInterface / DISPATCH_COMPLETED 前先触发关门动画",
		manager.has_active_dispatch()
				and String(manager.get_active_dispatch().dispatch_id)
						== "CASE_002"
				and door.get_door_state()
						== ElevatorDoorVisual3D.DoorPresentationState.CLOSING
	)
	animation_player.advance(2.0)

	console.queue_free()
	stage.queue_free()
	manager.queue_free()
	await tree.process_frame


func _create_manager(
		test_runner: Variant,
		tree: SceneTree
) -> DemoFlowManager:
	var manager := DemoFlowManager.new()
	manager.initial_floor = "900"
	manager.movement_duration_seconds = 0.01
	manager.initial_shift = DEMO_SHIFT
	test_runner.add_child(manager)
	await tree.process_frame
	return manager


func _move_to(
		manager: DemoFlowManager,
		destination: String
) -> bool:
	var result = manager.request_travel_to_floor(destination)
	if not result.succeeded:
		return false
	await manager.elevator_movement_completed
	return manager.get_current_floor() == destination
