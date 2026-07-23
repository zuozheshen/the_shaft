class_name UIHistoryState
extends RefCounted


const MAX_FRONT_HISTORY_LINES: int = 20
const EMPTY_STATUS_HINT: String = "暂无系统消息。"
const SHIFT_FINISHED_HINT: String = "本轮派单已全部完成。"

var _front_dialogue_history: Array[String] = []
var _system_message_history: Array[String] = []
var _current_building_status_hint: String = EMPTY_STATUS_HINT


func reset_for_new_dispatch(initial_hint: String) -> void:
	_front_dialogue_history.clear()
	_system_message_history.clear()
	_current_building_status_hint = initial_hint \
			if not initial_hint.is_empty() else EMPTY_STATUS_HINT
	if not initial_hint.is_empty():
		_append_system_message(initial_hint)


func clear_active_dispatch() -> void:
	_front_dialogue_history.clear()
	_system_message_history.clear()
	_current_building_status_hint = EMPTY_STATUS_HINT


func finish_shift() -> void:
	_front_dialogue_history.clear()
	_system_message_history = [SHIFT_FINISHED_HINT]
	_current_building_status_hint = SHIFT_FINISHED_HINT


func add_operator_transcript(operator_text: String) -> bool:
	if operator_text.is_empty():
		return false
	_front_dialogue_history.append("操作员：%s" % operator_text)
	_trim_front_dialogue_history()
	return true


func add_passenger_transcript(passenger_text: String) -> bool:
	if passenger_text.is_empty():
		return false
	var formatted_text: String = passenger_text
	if not formatted_text.begins_with("乘客："):
		formatted_text = "乘客：%s" % formatted_text
	_front_dialogue_history.append(formatted_text)
	_trim_front_dialogue_history()
	return true


func get_front_dialogue_history() -> Array[String]:
	return _front_dialogue_history.duplicate()


func get_current_building_status_hint() -> String:
	return _current_building_status_hint


func set_building_status_hint(
		hint: String,
		include_in_history: bool = false,
		history_text: String = ""
) -> bool:
	if hint.is_empty():
		return false
	_current_building_status_hint = hint
	if include_in_history:
		var message_text: String = history_text if not history_text.is_empty() else hint
		_append_system_message(message_text)
	return true


func add_system_log_message(message_text: String) -> bool:
	if message_text.is_empty():
		return false
	_append_system_message(message_text)
	return true


func get_system_message_history() -> Array[String]:
	return _system_message_history.duplicate()


func _trim_front_dialogue_history() -> void:
	while _front_dialogue_history.size() > MAX_FRONT_HISTORY_LINES:
		_front_dialogue_history.pop_front()


func _append_system_message(message_text: String) -> void:
	_system_message_history.append(message_text)
	while _system_message_history.size() > MAX_FRONT_HISTORY_LINES:
		_system_message_history.pop_front()
