extends RefCounted
const MAIN := preload("res://scenes/main/main_3d.tscn")
const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Docs := preload("res://tests/fixtures/runtime/test_workspace_documents.gd")
const Statements := preload("res://tests/fixtures/runtime/test_statement_selection.gd")
const Review := preload("res://tests/fixtures/runtime/test_document_review.gd")

func run(t: Variant, tree: SceneTree) -> void:
	var original_size := tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	await _test_statement_selection(t, tree)
	await _test_review_cards(t, tree)
	var definition: DispatchDefinition = ContentRegistry.get_dispatch("TEST_CASE_001")
	var saved: Array[DocumentDefinition] = definition.documents
	definition.documents = Docs.definitions(true)
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
	t.assert_true("工作区 / 无证据时也常驻两张卡，质疑仍禁用",
		workspace._review_panel.visible and workspace._challenge.disabled
		and workspace._evidence_buttons.all(func(button: Button) -> bool:
			return button.disabled and button.text == "未选择证据"))
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
	t.assert_equal("工作区 / 人员记录只包含左台结果", ["preview/personnel"], catalog_ids(workspace))
	workspace._select_category(3)
	t.assert_equal("工作区 / 楼层档案只包含右台结果", ["preview/floor"], catalog_ids(workspace))
	workspace._select_category(4)
	t.assert_true("工作区 / 未摘录的陈述不出现", catalog_ids(workspace).is_empty())
	t.assert_equal("工作区 / 五个资料栏目", 5, workspace.category_buttons.size())
	t.assert_true("工作区 / 展开其他分类保留原目录文件",
		workspace._catalog_lists[0].visible and workspace._catalog_lists[3].visible)
	workspace.category_buttons[3].grab_focus()
	await frames(tree)
	key(viewport, KEY_ENTER)
	t.assert_true("工作区 / 键盘只收起当前分类",
		workspace._catalog_lists[0].visible and not workspace._catalog_lists[3].visible)
	workspace._select_category(3)
	await frames(tree)
	_catalog_entry(workspace, Docs.ref("floor")).grab_focus()
	workspace._set_directory_visible(false)
	t.assert_true("工作区 / 总开关收起后保留焦点",
		workspace.directory_button.has_focus() and not workspace.catalog_scroll.visible)
	workspace._set_directory_visible(true)
	workspace._select_category(0)
	for id: String in ["identity", "task", "floor"]:
		workspace.open_document(Docs.ref(id))
	workspace.arrange_windows()
	await frames(tree)
	t.assert_equal("工作区 / 三份同时打开", 3, workspace.windows.size())
	workspace._select_category(0)
	await frames(tree)
	workspace._arranged = false
	# 人为重叠两窗，目录应找回同一版本、同一实例。
	var original_identity: DocumentWindow = workspace.windows["preview/identity@1"]
	original_identity.position = workspace.windows["preview/task@1"].position
	workspace.raise_window("preview/task@1")
	var rects: Dictionary = {}
	for window_key: String in workspace.windows:
		var open_window: DocumentWindow = workspace.windows[window_key]
		rects[window_key] = Rect2(open_window.position, open_window.size)
	var entry := _catalog_entry(workspace, Docs.ref("identity"))
	mouse(viewport, entry.get_global_rect().get_center(), true)
	mouse(viewport, entry.get_global_rect().get_center(), false)
	await frames(tree)
	t.assert_equal("工作区 / 鼠标目录找回同一遮挡窗", original_identity, workspace.windows.get("preview/identity@1"))
	t.assert_true("工作区 / 鼠标找回置顶并聚焦正文", original_identity.scroll.has_focus()
		and workspace.desk.get_child(-1) == original_identity)
	activate_catalog(workspace, viewport, Docs.ref("task"))
	await frames(tree)
	t.assert_true("工作区 / Enter目录聚焦阅读窗", workspace.windows["preview/task@1"].scroll.has_focus())
	workspace._select_category(3)
	_catalog_entry(workspace, Docs.ref("floor")).grab_focus()
	joy(viewport, JOY_BUTTON_A)
	await frames(tree)
	t.assert_equal("工作区 / 手柄A从目录找回窗口", "preview/floor@1", workspace._active_key)
	t.assert_equal("工作区 / 目录找回不会创建重复窗", 3, workspace.windows.size())
	for window_key: String in rects:
		var open_window: DocumentWindow = workspace.windows[window_key]
		t.assert_equal("工作区 / 找回不移动现有窗口", rects[window_key], Rect2(open_window.position, open_window.size))
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
	t.assert_true("工作区 / 关闭当前窗后焦点落到剩余正文",
			windows_scroll_has_focus(workspace))
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
	t.assert_equal("工作区 / 重复查看不重复开窗", 4, workspace.windows.size())
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
	t.assert_equal("工作区 / 已取得规程不进入人员目录", ["preview/personnel"], catalog_ids(workspace))
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
	start = task.title_label.get_global_rect().get_center()
	mouse(viewport, start, true)
	terminal._on_focus_exited()
	before_position = task.position
	motion(viewport, start + Vector2(32, 32))
	mouse(viewport, start + Vector2(32, 32), false)
	t.assert_equal("工作区 / 失焦后拖动不残留", before_position, task.position)
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
	t.assert_equal("工作区 / 全部关闭清空桌面", 0, workspace.desk.get_child_count())
	t.assert_true("工作区 / 最后窗口关闭有安全焦点", workspace.arrange_button.has_focus())
	# 右台档案同样可从所属栏目打开最新，再从文件内恢复旧版。
	workspace.open_document(Docs.ref("floor"))
	workspace.close_window("preview/floor@1")
	manager.accept_right_lookup_result(manager.get_document_session_id(), &"preview:right:2", [Docs.ref("floor", 2)])
	workspace._select_category(3)
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
	t.assert_equal("工作区 / 同ID重开清活动窗", "", workspace._active_key)
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

