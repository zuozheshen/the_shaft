class_name VerificationWorkspace
extends VBoxContainer
## 只缓存引用和阅读布局；资料真值来自受限端口和已有提交事件。

const WINDOW := preload("res://scenes/ui/document_window.tscn")
const CATEGORIES: Array[String] = ["收件箱", "规程 / 样板", "已调阅资料"]

var port: Dictionary = {}
var session_id: int = 0
var windows: Dictionary = {}
var saved_views: Dictionary = {}
var category: int = 0
var catalog: VBoxContainer
var catalog_scroll: ScrollContainer
var desk: Control
var status_label: Label
var arrange_button: Button
var directory_button: Button
var category_buttons: Array[Button] = []
var switch_scroll: ScrollContainer
var switch_strip: HBoxContainer
var switch_buttons: Dictionary = {}
var _outer_focus: Control
var _latest: Dictionary = {}
var _history: Dictionary = {}
var _active_key: String = ""
var _arranged: bool = false
var _focus_queued: bool = false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = Theme.new()
	theme.default_font_size = 18
	add_theme_constant_override("separation", 4)
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	for index in CATEGORIES.size():
		var button := Button.new()
		button.text = CATEGORIES[index]
		button.toggle_mode = true
		button.button_pressed = index == category
		button.pressed.connect(_select_category.bind(index))
		toolbar.add_child(button)
		category_buttons.append(button)
	directory_button = Button.new()
	directory_button.text = "目录"
	directory_button.toggle_mode = true
	directory_button.button_pressed = true
	directory_button.toggled.connect(func(value: bool) -> void:
		catalog_scroll.visible = value
		_queue_focus()
		_fit_windows.call_deferred())
	toolbar.add_child(directory_button)
	arrange_button = Button.new()
	arrange_button.text = "自动并排"
	arrange_button.pressed.connect(arrange_windows)
	toolbar.add_child(arrange_button)
	# 提交状态与窗口条共用一行，避免增加导航高度挤占正文。
	var status_row := HBoxContainer.new()
	add_child(status_row)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_row.add_child(status_label)
	status_row.add_child(VSeparator.new())
	switch_scroll = ScrollContainer.new()
	switch_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	switch_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	switch_scroll.follow_focus = true
	status_row.add_child(switch_scroll)
	switch_strip = HBoxContainer.new()
	switch_scroll.add_child(switch_strip)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	catalog_scroll = ScrollContainer.new()
	catalog_scroll.custom_minimum_size.x = 166
	catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(catalog_scroll)
	catalog = VBoxContainer.new()
	catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_scroll.add_child(catalog)
	desk = Control.new()
	desk.name = "WindowDesk"
	desk.clip_contents = true
	desk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(desk)
	desk.resized.connect(_fit_windows)
	get_window().size_changed.connect(_update_font)
	_update_font()
	refresh()

func bind_port(value: Dictionary, outside_focus: Control) -> void:
	port = value.duplicate()
	_outer_focus = outside_focus
	reset_session(int(port.get_session_id.call()))

func reset_session(value: int) -> void:
	if value == session_id:
		refresh()
		return
	for window in windows.values():
		window.free()
	windows.clear()
	saved_views.clear()
	_latest.clear()
	_history.clear()
	_active_key = ""
	_render_switch_strip()
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
	var passenger_batches: int = 0
	for event: Dictionary in events:
		if event.route == "passenger":
			passenger_batches += 1
	status_label.text = "值班待命 / 暂无当前派单" if session_id == 0 else (
		"尚无提交记录" if passenger_batches == 0 else
		"本批提交结束 · 已收到 · 提交批次 %d%s" % [passenger_batches,
			" / 含后续补交" if passenger_batches > 1 else ""])
	for window in windows.values():
		var id: String = window.document_ref.document_id
		if _latest.has(id):
			window.show_document(window.receipt, int(_latest[id].document.version))
			window.set_history(_older_refs(id))
	_render_catalog()
	_queue_focus()

