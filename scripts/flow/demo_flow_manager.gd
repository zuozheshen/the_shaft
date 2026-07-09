extends Node
class_name DemoFlowManager


# 状态变化后通知界面等监听者，避免其他节点反复查询流程状态。
signal case_updated


const MAX_FRONT_HISTORY_LINES: int = 20
const SYSTEM_RECOMMENDATION_EXCLUSIONS: Array[String] = ["004", "387", "392", "547"]


# 当前案例暂时以内置 GDScript 数据保存，后续会迁移到 data/cases/case_001.json。
# UI 应通过下方 getter 读取，未来替换 CaseManager / PassengerCase / JSON Loader 时无需大改。
# 所有楼层编号都保持为字符串，尤其不能把 "004" 转换为整数。
var current_case: Dictionary = {
	"case_id": "CASE_001",
	"passenger_name": "M. ROWAN",
	"passenger_display_name": "罗文",
	"dispatch_from": "612",
	"dispatch_to": "900",
	"case_phase": "WAITING_FOR_PICKUP",
	"pickup_floor": "612",
	"passenger_onboard": false,
	"door_greeting_done": false,
	"pickup_completed": false,
	"cabin_door_closed_after_boarding": false,
	"case_summary_reached": false,
	"submitted_destination": "",
	"destination_feedback_shown": false,
	"passenger_record": {
		"name": "M. ROWAN",
		"display_name": "罗文",
		"registration_status": "TEMPORARY SUPPORT / 待复核",
		"risk_tag": "LOW",
		"dispatch": "612 → 900",
		"average_stay": "12 MIN",
		"recent_routes": [
			"612 → 900 / APPROVED / 未完成复核",
			"612 → 900 / APPROVED / 未完成复核",
			"612 → 900 / APPROVED / 未完成复核",
		],
		"note": "该乘客近期路线重复率异常。\n多次抵达 900 外等待区后未完成柜台复核。\n服务区相关记录存在纸质缺口。",
	},
}

# 三份状态是 FRONT 到 LEFT 的临时桥接，后续会由正式 PassengerCase 替换。
# 对话历史只用于 TRANSCRIPT，操作历史只用于 SYSTEM LOG，提示只用于 STATUS。
var front_dialogue_history: Array[String] = []
var front_operation_history: Array[String] = []
var current_building_status_hint: String = "暂无前台通话。"
var has_unread_status_hint: bool = false


func _ready() -> void:
	_configure_issue_12_case()


