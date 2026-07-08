extends Control
class_name BuildingTerminalInterface


signal return_requested


const STATUS_CONTENT: String = """稳定度：62%
建筑状态：CAUTION
请求解析：PARTIAL
路线匹配率：42%

当前判断：
- 乘客目的地字段不完整。
- 乘客自述与派单记录存在偏差。
- 建议：继续询问，保持门控关闭。

系统建议：
继续复核乘客自述。
必要时查看 TRANSCRIPT 与 SYSTEM LOG。"""

const RECORD_CONTENT: String = """乘客记录

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

const EMPTY_TRANSCRIPT_CONTENT: String = """对话转写

暂无通话转写。
请先在 FRONT 主仲裁台开启麦克风并选择对话。"""

const EMPTY_SYSTEM_LOG_CONTENT: String = """系统日志

[19:42] AUDIO LINK STANDBY
[19:43] REQUEST PARSE PARTIAL
[19:43] RECORD INCOMPLETE
[19:44] DOOR HOLD RECOMMENDED
[19:44] RECORD CONFLICT POSSIBLE"""


# 左侧建筑终端只显示系统复核信息；这些节点均安全查找，避免手工场景缺项时崩溃。
var title_label: Label
var access_status_label: Label
var status_tab_button: Button
var record_tab_button: Button
var transcript_tab_button: Button
var system_log_tab_button: Button
var terminal_content_label: Label
var terminal_hint_label: Label
var return_button: Button

var demo_flow_manager: DemoFlowManager


func _ready() -> void:
	_cache_terminal_nodes()
	_connect_terminal_signals()
	_initialize_terminal_text()
	_show_status_tab()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		push_warning("BuildingTerminalInterface: DemoFlowManager is not connected.")
		return
	# 父节点完成依赖注入后刷新一次，补上子节点 ready 时尚未取得的共享事件。
	_show_status_tab()


func show_terminal() -> void:
	# 每次进入都回到 STATUS，便于玩家先阅读当前建筑判断。
	_show_status_tab()
	show()
	if status_tab_button != null:
		status_tab_button.grab_focus()


func _cache_terminal_nodes() -> void:
	title_label = _find_optional_node("TitleLabel") as Label
	access_status_label = _find_optional_node("AccessStatusLabel") as Label
	status_tab_button = _find_optional_node("StatusTabButton") as Button
	record_tab_button = _find_optional_node("RecordTabButton") as Button
	transcript_tab_button = _find_optional_node("TranscriptTabButton") as Button
	system_log_tab_button = _find_optional_node("SystemLogTabButton") as Button
	terminal_content_label = _find_optional_node("TerminalContentLabel") as Label
	terminal_hint_label = _find_optional_node("TerminalHintLabel") as Label
	return_button = _find_optional_node("ReturnButton") as Button


func _find_optional_node(node_name: String) -> Node:
	var found_node: Node = find_child(node_name, true, false)
	if found_node == null:
		push_warning("BuildingTerminalInterface: Missing optional node '%s'." % node_name)
	return found_node


func _connect_terminal_signals() -> void:
	# 四个占位页签只切换复核文本，不在本 Issue 中编辑或归档真实日志。
	_connect_button(status_tab_button, _show_status_tab)
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
	_set_button_text(status_tab_button, "STATUS")
	_set_button_text(record_tab_button, "RECORD")
	_set_button_text(transcript_tab_button, "TRANSCRIPT")
	_set_button_text(system_log_tab_button, "SYSTEM LOG")
	_set_button_text(return_button, "返回操作间")


func _show_status_tab() -> void:
	# STATUS 只显示最近一次对话选项携带的建筑提示，不计算真实稳定度或风险。
	var status_hint: String = "暂无前台通话。"
	if demo_flow_manager != null:
		status_hint = demo_flow_manager.get_current_building_status_hint()
	_set_content(
		STATUS_CONTENT + "\n\n当前复核提示：\n" + status_hint,
		"选择一个终端页签查看建筑记录。"
	)


func _show_record_tab() -> void:
	_set_content(RECORD_CONTENT, "乘客记录为当前复核会话的占位数据。")


func _show_transcript_tab() -> void:
	# TRANSCRIPT 只读取临时对话历史，不混入麦克风、摄像头或门控操作。
	var dialogue_history: Array[String] = _get_front_dialogue_history()
	if dialogue_history.is_empty():
		_set_content(EMPTY_TRANSCRIPT_CONTENT, "暂无可复核的通话转写。")
		return

	var transcript_lines := PackedStringArray(["对话转写", ""])
	for dialogue_line in dialogue_history:
		transcript_lines.append(dialogue_line)
	_set_content("\n".join(transcript_lines), "已读取 FRONT 临时对话缓存。")


func _show_system_log_tab() -> void:
	# SYSTEM LOG 只读取玩家操作，不显示操作员台词或乘客回应。
	var operation_history: Array[String] = _get_front_operation_history()
	if operation_history.is_empty():
		_set_content(EMPTY_SYSTEM_LOG_CONTENT, "显示建筑系统日志占位。")
		return

	var log_lines := PackedStringArray(["系统日志", ""])
	for operation_text in operation_history:
		log_lines.append("[SYS] %s" % operation_text)
	_set_content("\n".join(log_lines), "已读取 FRONT / RIGHT 临时操作缓存。")


func _get_front_dialogue_history() -> Array[String]:
	# dialogue_history 专供 LEFT 的 TRANSCRIPT，后续会由 PassengerCase 替换。
	if demo_flow_manager == null:
		push_warning("BuildingTerminalInterface: Cannot read dialogue without DemoFlowManager.")
		var empty_history: Array[String] = []
		return empty_history
	return demo_flow_manager.get_front_dialogue_history()


func _get_front_operation_history() -> Array[String]:
	# 当前缓存同时接收 FRONT 与 RIGHT 操作，只供 LEFT 的 SYSTEM LOG 读取。
	# 这是早期桥接，后续会由 PassengerCase 或统一事件系统替换。
	if demo_flow_manager == null:
		push_warning("BuildingTerminalInterface: Cannot read operations without DemoFlowManager.")
		var empty_history: Array[String] = []
		return empty_history
	return demo_flow_manager.get_front_operation_history()


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
