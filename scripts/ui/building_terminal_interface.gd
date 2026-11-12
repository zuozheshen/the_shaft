extends Control
class_name BuildingTerminalInterface


signal section_changed(section: int)
signal unread_state_changed(snapshot: Dictionary)
signal retrieval_available_changed(available: bool)
signal archive_document_retrieved(session: int, ref: Dictionary)


enum Section { SYSTEM_LOG, PASSENGER_RECORD }

const STYLE := preload("res://scripts/ui/terminal_ui_style.gd")
const SECTION_SYSTEM_LOG: StringName = &"system_log"
const SECTION_PASSENGER_RECORD: StringName = &"passenger_record"
const EMPTY_SYSTEM_LOG_CONTENT: String = "暂无系统通信记录。"

@export_range(24, 240, 8) var scroll_step: int = 96

@onready var title_label: Label = $TerminalLayout/TitleLabel
@onready var _section_rule: HSeparator = $TerminalLayout/SectionRule
@onready var content_scroll_container: ScrollContainer = $TerminalLayout/ContentScrollContainer
@onready var _reading: VBoxContainer = $TerminalLayout/ContentScrollContainer/TerminalContentPanel/TerminalContentMargin/Reading
@onready var document_heading: Label = _reading.get_node("DocumentHeading")
@onready var record_meta: Label = _reading.get_node("RecordMeta")
@onready var terminal_content_label: Label = _reading.get_node("TerminalContentLabel")
@onready var _log_rows: VBoxContainer = _reading.get_node("LogRows")
@onready var _record_fields: VBoxContainer = _reading.get_node("RecordFields")
@onready var terminal_hint_label: Label = $TerminalLayout/TerminalHintLabel

var demo_flow_manager: DemoFlowManager
var embedded_3d_mode: bool = false
var _current_section: int = Section.SYSTEM_LOG
var _is_actively_viewed: bool = false
var _system_log_unread: bool = false
var _archive_available_hint: bool = false
var _session: int = 0

# 左台只保留本单显示快照及阅读位置。玩家取得的资料由运行层持有。
var _documents: Array[Dictionary] = []
var _document_index: int = 0
var _read_documents: Dictionary = {}
var _stale_documents: Dictionary = {}
var _event_ids: Dictionary = {}
var _next_event: int = 0
var _reading_positions: Dictionary = {}
var _scroll_revision: int = 0
var _scroll_pending: bool = false


func _ready() -> void:
	_apply_terminal_theme()
	_render_system_log()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	if demo_flow_manager == flow_manager:
		return
	if is_instance_valid(demo_flow_manager):
		demo_flow_manager.left_terminal_section_updated.disconnect(_on_left_terminal_section_updated)
		demo_flow_manager.document_session_changed.disconnect(_reset_session)
	demo_flow_manager = flow_manager
	if is_instance_valid(demo_flow_manager):
		demo_flow_manager.left_terminal_section_updated.connect(_on_left_terminal_section_updated)
		demo_flow_manager.document_session_changed.connect(_reset_session)
	_reset_session(demo_flow_manager.get_document_session_id() if demo_flow_manager != null else 0)


func set_embedded_3d_mode(is_enabled: bool) -> void:
	embedded_3d_mode = is_enabled
	if content_scroll_container != null:
		content_scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE \
				if is_enabled else Control.MOUSE_FILTER_STOP


func set_actively_viewed(is_viewed: bool) -> void:
	if _is_actively_viewed == is_viewed:
		return
	_is_actively_viewed = is_viewed
	if is_viewed and _current_section == Section.SYSTEM_LOG:
		_render_system_log()
	_mark_current_read()


func is_actively_viewed() -> bool:
	return _is_actively_viewed


func show_system_log() -> void:
	if _current_section == Section.SYSTEM_LOG:
		return
	_save_reading_position()
	_current_section = Section.SYSTEM_LOG
	_render_system_log()
	_restore_scroll_after_layout()
	section_changed.emit(_current_section)
	_mark_current_read()


