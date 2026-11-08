extends Node
class_name DialogueManagerAdapter


signal dialogue_line_received(character: String, text: String, has_choices: bool)
signal choices_received(choices: Array)
signal dialogue_finished
signal status_hint_requested(text: String)
signal floor_unlock_requested(floor_id: String)
signal door_greeting_done_requested
signal scoped_mutation_requested(scope: RefCounted, kind: StringName, value: String)
signal line_presented_candidate(character: String, text: String, has_choices: bool, from_choice: bool)
signal parse_started(from_choice: bool)

const CallScope := preload("res://scripts/dialogue/dialogue_call_scope.gd")
var _manager: DemoFlowManager
var parse_generation: int = 0
var _utterance_sequence: int = 0
var _presented: Dictionary = {}
var _exchange_prefix: Array[Dictionary] = []
var _latest_excerpt: Dictionary = {}
var _resource_version: String = ""


func bind_flow_manager(manager: DemoFlowManager) -> void:
	reset_dialogue()
	_manager = manager


func discard_current_excerpt() -> void:
	parse_generation += 1
	_presented.clear()
	_exchange_prefix.clear()
	_latest_excerpt.clear()


func get_current_excerpt() -> Dictionary:
	return _latest_excerpt.duplicate(true)


func forward_scoped_mutation(scope: RefCounted, kind: StringName, value: String) -> void:
	if not scope.is_current(self, _manager):
		return
	match kind:
		&"open_reply": reply_when_open_door(value)
		&"close_reply": reply_when_close_door(value)
		_:
			scoped_mutation_requested.emit(scope, kind, value)
			if not scope.is_current(self, _manager):
				return
			match kind:
				&"status_hint": status_hint(value)
				&"unlock_floor": unlock_floor(value)
				&"door_greeting": mark_door_greeting_done()


var dialogue_resource: DialogueResource
var current_line: DialogueLine
var pending_open_door_reply: String = ""
var pending_close_door_reply: String = ""


func reset_dialogue() -> void:
	# 切换派单时清掉资源和门控缓存，避免下一名乘客沿用上一段对话。
	discard_current_excerpt()
	_utterance_sequence = 0
	dialogue_resource = null
	current_line = null
	pending_open_door_reply = ""
	pending_close_door_reply = ""


func start_dialogue(resource_path: String, title: String = "start") -> void:
	# 同一个 DialogueResource 会在后续 next_id 中持续复用，避免对话状态被重新创建。
	discard_current_excerpt()
	dialogue_resource = load(resource_path) as DialogueResource
	current_line = null

	if dialogue_resource == null:
		push_warning("DialogueManagerAdapter: Cannot load dialogue resource: %s" % resource_path)
		dialogue_finished.emit()
		return

	_resource_version = JSON.stringify(dialogue_resource.lines).sha256_text()
	await _load_line(title)


func choose_response(index: int) -> void:
	if current_line == null:
		return
	if index < 0 or index >= current_line.responses.size():
		push_warning("DialogueManagerAdapter: Response index is out of range.")
		return

	var response: DialogueResponse = current_line.responses[index] as DialogueResponse
	if response == null:
		return
	if not response.is_allowed:
		return

	var prefix: Array[Dictionary] = []
	if not _presented.is_empty():
		prefix.append(_presented.duplicate(true))
		prefix.append(_utterance("操作员", response.text, response.id, "operator"))
	await _load_line(response.next_id, prefix, true)


func show_title(title: String) -> void:
	# 外部系统事件（如目标楼层提交）可以跳到同一份 dialogue 的指定标题。
	if dialogue_resource == null:
		return
	if not dialogue_resource.titles.has(title):
		push_warning("DialogueManagerAdapter: Missing dialogue title: %s" % title)
		return
	await _load_line(title)


func show_destination_feedback(floor_id: String) -> void:
	# 楼层反馈统一约定为 destination_楼层号，例如 destination_001。
	await show_title("destination_%s" % floor_id.strip_edges())


