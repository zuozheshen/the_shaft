extends RefCounted


const DEMO_SHIFT: ShiftDefinition = preload("res://data/shifts/demo_shift_001.tres")
const ShiftRunnerScript := preload("res://scripts/runtime/shift/shift_runner.gd")


func run(test_runner: Variant) -> void:
	var runner = ShiftRunnerScript.new()
	test_runner.assert_true("ShiftRunner / 有效值班开始", runner.start_shift(DEMO_SHIFT))
	test_runner.assert_equal(
		"ShiftRunner / 第一条派单顺序正确",
		&"CASE_001",
		runner.get_next_dispatch_id()
	)
	test_runner.assert_equal(
		"ShiftRunner / 第二条派单顺序正确",
		&"CASE_002",
		runner.get_next_dispatch_id()
	)
	test_runner.assert_equal(
		"ShiftRunner / 第三条派单顺序正确",
		&"CASE_003",
		runner.get_next_dispatch_id()
	)
	test_runner.assert_equal(
		"ShiftRunner / 派单耗尽后返回空 ID",
		&"",
		runner.get_next_dispatch_id()
	)

	var result := DispatchResult.create(&"CASE_001", &"passenger_001", &"900", 1)
	test_runner.assert_true(
		"ShiftRunner / 完成结果可以记录",
		runner.record_completed_result(result)
	)
	var result_copy: Array[DispatchResult] = runner.get_completed_results()
	result_copy.clear()
	test_runner.assert_equal(
		"ShiftRunner / 完成结果查询返回副本",
		1,
		runner.get_completed_results().size()
	)

	var empty_shift := ShiftDefinition.new()
	test_runner.assert_false("ShiftRunner / 空值班安全失败", runner.start_shift(empty_shift))
	test_runner.assert_true("ShiftRunner / 重启有效值班", runner.start_shift(DEMO_SHIFT))
	test_runner.assert_equal(
		"ShiftRunner / 重启值班清空旧结果",
		0,
		runner.get_completed_results().size()
	)
	test_runner.assert_equal(
		"ShiftRunner / 重启值班从第一条开始",
		&"CASE_001",
		runner.get_next_dispatch_id()
	)
	test_runner.assert_true("ShiftRunner / 首次结束值班成功", runner.finish_shift())
	test_runner.assert_false("ShiftRunner / 重复结束值班幂等", runner.finish_shift())
	test_runner.assert_true("ShiftRunner / 结束状态可查询", runner.is_finished())
