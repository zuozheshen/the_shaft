extends Control
class_name DestinationControlInterface


signal return_requested


const RECOMMENDED_DESTINATIONS: Array[String] = ["612"]

# Issue 9 的临时楼层数据库；后续会替换为正式楼层数据资源。
# 楼层编号始终按字符串处理，确保 004 之类的编号不会丢失前导零。
const FLOOR_DATABASE: Dictionary = {
	"900": {
		"description": "派单记录目标层。",
		"relation": "94%",
		"access_eval": "可前往",
		"stability": "基本稳定",
		"message": "该楼层与当前派单高度一致。",
	},
	"742": {
		"description": "系统推荐的中继目标层。",
		"relation": "78%",
		"access_eval": "可前往",
		"stability": "轻微波动",
		"message": "该楼层与当前派单存在关联，但不是派单记录目标。",
	},
	"612": {
		"description": "当前派单起始相关层。",
		"relation": "63%",
		"access_eval": "可前往",
		"stability": "稳定",
		"message": "该楼层仍与当前派单相关，适合暂时复核。",
	},
	"004": {
		"description": "低层服务区。",
		"relation": "48%",
		"access_eval": "可前往",
		"stability": "中等波动",
		"message": "该楼层不在系统推荐中，但与乘客描述的服务区、洗洁精味和旧暖柜线索相符。",
	},
	"387": {
		"description": "旧记录存放层。",
		"relation": "29%",
		"access_eval": "可前往",
		"stability": "轻微波动",
		"message": "该楼层与当前派单存在弱关联，建议谨慎提交。",
	},
	"392": {
		"description": "普通通行层。",
		"relation": "0%",
		"access_eval": "可前往",
		"stability": "稳定",
		"message": "该楼层与当前派单无关联，但建筑允许前往。",
	},
	"547": {
		"description": "普通办公层。",
		"relation": "0%",
		"access_eval": "可前往",
		"stability": "基本稳定",
		"message": "该楼层与当前派单无关联，稳定度未见明显变化。",
	},
}

# Issue 10 的临时纸质索引数据，与负责系统验证的 FLOOR_DATABASE 分开维护。
# 书页只保存纸面资料，不包含关联度、通行评估、稳定度或系统提示。
const FLOOR_BOOK_ENTRIES: Array[Dictionary] = [
	{
		"number": "900",
		"intro": "派单记录中的目标层，常用于标准人员交接与登记确认。",
		"function": "登记、交接、身份复核、短暂停留。",
		"history": "该层曾在多次垂直调度异常后作为稳定参照层使用。",
		"note": "纸质索引内容可能滞后于建筑当前状态。",
	},
	{
		"number": "742",
		"intro": "中继楼层，常见于长距离垂直调度中的临时停靠。",
		"function": "中继等待、人员重新编号、短时路线复核。",
		"history": "曾因照明频闪与广播延迟被短暂停用，后恢复为有限通行层。",
		"note": "部分旧版索引将该层标为“等待层”。",
	},
	{
		"number": "612",
		"intro": "当前派单起始相关层，靠近普通居住与服务混合区。",
		"function": "居民登记、基础服务、短程派单生成。",
		"history": "多次门控校准记录显示，该层门外等待区存在轻微延迟。",
		"note": "该层记录常被用作派单起点参考。",
	},
	{
		"number": "004",
		"intro": "低层服务区，位于旧维护系统附近。",
		"function": "后勤转运、旧设备暂存、低层人员通行。",
		"history": "早期曾作为备用疏散层使用，后被改为服务与维护混合区。",
		"note": "纸质索引中对该层描述较少，部分信息可能缺失。",
	},
	{
		"number": "387",
		"intro": "旧记录存放层，保留大量过期派单、登记与复核资料。",
		"function": "纸质记录存储、过期档案转运、人工复查。",
		"history": "该层曾发生多次归档编号错位，后改为低频访问区域。",
		"note": "部分乘客记录可能仍指向该层的旧档案柜。",
	},
	{
		"number": "392",
		"intro": "普通通行层，服务于常规办公与短时停留。",
		"function": "办公、通行、临时等待。",
		"history": "最近一次维护记录显示通风系统调整完成。",
		"note": "未发现与当前派单直接相关的纸质标记。",
	},
	{
		"number": "547",
		"intro": "普通办公层，主要供内部人员使用。",
		"function": "办公、会议、文件处理。",
		"history": "该层曾因楼层编号牌更换导致短期导航混乱。",
		"note": "纸质索引中该层信息较完整，但缺少近期状态记录。",
	},
]


