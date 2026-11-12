class_name VerificationWorkspace
extends VBoxContainer
## 只缓存引用和阅读布局；资料真值来自受限端口和已有提交事件。

const STYLE := preload("res://scripts/ui/terminal_ui_style.gd")
const CATEGORY_MARKS: Array[String] = ["▤", "≡", "▣", "▦", "❞"]
const WINDOW := preload("res://scenes/ui/document_window.tscn")
const CATEGORIES: Array[String] = ["乘客材料", "规程与样板", "人员记录", "楼层档案", "陈述摘录"]
const CATEGORY_ROUTES: Array[String] = ["passenger", "", "left", "right", "main"]
const REFERENCE_CATEGORY := 1

var port: Dictionary = {}
# 仅由三文件测试预览注入，按已取得的文件版本读取陈述映射。
var statement_documents: Dictionary = {}
var session_id: int = 0
var windows: Dictionary = {}
var saved_views: Dictionary = {}
var category: int = 0
var catalog: VBoxContainer
var catalog_scroll: ScrollContainer
var desk: Control
var arrange_button: Button
var directory_button: Button
var category_buttons: Array[Button] = []
var _catalog_lists: Array[VBoxContainer] = []
var _latest: Dictionary = {}
var _history: Dictionary = {}
var _active_key: String = ""
var _arranged: bool = false
var _focus_queued: bool = false
var _review_panel: VBoxContainer
var _evidence_buttons: Array[Button] = []
var _clear_buttons: Array[Button] = []
var _review_buttons: Array[Button] = []
var _review_feedback: Label
var _challenge: Button
var _delivery_feedback: Label
var _slots: Array[Dictionary] = [{}, {}]
var _review_operation := 0
var _reading_enabled := false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = STYLE.make_theme(22)
	add_theme_constant_override("separation", 6)
	directory_button = Button.new()
	directory_button.text = "目录  ▾"
	directory_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	directory_button.tooltip_text = "展开或收起目录"
	directory_button.toggle_mode = true
	directory_button.button_pressed = true
	directory_button.toggled.connect(_set_directory_visible)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	var sidebar := VBoxContainer.new()
	row.add_child(sidebar)
	sidebar.add_child(directory_button)
	# 即使目录折叠，留出的纵向空间也把整理固定在侧栏底部。
	var directory_space := MarginContainer.new()
	directory_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(directory_space)
	catalog_scroll = ScrollContainer.new()
	catalog_scroll.custom_minimum_size.x = 244
	catalog_scroll.add_theme_stylebox_override("panel", STYLE.box(STYLE.SURFACE, STYLE.EDGE, 1, 6, 6))
	catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	directory_space.add_child(catalog_scroll)
	arrange_button = Button.new()
	arrange_button.text = "整理"
	arrange_button.pressed.connect(arrange_windows)
	sidebar.add_child(arrange_button)
	var directory := VBoxContainer.new()
	directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_scroll.add_child(directory)
	directory.add_theme_constant_override("separation", 5)
	for index in CATEGORIES.size():
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = index == category
		button.text = _category_title(index, button.button_pressed)
		button.pressed.connect(_toggle_category.bind(index))
		button.focus_entered.connect(_reveal_directory_focus.call_deferred)
		directory.add_child(button)
		category_buttons.append(button)
		var files := VBoxContainer.new()
		files.add_theme_constant_override("separation", 1)
		files.visible = button.button_pressed
		directory.add_child(files)
		_catalog_lists.append(files)
	catalog = _catalog_lists[category]
	var work_surface := Panel.new()
	work_surface.add_theme_stylebox_override("panel", STYLE.box(STYLE.DESK, STYLE.EDGE, 1, 0, 0))
	desk = work_surface
	desk.name = "WindowDesk"
	desk.clip_contents = true
	desk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(desk)
	desk.resized.connect(_fit_windows)
	_create_review_panel()
	get_window().size_changed.connect(_update_font)
	_update_font()
	refresh()