func _configure_issue_12_case() -> void:
	# 第一位乘客暂用内置案例数据；后续由正式 CaseManager / JSON 替换。
	current_case["pickup"] = {
		"floor": "612",
		"arrival_feedback": "已前往接乘楼层：612。请回到主操作台，使用门外摄像头确认乘客。",
		"arrival_status_hint": "电梯已被指派至 612 层接乘点。建议使用门外摄像头确认乘客状态。",
		"outside_audio_idle": "门外音频链路已开启。",
		"greeting": {
			"operator": "你好。",
			"passenger": "乘客：……这是自动广播吗？如果有真人在听，麻烦开一下门。我在 612 等了很久。",
			"status_hint": "门外乘客已回应，并请求进入电梯。建议开启舱门完成接乘。",
			"system_hint": "门外乘客已回应。请开启舱门完成接乘。",
		},
		"after_open_line": "乘客：谢谢。门关上以后再说吧。",
		"after_open_hint": "乘客已进入舱内。请关闭舱门后继续询问。",
		"after_close_line": "乘客：好了。现在能听见你了。",
		"after_close_hint": "舱门已关闭。请切换至主摄像头并开启麦克风继续询问。",
		"after_close_status_hint": "乘客已进入舱内，舱门已关闭。可以开始正式询问目标。",
	}
	current_case["camera_feeds"] = {
		"WAITING_FOR_PICKUP": [
			"画面占位：乘客舱内为空。等待接乘任务。",
			"画面占位：乘客舱地面区域。暂无乘客进入痕迹。",
			"画面占位：当前门外切片暂无待接乘客。请先前往接乘楼层。",
		],
		"ARRIVED_AT_PICKUP": [
			"画面占位：乘客舱内为空。等待乘客进入。",
			"画面占位：乘客舱地面区域。暂无乘客进入痕迹。",
			"画面占位：612 层门外三到五米切片。自动售卖机旁有一名等待乘客，手里提着旧饭盒。",
		],
		"DOOR_GREETING_DONE": [
			"画面占位：乘客舱内为空。等待乘客进入。",
			"画面占位：乘客舱地面区域。暂无乘客进入痕迹。",
			"画面占位：612 层门外三到五米切片。等待乘客站在门外，正在等舱门开启。",
		],
		"BOARDING_WAIT_DOOR_CLOSE": [
			"画面占位：乘客站在舱内。她抱着一个旧饭盒，胸牌翻在外套里面。",
			"画面占位：乘客舱地面区域。能看到一小段水痕和旧饭盒底部蹭出的拖痕。",
			"画面占位：612 层门外切片。自动售卖机灯牌闪烁，等待区已空。",
		],
		"PASSENGER_ONBOARD": [
			"画面占位：乘客站在舱内。她抱着一个旧饭盒，胸牌翻在外套里面。",
			"画面占位：乘客舱地面区域。能看到一小段水痕和旧饭盒底部蹭出的拖痕。",
			"画面占位：612 层门外切片。自动售卖机灯牌闪烁，等待区已空。",
		],
		"DESTINATION_CONFIRMED": [
			"画面占位：乘客站在舱内。她抱着一个旧饭盒，正在等待电梯执行目标。",
			"画面占位：乘客舱地面区域。水痕停在乘客脚边，没有继续扩散。",
			"画面占位：门外等待区已空。",
		],
	}
	current_case["front_phase_texts"] = {
		"WAITING_FOR_PICKUP": {"state": "当前状态：等待接乘", "task": "当前任务：前往 {pickup_floor} 层接乘"},
		"ARRIVED_AT_PICKUP": {"state": "当前状态：已抵达接乘点", "task": "当前任务：使用门外摄像头确认 {pickup_floor} 层等待乘客"},
		"DOOR_GREETING_DONE": {"state": "当前状态：门外乘客已回应", "task": "当前任务：开启舱门完成接乘"},
		"BOARDING_WAIT_DOOR_CLOSE": {"state": "当前状态：乘客已进入，等待关门", "task": "当前任务：关闭舱门后继续询问"},
		"PASSENGER_ONBOARD": {"state": "当前状态：舱内询问中", "task": "当前目标：{submitted_destination_or_none}"},
		"DESTINATION_CONFIRMED": {"state": "当前状态：目标已提交", "task": "当前目标：{submitted_destination_or_none}"},
	}
	current_case["right_phase_texts"] = {
		"PICKUP": {"task": "当前任务：前往 {pickup_floor} 层接乘"},
		"ONBOARD": {"task": "当前目标：{submitted_destination_or_none}"},
	}
	current_case["recommended_destination_rules"] = {
		"pickup_phases": ["WAITING_FOR_PICKUP", "ARRIVED_AT_PICKUP", "DOOR_GREETING_DONE", "BOARDING_WAIT_DOOR_CLOSE"],
		"pickup_recommendations": ["612"],
		"default_onboard_recommendations": ["900"],
		"summary_recommendations": ["900", "742"],
	}
	current_case["dialogue_tree"] = _build_dialogue_tree()
	current_case["dialogue_fallbacks"] = {
		"application_reason": "book_prompt_soft", "standard_target": "about_900",
		"identity_record": "old_badge", "repeated_route": "about_900",
		"waiting_time": "about_612", "operator_role": "trust_start",
		"target_clues": "case_summary", "unrecorded_help": "service_area",
	}
	current_case["floor_database"] = {
		"900": {"description": "居民事务柜台层。", "relation": "91%", "access_eval": "可前往", "stability": "基本稳定", "message": "该楼层是派单记录目标。适合标准登记与身份复核。"},
		"742": {"description": "中继等待层。", "relation": "76%", "access_eval": "可前往", "stability": "稳定", "message": "该楼层适合临时等待与路线复核，但不能直接解决乘客登记问题。"},
		"612": {"description": "接乘起始相关层。", "relation": "84%", "access_eval": "可前往", "stability": "稳定", "message": "该楼层为本单接乘来源。返回该层可维持流程安全。"},
		"004": {"description": "低层服务区。", "relation": "48%", "access_eval": "可前往", "stability": "中等波动", "message": "该楼层不在系统推荐中，但与乘客描述的服务区、洗洁精味和旧暖柜线索相符。"},
		"387": {"description": "旧记录存放层。", "relation": "61%", "access_eval": "可前往", "stability": "轻微波动", "message": "该楼层与乘客提到的旧工牌、旧班表和纸质记录线索相符。"},
		"392": {"description": "普通通行层。", "relation": "0%", "access_eval": "可前往", "stability": "稳定", "message": "该楼层与当前派单无关联，但建筑允许前往。"},
		"547": {"description": "普通办公层。", "relation": "0%", "access_eval": "可前往", "stability": "基本稳定", "message": "该楼层与当前派单无关联，稳定度未见明显变化。"},
	}
	current_case["floor_book_entries"] = _build_floor_book_entries()
	current_case["destination_feedbacks"] = {
		"900": {"passenger": "乘客：好吧。那就是记录上的地方。也许这次我能把话说完。", "status_hint": "目标 900 已确认。该目标与派单记录一致。提示：标准目标稳定，但可能重复乘客此前未完成的复核路径。"},
		"742": {"passenger": "乘客：中间停一下也好。至少不是立刻坐到柜台前。", "status_hint": "目标 742 已确认。该楼层可作为中继等待点。提示：该选择较稳定，但不会直接解决乘客旧牌与旧记录问题。"},
		"612": {"passenger": "乘客：送回去？那我可能又要坐回那张长椅上了。", "status_hint": "目标 612 已确认。电梯将返回接乘相关层。提示：返回起点可维持流程安全，但可能无法推进乘客问题。"},
		"004": {"passenger": "乘客：你查到了？前面的零还在吗？那地方少一个零就不是它了。", "status_hint": "目标 004 已确认。该楼层不在系统推荐中，但与乘客服务区线索相符。提示：该选择可能满足乘客取回旧工牌的特殊需求。"},
		"387": {"passenger": "乘客：旧记录层……如果班表还在，我就还能证明我不是临时出现的。", "status_hint": "目标 387 已确认。旧记录存放层已被选为目标。提示：该选择可能提供纸质记录证据，但会偏离标准派单。"},
		"392": {"passenger": "乘客：我不认识那层。你确定不是输错了吗？", "status_hint": "目标 392 已确认。该目标与当前乘客线索无直接关联。提示：可前往，但缺少案例依据。"},
		"547": {"passenger": "乘客：办公层？我这身味道上去，可能会被请去走货梯。", "status_hint": "目标 547 已确认。该目标与当前乘客线索无直接关联。提示：可前往，但与当前派单和乘客自述关联较弱。"},
	}
	current_building_status_hint = "当前系统提示：\n%s 层检测到待接乘客。\n建议前往 %s 层完成接乘确认。\n\n当前任务：\n前往接乘楼层。" % [get_pickup_floor(), get_pickup_floor()]

