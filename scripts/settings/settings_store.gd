extends RefCounted
## 只保存可应用的设备设置。显示预览在用户确认后才写盘。

const ACTIONS: Array[StringName] = [&"turn_left", &"turn_right", &"verification_terminal_toggle"]
const DEFAULT_KEYS: Array[int] = [KEY_Q, KEY_E, KEY_W]
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440)]
const BUSES: Array[StringName] = [&"Master", &"SFX"]

var path := "user://settings.cfg"
var volumes: Array[float] = [100.0, 100.0]
var keys: Array[int] = DEFAULT_KEYS.duplicate()
var fullscreen := true
var window_size := Vector2i(1280, 720)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for index in BUSES.size():
		var value: Variant = config.get_value("audio", BUSES[index], 100.0)
		if (value is float or value is int) and is_finite(float(value)) and value >= 0 and value <= 100:
			volumes[index] = float(value)
	var mode: Variant = config.get_value("display", "fullscreen", true)
	if mode is bool:
		fullscreen = mode
	var size: Variant = config.get_value("display", "window_size", window_size)
	if size is Vector2i and _fits_screen(size):
		window_size = size
	var proposed: Array[int] = DEFAULT_KEYS.duplicate()
	for index in ACTIONS.size():
		var key: Variant = config.get_value("input", ACTIONS[index], DEFAULT_KEYS[index])
		if key is int and valid_key(key):
			proposed[index] = key
	if proposed[0] != proposed[1] and proposed[0] != proposed[2] and proposed[1] != proposed[2]:
		keys = proposed


func save_settings() -> Error:
	var config := ConfigFile.new()
	for index in BUSES.size():
		config.set_value("audio", BUSES[index], volumes[index])
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "window_size", window_size)
	for index in ACTIONS.size():
		config.set_value("input", ACTIONS[index], keys[index])
	var temp := path + ".tmp"
	var result := config.save(temp)
	if result != OK:
		return result
	return DirAccess.rename_absolute(temp, path)


func apply_audio() -> void:
	for index in BUSES.size():
		var bus := AudioServer.get_bus_index(BUSES[index])
		if bus >= 0:
			AudioServer.set_bus_volume_linear(bus, maxf(0.001, volumes[index] / 100.0))
			AudioServer.set_bus_mute(bus, is_zero_approx(volumes[index]))


func apply_keys() -> void:
	for index in ACTIONS.size():
		var action := ACTIONS[index]
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		var binding := InputEventKey.new()
		binding.physical_keycode = keys[index] as Key
		InputMap.action_add_event(action, binding)


static func valid_key(key: int) -> bool:
	if key not in range(KEY_A, KEY_Z + 1) and key not in range(KEY_F1, KEY_F12 + 1):
		return false
	var event := InputEventKey.new()
	event.physical_keycode = key as Key
	for action: StringName in [&"developer_mode", &"ui_accept", &"ui_cancel", &"ui_focus_next",
			&"ui_focus_prev", &"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		if InputMap.event_is_action(event, action):
			return false
	return true


func available_sizes() -> Array[Vector2i]:
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen).size
	var result: Array[Vector2i] = []
	for size in SIZES:
		if size.x <= area.x and size.y <= area.y:
			result.append(size)
	if _fits_screen(window_size) and not result.has(window_size):
		result.append(window_size)
	var current := DisplayServer.window_get_size()
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED \
			and _fits_screen(current) and not result.has(current):
		result.append(current)
	if result.is_empty():
		result.append(Vector2i(mini(1280, area.x), mini(720, area.y)).max(Vector2i.ONE))
	return result


func _fits_screen(size: Vector2i) -> bool:
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen).size
	return size.x >= 640 and size.y >= 360 and size.x <= area.x and size.y <= area.y


func apply_display(use_fullscreen: bool, size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless" or get_embedded():
		return
	if use_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var screen := DisplayServer.window_get_current_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	var fitted := size.min(area.size)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(fitted)
	DisplayServer.window_set_position(area.position + (area.size - fitted) / 2)


static func get_embedded() -> bool:
	return "--wid" in OS.get_cmdline_args()
