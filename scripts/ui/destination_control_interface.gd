extends Control
class_name DestinationControlInterface


signal return_requested


const RECOMMENDED_DESTINATIONS: Array[String] = ["900", "742", "612"]

# Issue 9 的临时楼层数据库；后续会替换为正式楼层数据资源。
# 楼层编号始终按字符串处理，确保 004 之类的编号不会丢失前导零。
const FLOOR_DATABASE: Dictionary = {
	"900": {
		"description": "派单记录目标层。",
		"relevance": "94%",
		"access": "可前往",
		"stability": "基本稳定",
		"hint": "该楼层与当前派单高度一致。",
	},
	"742": {
		"description": "系统推荐的中继目标层。",
		"relevance": "78%",
		"access": "可前往",
		"stability": "轻微波动",
		"hint": "该楼层与当前派单存在关联，但不是派单记录目标。",
	},
	"612": {
		"description": "当前派单起始相关层。",
		"relevance": "63%",
		"access": "可前往",
		"stability": "稳定",
		"hint": "该楼层仍与当前派单相关，适合暂时复核。",
	},
	"004": {
		"description": "低层服务区。",
		"relevance": "37%",
		"access": "可前往",
		"stability": "中度波动",
		"hint": "该楼层不在系统推荐中，但可能满足乘客的特殊需求。",
	},
	"387": {
		"description": "旧记录存放层。",
		"relevance": "29%",
		"access": "可前往",
		"stability": "轻微波动",
		"hint": "该楼层与当前派单存在弱关联，建议谨慎提交。",
	},
	"392": {
		"description": "普通通行层。",
		"relevance": "0%",
		"access": "可前往",
		"stability": "稳定",
		"hint": "该楼层与当前派单无关联，但建筑允许前往。",
	},
	"547": {
		"description": "普通办公层。",
		"relevance": "0%",
		"access": "可前往",
		"stability": "基本稳定",
		"hint": "该楼层与当前派单无关联，稳定度未见明显变化。",
	},
}


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


func show_destination_console() -> void:
	show()
	if manual_destination_line_edit != null:
		manual_destination_line_edit.grab_focus()


func _cache_destination_nodes() -> void:
	title_label = _find_ui_node("TitleLabel") as Label
	dispatch_summary_label = _find_ui_node("DispatchSummaryLabel") as Label
	recommended_title_label = _find_ui_node("RecommendedTitleLabel") as Label
	manual_destination_line_edit = _find_ui_node("ManualDestinationLineEdit") as LineEdit
	verify_destination_button = _find_ui_node("VerifyDestinationButton") as Button
	destination_status_label = _find_ui_node("DestinationStatusLabel") as Label
	destination_feedback_label = _find_ui_node("DestinationFeedbackLabel") as Label
	submit_destination_button = _find_ui_node("SubmitDestinationButton") as Button
	return_button = _find_ui_node("ReturnButton") as Button

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


func _connect_button(button: Button, callback: Callable) -> void:
	if button != null and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _initialize_destination_text() -> void:
	_set_label_text(title_label, "目标楼层控制台 / DESTINATION CONSOLE")
	_set_label_text(
		dispatch_summary_label,
		"当前派单：612 → 900\n系统推荐目标：900 / 742 / 612\n当前状态：等待目标确认"
	)
	_set_label_text(recommended_title_label, "系统推荐楼层：")

	for button_index in recommended_destination_buttons.size():
		if button_index < RECOMMENDED_DESTINATIONS.size():
			recommended_destination_buttons[button_index].text = RECOMMENDED_DESTINATIONS[button_index]

	if manual_destination_line_edit != null:
		manual_destination_line_edit.text = "900"
	_set_button_text(verify_destination_button, "验证地址")
	_set_label_text(destination_status_label, _build_unverified_status())
	_set_label_text(
		destination_feedback_label,
		"请选择推荐楼层，或手动输入目标楼层。"
	)
	_set_button_text(submit_destination_button, "提交目标")
	_set_button_text(return_button, "返回操作间")


func _select_recommended_destination(button_index: int) -> void:
	if button_index < 0 or button_index >= RECOMMENDED_DESTINATIONS.size():
		push_warning("DestinationControlInterface: Invalid recommendation slot.")
		return
	if manual_destination_line_edit == null:
		return

	var destination: String = RECOMMENDED_DESTINATIONS[button_index]
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
	is_destination_recognized = FLOOR_DATABASE.has(destination)

	if not is_destination_recognized:
		_set_label_text(destination_status_label, _build_unrecognized_status(destination))
		_set_label_text(destination_feedback_label, "无法识别目标楼层：%s。" % destination)
		_append_operation("目标验证：%s / 无法识别 / 无法前往" % destination)
		return

	var floor_data: Dictionary = FLOOR_DATABASE[destination]
	_set_label_text(destination_status_label, _build_recognized_status(destination, floor_data))
	_set_label_text(destination_feedback_label, "目标已验证：%s。" % destination)
	_append_operation(
		"目标验证：%s / %s / 稳定度%s / 关联度%s" % [
			destination,
			floor_data["access"],
			floor_data["stability"],
			floor_data["relevance"],
		]
	)


func _submit_destination() -> void:
	var destination: String = _get_current_destination()
	if destination.is_empty():
		_set_label_text(destination_feedback_label, "请输入目标楼层。")
		_append_operation("目标提交失败：空输入")
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

	var floor_data: Dictionary = FLOOR_DATABASE[destination]
	_set_label_text(
		destination_feedback_label,
		"目标已提交：%s\n通行评估：%s\n稳定度：%s\n电梯将前往该目标。" % [
			destination,
			floor_data["access"],
			floor_data["stability"],
		]
	)
	_append_operation("目标提交：%s" % destination)


func _get_current_destination() -> String:
	if manual_destination_line_edit == null:
		return ""
	# 只清理首尾空格，不转为整数，以保留 004 等完整楼层编号。
	return manual_destination_line_edit.text.strip_edges()


func _build_unverified_status() -> String:
	return """目标确认状态：未验证
当前目标：900
楼层说明：等待验证
与当前派单的关联度：待评估
通行评估：等待验证
稳定度：待评估

系统提示：
请选择系统推荐楼层，或手动输入目标楼层后进行验证。"""


func _build_recognized_status(destination: String, floor_data: Dictionary) -> String:
	return """目标确认状态：已验证
当前目标：%s
楼层说明：%s
与当前派单的关联度：%s
通行评估：%s
稳定度：%s

系统提示：
%s""" % [
		destination,
		floor_data["description"],
		floor_data["relevance"],
		floor_data["access"],
		floor_data["stability"],
		floor_data["hint"],
	]


func _build_unrecognized_status(destination: String) -> String:
	return """目标确认状态：无法确认
当前目标：%s
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
