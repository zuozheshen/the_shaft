class_name ConsoleButtonVisual3D
extends Node3D


@export var press_axis_path: NodePath = NodePath("按钮按压轴")
@export var feedback_enabled: bool = true
@export var press_distance: float = 0.003
@export var press_down_duration: float = 0.06
@export var press_return_duration: float = 0.10
# 可选帽材质只反映已有 CAM 选中态，不参与按钮业务。
@export var cap_unselected_material: StandardMaterial3D
@export var cap_selected_material: StandardMaterial3D

var _press_axis: Node3D
var _rest_position: Vector3
var _press_tween: Tween
var _cap_meshes: Array[MeshInstance3D] = []
var _unselected_material: StandardMaterial3D
var _selected_material: StandardMaterial3D


func _ready() -> void:
	if not press_axis_path.is_empty():
		_press_axis = get_node_or_null(press_axis_path) as Node3D
	if is_instance_valid(_press_axis):
		# 始终从场景中的原始位置往返，重复按压不会积累位移。
		_rest_position = _press_axis.position
		if cap_unselected_material != null and cap_selected_material != null:
			# 在自有帽轴下面查找视觉 Mesh；Gameplay 不依赖 GLB 内部名称。
			for node in _press_axis.find_children("", "MeshInstance3D", true, false):
				_cap_meshes.append(node as MeshInstance3D)
			# 两颗 CAM 共用几何，但状态材质按实例隔离。
			_unselected_material = cap_unselected_material.duplicate() as StandardMaterial3D
			_selected_material = cap_selected_material.duplicate() as StandardMaterial3D
			set_selected(false)


func set_selected(selected: bool) -> void:
	var material := _selected_material if selected else _unselected_material
	if material == null:
		return
	for cap_mesh in _cap_meshes:
		if is_instance_valid(cap_mesh):
			cap_mesh.material_override = material


func play_press() -> void:
	if not feedback_enabled or not is_instance_valid(_press_axis):
		return
	_reset_press()
	_press_tween = create_tween()
	_press_tween.tween_property(
		_press_axis, "position", _rest_position + Vector3.DOWN * press_distance,
		press_down_duration
	)
	_press_tween.tween_property(_press_axis, "position", _rest_position, press_return_duration)


func _reset_press() -> void:
	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()
	if is_instance_valid(_press_axis):
		_press_axis.position = _rest_position


func _exit_tree() -> void:
	_reset_press()