func bind_port(value: Dictionary) -> void:
	port = value.duplicate()
	reset_session(int(port.get_session_id.call()))

func reset_session(value: int) -> void:
	if value == session_id:
		refresh()
		return
	for window in windows.values():
		window.free()
	windows.clear()
	saved_views.clear()
	_slots = [{}, {}]
	_review_operation = 0
	_review_feedback.text = ""
	_delivery_feedback.hide()
	_latest.clear()
	_history.clear()
	_active_key = ""
	session_id = value
	refresh()

func _key(ref: Dictionary) -> String:
	return "%s@%d" % [ref.document_id, ref.version]

func refresh(changed_session: int = -1) -> void:
	if not is_node_ready() or (changed_session >= 0 and changed_session != session_id):
		return
	_latest.clear()
	_history.clear()
	var events: Array = []
	if session_id > 0 and not port.is_empty():
		for item: Dictionary in port.get_acquired_documents.call(session_id):
			_latest[item.document.document_id] = item
		events = port.get_document_events.call(session_id)
		for event: Dictionary in events:
			for ref: Dictionary in event.document_refs:
				# 历史来源仍是业务事件；该索引可随时重建，不保存另一份版本正文。
				var snapshot: Dictionary = port.get_acquired_document.call(session_id, ref)
				if not snapshot.is_empty():
					_history[_key(ref)] = ref.duplicate()
	for window in windows.values():
		var id: String = window.document_ref.document_id
		if _latest.has(id):
			window.show_document(window.receipt, int(_latest[id].document.version))
			window.set_history(_older_refs(id))
	_render_catalog()
	refresh_review()
	_queue_focus()

func _set_directory_visible(value: bool) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if not value and focused != null and catalog_scroll.is_ancestor_of(focused):
		directory_button.grab_focus()
	catalog_scroll.visible = value
	directory_button.text = "目录  ▾" if value else "目录  ▸"
	directory_button.set_pressed_no_signal(value)
	_queue_focus()
	_fit_windows.call_deferred()


func _category_title(index: int, expanded: bool) -> String:
	return "%s  %s  %s" % ["▾" if expanded else "▸", CATEGORY_MARKS[index], CATEGORIES[index]]


func _toggle_category(index: int) -> void:
	var button := category_buttons[index]
	var files := _catalog_lists[index]
	var focused := get_viewport().gui_get_focus_owner()
	if not button.button_pressed and focused != null and files.is_ancestor_of(focused):
		button.grab_focus()
	category = index
	catalog = files
	files.visible = button.button_pressed
	button.text = _category_title(index, files.visible)
	_render_catalog()
	_queue_focus()


func _select_category(index: int) -> void:
	category_buttons[index].set_pressed_no_signal(true)
	_set_directory_visible(true)
	_toggle_category(index)


func _catalog_button(files: VBoxContainer, text: String, action: Callable, ref: Dictionary) -> void:
	var button := Button.new()
	button.text = "    ▫  " + text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	button.set_meta("document_ref", ref.duplicate())
	_style_catalog_entry(button)
	button.focus_entered.connect(_reveal_directory_focus.call_deferred)
	button.pressed.connect(action)
	files.add_child(button)

func _style_catalog_entry(button: Button) -> void:
	var ref: Dictionary = button.get_meta("document_ref", {})
	var selected := not ref.is_empty() and _key(ref) == _active_key
	button.add_theme_stylebox_override("normal", STYLE.box(STYLE.ACTIVE if selected else STYLE.SURFACE,
			STYLE.EDGE, 0, 8, 3))
	button.add_theme_color_override("font_color", STYLE.INK if selected else STYLE.AMBER)
	button.add_theme_color_override("font_focus_color", STYLE.INK if selected else STYLE.AMBER)


func _reveal_directory_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and catalog_scroll.visible and catalog_scroll.is_ancestor_of(focused):
		catalog_scroll.ensure_control_visible(focused)


