extends Control
class_name DestinationControlInterface


signal return_requested


# 场景结构已固定，直接引用节点；节点改名或移动时 Godot 会直接报出明确错误。
@onready var root_margin: MarginContainer = $RootMargin
@onready var title_label: Label = $RootMargin/DestinationLayout/TitleLabel
@onready var dispatch_summary_label: Label = $RootMargin/DestinationLayout/DispatchSummaryLabel
@onready var recommended_destination_panel: PanelContainer = $RootMargin/DestinationLayout/RecommendedDestinationPanel
@onready var recommended_title_label: Label = $RootMargin/DestinationLayout/RecommendedDestinationPanel/RecommendedDestinationLayout/RecommendedTitleLabel
@onready var recommended_destination_buttons: Array[Button] = [
	$RootMargin/DestinationLayout/RecommendedDestinationPanel/RecommendedDestinationLayout/RecommendedDestinationButton1,
	$RootMargin/DestinationLayout/RecommendedDestinationPanel/RecommendedDestinationLayout/RecommendedDestinationButton2,
	$RootMargin/DestinationLayout/RecommendedDestinationPanel/RecommendedDestinationLayout/RecommendedDestinationButton3,
]
@onready var manual_destination_line_edit: LineEdit = $RootMargin/DestinationLayout/ManualInputPanel/ManualInputLayout/ManualDestinationLineEdit
@onready var verify_destination_button: Button = $RootMargin/DestinationLayout/ManualInputPanel/ManualInputLayout/VerifyDestinationButton
@onready var floor_overview_panel: PanelContainer = $RootMargin/DestinationLayout/FloorOverviewPanel
@onready var floor_overview_label: Label = $RootMargin/DestinationLayout/FloorOverviewPanel/FloorOverviewLabel
@onready var dispatch_evaluation_panel: PanelContainer = $RootMargin/DestinationLayout/DispatchEvaluationPanel
@onready var dispatch_evaluation_label: Label = $RootMargin/DestinationLayout/DispatchEvaluationPanel/DispatchEvaluationLabel
@onready var destination_feedback_label: Label = $RootMargin/DestinationLayout/DestinationFeedbackLabel
@onready var submit_destination_button: Button = $RootMargin/DestinationLayout/SubmitDestinationButton
@onready var return_button: Button = $RootMargin/DestinationLayout/ReturnButton

# 索引书是右侧操作台上的纸质资料页，不参与系统验证结果计算。
@onready var open_floor_book_button: Button = $RootMargin/DestinationLayout/OpenFloorBookButton
@onready var floor_book_page: MarginContainer = $FloorBookPage
@onready var floor_book_title_label: Label = $FloorBookPage/FloorBookLayout/FloorBookTitleLabel
@onready var floor_book_page_label: Label = $FloorBookPage/FloorBookLayout/FloorBookPageLabel
@onready var floor_book_number_label: Label = $FloorBookPage/FloorBookLayout/FloorBookContentPanel/FloorBookContentMargin/FloorBookContentLayout/FloorBookNumberLabel
@onready var floor_book_intro_label: Label = $FloorBookPage/FloorBookLayout/FloorBookContentPanel/FloorBookContentMargin/FloorBookContentLayout/FloorBookIntroLabel
@onready var floor_book_function_label: Label = $FloorBookPage/FloorBookLayout/FloorBookContentPanel/FloorBookContentMargin/FloorBookContentLayout/FloorBookFunctionLabel
@onready var floor_book_history_label: Label = $FloorBookPage/FloorBookLayout/FloorBookContentPanel/FloorBookContentMargin/FloorBookContentLayout/FloorBookHistoryLabel
@onready var floor_book_note_label: Label = $FloorBookPage/FloorBookLayout/FloorBookContentPanel/FloorBookContentMargin/FloorBookContentLayout/FloorBookNoteLabel
@onready var previous_book_page_button: Button = $FloorBookPage/FloorBookLayout/FloorBookButtonPanel/PrevBookPageButton
@onready var next_book_page_button: Button = $FloorBookPage/FloorBookLayout/FloorBookButtonPanel/NextBookPageButton
@onready var fill_current_floor_button: Button = $FloorBookPage/FloorBookLayout/FloorBookButtonPanel/FillCurrentFloorButton
@onready var close_floor_book_button: Button = $FloorBookPage/FloorBookLayout/FloorBookButtonPanel/CloseFloorBookButton
var current_book_page_index: int = 0

