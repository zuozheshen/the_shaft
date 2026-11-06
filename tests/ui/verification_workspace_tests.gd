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
	for id: String in ["identity", "task", "floor"]:
		workspace.open_document(Docs.ref(id))
	workspace.arrange_windows()
	await frames(tree)
	t.assert_equal("工作区 / 三份同时打开", 3, workspace.windows.size())
	var task: DocumentWindow = workspace.windows["preview/task@1"]
	var identity: DocumentWindow = workspace.windows["preview/identity@1"]
	t.assert_equal("工作区 / 身份证明为乘客实收", "passenger", identity.receipt.route)
	t.assert_equal("工作区 / 楼层档案为右台取得", "right", workspace.windows["preview/floor@1"].receipt.route)
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
	Docs.supplement(manager)
	await frames(tree)
	var event_count := manager.get_document_events(manager.get_document_session_id()).size()
	var requests := manager.get_material_requests(manager.get_document_session_id()).size()
	t.assert_equal("工作区 / 新版本刷新不重建无关窗口", identity, workspace.windows["preview/identity@1"])
	t.assert_true("工作区 / 无关刷新不抢焦点", workspace.arrange_button.has_focus())
	t.assert_equal("工作区 / 保留两个任务版本历史", 2, _versions(workspace, "preview/task"))
	workspace._select_category(2)
	await frames(tree)
	var historical: Button
	for child in workspace.catalog.get_children():
		if child is Button and child.get_meta("document_ref", {}) == Docs.ref("task"):
			historical = child
	t.assert_true("工作区 / 历史目录含精确旧版本入口", historical != null)
	if historical != null:
		historical.grab_focus()
		key(viewport, KEY_ENTER)
	await frames(tree)
	task = workspace.windows["preview/task@1"]
	t.assert_equal("工作区 / 关闭后旧版原文仍为v1", 1, task.receipt.document.version)
	t.assert_equal("工作区 / 关闭后旧版恢复滚动", reading, task.scroll.scroll_vertical)
	t.assert_true("工作区 / 旧版显示新版提示", task.update_button.visible and task.version_label.text.contains("旧版"))
	task.update_button.grab_focus()
	key(viewport, KEY_ENTER)
	await frames(tree)
	t.assert_true("工作区 / Enter查看新版且旧版保留", workspace.windows.has("preview/task@2") and workspace.windows.has("preview/task@1"))
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
	manager.start_dispatch(&"TEST_CASE_001")
	await frames(tree)
	t.assert_equal("工作区 / 同ID重开清窗口", 0, workspace.windows.size())
	t.assert_equal("工作区 / 同ID重开清历史", 0, workspace._history.size())
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
