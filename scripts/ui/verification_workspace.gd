class_name VerificationWorkspace
extends VBoxContainer
## 只缓存引用和阅读布局；资料真值来自受限端口和已有提交事件。

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
var status_label: Label
var arrange_button: Button
var directory_button: Button
var category_buttons: Array[Button] = []
var _outer_focus: Control
var _latest: Dictionary = {}
var _history: Dictionary = {}
var _active_key: String = ""
var _arranged: bool = false
var _focus_queued: bool = false
var _review_panel: VBoxContainer
var _evidence_buttons: Array[Button] = []
var _review_buttons: Array[Button] = []
var _review_feedback: Label
var _challenge: Button
var _delivery_feedback: Label
var _slots: Array[Dictionary] = [{}, {}]
var _review_operation := 0
var _reading_enabled := false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = Theme.new()
	theme.default_font_size = 18
	add_theme_constant_override("separation", 4)
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	directory_button = Button.new()
	directory_button.text = "目录"
	directory_button.toggle_mode = true
	directory_button.button_pressed = true
	directory_button.toggled.connect(_set_directory_visible)
	toolbar.add_child(directory_button)
	arrange_button = Button.new()
	arrange_button.text = "整理窗口"
	arrange_button.pressed.connect(arrange_windows)
	toolbar.add_child(arrange_button)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size", 14)
	toolbar.add_child(status_label)
	toolbar.move_child(status_label, 0)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	catalog_scroll = ScrollContainer.new()
	catalog_scroll.custom_minimum_size.x = 226
	catalog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(catalog_scroll)
	var directory := VBoxContainer.new()
	directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_scroll.add_child(directory)
	for index in CATEGORIES.size():
		var button := Button.new()
		button.text = CATEGORIES[index]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = index == category
		button.pressed.connect(_select_category.bind(index))
		button.focus_entered.connect(_reveal_directory_focus.call_deferred)
		directory.add_child(button)
		category_buttons.append(button)
	directory.add_child(HSeparator.new())
	catalog = VBoxContainer.new()
	directory.add_child(catalog)
	desk = Control.new()
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
	refresh_review()
	_queue_focus()

func _set_directory_visible(value: bool) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if not value and focused != null and catalog_scroll.is_ancestor_of(focused):
		directory_button.grab_focus()
	catalog_scroll.visible = value
	directory_button.set_pressed_no_signal(value)
	_queue_focus()
	_fit_windows.call_deferred()


func _select_category(index: int) -> void:
	category = index
	for n in category_buttons.size():
		category_buttons[n].set_pressed_no_signal(n == index)
	_set_directory_visible(true)
	_render_catalog()
	_queue_focus()


func _catalog_button(text: String, action: Callable, ref: Dictionary = {}) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	button.set_meta("document_ref", ref.duplicate())
	button.focus_entered.connect(_reveal_directory_focus.call_deferred)
	button.pressed.connect(action)
	catalog.add_child(button)
	return button

func _reveal_directory_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and catalog_scroll.visible and catalog_scroll.is_ancestor_of(focused):
		catalog_scroll.ensure_control_visible(focused)


