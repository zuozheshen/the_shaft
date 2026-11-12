class_name DocumentWindow
extends PanelContainer
## 窗口固定到一个已取得版本；移动、滚动与焦点均为本单 UI 状态。

signal closing
signal raised
signal newer_requested
signal geometry_changed
signal history_requested(ref: Dictionary)
signal focus_layout_changed
signal review_field_requested(ref: Dictionary)

var review_enabled := false
var statement_blocks: Array = []
var _quote_body: TextEdit
var _quote_join: Button
var _candidate: Dictionary = {}
var _selecting_quote := false
var _selection_generation := 0
var _review_buttons: Array[Button] = []
var document_ref: Dictionary = {}
var receipt: Dictionary = {}
var scroll: ScrollContainer
var title_label: Label
var version_label: Label
var update_button: Button
var detail_button: Button
var top_button: Button
var close_button: Button
var body: VBoxContainer
var metadata_label: Label
var _drag_mode: int = 0
var _drag_start: Vector2
var _start_rect: Rect2
var _details: bool = false
var history_button: Button
var history_list: VBoxContainer
var _history_refs: Array[Dictionary] = []
var _document_rendered: bool = false
var _field_labels: Dictionary = {}
var _located_field: Label
var _history_reading_position: int = 0

func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(200, 120)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#102c2b")
	style.border_color = Color("#63837a")
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 3)
	add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	title_label = Label.new()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.gui_input.connect(_title_input)
	header.add_child(title_label)
	top_button = _button(header, "置顶")
	top_button.pressed.connect(func() -> void: raised.emit())
	close_button = _button(header, "关闭")
	close_button.pressed.connect(func() -> void: closing.emit())
	version_label = Label.new()
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	actions.add_child(version_label)
	detail_button = _button(actions, "详情")
	detail_button.toggle_mode = true
	detail_button.toggled.connect(_show_details)
	history_button = _button(actions, "历史版本")
	history_button.toggle_mode = true
	history_button.visible = false
	history_button.toggled.connect(_show_history)
	update_button = _button(actions, "查看新版")
	update_button.pressed.connect(func() -> void: newer_requested.emit())
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.gui_input.connect(_body_input)
	layout.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	history_list = VBoxContainer.new()
	history_list.visible = false
	body.add_child(history_list)
	metadata_label = _text("")
	metadata_label.visible = false
	# 角柄只负责局部缩放，不使用原生 OS 窗口。
	var grip := Button.new()
	grip.text = "◢"
	grip.tooltip_text = "拖动调整窗口"
	grip.focus_mode = Control.FOCUS_NONE
	grip.custom_minimum_size = Vector2(22, 22)
	grip.size_flags_horizontal = Control.SIZE_SHRINK_END
	grip.size_flags_vertical = Control.SIZE_SHRINK_END
	grip.gui_input.connect(_grip_input)
	add_child(grip)
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			raised.emit())

func _button(parent: Node, text: String) -> Button:
	var result := Button.new()
	result.text = text
	parent.add_child(result)
	return result

func _text(text: String) -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_color", Color("#d4e1d7"))
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(label)
	return label