var demo_flow_manager: DemoFlowManager


func _ready() -> void:
	_connect_destination_signals()
	_initialize_destination_text()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		push_warning("DestinationControlInterface: DemoFlowManager is not connected.")
		return
	if not demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.connect(_refresh_case_display)
	if not demo_flow_manager.elevator_movement_completed.is_connected(_on_elevator_movement_completed):
		demo_flow_manager.elevator_movement_completed.connect(_on_elevator_movement_completed)
	# 子节点 ready 后才注入共享流程，因此这里再次刷新案例相关文字。
	_initialize_destination_text()


func _refresh_case_display() -> void:
	_update_dispatch_summary_label()
	_update_recommended_destination_buttons()
	if recommended_destination_panel != null:
		recommended_destination_panel.visible = _should_show_recommendations()
	var validated_floor: String = demo_flow_manager.get_validated_floor() \
			if demo_flow_manager != null else ""
	if validated_floor.is_empty():
		_set_dispatch_evaluation("", false)
		return
	var relation: DispatchFloorRelation = _get_dispatch_floor_relation(validated_floor)
	_set_dispatch_evaluation(
		_build_dispatch_evaluation(relation),
		_can_show_dispatch_evaluation()
	)


func show_destination_console() -> void:
	# 每次进入 RIGHT 时先显示主控制台，但保留玩家上次填写的目标楼层。
	_initialize_destination_text()
	_set_floor_book_visibility(false)
	show()
	if manual_destination_line_edit != null:
		manual_destination_line_edit.grab_focus()


func _connect_destination_signals() -> void:
	# 推荐、验证、提交和返回均在场景加载后连接。
	for button_index in recommended_destination_buttons.size():
		var recommendation_button := recommended_destination_buttons[button_index]
		var callback: Callable = _select_recommended_destination.bind(button_index)
		if not recommendation_button.pressed.is_connected(callback):
			recommendation_button.pressed.connect(callback)

	_connect_button(verify_destination_button, _verify_destination)
	_connect_button(submit_destination_button, _submit_destination)
	_connect_button(return_button, _request_return)
	if manual_destination_line_edit != null \
			and not manual_destination_line_edit.text_changed.is_connected(_on_destination_text_changed):
		manual_destination_line_edit.text_changed.connect(_on_destination_text_changed)
	# 楼层书只提供浏览与填入，不写入左侧的系统通信历史。
	_connect_button(open_floor_book_button, _open_floor_book)
	_connect_button(previous_book_page_button, _change_floor_book_page.bind(-1))
	_connect_button(next_book_page_button, _change_floor_book_page.bind(1))
	_connect_button(fill_current_floor_button, _fill_current_floor)
	_connect_button(close_floor_book_button, _close_floor_book)


func _connect_button(button: Button, callback: Callable) -> void:
	if button != null and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _initialize_destination_text() -> void:
	var recommended_destinations: Array = _get_recommended_destinations()
	var passenger_is_onboard: bool = demo_flow_manager != null \
			and demo_flow_manager.is_passenger_onboard()
	_set_label_text(title_label, "目标楼层控制台 / DESTINATION CONSOLE")
	_update_dispatch_summary_label()
	_set_label_text(recommended_title_label, "系统推荐楼层：")

	_update_recommended_destination_buttons()
	if recommended_destination_panel != null:
		recommended_destination_panel.visible = _should_show_recommendations()

	if manual_destination_line_edit != null and passenger_is_onboard \
			and manual_destination_line_edit.text.strip_edges().is_empty():
		manual_destination_line_edit.text = str(recommended_destinations[0]) \
			if not recommended_destinations.is_empty() else ""
	_set_button_text(verify_destination_button, "验证地址")
	_set_floor_overview("", false)
	_set_dispatch_evaluation("", false)
	var feedback_text: String = "请选择推荐楼层，或手动输入目标楼层。"
	if demo_flow_manager == null:
		feedback_text = "数据源未连接：无法读取楼层与派单信息。"
	_set_label_text(destination_feedback_label, feedback_text)
	_set_button_text(submit_destination_button, "前往该楼层")
	_set_button_text(return_button, "返回操作间")
	_set_button_text(open_floor_book_button, "查看楼层索引书")
	_set_label_text(floor_book_title_label, "楼层索引书 / FLOOR DIRECTORY")
	_set_button_text(previous_book_page_button, "上一页")
	_set_button_text(next_book_page_button, "下一页")
	_set_button_text(fill_current_floor_button, "填写此楼层")
	_set_button_text(close_floor_book_button, "合上索引书")
	current_book_page_index = 0
	_update_floor_book_display()
	_set_floor_book_visibility(false)