func add_front_dialogue(
		operator_text: String,
		passenger_text: String,
		status_hint: String = ""
) -> void:
	# 普通问答只写入 TRANSCRIPT，关键选项才更新 LEFT STATUS。
	front_dialogue_history.append("操作员：%s" % operator_text)
	var formatted_passenger_text: String = passenger_text
	if not formatted_passenger_text.begins_with("乘客："):
		formatted_passenger_text = "乘客：%s" % formatted_passenger_text
	front_dialogue_history.append(formatted_passenger_text)
	if not status_hint.is_empty():
		set_building_status_hint(status_hint, true)

	# 每次移除一整组问答，避免 20 行上限把操作员与乘客台词拆开。
	while front_dialogue_history.size() > MAX_FRONT_HISTORY_LINES:
		front_dialogue_history.pop_front()
		front_dialogue_history.pop_front()


func add_front_operation(operation_text: String) -> void:
	# 当前是临时操作历史缓存：虽从 FRONT 事件开始，现在也接收 RIGHT 目标楼层操作。
	# 这些记录只供 LEFT SYSTEM LOG 使用，后续会由 PassengerCase 或统一事件系统替换。
	front_operation_history.append(operation_text)
	if front_operation_history.size() > MAX_FRONT_HISTORY_LINES:
		front_operation_history.pop_front()


func get_front_dialogue_history() -> Array[String]:
	# 返回副本，避免 LEFT 界面意外改写共享对话缓存。
	var history_copy: Array[String] = []
	history_copy.assign(front_dialogue_history)
	return history_copy


func get_front_operation_history() -> Array[String]:
	# 返回副本，避免 LEFT 界面意外改写共享操作缓存。
	var history_copy: Array[String] = []
	history_copy.assign(front_operation_history)
	return history_copy


func get_current_building_status_hint() -> String:
	return current_building_status_hint


func set_building_status_hint(hint: String, mark_unread: bool = true) -> void:
	current_building_status_hint = hint
	has_unread_status_hint = mark_unread
	case_updated.emit()


