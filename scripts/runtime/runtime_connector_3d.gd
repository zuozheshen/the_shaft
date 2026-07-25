class_name RuntimeConnector3D
extends Node


@export var game_runtime_path: NodePath = ^"../游戏运行层"
@export var elevator_cabin_path: NodePath = ^"../三维操作舱"

var _game_runtime: GameRuntime
var _demo_flow_manager: DemoFlowManager
var _main_interface: ConsoleInterface
var _left_interface: BuildingTerminalInterface
var _right_interface: DestinationControlInterface
var _monitor_camera_controller: MonitorCameraController3D


func _ready() -> void:
	# 同级实例的 _ready 顺序不应成为依赖；延迟到整棵场景树初始化完成后再注入业务数据。
	_connect_runtime.call_deferred()


func _connect_runtime() -> void:
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

	# 由界面路由器封装布局路径，节点树增加“界面根”等容器时不会切断业务注入。
	var interface_router := elevator_cabin.find_child(
		"操作台界面层",
		true,
		false
	) as CabinInterfaceRouter3D
	if interface_router == null:
		push_error("运行层连接器找不到操作台界面路由器。")
		return

	# 监控属于表现层；缺失时仅退回文字画面，不能阻断三个操作台的业务注入。
	_monitor_camera_controller = elevator_cabin.find_child(
		"监控渲染系统",
		true,
		false
	) as MonitorCameraController3D
	if _monitor_camera_controller == null:
		push_warning("运行层连接器找不到 MonitorCameraController3D，主台将保留文字监控。")

	_main_interface = interface_router.get_main_interface()
	_left_interface = interface_router.get_left_interface()
	_right_interface = interface_router.get_right_interface()

	if _main_interface == null or _left_interface == null or _right_interface == null:
		push_error("运行层连接器无法取得完整的三个操作台界面。")
		return
	_main_interface.set_demo_flow_manager(_demo_flow_manager)
	_left_interface.set_demo_flow_manager(_demo_flow_manager)
	_right_interface.set_demo_flow_manager(_demo_flow_manager)
	if _monitor_camera_controller != null:
		_monitor_camera_controller.setup(_main_interface, interface_router)


func get_demo_flow_manager() -> DemoFlowManager:
	return _demo_flow_manager