func _render_catalog() -> void:
	# 刷新只重建展开的文件行，按分类和精确版本恢复原焦点。
	var focused := get_viewport().gui_get_focus_owner()
	var focused_index := -1
	var focused_ref: Dictionary = {}
	if focused != null and catalog_scroll.is_ancestor_of(focused):
		focused_index = _catalog_lists.find(focused.get_parent())
		focused_ref = focused.get_meta("document_ref", {})
	var old_scroll := catalog_scroll.scroll_vertical
	for index in _catalog_lists.size():
		var files := _catalog_lists[index]
		for child in files.get_children():
			files.remove_child(child)
			child.queue_free()
		if files.visible:
			_render_category(files, index)
	catalog_scroll.set_deferred("scroll_vertical", old_scroll)
	if focused_index >= 0 and not focused_ref.is_empty() and catalog_scroll.visible:
		for entry in _catalog_lists[focused_index].get_children():
			if entry.get_meta("document_ref", {}) == focused_ref:
				entry.grab_focus()
				return
		category_buttons[focused_index].grab_focus()


func _render_category(files: VBoxContainer, index: int) -> void:
	if index == REFERENCE_CATEGORY:
		if session_id > 0 and not port.is_empty():
			var references: Dictionary = {}
			for ref: Dictionary in port.get_system_references.call(session_id):
				if not references.has(ref.document_id) or int(ref.version) > int(references[ref.document_id].version):
					references[ref.document_id] = ref
			for ref: Dictionary in references.values():
				_catalog_button(files, ref.title, open_reference.bind(ref),
						{"document_id": ref.document_id, "version": ref.version})
	else:
		for item: Dictionary in _latest.values():
			# 字段的引述出处不改变取得渠道或权限。
			if item.route == CATEGORY_ROUTES[index]:
				var ref := {"document_id": item.document.document_id, "version": item.document.version}
				_catalog_button(files, "%s · v%d" % [item.document.title, ref.version], open_document.bind(ref), ref)
	if files.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "      暂无资料"
		empty.add_theme_color_override("font_color", STYLE.MUTED)
		files.add_child(empty)


func open_reference(ref: Dictionary) -> void:
	if session_id <= 0:
		return
	port.open_system_reference.call(session_id, ref)
	refresh()
	open_document(ref)

func open_retrieved_document(ref: Dictionary) -> void:
	if session_id <= 0 or port.is_empty():
		return
	var receipt: Dictionary = port.get_acquired_document.call(session_id, ref)
	var route: String = receipt.get("route", "")
	if route in ["left", "right"]:
		_select_category(CATEGORY_ROUTES.find(route))
	open_document(ref)


func open_document(ref: Dictionary) -> void:
	if session_id <= 0 or port.is_empty():
		return
	var snapshot: Dictionary = port.get_acquired_document.call(session_id, ref)
	if snapshot.is_empty():
		_review_feedback.text = "该版本已失效，请重新调阅"
		return
	var key := _key(ref)
	if windows.has(key):
		raise_window(key)
		return
	var window := WINDOW.instantiate() as DocumentWindow
	desk.add_child(window)
	windows[key] = window
	window.closing.connect(close_window.bind(key))
	window.raised.connect(raise_window.bind(key, false))
	window.newer_requested.connect(_open_latest.bind(String(ref.document_id)))
	window.history_requested.connect(open_document)
	window.focus_layout_changed.connect(_queue_focus)
	window.geometry_changed.connect(func() -> void: _arranged = false)
	window.review_enabled = _can_review()
	window.statement_blocks = statement_documents.get(key, [])
	if not window.statement_blocks.is_empty():
		window.review_field_requested.connect(_add_statement.bind(key, session_id))
	else:
		window.review_field_requested.connect(_add_review_field)
	window.show_document(snapshot, int(_latest.get(ref.document_id, snapshot).document.version))
	window.set_history(_older_refs(String(ref.document_id)))
	_update_font()
	if saved_views.has(key):
		var saved: Dictionary = saved_views[key]
		window.position = saved.position
		window.size = saved.size
		window.detail_button.button_pressed = saved.details
		if window.history_button.visible:
			window.history_button.button_pressed = saved.get("history_open", false)
		window.restore_reading_position(saved.scroll)
	else:
		window.size = (desk.size * Vector2(0.58, 0.74)).max(window.custom_minimum_size).min(desk.size)
		window.position = Vector2(16, 12) + Vector2(46, 42) * ((windows.size() - 1) % 4)
	window.constrain()
	_arranged = false
	raise_window(key)
	_render_catalog()
	refresh_review()
	_queue_focus()