# 手工场景节点可能仍在调整，因此统一安全查找；缺失节点只跳过对应功能。
var title_label: Label
var dispatch_summary_label: Label
var recommended_title_label: Label
var recommended_destination_buttons: Array[Button] = []
var manual_destination_line_edit: LineEdit
var verify_destination_button: Button
var destination_status_label: Label
var destination_feedback_label: Label
var submit_destination_button: Button
var return_button: Button

# 索引书是右侧操作台上的纸质资料页，不参与系统验证结果计算。
var root_margin: MarginContainer
var open_floor_book_button: Button
var floor_book_page: MarginContainer
var floor_book_title_label: Label
var floor_book_page_label: Label
var floor_book_number_label: Label
var floor_book_intro_label: Label
var floor_book_function_label: Label
var floor_book_history_label: Label
var floor_book_note_label: Label
var previous_book_page_button: Button
var next_book_page_button: Button
var fill_current_floor_button: Button
var close_floor_book_button: Button
var current_book_page_index: int = 0

var demo_flow_manager: DemoFlowManager

# 这里仅记录目标确认结果，不会触发真实电梯移动或楼层切换。
var verified_destination: String = ""
var is_destination_verified: bool = false
var is_destination_recognized: bool = false


func _ready() -> void:
	_cache_destination_nodes()
	_connect_destination_signals()
	_initialize_destination_text()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		push_warning("DestinationControlInterface: DemoFlowManager is not connected.")
		return
	# 子节点 ready 后才注入共享流程，因此这里再次刷新案例相关文字。
	_initialize_destination_text()


func show_destination_console() -> void:
	# 每次进入 RIGHT 时先显示主控制台，但保留玩家上次填写的目标楼层。
	_initialize_destination_text()
	_set_floor_book_visibility(false)
	show()
	if manual_destination_line_edit != null:
		manual_destination_line_edit.grab_focus()


func _cache_destination_nodes() -> void:
	root_margin = _find_ui_node("RootMargin") as MarginContainer
	title_label = _find_ui_node("TitleLabel") as Label
	dispatch_summary_label = _find_ui_node("DispatchSummaryLabel") as Label
	recommended_title_label = _find_ui_node("RecommendedTitleLabel") as Label
	manual_destination_line_edit = _find_ui_node("ManualDestinationLineEdit") as LineEdit
	verify_destination_button = _find_ui_node("VerifyDestinationButton") as Button
	destination_status_label = _find_ui_node("DestinationStatusLabel") as Label
	destination_feedback_label = _find_ui_node("DestinationFeedbackLabel") as Label
	submit_destination_button = _find_ui_node("SubmitDestinationButton") as Button
	return_button = _find_ui_node("ReturnButton") as Button
	open_floor_book_button = _find_ui_node("OpenFloorBookButton") as Button
	floor_book_page = _find_ui_node("FloorBookPage") as MarginContainer
	floor_book_title_label = _find_ui_node("FloorBookTitleLabel") as Label
	floor_book_page_label = _find_ui_node("FloorBookPageLabel") as Label
	floor_book_number_label = _find_ui_node("FloorBookNumberLabel") as Label
	floor_book_intro_label = _find_ui_node("FloorBookIntroLabel") as Label
	floor_book_function_label = _find_ui_node("FloorBookFunctionLabel") as Label
	floor_book_history_label = _find_ui_node("FloorBookHistoryLabel") as Label
	floor_book_note_label = _find_ui_node("FloorBookNoteLabel") as Label
	previous_book_page_button = _find_ui_node("PrevBookPageButton") as Button
	next_book_page_button = _find_ui_node("NextBookPageButton") as Button
	fill_current_floor_button = _find_ui_node("FillCurrentFloorButton") as Button
	close_floor_book_button = _find_ui_node("CloseFloorBookButton") as Button

	# 三个按钮是推荐数据槽位，显示数字来自 RECOMMENDED_DESTINATIONS，而不是节点名。
	for button_number in range(1, 4):
		var recommendation_button := _find_ui_node(
			"RecommendedDestinationButton%d" % button_number
		) as Button
		if recommendation_button != null:
			recommended_destination_buttons.append(recommendation_button)