func _test_statement_selection(t: Variant, tree: SceneTree) -> void:
	var saved: Dictionary = ContentRegistry.get("_dispatches_by_id")
	var main := Statements.prepare()
	t.add_child(main)
	await frames(tree)
	var terminal := Statements.open_preview(main)
	var viewport := terminal.get_viewport()
	var workspace := terminal.workspace
	await tree.create_timer(terminal.slide_duration + 0.08).timeout
	workspace.open_document(Statements.ref("application"))
	await frames(tree)
	var window: DocumentWindow = workspace.windows["statement/application@1"]
	var text := window._quote_body
	t.assert_true("摘取原文 / 质疑禁用", workspace._challenge.disabled)
	t.assert_false("摘取原文 / 尚无选区时隐藏按钮", window._quote_join.visible)
	# 使用控件原生选区，命中与拖动由可见的实机预览另外验证。
	text.select(0, 8, 0, 5)
	window._finish_quote_drag(window._selection_generation, true)
	t.assert_equal("摘取原文 / 反向选区只摘取数字", "001", window._candidate.get("quote", ""))
	t.assert_false("摘取原文 / 局部选区无结构化字段", window._candidate.has("field_id"))
	t.assert_equal("摘取原文 / 区间准确", [5, 8], [window._candidate.get("start"), window._candidate.get("end")])
	t.assert_true("摘取原文 / 选区只展示加入按钮", window._quote_join.visible and workspace._slots[0].is_empty())
	window.cancel_statement_selection()
	text.select(0, 8, 1, text.get_line(1).length())
	window._finish_quote_drag(window._selection_generation, true)
	var expected_cross_line := " 层处理维修任务。\n现场记录 [待填写]。"
	t.assert_equal("摘取原文 / 跨段保留换行、空格和标点", expected_cross_line, window._candidate.get("quote", ""))
	await frames(tree)
	var join_at := window._quote_join.get_global_rect().get_center()
	mouse(viewport, join_at, true)
	mouse(viewport, join_at, false)
	await frames(tree)
	t.assert_equal("摘取原文 / 无映射的跨段片段可入槽", expected_cross_line, workspace._slots[0].get("quote", ""))
	t.assert_true("摘取原文 / 入槽显示引文与出处",
		workspace._evidence_buttons[0].text.begins_with("维修申请 · v1 · ")
		and window.receipt.document.source.source_id in workspace._evidence_buttons[0].text
		and expected_cross_line.replace("\n", " ") in workspace._evidence_buttons[0].text)
	workspace._evidence_buttons[0].grab_focus()
	key(viewport, KEY_ENTER)
	await frames(tree)
	t.assert_equal("摘取原文 / 定位后高亮原选区", expected_cross_line, text.get_selected_text())
	t.assert_false("摘取原文 / 定位不再次显示加入按钮", window._quote_join.visible)

	workspace.open_document(Statements.ref("task"))
	await frames(tree)
	var task: DocumentWindow = workspace.windows["statement/task@1"]
	task._quote_body.grab_focus()
	workspace.move_focus(1)
	t.assert_equal("摘取原文 / 手柄可聚焦无映射段落", 1, task._quote_body.get_caret_line())
	joy(viewport, JOY_BUTTON_A)
	t.assert_true("摘取原文 / 手柄确认后高亮段落并聚焦加入", task._quote_join.has_focus())
	t.assert_true("摘取原文 / 手柄第一次确认不入槽", workspace._slots[1].is_empty())
	joy(viewport, JOY_BUTTON_B)
	t.assert_true("摘取原文 / 取消后回到正文", terminal.target_open and task._quote_body.has_focus() and not task._quote_body.has_selection())
	joy(viewport, JOY_BUTTON_A)
	joy(viewport, JOY_BUTTON_A)
	await frames(tree)
	t.assert_equal("摘取原文 / 取消后仍可用两次确认加入", "记录供本班交接使用。", workspace._slots[1].get("quote", ""))

	workspace.open_reference(Statements.ref("regulation"))
	await frames(tree)
	var rules: DocumentWindow = workspace.windows.get("statement/regulation@1")
	t.assert_true("摘取原文 / 从既有入口取得规程", rules != null)
	if rules != null:
		rules._quote_body.grab_focus()
		joy(viewport, JOY_BUTTON_A)
		t.assert_equal("摘取原文 / 完整条款保留映射", "applicable", rules._candidate.get("field_id", ""))
		joy(viewport, JOY_BUTTON_A)
		t.assert_equal("摘取原文 / 满槽不覆盖", "记录供本班交接使用。", workspace._slots[1].get("quote", ""))
		workspace._clear_review_field(0)
		t.assert_true("摘取原文 / 清左后右槽位置不变", workspace._slots[0].is_empty()
			and workspace._slots[1].get("quote", "") == "记录供本班交接使用。")
		rules._quote_body.grab_focus()
		joy(viewport, JOY_BUTTON_A)
		joy(viewport, JOY_BUTTON_A)
		t.assert_equal("摘取原文 / 完整条款生成既有引用", Statements.ref("regulation", "applicable"),
			workspace._review_ref(workspace._slots[0]) if not workspace._slots[0].is_empty() else {})
		rules._quote_body.grab_focus()
		joy(viewport, JOY_BUTTON_A)
		key(viewport, KEY_W)
		await frames(tree)
		t.assert_true("摘取原文 / 收起清选区并保留槽位", rules._candidate.is_empty() and not workspace._slots[0].is_empty())
	workspace.reset_session(0)
	t.assert_equal("摘取原文 / 换单清空槽位", [{}, {}], workspace._slots)
	main.queue_free()
	await frames(tree)
	ContentRegistry.set("_dispatches_by_id", saved)


