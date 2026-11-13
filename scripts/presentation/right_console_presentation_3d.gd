class_name RightConsolePresentation3D
extends Node

const SUMMARY_ROWS := {
	"current_function": ^"功能行",
	"current_area": ^"区域行",
	"administrative_access_conditions": ^"访问行",
}


# 外形、位置和角度都留在场景；本脚本只把旧右台状态映射到实体显示。
@export var destination_interface_path: NodePath
@export var information_screen_path: NodePath
@export var information_viewport_path: NodePath
@export var input_screen_path: NodePath
@export var input_viewport_path: NodePath
@export var information_label_path: NodePath
@export var current_floor_label_path: NodePath
@export var execution_target_label_path: NodePath
@export var source_label_path: NodePath
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
var _information_label: Label
var _current_floor_label: Label
var _execution_target_label: Label
var _source_label: Label
var _query_caption: Label
var _stop_badge: PanelContainer
var _summary_rows: Dictionary[String, HBoxContainer] = {}
var _input_label: Label
var _feedback_label: Label
var _lever_pivot: Node3D
var _lever_hotspot: InteractionHotspot3D
var _lever_rest_rotation: Vector3
var _lever_tween: Tween
var _lever_animating: bool = false


func _ready() -> void:
	_bind_presentation.call_deferred()


func _bind_presentation() -> void:
	_destination = get_node_or_null(destination_interface_path) as DestinationControlInterface
	_information_label = get_node_or_null(information_label_path) as Label
	_current_floor_label = get_node_or_null(current_floor_label_path) as Label
	_execution_target_label = get_node_or_null(execution_target_label_path) as Label
	_source_label = get_node_or_null(source_label_path) as Label
	_input_label = get_node_or_null(input_label_path) as Label
	_feedback_label = get_node_or_null(feedback_label_path) as Label
	_lever_pivot = get_node_or_null(lever_pivot_path) as Node3D
	if _destination == null or _information_label == null or _input_label == null \
			or _feedback_label == null or _current_floor_label == null \
			or _execution_target_label == null or _source_label == null \
			or _lever_pivot == null:
		push_error("右台实体展示缺少关键导出路径或节点类型错误。")
		return
	var summary := _information_label.get_parent()
	_query_caption = summary.get_node("查询标题") as Label
	_stop_badge = summary.get_node("停靠标记") as PanelContainer
	for key: String in SUMMARY_ROWS:
		_summary_rows[key] = summary.get_node(SUMMARY_ROWS[key]) as HBoxContainer
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
	# 显示接线异常时仍保留实体键、拨杆和业务联锁。
	var information_screen := get_node_or_null(information_screen_path) as ScreenSurface3D
	var information_viewport := get_node_or_null(information_viewport_path) as SubViewport
	var input_screen := get_node_or_null(input_screen_path) as ScreenSurface3D
	var input_viewport := get_node_or_null(input_viewport_path) as SubViewport
	if information_screen == null or input_screen == null \
			or not information_screen.bind_viewport(information_viewport) \
			or not input_screen.bind_viewport(input_viewport):
		push_error("右台摘要屏或数字 LCD 无法绑定现有显示视口。")


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
	_current_floor_label.text = str(snapshot.current_floor)
	_execution_target_label.text = str(snapshot.execution_target)
	_input_label.text = str(snapshot.input)
	_feedback_label.text = str(snapshot.feedback)
	if _feedback_label.text.is_empty() and snapshot.current_floor != "---":
		# 现有快照只在实际行驶时提供执行目标。
		_feedback_label.text = "运行中" if snapshot.execution_target != "---" else "已停靠"
	var found: bool = snapshot.query_status == "found"
	_query_caption.visible = found
	_stop_badge.visible = found
	_information_label.position.x = 86.0 if found else 26.0
	_information_label.add_theme_font_size_override("font_size", 34 if found else 27)
	_source_label.text = ""
	for key: String in _summary_rows:
		var row := _summary_rows[key]
		var value: String = snapshot[key]
		row.visible = found and value not in ["", "—", "未知", "未登记", "未记录"]
		(row.get_node("值") as Label).text = value.replace("\r", " ").replace("\n", " ")
	match String(snapshot.query_status):
		"found":
			_information_label.text = snapshot.query_floor
			(_stop_badge.get_node("值") as Label).text = snapshot.elevator_stop
			var origin := str(snapshot.source).strip_edges()
			var version: String = snapshot.source_version
			if not version.is_empty():
				origin += " v" + version
			var updated: String = snapshot.updated_at
			_source_label.text = " · ".join(PackedStringArray([origin, updated])) \
					if not origin.is_empty() and not updated.is_empty() else origin + updated
		"prefix":
			_information_label.text = "输入中"
		"unknown":
			_information_label.text = "未知地址"
		"ambiguous", "invalid":
			_information_label.text = "档案配置需核对"
		_:
			_information_label.text = "未查询"