func has_unread_building_status_hint() -> bool:
	return has_unread_status_hint


func clear_unread_building_status_hint() -> void:
	has_unread_status_hint = false
	case_updated.emit()


# 以下方法是当前案例的临时访问接口，正式数据层接入后可保持 UI 调用方式不变。
func get_current_case() -> Dictionary:
	return current_case.duplicate(true)


func get_case_id() -> String:
	return str(current_case.get("case_id", ""))


func get_passenger_name() -> String:
	return str(current_case.get("passenger_name", ""))


func get_passenger_display_name() -> String:
	return str(current_case.get("passenger_display_name", "罗文"))


func get_passenger_label() -> String:
	var passenger_name: String = get_passenger_name()
	var display_name: String = get_passenger_display_name()
	return passenger_name if display_name.is_empty() else "%s / %s" % [passenger_name, display_name]


func get_pickup_data() -> Dictionary:
	return current_case.get("pickup", {}).duplicate(true)


func get_pickup_floor() -> String:
	var pickup: Dictionary = current_case.get("pickup", {})
	return str(pickup.get("floor", current_case.get("pickup_floor", "")))


func get_pickup_greeting() -> Dictionary:
	var pickup: Dictionary = current_case.get("pickup", {})
	return pickup.get("greeting", {}).duplicate(true)


func get_pickup_arrival_feedback() -> String:
	return str(current_case.get("pickup", {}).get("arrival_feedback", ""))


func get_pickup_arrival_status_hint() -> String:
	return str(current_case.get("pickup", {}).get("arrival_status_hint", ""))


func get_after_open_line() -> String:
	return str(current_case.get("pickup", {}).get("after_open_line", ""))


func get_after_open_hint() -> String:
	return str(current_case.get("pickup", {}).get("after_open_hint", ""))


func get_after_close_line() -> String:
	return str(current_case.get("pickup", {}).get("after_close_line", ""))


func get_after_close_hint() -> String:
	return str(current_case.get("pickup", {}).get("after_close_hint", ""))


func get_after_close_status_hint() -> String:
	return str(current_case.get("pickup", {}).get("after_close_status_hint", ""))


func get_camera_feed_for_phase(phase: String, camera_index: int) -> String:
	# 缺少阶段时回退到接乘初始画面；无效摄像头编号只返回空文本，避免数组越界。
	var camera_feeds: Dictionary = current_case.get("camera_feeds", {})
	var phase_feeds: Array = camera_feeds.get(phase, camera_feeds.get("WAITING_FOR_PICKUP", []))
	if camera_index < 0 or camera_index >= phase_feeds.size():
		return ""
	return str(phase_feeds[camera_index])


func get_front_phase_text(phase: String) -> Dictionary:
	var phase_texts: Dictionary = current_case.get("front_phase_texts", {})
	var text_data: Dictionary = phase_texts.get(phase, phase_texts.get("WAITING_FOR_PICKUP", {})).duplicate(true)
	text_data["state"] = _format_case_text(str(text_data.get("state", "")))
	text_data["task"] = _format_case_text(str(text_data.get("task", "")))
	return text_data


func get_right_phase_task_text() -> String:
	var right_phase_texts: Dictionary = current_case.get("right_phase_texts", {})
	var text_key: String = "ONBOARD" if get_case_phase() in ["PASSENGER_ONBOARD", "DESTINATION_CONFIRMED"] else "PICKUP"
	var text_data: Dictionary = right_phase_texts.get(text_key, {})
	return _format_case_text(str(text_data.get("task", "")))


func _format_case_text(template: String) -> String:
	# 集中替换案例占位符，UI 不需要知道接乘楼层或当前目标的具体值。
	var submitted_destination: String = get_submitted_destination()
	# 接乘楼层提交只代表电梯抵达起点，乘客登舱后尚未选择正式目标。
	if get_case_phase() == "PASSENGER_ONBOARD" and submitted_destination == get_pickup_floor():
		submitted_destination = ""
	var destination_or_none: String = submitted_destination if not submitted_destination.is_empty() else "暂无"
	var formatted_text: String = template.replace(
		"{submitted_destination_or_none}", destination_or_none
	)
	formatted_text = formatted_text.replace("{submitted_destination}", submitted_destination)
	formatted_text = formatted_text.replace("{pickup_floor}", get_pickup_floor())
	return formatted_text


func get_dispatch_from() -> String:
	return str(current_case.get("dispatch_from", ""))


func get_dispatch_to() -> String:
	return str(current_case.get("dispatch_to", ""))