func _open_latest(id: String) -> void:
	if _latest.has(id):
		open_document({"document_id": id, "version": _latest[id].document.version})

func raise_window(key: String, focus_body: bool = true) -> void:
	if not windows.has(key):
		return
	var previous: String = _active_key
	_active_key = key
	if previous != key and windows.has(previous):
		windows[previous].cancel_statement_selection()
		windows[previous].set_active(false)
	var window: DocumentWindow = windows[key]
	desk.move_child(window, desk.get_child_count() - 1)
	window.set_active(true)
	for files in _catalog_lists:
		for entry in files.get_children():
			if entry is Button:
				_style_catalog_entry(entry)
	if focus_body:
		window.scroll.grab_focus()

func close_window(key: String) -> void:
	if not windows.has(key):
		return
	var window: DocumentWindow = windows[key]
	saved_views[key] = {"position": window.position, "size": window.size,
		"scroll": window.get_reading_position(), "details": window.detail_button.button_pressed,
		"history_open": window.history_button.button_pressed}
	var focused := get_viewport().gui_get_focus_owner()
	var lost_focus := focused != null and window.is_ancestor_of(focused)
	windows.erase(key)
	window.hide()
	desk.remove_child(window)
	window.queue_free()
	if _active_key == key:
		var top := desk.get_child(desk.get_child_count() - 1) as DocumentWindow if not windows.is_empty() else null
		_active_key = _key(top.document_ref) if top != null else ""
		if top != null:
			top.set_active(true)
	if lost_focus:
		if windows.has(_active_key):
			raise_window(_active_key)
		elif catalog_scroll.visible:
			category_buttons[category].grab_focus()
		else:
			arrange_button.grab_focus()
	_render_catalog()
	_queue_focus()

func _older_refs(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _latest.has(id):
		return result
	var latest: int = _latest[id].document.version
	for ref: Dictionary in _history.values():
		if ref.document_id == id and int(ref.version) < latest:
			result.append(ref.duplicate())
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.version > b.version)
	return result

func arrange_windows() -> void:
	# 收折目录后再排版，给正文留出屏口空间。
	_set_directory_visible(false)
	_arranged = true
	_tile.call_deferred()
	_queue_focus()

func _tile() -> void:
	var ordered := windows.values()
	var count := ordered.size()
	if count == 0 or not _arranged:
		return
	var columns := 1 if count == 1 else 2
	if count == 3 and desk.size.x >= 1050:
		columns = 3
	var rows := ceili(float(count) / columns)
	var cell := (desk.size - Vector2(6 * (columns - 1), 6 * (rows - 1))) / Vector2(columns, rows)
	for index in count:
		var window := ordered[index] as DocumentWindow
		window.position = Vector2(index % columns, index / columns) * (cell + Vector2(6, 6))
		window.size = cell
		window.constrain()

func _fit_windows() -> void:
	if _arranged:
		_tile.call_deferred()
	else:
		for window in windows.values():
			window.constrain()

func set_reading_enabled(value: bool) -> void:
	_reading_enabled = value
	mouse_filter = Control.MOUSE_FILTER_PASS if value else Control.MOUSE_FILTER_IGNORE
	if not value:
		cancel_pointer_interaction()


func cancel_pointer_interaction() -> void:
	for window in windows.values():
		window.cancel_drag()
		window.cancel_statement_selection()

func _queue_focus() -> void:
	if not _focus_queued:
		_focus_queued = true
		rebuild_focus.call_deferred()