func show_passenger_record() -> void:
	_save_reading_position()
	if _current_section != Section.PASSENGER_RECORD:
		_refresh_archive()
		_current_section = Section.PASSENGER_RECORD
		section_changed.emit(_current_section)
	elif _documents.size() > 1:
		_document_index = (_document_index + 1) % _documents.size()
	else:
		return
	_render_record()
	_restore_scroll_after_layout()
	_mark_current_read()


func _refresh_archive() -> void:
	var previous := _current_document()
	_documents = demo_flow_manager.query_current_passenger_archive(_session) if demo_flow_manager != null else []
	_archive_available_hint = false
	_document_index = 0
	_stale_documents.clear()
	_event_ids.clear()
	for index: int in _documents.size():
		if _documents[index].document_id == previous.get("document_id", ""):
			_document_index = index
			break


func retrieve_current_document() -> void:
	if not _is_actively_viewed:
		return
	if not can_retrieve_current_document():
		if _current_section == Section.SYSTEM_LOG:
			_show_feedback("请先查看乘客档案。")
		return
	var document := _current_document()
	var key := _document_key(document)
	if not _event_ids.has(key):
		# 同轮查询可逐份调阅，每份文档的事件 ID 和载荷一一对应。
		_next_event += 1
		_event_ids[key] = StringName("left:%d:%d" % [_session, _next_event])
	var session := _session
	var result := demo_flow_manager.retrieve_passenger_archive_document(session, _event_ids[key], document)
	if session != _session:
		return
	if result.succeeded:
		archive_document_retrieved.emit(session, {"document_id": document.document_id, "version": document.version})
	elif result.code == &"LEFT_RECORD_CHANGED" or result.code == &"VERSION_CONFLICT" or result.code == &"STALE_VERSION":
		_stale_documents[key] = true
		_show_feedback("资料已更新，请返回系统日志后重新打开乘客档案。")
		_publish_read_state()
	else:
		_show_feedback("当前无法调阅此文档。")


func can_retrieve_current_document() -> bool:
	return _is_actively_viewed and _current_section == Section.PASSENGER_RECORD \
			and _session > 0 and not _documents.is_empty() \
			and not _stale_documents.has(_document_key(_current_document()))


func get_current_section() -> int:
	return _current_section


func get_section_unread(section: int) -> bool:
	if section == Section.SYSTEM_LOG:
		return _system_log_unread
	if section == Section.PASSENGER_RECORD:
		if _archive_available_hint:
			return true
		for document: Dictionary in _documents:
			if not _read_documents.has(_document_key(document)):
				return true
	return false


func get_unread_snapshot() -> Dictionary:
	return {
		SECTION_SYSTEM_LOG: _system_log_unread,
		SECTION_PASSENGER_RECORD: get_section_unread(Section.PASSENGER_RECORD),
	}


func scroll_current_content(direction: int) -> void:
	if content_scroll_container == null or direction == 0 or _scroll_pending:
		return
	var scroll_bar := content_scroll_container.get_v_scroll_bar()
	var maximum := maxf(0.0, scroll_bar.max_value - scroll_bar.page)
	content_scroll_container.scroll_vertical = int(clampf(
		float(content_scroll_container.scroll_vertical + direction * scroll_step), 0.0, maximum))


func _reset_session(session: int) -> void:
	_session = session
	_current_section = Section.SYSTEM_LOG
	_system_log_unread = session > 0 and not _is_actively_viewed
	_archive_available_hint = session > 0 and demo_flow_manager.get_active_passenger() != null
	_documents.clear()
	_document_index = 0
	_read_documents.clear()
	_stale_documents.clear()
	_event_ids.clear()
	_next_event = 0
	_reading_positions.clear()
	_render_system_log()
	_restore_scroll_after_layout()
	section_changed.emit(_current_section)
	_publish_read_state()


func _on_left_terminal_section_updated(section_id: StringName) -> void:
	if section_id != SECTION_SYSTEM_LOG:
		return
	_system_log_unread = true
	if _is_actively_viewed and _current_section == Section.SYSTEM_LOG:
		_render_system_log()
	_mark_current_read()


func _mark_current_read() -> void:
	if _is_actively_viewed:
		if _current_section == Section.SYSTEM_LOG:
			_system_log_unread = false
		elif not _documents.is_empty():
			_read_documents[_document_key(_current_document())] = true
	_publish_read_state()


