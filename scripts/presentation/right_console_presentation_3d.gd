class_name RightConsolePresentation3D
extends Node


# 外形、位置和角度都留在场景；本脚本只把旧右台状态映射到实体显示。
@export var destination_interface_path: NodePath
@export var information_label_path: NodePath
@export var input_label_path: NodePath
@export var feedback_label_path: NodePath
@export var lever_pivot_path: NodePath
@export_range(2.0, 35.0, 1.0) var lever_travel_degrees: float = 30.0
@export_range(0.03, 0.5, 0.01) var lever_forward_duration: float = 0.12
@export_range(0.03, 0.8, 0.01) var lever_return_duration: float = 0.22

# 本地音效节点在场景中配置；音效只跟随实际操作，不随显示刷新播放。
@onready var _keypad_audio_player := get_node_or_null(^"键盘音效") as AudioStreamPlayer
@onready var _verify_audio_player := get_node_or_null(^"验证音效") as AudioStreamPlayer
@onready var _lever_audio_player := get_node_or_null(^"拨杆音效") as AudioStreamPlayer

var _destination: DestinationControlInterface
var _information_label: Label3D
var _input_label: Label3D
var _feedback_label: Label3D
var _lever_pivot: Node3D
var _lever_hotspot: InteractionHotspot3D
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
			or _feedback_label == null \
			or _lever_pivot == null:
		push_error("右台实体展示缺少关键导出路径或节点类型错误。")
		return
	_lever_rest_rotation = _lever_pivot.rotation
	_lever_hotspot = _lever_pivot.get_parent() as InteractionHotspot3D
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
	_play_audio(_lever_audio_player)
	# 前进与回位全过程隐藏握柄高亮，仍由原动画锁防止重复提交。
	if _lever_hotspot != null:
		_lever_hotspot.set_hover_visual_enabled(false)
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


func play_keypad_sound() -> void:
	_play_audio(_keypad_audio_player)


func play_verify_sound() -> void:
	_play_audio(_verify_audio_player)


func _play_audio(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player):
		player.play()


func _finish_lever_animation() -> void:
	if _lever_pivot != null:
		_lever_pivot.rotation = _lever_rest_rotation
	_lever_animating = false
	if _lever_hotspot != null:
		_lever_hotspot.set_hover_visual_enabled(true)


func _on_destination_presentation_changed(snapshot: Dictionary) -> void:
	if _information_label == null or _input_label == null or _feedback_label == null:
		return
	var query := "—"
	match String(snapshot.query_status):
		"found":
			query = snapshot.query_floor
		"prefix":
			query = "输入中"
		"unknown":
			query = "未知地址"
		"ambiguous", "invalid":
			query = "档案配置需核对"
	var updated: String = snapshot.updated_at
	_information_label.text = (
		"当前位置 %s   执行目标 %s\n查询楼层 %s\n功能 %s\n区域 %s\n行政访问 %s\n电梯停靠状态 %s\n来源 %s\n更新时间 %s"
	) % [
		snapshot.current_floor, snapshot.execution_target, query,
		_short_text(snapshot.current_function), _short_text(snapshot.current_area),
		_short_text(snapshot.administrative_access_conditions), snapshot.elevator_stop,
		_short_text(("%s %s" % [snapshot.source, snapshot.source_version]).strip_edges()),
		_short_text(updated) if not updated.is_empty() else "未知",
	]
	_input_label.text = str(snapshot.input)
	_feedback_label.text = str(snapshot.feedback)


## 右台只展示短摘要，原始字段和完整来源保留在 W。
func _short_text(value: String, limit: int = 24) -> String:
	var line := value.replace("\r", " ").replace("\n", " ")
	return line.left(limit - 1) + "…" if line.length() > limit else line