func rebuild_focus() -> void:
	_focus_queued = false
	var controls: Array[Control] = []
	controls.append(directory_button)
	if catalog_scroll.visible:
		for index in category_buttons.size():
			var button := category_buttons[index]
			if not button.visible or button.disabled:
				continue
			controls.append(button)
			if _catalog_lists[index].visible:
				for entry in _catalog_lists[index].get_children():
					if entry is Button and entry.visible and not entry.disabled:
						controls.append(entry)
	controls.append(arrange_button)
	if _review_panel.visible:
		for button in _review_buttons:
			if button.visible and not button.disabled:
				controls.append(button)
	for key: String in windows:
		var window: DocumentWindow = windows[key]
		var window_controls: Array[Control] = window.focus_controls()
		for control in window_controls:
			var on_focus := raise_window.bind(key, false)
			if not control.focus_entered.is_connected(on_focus):
				control.focus_entered.connect(on_focus)
		controls.append_array(window_controls)
	for index in controls.size():
		var control: Control = controls[index]
		var previous: Control = controls[posmod(index - 1, controls.size())]
		var next: Control = controls[(index + 1) % controls.size()]
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)
		control.focus_neighbor_left = control.get_path_to(previous)
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_right = control.get_path_to(next)
		control.focus_neighbor_bottom = control.get_path_to(next)