func get_dispatch_text() -> String:
	return "%s → %s" % [get_dispatch_from(), get_dispatch_to()]


func get_recommended_destinations() -> Array:
	return get_current_recommended_destinations()


func get_initial_passenger_line() -> String:
	# 初始台词也从对话树根节点读取，更换案例时不需要修改访问接口。
	var dialogue_tree: Dictionary = current_case.get("dialogue_tree", {})
	var initial_node: Dictionary = dialogue_tree.get("onboard_start", {})
	return str(initial_node.get("passenger_line", "乘客舱音频链路待机。"))


func get_dialogue_nodes() -> Array:
	return current_case.get("dialogue_nodes", []).duplicate(true)


func get_dialogue_tree() -> Dictionary:
	return current_case.get("dialogue_tree", {}).duplicate(true)


func get_passenger_record() -> Dictionary:
	return current_case.get("passenger_record", {}).duplicate(true)


func get_floor_database() -> Dictionary:
	return current_case.get("floor_database", {}).duplicate(true)


func get_floor_book_entries() -> Array:
	return current_case.get("floor_book_entries", []).duplicate(true)


func get_submitted_destination() -> String:
	return str(current_case.get("submitted_destination", ""))


func set_submitted_destination(destination: String) -> void:
	# 目标仍按字符串保存，避免 004 这样的正式楼层编号丢失前导零。
	current_case["submitted_destination"] = destination.strip_edges()
	current_case["destination_feedback_shown"] = false
	case_updated.emit()


func get_case_phase() -> String:
	return str(current_case.get("case_phase", "WAITING_FOR_PICKUP"))


func set_case_phase(phase: String) -> void:
	current_case["case_phase"] = phase
	case_updated.emit()


func is_passenger_onboard() -> bool:
	return bool(current_case.get("passenger_onboard", false))


func set_passenger_onboard(value: bool) -> void:
	current_case["passenger_onboard"] = value
	case_updated.emit()


func is_door_greeting_done() -> bool:
	return bool(current_case.get("door_greeting_done", false))


func set_door_greeting_done(value: bool) -> void:
	current_case["door_greeting_done"] = value
	case_updated.emit()


func set_pickup_completed(value: bool) -> void:
	current_case["pickup_completed"] = value
	case_updated.emit()


func is_cabin_door_closed_after_boarding() -> bool:
	return bool(current_case.get("cabin_door_closed_after_boarding", false))


func set_cabin_door_closed_after_boarding(value: bool) -> void:
	current_case["cabin_door_closed_after_boarding"] = value
	case_updated.emit()


func get_destination_feedback(destination: String) -> Dictionary:
	var feedbacks: Dictionary = current_case.get("destination_feedbacks", {})
	return feedbacks.get(destination, {}).duplicate(true)


func get_current_recommended_destinations() -> Array:
	var phase: String = get_case_phase()
	var rules: Dictionary = current_case.get("recommended_destination_rules", {})
	var pickup_phases: Array = rules.get("pickup_phases", [])
	var recommendation_key: String = "default_onboard_recommendations"
	if phase in pickup_phases:
		recommendation_key = "pickup_recommendations"
	elif bool(current_case.get("case_summary_reached", false)):
		recommendation_key = "summary_recommendations"
	var configured_candidates: Array = rules.get(recommendation_key, [])
	# 系统推荐与玩家手动发现严格分开，隐藏楼层只能由玩家自行填写。
	var candidates: Array[String] = []
	for destination in configured_candidates:
		var floor_number: String = str(destination)
		if floor_number not in SYSTEM_RECOMMENDATION_EXCLUSIONS:
			candidates.append(floor_number)
	return candidates


func mark_case_summary_reached() -> void:
	# 到达总结节点后，建筑才愿意把稳定的中继等待层 742 加入系统推荐。
	current_case["case_summary_reached"] = true
	case_updated.emit()


func _choice(operator: String, passenger: String, next_node: String, hint: String = "") -> Dictionary:
	var choice := {"operator": operator, "passenger": passenger, "next": next_node}
	if not hint.is_empty():
		choice["status_hint"] = hint
	return choice


func _node(line: String, choices: Array, hint: String = "") -> Dictionary:
	var node := {"passenger_line": line, "choices": choices}
	if not hint.is_empty():
		node["status_hint"] = hint
	return node