func _find_ui_node(node_name: String) -> Node:
	var found_node: Node = find_child(node_name, true, false)
	if found_node == null:
		push_warning("DestinationControlInterface: Missing optional node '%s'." % node_name)
	return found_node


func _connect_destination_signals() -> void:
	# 推荐、验证、提交和返回均逐项检查，避免手工场景缺少节点时崩溃。
	for button_index in recommended_destination_buttons.size():
		var recommendation_button := recommended_destination_buttons[button_index]
		var callback: Callable = _select_recommended_destination.bind(button_index)
		if not recommendation_button.pressed.is_connected(callback):
			recommendation_button.pressed.connect(callback)

	_connect_button(verify_destination_button, _verify_destination)
	_connect_button(submit_destination_button, _submit_destination)
	_connect_button(return_button, _request_return)
	# 打开、填写和合上会记入 SYSTEM LOG；前后翻页只是浏览，不记录操作。
	_connect_button(open_floor_book_button, _open_floor_book)
	_connect_button(previous_book_page_button, _change_floor_book_page.bind(-1))
	_connect_button(next_book_page_button, _change_floor_book_page.bind(1))
	_connect_button(fill_current_floor_button, _fill_current_floor)
	_connect_button(close_floor_book_button, _close_floor_book)


func _connect_button(button: Button, callback: Callable) -> void:
	if button != null and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _initialize_destination_text() -> void:
	var recommended_destinations: Array = _get_recommended_destinations()
	_set_label_text(title_label, "目标楼层控制台 / DESTINATION CONSOLE")
	_update_dispatch_summary_label()
	_set_label_text(recommended_title_label, "系统推荐楼层：")

	_update_recommended_destination_buttons()

	if manual_destination_line_edit != null:
		manual_destination_line_edit.text = str(recommended_destinations[0]) \
			if not recommended_destinations.is_empty() else ""
	_set_button_text(verify_destination_button, "验证地址")
	_set_label_text(destination_status_label, _build_unverified_status(_get_current_destination()))
	_set_label_text(
		destination_feedback_label,
		"请选择推荐楼层，或手动输入目标楼层。"
	)
	_set_button_text(submit_destination_button, "提交目标")
	_set_button_text(return_button, "返回操作间")
	_set_button_text(open_floor_book_button, "查看楼层索引书")
	_set_label_text(floor_book_title_label, "楼层索引书 / FLOOR DIRECTORY")
	_set_button_text(previous_book_page_button, "上一页")
	_set_button_text(next_book_page_button, "下一页")
	_set_button_text(fill_current_floor_button, "填写此楼层")
	_set_button_text(close_floor_book_button, "合上索引书")
	current_book_page_index = 0
	_update_floor_book_display()
	_set_floor_book_visibility(false)


func _open_floor_book() -> void:
	current_book_page_index = 0
	_update_floor_book_display()
	_set_floor_book_visibility(true)
	_append_operation("打开楼层索引书")
	if next_book_page_button != null:
		next_book_page_button.grab_focus()


func _close_floor_book() -> void:
	_set_floor_book_visibility(false)
	_set_label_text(destination_feedback_label, "已合上楼层索引书。")
	_append_operation("合上楼层索引书")
	if open_floor_book_button != null:
		open_floor_book_button.grab_focus()


func _change_floor_book_page(direction: int) -> void:
	var floor_book_entries: Array = _get_floor_book_entries()
	if floor_book_entries.is_empty():
		push_warning("DestinationControlInterface: Floor book has no entries.")
		return
	# 纸质书翻页仅改变浏览页码，不写入 LEFT 的 SYSTEM LOG。
	current_book_page_index = wrapi(
		current_book_page_index + direction,
		0,
		floor_book_entries.size()
	)
	_update_floor_book_display()


