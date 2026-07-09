extends Node
class_name DemoFlowManager


# 状态变化后通知界面等监听者，避免其他节点反复查询流程状态。
signal case_updated
signal destination_submitted(destination: String)


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
var runtime_recommended_destinations: Array[String] = []


func _ready() -> void:
	_configure_issue_12_case()


func _configure_issue_12_case() -> void:
	# 第一位乘客暂用内置案例数据；后续由正式 CaseManager / JSON 替换。
	current_case["pickup"] = {
		"floor": "612",
		"arrival_feedback": "已前往接乘楼层：612。请回到主操作台，使用门外摄像头确认乘客。",
		"arrival_status_hint": "电梯已被指派至 612 层接乘点。建议使用门外摄像头确认乘客状态。",
		"outside_audio_idle": "门外音频链路已开启。",
		"after_open_line": "乘客：谢谢。门关上以后再说吧。",
		"after_open_hint": "乘客已进入舱内。请关闭舱门后继续询问。",
		"after_close_line": "乘客：好了。现在能听见你了。",
		"after_close_hint": "舱门已关闭。可以开启麦克风继续询问。",
		"after_close_status_hint": "乘客已进入舱内，舱门已关闭。可以开始正式询问目标。",
	}
	current_case["camera_feeds"] = {
		"WAITING_FOR_PICKUP": [
			"画面占位：乘客舱内为空。等待接乘任务。",
			"画面占位：当前门外切片暂无待接乘客。请先前往接乘楼层。",
		],
		"ARRIVED_AT_PICKUP": [
			"画面占位：乘客舱内为空。等待乘客进入。",
			"画面占位：612 层门外三到五米切片。自动售卖机旁有一名等待乘客，手里提着旧饭盒。",
		],
		"DOOR_GREETING_DONE": [
			"画面占位：乘客舱内为空。等待乘客进入。",
			"画面占位：612 层门外三到五米切片。等待乘客站在门外，正在等舱门开启。",
		],
		"BOARDING_WAIT_DOOR_CLOSE": [
			"画面占位：乘客站在舱内。她抱着一个旧饭盒，胸牌翻在外套里面。",
			"画面占位：612 层门外切片。自动售卖机灯牌闪烁，等待区已空。",
		],
		"PASSENGER_ONBOARD": [
			"画面占位：乘客站在舱内。她抱着一个旧饭盒，胸牌翻在外套里面。",
			"画面占位：612 层门外切片。自动售卖机灯牌闪烁，等待区已空。",
		],
		"DESTINATION_CONFIRMED": [
			"画面占位：乘客站在舱内。她抱着一个旧饭盒，正在等待电梯执行目标。",
			"画面占位：门外等待区已空。",
		],
	}
	current_case["front_phase_texts"] = {
		"WAITING_FOR_PICKUP": {"state": "当前状态：等待接乘", "task": "当前任务：前往 {pickup_floor} 层接乘"},
		"ARRIVED_AT_PICKUP": {"state": "当前状态：已抵达接乘点", "task": "当前任务：使用门外摄像头确认 {pickup_floor} 层等待乘客"},
		"DOOR_GREETING_DONE": {"state": "当前状态：门外乘客已回应", "task": "当前任务：开启舱门完成接乘"},
		"BOARDING_WAIT_DOOR_CLOSE": {"state": "当前状态：乘客已进入，等待关门", "task": "当前任务：关闭舱门后继续询问"},
		"PASSENGER_ONBOARD": {"state": "当前状态：舱内询问中", "task": "当前任务：询问乘客自述目标并验证楼层"},
		"DESTINATION_CONFIRMED": {"state": "当前状态：目标已提交", "task": "已提交目标：{submitted_destination_or_none}"},
	}
	current_case["right_phase_texts"] = {
		"PICKUP": {"task": "当前任务：前往 {pickup_floor} 层接乘"},
		"ONBOARD": {"task": "当前任务：验证并提交正式目标楼层"},
	}
	current_case["recommended_destination_rules"] = {
		"pickup_phases": ["WAITING_FOR_PICKUP", "ARRIVED_AT_PICKUP", "DOOR_GREETING_DONE", "BOARDING_WAIT_DOOR_CLOSE"],
		"pickup_recommendations": ["612"],
		"default_onboard_recommendations": ["900"],
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
	current_building_status_hint = "当前系统提示：\n%s 层检测到待接乘客。\n建议前往 %s 层完成接乘确认。\n\n当前任务：\n前往接乘楼层。" % [get_pickup_floor(), get_pickup_floor()]

func add_front_transcript_operator(operator_text: String) -> void:
	# 单行写入供 Dialogue Manager 接入使用；仍然只进入 TRANSCRIPT。
	if operator_text.is_empty():
		return
	front_dialogue_history.append("操作员：%s" % operator_text)
	_trim_front_dialogue_history()


func add_front_transcript_passenger(passenger_text: String) -> void:
	if passenger_text.is_empty():
		return
	var formatted_passenger_text: String = passenger_text
	if not formatted_passenger_text.begins_with("乘客："):
		formatted_passenger_text = "乘客：%s" % formatted_passenger_text
	front_dialogue_history.append(formatted_passenger_text)
	_trim_front_dialogue_history()


func _trim_front_dialogue_history() -> void:
	while front_dialogue_history.size() > MAX_FRONT_HISTORY_LINES:
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
	# 集中替换案例占位符，UI 不需要知道接乘楼层或已提交目标的具体值。
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
	destination_submitted.emit(get_submitted_destination())


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


func get_current_recommended_destinations() -> Array:
	var phase: String = get_case_phase()
	var rules: Dictionary = current_case.get("recommended_destination_rules", {})
	var pickup_phases: Array = rules.get("pickup_phases", [])
	var recommendation_key: String = "default_onboard_recommendations"
	if phase in pickup_phases:
		recommendation_key = "pickup_recommendations"
	var configured_candidates: Array = rules.get(recommendation_key, [])
	# 系统推荐与玩家手动发现严格分开，隐藏楼层只能由玩家自行填写。
	var candidates: Array[String] = []
	for destination in configured_candidates:
		var floor_number: String = str(destination)
		if floor_number not in SYSTEM_RECOMMENDATION_EXCLUSIONS:
			candidates.append(floor_number)
	for destination in runtime_recommended_destinations:
		var floor_number: String = str(destination)
		if floor_number not in candidates and floor_number not in SYSTEM_RECOMMENDATION_EXCLUSIONS:
			candidates.append(floor_number)
	return candidates


func add_recommended_destination(destination: String) -> void:
	# DM mutation 只追加本轮运行时推荐，不改写楼层数据库或纸质索引。
	var floor_number: String = destination.strip_edges()
	if floor_number.is_empty() or floor_number in runtime_recommended_destinations:
		return
	runtime_recommended_destinations.append(floor_number)
	case_updated.emit()


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