func _test_review_cards(t: Variant, tree: SceneTree) -> void:
	var saved: Dictionary = ContentRegistry.get("_dispatches_by_id")
	var main := Review.prepare()
	t.add_child(main)
	await frames(tree)
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	var terminal := main.find_child("核验终端", true, false) as VerificationTerminal3D
	var workspace := terminal.workspace
	var viewport := terminal.get_viewport()
	terminal.slide_duration = 0.01
	manager.start_dispatch(Review.CASE)
	var session := manager.get_document_session_id()
	Review.submit_fixture_documents(manager)
	terminal.set_open(true)
	await tree.create_timer(0.05).timeout
	workspace.open_reference(Review.ref("regulation"))
	workspace.open_document(Review.ref("application"))
	workspace.open_document(Review.ref("task"))
	await frames(tree)
	var clause := Review.ref("regulation", "applicable")
	var application := Review.ref("application", "destination")
	var task := Review.ref("task", "destination")
	var application_window: DocumentWindow = workspace.windows["review/application@1"]
	workspace.raise_window("review/application@1")
	var row := application_window._field_labels["destination"].get_parent() as Control
	application_window.scroll.ensure_control_visible(row)
	await frames(tree)
	mouse(viewport, row.get_global_rect().get_center(), true)
	mouse(viewport, row.get_global_rect().get_center(), false)
	t.assert_equal("证据框 / 点击正文整行取得原字段引用", application, workspace._slots[0])
	t.assert_true("证据框 / 入槽后才标记字段选中", application_window._selected_fields.has("destination"))
	workspace._add_review_field(clause)
	var clear_left := workspace._evidence_buttons[0].get_parent().get_child(1) as Button
	mouse(viewport, clear_left.get_global_rect().get_center(), true)
	mouse(viewport, clear_left.get_global_rect().get_center(), false)
	t.assert_equal("证据框 / ×只清左槽，保留右槽", [{}, clause], workspace._slots)
	t.assert_true("证据框 / 清空不触发定位且焦点留在×", clear_left.has_focus())
	t.assert_false("证据框 / 清槽同步取消字段选中", application_window._selected_fields.has("destination"))
	t.assert_false("证据框 / 仅右侧有效条款仍可索证", workspace._challenge.disabled)
	workspace._challenge.grab_focus()
	key(viewport, KEY_ENTER)
	t.assert_equal("证据框 / 仅右槽从正式界面提交原索证", 1, manager.get_material_requests(session).size())

	# 模拟这一笔确已提交的交付发生技术失败。3A 只展示失败，不复投。
	var failed := manager.take_pending_passenger_event()
	manager.finish_passenger_event(failed, "", [])
	await frames(tree)
	t.assert_true("证据框 / 显示真实失败且未自动重试", workspace._delivery_feedback.visible
		and manager.get_review_deliveries(session).size() == 1
		and manager.get_review_deliveries(session)[0].status == "failed")
	t.assert_true("证据框 / 正式界面无重试入口",
		workspace._review_buttons.all(func(button: Button) -> bool: return button.text != "重试回应"))

	workspace._clear_review_field(1)
	workspace._add_review_field(application)
	workspace._add_review_field(Review.ref("access", "destination"))
	workspace._challenge.grab_focus()
	key(viewport, KEY_ENTER)
	t.assert_equal("证据框 / 无匹配规则不创建交付", 1, manager.get_review_deliveries(session).size())
	workspace._clear_review_field(1)
	workspace._add_review_field(task)
	workspace._challenge.grab_focus()
	key(viewport, KEY_ENTER)
	t.assert_equal("证据框 / 双字段从正式界面提交质疑", 1, manager.get_contradiction_challenges(session).size())
	manager.accept_left_lookup_result(session, &"review-fixture-left-v2", [Review.ref("task", "", 2)])
	workspace.open_document(Review.ref("task", "", 2))
	workspace.close_window("review/task@1")
	await frames(tree)
	t.assert_true("证据框 / 旧版证据不可提交", workspace._challenge.disabled)
	workspace._evidence_buttons[1].grab_focus()
	joy(viewport, JOY_BUTTON_A)
	await frames(tree)
	var located := workspace.windows.get("review/task@1") as DocumentWindow
	t.assert_true("证据框 / 手柄从证据找回旧版字段",
		located != null and located._located_field == located._field_labels.get("destination")
		and located.scroll.has_focus() and workspace.desk.get_child(-1) == located)
	if located != null:
		located._field_labels["complete"].text = located._field_labels["current"].text
		workspace._clear_review_field(1)
		workspace._add_review_field(Review.ref("task", "current"))
		workspace._evidence_buttons[1].grab_focus()
		key(viewport, KEY_ENTER)
		await frames(tree)
		t.assert_true("证据框 / 字段显示值相同仍按ID定位",
			located._located_field == located._field_labels["current"])
	workspace._locate_evidence(0)
	manager.start_dispatch(Review.CASE)
	await frames(tree)
	t.assert_true("证据框 / 换单撤销待完成的定位和旧交付提示",
		workspace.windows.is_empty() and not workspace._delivery_feedback.visible
		and terminal.close_button.has_focus())
	main.queue_free()
	await frames(tree)
	ContentRegistry.set("_dispatches_by_id", saved)


func windows_scroll_has_focus(workspace: VerificationWorkspace) -> bool:
	for window: DocumentWindow in workspace.windows.values():
		if window.scroll.has_focus():
			return true
	return false


func _catalog_entry(workspace: VerificationWorkspace, ref: Dictionary) -> Button:
	for button in workspace.catalog.get_children():
		if button is Button and button.get_meta("document_ref", {}) == ref:
			return button
	return null


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
