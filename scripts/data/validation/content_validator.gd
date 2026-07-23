class_name ContentValidator
extends RefCounted


const PICKUP_DATA_KEYS: Array[String] = [
	"arrival_status_hint",
	"outside_audio_idle",
	"after_open_line",
	"after_open_hint",
	"after_close_line",
	"after_close_hint",
	"after_close_status_hint",
]


static func validate_content(
	floors: Array,
	passengers: Array,
	dispatches: Array,
	shifts: Array
) -> ContentValidationReport:
	var report := ContentValidationReport.new()
	var floor_ids: Dictionary = _validate_floors(floors, report)
	var passenger_ids: Dictionary = _validate_passengers(passengers, report)
	var dispatch_ids: Dictionary = {}
	var referenced_passenger_ids: Dictionary = {}

	_validate_dispatches(
		dispatches,
		floor_ids,
		passenger_ids,
		dispatch_ids,
		referenced_passenger_ids,
		report
	)
	var referenced_dispatch_ids: Dictionary = _validate_shifts(
		shifts,
		dispatch_ids,
		report
	)
	_add_unreferenced_warnings(
		dispatch_ids,
		referenced_dispatch_ids,
		passenger_ids,
		referenced_passenger_ids,
		report
	)
	return report


static func _validate_floors(
	floors: Array,
	report: ContentValidationReport
) -> Dictionary:
	var floor_ids: Dictionary = {}
	for index: int in floors.size():
		var item: Variant = floors[index]
		var context := "floor:index=%d" % index
		if item == null:
			report.add_error(&"FLOOR_NULL", context, "FloorCatalog 中存在空条目。")
			continue
		if not (item is FloorDefinition):
			report.add_error(&"FLOOR_TYPE_INVALID", context, "条目不是 FloorDefinition。")
			continue

		var floor := item as FloorDefinition
		var floor_id := _normalized_id(floor.floor_id)
		context = "floor:%s" % ("<empty>@%d" % index if floor_id.is_empty() else floor_id)
		if floor_id.is_empty():
			report.add_error(&"FLOOR_ID_EMPTY", context, "floor_id 不能为空。")
			continue
		if floor_ids.has(floor_id):
			report.add_error(&"FLOOR_ID_DUPLICATE", context, "floor_id 重复：%s。" % floor_id)
			continue
		floor_ids[floor_id] = floor
	return floor_ids


static func _validate_passengers(
	passengers: Array,
	report: ContentValidationReport
) -> Dictionary:
	var passenger_ids: Dictionary = {}
	for index: int in passengers.size():
		var item: Variant = passengers[index]
		var context := "passenger:index=%d" % index
		if item == null:
			report.add_error(&"PASSENGER_NULL", context, "PassengerCatalog 中存在空条目。")
			continue
		if not (item is PassengerDefinition):
			report.add_error(
				&"PASSENGER_TYPE_INVALID",
				context,
				"条目不是 PassengerDefinition。"
			)
			continue

		var passenger := item as PassengerDefinition
		var passenger_id := _normalized_id(passenger.passenger_id)
		context = "passenger:%s" % (
			"<empty>@%d" % index if passenger_id.is_empty() else passenger_id
		)
		if passenger_id.is_empty():
			report.add_error(&"PASSENGER_ID_EMPTY", context, "passenger_id 不能为空。")
		else:
			if passenger_ids.has(passenger_id):
				report.add_error(
					&"PASSENGER_ID_DUPLICATE",
					context,
					"passenger_id 重复：%s。" % passenger_id
				)
			else:
				passenger_ids[passenger_id] = passenger

		if passenger.display_name.strip_edges().is_empty():
			report.add_error(
				&"PASSENGER_DISPLAY_NAME_EMPTY",
				context,
				"display_name 不能为空。"
			)
		if passenger.system_name.strip_edges().is_empty():
			report.add_warning(
				&"PASSENGER_SYSTEM_NAME_EMPTY",
				context,
				"system_name 为空。"
			)
		if passenger.archive_text.strip_edges().is_empty():
			report.add_warning(
				&"PASSENGER_ARCHIVE_TEXT_EMPTY",
				context,
				"archive_text 为空。"
			)
	return passenger_ids


