extends Node
class_name DialogueManagerAdapter

signal scoped_mutation_requested(scope: RefCounted, kind: StringName, value: String)

const CallScope := preload("res://scripts/dialogue/dialogue_call_scope.gd")
const MAX_LINES := 8
const MAX_TEXT_LENGTH := 2048
const MAX_STEPS := 32

var _manager: DemoFlowManager
var parse_generation: int = 0
var dialogue_resource: DialogueResource
var _busy := false


func bind_flow_manager(manager: DemoFlowManager) -> void:
	reset_dialogue()
	_manager = manager


func reset_dialogue() -> void:
	parse_generation += 1
	dialogue_resource = null
	_busy = false


func forward_scoped_mutation(scope: RefCounted, kind: StringName, value: String) -> void:
	if scope.is_current(self, _manager):
		scoped_mutation_requested.emit(scope, kind, value)


## 只接受有限的顺序台词。预检整个标题，避免在碰到废弃选项前就执行副作用。
static func is_event_title(resource: DialogueResource, title: String, review := false, action := "") -> bool:
	if resource == null or not resource.titles.has(title):
		return false
	var id := String(resource.titles[title])
	var count := 0
	var supplement_seen := false
	var length := 0
	for step in range(MAX_STEPS):
		if id in ["", "end", "end!"]:
			return count > 0 and (action.is_empty() or supplement_seen)
		var line: Dictionary = resource.lines.get(id, {})
		if not line.get("responses", []).is_empty() or not line.get("siblings", []).is_empty() \
				or not line.get("next_id_expression", []).is_empty():
			return false
		match line.get("type"):
			"dialogue":
				var speaker := String(line.get("character", "")).to_lower()
				var text := String(line.get("text", ""))
				if review and (speaker not in ["passenger", "乘客"] or text.strip_edges().is_empty()):
					return false
				if not line.get("concurrent_lines", []).is_empty() \
						or not line.get("text_replacements", []).is_empty() \
						or not line.get("character_replacements", []).is_empty() \
						or "[" in text \
						or speaker in ["操作员", "operator"]:
					return false
				count += 1
				length += text.length()
				if count > MAX_LINES or length > MAX_TEXT_LENGTH:
					return false
			"mutation":
				var tokens: Array = line.get("mutation", {}).get("expression", [])
				if not line.mutation.get("is_blocking", false) or tokens.size() != 1 \
						or tokens[0].get("type") != "function":
					return false
				# 编译器把右括号留在最后一个参数的 token 列表中。
				var args: Array = tokens[0].get("value", []).duplicate(true)
				if not args.is_empty() and not args.back().is_empty() \
						and args.back().back().get("type") == "parens_close":
					args.back().pop_back()
					if args.back().is_empty():
						args.pop_back()
				var method: String = tokens[0].get("function", "")
				if review and method not in ["wait", "submit_review_supplement"]:
					return false
				match method:
					"submit_review_supplement":
						if not review or action.is_empty() or args.size() != 1 or args[0].size() != 1 \
								or args[0][0].get("type") != "string" or args[0][0].get("value") != action:
							return false
						supplement_seen = true
					"mark_door_greeting_done":
						if not args.is_empty():
							return false
					"status_hint", "unlock_floor":
						if args.size() != 1 or args[0].size() != 1 or args[0][0].get("type") != "string":
							return false
					"wait":
						if args.size() != 1 or args[0].size() != 1 or args[0][0].get("type") != "number":
							return false
					_:
						return false
			"title", "goto":
				if line.get("is_snippet", false):
					return false
			_:
				return false
		id = String(line.get("next_id", ""))
	return false


## 本阶段只解析并保存事件结果。没有屏幕回执，原文不能成为摘录候选。
func process_pending_events() -> void:
	if _busy or not is_instance_valid(_manager):
		return
	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null:
		return
	_busy = true
	parse_generation += 1
	var generation := parse_generation
	while generation == parse_generation:
		var event := _manager.take_pending_passenger_event()
		if event.is_empty():
			break
		dialogue_resource = load(event.resource_path) as DialogueResource
		var rows: Array[Dictionary] = []
		var review := event.has("question_id")
		var scope: RefCounted
		if is_event_title(dialogue_resource, event.title, review, event.get("supplement_action", "")):
			scope = CallScope.new(self, _manager, event.session, generation, dialogue_resource, event)
			var id: String = event.title
			for step in range(MAX_LINES + 1):
				var line: DialogueLine = await dm.get_next_dialogue_line(dialogue_resource, id, [scope])
				if not scope.is_current(self, _manager):
					return
				if line == null:
					break
				rows.append({"line_id": line.id, "speaker": line.character, "text": line.text})
				id = line.next_id
				if id in ["", "end", "end!"]:
					break
		if scope != null and scope.supplement_failed:
			rows.clear()
		var source_version := JSON.stringify(dialogue_resource.lines).sha256_text() if dialogue_resource != null else ""
		_manager.finish_passenger_event(event, source_version, rows)
	if generation == parse_generation:
		_busy = false


func can_accept_review() -> bool:
	return not _busy and is_instance_valid(_manager) and get_node_or_null("/root/DialogueManager") != null