func _load_line(line_id: String, prefix: Array[Dictionary] = [], from_choice: bool = false) -> void:
	discard_current_excerpt()
	current_line = null
	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null or dialogue_resource == null or not is_instance_valid(_manager):
		dialogue_finished.emit()
		return
	var scope := CallScope.new(self, _manager, _manager.get_document_session_id(),
		parse_generation, dialogue_resource)
	parse_started.emit(from_choice)
	if not scope.is_current(self, _manager):
		return
	# DM 在返回对白行前也会调用 mutation；每次解析只暴露受控的调用入口。
	var next_line: DialogueLine = await dm.get_next_dialogue_line(dialogue_resource, line_id, [scope])
	if not scope.is_current(self, _manager):
		return
	current_line = next_line
	if current_line == null:
		dialogue_finished.emit()
		return
	_exchange_prefix = prefix
	_emit_current_line(scope, from_choice)


func _utterance(speaker: String, text: String, line_id: String, role: String) -> Dictionary:
	_utterance_sequence += 1
	return {"speaker": speaker, "text": text, "line_id": line_id, "role": role,
		"sequence": _utterance_sequence, "occurred_at": Time.get_unix_time_from_system()}


func confirm_presented_line(speaker: String, text: String, has_choices: bool, from_choice: bool) -> void:
	# 只有 Console 已显示本行后才登记；摘录按钮不读取未选择的分支。
	if current_line == null or current_line.text != text or not is_instance_valid(_manager):
		return
	if text.strip_edges().is_empty() or current_line.id.is_empty():
		return
	_presented = _utterance(speaker, text, current_line.id, "passenger")
	if (from_choice and _exchange_prefix.size() != 2) or (not from_choice and has_choices):
		return
	var rows: Array[Dictionary] = _exchange_prefix.duplicate(true)
	rows.append(_presented.duplicate(true))
	var dispatch := _manager.get_active_dispatch()
	if dispatch == null:
		return
	_latest_excerpt = {"session": _manager.get_document_session_id(), "generation": parse_generation,
		"passenger_id": dispatch.passenger_id, "resource_path": dialogue_resource.resource_path,
		"source_version": _resource_version, "rows": rows}


func _emit_current_line(scope: RefCounted, from_choice: bool) -> void:
	var choices: Array[Dictionary] = []
	for response_data in current_line.responses:
		var response: DialogueResponse = response_data as DialogueResponse
		if response == null:
			continue
		choices.append({
			"text": response.text,
			"is_allowed": response.is_allowed,
		})

	var line := current_line
	line_presented_candidate.emit(line.character, line.text, not choices.is_empty(), from_choice)
	if not scope.is_current(self, _manager):
		return
	dialogue_line_received.emit(line.character, line.text, not choices.is_empty())
	if scope.is_current(self, _manager):
		choices_received.emit(choices)


func status_hint(text: String) -> void:
	# Dialogue Manager 的 do status_hint(...) 会落到这里，再交给主操作台更新提示。
	status_hint_requested.emit(text)


func unlock_floor(floor_id: String) -> void:
	# 这里只发信号，不直接操作右侧 UI，保持 adapter 只负责对话桥接。
	floor_unlock_requested.emit(floor_id)


func mark_door_greeting_done() -> void:
	# DM 只确认门外通话完成，真正开门和乘客进舱仍交给门控按钮。
	door_greeting_done_requested.emit()


func reply_when_open_door(text: String) -> void:
	# 对话只登记“开门后回应”，真正显示由主操作台的开门按钮触发。
	pending_open_door_reply = text


func reply_when_close_door(text: String) -> void:
	# 预留给关门请求：乘客要求关门后，玩家按关门才更新回应。
	pending_close_door_reply = text


func consume_open_door_reply() -> String:
	var reply: String = pending_open_door_reply
	pending_open_door_reply = ""
	return reply


func consume_close_door_reply() -> String:
	var reply: String = pending_close_door_reply
	pending_close_door_reply = ""
	return reply
