extends RefCounted

const Fixture := preload("res://tests/fixtures/runtime/test_call_excerpt_fixture.gd")


func run(t: Variant, tree: SceneTree) -> void:
	# 专项夹具换过派单资源，结束后交回共用注册表。
	var dispatches: Dictionary = ContentRegistry.get("_dispatches_by_id")
	var main := Fixture.prepare()
	tree.root.add_child(main)
	await main.get_node("值守入口").start_duty()
	await tree.process_frame
	await tree.process_frame
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	var console := main.find_child("ConsoleInterface", true, false) as ConsoleInterface
	var resource := load(Fixture.DIALOGUE) as DialogueResource
	t.assert_false("事件陈述 / 拒绝玩家选项标题",
		DialogueManagerAdapter.is_event_title(resource, "rejected_choices"))
	t.assert_true("事件陈述 / 慢事件标题可解析",
		DialogueManagerAdapter.is_event_title(resource, "slow_statement"))
	manager.start_dispatch(Fixture.FIRST)
	await tree.process_frame
	await tree.process_frame
	var old_session := manager.get_document_session_id()
	var first := manager.get_passenger_events()
	t.assert_equal("事件陈述 / 换单前真实解析正在等待", "running",
		first[0].status if first.size() == 1 else "")
	var terminal := main.find_child("核验终端", true, false) as VerificationTerminal3D
	main.get_node("值守入口")._request_developer()
	# 等真实举起完成，再确认第三方等待已跨过暂停窗口。
	await terminal.slide_finished
	await tree.create_timer(0.28).timeout
	var waiting: Dictionary = manager.get_passenger_events()[0]
	t.assert_true("设置暂停 / 第三方等待到期仍不交付旧陈述",
		tree.paused and waiting.status == "running" and "OLD EVENT" not in manager.get_system_message_history())
	terminal.developer_panel.request_back()
	await terminal.slide_finished
	t.assert_false("设置暂停 / 收起后恢复业务时钟", tree.paused)
	manager.start_dispatch(Fixture.SECOND)
	await tree.create_timer(0.4).timeout
	var events := manager.get_passenger_events()
	t.assert_equal("事件陈述 / 新派单仅保留本单事件", 1, events.size())
	if events.size() == 1:
		var event: Dictionary = events[0]
		t.assert_true("事件陈述 / 新会话与原文来源分离",
			event.session != old_session and event.status == "resolved" and event.rows.size() == 2)
		if event.get("rows", []).size() == 2:
			t.assert_equal("事件陈述 / 保留预编写原文", "我只记得可能是 002。", event.rows[0].text)
			t.assert_equal("事件陈述 / 只有乘客发言", "Passenger", event.rows[0].speaker)
	t.assert_false("事件陈述 / 旧 mutation 不污染新派单",
		"OLD EVENT" in manager.get_system_message_history())
	var session := manager.get_document_session_id()
	var before := manager.get_acquired_documents(session).size()
	console.request_excerpt_current_call()
	t.assert_equal("摘录 / 解析成功不代表已呈现", before, manager.get_acquired_documents(session).size())
	if events.size() == 1 and events[0].get("rows", []).size() == 2:
		var event: Dictionary = events[0]
		var id: String = event.source_event_id
		t.assert_equal("摘录 / 明确事件仍须有末页回执", &"EXCERPT_NOT_PRESENTED",
			manager.acquire_main_call_excerpt(session, id).code)
		manager.note_passenger_event_drawn(old_session, id)
		t.assert_equal("摘录 / 旧会话回执无效", &"EXCERPT_NOT_PRESENTED",
			manager.acquire_main_call_excerpt(session, id).code)
		# Headless 验证业务回执门，正式屏幕实际绘制另做实机检查。
		manager.note_passenger_event_drawn(session, id)
		var result := manager.acquire_main_call_excerpt(session, id)
		t.assert_true("摘录 / 末页回执后可取得", result.succeeded)
		var received := manager.get_acquired_documents(session)
		t.assert_equal("摘录 / 只取得一份文档", 1, received.size())
		if received.size() == 1:
			var receipt: Dictionary = received[0]
			t.assert_equal("摘录 / 通过 main 渠道", "main", receipt.route)
			var document: Dictionary = receipt.document
			t.assert_true("摘录 / 事件、标题与版本可追溯",
				id in document.source.origin_ref and event.title in document.source.origin_ref
				and document.source.source_version == event.source_version)
			t.assert_equal("摘录 / 仅两行原文", 2, document.fields.size())
			for field_id: String in document.fields:
				var field: Dictionary = document.fields[field_id]
				t.assert_true("摘录 / 字段只属于乘客", field.subject_type == "passenger")
		var event_count := manager.get_document_events(session).size()
		t.assert_equal("摘录 / 同一源事件幂等", &"UNCHANGED", manager.acquire_main_call_excerpt(session, id).code)
		t.assert_equal("摘录 / 复按不增加取得事件", event_count, manager.get_document_events(session).size())
		t.assert_equal("摘录 / 未知事件不可取得", &"NO_EXCERPT", manager.acquire_main_call_excerpt(session, "unknown").code)
	manager.get_active_dispatch().dialogue_events["destination_opened"] = "statement"
	manager._record_passenger_event(session, "destination_opened", 2)
	await tree.process_frame
	await tree.process_frame
	var dropoff: Dictionary = manager.get_passenger_events().back()
	t.assert_true("事件陈述 / 带行程编号的开门回应成功写回",
		dropoff.key == "destination_opened" and dropoff.status == "resolved"
		and dropoff.get("rows", []).size() == 2 and String(dropoff.source_event_id).ends_with(":2"))
	manager.finish_shift()
	t.assert_true("事件陈述 / 值班结束清除缓存", manager.get_passenger_events().is_empty())
	main.queue_free()
	await tree.process_frame
	ContentRegistry.set("_dispatches_by_id", dispatches)
