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