func _build_dialogue_tree() -> Dictionary:
	# node_id / next 让每条回答明确指向下一节点，不再依赖固定两层数组。
	return {
		"onboard_start": _node("乘客：你是真人在听，对吧？那我能不能不直接去 900？", [
			_choice("你想去哪？", "乘客：下面一点。不是最下面。那里有洗洁精味，晚上会有人把餐盘推过去。", "below_clues"),
			_choice("系统目前只推荐 900。", "乘客：我知道。900 是柜台。柜台会让我把临时牌交上去，然后等复核。", "about_900", "系统当前推荐目标仅为 900。乘客对标准目标存在迟疑，建议继续询问原因。"),
			_choice("你为什么在 612 等电梯？", "乘客：我换班以后一直在那层等。612 的屏幕会说“即将调度”，但它说得太久了。", "about_612"),
			_choice("我可以先保持门关闭。你慢慢说。", "乘客：谢谢。门关着的时候，我比较像一个乘客，不像一个堵在门口的故障。", "trust_start", "乘客对门控状态有明显安全感反馈。保持舱门关闭有助于继续沟通。"),
		]),
		"below_clues": _node("乘客：我记不清楼层号。只记得那里有人洗桶，地上总是湿的，暖柜门关不上。", [
			_choice("你去那里做什么？", "乘客：想拿回一张旧工牌。以前有人替我放在暖柜后面，说哪天系统不认我了，也许还能用上。", "old_badge"),
			_choice("那听起来像服务区。", "乘客：对，服务区。不是给住户看的地方。大家只是从那里经过，拿东西，换班，倒掉剩饭。", "service_area"),
			_choice("你为什么不直接申请那个楼层？", "乘客：申请要写理由。我总不能写“我想证明我还是我自己”。", "application_reason", "乘客需求无法被标准申请理由完整表达。建议玩家结合纸质楼层索引书自行判断目标楼层。"),
			_choice("你确定不是 900 吗？", "乘客：900 是最后要去的地方。可我不想空着手去。", "about_900"),
		]),
		"about_900": _node("乘客：900 的灯很白。人在柜台前站着，什么都还没说，记录就先排好了。", [
			_choice("900 是系统推荐目标，应该最稳。", "乘客：稳定是好事。我也靠稳定活着。只是有时候，稳定会把没写进去的东西都挤掉。", "standard_target"),
			_choice("你去了 900 会发生什么？", "乘客：他们会收走我的临时牌，给我一张新的。新的上面名字没错，可我以前的班表就对不上了。", "identity_record", "乘客担心标准复核流程改变自身记录状态。900 合规，但可能重复其既往困境。"),
			_choice("你以前去过 900 吗？", "乘客：三次。每次都在柜台外坐到号码跳过，然后再坐电梯回来。", "repeated_route", "乘客历史路线存在重复但未完成的复核行为。建议查看 LEFT 的 RECORD 页。"),
			_choice("你不是不去 900，只是不想现在去？", "乘客：对。我想带着一点能说明自己的东西去。", "old_badge"),
		]),
		"about_612": _node("乘客：612 有长椅、售卖机，还有一个总是卷边的公告板。等久了，人会开始怀疑是不是自己没被算进去。", [
			_choice("你在那里等了多久？", "乘客：两班人换过了。售卖机补了一次货。我的汤也从热的变成温的。", "waiting_time"),
			_choice("你说“汤”？", "乘客：绿豆汤。给夜班的人带的。她以前帮过我。", "soup_context"),
			_choice("公告板上有什么？", "乘客：班表、清洁扣分、失物认领，还有一张被撕掉一半的低层服务区通知。", "service_area"),
			_choice("你觉得自己没被算进去？", "乘客：系统会算路线、算人数、算等待时间。可是它不太会算一个人为什么一直没走。", "trust_start", "乘客表达出对调度系统的低信任。建议继续收集目标线索，而不是立即提交 900。"),
		]),
		"trust_start": _node("乘客：我不是想给你添麻烦。我知道你也只是按按钮。", [
			_choice("按按钮也是决定。", "乘客：那你比广播强。广播只会说“请等待”。", "operator_role"),
			_choice("我需要知道你真正想去哪里。", "乘客：我想先去找旧工牌。找不到的话，再去旧记录层看看。", "target_clues"),
			_choice("我会先查记录。", "乘客：查吧。记录比我会说话，就是有时候说得太整齐。", "repeated_route", "建议查看 LEFT 的 RECORD 页。系统记录可能完整，但不一定足够解释乘客需求。"),
			_choice("你可以继续说。", "乘客：我以前在低层发餐点帮忙。不是正式岗位，就是缺人的时候叫我一下。", "work_history"),
		]),
		"soup_context": _node("乘客：那碗汤不是任务。只是她胃不好，夜班又总忘记吃东西。", [
			_choice("她是谁？", "乘客：清洁队的阿姨。她不喜欢别人叫她工号。她说工号是给柜台听的。", "service_area"),
			_choice("这件事系统里没有记录？", "乘客：不会有。顺手带汤这种事，一登记就变成责任。没人想多一条责任。", "unrecorded_help", "乘客描述的是系统记录之外的生活互助。当前信息可能与非推荐楼层有关。"),
			_choice("你担心汤被当成异常物品？", "乘客：担心。写“旧饭盒”就好，别写“容器”。容器听起来像我藏了东西。", "record_language"),
			_choice("这和旧工牌有关吗？", "乘客：有。她说，如果哪天新牌不认我，就去暖柜后面找旧的。", "old_badge"),
		]),
		"old_badge": _node("乘客：那张旧工牌不是为了通行，是为了让柜台相信我以前就在这里。", [
			_choice("新工牌有什么问题？", "乘客：新工牌把我归到临时支援。可我在那边做了很久，久到知道哪台暖柜会夹手。", "work_history"),
			_choice("旧工牌在哪里？", "乘客：低层服务区，一个坏暖柜后面。那地方纸质索引里应该有写。", "book_prompt_soft"),
			_choice("你想用旧工牌去 900 复核？", "乘客：对。不是逃开柜台，是想带点证据过去。", "case_summary", "乘客目标不是拒绝 900，而是希望在前往 900 前补足身份材料。"),
			_choice("如果旧工牌不在了呢？", "乘客：那就看旧班表。纸柜那边也许还留着。电子记录太快，纸有时候慢一点。", "old_records"),
		]),
		"service_area": _node("乘客：服务区不太像楼层，更像建筑把不方便给人看的东西都放在那里。", [
			_choice("你在那里工作过？", "乘客：算是。缺人就叫我，有人请假就叫我，系统里写“临时协助”。", "work_history"),
			_choice("你记得那层的名字吗？", "乘客：不记得正式名字。大家就说“下面服务区”。", "book_prompt_soft"),
			_choice("那里为什么重要？", "乘客：因为那里的人知道我是谁。不是系统那种知道，是会问我今天怎么又没吃饭的知道。", "unrecorded_help", "乘客需求与非正式生活关系相关。系统推荐目标可能无法覆盖该信息。"),
			_choice("你还愿意去 900 吗？", "乘客：愿意。只是想先把自己的名字带上。", "case_summary"),
		]),
		"old_records": _node("乘客：旧记录层有纸柜。纸会发霉，字会歪，但有时候它比终端宽容。", [
			_choice("你去过旧记录层？", "乘客：去过一次，帮人搬过过期班表。风扇吵，纸灰会粘在手上。", "book_prompt_soft"),
			_choice("你觉得那里会有你的记录？", "乘客：不确定。但如果低层找不到旧牌，那里也许还有第一张班表。", "case_summary"),
			_choice("为什么纸质记录反而有用？", "乘客：因为纸不急着合并人。它只会放在那里，等有人翻。", "case_summary", "乘客提供了第二类目标线索：旧记录相关楼层。建议玩家自行结合楼层索引书判断。"),
			_choice("这听起来不像系统推荐会给的目标。", "乘客：它当然不会推荐。系统推荐的是最顺的地方，不一定是能把话说清楚的地方。", "case_summary"),
		]),
		"work_history": _node("乘客：我不算正式员工，也不算居民服务人员。哪里缺一点，就把我补进去一点。", [
			_choice("所以记录很难归类你。", "乘客：对。系统不喜欢半个岗位。可人活着经常就是半个岗位、半顿饭、半张旧牌。", "case_summary", "乘客身份处于多种低优先级记录之间。建议不要只依据单一推荐目标判断。"),
			_choice("你怕被归到临时支援？", "乘客：临时支援可以随时被替换。可我不是临时认识那些人的。", "case_summary"),
			_choice("你需要我怎么做？", "乘客：别只把我送到最像答案的地方。让我先找一件能说明我的东西。", "case_summary"),
			_choice("我明白了。", "乘客：你明白不明白都没关系。只要电梯真的停一次。", "case_summary"),
		]),
		"record_language": _node("乘客：他们写字很厉害。同一个东西，写成“饭盒”和写成“未登记容器”，后果不一样。", [
			_choice("你很在意记录用词。", "乘客：当然。在这里，词会变成楼层，楼层会变成你能不能回去。", "case_summary", "乘客对系统记录语言高度敏感。后续日志与目标选择应避免过早异常化。"),
			_choice("你希望系统怎么写你？", "乘客：写“夜班回来的人”。别写“异常等待人员”。", "case_summary"),
			_choice("你以前被这样写过？", "乘客：写过一次“逗留”。其实我只是等一个人把钥匙还我。", "case_summary"),
			_choice("我先不替你下结论。", "乘客：谢谢。先不下结论，有时候就是帮忙了。", "case_summary"),
		]),
		"book_prompt_soft": _node("乘客：我记不住编号。你们台上如果还有旧楼层书，可能比我记得准。", [
			_choice("我会查。", "乘客：嗯。别只看推荐，推荐里通常没有这些地方。", "case_summary", "乘客建议查阅右侧纸质楼层索引书。系统推荐目标仍只有 900。"),
			_choice("你能再描述一下吗？", "乘客：低层那个地方有餐盘车。旧记录那个地方有纸柜。一个闻起来潮，一个闻起来灰。", "case_summary"),
			_choice("你是不是想让我手动输入？", "乘客：如果你只能按推荐，那我就去 900。如果你能查，那就查一下。", "case_summary"),
			_choice("我不能保证结果。", "乘客：我也不能。我只是想试一次不是自动跳过去的结果。", "case_summary"),
		]),
		"case_summary": _node("乘客：我知道 900 是流程。我不是不要流程。我只是想先找回一点能让我站在柜台前说话的东西。", [], "乘客目标线索已整理：标准推荐目标为 900；非推荐线索指向低层服务区与旧记录相关楼层。建议玩家查阅纸质楼层索引书并自行验证目标楼层。"),
	}