func show_document(value: Dictionary, latest: int) -> void:
	receipt = value.duplicate(true)
	var doc: Dictionary = receipt.document
	document_ref = {"document_id": doc.document_id, "version": doc.version}
	title_label.text = doc.title
	var source: Dictionary = doc.source
	version_label.text = "%s · v%d%s" % [{"passenger_upload":"乘客上传", "system_reference":"系统参考", "floor_archive":"右台档案", "personnel_record":"人员档案", "duty_record":"当班记录", "call_excerpt":"通话摘录"}.get(source.kind, source.kind), doc.version,
		" · 旧版 / 有更新" if latest > int(doc.version) else ""]
	update_button.visible = latest > int(doc.version)
	if update_button.visible and not statement_blocks.is_empty():
		cancel_statement_selection()
	metadata_label.text = "来源：%s\n原始位置：%s\n来源版本：%s\n原始更新：%s\n取得时间：%s" % [
		source.source_id, source.origin_ref, source.source_version,
		source.updated_at if not String(source.updated_at).is_empty() else "未知",
		Time.get_datetime_string_from_unix_time(int(receipt.acquired_at))]
	# 刷新版本提示不重建正文，避免无关资料更新打断阅读。
	if _document_rendered:
		return
	_document_rendered = true
	if not statement_blocks.is_empty():
		_render_statements(doc)
		return
	_text(doc.original_text)
	for field_id: String in doc.fields:
		var field: Dictionary = doc.fields[field_id]
		_field_labels[field_id] = _text(field.display_value)
		if review_enabled and field.has_value:
			_add_review_button(field_id, field)
		var detail := _text("字段：%s · %s\n%s" % [field_id, field.source.source_id, field.source_note])
		detail.set_meta("field_detail", true)
		detail.visible = _details

func _show_details(value: bool) -> void:
	_details = value
	metadata_label.visible = value
	for child in body.get_children():
		if child.has_meta("field_detail"):
			child.visible = value

func focus_controls() -> Array[Control]:
	var result: Array[Control] = [top_button, close_button, detail_button]
	if update_button.visible:
		result.append(update_button)
	if history_button.visible:
		result.append(history_button)
	if history_list.visible:
		for button in history_list.get_children():
			if button is Button and not button.disabled:
				result.append(button)
	result.append(scroll)
	if _quote_body != null:
		result.append(_quote_body)
		if _quote_join.visible:
			result.append(_quote_join)
	for button in _review_buttons:
		result.append(button)
	return result

func scroll_by(amount: int) -> void:
	scroll.scroll_vertical += amount

func _body_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_UP: scroll_by(-48)
		KEY_DOWN: scroll_by(48)
		KEY_PAGEUP: scroll_by(-int(scroll.size.y * 0.8))
		KEY_PAGEDOWN: scroll_by(int(scroll.size.y * 0.8))
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return
	accept_event() # 到达边缘也不把滚动传给其他窗口或背景。

func _title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(1)
		else:
			_drag_mode = 0
		accept_event()

func _grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(2)
		else:
			_drag_mode = 0
		accept_event()

func _begin_drag(mode: int) -> void:
	cancel_statement_selection()
	_drag_mode = mode
	_drag_start = get_global_mouse_position()
	_start_rect = Rect2(position, size)
	raised.emit()

func cancel_drag() -> void:
	_drag_mode = 0

func _input(event: InputEvent) -> void:
	if _drag_mode == 0:
		return
	if event is InputEventMouseButton and not event.pressed:
		_drag_mode = 0
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var change: Vector2 = event.position - _drag_start
		if _drag_mode == 1:
			position = _start_rect.position + change
		else:
			size = (_start_rect.size + change).max(custom_minimum_size)
		constrain()
		geometry_changed.emit()
		get_viewport().set_input_as_handled()

func constrain() -> void:
	var area := (get_parent() as Control).size
	if area.x <= 0 or area.y <= 0:
		return
	size = size.min(area)
	position = position.clamp(Vector2.ZERO, (area - size).max(Vector2.ZERO))

func set_history(refs: Array[Dictionary]) -> void:
	if refs == _history_refs:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var lost_focus := focused != null and (history_list.is_ancestor_of(focused) or focused == history_button)
	_history_refs = refs.duplicate(true)
	for child in history_list.get_children():
		history_list.remove_child(child)
		child.queue_free()
	history_button.visible = not refs.is_empty()
	history_button.text = "历史版本 (%d)" % refs.size()
	if refs.is_empty():
		history_button.set_pressed_no_signal(false)
		history_list.visible = false
	for ref: Dictionary in refs:
		var current: bool = ref == document_ref
		var button := _button(history_list, "v%d%s" % [ref.version, " / 当前阅读" if current else ""])
		button.disabled = current
		button.set_meta("document_ref", ref.duplicate())
		button.pressed.connect(func() -> void: history_requested.emit(ref.duplicate()))
	if lost_focus:
		if history_button.visible:
			history_button.grab_focus()
		else:
			detail_button.grab_focus()
	focus_layout_changed.emit()