func _open_floor_book() -> void:
	current_book_page_index = 0
	_update_floor_book_display()
	_set_floor_book_visibility(true)
	if next_book_page_button != null:
		next_book_page_button.grab_focus()


func _close_floor_book() -> void:
	_set_floor_book_visibility(false)
	_set_label_text(destination_feedback_label, "已合上楼层索引书。")
	if open_floor_book_button != null:
		open_floor_book_button.grab_focus()


func _change_floor_book_page(direction: int) -> void:
	var floors: Array[FloorDefinition] = _get_floor_definitions()
	if floors.is_empty():
		push_warning("DestinationControlInterface: Floor book has no entries.")
		return
	# 纸质书翻页仅改变浏览页码，不写入系统通信记录。
	current_book_page_index = wrapi(
		current_book_page_index + direction,
		0,
		floors.size()
	)
	_update_floor_book_display()


func _fill_current_floor() -> void:
	var floors: Array[FloorDefinition] = _get_floor_definitions()
	if floors.is_empty():
		push_warning("DestinationControlInterface: Cannot fill from an empty floor book.")
		return
	if manual_destination_line_edit == null:
		return

	# 楼层编号直接作为字符串填写，004 等编号不会被转换为整数。
	var floor: FloorDefinition = floors[current_book_page_index]
	var floor_number: String = String(floor.floor_id)
	manual_destination_line_edit.text = floor_number
	_set_floor_book_visibility(false)
	_set_label_text(
		destination_feedback_label,
		"已从楼层索引书填写：%s。请验证地址。" % floor_number
	)
	# 纸质索引只帮助玩家填写；004 / 387 等隐藏楼层不会因此成为系统推荐。
	if verify_destination_button != null:
		verify_destination_button.grab_focus()


func _set_floor_book_visibility(book_is_open: bool) -> void:
	if root_margin != null:
		root_margin.visible = not book_is_open
	if floor_book_page != null:
		floor_book_page.visible = book_is_open


func _update_floor_book_display() -> void:
	var floors: Array[FloorDefinition] = _get_floor_definitions()
	if floors.is_empty():
		_set_label_text(floor_book_page_label, "数据源未连接")
		_set_label_text(floor_book_number_label, "楼层编号：—")
		_set_label_text(floor_book_intro_label, "楼层介绍：无法读取")
		_set_label_text(floor_book_function_label, "主要功能：无法读取")
		_set_label_text(floor_book_history_label, "维修历史：无法读取")
		_set_label_text(floor_book_note_label, "备注：请检查 DemoFlowManager 连接。")
		return

	var floor: FloorDefinition = floors[current_book_page_index]
	_set_label_text(
		floor_book_page_label,
		"第 %d / %d 页" % [current_book_page_index + 1, floors.size()]
	)
	_set_label_text(floor_book_number_label, "楼层编号：%s" % floor.floor_id)
	_set_label_text(floor_book_intro_label, "楼层介绍：%s" % floor.description)
	_set_label_text(floor_book_function_label, "主要功能：%s" % floor.function_description)
	_set_label_text(floor_book_history_label, "维修历史：%s" % floor.maintenance_history)
	_set_label_text(floor_book_note_label, "备注：%s" % floor.book_note)


