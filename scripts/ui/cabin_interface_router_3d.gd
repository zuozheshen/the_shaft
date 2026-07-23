class_name CabinInterfaceRouter3D
extends CanvasLayer


var _view_controller: CabinViewController3D
var _main_container: Control
var _right_container: Control
var _door_hint: Label
var _main_interface: ConsoleInterface
var _left_interface: BuildingTerminalInterface
var _right_interface: DestinationControlInterface


func _ready() -> void:
	_view_controller = get_parent() as CabinViewController3D
	if _view_controller == null:
		push_error("操作台界面层的父节点必须是三维操作舱视角控制器。")

	# 场景允许在 CanvasLayer 下增加统一的界面根节点；这里按稳定节点名递归查找，
	# 避免纯布局调整让三个操作台同时失去路由和业务连接。
	_main_container = _find_required_control("主操作台界面容器")
	_right_container = _find_required_control("右操作台界面容器")
	_door_hint = _get_required_node(^"门区提示", "Label") as Label
	_main_interface = _find_required_control("ConsoleInterface") as ConsoleInterface
	# LEFT 已迁入 3D 屏幕的 SubViewport，但仍由本路由器向运行层提供唯一实例。
	_left_interface = _view_controller.find_child(
		"BuildingTerminalInterface",
		true,
		false
	) as BuildingTerminalInterface if _view_controller != null else null
	if _left_interface == null:
		push_error("三维操作舱缺少左台 BuildingTerminalInterface。")
	_right_interface = _find_required_control("DestinationControlInterface") as DestinationControlInterface

	_configure_embedded_interfaces()
	_connect_view_signals()

	# 不相信场景文件里的初始 visible 值，始终按控制器的实际方向同步。
	if _view_controller != null:
		_show_direction(_view_controller.get_current_direction())
	else:
		_hide_all_interfaces()


func _connect_view_signals() -> void:
	if _view_controller == null:
		return
	if not _view_controller.turn_started.is_connected(_on_turn_started):
		_view_controller.turn_started.connect(_on_turn_started)
	if not _view_controller.facing_changed.is_connected(_on_facing_changed):
		_view_controller.facing_changed.connect(_on_facing_changed)


# 运行层只向路由器查询界面，不再重复了解 CanvasLayer 内部的布局路径。
func get_main_interface() -> ConsoleInterface:
	return _main_interface


func get_left_interface() -> BuildingTerminalInterface:
	return _left_interface


func get_right_interface() -> DestinationControlInterface:
	return _right_interface


func _configure_embedded_interfaces() -> void:
	# 三个实例一直留在场景树中；LEFT 始终渲染，主台和右台仍沿用覆盖层。
	if _main_interface != null:
		_main_interface.set_embedded_3d_mode(true)
		_main_interface.show()
	if _left_interface != null:
		_left_interface.set_embedded_3d_mode(true)
		_left_interface.show()
	if _right_interface != null:
		_right_interface.set_embedded_3d_mode(true)
		_right_interface.show()


func _on_turn_started(_direction: int, _direction_name: String) -> void:
	# UI 必须在 Tween 开始的同一帧消失，让玩家看见完整的 3D 转身过程。
	_hide_all_interfaces()


func _on_facing_changed(direction: int, _direction_name: String) -> void:
	_show_direction(direction)


func _show_direction(direction: int) -> void:
	_hide_all_interfaces()
	match direction:
		CabinViewController3D.FacingDirection.MAIN_CONSOLE:
			_set_container_enabled(_main_container, true)
		CabinViewController3D.FacingDirection.LEFT_CONSOLE:
			pass
		CabinViewController3D.FacingDirection.RIGHT_CONSOLE:
			_set_container_enabled(_right_container, true)
		CabinViewController3D.FacingDirection.ELEVATOR_DOOR:
			if _door_hint != null:
				_door_hint.show()
		_:
			push_error("操作台界面层收到未知方向：%s" % direction)


func _hide_all_interfaces() -> void:
	_set_container_enabled(_main_container, false)
	_set_container_enabled(_right_container, false)
	if _door_hint != null:
		_door_hint.hide()
		_door_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _set_container_enabled(container: Control, is_enabled: bool) -> void:
	if container == null:
		return
	container.visible = is_enabled
	container.mouse_filter = Control.MOUSE_FILTER_STOP if is_enabled \
			else Control.MOUSE_FILTER_IGNORE


func _get_required_control(node_path: NodePath) -> Control:
	return _get_required_node(node_path, "Control") as Control


func _find_required_control(node_name: String) -> Control:
	var control := find_child(node_name, true, false) as Control
	if control == null:
		push_error("操作台界面层缺少关键 Control 节点：%s" % node_name)
	return control


func _get_required_node(node_path: NodePath, expected_type: String) -> Node:
	var required_node := get_node_or_null(node_path)
	if required_node == null:
		push_error("操作台界面层缺少关键节点：%s" % node_path)
		return null
	if not required_node.is_class(expected_type):
		push_error("节点 %s 应为 %s，实际为 %s。" % [
			node_path,
			expected_type,
			required_node.get_class(),
		])
		return null
	return required_node
