extends VerificationTerminal3D
## 预览专用：同一真实 Control 树在根画布与独立 SubViewport 之间切换。
var projected := false
var tilted := false
var gui: SubViewport
var surface: MeshInstance3D
var _previous_pixel := Vector2.ZERO
var _mouse_down := false
var _has_pixel := false
var _forwarded := 0

func _ready() -> void:
	super._ready()
	gui = SubViewport.new()
	gui.name = "GateGUI"
	gui.disable_3d = true
	gui.render_target_update_mode = SubViewport.UPDATE_DISABLED
	gui.size_2d_override_stretch = true
	add_child(gui)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.albedo_texture = gui.get_texture()
	material.no_depth_test = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.68, 0.88)
	surface = MeshInstance3D.new()
	surface.name = "GateScreen"
	surface.mesh = quad
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.position.z = 0.025
	surface.hide()
	shell.add_child(surface)
	get_window().focus_exited.connect(_cancel_pointer)

func set_projected(value: bool) -> void:
	if value == projected:
		return
	_cancel_pointer()
	var focus := screen.get_viewport().gui_get_focus_owner()
	projected = value
	screen.reparent(gui if projected else input_shield, false)
	gui.render_target_update_mode = SubViewport.UPDATE_ALWAYS if projected else SubViewport.UPDATE_DISABLED
	surface.visible = projected
	_update_layout()
	if is_instance_valid(focus) and screen.is_ancestor_of(focus):
		focus.grab_focus()
	elif is_input_captured():
		workspace.directory_button.grab_focus()
	print("W GATE mode=", "3D" if projected else "CanvasLayer", " logical=", screen.size, " texture=", gui.size)

func _update_layout() -> void:
	super._update_layout()
	if not projected or not is_instance_valid(surface):
		shell.rotation.x = 0.0
		return
	var rect := get_screen_rect()
	var logical := Vector2i(rect.size.round()).max(Vector2i(2, 2))
	var pixel_scale := get_viewport().get_screen_transform().get_scale()
	var physical := Vector2i((Vector2(logical) * pixel_scale).round()).max(Vector2i(2, 2))
	if gui.size != physical or gui.size_2d_override != logical:
		gui.size = physical
		gui.size_2d_override = logical
	screen.position = Vector2.ZERO
	screen.size = Vector2(logical)
	# 原方案的字级补偿基于根窗口；保留同样的字号供画质对照。
	var scale_x := maxf(0.5, pixel_scale.x)
	workspace.theme.default_font_size = maxi(18, roundi(16.0 / scale_x))
	var t := 1.0 - open_progress
	shell.position.x = 0.0
	shell.position.y = -get_viewport().get_visible_rect().size.y * shell.scale.y / rect.size.y * t
	var angle := deg_to_rad(-28.0 if tilted else 0.0)
	angle = lerpf(angle, deg_to_rad(-68.0), t)
	var offset := Vector3(0.0, 0.53 * shell.scale.y, 0.0)
	shell.position += offset.rotated(Vector3.RIGHT, angle) - offset
	shell.rotation.x = angle
	gui.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open_progress > 0.0 else SubViewport.UPDATE_DISABLED

func _process(delta: float) -> void:
	if projected and open_progress < 1.0:
		return
	super._process(delta)

func set_open(value: bool) -> void:
	if not value:
		_cancel_pointer()
	super.set_open(value)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode in [KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9]:
		return
	if not projected or not is_input_captured() or event.is_action(TOGGLE_ACTION):
		super._input(event)
		return
	if open_progress < 1.0 or not target_open:
		if event.is_action_pressed(&"interact_cancel") or event.is_action_pressed(&"ui_cancel"):
			set_open(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse:
		_forward_pointer(event)
	elif event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if event.pressed:
			_held_keys[code] = true
		else:
			_held_keys.erase(code)
		if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
			_cancel_pointer()
			if not workspace.cancel_statement_selection():
				set_open(false)
		elif not event.pressed or not event.is_echo() or code != KEY_TAB:
			gui.push_input(event)
	else:
		# 手柄保持既有一次确认与轮询，Workspace 读取自己的 GUI 焦点。
		super._input(event)
	get_viewport().set_input_as_handled()

func _forward_pointer(event: InputEventMouse) -> void:
	var camera := get_parent() as Camera3D
	var origin := surface.to_local(camera.project_ray_origin(event.position))
	var sample := surface.to_local(camera.project_ray_origin(event.position)
		+ camera.project_ray_normal(event.position))
	var direction := sample - origin
	if absf(direction.z) < 0.00001 or -origin.z / direction.z <= 0.0:
		_cancel_pointer()
		return
	var point := origin - direction * (origin.z / direction.z)
	var extent := (surface.mesh as QuadMesh).size
	var uv := Vector2(0.5 + point.x / extent.x, 0.5 - point.y / extent.y)
	var inside := Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv)
	if not inside and not _mouse_down:
		return
	var mouse := event.duplicate() as InputEventMouse
	# push_input 接收 SubViewport 本地坐标，GUI 继续应用它自己的 2D 缩放。
	var pixel := uv * Vector2(gui.size)
	mouse.position = pixel
	mouse.global_position = pixel
	if mouse is InputEventMouseMotion:
		mouse.relative = pixel - _previous_pixel if _has_pixel else Vector2.ZERO
	_previous_pixel = pixel
	_has_pixel = true
	if mouse is InputEventMouseButton and mouse.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = mouse.pressed
	gui.push_input(mouse, true)
	_forwarded += 1

func _cancel_pointer() -> void:
	if not is_instance_valid(workspace):
		return
	for window: DocumentWindow in workspace.windows.values():
		window.cancel_drag()
		window.cancel_statement_selection()
	if _mouse_down and is_instance_valid(gui):
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = -Vector2.ONE
		release.global_position = release.position
		gui.push_input(release, true)
	_mouse_down = false
	_has_pixel = false
