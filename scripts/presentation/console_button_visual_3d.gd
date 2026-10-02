class_name ConsoleButtonVisual3D
extends Node3D


@export var press_axis_path: NodePath = NodePath("按钮按压轴")
@export var feedback_enabled: bool = true
@export var press_distance: float = 0.003
@export var press_down_duration: float = 0.06
@export var press_return_duration: float = 0.10

var _press_axis: Node3D
var _rest_position: Vector3
var _press_tween: Tween


func _ready() -> void:
	if not press_axis_path.is_empty():
		_press_axis = get_node_or_null(press_axis_path) as Node3D
	if is_instance_valid(_press_axis):
		# 始终从场景中的原始位置往返，重复按压不会积累位移。
		_rest_position = _press_axis.position


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