func _show_history(value: bool) -> void:
	# 历史展开时滚到入口，收折后回到之前的正文位置，不丢阅读进度。
	var focused := get_viewport().gui_get_focus_owner()
	if not value and focused != null and history_list.is_ancestor_of(focused):
		history_button.grab_focus()
	if value and not history_list.visible:
		_history_reading_position = scroll.scroll_vertical
	history_list.visible = value and history_button.visible
	scroll.set_deferred("scroll_vertical", 0 if history_list.visible else _history_reading_position)
	focus_layout_changed.emit()

func get_reading_position() -> int:
	return _history_reading_position if history_list.visible else scroll.scroll_vertical

func restore_reading_position(value: int) -> void:
	_history_reading_position = value
	scroll.set_deferred("scroll_vertical", 0 if history_list.visible else value)


# 一个只读正文控件保留跨行选区，鼠标和手柄使用相同的字符范围。
func _render_statements(doc: Dictionary) -> void:
	_quote_body = TextEdit.new()
	_quote_body.text = doc.original_text
	_quote_body.editable = false
	_quote_body.caret_multiple = false
	_quote_body.caret_draw_when_editable_disabled = true
	_quote_body.context_menu_enabled = false
	_quote_body.drag_and_drop_selection_enabled = false
	_quote_body.deselect_on_focus_loss_enabled = false
	_quote_body.virtual_keyboard_enabled = false
	_quote_body.tab_input_mode = false
	_quote_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_quote_body.scroll_fit_content_height = true
	_quote_body.highlight_current_line = true
	var background := StyleBoxEmpty.new()
	_quote_body.add_theme_stylebox_override("normal", background)
	_quote_body.add_theme_stylebox_override("read_only", background)
	_quote_body.add_theme_color_override("font_readonly_color", Color("#d4e1d7"))
	_quote_body.add_theme_color_override("current_line_color", Color("#254239"))
	_quote_body.gui_input.connect(_quote_input)
	body.add_child(_quote_body)
	_quote_join = _button(scroll.get_parent(), "加入比对")
	_quote_join.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_quote_join.hide()
	_quote_join.pressed.connect(_join_statement)
	scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void:
		if _selecting_quote:
			cancel_statement_selection())
	resized.connect(func() -> void: cancel_statement_selection())
	get_window().focus_exited.connect(func() -> void: cancel_statement_selection())

func _quote_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.is_action("ui_accept"):
		confirm_statement(_quote_body)
		accept_event()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		cancel_statement_selection()
		_selecting_quote = true
		raised.emit()
	elif _selecting_quote:
		_selecting_quote = false
		var inside := Rect2(Vector2.ZERO, _quote_body.size).has_point(event.position) \
				and scroll.get_global_rect().has_point(_quote_body.get_global_transform() * event.position)
		_finish_quote_drag.call_deferred(_selection_generation, inside)

func _finish_quote_drag(generation: int, inside: bool) -> void:
	if generation != _selection_generation or not is_visible_in_tree():
		return
	if inside:
		_read_quote_selection()
	else:
		_quote_body.deselect()

func _read_quote_selection() -> bool:
	if update_button.visible or not _quote_body.has_selection():
		return false
	var quote := _quote_body.get_selected_text()
	if quote.strip_edges().is_empty():
		return false
	var from_line := _quote_body.get_selection_from_line()
	var start := _quote_body.get_selection_from_column()
	for line in from_line:
		start += _quote_body.get_line(line).length() + 1
	var end := start + quote.length()
	_candidate = document_ref.merged({"start": start, "end": end, "quote": quote})
	for block: Dictionary in statement_blocks:
		if start == block.start and end == block.end and quote == block.quote:
			var field: Dictionary = receipt.document.fields.get(block.field_id, {})
			if field.get("has_value", false):
				_candidate["field_id"] = block.field_id
			break
	_quote_join.show()
	focus_layout_changed.emit()
	return true

