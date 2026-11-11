class_name RuntimeConnector3D
extends Node

const AudioShutdown := preload("res://scripts/runtime/audio_shutdown.gd")


@export var game_runtime_path: NodePath = ^"../游戏运行层"
@export var elevator_cabin_path: NodePath = ^"../三维操作舱"

var _owns_close_request: bool = false
var _previous_auto_accept_quit: bool = true
var _quit_requested: bool = false

var _game_runtime: GameRuntime
var _demo_flow_manager: DemoFlowManager
var _main_interface: ConsoleInterface
var _left_interface: BuildingTerminalInterface
var _right_interface: DestinationControlInterface
var _monitor_stage_controller: MonitorStageController3D
var _monitor_presentation_coordinator: MonitorPresentationCoordinator3D
var _monitor_camera_controller: MonitorCameraController3D


func _ready() -> void:
	# 同级实例的 _ready 顺序不应成为依赖；延迟到整棵场景树初始化完成后再注入业务数据。
	_connect_runtime.call_deferred()


func _exit_tree() -> void:
	if _owns_close_request:
		var tree := get_tree()
		if tree.root.close_requested.is_connected(request_quit):
			tree.root.close_requested.disconnect(request_quit)
		tree.auto_accept_quit = _previous_auto_accept_quit


func request_quit(exit_code: int = 0) -> bool:
	# 关闭按钮、程序退出共用同一条收尾路径；重复请求不会启动第二次清理。
	if _quit_requested:
		return false
	_quit_requested = true
	var tree := get_tree()
	tree.paused = true
	var released := await AudioShutdown.stop_and_wait(get_parent(), tree)
	if released:
		print("AUDIO SHUTDOWN COMPLETE")
	else:
		push_error("音频退出清理超时：仍有播放实例未释放。")
	tree.quit(exit_code if released else 1)
	return released


func _connect_runtime() -> void:
	# 只接管真正主场景的根窗口；测试中临时实例化的操作舱不改变全局关闭策略。
	var tree := get_tree()
	if get_parent() == tree.current_scene and not _owns_close_request:
		_previous_auto_accept_quit = tree.auto_accept_quit
		tree.auto_accept_quit = false
		tree.root.close_requested.connect(request_quit)
		_owns_close_request = true
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

	_main_interface = interface_router.get_main_interface()
	_left_interface = interface_router.get_left_interface()
	_right_interface = interface_router.get_right_interface()

	if _main_interface == null or _left_interface == null or _right_interface == null:
		push_error("运行层连接器无法取得完整的三个操作台界面。")
		return
	_main_interface.set_demo_flow_manager(_demo_flow_manager)
	_left_interface.set_demo_flow_manager(_demo_flow_manager)
	_right_interface.set_demo_flow_manager(_demo_flow_manager)

	# W 只取得 #91 的受限 Callable 端口；生命周期通知由应用层转发。
	var verification_terminal := elevator_cabin.find_child("核验终端", true, false) as VerificationTerminal3D
	if verification_terminal != null:
		verification_terminal.set_workspace_port(_demo_flow_manager.get_document_workspace_port())
		_demo_flow_manager.document_session_changed.connect(verification_terminal.reset_document_session)
		_demo_flow_manager.documents_changed.connect(verification_terminal.refresh_documents)
		_demo_flow_manager.passenger_event_changed.connect(verification_terminal.workspace.refresh_review)
		_left_interface.archive_document_retrieved.connect(verification_terminal.open_left_archive_document)
		_right_interface.archive_document_retrieved.connect(verification_terminal.open_right_archive_document)

	var presentation := elevator_cabin.get_node_or_null("主台展示绑定") as MainConsolePresentation3D
	if presentation != null and verification_terminal != null:
		presentation.bind_dialogue.call_deferred(_demo_flow_manager, elevator_cabin, verification_terminal)

	# 舱内运行声复用同一个流程实例，只表现已接收的行驶与实际到站。
	var movement_audio := elevator_cabin.get_node_or_null(
		"玩家视角/电梯运行音效"
	) as ElevatorMovementAudio
	if movement_audio != null:
		movement_audio.setup(_demo_flow_manager)

	# 摄影棚门表现是可选依赖，缺失时主台仍保留原有纯业务门控。
	_monitor_stage_controller = elevator_cabin.find_child(
		"监控测试摄影棚",
		true,
		false
	) as MonitorStageController3D
	if _monitor_stage_controller == null:
		push_warning("运行层连接器找不到 MonitorStageController3D，舱门将仅更新业务状态。")
	else:
		_main_interface.set_monitor_stage_controller(_monitor_stage_controller)

	# 高层协调器聚合门、乘客与等待状态；缺失时沿用已有门表现与纯业务流程。
	_monitor_presentation_coordinator = elevator_cabin.find_child(
		"监控表现协调器",
		true,
		false
	) as MonitorPresentationCoordinator3D
	if _monitor_presentation_coordinator == null:
		push_warning("运行层连接器找不到 MonitorPresentationCoordinator3D，表现时间线将降级运行。")
	else:
		_monitor_presentation_coordinator.setup(
			_demo_flow_manager,
			_main_interface,
			_right_interface,
			_monitor_stage_controller
		)
		_main_interface.set_monitor_presentation_coordinator(
			_monitor_presentation_coordinator
		)
		if _monitor_stage_controller != null:
			_demo_flow_manager.set_travel_busy_query(_query_travel_busy)
		_right_interface.set_monitor_presentation_coordinator(
			_monitor_presentation_coordinator
		)

	# 监控摄像机同样属于表现层，放在业务与门表现注入之后独立接线。
	_monitor_camera_controller = elevator_cabin.find_child(
		"监控渲染系统",
		true,
		false
	) as MonitorCameraController3D
	if _monitor_camera_controller == null:
		push_warning("运行层连接器找不到 MonitorCameraController3D，主台将保留文字监控。")
	if _monitor_camera_controller != null:
		_monitor_camera_controller.setup(_main_interface, interface_router)


func get_demo_flow_manager() -> DemoFlowManager:
	return _demo_flow_manager


## 缺失或离树的表现节点无法提供联锁结论。
func _query_travel_busy() -> Variant:
	if not is_instance_valid(_monitor_presentation_coordinator) or not is_instance_valid(_monitor_stage_controller):
		return null
	if not _monitor_presentation_coordinator.is_inside_tree() or not _monitor_stage_controller.is_inside_tree():
		return null
	var door := _monitor_stage_controller.get_door_visual()
	if not is_instance_valid(door) or not door.is_inside_tree() or not door.is_ready_for_commands():
		return null
	return _monitor_presentation_coordinator.is_presentation_busy() \
			or (not _demo_flow_manager.is_cabin_door_open() and not door.is_closed())
