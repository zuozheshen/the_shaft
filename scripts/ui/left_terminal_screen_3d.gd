class_name LeftTerminalScreen3D
extends Node3D


@export var screen_mesh_path: NodePath = ^"左台屏幕"
@export var interaction_area_path: NodePath = ^"左台屏幕交互区"
@export var sub_viewport_path: NodePath = ^"左台界面视口"
@export var player_camera_path: NodePath
@export var view_controller_path: NodePath
@export_flags_3d_physics var interaction_collision_mask: int = 1 << 7
@export_range(1.0, 50.0, 0.5) var ray_length: float = 10.0

var _screen_mesh: MeshInstance3D
var _interaction_area: Area3D
var _sub_viewport: SubViewport
var _player_camera: Camera3D
var _view_controller: CabinViewController3D
var _pointer_inside: bool = false
var _last_viewport_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_screen_mesh = _get_required_node(screen_mesh_path, "MeshInstance3D") as MeshInstance3D
	_interaction_area = _get_required_node(interaction_area_path, "Area3D") as Area3D
	_sub_viewport = _get_required_node(sub_viewport_path, "SubViewport") as SubViewport
	_player_camera = _get_required_node(player_camera_path, "Camera3D") as Camera3D
	_view_controller = _get_required_node(view_controller_path, "Node3D") \
			as CabinViewController3D

	if _view_controller == null:
		push_error("左台屏幕控制器没有连接 CabinViewController3D。")
	else:
		if not _view_controller.turn_started.is_connected(_on_turn_started):
			_view_controller.turn_started.connect(_on_turn_started)
		if not _view_controller.facing_changed.is_connected(_on_facing_changed):
			_view_controller.facing_changed.connect(_on_facing_changed)
	if _screen_mesh == null or not _screen_mesh.mesh is QuadMesh:
		push_error("左台屏幕必须使用 QuadMesh，才能按实际尺寸换算点击坐标。")
		return
	_configure_screen_material()


func _exit_tree() -> void:
	_clear_sub_viewport_hover()


func _input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	if not _can_forward_input():
		_clear_sub_viewport_hover()
		return

	var mouse_event := event as InputEventMouse
	var viewport_position: Vector2 = _get_viewport_position(mouse_event.position)
	if viewport_position.x < 0.0:
		# 鼠标离开屏幕时发送一次视口外坐标，清除 Button 的残留 hover。
		_clear_sub_viewport_hover()
		var mouse_button := event as InputEventMouseButton
		if mouse_button != null and not mouse_button.pressed:
			_forward_mouse_event(mouse_button, Vector2(-1.0, -1.0))
		return

	_pointer_inside = true
	_last_viewport_position = viewport_position
	_forward_mouse_event(event, viewport_position)
	get_viewport().set_input_as_handled()


func _configure_screen_material() -> void:
	if _screen_mesh == null or _sub_viewport == null:
		return
	# 屏幕使用独立材质，避免把视口纹理意外写进机舱其他共享网格。
	var screen_material := StandardMaterial3D.new()
	screen_material.resource_local_to_scene = true
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen_material.albedo_texture = _sub_viewport.get_texture()
	_screen_mesh.material_override = screen_material


func _can_forward_input() -> bool:
	# 屏幕始终渲染；只有正对左台且转向结束后才允许输入，避免转身时误触。
	return _player_camera != null \
			and _player_camera.is_current() \
			and _view_controller != null \
			and not _view_controller.is_turning() \
			and _view_controller.get_current_direction() \
					== CabinViewController3D.FacingDirection.LEFT_CONSOLE


func _get_viewport_position(mouse_position: Vector2) -> Vector2:
	if _player_camera == null or _player_camera.get_world_3d() == null:
		return Vector2(-1.0, -1.0)
	var ray_origin := _player_camera.project_ray_origin(mouse_position)
	var ray_direction := _player_camera.project_ray_normal(mouse_position)
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * ray_length
	)
	query.collision_mask = interaction_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := _player_camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty() or result.get("collider") != _interaction_area:
		return Vector2(-1.0, -1.0)

	var quad_mesh := _screen_mesh.mesh as QuadMesh
	var local_hit := _screen_mesh.to_local(result.get("position", Vector3.ZERO))
	# QuadMesh 的局部 X/Y 对应屏幕 U/V；视口 Y 轴向下，因此需要翻转 V。
	var uv := Vector2(
		local_hit.x / quad_mesh.size.x + 0.5,
		0.5 - local_hit.y / quad_mesh.size.y
	)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1.0, -1.0)
	return uv * Vector2(_sub_viewport.size)


func _forward_mouse_event(source_event: InputEvent, viewport_position: Vector2) -> void:
	if _sub_viewport == null:
		return
	var forwarded_event := source_event.duplicate() as InputEventMouse
	forwarded_event.position = viewport_position
	forwarded_event.global_position = viewport_position
	_sub_viewport.push_input(forwarded_event, true)


func _clear_sub_viewport_hover() -> void:
	if not _pointer_inside or _sub_viewport == null:
		return
	_pointer_inside = false
	var exit_event := InputEventMouseMotion.new()
	exit_event.position = Vector2(-1.0, -1.0)
	exit_event.global_position = exit_event.position
	exit_event.relative = exit_event.position - _last_viewport_position
	_sub_viewport.push_input(exit_event, true)


func _on_turn_started(_direction: int, _direction_name: String) -> void:
	_clear_sub_viewport_hover()


func _on_facing_changed(_direction: int, _direction_name: String) -> void:
	if not _can_forward_input():
		_clear_sub_viewport_hover()


func _get_required_node(node_path: NodePath, expected_class: String) -> Node:
	if node_path.is_empty():
		push_error("左台屏幕控制器缺少 %s 的 NodePath 配置。" % expected_class)
		return null
	var required_node := get_node_or_null(node_path)
	if required_node == null:
		push_error("左台屏幕控制器找不到节点：%s" % node_path)
		return null
	if not required_node.is_class(expected_class):
		push_error("节点 %s 应为 %s，实际为 %s。" % [
			node_path,
			expected_class,
			required_node.get_class(),
		])
		return null
	return required_node
