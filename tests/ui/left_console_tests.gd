extends RefCounted
## 使用正式 main_3d 验证左台实体入口复用唯一 BuildingTerminalInterface。

const MAIN := preload("res://scenes/main/main_3d.tscn")


func run(t: Variant, tree: SceneTree) -> void:
	var main := MAIN.instantiate()
	t.add_child(main)
	await _frames(tree)
	var cabin := main.get_node("三维操作舱") as CabinViewController3D
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	var router := main.find_child("操作台界面层", true, false) as CabinInterfaceRouter3D
	var terminal := router.get_left_interface()
	var interaction := cabin.get_node("交互控制器") as CabinInteractionController3D
	var left := cabin.get_node("操作台占位/左操作台定位") as LeftTerminalScreen3D
	var control_root := left.get_node("栏目控制区") as Node3D

	t.assert_equal("左台 / 唯一 BuildingTerminalInterface", 1,
			main.find_children("BuildingTerminalInterface", "", true, false).size())
	t.assert_false("左台 / 旧屏幕页签在 3D 模式隐藏", terminal.tab_button_panel.visible)
	for button: Button in [
		terminal.system_log_tab_button,
		terminal.record_tab_button,
		terminal.transcript_tab_button,
	]:
		t.assert_true("左台 / 旧屏幕按钮禁用 " + button.name, button.disabled)

	var names := ["系统日志", "乘客档案", "对话记录"]
	var actions: Array[StringName] = [
		&"left_system_log", &"left_passenger_record", &"left_transcript",
	]
	for index in names.size():
		var key := control_root.get_node(names[index]) as InteractionHotspot3D
		var collision := key.get_node("CollisionShape3D") as CollisionShape3D
		var cap := key.get_node("按钮帽") as MeshInstance3D
		t.assert_equal("左台 / 栏目动作映射 " + names[index],
				actions[index], key.get_action_id())
		t.assert_equal("左台 / 热点属于左台 " + names[index],
				&"left_console", key.get_station_id())
		t.assert_equal("左台 / 保留现有中文术语 " + names[index], names[index],
				(key.get_node("标识") as Label3D).text)
		t.assert_true("左台 / Mesh 与碰撞跟随同一按键根 " + names[index],
				collision.global_transform.basis.is_equal_approx(
					cap.global_transform.basis
				))
	# 左视角中 z 从大到小对应画面从左到右；人工验收冻结为 FILE、TRANSCRIPT、SYSTEM、滚轮。
	var passenger_key := control_root.get_node("乘客档案") as Node3D
	var transcript_key := control_root.get_node("对话记录") as Node3D
	var system_key := control_root.get_node("系统日志") as Node3D
	var scroll_root := left.get_node("滚轮根") as Node3D
	t.assert_true("左台 / 实体件从左到右顺序固定",
			passenger_key.position.z > transcript_key.position.z
			and transcript_key.position.z > system_key.position.z
			and system_key.position.z > scroll_root.position.z)

	# 首单在主台启动：SYSTEM 与新档案都未被玩家实际查看。
	t.assert_false("左台 / 初始不在左台视角", terminal.is_actively_viewed())
	t.assert_true("左台 / 离开左台时初始 SYSTEM 未读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.SYSTEM_LOG))
	t.assert_true("左台 / 新派单 FILE 未读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.PASSENGER_RECORD))
	t.assert_false("左台 / 新派单空 TRANSCRIPT 已读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.TRANSCRIPT))

	manager.add_system_log_message("离开左台时的新日志")
	t.assert_true("左台 / current SYSTEM 但玩家未看仍点灯",
			terminal.get_section_unread(BuildingTerminalInterface.Section.SYSTEM_LOG))
	terminal.set_actively_viewed(true)
	t.assert_false("左台 / 实际转到左台清当前 SYSTEM",
			terminal.get_section_unread(BuildingTerminalInterface.Section.SYSTEM_LOG))

	manager.add_front_transcript_operator("新的对话记录")
	t.assert_true("左台 / 查看 SYSTEM 时 TRANSCRIPT 更新点灯",
			terminal.get_section_unread(BuildingTerminalInterface.Section.TRANSCRIPT))
	interaction._execute_action(&"left_transcript")
	t.assert_equal("左台 / 实体键切换唯一栏目",
			BuildingTerminalInterface.Section.TRANSCRIPT, terminal.get_current_section())
	t.assert_false("左台 / 查看 TRANSCRIPT 后清灯",
			terminal.get_section_unread(BuildingTerminalInterface.Section.TRANSCRIPT))
	manager.add_front_transcript_passenger("继续追加")
	t.assert_false("左台 / 正在阅读的 TRANSCRIPT 更新保持已读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.TRANSCRIPT))

	# 新派单重置不跨单保留；FILE 只因新 Passenger resource 可查看而点亮。
	var dispatch_id: StringName = manager.get_active_dispatch().dispatch_id
	terminal.set_actively_viewed(false)
	manager.clear_active_dispatch()
	t.assert_false("左台 / 清空派单后 FILE 不残留",
			terminal.get_section_unread(BuildingTerminalInterface.Section.PASSENGER_RECORD))
	t.assert_true("左台 / 可重新开始同一测试派单", manager.start_dispatch(dispatch_id))
	t.assert_equal("左台 / 新派单回到 SYSTEM",
			BuildingTerminalInterface.Section.SYSTEM_LOG, terminal.get_current_section())
	t.assert_true("左台 / 新派单离开视角时 SYSTEM 未读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.SYSTEM_LOG))
	t.assert_true("左台 / 新派单档案可查看时 FILE 未读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.PASSENGER_RECORD))
	t.assert_false("左台 / 新派单不虚构对话未读",
			terminal.get_section_unread(BuildingTerminalInterface.Section.TRANSCRIPT))

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
	var wheel_basis_before := wheel_visual.transform.basis
	var wheel_axis_before := wheel_basis_before.y.normalized()
	interaction._execute_left_scroll(1)
	await _frames(tree, 2)
	t.assert_true("左台 / 实体滚轮改变当前阅读位置",
			terminal.content_scroll_container.scroll_vertical > 0)
	t.assert_not_equal("左台 / 滚轮视觉产生机械步进",
			wheel_basis_before, wheel_visual.transform.basis)
	t.assert_true("左台 / 滚轮只绕自身轴旋转",
			wheel_axis_before.is_equal_approx(
				wheel_visual.transform.basis.y.normalized()
			))
	t.assert_equal("左台 / 滚轮包含可观察轴向刻线", 4,
			wheel_visual.find_children("轴向刻线*", "MeshInstance3D", false, false).size())
	t.assert_equal("左台 / 滚轮不修改系统日志", system_history_before,
			manager.get_system_message_history())
	t.assert_equal("左台 / 滚轮不修改对话内容", transcript_before,
			manager.get_front_dialogue_history())

	var scroll_hotspot := left.get_node("滚轮根") as InteractionHotspot3D
	t.assert_equal("左台 / 滚轮使用独立实体热点", &"left_scroll",
			scroll_hotspot.get_action_id())
	t.assert_equal("左台 / 新结构没有触摸屏碰撞", null,
			left.get_node_or_null("左台屏幕交互区"))

	main.queue_free()
	await _frames(tree, 3)


func _frames(tree: SceneTree, count: int = 8) -> void:
	for frame in count:
		await tree.process_frame
