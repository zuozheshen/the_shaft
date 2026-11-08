extends RefCounted

const Fixture := preload("res://tests/fixtures/runtime/test_call_excerpt_fixture.gd")


func run(t: Variant, tree: SceneTree) -> void:
	var saved_dispatches: Dictionary = ContentRegistry.get("_dispatches_by_id")
	var main := Fixture.prepare()
	t.add_child(main)
	for frame in 4:
		await tree.process_frame
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	var console := main.find_child("ConsoleInterface", true, false) as ConsoleInterface
	var adapter := console.dialogue_manager_adapter
	var terminal := main.find_child("核验终端", true, false) as VerificationTerminal3D
	var hotspot := main.find_child("摘录热点", true, false) as InteractionHotspot3D
	var camera := terminal.get_parent() as Camera3D
	var viewport := camera.get_viewport()
	var point := camera.unproject_position(hotspot.global_position)
	t.assert_equal("摘录 / 唯一实体键", 1, main.find_children("摘录热点", "Area3D", true, false).size())
	_click(viewport, point)
	_assert_toast(t, console, "当前没有可摘录的乘客派单。")

	manager.start_dispatch(Fixture.FIRST)
	var session_a := manager.get_document_session_id()
	t.assert_false("摘录 / 换单清除旧 Toast", console.rejection_toast.visible)
	console.request_toggle_microphone()
	t.assert_true("摘录 / 真实 DM 开场已呈现", await _until(tree, func() -> bool: return console.dm_choices.size() == 2))
	_click(viewport, point)
	_assert_toast(t, console, "当前片段尚未完成。")

	var dm := tree.root.get_node("DialogueManager")
	var waits: Array[float] = []
	var on_mutated := func(mutation: Dictionary) -> void:
		if mutation.expression[0].get("function", "") in ["wait", "Wait"]:
			waits.append(Time.get_ticks_msec() / 1000.0)
	dm.mutated.connect(on_mutated)
	var a_done: Array[bool] = []
	_select_and_mark(console, 0, a_done)
	t.assert_true("摘录 / A 已进入 DM 的真实 wait", await _until(tree, func() -> bool: return waits.size() == 1))
	manager.start_dispatch(Fixture.SECOND)
	var session_b := manager.get_document_session_id()
	t.assert_true("摘录 / 不同乘客复用同一 Dialogue 资源", session_a != session_b)
	console.request_toggle_microphone()
	t.assert_true("摘录 / B 独立开场", await _until(tree, func() -> bool: return console.dm_choices.size() == 2))
	var b_done: Array[bool] = []
	_select_and_mark(console, 1, b_done)
	t.assert_true("摘录 / B 同时等待真实 DM", await _until(tree, func() -> bool: return waits.size() == 2))
	t.assert_true("摘录 / 旧选择已恢复", await _until(tree, func() -> bool: return not a_done.is_empty()))
	t.assert_true("摘录 / A 返回不能释放 B 忙碌状态", console._choice_in_progress and b_done.is_empty())
	t.assert_false("摘录 / 旧 mutation 未写 B 日志", str(manager.get_system_message_history()).contains("EXCERPT_A"))
	t.assert_false("摘录 / 旧 mutation 未解锁可推荐楼层", &"004" in manager.dispatch_lifecycle.get_recommended_floor_ids())
	t.assert_false("摘录 / 旧 mutation 未确认 B 门外乘客", manager.is_door_greeting_done())
	t.assert_true("摘录 / 旧门回复未进入 B 缓存", adapter.pending_open_door_reply.is_empty() and adapter.pending_close_door_reply.is_empty())
	t.assert_equal("摘录 / A 未覆盖 B 的 COMM", "乘客：我记得一部分。", console.current_passenger_line)
	_click(viewport, point)
	_assert_toast(t, console, "当前片段尚未完成。")
	t.assert_true("摘录 / 旧解析及未完成点击不写资料", manager.get_document_events(session_b).is_empty())

	console.comm_view.set_minimized(true)
	t.assert_true("摘录 / B 正常返回", await _until(tree, func() -> bool: return not b_done.is_empty()))
	t.assert_true("摘录 / 收起 COMM 时返回的答复尚不可摘录", adapter.get_current_excerpt().is_empty())
	_click(viewport, point)
	t.assert_true("摘录 / 后台答复不会进入 W", manager.get_document_events(session_b).is_empty())
	console.comm_view.set_minimized(false)
	t.assert_true("摘录 / 展开并呈现答复后可摘录", not adapter.get_current_excerpt().is_empty())
	t.assert_equal("摘录 / 合法提示恰执行一次", 1, str(manager.get_system_message_history()).count("EXCERPT_B_CURRENT"))
	t.assert_true("摘录 / 合法解锁及门控仍生效", &"742" in manager.dispatch_lifecycle.get_recommended_floor_ids() and manager.is_door_greeting_done())
	t.assert_equal("摘录 / 当前门缓存", "EXCERPT_B_OPEN", adapter.pending_open_door_reply)
	t.assert_equal("摘录 / 当前关门缓存", "EXCERPT_B_CLOSE", adapter.pending_close_door_reply)
	t.assert_false("摘录 / B 忙碌正常释放", console._choice_in_progress)
	t.assert_equal("摘录 / 下一组选择保留", 1, console.dm_choices.size())
	console.comm_view.set_minimized(true)
	_click(viewport, point)
	_assert_toast(t, console, "摘录已送入 W 收件箱。")
	t.assert_false("摘录 / 点击不会自动打开 W", terminal.target_open)
	var acquired := manager.get_acquired_documents(session_b)
	t.assert_equal("摘录 / 主台只取得一份", 1, acquired.size())
	if not acquired.is_empty():
		var item: Dictionary = acquired.front()
		var doc: Dictionary = item.document
		t.assert_equal("摘录 / 独立 main 取得渠道", "main", item.route)
		t.assert_equal("摘录 / 来源类型", "call_excerpt", doc.source.kind)
		t.assert_equal("摘录 / 只保留三条已呈现及选中的话", 3, doc.fields.size())
		var reply: Dictionary = doc.fields.utterance_003
		t.assert_equal("摘录 / 逐字保留不确定性", "我只记得可能是 002。", reply.comparable_value)
		t.assert_true("摘录 / 说话人与行出处", reply.display_value.begins_with("乘客：") and reply.source.origin_ref.begins_with(Fixture.DIALOGUE + "#"))
		t.assert_true("摘录 / 详情保留来源、顺序和时间", reply.source_note.contains("顺序") and reply.source_note.contains("UTC") and reply.source_note.contains(item.event_id))
		t.assert_false("摘录 / 正文不重复字段", doc.original_text.contains(reply.comparable_value))
		t.assert_false("摘录 / W 端口没有摘录写入口", manager.get_document_workspace_port().has("acquire_main_call_excerpt"))
	_click(viewport, point)
	_assert_toast(t, console, "该片段已摘录。")
	t.assert_equal("摘录 / 复按不产生新事件", 1, manager.get_document_events(session_b).size())
	t.assert_true("摘录 / 不视为乘客上传", manager.get_received_materials(session_b).is_empty())
	_key(viewport, KEY_W)
	t.assert_true("摘录 / W 已通过键盘展开", terminal.target_open)
	t.assert_equal("摘录 / 收件箱可直接查看主台摘录", 1, terminal.workspace.catalog.get_child_count())
	t.assert_true("摘录 / W 动画完成后可点目录", await _until(tree, func() -> bool: return is_equal_approx(terminal.open_progress, 1.0)))
	var entry := terminal.workspace.catalog.get_child(0) as Button
	if entry != null:
		_click(viewport, entry.get_global_rect().get_center())
	t.assert_equal("摘录 / 取得的文档可在 W 阅读", 1, terminal.workspace.windows.size())
	_click(viewport, point)
	t.assert_equal("摘录 / 展开 W 阻止背景按钮", 1, manager.get_document_events(session_b).size())
	manager.start_dispatch(Fixture.SECOND)
	t.assert_true("摘录 / 同 ID 重开撤销旧资料和窗口", manager.get_acquired_documents(session_b).is_empty() and terminal.workspace.windows.is_empty())
	terminal.set_open(false)

	# 同一资源、同一单重开与同会话跳标题都撤销旧解析。
	console.request_toggle_microphone()
	t.assert_true("摘录 / 重开后可选择", await _until(tree, func() -> bool: return console.dm_choices.size() == 2))
	console.comm_view.set_minimized(false)
	var superseded: Array[bool] = []
	_select_and_mark(console, 0, superseded)
	t.assert_true("摘录 / 新标题覆盖前已挂起", await _until(tree, func() -> bool: return waits.size() == 3))
	await adapter.show_title("statement")
	t.assert_true("摘录 / 旧标题解析已恢复", await _until(tree, func() -> bool: return not superseded.is_empty()))
	t.assert_false("摘录 / 旧标题 mutation 也被隔离", str(manager.get_system_message_history()).contains("EXCERPT_A"))
	t.assert_equal("摘录 / 直接陈述只有一行", 1, adapter.get_current_excerpt().get("rows", []).size())

	manager.start_dispatch(Fixture.SECOND)
	console.request_toggle_microphone()
	t.assert_true("摘录 / 清空前正常开场", await _until(tree, func() -> bool: return console.dm_choices.size() == 2))
	var cleared: Array[bool] = []
	_select_and_mark(console, 0, cleared)
	t.assert_true("摘录 / clear 前已挂起", await _until(tree, func() -> bool: return waits.size() == 4))
	manager.clear_active_dispatch()
	t.assert_true("摘录 / clear 后旧解析正常结束", await _until(tree, func() -> bool: return not cleared.is_empty()))
	t.assert_true("摘录 / clear 后无旧显示与缓存", adapter.get_current_excerpt().is_empty() and adapter.pending_open_door_reply.is_empty() and not console._choice_in_progress)
	# 已开始生效的 mutation 发信号时换单，后续 mutation 仍必须逐条复核。
	manager.start_dispatch(Fixture.SECOND)
	console.request_toggle_microphone()
	t.assert_true("摘录 / 重入换单前正常开场", await _until(tree, func() -> bool: return console.dm_choices.size() == 2))
	var switched: Array[bool] = []
	var on_status := func() -> void:
		if switched.is_empty() and manager.get_current_building_status_hint() == "EXCERPT_A_LATE":
			switched.append(true)
			manager.start_dispatch(Fixture.FIRST)
	manager.case_updated.connect(on_status)
	var interrupted: Array[bool] = []
	_select_and_mark(console, 0, interrupted)
	t.assert_true("摘录 / mutation 写入旧单后触发同步换单", await _until(tree, func() -> bool: return not interrupted.is_empty() and not switched.is_empty()))
	t.assert_true("摘录 / 同一解析后续 mutation 不改新单", not manager.is_door_greeting_done() and adapter.pending_open_door_reply.is_empty() and &"004" not in manager.dispatch_lifecycle.get_recommended_floor_ids())
	t.assert_false("摘录 / 重入时旧提示未写入新单", str(manager.get_system_message_history()).contains("EXCERPT_A"))
	manager.case_updated.disconnect(on_status)

	manager.start_shift(Fixture.Content.shift())
	console.request_toggle_microphone()
	t.assert_true("摘录 / 结束值班前正常开场", await _until(tree, func() -> bool: return console.dm_choices.size() == 2))
	var ending: Array[bool] = []
	_select_and_mark(console, 0, ending)
	t.assert_true("摘录 / 结束值班前已挂起", await _until(tree, func() -> bool: return waits.size() == 6))
	manager.finish_shift()
	t.assert_true("摘录 / 结束值班后旧解析返回", await _until(tree, func() -> bool: return not ending.is_empty()))
	t.assert_true("摘录 / 结束值班撤销旧业务与显示", manager.get_document_session_id() == 0 and adapter.get_current_excerpt().is_empty() and not str(manager.get_system_message_history()).contains("EXCERPT_A"))
	dm.mutated.disconnect(on_mutated)
	main.queue_free()
	await tree.process_frame
	ContentRegistry.set("_dispatches_by_id", saved_dispatches)
	print("CALL EXCERPT TESTS COMPLETE")


func _select_and_mark(console: ConsoleInterface, index: int, completion: Array[bool]) -> void:
	await console._select_dialogue_manager_choice(index)
	completion.append(true)


func _until(tree: SceneTree, predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	return predicate.call()


func _assert_toast(t: Variant, console: ConsoleInterface, expected: String) -> void:
	t.assert_true("摘录 / 正式 3D Toast 可见：" + expected, console.rejection_toast.is_visible_in_tree())
	t.assert_equal("摘录 / 实际 Toast 文案", expected, console.rejection_toast.text)
	t.assert_false("摘录 / 提示启动原计时器", console.toast_timer.is_stopped())


func _click(viewport: Viewport, position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		viewport.push_input(event, true)


func _key(viewport: Viewport, key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		viewport.push_input(event, true)
