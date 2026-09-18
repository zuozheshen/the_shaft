class_name RightConsolePresentation3D
extends Node


# 外形、位置和角度都留在场景；本脚本只把旧右台状态映射到实体显示。
@export var destination_interface_path: NodePath
@export var information_label_path: NodePath
@export var input_label_path: NodePath
@export var feedback_label_path: NodePath
@export var lever_pivot_path: NodePath
@export_range(2.0, 35.0, 1.0) var lever_travel_degrees: float = 16.0
@export_range(0.03, 0.5, 0.01) var lever_forward_duration: float = 0.12
@export_range(0.03, 0.8, 0.01) var lever_return_duration: float = 0.22

var _destination: DestinationControlInterface
var _information_label: Label3D
var _input_label: Label3D
var _feedback_label: Label3D
var _lever_pivot: Node3D
var _lever_rest_rotation: Vector3
var _lever_tween: Tween
var _lever_animating: bool = false


func _ready() -> void:
	_bind_presentation.call_deferred()


func _bind_presentation() -> void:
	_destination = get_node_or_null(destination_interface_path) as DestinationControlInterface
	_information_label = get_node_or_null(information_label_path) as Label3D
	_input_label = get_node_or_null(input_label_path) as Label3D
	_feedback_label = get_node_or_null(feedback_label_path) as Label3D
	_lever_pivot = get_node_or_null(lever_pivot_path) as Node3D
	if _destination == null or _information_label == null or _input_label == null \
			or _feedback_label == null or _lever_pivot == null:
		push_error("右台实体展示缺少关键导出路径或节点类型错误。")
		return
	_lever_rest_rotation = _lever_pivot.rotation
	if not _destination.destination_presentation_changed.is_connected(
			_on_destination_presentation_changed
	):
		_destination.destination_presentation_changed.connect(
			_on_destination_presentation_changed
		)
	_on_destination_presentation_changed(
		_destination.get_destination_presentation()
	)


func request_submit() -> void:
	if _destination == null or _lever_pivot == null or _lever_animating:
		return
	# 业务提交只发生在按下这一刻；Tween 前进和回位都不触发第二次提交。
	_destination.request_submit_destination()
	_lever_animating = true
	if _lever_tween != null and _lever_tween.is_valid():
		_lever_tween.kill()
	_lever_pivot.rotation = _lever_rest_rotation
	_lever_tween = create_tween()
	_lever_tween.set_trans(Tween.TRANS_QUAD)
	_lever_tween.set_ease(Tween.EASE_OUT)
	_lever_tween.tween_property(
		_lever_pivot,
		^"rotation:z",
		_lever_rest_rotation.z + deg_to_rad(lever_travel_degrees),
		lever_forward_duration
	)
	_lever_tween.set_ease(Tween.EASE_IN_OUT)
	_lever_tween.tween_property(
		_lever_pivot,
		^"rotation:z",
		_lever_rest_rotation.z,
		lever_return_duration
	)
	_lever_tween.tween_callback(_finish_lever_animation)


func is_lever_animating() -> bool:
	return _lever_animating


func _finish_lever_animation() -> void:
	if _lever_pivot != null:
		_lever_pivot.rotation = _lever_rest_rotation
	_lever_animating = false


func _on_destination_presentation_changed(snapshot: Dictionary) -> void:
	if _information_label == null or _input_label == null or _feedback_label == null:
		return
	_information_label.text = (
		"当前楼层：%s\n系统推荐：%s\n目标楼层：%s\n地址状态：%s\n"
		+ "派单关联度：%s\n稳定度影响：%s"
	) % [
		snapshot.get("current_floor", "---"),
		snapshot.get("recommended", "—"),
		snapshot.get("validated_floor", "---"),
		snapshot.get("address_status", "未验证"),
		snapshot.get("relevance", "—"),
		snapshot.get("stability", "—"),
	]
	_input_label.text = str(snapshot.get("input", ""))
	_feedback_label.text = str(snapshot.get("feedback", ""))