func move_focus(direction: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		arrange_button.grab_focus()
		return
	var active: DocumentWindow = windows.get(_active_key)
	if active != null and active.move_quote_focus(focused, direction):
		return
	var candidate := focused.find_prev_valid_focus() if direction < 0 else focused.find_next_valid_focus()
	if candidate != null:
		candidate.grab_focus()

func confirm_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if windows.has(_active_key):
		var window: DocumentWindow = windows[_active_key]
		window.cancel_statement_drag()
		if window.confirm_statement(focused):
			return
	if focused is Button and not focused.disabled:
		if focused.toggle_mode:
			focused.button_pressed = not focused.button_pressed
		focused.pressed.emit()

func cancel_statement_selection() -> bool:
	return windows.has(_active_key) and windows[_active_key].cancel_statement_selection(true)

func scroll_active(amount: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and catalog_scroll.visible and catalog_scroll.is_ancestor_of(focused):
		catalog_scroll.scroll_vertical += amount
		return
	for key: String in windows:
		var window: DocumentWindow = windows[key]
		if focused != null and (window == focused or window.is_ancestor_of(focused)):
			window.scroll_by(amount)
			return
	if windows.has(_active_key):
		windows[_active_key].scroll_by(amount)
func _update_font() -> void:
	# 项目按2560基准缩放画布；小窗口局部补偿字号，不改全局stretch或Camera。
	var screen_scale: float = maxf(0.5, get_viewport().get_screen_transform().get_scale().x)
	var font_size: int = maxi(22, roundi(18.0 / screen_scale))
	if theme.default_font_size != font_size:
		theme.default_font_size = font_size
	for window in windows.values():
		window.version_label.add_theme_font_size_override("font_size", maxi(14, roundi(13.0 / screen_scale)))


func _create_review_panel() -> void:
	_review_panel = VBoxContainer.new()
	add_child(_review_panel)
	var row := HBoxContainer.new()
	_review_panel.add_child(row)
	var frame := STYLE.box(STYLE.PAPER, STYLE.EDGE, 1, 5, 4)
	for slot in range(2):
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", frame)
		row.add_child(card)
		var contents := HBoxContainer.new()
		card.add_child(contents)
		var body := _review_button(contents, "", _locate_evidence.bind(slot))
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.custom_minimum_size.y = 63
		for state in ["normal", "disabled", "hover", "pressed"]:
			body.add_theme_stylebox_override(state, STYLE.box(
					STYLE.HOVER if state == "hover" else STYLE.PAPER, STYLE.EDGE, 0, 11, 5))
		for state in ["font_color", "font_focus_color", "font_disabled_color", "font_hover_color", "font_pressed_color"]:
			body.add_theme_color_override(state, STYLE.INK)
		body.clip_text = true
		body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_evidence_buttons.append(body)
		var clear := _review_button(contents, "×", _clear_review_field.bind(slot))
		clear.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		clear.custom_minimum_size.x = 34
		clear.tooltip_text = "清空这项证据"
		_clear_buttons.append(clear)
	var actions := HBoxContainer.new()
	_review_panel.add_child(actions)
	_review_feedback = Label.new()
	_review_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_review_feedback.clip_text = true
	_review_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	actions.add_child(_review_feedback)
	_challenge = _review_button(actions, "质疑", _submit_challenge)
	_challenge.custom_minimum_size = Vector2(232, 42)
	var fills := {
		"normal": Color("#a4372e"),
		"hover": Color("#c24d3e"),
		"pressed": Color("#842b24"),
		"hover_pressed": Color("#a4372e"),
		"disabled": Color("#6c312b"),
	}
	for state: String in fills:
		_challenge.add_theme_stylebox_override(state, STYLE.box(fills[state], Color("#c2745b")))
	for role in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_challenge.add_theme_color_override(role, STYLE.LIGHT)
	_challenge.add_theme_color_override("font_disabled_color", Color("#e6b4a4"))
	# 两侧各留一列反馈，交付提示隐藏时按钮也保持居中。
	var delivery_slot := MarginContainer.new()
	delivery_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(delivery_slot)
	_delivery_feedback = Label.new()
	_delivery_feedback.text = "回应未送达"
	_delivery_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_delivery_feedback.clip_text = true
	_delivery_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_delivery_feedback.hide()
	delivery_slot.add_child(_delivery_feedback)


func _review_button(row: HBoxContainer, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	row.add_child(button)
	_review_buttons.append(button)
	return button


func _can_review() -> bool:
	# 常驻卡槽只改变呈现，证据操作仍受原有会话和规则约束。
	return session_id > 0 and (not statement_documents.is_empty() \
			or (port.has("has_review_rules") and port.has_review_rules.call(session_id)))


func refresh_review() -> void:
	if _review_panel == null:
		return
	var preview := not statement_documents.is_empty()
	var can_review := _can_review()
	var valid_fields := 0
	var single_clause := false
	for slot in range(2):
		var ref := _slots[slot]
		var button := _evidence_buttons[slot]
		button.disabled = not can_review or ref.is_empty()
		_clear_buttons[slot].disabled = not can_review
		var item: Dictionary = _latest.get(ref.get("document_id"), {})
		var current: bool = not item.is_empty() and item.document.version == ref.get("version")
		var field: Dictionary = item.document.fields.get(ref.get("field_id", ""), {}) if current else {}
		if not field.is_empty():
			valid_fields += 1
			if item.document.source.kind == "system_reference":
				single_clause = field.requirement_key != "" and field.required_material_type != "" \
						and field.applicability_key != ""
		if ref.is_empty():
			button.text = "未选择证据"
		else:
			var snapshot: Dictionary = item if current else port.get_acquired_document.call(session_id, ref)
			if snapshot.is_empty():
				button.text = "v%d · 无法定位" % ref.version
			else:
				var doc: Dictionary = snapshot.document
				var quoted_field: Dictionary = doc.fields.get(ref.get("field_id", ""), {})
				var excerpt: String = ref.get("quote", quoted_field.get("display_value", ""))
				button.text = "%s · v%d%s · %s\n%s" % [doc.title, ref.version,
						"" if current else " · 旧版", doc.source.source_id, excerpt.replace("\n", " ")]
		button.tooltip_text = button.text if ref.is_empty() else button.text + "\n点击定位原文"
	for window: DocumentWindow in windows.values():
		window.set_evidence_fields(_slots)
	var selected_count := _selected_refs().size()
	_challenge.disabled = not can_review or preview or not (
			(selected_count == 1 and valid_fields == 1 and single_clause)
			or (selected_count == 2 and valid_fields == 2 and _slots[0].document_id != _slots[1].document_id))
	if preview:
		_challenge.tooltip_text = "本原型仅验证选取与比对"
		if _review_feedback.text.is_empty():
			_review_feedback.text = _challenge.tooltip_text
	_delivery_feedback.hide()
	if can_review and port.has("get_review_deliveries"):
		for delivery: Dictionary in port.get_review_deliveries.call(session_id):
			if delivery.status == "failed":
				_delivery_feedback.show()
				break
	_queue_focus()


func _selected_refs() -> Array[Dictionary]:
	var refs: Array[Dictionary] = []
	for ref in _slots:
		if not ref.is_empty():
			refs.append(ref)
	return refs


func _locate_evidence(slot: int) -> void:
	var ref := _slots[slot].duplicate()
	if ref.is_empty():
		return
	var expected_session := session_id
	open_document(ref)
	var key := _key(ref)
	var window := windows.get(key) as DocumentWindow
	if window == null:
		_review_feedback.text = "该版本不可定位"
		return
	if window.history_list.visible:
		window.history_button.button_pressed = false
	# 等开窗布局和阅读位置恢复完成；已经转移的焦点不应被旧定位抢回。
	await get_tree().process_frame
	await get_tree().process_frame
	if not _reading_enabled or expected_session != session_id or _slots[slot] != ref \
			or not is_instance_valid(window) or windows.get(key) != window \
			or not window.is_ancestor_of(get_viewport().gui_get_focus_owner()):
		return
	if ref.has("quote"):
		var original: String = window.receipt.document.original_text
		if ref.start >= 0 and ref.end > ref.start and ref.end <= original.length() \
				and original.substr(ref.start, ref.end - ref.start) == ref.quote:
			window.locate_statement(ref.start, ref.end)
			return
	elif window.locate_field(ref.get("field_id", "")):
		return
	_review_feedback.text = "该证据原文不可定位"


func _add_statement(ref: Dictionary, key: String, expected_session: int) -> void:
	if expected_session != session_id or not windows.has(key):
		return
	var item: Dictionary = _latest.get(ref.document_id, {})
	if item.is_empty() or item.document.version != ref.version:
		_review_feedback.text = "资料已更新，请重新选择当前版本。"
		return
	var text: String = item.document.original_text
	if ref.start < 0 or ref.end > text.length() or text.substr(ref.start, ref.end - ref.start) != ref.quote:
		_review_feedback.text = "选区已失效，请重新选择。"
		return
	ref["session_id"] = expected_session
	_add_review_field(ref)

func _add_review_field(ref: Dictionary) -> void:
	for selected: Dictionary in _slots:
		if selected.get("document_id") == ref.document_id:
			_review_feedback.text = "这份资料已加入比对，请选择另一份。"
			return
	var empty_slot := _slots.find({})
	if empty_slot == -1:
		_review_feedback.text = "比对已选满，请先清空一项。"
		return
	_slots[empty_slot] = ref.duplicate()
	_review_feedback.text = ""
	refresh_review()


func _clear_review_field(slot: int) -> void:
	_slots[slot] = {}
	_review_feedback.text = ""
	refresh_review()


func _operation_id() -> StringName:
	_review_operation += 1
	return StringName("w-review:%d" % _review_operation)


func _show_review_result(expected_session: int, result: FlowCommandResult) -> void:
	if expected_session != session_id:
		return
	_review_feedback.text = result.message
	refresh_review()


func _submit_challenge() -> void:
	if _challenge.disabled:
		return
	var refs := _selected_refs()
	# 业务只看非空证据；清左后留在右侧的条款仍然可以索证。
	if refs.size() == 1:
		_show_review_result(session_id, port.submit_material_request.call(session_id, _operation_id(), _review_ref(refs[0])))
	elif refs.size() == 2:
		_show_review_result(session_id, port.submit_document_challenge.call(session_id, _operation_id(), _review_ref(refs[0]), _review_ref(refs[1])))


func _review_ref(ref: Dictionary) -> Dictionary:
	if not ref.has("quote"):
		return ref
	return {"document_id": ref.document_id, "version": ref.version, "field_id": ref.field_id}
