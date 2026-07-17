class_name RuntimeConnector3D
extends Node


@export var game_runtime_path: NodePath = ^"../游戏运行层"
@export var elevator_cabin_path: NodePath = ^"../三维操作舱"

var _game_runtime: GameRuntime
var _demo_flow_manager: DemoFlowManager
var _main_interface: ConsoleInterface
var _left_interface: BuildingTerminalInterface
var _right_interface: DestinationControlInterface


func _ready() -> void:
	_game_runtime = get_node_or_null(game_runtime_path) as GameRuntime
	if _game_runtime == null:
		push_error("运行层连接器找不到节点：%s" % game_runtime_path)
		return

	_demo_flow_manager = _game_runtime.get_demo_flow_manager()
	if _demo_flow_manager == null:
		push_error("运行层连接器无法取得唯一的演示流程管理器。")
		return

	var elevator_cabin := get_node_or_null(elevator_cabin_path)
	if elevator_cabin == null:
		push_error("运行层连接器找不到节点：%s" % elevator_cabin_path)
		return

	# 依赖只在主场景初始化时注入一次；转向和界面显隐不会重新连接业务信号。
	_main_interface = _get_required_interface(
		elevator_cabin,
		^"操作台界面层/主操作台界面容器/ConsoleInterface",
		"ConsoleInterface"
	) as ConsoleInterface
	_left_interface = _get_required_interface(
		elevator_cabin,
		^"操作台界面层/左操作台界面容器/BuildingTerminalInterface",
		"BuildingTerminalInterface"
	) as BuildingTerminalInterface
	_right_interface = _get_required_interface(
		elevator_cabin,
		^"操作台界面层/右操作台界面容器/DestinationControlInterface",
		"DestinationControlInterface"
	) as DestinationControlInterface

	if _main_interface == null or _left_interface == null or _right_interface == null:
		return
	_main_interface.set_demo_flow_manager(_demo_flow_manager)
	_left_interface.set_demo_flow_manager(_demo_flow_manager)
	_right_interface.set_demo_flow_manager(_demo_flow_manager)


func get_demo_flow_manager() -> DemoFlowManager:
	return _demo_flow_manager


func _get_required_interface(
		elevator_cabin: Node,
		interface_path: NodePath,
		expected_class_name: String
) -> Node:
	var interface_node := elevator_cabin.get_node_or_null(interface_path)
	if interface_node == null:
		push_error("运行层连接器缺少操作台界面：%s" % interface_path)
		return null
	if not interface_node.is_class("Control"):
		push_error("节点 %s 必须是 Control，实际为 %s。" % [
			interface_path,
			interface_node.get_class(),
		])
		return null
	if interface_node.get_script() == null:
		push_error("操作台界面 %s 缺少脚本 %s。" % [interface_path, expected_class_name])
		return null
	return interface_node
