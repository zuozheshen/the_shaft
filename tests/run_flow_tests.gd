extends Node


const DispatchPhaseTests := preload("res://tests/flow/dispatch_phase_tests.gd")
const DemoFlowManagerTests := preload("res://tests/flow/demo_flow_manager_tests.gd")
const ElevatorRuntimeStateTests := preload(
	"res://tests/runtime/elevator_runtime_state_tests.gd"
)
const DispatchLifecycleTests := preload(
	"res://tests/runtime/dispatch_lifecycle_tests.gd"
)
const ShiftRunnerTests := preload("res://tests/runtime/shift_runner_tests.gd")
const UIHistoryStateTests := preload("res://tests/runtime/ui_history_state_tests.gd")
const FlowCommandResultTests := preload(
	"res://tests/runtime/flow_command_result_tests.gd"
)
const FlowCommandTests := preload("res://tests/flow/flow_command_tests.gd")
const ContentValidationReportTests := preload(
	"res://tests/content/content_validation_report_tests.gd"
)
const ContentValidatorTests := preload(
	"res://tests/content/content_validator_tests.gd"
)
const Case003ContentTests := preload(
	"res://tests/content/case_003_content_tests.gd"
)
const MonitorStageTests := preload(
	"res://tests/presentation/monitor_stage_tests.gd"
)
const ElevatorDoorVisualTests := preload(
	"res://tests/presentation/elevator_door_visual_tests.gd"
)
const MonitorPassengerTimelineTests := preload(
	"res://tests/presentation/monitor_passenger_timeline_tests.gd"
)

var passed_count: int = 0
var failed_count: int = 0


func _ready() -> void:
	# 延后一帧运行，确保项目 Autoload 已完成资源注册。
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	print("=== The Shaft 自动测试 ===")

	var content_validation_report_tests := ContentValidationReportTests.new()
	content_validation_report_tests.run(self)

	var content_validator_tests := ContentValidatorTests.new()
	content_validator_tests.run(self)

	var case_003_content_tests := Case003ContentTests.new()
	case_003_content_tests.run(self)

	var dispatch_phase_tests := DispatchPhaseTests.new()
	dispatch_phase_tests.run(self)

	var elevator_runtime_state_tests := ElevatorRuntimeStateTests.new()
	await elevator_runtime_state_tests.run(self, get_tree())

	var dispatch_lifecycle_tests := DispatchLifecycleTests.new()
	dispatch_lifecycle_tests.run(self)

	var shift_runner_tests := ShiftRunnerTests.new()
	shift_runner_tests.run(self)

	var ui_history_state_tests := UIHistoryStateTests.new()
	ui_history_state_tests.run(self)

	var flow_command_result_tests := FlowCommandResultTests.new()
	flow_command_result_tests.run(self)

	var demo_flow_manager_tests := DemoFlowManagerTests.new()
	await demo_flow_manager_tests.run(self, get_tree())

	var flow_command_tests := FlowCommandTests.new()
	await flow_command_tests.run(self, get_tree())

	var monitor_stage_tests := MonitorStageTests.new()
	await monitor_stage_tests.run(self, get_tree())

	var elevator_door_visual_tests := ElevatorDoorVisualTests.new()
	await elevator_door_visual_tests.run(self, get_tree())

	var monitor_passenger_timeline_tests := MonitorPassengerTimelineTests.new()
	await monitor_passenger_timeline_tests.run(self, get_tree())

	print("=== 测试汇总：通过 %d，失败 %d ===" % [passed_count, failed_count])
	get_tree().quit(0 if failed_count == 0 else 1)


func assert_true(test_name: String, condition: bool, detail: String = "") -> void:
	_record_result(test_name, condition, detail)


func assert_false(test_name: String, condition: bool, detail: String = "") -> void:
	_record_result(test_name, not condition, detail)


func assert_equal(test_name: String, expected: Variant, actual: Variant) -> void:
	_record_result(
		test_name,
		expected == actual,
		"期望：%s；实际：%s" % [str(expected), str(actual)]
	)


func assert_not_equal(test_name: String, unexpected: Variant, actual: Variant) -> void:
	_record_result(
		test_name,
		unexpected != actual,
		"不应为：%s；实际：%s" % [str(unexpected), str(actual)]
	)


func _record_result(test_name: String, passed: bool, detail: String) -> void:
	if passed:
		passed_count += 1
		print("PASS | %s" % test_name)
		return
	failed_count += 1
	printerr("FAIL | %s%s" % [
		test_name,
		"" if detail.is_empty() else " | %s" % detail,
	])