static func _validate_dispatches(
	dispatches: Array,
	floor_ids: Dictionary,
	passenger_ids: Dictionary,
	dispatch_ids: Dictionary,
	referenced_passenger_ids: Dictionary,
	report: ContentValidationReport
) -> void:
	for index: int in dispatches.size():
		var item: Variant = dispatches[index]
		var context := "dispatch:<null>@%d" % index
		if item == null:
			report.add_error(&"DISPATCH_NULL", context, "DispatchCatalog 中存在空条目。")
			continue
		if not (item is DispatchDefinition):
			report.add_error(
				&"DISPATCH_TYPE_INVALID",
				"dispatch:<invalid>@%d" % index,
				"条目不是 DispatchDefinition。"
			)
			continue

		var dispatch := item as DispatchDefinition
		var dispatch_id := _normalized_id(dispatch.dispatch_id)
		context = "dispatch:%s" % (
			"<empty>@%d" % index if dispatch_id.is_empty() else dispatch_id
		)
		if dispatch_id.is_empty():
			report.add_error(&"DISPATCH_ID_EMPTY", context, "dispatch_id 不能为空。")
		elif dispatch_ids.has(dispatch_id):
			report.add_error(
				&"DISPATCH_ID_DUPLICATE",
				context,
				"dispatch_id 重复：%s。" % dispatch_id
			)
		else:
			dispatch_ids[dispatch_id] = dispatch

		_validate_dispatch_references(
			dispatch,
			context,
			floor_ids,
			passenger_ids,
			referenced_passenger_ids,
			report
		)
		var relations: Dictionary = _validate_relations(
			dispatch,
			context,
			floor_ids,
			report
		)
		_validate_pickup_data(dispatch, context, report)
		_validate_camera_feeds(dispatch, context, report)
		_validate_front_phase_texts(dispatch, context, report)
		_validate_dialogue(dispatch, context, floor_ids, relations, report)


static func _validate_dispatch_references(
	dispatch: DispatchDefinition,
	context: String,
	floor_ids: Dictionary,
	passenger_ids: Dictionary,
	referenced_passenger_ids: Dictionary,
	report: ContentValidationReport
) -> void:
	var passenger_id := _normalized_id(dispatch.passenger_id)
	if passenger_id.is_empty():
		report.add_error(&"DISPATCH_PASSENGER_ID_EMPTY", context, "passenger_id 不能为空。")
	else:
		referenced_passenger_ids[passenger_id] = true
		if not passenger_ids.has(passenger_id):
			report.add_error(
				&"DISPATCH_PASSENGER_MISSING",
				context,
				"引用的乘客不存在：%s。" % passenger_id
			)

	_validate_floor_reference(
		_normalized_id(dispatch.pickup_floor_id),
		"pickup_floor_id",
		&"DISPATCH_PICKUP_FLOOR_EMPTY",
		&"DISPATCH_PICKUP_FLOOR_MISSING",
		context,
		floor_ids,
		report
	)
	_validate_floor_reference(
		_normalized_id(dispatch.default_destination_floor_id),
		"default_destination_floor_id",
		&"DISPATCH_DEFAULT_FLOOR_EMPTY",
		&"DISPATCH_DEFAULT_FLOOR_MISSING",
		context,
		floor_ids,
		report
	)

	if dispatch.dialogue_path.strip_edges().is_empty():
		report.add_error(&"DISPATCH_DIALOGUE_PATH_EMPTY", context, "dialogue_path 不能为空。")


static func _validate_floor_reference(
	floor_id: String,
	field_name: String,
	empty_code: StringName,
	missing_code: StringName,
	context: String,
	floor_ids: Dictionary,
	report: ContentValidationReport
) -> void:
	if floor_id.is_empty():
		report.add_error(empty_code, context, "%s 不能为空。" % field_name)
	elif not floor_ids.has(floor_id):
		report.add_error(missing_code, context, "%s 引用不存在楼层：%s。" % [field_name, floor_id])