func _select_category(index: int) -> void:
	category = index
	for n in category_buttons.size():
		category_buttons[n].set_pressed_no_signal(n == index)
	catalog_scroll.visible = true
	directory_button.set_pressed_no_signal(true)
	_render_catalog()
	_queue_focus()

func _catalog_button(text: String, action: Callable, ref: Dictionary = {}) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	button.set_meta("document_ref", ref.duplicate())
	button.pressed.connect(action)
	catalog.add_child(button)
	return button

func _render_catalog() -> void:
	# 更新目录时保留键盘所处行；无关更新不能抢走正文焦点。
	var focused := get_viewport().gui_get_focus_owner()
	var focus_index := focused.get_index() if focused != null and focused.get_parent() == catalog else -1
	var old_scroll := catalog_scroll.scroll_vertical
	for child in catalog.get_children():
		catalog.remove_child(child)
		child.queue_free()
	match category:
		0:
			for item: Dictionary in _latest.values():
				if item.route == "passenger":
					var ref := {"document_id": item.document.document_id, "version": item.document.version}
					_catalog_button(item.document.title, open_document.bind(ref), ref)
		1:
			if session_id > 0 and not port.is_empty():
				var references: Dictionary = {}
				for ref: Dictionary in port.get_system_references.call(session_id):
					if not references.has(ref.document_id) or int(ref.version) > int(references[ref.document_id].version):
						references[ref.document_id] = ref
				for ref: Dictionary in references.values():
					_catalog_button(ref.title, open_reference.bind(ref), {"document_id":ref.document_id, "version":ref.version})
		2:
			for item: Dictionary in _latest.values():
				# 只按实际取得渠道分类，字段的引述出处不能提升权限。
				if item.route not in ["left", "right"]:
					continue
				var ref := {"document_id":item.document.document_id, "version":item.document.version}
				_catalog_button(item.document.title, open_document.bind(ref), ref)
	if catalog.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "暂无资料"
		catalog.add_child(empty)
	if focus_index >= 0:
		var candidate := catalog.get_child(mini(focus_index, catalog.get_child_count() - 1)) as Control
		if candidate.focus_mode == Control.FOCUS_ALL:
			candidate.grab_focus()
		else:
			category_buttons[category].grab_focus()
	catalog_scroll.set_deferred("scroll_vertical", old_scroll)

func open_reference(ref: Dictionary) -> void:
	if session_id <= 0:
		return
	port.open_system_reference.call(session_id, ref)
	refresh()
	open_document(ref)

func open_retrieved_document(ref: Dictionary) -> void:
	_select_category(2) # 已调阅资料
	open_document(ref)


func open_document(ref: Dictionary) -> void:
	if session_id <= 0 or port.is_empty():
		return
	var snapshot: Dictionary = port.get_acquired_document.call(session_id, ref)
	if snapshot.is_empty():
		status_label.text = "该版本已失效 / 请重新调阅"
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
		window.size = (desk.size * Vector2(0.65, 0.9)).max(Vector2(200, 120)).min(desk.size)
		window.position = Vector2(18, 14) * ((windows.size() - 1) % 4)
	window.constrain()
	_arranged = false
	_render_switch_strip()
	raise_window(key)
	_render_catalog()
	_queue_focus()

func _open_latest(id: String) -> void:
	if _latest.has(id):
		open_document({"document_id": id, "version": _latest[id].document.version})

func raise_window(key: String, focus_body: bool = true) -> void:
	if not windows.has(key):
		return
	_active_key = key
	var window: DocumentWindow = windows[key]
	desk.move_child(window, desk.get_child_count() - 1)
	_update_switch_active()
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
	var lost_focus: bool = focused != null and (window.is_ancestor_of(focused) or focused == switch_buttons.get(key))
	var open_keys: Array = windows.keys()
	var closed_index: int = open_keys.find(key)
	windows.erase(key)
	window.hide()
	desk.remove_child(window)
	window.queue_free()
	if _active_key == key:
		var remaining: Array = windows.keys()
		_active_key = String(remaining[mini(closed_index, remaining.size() - 1)]) if not remaining.is_empty() else ""
	_render_switch_strip()
	if lost_focus:
		if switch_buttons.has(_active_key):
			raise_window(_active_key, false)
			switch_buttons[_active_key].grab_focus()
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

