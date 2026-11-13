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
		_validate_front_phase_texts(dispatch, context, report)
		_validate_dialogue(dispatch, context, floor_ids, relations, report)
		var archive_ids: Dictionary = {}
		for document: DocumentDefinition in dispatch.documents:
			if document == null:
				continue
			if String(document.document_id).begins_with("registry/"):
				report.add_error(&"DOCUMENT_ID_RESERVED", context, "registry/ 是身份资料适配视图的保留前缀。")
			if document.source == null or document.source.kind != &"floor_archive":
				continue
			if document.owner_type != &"floor":
				report.add_error(&"FLOOR_ARCHIVE_OWNER_INVALID", context, "楼层档案须属于已登记楼层。")
			elif archive_ids.get(document.owner_id, document.document_id) != document.document_id:
				report.add_error(&"FLOOR_ARCHIVE_AMBIGUOUS", context, "同一派单内每层只能配置一份楼层档案。")
			else:
				archive_ids[document.owner_id] = document.document_id
		_validate_review_rules(dispatch, report, context)
		validate_documents(dispatch.documents, report, context, {
			"floor": floor_ids, "passenger": passenger_ids,
			"dispatch": {String(dispatch.dispatch_id): dispatch},
		})


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

	if not dispatch.dialogue_events.is_empty() and dispatch.dialogue_path.strip_edges().is_empty():
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

	_validate_dialogue_titles(dispatch, context, titles, report)
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
	titles: Dictionary,
	report: ContentValidationReport
) -> void:
	for key: String in dispatch.dialogue_events:
		var title := dispatch.dialogue_events[key]
		if key not in DispatchDefinition.DIALOGUE_EVENT_KEYS or not titles.has(title):
			report.add_error(&"DIALOGUE_EVENT_INVALID", context,
				"无效的乘客事件或标题：%s → %s。" % [key, title])
		elif dispatch.dialogue_path.ends_with(".dialogue"):
			var resource := load(dispatch.dialogue_path) as DialogueResource
			if not DialogueManagerAdapter.is_event_title(resource, title):
				report.add_error(&"DIALOGUE_EVENT_INVALID", context,
					"标题不符合有限顺序陈述契约：%s。" % title)


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
	# ID 只清理首尾空格，保留 001 等前导零。
	return String(value).strip_edges()


## 资料校验只检查内容契约，不判断规程是否适用或乘客陈述是否属实。
static func validate_documents(documents: Array, report: ContentValidationReport,
		context: String = "documents", objects: Dictionary = {}) -> void:
	var seen: Dictionary = {}
	for item: Variant in documents:
		if not item is DocumentDefinition:
			report.add_error(&"DOCUMENT_INVALID", context, "资料为空或类型不正确。")
			continue
		var document := item as DocumentDefinition
		var label: String = "%s/document:%s@%d" % [context, document.document_id, document.version]
		var identity: String = "%s@%d" % [document.document_id, document.version]
		if seen.has(identity):
			report.add_error(&"DOCUMENT_DUPLICATE", label, "同一资料版本重复声明。")
		seen[identity] = true
		if not _document_id_valid(document.document_id) or document.version <= 0:
			report.add_error(&"DOCUMENT_ID_VERSION_INVALID", label, "资料 ID 或版本无效。")
		if not _document_id_valid(document.material_type) or document.title.strip_edges().is_empty():
			report.add_error(&"DOCUMENT_METADATA_INVALID", label, "材料类型和标题不能为空。")
		_validate_document_object(document.owner_type, document.owner_id, objects, report, label)
		_validate_document_source(document.source, report, label)
		var field_ids: Dictionary = {}
		for field: DocumentFieldDefinition in document.fields:
			if field == null:
				report.add_error(&"DOCUMENT_FIELD_INVALID", label, "字段不能为空。")
				continue
			var field_label: String = label + "/field:" + String(field.field_id)
			if not _document_id_valid(field.field_id) or field_ids.has(field.field_id):
				report.add_error(&"DOCUMENT_FIELD_ID_INVALID", field_label, "字段 ID 为空或重复。")
			field_ids[field.field_id] = true
			_validate_document_object(field.subject_type, field.subject_id, objects, report, field_label)
			if not _document_id_valid(field.comparison_key):
				report.add_error(&"DOCUMENT_COMPARISON_KEY_INVALID", field_label, "可比字段键不能为空。")
			var effective: DocumentSourceDefinition = field.source if field.source != null else document.source
			if field.source != null:
				_validate_document_source(field.source, report, field_label)
				if (document.source != null and field.source.snapshot() != document.source.snapshot()
						and field.source_note.strip_edges().is_empty()):
					report.add_error(&"DOCUMENT_FIELD_SOURCE_NOTE_REQUIRED", field_label,
						"跨出处字段须注明引用或转述关系；覆盖不能改变所属文档的取得身份。")
			if not _document_value_valid(field):
				report.add_error(&"DOCUMENT_VALUE_INVALID", field_label, "字段类型、缺值标志或可比值不一致。")
			var has_requirement: bool = field.requirement_key != &"" or field.required_material_type != &"" or field.applicability_key != &""
			if has_requirement and (document.source == null or document.source.kind != &"system_reference"
					or effective == null or effective.kind != &"system_reference" or not field.has_value
					or not _document_id_valid(field.requirement_key)
					or not _document_id_valid(field.required_material_type)
					or not _document_id_valid(field.applicability_key)):
				report.add_error(&"DOCUMENT_REQUIREMENT_INVALID", field_label, "只有完整的系统规程条款可声明索证要求。")


