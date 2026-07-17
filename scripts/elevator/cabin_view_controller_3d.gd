class_name CabinViewController3D
extends Node3D


signal turn_started(direction: int, direction_name: String)
signal facing_changed(direction: int, direction_name: String)


# 四个方向按左转顺序组成明确的环，不依赖场景树中的节点排列。
enum FacingDirection {
	MAIN_CONSOLE,
	LEFT_CONSOLE,
	ELEVATOR_DOOR,
	RIGHT_CONSOLE,
}


const TURN_LEFT_ACTION: StringName = &"turn_left"
const TURN_RIGHT_ACTION: StringName = &"turn_right"
const DIRECTION_NAMES: Array[String] = [
	"主操作台",
	"左操作台",
	"电梯门",
	"右操作台",
]
const DIRECTION_ANCHOR_PATHS: Array[NodePath] = [
	^"观察方向/主操作台方向",
	^"观察方向/左操作台方向",
	^"观察方向/电梯门方向",
	^"观察方向/右操作台方向",
]


@export_range(0.05, 2.0, 0.05) var turn_duration: float = 0.4

var _current_direction: int = FacingDirection.MAIN_CONSOLE
var _is_turning: bool = false
var _camera_pivot: Node3D
var _player_camera: Camera3D
var _current_direction_label: Label
var _operation_hint_label: Label
var _direction_anchors: Array[Marker3D] = []


func _ready() -> void:
	# 集中检查节点路径，让场景结构被误改时能在 Output 中直接定位问题。
	_camera_pivot = _get_required_node(^"玩家视角/摄像机旋转轴", "Node3D") as Node3D
	_player_camera = _get_required_node(^"玩家视角/摄像机旋转轴/玩家摄像机", "Camera3D") as Camera3D
	_current_direction_label = _get_required_node(^"调试界面/当前方向文本", "Label") as Label
	_operation_hint_label = _get_required_node(^"调试界面/操作提示文本", "Label") as Label

	_direction_anchors.resize(FacingDirection.size())
	for direction: int in range(FacingDirection.size()):
		var anchor := get_node_or_null(DIRECTION_ANCHOR_PATHS[direction]) as Marker3D
		_direction_anchors[direction] = anchor
		if anchor == null:
			push_error("三维操作舱缺少方向节点：%s" % DIRECTION_ANCHOR_PATHS[direction])

	_validate_input_actions()
	_set_initial_facing()
	_update_debug_interface()


func _input(event: InputEvent) -> void:
	# 使用 _input 抢在 GUI 之前处理固定转向，按钮或 LineEdit 聚焦时 Q / E 仍然有效。
	var turn_step: int = 0
	if InputMap.has_action(TURN_LEFT_ACTION) and event.is_action_pressed(TURN_LEFT_ACTION):
		turn_step = 1
	elif InputMap.has_action(TURN_RIGHT_ACTION) and event.is_action_pressed(TURN_RIGHT_ACTION):
		turn_step = -1
	else:
		return

	# 转向期间消费但不排队新的 Q / E 输入，避免快速按键造成角度错乱。
	get_viewport().set_input_as_handled()
	if _is_turning:
		return
	_start_turn(turn_step)


# 返回方向枚举的当前值，供后续操作台路由脚本查询。
func get_current_direction() -> int:
	return _current_direction


func get_current_direction_name() -> String:
	return DIRECTION_NAMES[_current_direction]


func is_turning() -> bool:
	return _is_turning


func _start_turn(turn_step: int) -> void:
	if _camera_pivot == null:
		push_error("无法转向：缺少节点 玩家视角/摄像机旋转轴。")
		return

	var target_direction := wrapi(
		_current_direction + turn_step,
		0,
		FacingDirection.size()
	)
	var target_anchor := _direction_anchors[target_direction]
	if target_anchor == null:
		push_error("无法转向：缺少节点 %s。" % DIRECTION_ANCHOR_PATHS[target_direction])
		return

	_is_turning = true
	turn_started.emit(target_direction, DIRECTION_NAMES[target_direction])

	var start_angle := _camera_pivot.rotation.y
	var exact_target_angle := target_anchor.rotation.y
	# angle_difference 把目标换算为离当前角度最近的等价角，避免跨界时绕行 270 度。
	var shortest_target_angle := start_angle + angle_difference(start_angle, exact_target_angle)
	var turn_tween := create_tween()
	turn_tween.set_trans(Tween.TRANS_SINE)
	turn_tween.set_ease(Tween.EASE_IN_OUT)
	turn_tween.tween_property(
		_camera_pivot,
		^"rotation:y",
		shortest_target_angle,
		turn_duration
	)
	turn_tween.tween_callback(
		_finish_turn.bind(target_direction, exact_target_angle)
	)


func _finish_turn(target_direction: int, exact_target_angle: float) -> void:
	# 每次结束都对齐 Marker3D 的原始角度，防止多次 Tween 后出现累计误差。
	if _camera_pivot != null:
		_camera_pivot.rotation.y = exact_target_angle
	_current_direction = target_direction
	_is_turning = false
	_update_debug_interface()
	facing_changed.emit(_current_direction, get_current_direction_name())


func _set_initial_facing() -> void:
	if _camera_pivot == null:
		return
	var initial_anchor := _direction_anchors[FacingDirection.MAIN_CONSOLE]
	if initial_anchor == null:
		return
	_camera_pivot.rotation.y = initial_anchor.rotation.y


func _update_debug_interface() -> void:
	if _current_direction_label != null:
		_current_direction_label.text = "当前方向：%s" % get_current_direction_name()
	if _operation_hint_label != null:
		_operation_hint_label.text = "Q 左转　E 右转"


func _validate_input_actions() -> void:
	if not InputMap.has_action(TURN_LEFT_ACTION):
		push_warning("缺少 Input Map 动作：turn_left（预期绑定 Q）。")
	if not InputMap.has_action(TURN_RIGHT_ACTION):
		push_warning("缺少 Input Map 动作：turn_right（预期绑定 E）。")


func _get_required_node(node_path: NodePath, expected_type: String) -> Node:
	var required_node := get_node_or_null(node_path)
	if required_node == null:
		push_error("三维操作舱缺少关键节点：%s" % node_path)
		return null
	if not required_node.is_class(expected_type):
		push_error("节点 %s 应为 %s，实际为 %s。" % [
			node_path,
			expected_type,
			required_node.get_class(),
		])
		return null
	return required_node
