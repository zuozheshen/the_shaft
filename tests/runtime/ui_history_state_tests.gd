extends RefCounted


const UIHistoryStateScript := preload(
	"res://scripts/runtime/ui/ui_history_state.gd"
)


func run(test_runner: Variant) -> void:
	var history = UIHistoryStateScript.new()
	history.add_operator_transcript("请说明目的地。")
	history.add_passenger_transcript("我去 900 层。")
	history.add_system_log_message("系统记录已读取。")

	test_runner.assert_equal(
		"UIHistoryState / 操作员和乘客进入对话历史",
		2,
		history.get_front_dialogue_history().size()
	)
	test_runner.assert_equal(
		"UIHistoryState / 系统日志与对话分离",
		1,
		history.get_system_message_history().size()
	)
	history.set_building_status_hint("仅更新短提示。")
	test_runner.assert_equal(
		"UIHistoryState / 当前短提示可查询",
		"仅更新短提示。",
		history.get_current_building_status_hint()
	)
	test_runner.assert_equal(
		"UIHistoryState / 短提示默认不进入日志",
		1,
		history.get_system_message_history().size()
	)
	history.set_building_status_hint("短提示和日志。", true, "明确写入日志。")
	test_runner.assert_equal(
		"UIHistoryState / 调用方可明确写入提示历史",
		2,
		history.get_system_message_history().size()
	)

	for index in 25:
		history.add_operator_transcript("对话 %d" % index)
		history.add_system_log_message("日志 %d" % index)
	test_runner.assert_equal(
		"UIHistoryState / 对话历史按上限裁剪",
		UIHistoryStateScript.MAX_FRONT_HISTORY_LINES,
		history.get_front_dialogue_history().size()
	)
	test_runner.assert_equal(
		"UIHistoryState / 系统日志按上限裁剪",
		UIHistoryStateScript.MAX_FRONT_HISTORY_LINES,
		history.get_system_message_history().size()
	)

	var dialogue_copy: Array[String] = history.get_front_dialogue_history()
	dialogue_copy.clear()
	test_runner.assert_not_equal(
		"UIHistoryState / 对话查询返回副本",
		0,
		history.get_front_dialogue_history().size()
	)
	var system_copy: Array[String] = history.get_system_message_history()
	system_copy.clear()
	test_runner.assert_not_equal(
		"UIHistoryState / 日志查询返回副本",
		0,
		history.get_system_message_history().size()
	)

	history.reset_for_new_dispatch("新派单已建立。")
	test_runner.assert_equal(
		"UIHistoryState / 新派单清空旧对话",
		0,
		history.get_front_dialogue_history().size()
	)
	test_runner.assert_equal(
		"UIHistoryState / 新派单建立独立系统历史",
		["新派单已建立。"],
		history.get_system_message_history()
	)
	history.finish_shift()
	test_runner.assert_equal(
		"UIHistoryState / 值班结束提示",
		UIHistoryStateScript.SHIFT_FINISHED_HINT,
		history.get_current_building_status_hint()
	)
