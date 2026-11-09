extends Node

const AudioShutdown := preload("res://scripts/runtime/audio_shutdown.gd")
const TestContent := preload("res://tests/fixtures/runtime/test_content.gd")

# 登记顺序就是全量执行顺序；每条注明 run 签名和是否需要注入内容。
enum { ID, GROUP, SCRIPT, TAKES_TREE, USES_FIXTURE }
const MODULES := [
	["audio_shutdown", "Audio", preload("res://tests/runtime/audio_shutdown_tests.gd"), true, false],
	["content_validation_report", "Content", preload("res://tests/content/content_validation_report_tests.gd"), false, false],
	["content_validator", "Content", preload("res://tests/content/content_validator_tests.gd"), false, false],
	["content_reset", "Content", preload("res://tests/content/content_reset_tests.gd"), true, false],
	["dispatch_phase", "Flow", preload("res://tests/flow/dispatch_phase_tests.gd"), false, true],
	["elevator_runtime_state", "Runtime", preload("res://tests/runtime/elevator_runtime_state_tests.gd"), true, true],
	["dispatch_lifecycle", "Runtime", preload("res://tests/runtime/dispatch_lifecycle_tests.gd"), false, true],
	["shift_runner", "Runtime", preload("res://tests/runtime/shift_runner_tests.gd"), false, true],
	["ui_history_state", "Runtime", preload("res://tests/runtime/ui_history_state_tests.gd"), false, true],
	["flow_command_result", "Runtime", preload("res://tests/runtime/flow_command_result_tests.gd"), false, true],
	["demo_flow_manager", "Flow", preload("res://tests/flow/demo_flow_manager_tests.gd"), true, true],
	["flow_command", "Flow", preload("res://tests/flow/flow_command_tests.gd"), true, true],
	["monitor_stage", "Presentation", preload("res://tests/presentation/monitor_stage_tests.gd"), true, true],
	["floor_visual_profile", "Presentation", preload("res://tests/presentation/floor_visual_profile_tests.gd"), true, true],
	["elevator_door_visual", "Presentation", preload("res://tests/presentation/elevator_door_visual_tests.gd"), true, true],
	["monitor_passenger_timeline", "Presentation", preload("res://tests/presentation/monitor_passenger_timeline_tests.gd"), true, true],
	["main_console", "MainConsole", preload("res://tests/ui/main_console_tests.gd"), true, true],
	["left_console", "LeftConsole", preload("res://tests/ui/left_console_tests.gd"), true, true],
	["right_console", "RightConsole", preload("res://tests/ui/right_console_tests.gd"), true, true],
	["gamepad_support", "Gamepad", preload("res://tests/ui/gamepad_support_tests.gd"), true, true],
]

var passed_count: int = 0
var failed_count: int = 0


func _ready() -> void:
	# 移除节点后音频线程可能仍持有播放；在 PREDELETE 之前记录弱引用，避免在退出树中重入 stop。
	get_tree().node_removed.connect(AudioShutdown.track_removed_player)
	call_deferred("_run")


func _run() -> void:
	# 等待项目 Autoload 完成资源注册。
	await get_tree().process_frame
	var group := _read_group()
	if group.is_empty():
		printerr("FAIL | invalid or conflicting test group")
		await _finish(true)
		return

	var selected: Array[Array] = []
	var selected_ids := PackedStringArray()
	var skipped_ids := PackedStringArray()
	for entry: Array in MODULES:
		if group == "All" or group.nocasecmp_to(entry[GROUP]) == 0:
			selected.append(entry)
			selected_ids.append(entry[ID])
		else:
			skipped_ids.append(entry[ID])
	if selected.is_empty():
		printerr("FAIL | no modules match group: %s" % group)
		await _finish(true)
		return

	print("=== The Shaft 自动测试 ===")
	print("MODULE SELECTED | %s" % ", ".join(selected_ids))
	print("MODULE SKIPPED | %s" % ", ".join(skipped_ids))

	var fixture_installed := false
	var completed: Array[Dictionary] = []
	for entry: Array in selected:
		# 正式空舱用例必须在注入前执行；分组执行独立准备所需夹具。
		if entry[USES_FIXTURE] and not fixture_installed:
			print("HOST | install test content")
			TestContent.install(ContentRegistry)
			fixture_installed = true
		var id: String = entry[ID]
		var passed_before := passed_count
		var failed_before := failed_count
		print("MODULE START | %s" % id)
		var start := Time.get_ticks_usec()
		var suite: Variant = entry[SCRIPT].new()
		if entry[TAKES_TREE]:
			await suite.run(self, get_tree())
		else:
			await suite.run(self)
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		completed.append({"id": id, "ms": elapsed})
		print("MODULE END | %s | elapsed_ms=%.2f | passed=%d | failed=%d" % [
			id, elapsed, passed_count - passed_before, failed_count - failed_before,
		])

	if fixture_installed:
		TestContent.restore(ContentRegistry)
		print("HOST | restore test content")
	print("MODULE SUMMARY | group=%s | selected=%d | completed=%d | not_selected=%d" % [
		group, selected.size(), completed.size(), skipped_ids.size(),
	])
	completed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	for index in mini(5, completed.size()):
		print("SLOW MODULE | %s | elapsed_ms=%.2f" % [completed[index].id, completed[index].ms])
	await _finish()


func _read_group() -> String:
	var group := "All"
	var has_group := false
	var audio_only := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--audio-shutdown-only":
			audio_only = true
		elif argument == "--group" or argument.begins_with("--group="):
			if has_group or argument == "--group":
				return ""
			group = argument.trim_prefix("--group=")
			has_group = true
	if audio_only:
		if has_group and group.nocasecmp_to("Audio") != 0:
			return ""
		return "Audio"
	if group.nocasecmp_to("All") == 0:
		return "All"
	for entry: Array in MODULES:
		if group.nocasecmp_to(entry[GROUP]) == 0:
			return entry[GROUP]
	return ""


func _finish(invalid_selection: bool = false) -> void:
	# 夹具释放后等待音频实例真正退出，所有分组共用此收尾。
	print("HOST | audio cleanup")
	assert_true("音频退出 / 测试宿主最终清理", await AudioShutdown.stop_and_wait(self, get_tree()))
	get_tree().node_removed.disconnect(AudioShutdown.track_removed_player)

	print("=== 测试汇总：通过 %d，失败 %d ===" % [passed_count, failed_count])
	get_tree().quit(1 if invalid_selection or failed_count > 0 else 0)


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