func _fill_current_floor() -> void:
	var floor_book_entries: Array = _get_floor_book_entries()
	if floor_book_entries.is_empty():
		push_warning("DestinationControlInterface: Cannot fill from an empty floor book.")
		return
	if manual_destination_line_edit == null:
		return

	# 楼层编号直接作为字符串填写，004 等编号不会被转换为整数。
	var entry: Dictionary = floor_book_entries[current_book_page_index]
	var floor_number: String = entry["number"]
	manual_destination_line_edit.text = floor_number
	_set_floor_book_visibility(false)
	_set_label_text(
		destination_feedback_label,
		"已从楼层索引书填写：%s。请验证地址。" % floor_number
	)
	_append_operation("从楼层索引书填写：%s" % floor_number)
	# 纸质索引只帮助玩家填写；004 / 387 等隐藏楼层不会因此成为系统推荐。
	if verify_destination_button != null:
		verify_destination_button.grab_focus()


func _set_floor_book_visibility(book_is_open: bool) -> void:
	if root_margin != null:
		root_margin.visible = not book_is_open
	if floor_book_page != null:
		floor_book_page.visible = book_is_open


func _update_floor_book_display() -> void:
	var floor_book_entries: Array = _get_floor_book_entries()
	if floor_book_entries.is_empty():
		push_warning("DestinationControlInterface: Floor book has no entries to display.")
		return

	var entry: Dictionary = floor_book_entries[current_book_page_index]
	_set_label_text(
		floor_book_page_label,
		"第 %d / %d 页" % [current_book_page_index + 1, floor_book_entries.size()]
	)
	_set_label_text(floor_book_number_label, "楼层编号：%s" % entry["number"])
	_set_label_text(floor_book_intro_label, "楼层介绍：%s" % entry["intro"])
	_set_label_text(floor_book_function_label, "主要功能：%s" % entry["function"])
	_set_label_text(floor_book_history_label, "维修历史：%s" % entry["history"])
	_set_label_text(floor_book_note_label, "备注：%s" % entry["note"])


func _select_recommended_destination(button_index: int) -> void:
	var recommended_destinations: Array = _get_recommended_destinations()
	if button_index < 0 or button_index >= recommended_destinations.size():
		push_warning("DestinationControlInterface: Invalid recommendation slot.")
		return
	if manual_destination_line_edit == null:
		return

	var destination: String = str(recommended_destinations[button_index])
	manual_destination_line_edit.text = destination
	_set_label_text(
		destination_feedback_label,
		"已填入推荐楼层：%s。请验证地址。" % destination
	)
	_append_operation("推荐楼层选择：%s" % destination)


func _verify_destination() -> void:
	var destination: String = _get_current_destination()
	if destination.is_empty():
		_set_label_text(destination_feedback_label, "请输入目标楼层。")
		_append_operation("目标验证失败：空输入")
		return

	verified_destination = destination
	is_destination_verified = true
	var floor_database: Dictionary = _get_floor_database()
	is_destination_recognized = floor_database.has(destination)

	if not is_destination_recognized:
		_set_label_text(destination_status_label, _build_unrecognized_status(destination))
		_set_label_text(destination_feedback_label, "无法识别目标楼层：%s。" % destination)
		_append_operation("目标验证：%s / 无法识别 / 无法前往" % destination)
		return
	var phase: String = demo_flow_manager.get_case_phase() \
		if demo_flow_manager != null else "PASSENGER_ONBOARD"
	var pickup_floor: String = demo_flow_manager.get_pickup_floor() \
		if demo_flow_manager != null else "612"
	if destination == pickup_floor and phase in ["WAITING_FOR_PICKUP", "ARRIVED_AT_PICKUP", "DOOR_GREETING_DONE", "BOARDING_WAIT_DOOR_CLOSE"]:
		_set_label_text(destination_status_label, _build_pickup_status(pickup_floor))
		_set_label_text(destination_feedback_label, "接乘楼层已确认：%s。可直接提交接乘任务。" % pickup_floor)
		_append_operation("接乘楼层确认：%s" % pickup_floor)
		return

	var floor_data: Dictionary = floor_database[destination]
	_set_label_text(destination_status_label, _build_recognized_status(destination, floor_data))
	_set_label_text(destination_feedback_label, "目标已验证：%s。" % destination)
	_append_operation(
		"目标验证：%s / %s / 稳定度%s / 关联度%s" % [
			destination,
			floor_data["access_eval"],
			floor_data["stability"],
			floor_data["relation"],
		]
	)
	# 验证只决定能否提交，不改变系统愿意主动推荐的楼层。


