extends Node
class_name DialogueManagerAdapter


signal dialogue_line_received(character: String, text: String, has_choices: bool)
signal choices_received(choices: Array)
signal dialogue_finished
signal status_hint_requested(text: String)
signal floor_unlock_requested(floor_id: String)
signal transcript_note_requested(text: String)


var dialogue_resource: DialogueResource
var current_line: DialogueLine
var current_resource_path: String = ""


func start_dialogue(resource_path: String, title: String = "start") -> void:
	# 同一个 DialogueResource 会在后续 next_id 中持续复用，避免对话状态被重新创建。
	current_resource_path = resource_path
	dialogue_resource = load(resource_path) as DialogueResource
	current_line = null

	if dialogue_resource == null:
		push_warning("DialogueManagerAdapter: Cannot load dialogue resource: %s" % resource_path)
		dialogue_finished.emit()
		return

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

	await _load_line(response.next_id)


func continue_dialogue() -> void:
	if current_line == null:
		dialogue_finished.emit()
		return
	if current_line.next_id.is_empty():
		dialogue_finished.emit()
		return

	# 没有选项但存在 next_id 时，由 UI 明确调用继续，避免自动跳过乘客回复。
	await _load_line(current_line.next_id)


func get_response_text(index: int) -> String:
	if current_line == null or index < 0 or index >= current_line.responses.size():
		return ""
	var response: DialogueResponse = current_line.responses[index] as DialogueResponse
	if response == null:
		return ""
	return response.text


func _load_line(line_id: String) -> void:
	var dialogue_manager := get_node_or_null("/root/DialogueManager")
	if dialogue_manager == null:
		push_warning("DialogueManagerAdapter: /root/DialogueManager is missing.")
		dialogue_finished.emit()
		return
	if dialogue_resource == null:
		dialogue_finished.emit()
		return

	var next_line = await dialogue_manager.call(
		"get_next_dialogue_line",
		dialogue_resource,
		line_id,
		[self]
	)
	current_line = next_line as DialogueLine

	if current_line == null:
		dialogue_finished.emit()
		return

	_emit_current_line()


func _emit_current_line() -> void:
	var choices: Array[Dictionary] = []
	for response_data in current_line.responses:
		var response: DialogueResponse = response_data as DialogueResponse
		if response == null:
			continue
		choices.append({
			"text": response.text,
			"is_allowed": response.is_allowed,
		})

	dialogue_line_received.emit(
		current_line.character,
		current_line.text,
		not choices.is_empty()
	)
	choices_received.emit(choices)


func status_hint(text: String) -> void:
	# Dialogue Manager 的 do status_hint(...) 会落到这里，再交给主操作台更新提示。
	status_hint_requested.emit(text)


func unlock_floor(floor_id: String) -> void:
	# 这里只发信号，不直接操作右侧 UI，保持 adapter 只负责对话桥接。
	floor_unlock_requested.emit(floor_id)


func add_transcript_note(text: String) -> void:
	# mutation 产生的是转写备注，不写入 SYSTEM LOG。
	transcript_note_requested.emit(text)