static func _document_id_valid(value: StringName) -> bool:
	return value != &"" and String(value) == String(value).strip_edges()


static func _validate_document_object(kind: StringName, id: StringName, objects: Dictionary,
		report: ContentValidationReport, context: String) -> void:
	if kind not in [&"passenger", &"floor", &"dispatch", &"system"] or not _document_id_valid(id):
		report.add_error(&"DOCUMENT_OBJECT_INVALID", context, "所属/陈述对象无效。")
	elif kind != &"system" and not objects.is_empty() and not objects.get(String(kind), {}).has(id):
		report.add_error(&"DOCUMENT_OBJECT_MISSING", context, "引用对象未登记：%s/%s。" % [kind, id])


static func _validate_document_source(source: DocumentSourceDefinition,
		report: ContentValidationReport, context: String) -> void:
	if source == null or not _document_id_valid(source.source_id) or source.kind not in DocumentSourceDefinition.KINDS:
		report.add_error(&"DOCUMENT_SOURCE_INVALID", context, "资料来源 ID 或类别无效。")
	elif source.origin_ref.strip_edges().is_empty() or source.source_version.strip_edges().is_empty():
		report.add_error(&"DOCUMENT_SOURCE_INVALID", context, "资料须记录原始出处和来源版本。")


static func _document_value_valid(field: DocumentFieldDefinition) -> bool:
	if field.value_type not in ["string", "floor_id", "bool", "int", "float"]:
		return false
	if not field.has_value:
		return field.comparable_value.is_empty()
	if field.comparable_value.size() != 1:
		return false
	var value: Variant = field.comparable_value[0]
	match field.value_type:
		"string": return value is String
		"floor_id": return value is String and not value.is_empty() and value == value.strip_edges()
		"bool": return value is bool
		"int": return value is int
		"float": return value is float and is_finite(value)
	return false


static func _validate_review_rules(dispatch: DispatchDefinition, report: ContentValidationReport, context: String) -> void:
	if dispatch.review_rules.is_empty():
		return
	var ids := {}
	var resource := load(dispatch.dialogue_path) as DialogueResource if ResourceLoader.exists(dispatch.dialogue_path) else null
	for rule: DocumentReviewRule in dispatch.review_rules:
		if not DocumentReviewMatcher.valid(rule) or ids.has(rule.question_id):
			report.add_error(&"REVIEW_RULE_INVALID", context, "无效或重复的审查规则。")
			continue
		ids[rule.question_id] = true
		if not DialogueManagerAdapter.is_event_title(resource, rule.response_title, true, rule.supplement_action):
			report.add_error(&"REVIEW_RESPONSE_INVALID", context, "回应标题或授权补件动作无效。")
		for ref: Dictionary in rule.supplement_refs:
			var found := false
			for document: DocumentDefinition in dispatch.documents:
				if document != null and document.document_id == ref.document_id and document.version == ref.version \
						and document.source != null and document.source.kind == &"passenger_upload" \
						and document.owner_type == &"passenger" and document.owner_id == dispatch.passenger_id:
					found = true
			if not found:
				report.add_error(&"REVIEW_SUPPLEMENT_INVALID", context, "补件必须引用本单乘客的明确上传文档。")
