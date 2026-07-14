extends Control
class_name BuildingTerminalInterface


signal return_requested


const FALLBACK_RECORD_CONTENT: String = """乘客档案

姓名：M. ROWAN
登记状态：UNREGISTERED
风险标记：LOW
当前派单：612 → 900
平均停留：2 MIN

近期路线：
612 → 900 / APPROVED
612 → 900 / APPROVED
612 → 900 / APPROVED

备注：
该乘客近期路线重复率异常。
当前自述与历史目的地不完全一致。"""

const EMPTY_TRANSCRIPT_CONTENT: String = """对话记录

暂无通话转写。
请先在 FRONT 主仲裁台开启麦克风并选择对话。"""

const EMPTY_SYSTEM_LOG_CONTENT: String = "暂无系统通信记录。"


# 场景结构已固定，直接引用节点，避免运行时按名称遍历整棵节点树。
@onready var title_label: Label = $TerminalLayout/TitleLabel
@onready var access_status_label: Label = $TerminalLayout/AccessStatusLabel
@onready var record_tab_button: Button = $TerminalLayout/TabButtonPanel/RecordTabButton
@onready var transcript_tab_button: Button = $TerminalLayout/TabButtonPanel/TranscriptTabButton
@onready var system_log_tab_button: Button = $TerminalLayout/TabButtonPanel/SystemLogTabButton
@onready var terminal_content_label: Label = $TerminalLayout/ContentScrollContainer/TerminalContentPanel/TerminalContentMargin/TerminalContentLabel
@onready var terminal_hint_label: Label = $TerminalLayout/TerminalHintLabel
@onready var return_button: Button = $TerminalLayout/ReturnButton

var demo_flow_manager: DemoFlowManager


func _ready() -> void:
	_connect_terminal_signals()
	_initialize_terminal_text()
	_set_content(EMPTY_SYSTEM_LOG_CONTENT, "等待系统通信。")


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		push_warning("BuildingTerminalInterface: DemoFlowManager is not connected.")
		return
	# 父节点完成依赖注入后刷新一次，补上子节点 ready 时尚未取得的共享事件。
	_show_system_log_tab()


func show_terminal() -> void:
	# 每次进入默认显示系统通信历史，便于复核本轮判断的变化。
	_show_system_log_tab()
	show()
	if system_log_tab_button != null:
		system_log_tab_button.grab_focus()


func _connect_terminal_signals() -> void:
	# 三个页签分别读取系统通信、乘客资料和对话记录。
	_connect_button(record_tab_button, _show_record_tab)
	_connect_button(transcript_tab_button, _show_transcript_tab)
	_connect_button(system_log_tab_button, _show_system_log_tab)
	_connect_button(return_button, _request_return)


func _connect_button(button: Button, callback: Callable) -> void:
	if button != null and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _initialize_terminal_text() -> void:
	_set_label_text(title_label, "建筑终端 / BUILDING TERMINAL")
	_set_label_text(access_status_label, "访问权限：OPERATOR｜节点：L-612-A｜会话：ACTIVE")
	_set_button_text(record_tab_button, "乘客档案")
	_set_button_text(transcript_tab_button, "对话记录")
	_set_button_text(system_log_tab_button, "系统日志")
	_set_button_text(return_button, "返回操作间")


func _show_record_tab() -> void:
	_set_content(_build_record_content(), "乘客记录来自当前复核案例。")


func _build_record_content() -> String:
	# RECORD 从 current_case 生成；流程管理器缺失时才退回旧占位文本。
	if demo_flow_manager == null:
		return FALLBACK_RECORD_CONTENT

	var passenger_record: Dictionary = demo_flow_manager.get_passenger_record()
	if passenger_record.is_empty():
		return FALLBACK_RECORD_CONTENT

	var record_lines := PackedStringArray([
		"乘客档案",
		"",
		"姓名：%s" % passenger_record.get("name", demo_flow_manager.get_passenger_name()),
		"常用称呼：%s" % passenger_record.get("display_name", "罗文"),
		"登记状态：%s" % passenger_record.get("registration_status", "UNKNOWN"),
		"风险标记：%s" % passenger_record.get("risk_tag", "UNKNOWN"),
		"当前派单：%s" % demo_flow_manager.get_dispatch_text(),
		"平均停留：%s" % passenger_record.get("average_stay", "UNKNOWN"),
		"",
		"近期路线：",
	])
	var recent_routes: Array = passenger_record.get("recent_routes", [])
	for route in recent_routes:
		record_lines.append(str(route))

	record_lines.append("")
	record_lines.append("备注：")
	record_lines.append(str(passenger_record.get("note", "暂无备注。")))

	var submitted_destination: String = demo_flow_manager.get_submitted_destination()
	if not submitted_destination.is_empty():
		record_lines.append("")
		record_lines.append("当前已提交目标：%s" % submitted_destination)
	return "\n".join(record_lines)


func _show_transcript_tab() -> void:
	# TRANSCRIPT 只读取临时对话历史，不混入麦克风、摄像头或门控操作。
	var dialogue_history: Array[String] = _get_front_dialogue_history()
	if dialogue_history.is_empty():
		_set_content(EMPTY_TRANSCRIPT_CONTENT, "暂无可复核的通话转写。")
		return

	var transcript_lines := PackedStringArray(["对话记录", ""])
	for dialogue_line in dialogue_history:
		transcript_lines.append(dialogue_line)
	_set_content("\n".join(transcript_lines), "已读取 FRONT 临时对话缓存。")


func _show_system_log_tab() -> void:
	# 系统日志记录建筑对操作员的通信，不记录玩家按钮操作。
	var message_history: Array[String] = _get_system_message_history()
	if message_history.is_empty():
		_set_content(EMPTY_SYSTEM_LOG_CONTENT, "暂无需要复核的系统通信。")
		return

	var log_lines := PackedStringArray(["系统日志", ""])
	for message_text in message_history:
		log_lines.append(message_text)
	_set_content("\n\n".join(log_lines), "已读取本轮系统通信历史。")
	if demo_flow_manager != null:
		demo_flow_manager.clear_unread_building_status_hint()


func _get_front_dialogue_history() -> Array[String]:
	# dialogue_history 专供 LEFT 的 TRANSCRIPT，后续会由 PassengerCase 替换。
	if demo_flow_manager == null:
		push_warning("BuildingTerminalInterface: Cannot read dialogue without DemoFlowManager.")
		var empty_history: Array[String] = []
		return empty_history
	return demo_flow_manager.get_front_dialogue_history()


func _get_system_message_history() -> Array[String]:
	if demo_flow_manager == null:
		push_warning("BuildingTerminalInterface: Cannot read system messages without DemoFlowManager.")
		var empty_history: Array[String] = []
		return empty_history
	return demo_flow_manager.get_system_message_history()


func _set_content(content_text: String, hint_text: String) -> void:
	_set_label_text(terminal_content_label, content_text)
	_set_label_text(terminal_hint_label, hint_text)


func _set_label_text(label: Label, new_text: String) -> void:
	if label != null:
		label.text = new_text


func _set_button_text(button: Button, new_text: String) -> void:
	if button != null:
		button.text = new_text


func _request_return() -> void:
	# 与 FRONT 相同，界面只通知外层控制器恢复电梯操作间。
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
