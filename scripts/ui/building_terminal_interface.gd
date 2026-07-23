extends Control
class_name BuildingTerminalInterface


signal return_requested


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
var embedded_3d_mode: bool = false


func _ready() -> void:
	_apply_terminal_theme()
	_connect_terminal_signals()
	_initialize_terminal_text()
	_set_content(EMPTY_SYSTEM_LOG_CONTENT, "等待系统通信。")


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	if demo_flow_manager == flow_manager:
		return
	_disconnect_demo_flow_manager()
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		push_warning("BuildingTerminalInterface: DemoFlowManager is not connected.")
		return
	if not demo_flow_manager.dispatch_started.is_connected(_on_dispatch_started):
		demo_flow_manager.dispatch_started.connect(_on_dispatch_started)
	if not demo_flow_manager.shift_completed.is_connected(_on_shift_completed):
		demo_flow_manager.shift_completed.connect(_on_shift_completed)
	# 父节点完成依赖注入后刷新一次，补上子节点 ready 时尚未取得的共享事件。
	_show_system_log_tab()


func _disconnect_demo_flow_manager() -> void:
	if demo_flow_manager == null:
		return
	if demo_flow_manager.dispatch_started.is_connected(_on_dispatch_started):
		demo_flow_manager.dispatch_started.disconnect(_on_dispatch_started)
	if demo_flow_manager.shift_completed.is_connected(_on_shift_completed):
		demo_flow_manager.shift_completed.disconnect(_on_shift_completed)


func _on_dispatch_started(_dispatch_id: StringName) -> void:
	_show_system_log_tab()


func _on_shift_completed() -> void:
	_show_system_log_tab()


func show_terminal() -> void:
	# 每次进入默认显示系统通信历史，便于复核本轮判断的变化。
	_show_system_log_tab()
	show()
	if system_log_tab_button != null:
		system_log_tab_button.grab_focus()


# 旧返回按钮仅在 2D 舱体中使用；3D 实例通过 Q / E 直接切换朝向。
func set_embedded_3d_mode(is_enabled: bool) -> void:
	embedded_3d_mode = is_enabled
	if return_button != null:
		return_button.visible = not is_enabled
		return_button.disabled = is_enabled
		if is_enabled:
			return_button.release_focus()


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
	_set_label_text(title_label, "SHAFT FACILITIES // ARCHIVE TERMINAL")
	_set_label_text(access_status_label, "> 建筑终端 L-612-A  //  OPERATOR ACCESS  //  LINK ACTIVE")
	_set_button_text(record_tab_button, "[ 乘客档案 ]")
	_set_button_text(transcript_tab_button, "[ 对话记录 ]")
	_set_button_text(system_log_tab_button, "[ 系统日志 ]")
	_set_button_text(return_button, "返回操作间")


func _apply_terminal_theme() -> void:
	# 使用系统等宽字体和高对比绿色，保持中文可回退显示并适配 1152×648 屏幕。
	var terminal_font := SystemFont.new()
	terminal_font.font_names = PackedStringArray([
		"Consolas",
		"Cascadia Mono",
		"Noto Sans Mono CJK SC",
		"Microsoft YaHei UI",
	])
	var terminal_theme := Theme.new()
	terminal_theme.default_font = terminal_font
	terminal_theme.default_font_size = 19
	terminal_theme.set_color("font_color", "Label", Color("78f58f"))
	terminal_theme.set_color("font_shadow_color", "Label", Color(0.05, 0.3, 0.08, 0.8))
	terminal_theme.set_constant("shadow_offset_x", "Label", 1)
	terminal_theme.set_constant("shadow_offset_y", "Label", 1)
	terminal_theme.set_color("font_color", "Button", Color("8cff9d"))
	terminal_theme.set_color("font_hover_color", "Button", Color("d0ffd5"))
	terminal_theme.set_color("font_pressed_color", "Button", Color("07140a"))
	terminal_theme.set_color("font_focus_color", "Button", Color("d0ffd5"))
	terminal_theme.set_font_size("font_size", "Button", 20)

	var normal_style := _create_terminal_style(Color("07140a"), Color("3d9b52"), 1)
	var hover_style := _create_terminal_style(Color("102819"), Color("8cff9d"), 2)
	var pressed_style := _create_terminal_style(Color("78f58f"), Color("b7ffc1"), 2)
	terminal_theme.set_stylebox("normal", "Button", normal_style)
	terminal_theme.set_stylebox("hover", "Button", hover_style)
	terminal_theme.set_stylebox("pressed", "Button", pressed_style)
	terminal_theme.set_stylebox("focus", "Button", hover_style)
	terminal_theme.set_stylebox(
		"panel",
		"PanelContainer",
		_create_terminal_style(Color("050d07"), Color("3d9b52"), 1)
	)
	theme = terminal_theme

	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color("b7ffc1"))
	access_status_label.add_theme_font_size_override("font_size", 17)
	terminal_hint_label.add_theme_font_size_override("font_size", 16)
	terminal_hint_label.add_theme_color_override("font_color", Color("4fbd65"))


func _create_terminal_style(
		background_color: Color,
		border_color: Color,
		border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	return style


func _show_record_tab() -> void:
	_set_content(_build_record_content(), "乘客记录来自当前复核案例。")


func _build_record_content() -> String:
	# RECORD 读取乘客永久档案；当前派单号只在显示时替换，不改写资源。
	if demo_flow_manager == null:
		return "乘客档案\n\n数据源未连接：无法读取当前乘客记录。"
	if not demo_flow_manager.has_active_dispatch():
		return "乘客档案\n\n暂无当前乘客。"

	var archive_text: String = demo_flow_manager.get_passenger_archive_text()
	if archive_text.is_empty():
		return "乘客档案\n\n当前案例未提供乘客记录。"

	return "乘客档案\n\n%s" % archive_text.replace(
		"{dispatch}",
		demo_flow_manager.get_dispatch_text()
	)


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


func _get_front_dialogue_history() -> Array[String]:
	# dialogue_history 专供 LEFT 的 TRANSCRIPT，后续由 UIHistoryState 管理。
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
	if embedded_3d_mode:
		return
	return_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or embedded_3d_mode:
		return
	if event.is_action_pressed("ui_cancel") or _is_key_pressed(event, KEY_S):
		_request_return()
		get_viewport().set_input_as_handled()


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)
