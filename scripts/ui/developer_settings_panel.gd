class_name DeveloperSettingsPanel
extends VBoxContainer
## 开发者页始终留在 W 的屏口中，确认与改键共享底部操作区。

signal back_requested
signal quit_requested
signal bindings_changed

const Settings := preload("res://scripts/settings/settings_store.gd")
const Style := preload("res://scripts/ui/terminal_ui_style.gd")

@onready var rows: VBoxContainer = $Scroll/Rows
@onready var status: Label = $Status
@onready var primary: Button = $Footer/Primary
@onready var cancel: Button = $Footer/Cancel
@onready var back: Button = $Footer/Back
@onready var quit: Button = $Footer/Quit

enum Prompt { NONE, QUIT, DISPLAY, KEY }
var store := Settings.new()
var _prompt := Prompt.NONE
var _deadline: int
var _capture_index: int
var _preview_size: Vector2i
var _preview_fullscreen: bool
var _restore_focus: WeakRef
var _volumes: Array[HSlider] = []
var _volume_labels: Array[Label] = []
var _binding_buttons: Array[Button] = []
var _mode: OptionButton
var _size: OptionButton
var _sizes: Array[Vector2i]
var _binding_release := KEY_NONE
var _section_rows: VBoxContainer


func _ready() -> void:
	theme = Style.make_theme(32)
	theme.set_type_variation("WOption", "OptionButton")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "WOption", theme.get_stylebox(state, "Button"))
	for role in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		theme.set_color(role, "WOption", theme.get_color(role, "Button"))
	theme.set_stylebox("panel", "PopupMenu", Style.box(Style.DESK))
	theme.set_stylebox("hover", "PopupMenu", Style.box(Style.HOVER))
	theme.set_color("font_color", "PopupMenu", Style.AMBER)
	theme.set_color("font_hover_color", "PopupMenu", Style.INK)
	theme.set_stylebox("slider", "HSlider", Style.box(Style.DESK, Style.EDGE, 1, 6, 5))
	theme.set_stylebox("grabber_area", "HSlider", Style.box(Style.PICKED, Style.EDGE, 1, 6, 5))
	theme.set_stylebox("grabber_area_highlight", "HSlider", Style.box(Style.ACTIVE, Style.AMBER, 1, 6, 5))
	for button in [primary, cancel, back, quit]:
		button.custom_minimum_size = Vector2(154, 48)
	quit.add_theme_stylebox_override("normal", Style.box(Color("#422725"), Color("#a36349")))
	_section("声音")
	for index in Settings.BUSES.size():
		var slider := HSlider.new()
		slider.max_value = 100.0
		slider.custom_minimum_size = Vector2(120, 40)
		slider.step = 1.0
		var value := Label.new()
		value.custom_minimum_size.x = 92
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_row(["主音量", "音效"][index]).add_child(slider)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.get_parent().add_child(value)
		slider.value_changed.connect(func(amount: float) -> void:
			value.text = "%d%%" % amount
			store.volumes[index] = amount
			store.apply_audio()
		)
		slider.drag_ended.connect(func(changed: bool) -> void:
			if changed:
				_save()
		)
		# 键盘或手柄调整时没有拖动结束事件。
		slider.value_changed.connect(func(_amount: float) -> void:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_save()
		)
		_volumes.append(slider)
		_volume_labels.append(value)
		slider.set_value_no_signal(100)
		value.text = "100%"
	_label("音乐：当前未配置")
	_section("显示")
	_mode = _option()
	_mode.add_item("窗口化")
	_mode.add_item("无边框全屏")
	_row("窗口模式").add_child(_mode)
	_size = _option()
	_row("窗口大小").add_child(_size)
	_mode.item_selected.connect(func(index: int) -> void: _size.disabled = index == 1)
	var apply := Button.new()
	apply.text = "应用显示"
	apply.pressed.connect(_preview_display)
	_row("").add_child(apply)
	_section("操作")
	_label("Esc / Menu：设置与返回　　十字键 / 左摇杆：导航")
	_label("鼠标左键 / A：确认　　B：返回　　右摇杆：滚动文书")
	for index in Settings.ACTIONS.size():
		var binding := Button.new()
		binding.custom_minimum_size = Vector2(128, 40)
		_row(["向左转 / LB", "向右转 / RB", "核验终端 / View"][index]).add_child(binding)
		binding.pressed.connect(_capture_key.bind(index))
		_binding_buttons.append(binding)
	var defaults := Button.new()
	defaults.text = "恢复默认键位"
	defaults.pressed.connect(_restore_default_keys)
	_row("").add_child(defaults)
	back.pressed.connect(request_back)
	quit.pressed.connect(_ask_quit)
	cancel.pressed.connect(request_back)
	primary.pressed.connect(_confirm_prompt)
	_end_prompt()


func refresh_settings() -> void:
	for index in _volumes.size():
		_volumes[index].set_value_no_signal(store.volumes[index])
		_volume_labels[index].text = "%d%%" % store.volumes[index]
	_sizes = store.available_sizes()
	_size.clear()
	for size in _sizes:
		_size.add_item("%d × %d" % [size.x, size.y])
	var selected := _sizes.find(store.window_size)
	_size.select(maxi(0, selected))
	_mode.select(1 if store.fullscreen else 0)
	_size.disabled = store.fullscreen
	for index in _binding_buttons.size():
		_binding_buttons[index].text = OS.get_keycode_string(store.keys[index] as Key)


