extends RefCounted


func run(test_runner: Variant) -> void:
	var all_phases: Array[String] = DispatchPhase.get_all()
	test_runner.assert_equal("DispatchPhase / 正式阶段数量", 9, all_phases.size())

	var all_phases_are_valid: bool = true
	for phase: String in all_phases:
		all_phases_are_valid = all_phases_are_valid and DispatchPhase.is_valid(phase)
	test_runner.assert_true("DispatchPhase / 所有正式阶段有效", all_phases_are_valid)
	test_runner.assert_false(
		"DispatchPhase / 错误阶段无效",
		DispatchPhase.is_valid("NOT_A_DISPATCH_PHASE")
	)

	var standard_transitions: Array[Array] = [
		[DispatchPhase.WAITING_FOR_PICKUP, DispatchPhase.ARRIVED_AT_PICKUP],
		[DispatchPhase.ARRIVED_AT_PICKUP, DispatchPhase.DOOR_GREETING_DONE],
		[DispatchPhase.ARRIVED_AT_PICKUP, DispatchPhase.BOARDING_WAIT_DOOR_CLOSE],
		[DispatchPhase.DOOR_GREETING_DONE, DispatchPhase.BOARDING_WAIT_DOOR_CLOSE],
		[DispatchPhase.BOARDING_WAIT_DOOR_CLOSE, DispatchPhase.PASSENGER_ONBOARD],
		[DispatchPhase.PASSENGER_ONBOARD, DispatchPhase.ARRIVED_AT_DESTINATION],
		[DispatchPhase.ARRIVED_AT_DESTINATION, DispatchPhase.DROPOFF_FEEDBACK],
		[DispatchPhase.DROPOFF_FEEDBACK, DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE],
	]
	test_runner.assert_true(
		"DispatchPhase / 标准生命周期转换合法",
		_all_transitions_are_allowed(standard_transitions)
	)

	var pickup_return_transitions: Array[Array] = [
		[DispatchPhase.ARRIVED_AT_PICKUP, DispatchPhase.WAITING_FOR_PICKUP],
		[DispatchPhase.DOOR_GREETING_DONE, DispatchPhase.WAITING_FOR_PICKUP],
		[DispatchPhase.WAITING_FOR_PICKUP, DispatchPhase.DOOR_GREETING_DONE],
	]
	test_runner.assert_true(
		"DispatchPhase / 离开和返回接乘楼层转换合法",
		_all_transitions_are_allowed(pickup_return_transitions)
	)
	test_runner.assert_false(
		"DispatchPhase / 非法跨阶段转换失败",
		DispatchPhase.can_transition(
			DispatchPhase.WAITING_FOR_PICKUP,
			DispatchPhase.PASSENGER_ONBOARD
		)
	)
	test_runner.assert_true(
		"DispatchPhase / 同阶段转换幂等合法",
		DispatchPhase.can_transition(
			DispatchPhase.ARRIVED_AT_PICKUP,
			DispatchPhase.ARRIVED_AT_PICKUP
		)
	)


func _all_transitions_are_allowed(transitions: Array[Array]) -> bool:
	for transition: Array in transitions:
		if not DispatchPhase.can_transition(str(transition[0]), str(transition[1])):
			return false
	return true
