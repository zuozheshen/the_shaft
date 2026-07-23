extends RefCounted


const CASE_001: DispatchDefinition = preload("res://data/dispatches/case_001.tres")
const CASE_002: DispatchDefinition = preload("res://data/dispatches/case_002.tres")
const DispatchLifecycleScript := preload(
	"res://scripts/runtime/dispatch/dispatch_lifecycle.gd"
)


func run(test_runner: Variant) -> void:
	var lifecycle = DispatchLifecycleScript.new()
	test_runner.assert_true(
		"DispatchLifecycle / 第一条派单建立",
		lifecycle.start_dispatch(CASE_001)
	)
	var first_state: ActiveDispatchState = lifecycle.get_active_state()
	lifecycle.set_passenger_inside(true)
	lifecycle.set_validated_floor("900")
	lifecycle.set_selected_target_floor("900")
	lifecycle.try_mark_arrival_triggered()

	test_runner.assert_true(
		"DispatchLifecycle / 第二条派单建立",
		lifecycle.start_dispatch(CASE_002)
	)
	var second_state: ActiveDispatchState = lifecycle.get_active_state()
	test_runner.assert_not_equal(
		"DispatchLifecycle / 新派单使用隔离状态对象",
		first_state,
		second_state
	)
	test_runner.assert_false(
		"DispatchLifecycle / 新派单不继承乘客状态",
		lifecycle.is_passenger_inside()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 新派单不继承验证楼层",
		"",
		lifecycle.get_validated_floor()
	)

	test_runner.assert_true(
		"DispatchLifecycle / 合法阶段转换",
		lifecycle.try_set_phase(DispatchPhase.ARRIVED_AT_PICKUP)
	)
	test_runner.assert_false(
		"DispatchLifecycle / 非法阶段转换",
		lifecycle.try_set_phase(DispatchPhase.PASSENGER_ONBOARD)
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 非法转换不修改阶段",
		DispatchPhase.ARRIVED_AT_PICKUP,
		lifecycle.get_phase()
	)
	test_runner.assert_true(
		"DispatchLifecycle / 乘客状态可写入",
		lifecycle.set_passenger_inside(true)
	)
	test_runner.assert_true(
		"DispatchLifecycle / 乘客状态可查询",
		lifecycle.is_passenger_inside()
	)
	test_runner.assert_true(
		"DispatchLifecycle / 到站反馈首次标记成功",
		lifecycle.try_mark_arrival_triggered()
	)
	test_runner.assert_false(
		"DispatchLifecycle / 到站反馈标记幂等",
		lifecycle.try_mark_arrival_triggered()
	)

	test_runner.assert_true(
		"DispatchLifecycle / 推荐楼层首次添加成功",
		lifecycle.add_recommended_floor(&"900")
	)
	test_runner.assert_false(
		"DispatchLifecycle / 推荐楼层自动去重",
		lifecycle.add_recommended_floor(&"900")
	)
	var recommendation_copy: Array[StringName] = lifecycle.get_recommended_floor_ids()
	recommendation_copy.clear()
	test_runner.assert_not_equal(
		"DispatchLifecycle / 推荐楼层查询返回副本",
		0,
		lifecycle.get_recommended_floor_ids().size()
	)

	lifecycle.clear()
	test_runner.assert_false(
		"DispatchLifecycle / 清除后无活动派单",
		lifecycle.has_active_dispatch()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 清除后阶段查询安全",
		DispatchPhase.SHIFT_IDLE,
		lifecycle.get_phase()
	)
	test_runner.assert_false(
		"DispatchLifecycle / 清除后乘客查询安全",
		lifecycle.is_passenger_inside()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 清除后推荐查询安全",
		0,
		lifecycle.get_recommended_floor_ids().size()
	)

	_test_atomic_commands(test_runner)