func _submit_destination() -> void:
	var destination: String = _get_current_destination()
	if destination.is_empty():
		_set_label_text(destination_feedback_label, "请输入目标楼层。")
		_append_operation("目标提交失败：空输入")
		return
	var phase: String = demo_flow_manager.get_case_phase() \
		if demo_flow_manager != null else "PASSENGER_ONBOARD"
	# 接乘楼层不是正式目标，因此无需先执行地址验证。
	if phase in ["WAITING_FOR_PICKUP", "ARRIVED_AT_PICKUP", "DOOR_GREETING_DONE", "BOARDING_WAIT_DOOR_CLOSE"]:
		var pickup_floor: String = demo_flow_manager.get_pickup_floor() \
			if demo_flow_manager != null else "612"
		if destination != pickup_floor:
			_set_label_text(destination_feedback_label, "当前任务是前往 %s 层完成接乘。" % pickup_floor)
			_append_operation("目标提交失败：%s / 尚未完成接乘" % destination)
			return
		if demo_flow_manager != null:
			demo_flow_manager.set_submitted_destination(pickup_floor)
			demo_flow_manager.set_case_phase("ARRIVED_AT_PICKUP")
			demo_flow_manager.set_building_status_hint(demo_flow_manager.get_pickup_arrival_status_hint(), true)
			_set_label_text(destination_feedback_label, demo_flow_manager.get_pickup_arrival_feedback())
		else:
			_set_label_text(destination_feedback_label, "已前往接乘楼层：%s。" % pickup_floor)
		_append_operation("目标提交：%s / 接乘楼层" % pickup_floor)
		_update_dispatch_summary_label()
		return

	# 输入内容若在验证后被修改，必须重新验证当前字符串。
	if not is_destination_verified or destination != verified_destination:
		_set_label_text(destination_feedback_label, "请先验证目标楼层。")
		_append_operation("目标提交失败：未验证")
		return

	if not is_destination_recognized:
		_set_label_text(
			destination_feedback_label,
			"提交失败：无法识别目标楼层 %s。\n请重新输入或选择系统推荐楼层。" % destination
		)
		_append_operation("目标提交失败：%s / 无法识别" % destination)
		return

	var floor_database: Dictionary = _get_floor_database()
	var floor_data: Dictionary = floor_database[destination]
	_set_label_text(
		destination_feedback_label,
		"目标已提交：%s\n通行评估：%s\n稳定度：%s\n电梯将前往该目标。" % [
			destination,
			floor_data["access_eval"],
			floor_data["stability"],
		]
	)
	if demo_flow_manager != null:
		demo_flow_manager.set_case_phase("DESTINATION_CONFIRMED")
		# 先写入通用系统提示；随后提交目标会触发 DM，允许 destination_xxx 里的 status_hint 覆盖它。
		demo_flow_manager.set_building_status_hint(
			_build_destination_status_hint(destination, floor_data),
			true
		)
		demo_flow_manager.set_submitted_destination(destination)
	_append_operation("目标提交：%s" % destination)
	_update_dispatch_summary_label()


func _build_destination_status_hint(destination: String, floor_data: Dictionary) -> String:
	# 右操作台只生成系统状态提示；乘客反馈由 Dialogue Manager 的 destination_xxx 标题负责。
	return "目标 %s 已确认。\n通行评估：%s\n稳定度：%s\n系统提示：%s" % [
		destination,
		str(floor_data.get("access_eval", "待评估")),
		str(floor_data.get("stability", "待评估")),
		str(floor_data.get("message", "目标已提交。")),
	]


func _get_current_destination() -> String:
	if manual_destination_line_edit == null:
		return ""
	# 只清理首尾空格，不转为整数，以保留 004 等完整楼层编号。
	return manual_destination_line_edit.text.strip_edges()


func _build_unverified_status(destination: String) -> String:
	return """目标确认状态：未验证
待验证楼层：%s
楼层说明：等待验证
与当前派单的关联度：待评估
通行评估：等待验证
稳定度：待评估

系统提示：
请选择系统推荐楼层，或手动输入目标楼层后进行验证。""" % destination


func _build_pickup_status(pickup_floor: String) -> String:
	return """目标确认状态：接乘楼层
接乘楼层：%s
楼层说明：当前待接乘客所在楼层。
通行评估：可前往

系统提示：
该楼层用于完成接乘确认。抵达后请使用门外摄像头联系乘客。""" % pickup_floor