static func _validate_relations(
	dispatch: DispatchDefinition,
	context: String,
	floor_ids: Dictionary,
	report: ContentValidationReport
) -> Dictionary:
	var relations: Dictionary = {}
	for index: int in dispatch.floor_relations.size():
		var relation: DispatchFloorRelation = dispatch.floor_relations[index]
		if relation == null:
			report.add_error(
				&"DISPATCH_RELATION_NULL",
				context,
				"floor_relations[%d] 为空。" % index
			)
			continue

		var floor_id := _normalized_id(relation.floor_id)
		if floor_id.is_empty():
			report.add_error(
				&"DISPATCH_RELATION_FLOOR_EMPTY",
				context,
				"floor_relations[%d].floor_id 不能为空。" % index
			)
			continue
		if relations.has(floor_id):
			report.add_error(
				&"DISPATCH_RELATION_DUPLICATE",
				context,
				"同一派单的楼层关系重复：%s。" % floor_id
			)
			continue
		relations[floor_id] = relation

		if not floor_ids.has(floor_id):
			report.add_error(
				&"DISPATCH_RELATION_FLOOR_MISSING",
				context,
				"楼层关系引用不存在楼层：%s。" % floor_id
			)
		if relation.initially_recommended and not relation.recommendation_eligible:
			report.add_error(
				&"DISPATCH_RELATION_RECOMMENDATION_INVALID",
				context,
				"初始推荐楼层 %s 不具备推荐资格。" % floor_id
			)
		if relation.relevance < 0 or relation.relevance > 100:
			report.add_error(
				&"DISPATCH_RELATION_RELEVANCE_OUT_OF_RANGE",
				context,
				"楼层 %s 的 relevance 必须在 0 到 100 之间。" % floor_id
			)
		var stability_preview := _normalized_id(relation.stability_preview)
		if stability_preview.is_empty() or stability_preview.to_lower() == "none":
			report.add_warning(
				&"DISPATCH_RELATION_STABILITY_PREVIEW_EMPTY",
				context,
				"楼层 %s 缺少有效 stability_preview。" % floor_id
			)

	var default_floor_id := _normalized_id(dispatch.default_destination_floor_id)
	if not default_floor_id.is_empty() and not relations.has(default_floor_id):
		report.add_error(
			&"DISPATCH_DEFAULT_RELATION_MISSING",
			context,
			"默认目标楼层 %s 没有 floor relation。" % default_floor_id
		)
	var pickup_floor_id := _normalized_id(dispatch.pickup_floor_id)
	if not pickup_floor_id.is_empty() and not relations.has(pickup_floor_id):
		report.add_warning(
			&"DISPATCH_PICKUP_RELATION_MISSING",
			context,
			"接乘楼层 %s 没有 floor relation。" % pickup_floor_id
		)
	return relations


static func _validate_pickup_data(
	dispatch: DispatchDefinition,
	context: String,
	report: ContentValidationReport
) -> void:
	for key: String in PICKUP_DATA_KEYS:
		if not dispatch.pickup_data.has(key):
			report.add_error(
				&"PICKUP_DATA_KEY_MISSING",
				context,
				"pickup_data 缺少必需键：%s。" % key
			)
			continue
		var value: Variant = dispatch.pickup_data[key]
		if not (value is String) or String(value).strip_edges().is_empty():
			report.add_error(
				&"PICKUP_DATA_VALUE_INVALID",
				context,
				"pickup_data.%s 必须是非空 String。" % key
			)


static func _validate_camera_feeds(
	dispatch: DispatchDefinition,
	context: String,
	report: ContentValidationReport
) -> void:
	var active_phases := _get_active_phases()
	for raw_key: Variant in dispatch.camera_feeds.keys():
		var phase := String(raw_key)
		if phase not in active_phases:
			report.add_error(
				&"CAMERA_PHASE_INVALID",
				context,
				"camera_feeds 包含非法阶段：%s。" % phase
			)

	for phase: String in active_phases:
		if not dispatch.camera_feeds.has(phase):
			report.add_error(
				&"CAMERA_PHASE_MISSING",
				context,
				"camera_feeds 缺少阶段：%s。" % phase
			)
			continue
		var value: Variant = dispatch.camera_feeds[phase]
		if not (value is Array):
			report.add_error(
				&"CAMERA_VALUE_TYPE_INVALID",
				context,
				"camera_feeds.%s 必须是 Array。" % phase
			)
			continue
		var feeds := value as Array
		if feeds.size() != 2:
			report.add_error(
				&"CAMERA_FEED_COUNT_INVALID",
				context,
				"camera_feeds.%s 必须包含 2 项，实际为 %d 项。" % [phase, feeds.size()]
			)
		for feed_index: int in feeds.size():
			var feed: Variant = feeds[feed_index]
			if not (feed is String) or String(feed).strip_edges().is_empty():
				report.add_error(
					&"CAMERA_FEED_TEXT_INVALID",
					context,
					"camera_feeds.%s[%d] 必须是非空 String。" % [phase, feed_index]
				)


