extends RefCounted

const TestContent := preload("res://tests/fixtures/runtime/test_content.gd")
const Archive := preload("res://tests/fixtures/runtime/test_left_lookup_documents.gd")
const Docs := preload("res://tests/fixtures/runtime/test_documents.gd")
## 使用正式 main_3d 验证左台实体入口复用唯一 BuildingTerminalInterface。

const MAIN := preload("res://scenes/main/main_3d.tscn")


func run(t: Variant, tree: SceneTree) -> void:
	var definition := ContentRegistry.get_dispatch("TEST_CASE_001")
	var original_documents := definition.documents
	definition.documents = Archive.definitions(definition.passenger_id, true)
	var main := MAIN.instantiate()
	TestContent.prepare_scene(main)
	var cabin := main.get_node("三维操作舱") as CabinViewController3D
	cabin.turn_duration = 0.025
	t.add_child(main)
	await _frames(tree)
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	var router := main.find_child("操作台界面层", true, false) as CabinInterfaceRouter3D
	var terminal := router.get_left_interface()
	var workspace_terminal := main.find_child("核验终端", true, false) as VerificationTerminal3D
	workspace_terminal.slide_duration = 0.02
	var interaction := cabin.get_node("交互控制器") as CabinInteractionController3D
	var left := cabin.get_node("操作台占位/左操作台定位") as LeftTerminalScreen3D
	var control_root := left.get_node("栏目控制区") as Node3D
	var screen := left.get_node(left.screen_mesh_path) as ScreenSurface3D
	var viewport := left.get_node(left.sub_viewport_path) as SubViewport
	var profile := preload("res://assets/art/materials/left_archive_crt.tres")
	var material := screen.material_override as ShaderMaterial

	t.assert_equal("左台 / 实际档案视口保持 1152x648", Vector2i(1152, 648), viewport.size)
	t.assert_equal("左台 / 当前场景的档案视口进入实体屏面", viewport.get_texture(),
			material.get_shader_parameter(&"feed_texture"))
	t.assert_true("左台 / 实例材质不把视口纹理写入共享 Profile", material != profile
			and profile.get_shader_parameter(&"feed_texture") == null)

	t.assert_equal("左台 / 唯一 BuildingTerminalInterface", 1,
			main.find_children("BuildingTerminalInterface", "", true, false).size())
	t.assert_false("左台 / 旧屏幕页签已移除", terminal.has_node("TerminalLayout/TabButtonPanel"))
	t.assert_equal("左台 / 旧屏幕按钮已移除", 0, terminal.find_children("*", "Button", true, false).size())

	var names := ["系统日志", "乘客档案", "调阅"]
	var actions: Array[StringName] = [
		&"left_system_log", &"left_passenger_record", &"left_retrieve_document",
	]
	for index in names.size():
		var key := control_root.get_node(names[index]) as InteractionHotspot3D
		var collision := key.get_node("CollisionShape3D") as CollisionShape3D
		var cap := key.get_node("视觉资产/按钮帽") as Node3D
		t.assert_equal("左台 / 栏目动作映射 " + names[index],
				actions[index], key.get_action_id())
		t.assert_equal("左台 / 热点属于左台 " + names[index],
				&"left_console", key.get_station_id())
		t.assert_equal("左台 / 保留现有中文术语 " + names[index], names[index],
				(key.get_node("标识") as Label3D).text)
		t.assert_true("左台 / 文字与键根一同移动 " + names[index],
				(key.get_node("标识") as Label3D).is_visible_in_tree())
		t.assert_true("左台 / 视觉挂载与碰撞跟随同一按键根 " + names[index],
				collision.global_transform.basis.is_equal_approx(
					cap.global_transform.basis
				))
		t.assert_true("左台 / 栏目模型导入后有可见网格 " + names[index],
				cap.find_children("*", "MeshInstance3D", true, false).size() > 0)
	var passenger_key := control_root.get_node("乘客档案") as Node3D
	var retrieve_key := control_root.get_node("调阅") as Node3D
	var system_key := control_root.get_node("系统日志") as Node3D
	var scroll_root := left.get_node("滚轮根") as Node3D
	t.assert_true("左台 / 实体件从左到右顺序固定",
			system_key.position.z > passenger_key.position.z
			and passenger_key.position.z > retrieve_key.position.z
			and retrieve_key.position.z > scroll_root.position.z)
	var shell := left.get_node("视觉资产/档案终端外壳")
	for old_label: String in ["固定铭牌_系统日志", "固定铭牌_乘客档案", "固定铭牌_对话记录"]:
		var decal := shell.find_child(old_label, true, false) as MeshInstance3D
		t.assert_true("左台 / 旧壳体标签已隐藏 " + old_label,
				decal != null and not decal.is_visible_in_tree())

	# 首单在主台启动：SYSTEM 与新档案都未被玩家实际查看。
	t.assert_false("左台 / 初始不在左台视角", terminal.is_actively_viewed())
	t.assert_true("左台 / 离开左台时初始 SYSTEM 未读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.SYSTEM_LOG))
	t.assert_true("左台 / 新派单 FILE 未读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.PASSENGER_RECORD))
	var lamp := left.get_node(left.retrieval_available_light_path) as Node3D
	t.assert_false("左台 / 未查档案时不点调阅灯", lamp.visible)
	manager.add_system_log_message("离开左台时的新日志")
	t.assert_true("左台 / current SYSTEM 但玩家未看仍点灯",
			terminal.get_section_unread(BuildingTerminalInterface.Section.SYSTEM_LOG))
	_key(cabin.get_viewport(), KEY_Q)
	await tree.create_timer(0.08).timeout
	t.assert_true("左台 / 实际按键转到左台", terminal.is_actively_viewed())
	var camera := left.get_node(left.player_camera_path) as Camera3D
	var system_x := camera.unproject_position(system_key.global_position).x
	var passenger_x := camera.unproject_position(passenger_key.global_position).x
	var retrieve_x := camera.unproject_position(retrieve_key.global_position).x
	t.assert_true("左台 / 正式玩家视角下调阅和两栏分组",
			system_x < passenger_x and retrieve_x - passenger_x > passenger_x - system_x)
	t.assert_equal("左台 / 原调阅位置只命中乘客档案", passenger_key,
			interaction._raycast_hotspot(camera.unproject_position(passenger_key.global_position)))
	t.assert_equal("左台 / 调阅新位置独立命中", retrieve_key,
			interaction._raycast_hotspot(camera.unproject_position(retrieve_key.global_position)))
	t.assert_false("左台 / 实际转到左台清当前 SYSTEM",
			terminal.get_section_unread(BuildingTerminalInterface.Section.SYSTEM_LOG))
	manager.add_front_transcript_operator("新的对话记录")
	manager.add_front_transcript_passenger("继续追加")
	t.assert_equal("左台 / 旧对话历史仍写入原缓存", 2, manager.get_front_dialogue_history().size())
	t.assert_false("左台 / 对话追加不点调阅灯", lamp.visible)
	interaction._execute_action(&"left_retrieve_document")
	t.assert_false("左台 / 日志不能调阅", workspace_terminal.target_open)

	await _exercise_archive(t, tree, terminal, workspace_terminal, interaction, manager, definition, lamp,
		passenger_key as InteractionHotspot3D, retrieve_key as InteractionHotspot3D)

	# 滚轮只改变当前 ScrollContainer 与视觉角度，不写业务历史。
	terminal.set_actively_viewed(true)
	var system_history_before := manager.get_system_message_history()
	var transcript_before := manager.get_front_dialogue_history()
	var long_lines := PackedStringArray()
	for index in 80:
		long_lines.append("阅读行 %02d" % index)
	terminal.terminal_content_label.text = "\n".join(long_lines)
	await _frames(tree, 3)
	var wheel_visual := left.get_node(left.scroll_wheel_visual_path) as Node3D
	var wheel_collision := scroll_root.get_node("CollisionShape3D") as CollisionShape3D
	var collision_transform_before := wheel_collision.global_transform
	var wheel_basis_before := wheel_visual.transform.basis
	var wheel_axis_before := wheel_basis_before.y.normalized()
	var expected_wheel_basis := wheel_basis_before * Basis(
			Vector3.UP,
			deg_to_rad(left.scroll_tick_degrees)
	)
	interaction._execute_left_scroll(1)
	await _frames(tree, 2)
	t.assert_true("左台 / 实体滚轮改变当前阅读位置",
			terminal.content_scroll_container.scroll_vertical > 0)
	t.assert_not_equal("左台 / 滚轮视觉产生机械步进",
			wheel_basis_before, wheel_visual.transform.basis)
	t.assert_true("左台 / 向下阅读时滚轮视觉方向正确",
			expected_wheel_basis.is_equal_approx(wheel_visual.transform.basis))
	t.assert_true("左台 / 滚轮只绕自身轴旋转",
			wheel_axis_before.is_equal_approx(
				wheel_visual.transform.basis.y.normalized()
			))
	t.assert_true("左台 / 可替换滚轮模型挂在唯一转轴内",
			wheel_visual.get_node("视觉资产/滚轮视觉")
					.find_children("*", "MeshInstance3D", true, false).size() > 0)
	t.assert_true("左台 / 滚动不旋转热点碰撞",
			collision_transform_before.is_equal_approx(wheel_collision.global_transform))
	t.assert_equal("左台 / 滚轮不修改系统日志", system_history_before,
			manager.get_system_message_history())
	t.assert_equal("左台 / 滚轮不修改对话内容", transcript_before,
			manager.get_front_dialogue_history())

	interaction._execute_left_scroll(-1)
	await _frames(tree, 2)
	t.assert_true("左台 / 反向阅读使滚轮回到原角度",
			wheel_basis_before.is_equal_approx(wheel_visual.transform.basis))
	t.assert_equal("左台 / 反向阅读回到原阅读位置", 0,
			terminal.content_scroll_container.scroll_vertical)

	var scroll_hotspot := left.get_node("滚轮根") as InteractionHotspot3D
	t.assert_equal("左台 / 滚轮使用独立实体热点", &"left_scroll",
			scroll_hotspot.get_action_id())
	t.assert_equal("左台 / 新结构没有触摸屏碰撞", null,
			left.get_node_or_null("左台屏幕交互区"))

	definition.documents = original_documents
	main.queue_free()
	await _frames(tree, 3)
	print("LEFT LOOKUP TESTS COMPLETE")


func _exercise_archive(t: Variant, tree: SceneTree, terminal: BuildingTerminalInterface,
		w: VerificationTerminal3D, interaction: CabinInteractionController3D, manager: DemoFlowManager,
		definition: DispatchDefinition, lamp: Node3D, archive_key: InteractionHotspot3D,
		retrieval_key: InteractionHotspot3D) -> void:
	var session := manager.get_document_session_id()
	t.assert_equal("左台 / 查询前没有初始收件", 0, manager.get_received_materials(session).size())
	var viewport := w.get_viewport()
	var camera := w.get_parent() as Camera3D
	_click(viewport, camera.unproject_position(archive_key.global_position))
	await _frames(tree, 4)
	t.assert_equal("左台 / 人员资料先显示且其他人员/上传不混入", "人员档案   1 / 3", terminal.document_heading.text)
	t.assert_true("左台 / 只读第一份后仍有未读文档", terminal.get_section_unread(BuildingTerminalInterface.Section.PASSENGER_RECORD))
	t.assert_true("左台 / 已查询当前文档点调阅灯", lamp.visible)
	t.assert_equal("左台 / 查询本身未让W取得文档", 0, manager.get_document_events(session).size())

	interaction._execute_left_scroll(1)
	var first_scroll := terminal.content_scroll_container.scroll_vertical
	_click(viewport, camera.unproject_position(archive_key.global_position))
	await _frames(tree, 4)
	t.assert_equal("左台 / 第二份显示名称与序号", "维修任务表   2 / 3", terminal.document_heading.text)
	t.assert_true("左台 / 原文包含完整范围与原始更新时间",
		terminal.terminal_content_label.text.contains("001、002") and terminal.terminal_content_label.text.contains("2026-11-08 08:30"))
	interaction._execute_left_scroll(2)
	var second_scroll := terminal.content_scroll_container.scroll_vertical
	t.assert_true("左台 / 真实布局允许滚动且两份位置不同", first_scroll > 0 and second_scroll > first_scroll)
	interaction._execute_left_scroll(1000)
	t.assert_equal("左台 / 滚动到边界不翻页", "维修任务表   2 / 3", terminal.document_heading.text)
	terminal.content_scroll_container.scroll_vertical = second_scroll
	terminal.set_actively_viewed(false)
	interaction._execute_action(&"left_passenger_record")
	await _frames(tree, 4)
	t.assert_true("左台 / 遮挡时显示第三份不清未读", terminal.get_section_unread(BuildingTerminalInterface.Section.PASSENGER_RECORD))
	terminal.set_actively_viewed(true)
	t.assert_equal("左台 / 第三份标题", "交接记录   3 / 3", terminal.document_heading.text)
	t.assert_false("左台 / 三份都已读后清档案灯", terminal.get_section_unread(BuildingTerminalInterface.Section.PASSENGER_RECORD))
	interaction._execute_action(&"left_passenger_record")
	await _frames(tree, 4)
	t.assert_equal("左台 / 末份回到第一份", "人员档案   1 / 3", terminal.document_heading.text)
	t.assert_equal("左台 / 第一份位置恢复", first_scroll, terminal.content_scroll_container.scroll_vertical)
	interaction._execute_action(&"left_passenger_record")
	await _frames(tree, 4)
	t.assert_equal("左台 / 第二份位置独立", second_scroll, terminal.content_scroll_container.scroll_vertical)
	interaction._execute_action(&"left_system_log")
	interaction._execute_action(&"left_passenger_record")
	await _frames(tree, 4)
	t.assert_equal("左台 / 日志往返恢复当前文档及位置", second_scroll, terminal.content_scroll_container.scroll_vertical)

	interaction._switch_to_gamepad_mode()
	interaction._set_hovered_hotspot(retrieval_key)
	_joy(viewport, JOY_BUTTON_A, true)
	await tree.create_timer(0.08).timeout
	_joy(viewport, JOY_BUTTON_A, false)
	var work := Docs.ref(Archive.WORK)
	var personnel := Docs.ref(Archive.PERSONNEL)
	t.assert_true("左台 / 一键展开W并打开第2份", w.target_open and w.workspace.windows.size() == 1)
	t.assert_equal("左台 / W定位已调阅资料", 2, w.workspace.category)
	t.assert_equal("左台 / 只取得当前工作表", 1, manager.get_acquired_documents(session).size())
	t.assert_false("左台 / W可读取第2份精确版本", manager.get_acquired_document(session, work).is_empty())
	t.assert_true("左台 / 第1份仍未取得", manager.get_acquired_document(session, personnel).is_empty())
	t.assert_true("左台 / 第3份仍未取得", manager.get_acquired_document(session, Docs.ref(Archive.HANDOVER)).is_empty())
	await _close_workspace(tree, w, terminal)
	t.assert_equal("左台 / 收起W恢复第2份位置", second_scroll, terminal.content_scroll_container.scroll_vertical)

	_click(viewport, camera.unproject_position(retrieval_key.global_position))
	t.assert_equal("左台 / 重复调阅同版只聚焦原窗", 1, w.workspace.windows.size())
	t.assert_equal("左台 / 重复调阅无重复事件", 1, manager.get_document_events(session).size())
	await _close_workspace(tree, w, terminal)
	interaction._execute_action(&"left_passenger_record")
	interaction._execute_action(&"left_passenger_record")
	await _frames(tree, 4)
	interaction._execute_action(&"left_retrieve_document")
	t.assert_equal("左台 / 先调阅第2份再调第1份保留两窗", 2, w.workspace.windows.size())
	t.assert_equal("左台 / 不同文档使用不同完成事件", 2, manager.get_document_events(session).size())
	await _close_workspace(tree, w, terminal)
	interaction._execute_action(&"left_passenger_record")
	await _frames(tree, 4)
	var revised := Archive.revised_work(definition.documents)
	definition.documents.append(revised)
	interaction._execute_action(&"left_retrieve_document")
	t.assert_false("左台 / 源版本变化不自动替换或展开W", w.target_open)
	t.assert_false("左台 / 旧结果调阅灯熄灭", lamp.visible)
	interaction._execute_action(&"left_system_log")
	interaction._execute_action(&"left_passenger_record")
	await _frames(tree, 4)
	t.assert_equal("左台 / 新版从顶部开始", 0, terminal.content_scroll_container.scroll_vertical)
	t.assert_true("左台 / 刷新后显示新版时间", terminal.terminal_content_label.text.contains("2026-11-08 09:00"))
	interaction._execute_action(&"left_retrieve_document")
	t.assert_false("左台 / 旧版与新版都可精确读", manager.get_acquired_document(session, work).is_empty()
		or manager.get_acquired_document(session, Docs.ref(Archive.WORK, 2)).is_empty())
	await _close_workspace(tree, w, terminal)

	var old_document: Dictionary = manager.query_current_passenger_archive(session)[0]
	manager.clear_active_dispatch()
	t.assert_true("左台 / 清空派单后可开启无工作记录测试单", manager.start_dispatch(&"TEST_CASE_002"))
	t.assert_false("左台 / 旧会话不能调阅", manager.retrieve_passenger_archive_document(session, &"left:old", old_document).succeeded)
	w.open_left_archive_document(session, work)
	t.assert_false("左台 / 旧会话展示请求不展开W", w.target_open)
	interaction._execute_action(&"left_passenger_record")
	await _frames(tree, 4)
	t.assert_true("左台 / 无工作记录只有人员文档", terminal.document_heading.text.ends_with("1 / 1"))
	t.assert_equal("左台 / 换单不复用阅读位置", 0, terminal.content_scroll_container.scroll_vertical)
	interaction._execute_action(&"left_passenger_record")
	t.assert_true("左台 / 只有一份时不切换", terminal.document_heading.text.ends_with("1 / 1"))
	interaction._execute_action(&"left_system_log")


func _close_workspace(tree: SceneTree, w: VerificationTerminal3D, terminal: BuildingTerminalInterface) -> void:
	w.set_open(false)
	await tree.create_timer(0.08).timeout
	# 本套件的状态/结构验证直接驱动热点，真实视角与输入另在定向测试中覆盖。
	terminal.set_actively_viewed(true)


func _key(viewport: Viewport, key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		viewport.push_input(event, true)


func _click(viewport: Viewport, position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		viewport.push_input(event, true)


func _joy(viewport: Viewport, button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	viewport.push_input(event, true)


func _frames(tree: SceneTree, count: int = 8) -> void:
	for frame in count:
		await tree.process_frame
