extends RefCounted
const MAIN := preload("res://scenes/main/main_3d.tscn")
const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Docs := preload("res://tests/fixtures/runtime/test_workspace_documents.gd")

func run(t: Variant, tree: SceneTree) -> void:
	var original_size := tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	var definition: DispatchDefinition = ContentRegistry.get_dispatch("TEST_CASE_001")
	var saved: Array[DocumentDefinition] = definition.documents
	definition.documents = Docs.definitions()
	var main := MAIN.instantiate()
	Content.prepare_scene(main)
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.initial_floor = "612"
	manager.initial_shift = null
	t.add_child(main)
	await frames(tree)
	manager.start_dispatch(&"TEST_CASE_001")
	var terminal := main.find_child("核验终端", true, false) as VerificationTerminal3D
	terminal.slide_duration = 0.01
	var workspace: VerificationWorkspace = terminal.workspace
	var viewport := terminal.get_viewport()
	key(viewport, KEY_W)
	await tree.create_timer(0.06).timeout
	t.assert_equal("工作区 / 未提交不生成缺件或窗口", 0, workspace.windows.size())
	t.assert_false("工作区 / 未取得楼层档案不可读取", not manager.get_acquired_document(manager.get_document_session_id(), Docs.ref("floor")).is_empty())
	var boarded := manager.request_open_cabin_door()
	t.assert_true("工作区 / 真实登舱命令成功", boarded.succeeded and manager.is_passenger_onboard())
	t.assert_true("工作区 / 登舱批次直接提交", Docs.submit_initial(manager).succeeded)
	Docs.acquire_floor(manager)
	manager.accept_left_lookup_result(manager.get_document_session_id(), &"preview:left:1", [Docs.ref("personnel")])
	workspace._select_category(0)
	t.assert_equal("工作区 / 收件箱仅乘客上传", ["preview/identity", "preview/task"], catalog_ids(workspace))
	workspace._select_category(1)
	t.assert_equal("工作区 / 规程样板每份仅一项", ["preview/rules", "preview/sample"], catalog_ids(workspace))
	workspace._select_category(2)
	t.assert_equal("工作区 / 已调阅仅左右台", ["preview/floor", "preview/personnel"], catalog_ids(workspace))
	t.assert_equal("工作区 / 三个资料栏目", 3, workspace.category_buttons.size())
	workspace._select_category(0)
	for id: String in ["identity", "task", "floor"]:
		workspace.open_document(Docs.ref(id))
	workspace.arrange_windows()
	await frames(tree)
	t.assert_equal("工作区 / 三份同时打开", 3, workspace.windows.size())
	t.assert_equal("工作区 / 切换条独立列出三窗", 3, workspace.switch_buttons.size())
	var strip_order: Array = workspace.switch_buttons.keys()
	var rects: Dictionary = {}
	for window_key: String in workspace.windows:
		var open_window: DocumentWindow = workspace.windows[window_key]
		rects[window_key] = Rect2(open_window.position, open_window.size)
	var switch_button: Button = workspace.switch_buttons["preview/identity@1"]
	mouse(viewport, switch_button.get_global_rect().get_center(), true)
	mouse(viewport, switch_button.get_global_rect().get_center(), false)
	await frames(tree)
	t.assert_equal("工作区 / 鼠标切换条置顶", "preview/identity@1", workspace._active_key)
	t.assert_true("工作区 / 当前窗口有切换条标记", switch_button.button_pressed)
	switch_button = workspace.switch_buttons["preview/task@1"]
	switch_button.grab_focus()
	key(viewport, KEY_ENTER)
	await frames(tree)
	t.assert_true("工作区 / Enter切换聚焦阅读窗", workspace.windows["preview/task@1"].scroll.has_focus())
	workspace.switch_buttons["preview/floor@1"].grab_focus()
	joy(viewport, JOY_BUTTON_A)
	await frames(tree)
	t.assert_equal("工作区 / 手柄A切换窗口", "preview/floor@1", workspace._active_key)
	t.assert_equal("工作区 / 置顶不改变切换条顺序", strip_order, workspace.switch_buttons.keys())
	for window_key: String in rects:
		var open_window: DocumentWindow = workspace.windows[window_key]
		t.assert_equal("工作区 / 切换不移动并排窗口", rects[window_key], Rect2(open_window.position, open_window.size))
	var task: DocumentWindow = workspace.windows["preview/task@1"]
	var identity: DocumentWindow = workspace.windows["preview/identity@1"]
	t.assert_equal("工作区 / 身份证明为乘客实收", "passenger", identity.receipt.route)
	t.assert_equal("工作区 / 楼层档案为右台取得", "right", workspace.windows["preview/floor@1"].receipt.route)
	t.assert_false("工作区 / 单版本隐藏历史入口", task.history_button.visible)
	# 此用例先把正文窗缩到确实存在溢出的阅读尺寸，避免无滚动范围时断言滚动。
	workspace._arranged = false
	task.size = Vector2(400, 220)
	task.constrain()
	task.scroll.grab_focus()
	await tree.create_timer(0.04).timeout
	key(viewport, KEY_PAGEDOWN)
	await frames(tree)
	var reading := task.scroll.scroll_vertical
	t.assert_true("工作区 / 真实PageDown进入正文", reading > 0)
	t.assert_equal("工作区 / 另窗独立滚动", 0, identity.scroll.scroll_vertical)
	key(viewport, KEY_TAB)
	t.assert_false("工作区 / Tab离开正文", task.scroll.has_focus())
	key(viewport, KEY_TAB, true)
	t.assert_true("工作区 / ShiftTab返回正文", task.scroll.has_focus())
	key(viewport, KEY_UP)
	await frames(tree)
	t.assert_true("工作区 / Up仅向上滚动正文", task.scroll.scroll_vertical < reading)
	task.scroll.scroll_vertical = reading
	task.close_button.grab_focus()
	# 原生按钮完整按下/释放，只关闭一次。
	key(viewport, KEY_SPACE)
	await frames(tree)
	t.assert_false("工作区 / Space关闭单窗", workspace.windows.has("preview/task@1"))
	t.assert_true("工作区 / 关闭后焦点留在W", terminal.screen.is_ancestor_of(viewport.gui_get_focus_owner()))
	var focus_after_close := viewport.gui_get_focus_owner()
	t.assert_true("工作区 / 关闭当前窗后焦点落到相邻切换项", focus_after_close in workspace.switch_buttons.values())
	t.assert_false("工作区 / 关闭即移除切换项", workspace.switch_buttons.has("preview/task@1"))
	Docs.supplement(manager)
	await frames(tree)
	var event_count := manager.get_document_events(manager.get_document_session_id()).size()
	var requests := manager.get_material_requests(manager.get_document_session_id()).size()
	t.assert_equal("工作区 / 新版本刷新不重建无关窗口", identity, workspace.windows["preview/identity@1"])
	t.assert_true("工作区 / 无关刷新不抢焦点", viewport.gui_get_focus_owner() == focus_after_close)
	t.assert_equal("工作区 / 保留两个任务版本历史", 2, _versions(workspace, "preview/task"))
	workspace._select_category(0)
	activate_catalog(workspace, viewport, Docs.ref("task", 2))
	await frames(tree)
	var latest_task: DocumentWindow = workspace.windows["preview/task@2"]
	t.assert_true("工作区 / 有已取得旧版才显示入口", latest_task.history_button.visible)
	t.assert_false("工作区 / 新窗历史默认折叠", latest_task.history_list.visible)
	latest_task.scroll.scroll_vertical = 60
	await frames(tree)
	var latest_reading := latest_task.scroll.scroll_vertical
	latest_task.history_button.grab_focus()
	key(viewport, KEY_ENTER)
	await frames(tree)
	t.assert_equal("工作区 / 展开历史可见列表起点", 0, latest_task.scroll.scroll_vertical)
	key(viewport, KEY_ENTER)
	await frames(tree)
	t.assert_equal("工作区 / 收折历史恢复正文位置", latest_reading, latest_task.scroll.scroll_vertical)
	key(viewport, KEY_ENTER)
	await frames(tree)
	t.assert_equal("工作区 / 历史仅旧版不重复最新", [Docs.ref("task")], history_refs(latest_task))
	activate_history(latest_task, viewport, Docs.ref("task"))
	await frames(tree)
	task = workspace.windows["preview/task@1"]
	t.assert_equal("工作区 / 文件内重开已关闭v1", 1, task.receipt.document.version)
	t.assert_equal("工作区 / 关闭后旧版恢复滚动", reading, task.scroll.scroll_vertical)
	t.assert_true("工作区 / 旧版显示新版提示", task.update_button.visible and task.version_label.text.contains("旧版"))
	task.update_button.grab_focus()
	key(viewport, KEY_ENTER)
	await frames(tree)
	t.assert_true("工作区 / Enter查看新版且旧版保留", workspace.windows.has("preview/task@2") and workspace.windows.has("preview/task@1"))
	t.assert_equal("工作区 / 重复查看不增加切换项", 4, workspace.switch_buttons.size())
	var old_field := manager.get_acquired_field(manager.get_document_session_id(),
		{"document_id":"preview/task", "version":1, "field_id":"destination"})
	t.assert_equal("工作区 / 旧FieldRef固定001", "001", old_field.comparable_value)
	t.assert_equal("工作区 / 读历史不产生取得事件", event_count, manager.get_document_events(manager.get_document_session_id()).size())
	t.assert_equal("工作区 / 刷新不产生索证", requests, manager.get_material_requests(manager.get_document_session_id()).size())
	workspace.close_window("preview/floor@1")
	workspace.open_reference(Docs.ref("rules"))
	await frames(tree)
	workspace.arrange_windows()
	await frames(tree)
	workspace._select_category(2)
	t.assert_equal("工作区 / 已取得规程不进入调阅栏目", ["preview/floor", "preview/personnel"], catalog_ids(workspace))
	workspace.arrange_windows()
	await frames(tree)
	t.assert_true("工作区 / 规程与乘客资料同屏", workspace.windows.has("preview/rules@1") and workspace.windows.has("preview/identity@1"))
	for window in workspace.windows.values():
		t.assert_true("工作区 / 自动并排在屏内", Rect2(Vector2.ZERO, workspace.desk.size).encloses(Rect2(window.position, window.size)))
	var all_windows := workspace.desk.get_children()
	for i in all_windows.size():
		for j in range(i + 1, all_windows.size()):
			t.assert_false("工作区 / 自动并排不覆盖正文", Rect2(all_windows[i].position, all_windows[i].size).intersects(Rect2(all_windows[j].position, all_windows[j].size)))
	# 真实鼠标事件拖动标题、操作角柄，鼠标松开后不继续移动。
	workspace._arranged = false
	task.size = Vector2(400, 220)
	task.position = Vector2(4, 4)
	await frames(tree)
	var start := task.title_label.get_global_rect().get_center()
	var before_position := task.position
	mouse(viewport, start, true)
	motion(viewport, start + Vector2(25, 12))
	mouse(viewport, start + Vector2(25, 12), false)
	t.assert_true("工作区 / 标题拖动更新位置", task.position.distance_to(before_position) > 5)
	var grip := task.get_child(task.get_child_count() - 1) as Control
	await frames(tree)
	start = grip.get_global_rect().get_center()
	var before_size := task.size
	mouse(viewport, start, true)
	motion(viewport, start + Vector2(20, 15))
	mouse(viewport, start + Vector2(20, 15), false)
	t.assert_true("工作区 / 单角柄可靠缩放", task.size.x > before_size.x)
	workspace.arrange_windows()
	await frames(tree)
	task.scroll.grab_focus()
	var prior := task.scroll.scroll_vertical
	key(viewport, KEY_W)
	await tree.create_timer(0.05).timeout
	key(viewport, KEY_W)
	await tree.create_timer(0.05).timeout
	t.assert_equal("工作区 / 同单收起展开保留窗口", 4, workspace.windows.size())
	t.assert_equal("工作区 / 同单收起展开保留阅读", prior, task.scroll.scroll_vertical)
	t.assert_true("工作区 / 同单收起展开恢复焦点", task.scroll.has_focus())
	for n in 28:
		key(viewport, KEY_TAB)
		t.assert_true("工作区 / Tab循环不进入后台", terminal.screen.is_ancestor_of(viewport.gui_get_focus_owner()))
	# 刷新历史时既不自动展开，也不把焦点留在已移除的旧控件上。
	latest_task.history_button.grab_focus()
	if not latest_task.history_list.visible:
		key(viewport, KEY_ENTER)
	await frames(tree)
	for button in latest_task.history_list.get_children():
		if button is Button and not button.disabled:
			button.grab_focus()
	manager.receive_passenger_batch(manager.get_document_session_id(), &"preview:third", [Docs.ref("task", 3)])
	await frames(tree)
	t.assert_equal("工作区 / 多个旧版按倒序且不重复", [Docs.ref("task", 2), Docs.ref("task")], history_refs(latest_task))
	t.assert_true("工作区 / 历史控件更新后焦点回到入口", latest_task.history_button.has_focus())
	key(viewport, KEY_ENTER)
	await frames(tree)
	t.assert_false("工作区 / 历史收折", latest_task.history_list.visible)
	t.assert_true("工作区 / 收折后焦点仍有效", latest_task.history_button.has_focus())
	for window_key: String in workspace.windows.keys():
		workspace.windows[window_key].close_button.grab_focus()
		key(viewport, KEY_SPACE)
		await frames(tree)
	t.assert_equal("工作区 / 全部关闭清空切换条", 0, workspace.switch_buttons.size())
	t.assert_true("工作区 / 最后窗口关闭有安全焦点", workspace.arrange_button.has_focus())
	# 右台档案同样可从所属栏目打开最新，再从文件内恢复旧版。
	workspace.open_document(Docs.ref("floor"))
	workspace.close_window("preview/floor@1")
	manager.accept_right_lookup_result(manager.get_document_session_id(), &"preview:right:2", [Docs.ref("floor", 2)])
	workspace._select_category(2)
	var before_history_events := manager.get_document_events(manager.get_document_session_id()).size()
	activate_catalog(workspace, viewport, Docs.ref("floor", 2))
	await frames(tree)
	var latest_floor: DocumentWindow = workspace.windows["preview/floor@2"]
	latest_floor.history_button.grab_focus()
	key(viewport, KEY_ENTER)
	await frames(tree)
	activate_history(latest_floor, viewport, Docs.ref("floor"))
	await frames(tree)
	t.assert_true("工作区 / 右台文件旧版关闭后可重开", workspace.windows.has("preview/floor@1"))
	t.assert_equal("工作区 / 右台历史阅读不重新查询", before_history_events, manager.get_document_events(manager.get_document_session_id()).size())
	workspace.close_window("preview/floor@1")
	workspace.close_window("preview/floor@2")
	workspace.open_reference(Docs.ref("rules"))
	workspace.close_window("preview/rules@1")
	workspace.open_reference(Docs.ref("rules", 2))
	workspace.close_window("preview/rules@2")
	workspace._select_category(1)
	t.assert_equal("工作区 / 系统参考多个版本仍只一项", ["preview/rules", "preview/sample"], catalog_ids(workspace))
	before_history_events = manager.get_document_events(manager.get_document_session_id()).size()
	activate_catalog(workspace, viewport, Docs.ref("rules", 2))
	await frames(tree)
	var latest_rules: DocumentWindow = workspace.windows["preview/rules@2"]
	latest_rules.history_button.grab_focus()
	key(viewport, KEY_ENTER)
	await frames(tree)
	activate_history(latest_rules, viewport, Docs.ref("rules"))
	await frames(tree)
	t.assert_true("工作区 / 系统参考旧版关闭后可重开", workspace.windows.has("preview/rules@1"))
	t.assert_equal("工作区 / 系统参考历史不重新取得", before_history_events, manager.get_document_events(manager.get_document_session_id()).size())
	manager.receive_passenger_batch(manager.get_document_session_id(), &"preview:first-v2", [Docs.ref("first_v2", 2)])
	workspace.open_document(Docs.ref("first_v2", 2))
	await frames(tree)
	t.assert_false("工作区 / 首次仅取得v2不假设有旧版", workspace.windows["preview/first_v2@2"].history_button.visible)
	manager.start_dispatch(&"TEST_CASE_001")
	await frames(tree)
	t.assert_equal("工作区 / 同ID重开清窗口", 0, workspace.windows.size())
	t.assert_equal("工作区 / 同ID重开清历史", 0, workspace._history.size())
	t.assert_equal("工作区 / 同ID重开清切换条", 0, workspace.switch_buttons.size())
	workspace.open_document(Docs.ref("task"))
	t.assert_equal("工作区 / 新会话拒绝旧引用", 0, workspace.windows.size())
	definition.documents = saved
	tree.root.size = original_size
	main.queue_free()
	await frames(tree)
	print("VERIFICATION WORKSPACE TESTS COMPLETE")