func _test_atomic_commands(test_runner: Variant) -> void:
	var pickup = DispatchLifecycleScript.new()
	pickup.start_dispatch(CASE_001, DispatchPhase.ARRIVED_AT_PICKUP)
	test_runner.assert_true(
		"DispatchLifecycle / 门外确认原子成功",
		pickup.complete_door_greeting()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 门外确认原子转换阶段",
		DispatchPhase.DOOR_GREETING_DONE,
		pickup.get_phase()
	)
	test_runner.assert_true(
		"DispatchLifecycle / 门外确认原子写入标记",
		pickup.is_door_greeting_done()
	)
	test_runner.assert_false(
		"DispatchLifecycle / 错误阶段门外确认失败",
		pickup.complete_door_greeting()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 失败门外确认保持阶段",
		DispatchPhase.DOOR_GREETING_DONE,
		pickup.get_phase()
	)

	test_runner.assert_true(
		"DispatchLifecycle / 登舱原子成功",
		pickup.board_passenger()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 登舱原子转换阶段",
		DispatchPhase.BOARDING_WAIT_DOOR_CLOSE,
		pickup.get_phase()
	)
	test_runner.assert_true(
		"DispatchLifecycle / 登舱原子写入乘客状态",
		pickup.is_passenger_inside()
	)
	test_runner.assert_false(
		"DispatchLifecycle / 登舱时门后确认保持未完成",
		pickup.is_cabin_door_closed_after_boarding()
	)
	test_runner.assert_true(
		"DispatchLifecycle / 关门确认原子成功",
		pickup.secure_passenger_after_door_close()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 关门确认原子转换舱内阶段",
		DispatchPhase.PASSENGER_ONBOARD,
		pickup.get_phase()
	)
	test_runner.assert_true(
		"DispatchLifecycle / 关门确认原子写入门控状态",
		pickup.is_cabin_door_closed_after_boarding()
	)

	var invalid_boarding = DispatchLifecycleScript.new()
	invalid_boarding.start_dispatch(CASE_001, DispatchPhase.WAITING_FOR_PICKUP)
	test_runner.assert_false(
		"DispatchLifecycle / 错误阶段登舱失败",
		invalid_boarding.board_passenger()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 失败登舱不改变阶段",
		DispatchPhase.WAITING_FOR_PICKUP,
		invalid_boarding.get_phase()
	)
	test_runner.assert_false(
		"DispatchLifecycle / 失败登舱不改变乘客状态",
		invalid_boarding.is_passenger_inside()
	)

	var invalid_secure = DispatchLifecycleScript.new()
	invalid_secure.start_dispatch(
		CASE_001,
		DispatchPhase.BOARDING_WAIT_DOOR_CLOSE
	)
	test_runner.assert_false(
		"DispatchLifecycle / 无乘客时关门确认失败",
		invalid_secure.secure_passenger_after_door_close()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 失败关门确认不改变阶段",
		DispatchPhase.BOARDING_WAIT_DOOR_CLOSE,
		invalid_secure.get_phase()
	)
	test_runner.assert_false(
		"DispatchLifecycle / 失败关门确认不改变门控标记",
		invalid_secure.is_cabin_door_closed_after_boarding()
	)

	var dropoff = DispatchLifecycleScript.new()
	dropoff.start_dispatch(CASE_001, DispatchPhase.PASSENGER_ONBOARD)
	dropoff.set_passenger_inside(true)
	dropoff.set_cabin_door_closed_after_boarding(true)
	dropoff.try_set_phase(DispatchPhase.ARRIVED_AT_DESTINATION)
	test_runner.assert_true(
		"DispatchLifecycle / 到站反馈原子成功",
		dropoff.begin_dropoff_feedback()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 到站反馈原子转换阶段",
		DispatchPhase.DROPOFF_FEEDBACK,
		dropoff.get_phase()
	)
	test_runner.assert_true(
		"DispatchLifecycle / 到站反馈原子写入触发标记",
		dropoff.is_arrival_triggered()
	)
	test_runner.assert_false(
		"DispatchLifecycle / 到站反馈不能重复开始",
		dropoff.begin_dropoff_feedback()
	)
	test_runner.assert_equal(
		"DispatchLifecycle / 失败到站反馈保持阶段",
		DispatchPhase.DROPOFF_FEEDBACK,
		dropoff.get_phase()
	)
