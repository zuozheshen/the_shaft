extends RefCounted
## 正式空舱基线，不使用派单夹具；验证三层、旧内容移除与真实 UI 接线。

const MAIN := preload("res://scenes/main/main_3d.tscn")

func run(t: Variant, tree: SceneTree) -> void:
	var ids: Array[String] = []
	for floor_data in ContentRegistry.get_all_floors():
		ids.append(String(floor_data.floor_id))
	t.assert_equal("空舱基线 / 正式楼层仅三层", ["318", "001", "002"], ids)
	t.assert_true("空舱基线 / 无正式乘客", ContentRegistry.get_all_passenger_definitions().is_empty())
	t.assert_true("空舱基线 / 无正式派单", ContentRegistry.get_all_dispatch_definitions().is_empty())
	t.assert_true("空舱基线 / 无正式值班", ContentRegistry.get_all_shift_definitions().is_empty())
	var main := MAIN.instantiate()
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.movement_duration_seconds = 0.01
	t.add_child(main)
	for n in range(8):
		await tree.process_frame
	var router := main.find_child("操作台界面层", true, false) as CabinInterfaceRouter3D
	var destination := router.get_right_interface()
	var console := router.get_main_interface()
	var stage := main.find_child("监控测试摄影棚", true, false) as MonitorStageController3D
	t.assert_equal("空舱基线 / 初始318", "318", manager.get_current_floor())
	t.assert_equal("空舱基线 / 初始视觉318", &"318", stage.get_current_floor_visual_id())
	t.assert_equal("空舱基线 / 空闲而非假结算", DispatchPhase.SHIFT_IDLE, manager.get_case_phase())
	t.assert_false("空舱基线 / 无活动派单", manager.has_active_dispatch())
	t.assert_false("空舱基线 / 正式对话停用", console.dialogue_enabled)
	t.assert_true("空舱基线 / 通讯浮窗已移出运行树", main.find_child("FloatingCommUI", true, false) == null)
	t.assert_true("空舱基线 / 不创建对话适配器", console.dialogue_manager_adapter == null)
	t.assert_false("空舱基线 / 无乘客", manager.is_passenger_onboard())
	t.assert_false("空舱基线 / 乘客视觉隐藏", stage.get_current_passenger_visual().visible)
	t.assert_true("空舱基线 / 无人物Profile", stage.get_current_passenger_visual().get_current_profile() == null)
	t.assert_true("空舱基线 / 楼层书节点已移除", main.find_child("楼层导引书", true, false) == null)
	t.assert_equal("空舱基线 / 仅左台、监控、CASE视口", 3, main.find_children("*", "SubViewport", true, false).size())
	var camera := console.get_current_camera_index()
	console.request_select_camera(1 - camera)
	t.assert_equal("空舱基线 / CAM可切换", 1 - camera, console.get_current_camera_index())
	console.request_toggle_microphone()
	t.assert_false("空舱基线 / 无乘客不能启动通话", console.mic_enabled)
	t.assert_equal("空舱基线 / MIC说明暂时停用", "对话功能暂时停用。", console.get_system_hint())
	t.assert_true("空舱基线 / 开门", manager.request_open_cabin_door().succeeded)
	t.assert_false("空舱基线 / 开门不运行", manager.request_travel_to_floor("001").succeeded)
	t.assert_true("空舱基线 / 关门", manager.request_close_cabin_door().succeeded)
	for id: String in ["001", "002", "318"]:
		destination.clear_destination_input()
		for digit in id:
			destination.append_destination_digit(digit)
		t.assert_equal("空舱基线 / 自动查询保留编号 " + id, id, destination.get_destination_presentation().query_floor)
		destination.request_submit_destination()
		t.assert_true("空舱基线 / 已启动 " + id, manager.is_elevator_moving())
		t.assert_false("空舱基线 / 行驶中拒绝开门", manager.request_open_cabin_door().succeeded)
		if manager.is_elevator_moving():
			await manager.elevator_movement_completed
		t.assert_equal("空舱基线 / 实际抵达 " + id, id, manager.get_current_floor())
		t.assert_equal("空舱基线 / 到站视觉 " + id, StringName(id), stage.get_current_floor_visual_id())
	t.assert_false("空舱基线 / 旧楼层不再登记", ContentRegistry.has_floor("900"))
	t.assert_false("空舱基线 / 未登记楼层拒绝", manager.request_travel_to_floor("900").succeeded)
	var right := main.find_child("右台展示绑定", true, false) as RightConsolePresentation3D
	var label := right.get_node(right.information_label_path) as Label3D
	t.assert_false("空舱基线 / 移除旧关联评估", "关联度" in label.text or "稳定度" in label.text)
	t.assert_true("空舱基线 / 行驶音效组件保留", main.find_child("电梯运行音效", true, false) is ElevatorMovementAudio)
	main.queue_free()
	await tree.process_frame
