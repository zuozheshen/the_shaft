class_name PassengerVisual3D
extends Node3D


@export var visual_root_path: NodePath
@export var sprite_path: NodePath
@export var contact_shadow_path: NodePath
@export var dialogue_focus_path: NodePath
@export var initial_profile: PassengerVisualProfile
@export var idle_enabled: bool = true

var _visual_root: Node3D
var _sprite: Sprite3D
var _contact_shadow: MeshInstance3D
var _dialogue_focus: Marker3D
var _current_profile: PassengerVisualProfile
var _base_visual_position: Vector3
var _base_sprite_scale: Vector3
var _base_sprite_position: Vector3
var _base_shadow_scale: Vector3
var _idle_amplitude: float = 0.0
var _idle_speed: float = 1.0
var _idle_time: float = 0.0
var _is_visual_ready: bool = false


func _ready() -> void:
	# 所有表现节点都由场景显式配置，避免名称搜索掩盖场景接线错误。
	_visual_root = _get_typed_node(
		visual_root_path,
		"Node3D",
		"纸片动画根"
	) as Node3D
	_sprite = _get_typed_node(
		sprite_path,
		"Sprite3D",
		"乘客纸片"
	) as Sprite3D
	_contact_shadow = _get_typed_node(
		contact_shadow_path,
		"MeshInstance3D",
		"接触阴影"
	) as MeshInstance3D
	_dialogue_focus = _get_typed_node(
		dialogue_focus_path,
		"Marker3D",
		"对话焦点"
	) as Marker3D

	if _visual_root == null \
			or _sprite == null \
			or _contact_shadow == null \
			or _dialogue_focus == null:
		push_error("乘客视觉节点配置不完整，将保留场景中的静态占位内容。")
		set_process(false)
		return

	# 缓存用户在场景中调好的基础值，后续 Profile 始终相对这些值应用。
	_base_visual_position = _visual_root.position
	_base_sprite_scale = _sprite.scale
	_base_sprite_position = _sprite.position
	_base_shadow_scale = _contact_shadow.scale
	_is_visual_ready = true

	if initial_profile != null:
		apply_profile(initial_profile)
	else:
		_update_processing()


func _process(delta: float) -> void:
	if not _is_visual_ready \
			or not idle_enabled \
			or _current_profile == null \
			or not is_visible_in_tree():
		return

	# 每帧从基础位置重算，只让纸片动画根上下起伏，避免累计误差与世界站位漂移。
	_idle_time += delta
	var vertical_offset := sin(_idle_time * _idle_speed) * _idle_amplitude
	_visual_root.position = _base_visual_position + Vector3.UP * vertical_offset


func apply_profile(profile: PassengerVisualProfile) -> bool:
	if profile == null:
		push_warning("乘客视觉拒绝空的表现 Profile。")
		return false
	if not _is_visual_ready:
		push_warning("乘客视觉节点尚未准备完成，无法应用 Profile。")
		return false

	reset_idle_pose()
	_current_profile = profile
	_sprite.texture = profile.texture
	_sprite.modulate = profile.tint
	_sprite.scale = Vector3(
		_base_sprite_scale.x * profile.visual_scale.x,
		_base_sprite_scale.y * profile.visual_scale.y,
		_base_sprite_scale.z
	)
	_sprite.position = _base_sprite_position + profile.sprite_offset
	_idle_amplitude = profile.idle_amplitude
	_idle_speed = profile.idle_speed

	var focus_position := _dialogue_focus.position
	focus_position.y = profile.dialogue_focus_height
	_dialogue_focus.position = focus_position
	_contact_shadow.scale = Vector3(
		_base_shadow_scale.x * profile.shadow_scale.x,
		_base_shadow_scale.y,
		_base_shadow_scale.z * profile.shadow_scale.y
	)
	_update_processing()
	return true


func get_current_profile() -> PassengerVisualProfile:
	return _current_profile


func set_passenger_visible(is_visible: bool) -> void:
	visible = is_visible
	_update_processing()


func set_idle_enabled(is_enabled: bool) -> void:
	idle_enabled = is_enabled
	if not idle_enabled:
		reset_idle_pose()
	_update_processing()


func reset_idle_pose() -> void:
	_idle_time = 0.0
	if _visual_root != null:
		_visual_root.position = _base_visual_position


func get_dialogue_focus() -> Marker3D:
	return _dialogue_focus


func get_passenger_id() -> StringName:
	if _current_profile == null:
		return StringName()
	return _current_profile.passenger_id


func _update_processing() -> void:
	set_process(
		_is_visual_ready
				and idle_enabled
				and visible
				and _current_profile != null
	)


func _get_typed_node(
		node_path: NodePath,
		expected_class: StringName,
		display_name: String
) -> Node:
	if node_path.is_empty():
		push_error("乘客视觉缺少%s的 NodePath 配置。" % display_name)
		return null
	var candidate := get_node_or_null(node_path)
	if candidate == null:
		push_error("乘客视觉找不到%s：%s" % [display_name, node_path])
		return null
	if not candidate.is_class(expected_class):
		push_error("乘客视觉的%s应为 %s，实际为 %s。" % [
			display_name,
			expected_class,
			candidate.get_class(),
		])
		return null
	return candidate