func _render_switch_strip() -> void:
	if switch_strip == null:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var focused_key: String = ""
	for key: String in switch_buttons:
		if switch_buttons[key] == focused:
			focused_key = key
	for child in switch_strip.get_children():
		switch_strip.remove_child(child)
		child.queue_free()
	switch_buttons.clear()
	# Dictionary保留开窗顺序；置顶只移动阅读窗，不让切换目标跳动。
	for key: String in windows:
		var window: DocumentWindow = windows[key]
		var button := Button.new()
		button.text = "%s · v%d" % [window.receipt.document.title, window.document_ref.version]
		button.toggle_mode = true
		var selected := StyleBoxFlat.new()
		selected.bg_color = Color("#36594f")
		selected.border_color = Color("#a8c7b2")
		selected.set_border_width_all(1)
		selected.set_content_margin_all(4)
		button.add_theme_stylebox_override("pressed", selected)
		button.set_meta("document_ref", window.document_ref.duplicate())
		button.pressed.connect(raise_window.bind(key))
		button.focus_entered.connect(switch_scroll.ensure_control_visible.bind(button))
		switch_strip.add_child(button)
		switch_buttons[key] = button
	switch_scroll.visible = not switch_buttons.is_empty()
	_update_switch_active()
	if switch_buttons.has(focused_key):
		switch_buttons[focused_key].grab_focus()
	_queue_focus()

func _update_switch_active() -> void:
	for key: String in switch_buttons:
		switch_buttons[key].set_pressed_no_signal(key == _active_key)

func arrange_windows() -> void:
	# 收折目录后再排版，给正文留出屏口空间。
	directory_button.set_pressed_no_signal(false)
	catalog_scroll.visible = false
	_arranged = true
	_tile.call_deferred()
	_queue_focus()

func _tile() -> void:
	var count := desk.get_child_count()
	if count == 0:
		return
	var columns := 1 if count == 1 else 2
	if count == 3 and desk.size.x >= 1050:
		columns = 3
	var rows := ceili(float(count) / columns)
	var cell := (desk.size - Vector2(6 * (columns - 1), 6 * (rows - 1))) / Vector2(columns, rows)
	for index in count:
		var window := desk.get_child(index) as DocumentWindow
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
	mouse_filter = Control.MOUSE_FILTER_PASS if value else Control.MOUSE_FILTER_IGNORE
	if not value:
		for window in windows.values():
			window.cancel_drag()

func _queue_focus() -> void:
	if not _focus_queued:
		_focus_queued = true
		rebuild_focus.call_deferred()

func rebuild_focus() -> void:
	_focus_queued = false
	var controls: Array[Control] = []
	if is_instance_valid(_outer_focus):
		controls.append(_outer_focus)
	for button in category_buttons:
		controls.append(button)
	controls.append(directory_button)
	controls.append(arrange_button)
	if catalog_scroll.visible:
		for child in catalog.get_children():
			if child is Button:
				controls.append(child)
	for button in switch_buttons.values():
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
	var candidate := focused.find_prev_valid_focus() if direction < 0 else focused.find_next_valid_focus()
	if candidate != null:
		candidate.grab_focus()

func confirm_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button and not focused.disabled:
		if focused.toggle_mode:
			focused.button_pressed = not focused.button_pressed
		focused.pressed.emit()

func scroll_active(amount: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
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
	var font_size: int = maxi(18, roundi(16.0 / screen_scale))
	if theme.default_font_size != font_size:
		theme.default_font_size = font_size
	status_label.add_theme_font_size_override("font_size", maxi(14, roundi(13.0 / screen_scale)))
	for window in windows.values():
		window.version_label.add_theme_font_size_override("font_size", maxi(14, roundi(13.0 / screen_scale)))
