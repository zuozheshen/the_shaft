extends RefCounted

const MAIN := preload("res://scenes/main/main_3d.tscn")
const Settings := preload("res://scripts/settings/settings_store.gd")


func run(t: Variant, tree: SceneTree) -> void:
	var main := MAIN.instantiate()
	var entry := main.get_node("值守入口") as CabinEntryController
	entry.sit_up_duration = 0.05
	t.add_child(main)
	await tree.process_frame
	var terminal := entry.terminal
	terminal.slide_duration = 0.10
	var viewport := entry.get_viewport()
	var camera := terminal.get_parent() as Camera3D
	var rest := camera.global_transform
	var sfx := AudioServer.get_bus_index(&"SFX")
	var door := AudioServer.get_bus_index(&"ElevatorDoor")
	t.assert_true("设置 / 音效总线真实承接门声",
		sfx > 0 and door > sfx and AudioServer.get_bus_send(door) == &"SFX")
	t.assert_true("休息 / 正式入口仰靠并拦截操作台",
		entry.menu.visible and terminal.is_input_captured() and rest.basis.z.y < -0.8)
	_press(viewport, false)
	await tree.create_timer(0.2).timeout
	t.assert_true("休息 / Esc 举起原 W 且相机不动",
		terminal.developer_active and tree.paused and camera.global_transform.is_equal_approx(rest))
	terminal.developer_panel.quit.pressed.emit()
	_press(viewport, true)
	t.assert_true("开发者页 / Menu 优先取消退出确认",
		terminal.developer_active and not terminal.developer_panel.cancel.visible)
	_press(viewport, true)
	await tree.create_timer(0.2).timeout
	t.assert_true("休息 / Menu 返回原菜单和设置焦点",
		entry.menu.visible and entry.settings_button.has_focus() and not tree.paused
		and camera.global_transform.is_equal_approx(rest))
	await entry.start_duty()
	t.assert_true("值守 / 坐起对齐原主台",
		not entry.menu.visible and not terminal.is_input_captured()
		and camera.global_basis.is_equal_approx(Basis.IDENTITY))
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.request_travel_to_floor("001")
	var timer := manager.elevator_runtime_state.movement_timer
	var remaining := timer.time_left
	_press(viewport, true)
	await tree.create_timer(0.2).timeout
	t.assert_true("值守 / Menu 打开设置时冻结实际行驶 Timer",
		tree.paused and manager.is_elevator_moving() and is_equal_approx(timer.time_left, remaining))
	_press(viewport, false)
	await tree.create_timer(0.2).timeout
	t.assert_true("值守 / Esc 直接返回台位并恢复业务",
		not terminal.target_open and not terminal.is_input_captured() and not tree.paused
		and camera.global_basis.is_equal_approx(Basis.IDENTITY))
	terminal.set_open(true)
	await tree.create_timer(0.2).timeout
	_press(viewport, true)
	t.assert_true("文书 / Menu 在原 W 内切换", terminal.developer_active and not terminal.workspace.visible)
	_press(viewport, true)
	t.assert_true("文书 / Menu 返回原 W",
		terminal.target_open and terminal.workspace.visible and not terminal.developer_active)
	t.assert_false("改键 / Esc 保留系统入口", Settings.valid_key(KEY_ESCAPE))
	_test_config(t)
	main.queue_free()
	await tree.process_frame


func _press(viewport: Viewport, gamepad: bool) -> void:
	var event: InputEvent
	if gamepad:
		var button := InputEventJoypadButton.new()
		button.button_index = JOY_BUTTON_START
		event = button
	else:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_ESCAPE
		event = key
	event.pressed = true
	viewport.push_input(event)
	event.pressed = false
	viewport.push_input(event)


func _test_config(t: Variant) -> void:
	var settings := Settings.new()
	settings.path = "user://test-menu-settings-%d.cfg" % OS.get_process_id()
	settings.keys[0] = KEY_F3
	settings.volumes[1] = 40.0
	t.assert_equal("设置 / 实际写入配置", OK, settings.save_settings())
	settings.volumes[1] = 42.0
	t.assert_equal("设置 / 新值覆盖旧配置", OK, settings.save_settings())
	var loaded := Settings.new()
	loaded.path = settings.path
	loaded.load_settings()
	t.assert_true("设置 / 新实例重载真实音量与键位",
		loaded.volumes[1] == 42.0 and loaded.keys[0] == KEY_F3)
	var broken := ConfigFile.new()
	broken.set_value("audio", "Master", -3)
	broken.set_value("input", "turn_left", KEY_ESCAPE)
	broken.save(settings.path)
	loaded = Settings.new()
	loaded.path = settings.path
	loaded.load_settings()
	t.assert_true("设置 / 异常配置回退，Esc 不可覆盖",
		loaded.volumes[0] == 100.0 and loaded.keys[0] == KEY_Q)
	DirAccess.remove_absolute(settings.path)