static func _validate_front_phase_texts(
	dispatch: DispatchDefinition,
	context: String,
	report: ContentValidationReport
) -> void:
	var active_phases := _get_active_phases()
	for raw_key: Variant in dispatch.front_phase_texts.keys():
		var phase := String(raw_key)
		if phase not in active_phases:
			report.add_error(
				&"FRONT_PHASE_INVALID",
				context,
				"front_phase_texts 包含非法阶段：%s。" % phase
			)

	for phase: String in active_phases:
		if not dispatch.front_phase_texts.has(phase):
			report.add_error(
				&"FRONT_PHASE_MISSING",
				context,
				"front_phase_texts 缺少阶段：%s。" % phase
			)
			continue
		var value: Variant = dispatch.front_phase_texts[phase]
		if not (value is Dictionary):
			report.add_error(
				&"FRONT_VALUE_TYPE_INVALID",
				context,
				"front_phase_texts.%s 必须是 Dictionary。" % phase
			)
			continue
		var phase_texts := value as Dictionary
		for field: String in ["state", "task"]:
			if not phase_texts.has(field):
				report.add_error(
					&"FRONT_FIELD_MISSING",
					context,
					"front_phase_texts.%s 缺少 %s。" % [phase, field]
				)
				continue
			var text_value: Variant = phase_texts[field]
			if not (text_value is String) or String(text_value).strip_edges().is_empty():
				report.add_error(
					&"FRONT_TEXT_INVALID",
					context,
					"front_phase_texts.%s.%s 必须是非空 String。" % [phase, field]
				)
				continue
			_validate_placeholders(String(text_value), context, phase, field, report)


static func _validate_placeholders(
	text: String,
	context: String,
	phase: String,
	field: String,
	report: ContentValidationReport
) -> void:
	var placeholder_regex := RegEx.create_from_string("\\{([^{}]+)\\}")
	for placeholder_match: RegExMatch in placeholder_regex.search_all(text):
		var placeholder := placeholder_match.get_string(1)
		if placeholder != "pickup_floor":
			report.add_warning(
				&"FRONT_PLACEHOLDER_UNKNOWN",
				context,
				"front_phase_texts.%s.%s 包含未知占位符：{%s}。" % [
					phase,
					field,
					placeholder,
				]
			)


static func _validate_shifts(
	shifts: Array,
	dispatch_ids: Dictionary,
	report: ContentValidationReport
) -> Dictionary:
	var shift_ids: Dictionary = {}
	var referenced_dispatch_ids: Dictionary = {}
	for index: int in shifts.size():
		var item: Variant = shifts[index]
		var context := "shift:index=%d" % index
		if item == null:
			report.add_error(&"SHIFT_NULL", context, "ShiftCatalog 中存在空条目。")
			continue
		if not (item is ShiftDefinition):
			report.add_error(&"SHIFT_TYPE_INVALID", context, "条目不是 ShiftDefinition。")
			continue

		var shift := item as ShiftDefinition
		var shift_id := _normalized_id(shift.shift_id)
		context = "shift:%s" % ("<empty>@%d" % index if shift_id.is_empty() else shift_id)
		if shift_id.is_empty():
			report.add_error(&"SHIFT_ID_EMPTY", context, "shift_id 不能为空。")
		elif shift_ids.has(shift_id):
			report.add_error(&"SHIFT_ID_DUPLICATE", context, "shift_id 重复：%s。" % shift_id)
		else:
			shift_ids[shift_id] = shift

		if shift.dispatch_ids.is_empty():
			report.add_error(&"SHIFT_DISPATCH_IDS_EMPTY", context, "dispatch_ids 不能为空。")
		var local_dispatch_ids: Dictionary = {}
		for dispatch_index: int in shift.dispatch_ids.size():
			var dispatch_id := _normalized_id(shift.dispatch_ids[dispatch_index])
			if dispatch_id.is_empty():
				report.add_error(
					&"SHIFT_DISPATCH_ID_EMPTY",
					context,
					"dispatch_ids[%d] 不能为空。" % dispatch_index
				)
				continue
			if local_dispatch_ids.has(dispatch_id):
				report.add_error(
					&"SHIFT_DISPATCH_ID_DUPLICATE",
					context,
					"同一值班重复引用派单：%s。" % dispatch_id
				)
			else:
				local_dispatch_ids[dispatch_id] = true
			referenced_dispatch_ids[dispatch_id] = true
			if not dispatch_ids.has(dispatch_id):
				report.add_error(
					&"SHIFT_DISPATCH_MISSING",
					context,
					"引用的派单不存在：%s。" % dispatch_id
				)
	return referenced_dispatch_ids


