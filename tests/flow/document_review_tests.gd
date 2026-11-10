extends RefCounted

const Fixture := preload("res://tests/fixtures/runtime/test_document_review.gd")


func run(t: Variant, tree: SceneTree) -> void:
	var previous: Dictionary = ContentRegistry.get("_dispatches_by_id")
	var main := Fixture.prepare()
	t.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	var console := main.find_child("ConsoleInterface", true, false) as ConsoleInterface
	var port := manager.get_document_workspace_port()
	t.assert_false("审查 / W 无旧旁路", port.has("request_material") or port.has("record_contradiction_challenge") or port.has("apply_review_supplement"))
	manager.start_dispatch(Fixture.CASE)
	var session := manager.get_document_session_id()
	var clause := Fixture.ref("regulation", "applicable")
	var a := Fixture.ref("application", "destination")
	var b := Fixture.ref("task", "destination")
	var equivalent := Fixture.ref("access", "destination")
	t.assert_equal("审查 / 没有首批不允许登记", &"INITIAL_SUBMISSION_REQUIRED",
		port.submit_material_request.call(session, &"early", clause).code)
	Fixture.submit_fixture_documents(manager)
	t.assert_equal("审查 / 未取得规程拒绝", &"INVALID_FIELD_REF",
		port.submit_material_request.call(session, &"unread", clause).code)
	manager.open_system_reference(session, Fixture.ref("regulation"))
	manager.set_review_delivery_ready(Callable())
	t.assert_equal("审查 / 回应通道断开不登记", &"REVIEW_UNAVAILABLE",
		port.submit_document_challenge.call(session, &"offline", a, b).code)
	manager.set_review_delivery_ready(console._can_deliver_review)
	var definition := manager.get_active_dispatch()
	var title := definition.review_rules[1].response_title
	definition.review_rules[1].response_title = "missing"
	t.assert_equal("审查 / 缺标题不登记问题", &"REVIEW_UNAVAILABLE",
		port.submit_document_challenge.call(session, &"missing-title", a, b).code)
	definition.review_rules[1].response_title = title
	t.assert_true("审查 / 交付预检失败无记录", manager.get_review_deliveries(session).is_empty() and manager.get_contradiction_challenges(session).is_empty())
	var state := manager._document_state()
	# 在没有可读画面的测试里预占全部已解析槽，验证申请不会挤掉旧回应。
	for slot in range(DemoFlowManager.REVIEW_QUEUE_LIMIT):
		state.passenger_events["reserved:%d" % slot] = {"status": "resolved"}
	t.assert_equal("审查 / 满队列拒绝登记", &"REVIEW_QUEUE_FULL",
		port.submit_document_challenge.call(session, &"full", a, b).code)
	t.assert_true("审查 / 满队列保留已有回应", state.passenger_events.size() == DemoFlowManager.REVIEW_QUEUE_LIMIT \
		and manager.get_contradiction_challenges(session).is_empty())
	state.passenger_events.clear()
	t.assert_equal("审查 / 无依据组合给中性拒绝", &"REVIEW_NO_MATCH",
		port.submit_document_challenge.call(session, &"mismatch", a, equivalent).code)
	t.assert_equal("审查 / 先质疑可直接提交", &"REVIEW_SUBMITTED",
		port.submit_document_challenge.call(session, &"scope", a, b).code)
	t.assert_equal("审查 / A/B 交换同操作幂等", &"REVIEW_ALREADY_SUBMITTED",
		port.submit_document_challenge.call(session, &"scope", b, a).code)
	t.assert_equal("审查 / 等价依据同问题幂等", &"REVIEW_ALREADY_SUBMITTED",
		port.submit_document_challenge.call(session, &"scope-equivalent", equivalent, b).code)
	t.assert_equal("审查 / 同操作 ID 异载荷拒绝", &"EVENT_CONFLICT",
		port.submit_document_challenge.call(session, &"scope", equivalent, b).code)
	t.assert_equal("审查 / 已预占解析时另一个问题不登记", &"REVIEW_BUSY",
		port.submit_material_request.call(session, &"busy", clause).code)
	t.assert_true("审查 / 质疑不自动补证", manager.get_material_requests(session).is_empty())
	await tree.create_timer(0.24).timeout
	var first: Dictionary = manager.get_passenger_events()[0]
	t.assert_true("审查 / 解释完成只含乘客原句", first.status == "resolved" and first.rows.size() == 1 and first.rows[0].speaker == "Passenger")

	# 复现补件已落地、回应交付失败。重试必须沿用原问题与动作回执。
	var interrupted: Array[String] = []
	var old_attempt: Dictionary = {}
	manager.documents_changed.connect(func(current: int) -> void:
		for event: Dictionary in manager.get_passenger_events():
			if event.get("supplement_done", false) and event.status == "running" and interrupted.is_empty():
				interrupted.append(event.source_event_id)
				old_attempt.merge(event)
				manager.finish_passenger_event(event, "", [])
	)
	t.assert_equal("审查 / 索证独立于质疑", &"REVIEW_SUBMITTED",
		port.submit_material_request.call(session, &"permit", clause).code)
	await tree.create_timer(0.24).timeout
	var initial_count := manager.get_document_events(session).size()
	t.assert_equal("审查 / 相同补件动作实际只交一次", 2, manager.get_received_materials(session).size())
	var deliveries := manager.get_review_deliveries(session)
	t.assert_equal("审查 / 原交付保持可重试", "failed", deliveries.back().status)
	if interrupted.size() == 1:
		var delivery := interrupted[0]
		t.assert_equal("审查 / 重试同一交付", &"REVIEW_RETRIED",
			port.retry_review_delivery.call(session, &"retry", delivery).code)
		t.assert_equal("审查 / 重试复按幂等", &"REVIEW_ALREADY_SUBMITTED",
			port.retry_review_delivery.call(session, &"retry", delivery).code)
		await tree.process_frame
		await tree.process_frame
		manager.finish_passenger_event(old_attempt, "", [])
		t.assert_equal("审查 / 旧尝试回调不能终止本次重试", "running", manager.get_review_deliveries(session).back().status)
		await tree.create_timer(0.24).timeout
		var retried: Dictionary = manager.get_passenger_events().back()
		t.assert_true("审查 / 重试保留交付 ID 并推进尝试", retried.source_event_id == delivery and retried.attempt == 2 and retried.status == "resolved")
	t.assert_equal("审查 / 重试不重放已交材料", initial_count, manager.get_document_events(session).size())
	t.assert_equal("审查 / 只保留原两次问题", 2, manager.get_review_deliveries(session).size())
	t.assert_equal("审查 / 补件已提供后不再次发起", &"ALREADY_PROVIDED",
		port.submit_material_request.call(session, &"permit-again", clause).code)
	manager.note_passenger_event_drawn(session, first.source_event_id)
	t.assert_true("审查 / 已绘制回应可取得原文", manager.acquire_main_call_excerpt(session, first.source_event_id).succeeded)
	var excerpt := manager.get_acquired_document(session, {
		"document_id": "call_" + String(first.source_event_id).replace(":", "_"), "version": 1})
	t.assert_true("审查 / 摘录来源保存问题与固定字段引用",
		excerpt.document.source.review_origin == {"question_id": "verify_scope", "refs": first.review_refs})
	t.assert_false("审查 / 出处不写入乘客原文", "verify_scope" in excerpt.document.fields.utterance_001.display_value)
	manager.start_dispatch(Fixture.CASE)
	var new_session := manager.get_document_session_id()
	Fixture.submit_fixture_documents(manager, 2)
	t.assert_equal("审查 / 新版使历史依据失效", &"INVALID_FIELD_REF",
		port.submit_document_challenge.call(new_session, &"old", a, b).code)
	t.assert_equal("审查 / 覆盖申请楼层的正常任务不匹配质疑", &"REVIEW_NO_MATCH",
		port.submit_document_challenge.call(new_session, &"valid", a, Fixture.ref("task", "destination", 2)).code)
	t.assert_true("审查 / 换单撤销问题且不污染新单", manager.get_review_deliveries(new_session).is_empty())
	t.assert_true("审查 / 合规对照无质疑仍可登舱", manager.request_open_cabin_door().succeeded)
	t.assert_true("审查 / 对照已进入舱内", manager.is_passenger_onboard())
	t.assert_true("审查 / 对照可关门与核准路线",
		manager.request_close_cabin_door().succeeded and manager.request_validate_destination("900").succeeded)
	var travel := manager.request_travel_to_floor("900")
	t.assert_true("审查 / 对照无需质疑即可发车", travel.succeeded)
	if travel.succeeded:
		await manager.elevator_movement_completed
		t.assert_true("审查 / 对照可完成运输", manager.request_open_cabin_door().succeeded \
			and manager.request_finish_dropoff_feedback().succeeded and manager.request_close_cabin_door().succeeded)
	main.queue_free()
	await tree.process_frame
	ContentRegistry.set("_dispatches_by_id", previous)