func _publish_read_state() -> void:
	unread_state_changed.emit(get_unread_snapshot())
	retrieval_available_changed.emit(can_retrieve_current_document())


func _current_document() -> Dictionary:
	return {} if _documents.is_empty() else _documents[_document_index]


func _document_key(document: Dictionary) -> String:
	return "%s@%d" % [document.document_id, document.version]


func _reading_key() -> String:
	return _document_key(_current_document()) if _current_section == Section.PASSENGER_RECORD \
			and not _documents.is_empty() else String(SECTION_SYSTEM_LOG)


func _save_reading_position() -> void:
	if not _scroll_pending:
		_reading_positions[_reading_key()] = content_scroll_container.scroll_vertical


func _restore_scroll_after_layout() -> void:
	_scroll_revision += 1
	var revision := _scroll_revision
	var saved: int = _reading_positions.get(_reading_key(), 0)
	_scroll_pending = true
	# 等换行后的正文和滚动范围就绪，快速翻页时只恢复最后一页。
	await get_tree().process_frame
	await get_tree().process_frame
	if revision == _scroll_revision:
		content_scroll_container.scroll_vertical = saved
		_scroll_pending = false


func _apply_terminal_theme() -> void:
	theme = STYLE.make_theme(23)
	title_label.add_theme_font_size_override("font_size", 23)
	document_heading.add_theme_font_size_override("font_size", 27)
	record_meta.add_theme_font_size_override("font_size", 19)
	record_meta.add_theme_color_override("font_color", STYLE.MUTED)
	terminal_hint_label.add_theme_font_size_override("font_size", 20)
	terminal_hint_label.add_theme_color_override("font_color", STYLE.AMBER)


func _render_record() -> void:
	title_label.hide()
	_section_rule.hide()
	_log_rows.hide()
	_clear_rows(_record_fields)
	terminal_hint_label.hide()
	document_heading.visible = not _documents.is_empty()
	record_meta.visible = document_heading.visible
	if _documents.is_empty():
		terminal_content_label.text = "暂无当前乘客。" if _session <= 0 else "暂无可用乘客档案。"
		return
	var document := _current_document()
	document_heading.text = "%s   %d / %d" % [document.title, _document_index + 1, _documents.size()]
	var source: Dictionary = document.source
	var metadata := PackedStringArray()
	if not String(document.owner_id).is_empty():
		metadata.append("人员编号 %s" % document.owner_id)
	metadata.append("%s · v%d" % [source.source_id, document.version])
	if not String(source.updated_at).is_empty():
		metadata.append(source.updated_at)
	record_meta.text = "   ｜   ".join(metadata)
	var original_text: String = document.original_text
	if String(document.document_id).begins_with("registry/passenger/"):
		# 旧身份档案只在左台展开；取得记录保留原文。
		original_text = original_text.replace("{dispatch}", demo_flow_manager.get_dispatch_text())
	terminal_content_label.text = original_text
	for field: Dictionary in document.fields.values():
		if field.has_value:
			_record_fields.add_child(HSeparator.new())
			_record_fields.add_child(_reading_label(field.display_value))
	if _stale_documents.has(_document_key(document)):
		_show_feedback("资料已更新，请返回系统日志后重新打开乘客档案。")


func _render_system_log() -> void:
	title_label.show()
	_section_rule.show()
	document_heading.hide()
	record_meta.hide()
	terminal_hint_label.hide()
	_clear_rows(_record_fields)
	_clear_rows(_log_rows)
	_log_rows.show()
	var history: Array[String] = []
	if demo_flow_manager != null:
		history = demo_flow_manager.get_system_message_history()
	terminal_content_label.text = EMPTY_SYSTEM_LOG_CONTENT if history.is_empty() else ""
	for message in history:
		var record := PanelContainer.new()
		var line := STYLE.box(STYLE.DESK, STYLE.EDGE, 0, 16, 8)
		line.border_width_left = 3
		record.add_theme_stylebox_override("panel", line)
		record.add_child(_reading_label(message))
		_log_rows.add_child(record)


func _reading_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_rows(rows: VBoxContainer) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()


func _show_feedback(text: String) -> void:
	terminal_hint_label.text = text
	terminal_hint_label.show()