static func _add_unreferenced_warnings(
	dispatch_ids: Dictionary,
	referenced_dispatch_ids: Dictionary,
	passenger_ids: Dictionary,
	referenced_passenger_ids: Dictionary,
	report: ContentValidationReport
) -> void:
	for dispatch_id: String in dispatch_ids:
		if not referenced_dispatch_ids.has(dispatch_id):
			report.add_warning(
				&"DISPATCH_UNREFERENCED",
				"dispatch:%s" % dispatch_id,
				"派单没有被任何值班引用。"
			)
	for passenger_id: String in passenger_ids:
		if not referenced_passenger_ids.has(passenger_id):
			report.add_warning(
				&"PASSENGER_UNREFERENCED",
				"passenger:%s" % passenger_id,
				"乘客没有被任何派单引用。"
			)


static func _validate_dialogue(
	dispatch: DispatchDefinition,
	context: String,
	floor_ids: Dictionary,
	relations: Dictionary,
	report: ContentValidationReport
) -> void:
	var dialogue_path := dispatch.dialogue_path.strip_edges()
	if dialogue_path.is_empty():
		return
	if not FileAccess.file_exists(dialogue_path):
		report.add_error(
			&"DIALOGUE_FILE_UNREADABLE",
			context,
			"Dialogue 文件不存在或不可读：%s。" % dialogue_path
		)
		return
	var file := FileAccess.open(dialogue_path, FileAccess.READ)
	if file == null:
		report.add_error(
			&"DIALOGUE_FILE_UNREADABLE",
			context,
			"Dialogue 文件不存在或不可读：%s。" % dialogue_path
		)
		return
	var content := file.get_as_text()
	file.close()

	var title_regex := RegEx.create_from_string(
		"^\\s*~\\s+([A-Za-z0-9_]+)\\s*$"
	)
	var unlock_regex := RegEx.create_from_string(
		"unlock_floor\\s*\\(\\s*\"([^\"]+)\"\\s*\\)"
	)
	var titles: Dictionary = {}
	var unlock_floor_ids: Array[String] = []
	for line: String in content.split("\n"):
		var clean_line := line.trim_suffix("\r")
		var title_match: RegExMatch = title_regex.search(clean_line)
		if title_match != null:
			var title := title_match.get_string(1)
			if titles.has(title):
				report.add_error(
					&"DIALOGUE_TITLE_DUPLICATE",
					context,
					"Dialogue 标题重复：%s。" % title
				)
			else:
				titles[title] = true

		if "unlock_floor" in clean_line:
			var unlock_match: RegExMatch = unlock_regex.search(clean_line)
			if unlock_match == null:
				report.add_warning(
					&"DIALOGUE_UNLOCK_PARSE_UNCERTAIN",
					context,
					"发现疑似 unlock_floor，但轻量扫描器无法解析：%s。" % clean_line.strip_edges()
				)
			else:
				unlock_floor_ids.append(unlock_match.get_string(1).strip_edges())

	_validate_dialogue_titles(dispatch, context, floor_ids, relations, titles, report)
	_validate_dialogue_unlocks(
		context,
		floor_ids,
		relations,
		unlock_floor_ids,
		report
	)


