extends Control
class_name BuildingTerminalInterface


signal return_requested
signal section_changed(section: int)
signal unread_state_changed(snapshot: Dictionary)


enum Section {
	SYSTEM_LOG,
	PASSENGER_RECORD,
	TRANSCRIPT,
}


const SECTION_SYSTEM_LOG: StringName = &"system_log"
const SECTION_PASSENGER_RECORD: StringName = &"passenger_record"
const SECTION_TRANSCRIPT: StringName = &"transcript"
const EMPTY_TRANSCRIPT_CONTENT: String = """对话记录

暂无通话转写。
请先在 FRONT 主仲裁台开启麦克风并选择对话。"""
const EMPTY_SYSTEM_LOG_CONTENT: String = "暂无系统通信记录。"


@export_range(24, 240, 8) var scroll_step: int = 96

# 场景结构已固定，直接引用节点，避免运行时按名称遍历整棵节点树。
@onready var title_label: Label = $TerminalLayout/TitleLabel
@onready var access_status_label: Label = $TerminalLayout/AccessStatusLabel
@onready var content_scroll_container: ScrollContainer = $TerminalLayout/ContentScrollContainer
@onready var terminal_content_label: Label = $TerminalLayout/ContentScrollContainer/TerminalContentPanel/TerminalContentMargin/TerminalContentLabel
@onready var terminal_hint_label: Label = $TerminalLayout/TerminalHintLabel

var demo_flow_manager: DemoFlowManager
var embedded_3d_mode: bool = false
var _current_section: int = Section.SYSTEM_LOG
var _is_actively_viewed: bool = false
var _system_log_unread: bool = false
var _passenger_record_unread: bool = false
var _transcript_unread: bool = false


func _ready() -> void:
	_apply_terminal_theme()
	_initialize_terminal_text()
	# RuntimeConnector3D 会在场景 ready 后注入唯一 Manager；注入前只显示静态空态，避免虚假缺失告警。
	_set_content(EMPTY_SYSTEM_LOG_CONTENT, "等待系统通信。")


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	if demo_flow_manager == flow_manager:
		return
	_disconnect_demo_flow_manager()
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		push_warning("BuildingTerminalInterface: DemoFlowManager is not connected.")
		return
	if not demo_flow_manager.left_terminal_section_updated.is_connected(
		_on_left_terminal_section_updated
	):
		demo_flow_manager.left_terminal_section_updated.connect(
			_on_left_terminal_section_updated
		)
	if not demo_flow_manager.left_terminal_session_reset.is_connected(
		_on_left_terminal_session_reset
	):
		demo_flow_manager.left_terminal_session_reset.connect(
			_on_left_terminal_session_reset
		)
	# 注入通常发生在首单启动之后；按真实当前派单补齐一次 presentation 状态。
	_on_left_terminal_session_reset(demo_flow_manager.has_active_dispatch())


func _disconnect_demo_flow_manager() -> void:
	if demo_flow_manager == null:
		return
	if demo_flow_manager.left_terminal_section_updated.is_connected(
		_on_left_terminal_section_updated
	):
		demo_flow_manager.left_terminal_section_updated.disconnect(
			_on_left_terminal_section_updated
		)
	if demo_flow_manager.left_terminal_session_reset.is_connected(
		_on_left_terminal_session_reset
	):
		demo_flow_manager.left_terminal_session_reset.disconnect(
			_on_left_terminal_session_reset
		)


func show_terminal() -> void:
	show_system_log()
	show()
	if not embedded_3d_mode:
		set_actively_viewed(true)


func set_embedded_3d_mode(is_enabled: bool) -> void:
	embedded_3d_mode = is_enabled
	if content_scroll_container != null:
		content_scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE \
				if is_enabled else Control.MOUSE_FILTER_STOP


func set_actively_viewed(is_viewed: bool) -> void:
	if _is_actively_viewed == is_viewed:
		return
	_is_actively_viewed = is_viewed
	if not _is_actively_viewed:
		return
	_render_current_section()
	_set_section_unread(_current_section, false)


func is_actively_viewed() -> bool:
	return _is_actively_viewed


func show_system_log() -> void:
	_select_section(Section.SYSTEM_LOG)


func show_passenger_record() -> void:
	_select_section(Section.PASSENGER_RECORD)


func show_transcript() -> void:
	_select_section(Section.TRANSCRIPT)


func get_current_section() -> int:
	return _current_section


func get_section_unread(section: int) -> bool:
	match section:
		Section.SYSTEM_LOG:
			return _system_log_unread
		Section.PASSENGER_RECORD:
			return _passenger_record_unread
		Section.TRANSCRIPT:
			return _transcript_unread
		_:
			return false


func get_unread_snapshot() -> Dictionary:
	return {
		SECTION_SYSTEM_LOG: _system_log_unread,
		SECTION_PASSENGER_RECORD: _passenger_record_unread,
		SECTION_TRANSCRIPT: _transcript_unread,
	}


func scroll_current_content(direction: int) -> void:
	if content_scroll_container == null or direction == 0:
		return
	var scroll_bar := content_scroll_container.get_v_scroll_bar()
	var maximum := maxf(0.0, scroll_bar.max_value - scroll_bar.page)
	content_scroll_container.scroll_vertical = int(clampf(
		float(content_scroll_container.scroll_vertical + direction * scroll_step),
		0.0,
		maximum
	))