func focus_return() -> void:
	back.grab_focus()


func release_settings_focus() -> void:
	_binding_release = KEY_NONE
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()


func move_focus(direction: int, horizontal: bool) -> void:
	if _prompt != Prompt.NONE:
		if primary.visible:
			(primary if direction < 0 else cancel).grab_focus()
		return
	var focused := get_viewport().gui_get_focus_owner()
	if horizontal and focused is HSlider:
		focused.value += direction * 5
	elif horizontal and focused is OptionButton:
		focused.select(wrapi(focused.selected + direction, 0, focused.item_count))
		focused.item_selected.emit(focused.selected)
	elif focused != null:
		var next := focused.find_next_valid_focus() if direction > 0 else focused.find_prev_valid_focus()
		if is_instance_valid(next) and is_ancestor_of(next):
			next.grab_focus()


func request_back() -> void:
	match _prompt:
		Prompt.DISPLAY:
			store.apply_display(store.fullscreen, store.window_size)
			_end_prompt()
			refresh_settings()
		Prompt.QUIT, Prompt.KEY:
			_end_prompt()
		_:
			back_requested.emit()


func capture_binding(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if _binding_release != KEY_NONE and key == _binding_release:
		if not event.pressed:
			_binding_release = KEY_NONE
		return true
	if _prompt != Prompt.KEY:
		return false
	if event.pressed and not event.echo:
		var existing := store.keys.find(key)
		if not store.valid_key(key):
			status.text = "请选择字母键或功能键。固定键不可占用。"
		elif existing != -1 and existing != _capture_index:
			status.text = "该键已绑定其他操作。"
		else:
			store.keys[_capture_index] = key
			_binding_release = key as Key
			_end_prompt()
			_apply_keys()
	return true


func _process(_delta: float) -> void:
	if _prompt != Prompt.DISPLAY:
		return
	var remaining := _deadline - Time.get_ticks_msec()
	if remaining <= 0:
		request_back()
	else:
		status.text = "保留当前显示？%d 秒后恢复" % ceili(remaining / 1000.0)


func _preview_display() -> void:
	if DisplayServer.get_name() == "headless" or store.get_embedded():
		status.text = "请在独立游戏窗口中调整显示。"
		return
	_begin_prompt(Prompt.DISPLAY, "保留当前显示？", "保留")
	_deadline = Time.get_ticks_msec() + 15000
	_preview_fullscreen = _mode.selected == 1
	_preview_size = _sizes[_size.selected]
	store.apply_display(_preview_fullscreen, _preview_size)


func _ask_quit() -> void:
	_begin_prompt(Prompt.QUIT, "确认退出程序？", "退出")


func _capture_key(index: int) -> void:
	_capture_index = index
	_begin_prompt(Prompt.KEY, "按一个字母键或功能键。", "")


func _restore_default_keys() -> void:
	store.keys = Settings.DEFAULT_KEYS.duplicate()
	_apply_keys()


func _apply_keys() -> void:
	store.apply_keys()
	refresh_settings()
	bindings_changed.emit()
	_save()


func _begin_prompt(kind: int, message: String, confirm_text: String) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	_restore_focus = weakref(focused) if is_instance_valid(focused) else null
	_prompt = kind
	status.text = message
	$Scroll.hide()
	back.hide()
	quit.hide()
	primary.text = confirm_text
	primary.visible = not confirm_text.is_empty()
	cancel.show()
	cancel.grab_focus()


func _end_prompt() -> void:
	_prompt = Prompt.NONE
	status.text = ""
	$Scroll.show()
	back.show()
	quit.show()
	primary.hide()
	cancel.hide()
	var focused := _restore_focus.get_ref() as Control if _restore_focus != null else null
	if is_instance_valid(focused) and focused.is_visible_in_tree():
		focused.grab_focus()
	elif is_visible_in_tree():
		back.grab_focus()
	_restore_focus = null


func _confirm_prompt() -> void:
	match _prompt:
		Prompt.QUIT:
			primary.disabled = true
			cancel.disabled = true
			quit_requested.emit()
		Prompt.DISPLAY:
			store.fullscreen = _preview_fullscreen
			store.window_size = _preview_size
			_end_prompt()
			_save()


func _save() -> void:
	if store.save_settings() != OK:
		status.text = "无法保存设置。"


func _section(caption: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box(Style.SURFACE, Style.EDGE, 1, 18, 9))
	rows.add_child(panel)
	_section_rows = VBoxContainer.new()
	_section_rows.add_theme_constant_override("separation", 4)
	panel.add_child(_section_rows)
	var heading := Label.new()
	heading.text = caption
	heading.add_theme_color_override("font_color", Style.LIGHT)
	_section_rows.add_child(heading)
	_section_rows.add_child(HSeparator.new())


func _option() -> OptionButton:
	var option := OptionButton.new()
	option.theme_type_variation = &"WOption"
	option.custom_minimum_size = Vector2(270, 44)
	return option


func _row(caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_rows.add_child(row)
	row.add_child(label)
	return row


func _label(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", Style.MUTED)
	label.add_theme_font_size_override("font_size", 27)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_section_rows.add_child(label)
