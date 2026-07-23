extends RefCounted


const FlowCommandResultScript := preload(
	"res://scripts/runtime/commands/flow_command_result.gd"
)


func run(test_runner: Variant) -> void:
	var success_effects: Array[StringName] = [
		FlowCommandResultScript.DOOR_OPENED,
		FlowCommandResultScript.PASSENGER_BOARDED,
	]
	var succeeded = FlowCommandResultScript.success(
		&"BOARDING_STARTED",
		"乘客已进入舱内。",
		DispatchPhase.ARRIVED_AT_PICKUP,
		DispatchPhase.BOARDING_WAIT_DOOR_CLOSE,
		"004",
		success_effects
	)
	test_runner.assert_true("FlowCommandResult / 成功状态", succeeded.succeeded)
	test_runner.assert_equal(
		"FlowCommandResult / 成功代码",
		&"BOARDING_STARTED",
		succeeded.code
	)
	test_runner.assert_equal(
		"FlowCommandResult / 阶段快照",
		DispatchPhase.BOARDING_WAIT_DOOR_CLOSE,
		succeeded.current_phase
	)
	test_runner.assert_equal(
		"FlowCommandResult / 楼层保留前导零",
		"004",
		succeeded.floor_id
	)
	test_runner.assert_true(
		"FlowCommandResult / 可查询效果",
		succeeded.has_effect(FlowCommandResultScript.PASSENGER_BOARDED)
	)

	var effects_copy: Array[StringName] = succeeded.get_effects()
	effects_copy.clear()
	test_runner.assert_equal(
		"FlowCommandResult / 效果查询返回副本",
		2,
		succeeded.get_effects().size()
	)

	var failed = FlowCommandResultScript.failure(
		&"DOOR_OPEN",
		"请先关闭舱门。",
		DispatchPhase.PASSENGER_ONBOARD,
		DispatchPhase.PASSENGER_ONBOARD,
		"742"
	)
	test_runner.assert_false("FlowCommandResult / 失败状态", failed.succeeded)
	test_runner.assert_equal(
		"FlowCommandResult / 失败不虚构效果",
		0,
		failed.get_effects().size()
	)