func _select_section(section: int) -> void:
	if section < Section.SYSTEM_LOG or section > Section.TRANSCRIPT:
		return
	_current_section = section
	_render_current_section()
	_set_section_unread(_current_section, false)
	call_deferred("_reset_scroll_to_top")
	section_changed.emit(_current_section)


func _on_left_terminal_session_reset(has_active_dispatch: bool) -> void:
	_current_section = Section.SYSTEM_LOG
	_system_log_unread = has_active_dispatch and not _is_actively_viewed
	# FILE 在 V1 中只表示“新派单的当前乘客档案可查看”。
	_passenger_record_unread = has_active_dispatch
	_transcript_unread = false
	_render_current_section()
	call_deferred("_reset_scroll_to_top")
	section_changed.emit(_current_section)
	_emit_unread_state()


func _on_left_terminal_section_updated(section_id: StringName) -> void:
	var section := _section_from_id(section_id)
	if section < 0:
		return
	_set_section_unread(section, true)
	if _is_actively_viewed and section == _current_section:
		_render_current_section()
		_set_section_unread(section, false)


func _section_from_id(section_id: StringName) -> int:
	match section_id:
		SECTION_SYSTEM_LOG:
			return Section.SYSTEM_LOG
		SECTION_PASSENGER_RECORD:
			return Section.PASSENGER_RECORD
		SECTION_TRANSCRIPT:
			return Section.TRANSCRIPT
		_:
			return -1


func _set_section_unread(section: int, is_unread: bool) -> void:
	var changed := false
	match section:
		Section.SYSTEM_LOG:
			changed = _system_log_unread != is_unread
			_system_log_unread = is_unread
		Section.PASSENGER_RECORD:
			changed = _passenger_record_unread != is_unread
			_passenger_record_unread = is_unread
		Section.TRANSCRIPT:
			changed = _transcript_unread != is_unread
			_transcript_unread = is_unread
	if changed:
		_emit_unread_state()


func _emit_unread_state() -> void:
	unread_state_changed.emit(get_unread_snapshot())


func _initialize_terminal_text() -> void:
	_set_label_text(title_label, "SHAFT FACILITIES // ARCHIVE TERMINAL")
	_set_label_text(access_status_label, "> 建筑终端 L-612-A  //  OPERATOR ACCESS  //  LINK ACTIVE")


func _apply_terminal_theme() -> void:
	# 沿用右台深青屏面与浅色字体系；仍保留系统等宽字体和中文回退。
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
	terminal_theme.set_color("font_color", "Label", Color("edf4f1"))
	terminal_theme.set_color("font_shadow_color", "Label", Color(0.0, 0.04, 0.04, 0.85))
	terminal_theme.set_constant("shadow_offset_x", "Label", 1)
	terminal_theme.set_constant("shadow_offset_y", "Label", 1)
	terminal_theme.set_stylebox("panel", "PanelContainer", _create_terminal_style(
		Color("092321"), Color("607b75"), 1
	))
	theme = terminal_theme
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color("ffffff"))
	access_status_label.add_theme_font_size_override("font_size", 17)
	terminal_hint_label.add_theme_font_size_override("font_size", 16)
	terminal_hint_label.add_theme_color_override("font_color", Color("b8cbc5"))


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


func _render_current_section() -> void:
	match _current_section:
		Section.PASSENGER_RECORD:
			_render_record()
		Section.TRANSCRIPT:
			_render_transcript()
		_:
			_render_system_log()


# 保留旧私有入口，现有调用者仍会落到唯一栏目状态。
func _show_record_tab() -> void:
	show_passenger_record()


func _show_transcript_tab() -> void:
	show_transcript()


func _show_system_log_tab() -> void:
	show_system_log()


func _render_record() -> void:
	_set_content(_build_record_content(), "乘客记录来自当前复核案例。")


func _build_record_content() -> String:
	if demo_flow_manager == null:
		return "乘客档案\n\n数据源未连接：无法读取当前乘客记录。"
	if not demo_flow_manager.has_active_dispatch():
		return "乘客档案\n\n暂无当前乘客。"
	var archive_text: String = demo_flow_manager.get_passenger_archive_text()
	if archive_text.is_empty():
		return "乘客档案\n\n当前案例未提供乘客记录。"
	return "乘客档案\n\n%s" % archive_text.replace(
		"{dispatch}", demo_flow_manager.get_dispatch_text()
	)


func _render_transcript() -> void:
	var dialogue_history: Array[String] = _get_front_dialogue_history()
	if dialogue_history.is_empty():
		_set_content(EMPTY_TRANSCRIPT_CONTENT, "暂无可复核的通话转写。")
		return
	var transcript_lines := PackedStringArray(["对话记录", ""])
	for dialogue_line in dialogue_history:
		transcript_lines.append(dialogue_line)
	_set_content("\n".join(transcript_lines), "已读取 FRONT 临时对话缓存。")


func _render_system_log() -> void:
	var message_history: Array[String] = _get_system_message_history()
	if message_history.is_empty():
		_set_content(EMPTY_SYSTEM_LOG_CONTENT, "暂无需要复核的系统通信。")
		return
	var log_lines := PackedStringArray(["系统日志", ""])
	for message_text in message_history:
		log_lines.append(message_text)
	_set_content("\n\n".join(log_lines), "已读取本轮系统通信历史。")


func _get_front_dialogue_history() -> Array[String]:
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


func _reset_scroll_to_top() -> void:
	if content_scroll_container != null:
		content_scroll_container.scroll_vertical = 0


func _set_label_text(label: Label, new_text: String) -> void:
	if label != null:
		label.text = new_text