func _versions(workspace: VerificationWorkspace, id: String) -> int:
	var count: int = 0
	for ref: Dictionary in workspace._history.values():
		if ref.document_id == id:
			count += 1
	return count

func key(viewport: Viewport, code: Key, shift: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = pressed
		viewport.push_input(event, true)

func frames(tree: SceneTree) -> void:
	for n in 6:
		await tree.process_frame
func mouse(viewport: Viewport, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	viewport.push_input(event, true)

func motion(viewport: Viewport, at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	viewport.push_input(event, true)


func catalog_ids(workspace: VerificationWorkspace) -> Array[String]:
	var ids: Array[String] = []
	for child in workspace.catalog.get_children():
		var ref: Dictionary = child.get_meta("document_ref", {})
		if not ref.is_empty():
			ids.append(ref.document_id)
	ids.sort()
	return ids

func history_refs(window: DocumentWindow) -> Array[Dictionary]:
	var refs: Array[Dictionary] = []
	for button in window.history_list.get_children():
		refs.append(button.get_meta("document_ref").duplicate())
	return refs

func activate_catalog(workspace: VerificationWorkspace, viewport: Viewport, ref: Dictionary) -> void:
	for button in workspace.catalog.get_children():
		if button is Button and button.get_meta("document_ref", {}) == ref:
			button.grab_focus()
			key(viewport, KEY_ENTER)
			return

func activate_history(window: DocumentWindow, viewport: Viewport, ref: Dictionary) -> void:
	for button in window.history_list.get_children():
		if button is Button and button.get_meta("document_ref", {}) == ref and not button.disabled:
			button.grab_focus()
			key(viewport, KEY_ENTER)
			return

func joy(viewport: Viewport, button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		viewport.push_input(event, true)
