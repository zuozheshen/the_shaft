class_name MonitorCameraController3D
extends Node


@export var monitor_subviewport_path: NodePath
@export var monitor_camera_path: NodePath
@export var cabin_camera_anchor_path: NodePath
@export var door_camera_anchor_path: NodePath

var _monitor_subviewport: SubViewport
var _monitor_camera: Camera3D
var _cabin_camera_anchor: Marker3D
var _door_camera_anchor: Marker3D
var _main_interface: ConsoleInterface
var _interface_router: CabinInterfaceRouter3D
var _current_camera_index: int = 0
var _is_setup_complete: bool = false
var _is_render_chain_ready: bool = false


func _ready() -> void:
	# 渲染节点由场景显式配置，避免控制器依赖易碎的深层名称搜索。
	_monitor_subviewport = _get_typed_node(
		monitor_subviewport_path,
		"SubViewport"
	) as SubViewport
	_monitor_camera = _get_typed_node(
		monitor_camera_path,
		"Camera3D"
	) as Camera3D
	_cabin_camera_anchor = _get_typed_node(
		cabin_camera_anchor_path,
		"Marker3D"
	) as Marker3D
	_door_camera_anchor = _get_typed_node(
		door_camera_anchor_path,
		"Marker3D"
	) as Marker3D
	_prepare_render_chain()


func setup(
		main_interface: ConsoleInterface,
		interface_router: CabinInterfaceRouter3D
) -> void:
	# RuntimeConnector3D 只注入一次，防止按钮和可见性信号重复连接。
	if _is_setup_complete:
		return
	_main_interface = main_interface
	_interface_router = interface_router

	if _main_interface == null:
		push_error("监控摄像机控制器未取得主操作台，实时画面无法连接。")
		return
	if _interface_router == null:
		push_error("监控摄像机控制器未取得界面路由器，视口将保持停用。")
		_main_interface.set_camera_feed_texture(null)
		return

	# 只有必要依赖通过验证后才锁定 setup，失败调用仍可在之后重试。
	_is_setup_complete = true
	if not _main_interface.camera_selected.is_connected(select_camera):
		_main_interface.camera_selected.connect(select_camera)
	if not _interface_router.main_console_visibility_changed.is_connected(
			_on_main_console_visibility_changed
	):
		_interface_router.main_console_visibility_changed.connect(
			_on_main_console_visibility_changed
		)

	if not _is_render_chain_ready:
		_main_interface.set_camera_feed_texture(null)
		return

	# ViewportTexture 必须在节点 ready 后取得，避免在场景文件中保存跨场景纹理路径。
	_main_interface.set_camera_feed_texture(_monitor_subviewport.get_texture())
	select_camera(_main_interface.get_current_camera_index())
	_on_main_console_visibility_changed(
		_interface_router.is_main_console_visible()
	)


func select_camera(camera_index: int) -> void:
	# 两个 Marker3D 只是机位；始终移动同一台监控 Camera3D。
	var selected_anchor: Marker3D
	match camera_index:
		0:
			selected_anchor = _cabin_camera_anchor
		1:
			selected_anchor = _door_camera_anchor
		_:
			push_warning("监控摄像机控制器拒绝无效机位索引：%s" % camera_index)
			return

	if not _apply_anchor(selected_anchor):
		return
	_current_camera_index = camera_index


func _prepare_render_chain() -> void:
	if _monitor_subviewport == null \
			or _monitor_camera == null \
			or _cabin_camera_anchor == null \
			or _door_camera_anchor == null:
		push_error("监控摄像机控制器缺少关键渲染节点，将保留文字画面。")
		return

	var shared_world: World3D = get_viewport().world_3d
	if shared_world == null:
		push_error("监控摄像机控制器无法取得主场景 World3D，将保留文字画面。")
		return

	# 监控视口复用主场景的 3D 世界，不创建第二套场景或 World3D。
	_monitor_subviewport.world_3d = shared_world
	_monitor_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_monitor_camera.current = true
	_is_render_chain_ready = true


func _apply_anchor(anchor: Marker3D) -> bool:
	if anchor == null or _monitor_camera == null:
		push_warning("监控摄像机缺少有效机位锚点，保留当前机位。")
		return false
	_monitor_camera.global_transform = anchor.global_transform
	return true


func _on_main_console_visibility_changed(is_visible: bool) -> void:
	if _monitor_subviewport == null:
		if _main_interface != null:
			_main_interface.set_camera_feed_texture(null)
		return
	_monitor_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS \
			if is_visible else SubViewport.UPDATE_DISABLED


func _get_typed_node(node_path: NodePath, expected_type: String) -> Node:
	if node_path.is_empty():
		push_error("监控摄像机控制器缺少 %s 的 NodePath 配置。" % expected_type)
		return null
	var target_node := get_node_or_null(node_path)
	if target_node == null:
		push_error("监控摄像机控制器找不到节点：%s" % node_path)
		return null
	if not target_node.is_class(expected_type):
		push_error("监控节点 %s 应为 %s，实际为 %s。" % [
			node_path,
			expected_type,
			target_node.get_class(),
		])
		return null
	return target_node