func confirm_statement(focused: Control) -> bool:
	if _quote_body == null or focused != _quote_body:
		return false
	# 键盘可先用 Shift 选字。手柄未选择时，确认当前段落。
	if not _quote_body.has_selection():
		var line := _quote_body.get_caret_line()
		_quote_body.select(line, 0, line, _quote_body.get_line(line).length())
	if _read_quote_selection():
		_quote_join.grab_focus()
	return true

func move_quote_focus(focused: Control, direction: int) -> bool:
	if _quote_body == null or focused != _quote_body:
		return false
	var line := _quote_body.get_caret_line() + direction
	if line < 0 or line >= _quote_body.get_line_count():
		return false
	cancel_statement_selection()
	_quote_body.set_caret_line(line)
	_quote_body.set_caret_column(0)
	_reveal_quote_line(line)
	return true

func _reveal_quote_line(line: int) -> void:
	var row := _quote_body.get_rect_at_line_column(line, 0)
	var y := (_quote_body.get_global_transform() * Vector2(row.position)).y - scroll.get_global_rect().position.y
	if y < 0:
		scroll_by(floori(y))
	elif y + row.size.y > scroll.size.y:
		scroll_by(ceili(y + row.size.y - scroll.size.y))

func _join_statement() -> void:
	# 确认时读取当前高亮，避免键盘调整后仍加入上一次范围。
	if _candidate.is_empty():
		return
	if not _read_quote_selection():
		cancel_statement_selection(true)
		return
	var ref := _candidate.duplicate()
	cancel_statement_selection(true)
	review_field_requested.emit(ref)

## 定位使用字段 ID，避免正文中有两个同值字段时跳错位置。
func locate_field(field_id: String) -> bool:
	var label := _field_labels.get(field_id) as Label
	if label == null:
		return false
	if is_instance_valid(_located_field):
		_located_field.add_theme_color_override("font_color", Color("#d4e1d7"))
	_located_field = label
	label.add_theme_color_override("font_color", Color("#fff2b7"))
	scroll.grab_focus()
	scroll.ensure_control_visible(label)
	return true


func locate_statement(start: int, end: int) -> void:
	if _quote_body == null:
		return
	cancel_statement_selection()
	var first := _quote_position(start)
	var last := _quote_position(end)
	_quote_body.set_caret_line(first.y)
	_quote_body.set_caret_column(first.x)
	_quote_body.select(first.y, first.x, last.y, last.x)
	_quote_body.grab_focus()
	_reveal_quote_line(first.y)

func _quote_position(offset: int) -> Vector2i:
	for line in _quote_body.get_line_count():
		var length := _quote_body.get_line(line).length()
		if offset <= length:
			return Vector2i(offset, line)
		offset -= length + 1
	return Vector2i.ZERO

func cancel_statement_drag() -> void:
	if _selecting_quote:
		_selecting_quote = false
		_selection_generation += 1
		_quote_body.deselect()

func cancel_statement_selection(restore_focus: bool = false) -> bool:
	if _quote_body == null:
		return false
	_selection_generation += 1
	var had_selection := _selecting_quote or _quote_body.has_selection() or _quote_join.visible
	_selecting_quote = false
	_candidate.clear()
	_quote_body.deselect()
	if _quote_join.visible:
		if restore_focus or _quote_join.has_focus():
			_quote_body.grab_focus()
		_quote_join.hide()
		focus_layout_changed.emit()
	return had_selection

func _add_review_button(field_id: String, field: Dictionary) -> void:
	var ref := document_ref.duplicate()
	ref["field_id"] = field_id
	var row := HBoxContainer.new()
	body.add_child(row)
	var button := _button(row, "加入比对")
	button.tooltip_text = field.display_value
	button.set_meta("review_ref", ref)
	button.pressed.connect(review_field_requested.emit.bind(ref))
	_review_buttons.append(button)