func _build_floor_book_entries() -> Array:
	# 纸质索引只呈现生活化资料，不泄露系统关联度或通行评估。
	return [
		{"number": "900", "intro": "居民事务柜台层。这里处理迁入、合并、岗位登记、异常路线复核和临时身份牌回收。", "function": "登记复核、居民事务、派单申诉、身份状态更新。", "history": "该层柜台灯网曾因长期开启出现白斑频闪，后改为恒定冷白照明。", "note": "等待区座椅很少，叫号错过后需重新取号。"},
		{"number": "742", "intro": "中继等待层。长距离调度中常被用作临时停靠点，走廊里有旧热水器和三排塑料候椅。", "function": "临时等待、路线复核、短时停留、乘客缓冲。", "history": "该层广播曾延迟三秒，后来被调低，但热水器一直没有更换。", "note": "旧版索引边角写着：杯子要自带。"},
		{"number": "612", "intro": "居住与服务混合层。自动售卖机、公共长椅、旧公告板和小型派单终端挤在同一段走廊里。", "function": "居民接乘、基础服务、短程派单、换班等待。", "history": "门外等待区的灯牌经常闪，维修记录称“不影响识别”。", "note": "公告板上的手写便条会被清洁队定期擦掉。"},
		{"number": "004", "intro": "低层服务区。空气里常有洗洁精、湿灰和热汤混在一起的味道。旧暖柜、回收餐盘车和拖把桶靠墙排放。", "function": "后勤转运、餐具回收、夜班临时发餐、低层服务人员通行。", "history": "早期曾作为备用疏散层，后来改成服务与维护混合区。部分暖柜编号与终端记录不一致。", "note": "纸质索引特别标注：004 前缀零不可省略。"},
		{"number": "387", "intro": "旧记录存放层。纸柜、过期派单、班表副本和居民申诉回执在这里低频存放。", "function": "纸质记录存储、旧档案转运、人工复查、过期柜清理。", "history": "该层曾发生多次归档编号错位，风扇长期开启以降低纸张受潮。", "note": "找不到电子记录时，先看第三排铁柜。"},
		{"number": "392", "intro": "普通通行层。楼道狭长，靠近一处鞋底修补窗口和临时饮水点。", "function": "办公通行、短时等待、维修人员换乘。", "history": "通风系统调整完成，饮水点水压仍偏低。", "note": "未发现与当前派单直接相关的纸质标记。"},
		{"number": "547", "intro": "普通办公层。文件窗口、值班室和小会议间沿走廊排列。", "function": "办公、会议、文件处理、内部人员通行。", "history": "曾因楼层编号牌更换导致短期导航混乱。", "note": "信息较完整，但缺少近期状态记录。"},
	]