func _select_recommended_destination(button_index: int) -> void:
	var recommended_destinations: Array = _get_recommended_destinations()
	if button_index < 0 or button_index >= recommended_destinations.size():
		push_warning("DestinationControlInterface: Invalid recommendation slot.")
		return
	if manual_destination_line_edit == null:
		return

	var destination: String = str(recommended_destinations[button_index])
	manual_destination_line_edit.text = destination
	_set_label_text(
		destination_feedback_label,
		"已填入推荐楼层：%s。请验证地址。" % destination
	)


func _on_destination_text_changed(_new_text: String) -> void:
	# LineEdit 每次改写都使旧验证失效，包括从楼层书或推荐按钮填入的编号。
	if demo_flow_manager != null:
		demo_flow_manager.set_validated_floor("")
	_set_label_text(destination_feedback_label, "目标已变更，请重新验证地址。")
	_set_floor_overview("", false)
	_set_dispatch_evaluation("", false)


func _verify_destination() -> void:
	var destination: String = _get_current_destination()
	if destination.is_empty():
		if demo_flow_manager != null:
			demo_flow_manager.set_validated_floor("")
		_set_label_text(destination_feedback_label, "请输入目标楼层。")
		_set_floor_overview("", false)
		_set_dispatch_evaluation("", false)
		return

	var floor: FloorDefinition = ContentRegistry.get_floor(destination)

	if floor == null:
		if demo_flow_manager != null:
			demo_flow_manager.set_validated_floor("")
		_set_label_text(destination_feedback_label, "无法识别目标楼层：%s。" % destination)
		_set_floor_overview("", false)
		_set_dispatch_evaluation("", false)
		return
	if demo_flow_manager != null:
		demo_flow_manager.set_validated_floor(destination)
	var relation: DispatchFloorRelation = _get_dispatch_floor_relation(destination)
	_set_label_text(destination_feedback_label, "目标已验证：%s。" % destination)
	_set_floor_overview(_build_floor_overview(floor), true)
	_set_dispatch_evaluation(
		_build_dispatch_evaluation(relation),
		_can_show_dispatch_evaluation()
	)


func _submit_destination() -> void:
	var destination: String = _get_current_destination()
	if destination.is_empty():
		_set_label_text(destination_feedback_label, "请输入目标楼层。")
		return
	if demo_flow_manager == null:
		_set_label_text(destination_feedback_label, "电梯位置系统尚未连接。")
		return

	if not ContentRegistry.has_floor(destination):
		_set_label_text(
			destination_feedback_label,
			"无法前往：楼层 %s 不在当前楼层数据库中。" % destination
		)
		return

	# 乘客未登舱时，操作员可直接前往任意已登记楼层；舱内阶段仍需保留地址复核。
	if demo_flow_manager.is_passenger_onboard() \
			and destination != demo_flow_manager.get_validated_floor():
		_set_label_text(destination_feedback_label, "乘客在舱内时，请先验证目标楼层。")
		return
	if demo_flow_manager.is_cabin_door_open():
		_set_label_text(destination_feedback_label, "请先关闭舱门，再确认前往楼层。")
		return
	if demo_flow_manager.is_elevator_moving():
		_set_label_text(destination_feedback_label, "电梯正在运行中，请等待停靠。")
		return
	if not demo_flow_manager.request_elevator_movement(destination):
		_set_label_text(destination_feedback_label, "无法开始移动，请检查电梯状态。")
		return
	if demo_flow_manager.is_passenger_onboard():
		demo_flow_manager.select_target_floor(destination)

	_set_label_text(destination_feedback_label, "目标楼层已确认：%s。电梯正在前往该楼层。" % destination)
	_update_dispatch_summary_label()


func _on_elevator_movement_completed(arrived_floor: String) -> void:
	# 移动完成时清除“正在前往”的旧提示，避免右侧保留过期运行状态。
	_set_label_text(destination_feedback_label, "已停靠于 %s 层，舱门保持关闭。" % arrived_floor)
	_update_dispatch_summary_label()


func _get_current_destination() -> String:
	if manual_destination_line_edit == null:
		return ""
	# 只清理首尾空格，不转为整数，以保留 004 等完整楼层编号。
	return manual_destination_line_edit.text.strip_edges()


func _get_recommended_destinations() -> Array:
	if demo_flow_manager == null:
		return []
	return demo_flow_manager.get_current_recommended_destinations()