func _build_recognized_status(destination: String, floor_data: Dictionary) -> String:
	return """目标确认状态：已验证
已验证楼层：%s
楼层说明：%s
与当前派单的关联度：%s
通行评估：%s
稳定度：%s

系统提示：
%s""" % [
		destination,
		floor_data["description"],
		floor_data["relation"],
		floor_data["access_eval"],
		floor_data["stability"],
		floor_data["message"],
	]


func _get_recommended_destinations() -> Array:
	if demo_flow_manager != null:
		var destinations: Array = demo_flow_manager.get_current_recommended_destinations()
		if not destinations.is_empty():
			return destinations
	return RECOMMENDED_DESTINATIONS


func add_recommended_floor(floor_id: String) -> void:
	# Dialogue Manager 只解锁一个临时推荐楼层；右侧控制台负责刷新可见按钮。
	if demo_flow_manager != null:
		demo_flow_manager.add_recommended_destination(floor_id)
	_initialize_destination_text()


func _update_recommended_destination_buttons() -> void:
	# 三个槽位只显示系统推荐；手动验证或查书填写不会把隐藏楼层塞进这里。
	var candidates: Array = _get_recommended_destinations()
	for button_index in recommended_destination_buttons.size():
		var has_candidate: bool = button_index < candidates.size() and button_index < 3
		var button: Button = recommended_destination_buttons[button_index]
		button.visible = has_candidate
		button.disabled = not has_candidate
		button.text = str(candidates[button_index]) if has_candidate else "—"


func _update_dispatch_summary_label() -> void:
	var recommendations: Array = _get_recommended_destinations()
	var recommendation_labels := PackedStringArray()
	for destination in recommendations:
		recommendation_labels.append(str(destination))
	var recommendation_text: String = " / ".join(recommendation_labels)
	var passenger_label: String = "当前乘客"
	var task_text: String = "当前任务：前往接乘楼层"
	var submitted_destination_text: String = "已提交目标：暂无"
	if demo_flow_manager != null:
		passenger_label = demo_flow_manager.get_passenger_label()
		task_text = demo_flow_manager.get_right_phase_task_text()
		var submitted_destination: String = demo_flow_manager.get_submitted_destination()
		if not submitted_destination.is_empty():
			submitted_destination_text = "已提交目标：%s" % submitted_destination
	var summary: String = "当前乘客：%s\n%s\n%s\n系统推荐楼层：%s" % [
		passenger_label, task_text, submitted_destination_text, recommendation_text,
	]
	_set_label_text(dispatch_summary_label, summary)


func _get_floor_database() -> Dictionary:
	# 正常运行读取 current_case；常量只用于流程管理器缺失时防止场景崩溃。
	if demo_flow_manager != null:
		var case_floor_database: Dictionary = demo_flow_manager.get_floor_database()
		if not case_floor_database.is_empty():
			return case_floor_database
	return FLOOR_DATABASE


func _get_floor_book_entries() -> Array:
	if demo_flow_manager != null:
		var case_book_entries: Array = demo_flow_manager.get_floor_book_entries()
		if not case_book_entries.is_empty():
			return case_book_entries
	return FLOOR_BOOK_ENTRIES


func _build_unrecognized_status(destination: String) -> String:
	return """目标确认状态：无法确认
待验证楼层：%s
楼层说明：无记录
与当前派单的关联度：未知
通行评估：无法前往
稳定度：未知

系统提示：
无法识别该楼层。请重新输入目标楼层。""" % destination


func _append_operation(operation_text: String) -> void:
	# RIGHT 操作只写入 LEFT 的 SYSTEM LOG，不会进入 TRANSCRIPT。
	# 当前沿用早期以 FRONT 命名的临时操作缓存，后续由统一事件系统替换。
	if demo_flow_manager == null:
		push_warning("DestinationControlInterface: Cannot record operation without DemoFlowManager.")
		return
	demo_flow_manager.add_front_operation(operation_text)


func _set_label_text(label: Label, new_text: String) -> void:
	if label != null:
		label.text = new_text


func _set_button_text(button: Button, new_text: String) -> void:
	if button != null:
		button.text = new_text


func _request_return() -> void:
	return_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or _is_key_pressed(event, KEY_S):
		_request_return()
		get_viewport().set_input_as_handled()


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)
