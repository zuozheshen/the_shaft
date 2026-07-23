extends RefCounted


const ElevatorRuntimeStateScript := preload(
	"res://scripts/runtime/elevator/elevator_runtime_state.gd"
)


func run(test_runner: Variant, tree: SceneTree) -> void:
	var elevator = ElevatorRuntimeStateScript.new()
	tree.root.add_child(elevator)
	elevator.initialize("900", 0.01)

	test_runner.assert_equal("ElevatorRuntimeState / 初始化楼层", "900", elevator.current_floor)
	test_runner.assert_equal("ElevatorRuntimeState / 初始化目标为空", "", elevator.target_floor)
	test_runner.assert_false("ElevatorRuntimeState / 初始化舱门关闭", elevator.is_cabin_door_open())
	test_runner.assert_false("ElevatorRuntimeState / 初始化不在移动", elevator.is_moving())

	elevator.initialize("742", 0.01)
	test_runner.assert_equal(
		"ElevatorRuntimeState / 重复初始化不创建多个 Timer",
		1,
		elevator.get_child_count()
	)

	elevator.set_cabin_door_open(true)
	test_runner.assert_false(
		"ElevatorRuntimeState / 门开不能移动",
		elevator.request_movement("612")
	)
	elevator.set_cabin_door_open(false)

	var movement_signal_counter := {"count": 0}
	elevator.movement_completed.connect(
		func(_arrived_floor: String) -> void:
			movement_signal_counter["count"] = int(movement_signal_counter["count"]) + 1
	)
	test_runner.assert_true(
		"ElevatorRuntimeState / 有效目标开始移动",
		elevator.request_movement("612")
	)
	test_runner.assert_false(
		"ElevatorRuntimeState / 移动中不能重复移动",
		elevator.request_movement("900")
	)
	await elevator.movement_completed
	await tree.process_frame
	test_runner.assert_equal(
		"ElevatorRuntimeState / 到站更新当前位置",
		"612",
		elevator.current_floor
	)
	test_runner.assert_equal(
		"ElevatorRuntimeState / 到站清空目标楼层",
		"",
		elevator.target_floor
	)
	test_runner.assert_equal(
		"ElevatorRuntimeState / 到站信号只发送一次",
		1,
		int(movement_signal_counter["count"])
	)

	elevator.queue_free()
	await tree.process_frame
