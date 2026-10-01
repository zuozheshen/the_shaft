extends RefCounted
## 正式主场景内验证纸质楼层书的数据、互斥状态与输入上下文。

const MAIN := preload("res://scenes/main/main_3d.tscn")


func run(t: Variant, tree: SceneTree) -> void:
	var main := MAIN.instantiate()
	t.add_child(main)
	await _frames(tree)
	var cabin := main.get_node("三维操作舱") as CabinViewController3D
	var interaction := cabin.get_node("交互控制器") as CabinInteractionController3D
	var book := cabin.get_node(
			"操作台占位/右操作台定位/下部斜面根/楼层导引书"
	) as FloorGuideBook3D
	var router := cabin.get_node("操作台界面层") as CabinInterfaceRouter3D
	var destination := router.get_right_interface()
	var floors: Array[FloorDefinition] = ContentRegistry.get_all_floors()

	t.assert_equal("楼层书 / 正式 Catalog 七层", 7, floors.size())
	t.assert_equal("楼层书 / 条数来自正式 Catalog", floors.size(),
			destination.get_floor_book_page_count())
	t.assert_true("楼层书 / 负索引为空", destination.get_floor_book_snapshot(-1).is_empty())
	t.assert_true("楼层书 / 越界索引为空",
			destination.get_floor_book_snapshot(floors.size()).is_empty())
	var previous_order := -1
	for index in floors.size():
		var definition := floors[index]
		var snapshot: Dictionary = destination.get_floor_book_snapshot(index)
		t.assert_true("楼层书 / book_order 单调递增 %d" % index,
				definition.book_order > previous_order)
		previous_order = definition.book_order
		t.assert_equal("楼层书 / 编号保留原始字符串 %d" % index,
				String(definition.floor_id), snapshot["floor_id"])
		t.assert_equal("楼层书 / 名称来自 FloorDefinition %d" % index,
				definition.display_name, snapshot["display_name"])
		t.assert_equal("楼层书 / 介绍来自 FloorDefinition %d" % index,
				definition.description, snapshot["description"])
		t.assert_equal("楼层书 / 功能来自 FloorDefinition %d" % index,
				definition.function_description, snapshot["function_description"])
		t.assert_equal("楼层书 / 维修来自 FloorDefinition %d" % index,
				definition.maintenance_history, snapshot["maintenance_history"])
		t.assert_equal("楼层书 / 备注来自 FloorDefinition %d" % index,
				definition.book_note, snapshot["book_note"])
		t.assert_equal("楼层书 / 只有六项静态资料和页码 %d" % index,
				8, snapshot.size())
		t.assert_equal("楼层书 / 页码稳定 %d" % index, index + 1,
				snapshot["page_number"])
		if String(definition.floor_id) == "004":
			t.assert_equal("楼层书 / 004 前导零", "004", snapshot["floor_id"])
		if String(definition.floor_id) == "392":
			t.assert_equal("楼层书 / 392 纸质备注固定",
					"纸质索引页无额外手写标记。", snapshot["book_note"])

	cabin._start_turn(-1)
	await tree.create_timer(cabin.turn_duration + 0.05).timeout
	t.assert_equal("楼层书 / 当前视角为右台",
			CabinViewController3D.FacingDirection.RIGHT_CONSOLE,
			cabin.get_current_direction())
	var closed_hotspot := book.get_node("BookRoot/BookHotspot") as InteractionHotspot3D
	var book_root := book.get_node("BookRoot") as Node3D
	var cover_pivot := book.get_node("BookRoot/CoverPivot") as Node3D
	var cover_mesh := book.get_node("BookRoot/CoverPivot/封面") as MeshInstance3D
	var left_page := book.get_node("BookRoot/LeftPageMesh") as MeshInstance3D
	var right_sheet := book.get_node("BookRoot/RightPageMesh") as MeshInstance3D
	var rest_pose := book.get_node("RestPose") as Marker3D
	var inspect_pose := book.get_node("InspectPose") as Marker3D
	t.assert_true("楼层书 / 合书热点可用", closed_hotspot.can_interact())
	var camera := cabin.get_node("玩家视角/摄像机旋转轴/玩家摄像机") as Camera3D
	t.assert_equal("楼层书 / 鼠标射线命中合书实体", closed_hotspot,
			interaction._raycast_hotspot(
				camera.unproject_position(closed_hotspot.global_position)
			))
	var candidate_actions: Array[StringName] = []
	for candidate in interaction._get_gamepad_candidates():
		candidate_actions.append(candidate.get_action_id())
	t.assert_true("楼层书 / 手柄可聚焦实体书", &"floor_book_open" in candidate_actions)

	var comm := router.get_main_interface().comm_view as FloatingCommUI
	var selected_choices: Array[int] = []
	comm.choice_selected.connect(func(index: int) -> void:
		selected_choices.append(index)
	)
	comm.present(true, "书本优先级测试", [
		{"text": "继续", "is_allowed": true},
	], true, true)
	await _frames(tree, 2)
	t.assert_true("楼层书 / COMM 选项上下文存在",
			comm.has_controller_choice_context())
	t.assert_false("楼层书 / COMM 选项排除手柄开书焦点",
			interaction._is_hotspot_allowed(closed_hotspot))
	t.assert_true("楼层书 / COMM 选项允许鼠标命中书",
			interaction._is_hotspot_allowed(closed_hotspot, true))
	t.assert_true("楼层书 / COMM 面板区域阻止鼠标穿透",
			interaction._is_pointer_over_blocking_gui(comm.get_global_rect().get_center()))
	interaction._switch_to_gamepad_mode()
	interaction._set_hovered_hotspot(closed_hotspot)
	interaction._execute_action(&"floor_book_open")
	t.assert_false("楼层书 / COMM 选项阻止手柄开书", book.is_inspection_active())
	var book_click := InputEventMouseButton.new()
	book_click.button_index = MOUSE_BUTTON_LEFT
	book_click.position = camera.unproject_position(closed_hotspot.global_position)
	book_click.pressed = true
	interaction._unhandled_input(book_click)
	t.assert_true("楼层书 / 鼠标点击时 COMM 与阅读并存",
			book.is_inspection_active() and comm.has_controller_choice_context())
	t.assert_true("楼层书 / 鼠标开书不选择对话", selected_choices.is_empty())
	comm.set_minimized(true, false)
	await _frames(tree, 2)

	interaction._switch_to_gamepad_mode()
	t.assert_true("楼层书 / 开书开始即锁转向", interaction.is_station_turn_locked())
	t.assert_equal("楼层书 / 开书清除旧手柄焦点", null,
			interaction._hovered_hotspot)
	t.assert_false("楼层书 / 展开时拒绝重复开书", book.open_book())
	t.assert_false("楼层书 / 展开时拒绝翻页", book.turn_page(1))
	await tree.create_timer(book.open_duration * 0.3).timeout
	t.assert_true("楼层书 / 先移动合上的封面",
			is_zero_approx(cover_pivot.rotation.y) and not left_page.visible
			and book_root.transform.origin.distance_to(rest_pose.transform.origin) > 0.05)
	t.assert_true("楼层书 / 拿起时封面遮住右页",
			camera.to_local(cover_mesh.global_position).z
			> camera.to_local(right_sheet.global_position).z + 0.005)
	await tree.create_timer(book.open_duration * 0.4).timeout
	t.assert_true("楼层书 / 到阅读位置后才展开",
			book_root.transform.is_equal_approx(inspect_pose.transform)
			and left_page.visible and cover_pivot.rotation.y < -0.1)
	t.assert_true("楼层书 / 展开封面在可读页前方",
			camera.to_local(cover_mesh.global_position).z
			> camera.to_local(right_sheet.global_position).z + 0.02)
	await tree.create_timer(book.open_duration * 0.35 + 0.05).timeout
	t.assert_true("楼层书 / 已展开", book.is_open())
	comm.set_minimized(false, false)
	interaction._handle_gamepad_navigation(Vector2i.RIGHT)
	t.assert_equal("楼层书 / COMM 可选时手柄右导航不翻页", 0,
			book.get_page_index())
	interaction._handle_gamepad_navigation(Vector2i.DOWN)
	t.assert_true("楼层书 / COMM 可选时手柄焦点留在对话",
			comm.has_controller_choice_focus())
	comm.set_minimized(true, false)
	t.assert_true("楼层书 / 展开后封面缩放复位",
			cover_pivot.scale.is_equal_approx(Vector3.ONE))
	var spread_center := camera.unproject_position(
			book_root.to_global(Vector3(-0.065, 0.0, -0.325))
	)
	var screen_center := camera.get_viewport().get_visible_rect().size * 0.5
	t.assert_true("楼层书 / 阅读跨页位于屏幕中央",
			absf(spread_center.x - screen_center.x) < screen_center.x * 0.06)
	t.assert_true("楼层书 / 阅读页接近平行且略后倾",
			(-book_root.global_transform.basis.x.normalized()).dot(
				camera.global_transform.basis.z.normalized()
			) > 0.98)
	for hotspot_name: String in [
		"PrevPageHotspot", "NextPageHotspot", "CloseBookHotspot",
	]:
		var hotspot := book.get_node("BookRoot/" + hotspot_name) as InteractionHotspot3D
		t.assert_equal("楼层书 / 鼠标射线命中翻页或合书 " + hotspot_name,
				hotspot,
				interaction._raycast_hotspot(
					camera.unproject_position(hotspot.global_position)
				))
	var digit_hotspot := cabin.get_node(
			"操作台占位/右操作台定位/数字键盘/数字4"
	) as InteractionHotspot3D
	t.assert_false("楼层书 / 阅读时背后热点不允许执行",
			interaction._is_hotspot_allowed(digit_hotspot))
	t.assert_false("楼层书 / 首页不能向前", book.turn_page(-1))

	var input_before: String = destination.manual_destination_line_edit.text
	interaction._execute_action(&"destination_digit_4")
	t.assert_equal("楼层书 / 阅读时背后数字键失效", input_before,
			destination.manual_destination_line_edit.text)
	t.assert_true("楼层书 / 阅读时普通焦点候选为空",
			interaction._get_gamepad_candidates().is_empty())
	var turn_event := InputEventAction.new()
	turn_event.action = &"turn_left"
	turn_event.pressed = true
	cabin._input(turn_event)
	await tree.create_timer(cabin.turn_duration + 0.05).timeout
	t.assert_equal("楼层书 / Q/E 或肩键转向被锁定",
			CabinViewController3D.FacingDirection.RIGHT_CONSOLE,
			cabin.get_current_direction())

	t.assert_true("楼层书 / 向后翻页开始", book.turn_page(1))
	t.assert_false("楼层书 / 动画中第二次翻页被拒", book.turn_page(1))
	await tree.create_timer(book.page_turn_duration * 0.35).timeout
	var turning_sheet := book.get_node("BookRoot/TurnPagePivot/TurnPage") as MeshInstance3D
	t.assert_true("楼层书 / 翻页面在可读页前方",
			camera.to_local(turning_sheet.global_position).z
			> camera.to_local(right_sheet.global_position).z + 0.02)
	await tree.create_timer(book.page_turn_duration * 0.7 + 0.05).timeout
	t.assert_equal("楼层书 / 落定后是第二页", 1, book.get_page_index())
	t.assert_false("楼层书 / 落定后薄页隐藏", turning_sheet.visible)
	t.assert_true("楼层书 / 落定后薄页缩放复位",
			(book.get_node("BookRoot/TurnPagePivot") as Node3D).scale.is_equal_approx(
				Vector3.ONE
			))
	interaction._handle_gamepad_navigation(Vector2i.LEFT)
	await tree.create_timer(book.page_turn_duration + 0.05).timeout
	t.assert_equal("楼层书 / 手柄左导航上一页", 0, book.get_page_index())
	var right_key := InputEventKey.new()
	right_key.keycode = KEY_RIGHT
	right_key.pressed = true
	interaction._input(right_key)
	await tree.create_timer(book.page_turn_duration + 0.05).timeout
	t.assert_equal("楼层书 / 键盘右方向下一页", 1, book.get_page_index())
	for index in range(2, floors.size()):
		t.assert_true("楼层书 / 下一页 %d" % index, book.turn_page(1))
		await tree.create_timer(book.page_turn_duration + 0.05).timeout
	t.assert_equal("楼层书 / 末页索引", floors.size() - 1, book.get_page_index())
	t.assert_false("楼层书 / 末页不能循环", book.turn_page(1))
	t.assert_equal("楼层书 / 末页页码与内容一致",
			String(floors[-1].floor_id),
			(book.get_node("LeftPageViewport/Page/Number") as Label).text)

	t.assert_true("楼层书 / 合书开始", book.close_book())
	t.assert_false("楼层书 / 合书期间拒绝重入", book.close_book())
	await tree.create_timer(book.close_duration * 0.3).timeout
	t.assert_true("楼层书 / 先在阅读位置合上封面",
			book_root.transform.is_equal_approx(inspect_pose.transform)
			and left_page.visible and cover_pivot.rotation.y > -PI + 0.1)
	await tree.create_timer(book.close_duration * 0.4).timeout
	t.assert_true("楼层书 / 合上后才放回",
			is_zero_approx(cover_pivot.rotation.y) and not left_page.visible
			and cover_pivot.scale.is_equal_approx(Vector3.ONE)
			and not book_root.transform.is_equal_approx(rest_pose.transform))
	await tree.create_timer(book.close_duration * 0.35 + 0.05).timeout
	t.assert_false("楼层书 / 合书释放转向锁", interaction.is_station_turn_locked())
	t.assert_true("楼层书 / 返回 RestPose",
			book.get_node("BookRoot").transform.is_equal_approx(
				book.get_node("RestPose").transform
			))
	t.assert_true("楼层书 / 合书热点恢复", closed_hotspot.can_interact())
	t.assert_true("楼层书 / 合书后右台焦点恢复",
			interaction._hovered_hotspot != null)
	interaction._execute_action(&"destination_digit_4")
	t.assert_equal("楼层书 / 合书后数字键恢复", input_before + "4",
			destination.manual_destination_line_edit.text)
	interaction._execute_action(&"floor_book_open")
	await tree.create_timer(book.open_duration + 0.05).timeout
	t.assert_equal("楼层书 / 同次运行再次打开保留末页",
			floors.size() - 1, book.get_page_index())
	var cancel_key := InputEventKey.new()
	cancel_key.keycode = KEY_ESCAPE
	cancel_key.pressed = true
	interaction._input(cancel_key)
	t.assert_true("楼层书 / Esc 开始合书", book.is_busy())
	await tree.create_timer(book.close_duration + 0.05).timeout
	interaction._execute_action(&"floor_book_open")
	await tree.create_timer(book.open_duration + 0.05).timeout
	var cancel_button := InputEventJoypadButton.new()
	cancel_button.button_index = JOY_BUTTON_B
	cancel_button.pressed = true
	interaction._input(cancel_button)
	t.assert_true("楼层书 / 手柄 B 开始合书", book.is_busy())
	await tree.create_timer(book.close_duration + 0.05).timeout

	main.queue_free()
	await _frames(tree, 3)


func _frames(tree: SceneTree, count: int = 4) -> void:
	for frame in count:
		await tree.process_frame