func _should_show_recommendations() -> bool:
	# 乘客上梯后显示正式推荐；接乘阶段则只显示乘客所在楼层。
	if demo_flow_manager == null:
		return false
	if demo_flow_manager.is_passenger_onboard():
		return true
	return demo_flow_manager.get_case_phase() in [
		"WAITING_FOR_PICKUP",
		"ARRIVED_AT_PICKUP",
		"DOOR_GREETING_DONE",
	]


func _update_recommended_destination_buttons() -> void:
	# 三个槽位只显示系统推荐；手动验证或查书填写不会把隐藏楼层塞进这里。
	var candidates: Array = _get_recommended_destinations()
	for button_index in recommended_destination_buttons.size():
		var has_candidate: bool = button_index < candidates.size() and button_index < 3
		var button: Button = recommended_destination_buttons[button_index]
		button.visible = has_candidate
		button.disabled = not has_candidate
		button.text = str(candidates[button_index]) if has_candidate else "—"


func _update_dispatch_summary_label() -> void:
	# DispatchSummaryLabel 只呈现电梯自身位置；派单与推荐仍由各自区域负责。
	var current_floor: String = "---"
	var target_floor: String = "---"
	var movement_text: String = "待命，舱门关闭"
	if demo_flow_manager != null:
		current_floor = demo_flow_manager.get_current_floor()
		var active_target: String = demo_flow_manager.get_target_floor()
		target_floor = active_target if not active_target.is_empty() else "---"
		movement_text = demo_flow_manager.get_movement_state_text()
	var summary: String = "当前楼层：%s\n目标楼层：%s\n电梯状态：%s" % [
		current_floor, target_floor, movement_text,
	]
	_set_label_text(dispatch_summary_label, summary)


func _get_dispatch_floor_relation(floor_id: String) -> DispatchFloorRelation:
	if demo_flow_manager == null:
		return null
	return demo_flow_manager.get_dispatch_floor_relation(floor_id)


func _get_floor_definitions() -> Array[FloorDefinition]:
	return ContentRegistry.get_all_floors()


func _build_floor_overview(floor: FloorDefinition) -> String:
	return "楼层：%s\n楼层概览：%s" % [
		floor.floor_id,
		floor.description,
	]


func _build_dispatch_evaluation(relation: DispatchFloorRelation) -> String:
	if relation == null:
		return "当前派单评估\n与当前派单关联度：0%\n预计稳定度影响：无当前数据"

	return "当前派单评估\n与当前派单关联度：%s\n预计稳定度影响：%s" % [
		"%d%%" % relation.relevance,
		_get_stability_preview_label(String(relation.stability_preview)),
	]


func _get_stability_preview_label(stability_preview: String) -> String:
	match stability_preview:
		"basic_stable":
			return "基本稳定"
		"stable":
			return "稳定"
		"minor_fluctuation":
			return "轻微波动"
		"moderate_fluctuation":
			return "中等波动"
		"major_fluctuation":
			return "严重波动"
		_:
			return "无当前数据"


func _can_show_dispatch_evaluation() -> bool:
	# 已有派单和乘客已进舱是两个条件；只有舱内阶段才展示派单关联评估。
	return demo_flow_manager != null \
			and demo_flow_manager.has_active_dispatch() \
			and demo_flow_manager.is_passenger_onboard()


func _set_floor_overview(overview_text: String, is_visible: bool) -> void:
	if floor_overview_panel != null:
		floor_overview_panel.visible = is_visible
	_set_label_text(floor_overview_label, overview_text)


func _set_dispatch_evaluation(evaluation_text: String, is_visible: bool) -> void:
	if dispatch_evaluation_panel != null:
		dispatch_evaluation_panel.visible = is_visible
	_set_label_text(dispatch_evaluation_label, evaluation_text)


func _set_label_text(label: Label, new_text: String) -> void:
	if label != null:
		label.text = new_text


func _set_button_text(button: Button, new_text: String) -> void:
	if button != null:
		button.text = new_text


func _request_return() -> void:
	return_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or _is_key_pressed(event, KEY_S):
		_request_return()
		get_viewport().set_input_as_handled()


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)