func _render_catalog() -> void:
	# 刷新目录时用资料引用恢复焦点；正文焦点不受目录重建影响。
	var focused := get_viewport().gui_get_focus_owner()
	var focused_ref: Dictionary = {}
	if focused != null and focused.get_parent() == catalog:
		focused_ref = focused.get_meta("document_ref", {})
	var old_scroll := catalog_scroll.scroll_vertical
	for child in catalog.get_children():
		catalog.remove_child(child)
		child.queue_free()
	if category == REFERENCE_CATEGORY:
		if session_id > 0 and not port.is_empty():
			var references: Dictionary = {}
			for ref: Dictionary in port.get_system_references.call(session_id):
				if not references.has(ref.document_id) or int(ref.version) > int(references[ref.document_id].version):
					references[ref.document_id] = ref
			for ref: Dictionary in references.values():
				_catalog_button(ref.title, open_reference.bind(ref),
						{"document_id": ref.document_id, "version": ref.version})
	else:
		for item: Dictionary in _latest.values():
			# 字段的引述出处不改变取得渠道或权限。
			if item.route == CATEGORY_ROUTES[category]:
				var ref := {"document_id": item.document.document_id, "version": item.document.version}
				_catalog_button("%s · v%d" % [item.document.title, ref.version], open_document.bind(ref), ref)
	if catalog.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "暂无资料"
		catalog.add_child(empty)
	catalog_scroll.set_deferred("scroll_vertical", old_scroll)
	if not focused_ref.is_empty() and catalog_scroll.visible:
		for button in catalog.get_children():
			var ref: Dictionary = button.get_meta("document_ref", {})
			# 同一资料升级时，目录焦点跟到这份资料的新版。
			if ref.get("document_id") == focused_ref.document_id:
				button.grab_focus()
				return
		category_buttons[category].grab_focus()


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
	window.review_enabled = _review_panel.visible
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
		window.size = (desk.size * Vector2(0.65, 0.9)).max(Vector2(200, 120)).min(desk.size)
		window.position = Vector2(18, 14) * ((windows.size() - 1) % 4)
	window.constrain()
	_arranged = false
	raise_window(key)
	_render_catalog()
	if not window.statement_blocks.is_empty():
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
	var window: DocumentWindow = windows[key]
	desk.move_child(window, desk.get_child_count() - 1)
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
	if is_instance_valid(_outer_focus):
		controls.append(_outer_focus)
	controls.append(directory_button)
	controls.append(arrange_button)
	if _review_panel.visible:
		for button in _review_buttons:
			if button.visible and not button.disabled:
				controls.append(button)
	if catalog_scroll.visible:
		controls.append_array(category_buttons)
		for child in catalog.get_children():
			if child is Button:
				controls.append(child)
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


func _create_review_panel() -> void:
	_review_panel = VBoxContainer.new()
	_review_panel.hide()
	add_child(_review_panel)
	var row := HBoxContainer.new()
	_review_panel.add_child(row)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#102c2b")
	frame.border_color = Color("#63837a")
	frame.set_border_width_all(1)
	frame.set_content_margin_all(4)
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
		body.clip_text = true
		body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_evidence_buttons.append(body)
		var clear := _review_button(contents, "×", _clear_review_field.bind(slot))
		clear.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		clear.tooltip_text = "清空这项证据"
	var actions := HBoxContainer.new()
	_review_panel.add_child(actions)
	_review_feedback = Label.new()
	_review_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_review_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	actions.add_child(_review_feedback)
	_delivery_feedback = Label.new()
	_delivery_feedback.text = "回应未送达"
	_delivery_feedback.hide()
	actions.add_child(_delivery_feedback)
	_challenge = _review_button(actions, "提出质疑", _submit_challenge)


func _review_button(row: HBoxContainer, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	row.add_child(button)
	_review_buttons.append(button)
	return button


func refresh_review() -> void:
	if _review_panel == null:
		return
	var preview := not statement_documents.is_empty()
	_review_panel.visible = session_id > 0 and (preview or (port.has("has_review_rules") and port.has_review_rules.call(session_id)))
	if not _review_panel.visible:
		return
	var valid_fields := 0
	var single_clause := false
	for slot in range(2):
		var ref := _slots[slot]
		var button := _evidence_buttons[slot]
		button.disabled = ref.is_empty()
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
		elif not current:
			button.text = "v%d · 版本已更新 / 请重新选取" % ref.version
		else:
			var excerpt: String = ref.get("quote", field.get("display_value", ""))
			button.text = "%s · v%d\n%s" % [item.document.title, ref.version, excerpt.replace("\n", " ")]
		button.tooltip_text = button.text if ref.is_empty() else button.text + "\n点击定位原文"
	var selected_count := _selected_refs().size()
	_challenge.disabled = preview or not (
			(selected_count == 1 and valid_fields == 1 and single_clause)
			or (selected_count == 2 and valid_fields == 2 and _slots[0].document_id != _slots[1].document_id))
	if preview:
		_challenge.tooltip_text = "本原型仅验证选取与比对"
		if _review_feedback.text.is_empty():
			_review_feedback.text = _challenge.tooltip_text
	_delivery_feedback.hide()
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