static func _validate_dialogue_titles(
	dispatch: DispatchDefinition,
	context: String,
	floor_ids: Dictionary,
	relations: Dictionary,
	titles: Dictionary,
	report: ContentValidationReport
) -> void:
	if not titles.has("pickup_start"):
		report.add_error(
			&"DIALOGUE_PICKUP_START_MISSING",
			context,
			"Dialogue 缺少 pickup_start 标题。"
		)
	if not titles.has("onboard_start"):
		report.add_error(
			&"DIALOGUE_ONBOARD_START_MISSING",
			context,
			"Dialogue 缺少 onboard_start 标题。"
		)

	var default_floor_id := _normalized_id(dispatch.default_destination_floor_id)
	if not default_floor_id.is_empty():
		var default_title := "destination_%s" % default_floor_id
		if not titles.has(default_title):
			report.add_error(
				&"DIALOGUE_DEFAULT_DESTINATION_MISSING",
				context,
				"Dialogue 缺少默认目标标题：%s。" % default_title
			)

	for floor_id: String in relations:
		var relation: DispatchFloorRelation = relations[floor_id]
		if relation.recommendation_eligible:
			var recommended_title := "destination_%s" % floor_id
			if not titles.has(recommended_title):
				report.add_error(
					&"DIALOGUE_RECOMMENDED_DESTINATION_MISSING",
					context,
					"Dialogue 缺少推荐楼层标题：%s。" % recommended_title
				)

	for floor_id: String in floor_ids:
		var destination_title := "destination_%s" % floor_id
		if not titles.has(destination_title):
			report.add_warning(
				&"DIALOGUE_REGISTERED_DESTINATION_MISSING",
				context,
				"Dialogue 缺少已登记楼层反馈：%s。" % destination_title
			)

	for title: String in titles:
		if not title.begins_with("destination_"):
			continue
		var title_floor_id := title.trim_prefix("destination_")
		if not floor_ids.has(title_floor_id):
			report.add_error(
				&"DIALOGUE_DESTINATION_FLOOR_MISSING",
				context,
				"Dialogue 标题引用不存在楼层：%s。" % title
			)
		if not relations.has(title_floor_id):
			report.add_warning(
				&"DIALOGUE_DESTINATION_RELATION_MISSING",
				context,
				"Dialogue 标题存在，但派单没有对应 relation：%s。" % title
			)


static func _validate_dialogue_unlocks(
	context: String,
	floor_ids: Dictionary,
	relations: Dictionary,
	unlock_floor_ids: Array[String],
	report: ContentValidationReport
) -> void:
	var seen_unlocks: Dictionary = {}
	for floor_id: String in unlock_floor_ids:
		if seen_unlocks.has(floor_id):
			report.add_warning(
				&"DIALOGUE_UNLOCK_DUPLICATE",
				context,
				"同一楼层重复 unlock：%s。" % floor_id
			)
		else:
			seen_unlocks[floor_id] = true

		if not floor_ids.has(floor_id):
			report.add_error(
				&"DIALOGUE_UNLOCK_FLOOR_MISSING",
				context,
				"unlock_floor 引用不存在楼层：%s。" % floor_id
			)
			continue
		if not relations.has(floor_id):
			report.add_error(
				&"DIALOGUE_UNLOCK_RELATION_MISSING",
				context,
				"unlock_floor 的楼层没有派单 relation：%s。" % floor_id
			)
			continue
		var relation: DispatchFloorRelation = relations[floor_id]
		if not relation.recommendation_eligible:
			report.add_error(
				&"DIALOGUE_UNLOCK_NOT_ELIGIBLE",
				context,
				"unlock_floor 的 relation 不具备推荐资格：%s。" % floor_id
			)


static func _get_active_phases() -> Array[String]:
	var phases: Array[String] = DispatchPhase.get_all()
	phases.erase(DispatchPhase.SHIFT_IDLE)
	return phases


static func _normalized_id(value: Variant) -> String:
	# ID 只清理首尾空格，保留 004 等前导零。
	return String(value).strip_edges()
