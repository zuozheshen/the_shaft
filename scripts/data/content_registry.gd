extends Node


const FLOOR_CATALOG: FloorCatalog = preload("res://data/catalogs/floor_catalog.tres")
const PASSENGER_CATALOG: PassengerCatalog = preload("res://data/catalogs/passenger_catalog.tres")
const DISPATCH_CATALOG: DispatchCatalog = preload("res://data/catalogs/dispatch_catalog.tres")
const SHIFT_CATALOG: ShiftCatalog = preload("res://data/catalogs/shift_catalog.tres")

var _floors_by_id: Dictionary = {}
var _passengers_by_id: Dictionary = {}
var _dispatches_by_id: Dictionary = {}
var _ordered_floors: Array[FloorDefinition] = []


func _ready() -> void:
	_register_floors()
	_register_passengers()
	_register_dispatches()


func _register_floors() -> void:
	_floors_by_id.clear()
	_ordered_floors.clear()

	for floor: FloorDefinition in FLOOR_CATALOG.floors:
		if floor == null:
			push_error("FloorCatalog 中存在空的楼层资源。")
			continue
		var floor_id: StringName = normalize_floor_id(String(floor.floor_id))
		if floor_id == &"":
			push_error("存在未填写 floor_id 的楼层资源。")
			continue
		if _floors_by_id.has(floor_id):
			push_error("楼层编号重复：%s" % floor_id)
			continue

		_floors_by_id[floor_id] = floor
		_ordered_floors.append(floor)

	# 顺序直接来自 Catalog，不再依赖已移除的楼层书。
	print("ContentRegistry: 已注册 %d 个楼层。" % _floors_by_id.size())


func _register_passengers() -> void:
	_passengers_by_id.clear()

	for passenger: PassengerDefinition in PASSENGER_CATALOG.passengers:
		if passenger == null:
			push_error("PassengerCatalog 中存在空的乘客资源。")
			continue
		var passenger_id: StringName = StringName(String(passenger.passenger_id).strip_edges())
		if passenger_id == &"":
			push_error("存在未填写 passenger_id 的乘客资源。")
			continue
		if _passengers_by_id.has(passenger_id):
			push_error("乘客编号重复：%s" % passenger_id)
			continue
		if passenger.display_name.strip_edges().is_empty():
			push_error("乘客 %s 未填写 display_name。" % passenger_id)
			continue

		_passengers_by_id[passenger_id] = passenger

	print("ContentRegistry: 已注册 %d 名乘客。" % _passengers_by_id.size())


func _register_dispatches() -> void:
	_dispatches_by_id.clear()

	for dispatch: DispatchDefinition in DISPATCH_CATALOG.dispatches:
		if dispatch == null:
			push_error("DispatchCatalog 中存在空的派单资源。")
			continue
		var dispatch_id: StringName = StringName(String(dispatch.dispatch_id).strip_edges())
		if dispatch_id == &"":
			push_error("存在未填写 dispatch_id 的派单资源。")
			continue
		if _dispatches_by_id.has(dispatch_id):
			push_error("派单编号重复：%s" % dispatch_id)
			continue

		var is_valid: bool = _validate_dispatch_passenger(dispatch, dispatch_id)
		is_valid = _validate_dispatch_floors(dispatch, dispatch_id) and is_valid
		if not is_valid:
			push_error("派单 %s 配置无效，未注册到 ContentRegistry。" % dispatch_id)
			continue

		_dispatches_by_id[dispatch_id] = dispatch

	print("ContentRegistry: 已注册 %d 个派单。" % _dispatches_by_id.size())


func _validate_dispatch_passenger(
		dispatch: DispatchDefinition,
		dispatch_id: StringName
) -> bool:
	var passenger_id: StringName = StringName(String(dispatch.passenger_id).strip_edges())
	if passenger_id == &"":
		push_error("派单 %s 未填写 passenger_id。" % dispatch_id)
		return false
	if not _passengers_by_id.has(passenger_id):
		push_error("派单 %s 引用了不存在的乘客：%s" % [dispatch_id, passenger_id])
		return false
	return true


func _validate_dispatch_floors(
		dispatch: DispatchDefinition,
		dispatch_id: StringName
) -> bool:
	var is_valid: bool = true
	if not has_floor(String(dispatch.pickup_floor_id)):
		push_error("派单 %s 的接乘楼层不存在：%s" % [dispatch_id, dispatch.pickup_floor_id])
		is_valid = false

	if not has_floor(String(dispatch.default_destination_floor_id)):
		push_error(
			"派单 %s 的默认目标楼层不存在：%s" % [
				dispatch_id,
				dispatch.default_destination_floor_id,
			]
		)
		is_valid = false

	var registered_floor_ids: Dictionary = {}
	for relation: DispatchFloorRelation in dispatch.floor_relations:
		if relation == null:
			push_error("派单 %s 中存在空的楼层关系。" % dispatch_id)
			is_valid = false
			continue
		var floor_id: StringName = normalize_floor_id(String(relation.floor_id))
		if floor_id == &"":
			push_error("派单 %s 中存在未填写 floor_id 的楼层关系。" % dispatch_id)
			is_valid = false
			continue
		if registered_floor_ids.has(floor_id):
			push_error("派单 %s 的楼层关系重复：%s" % [dispatch_id, floor_id])
			is_valid = false
			continue
		registered_floor_ids[floor_id] = true
		if not has_floor(String(floor_id)):
			push_error("派单 %s 关联了不存在的楼层：%s" % [dispatch_id, floor_id])
			is_valid = false
		if relation.initially_recommended and not relation.recommendation_eligible:
			push_error("派单 %s 的初始推荐楼层不具备推荐资格：%s" % [dispatch_id, floor_id])
			is_valid = false

	return is_valid


func normalize_floor_id(raw_value: String) -> StringName:
	# 只清理首尾空格，绝不转换成整数，确保 001 保持为 001。
	return StringName(raw_value.strip_edges())


func has_floor(raw_value: String) -> bool:
	return _floors_by_id.has(normalize_floor_id(raw_value))


func get_floor(raw_value: String) -> FloorDefinition:
	var floor_id: StringName = normalize_floor_id(raw_value)
	return _floors_by_id.get(floor_id) as FloorDefinition


func get_all_floors() -> Array[FloorDefinition]:
	return _ordered_floors.duplicate()


func get_all_floor_definitions() -> Array[FloorDefinition]:
	return FLOOR_CATALOG.floors.duplicate()


func get_all_passenger_definitions() -> Array[PassengerDefinition]:
	return PASSENGER_CATALOG.passengers.duplicate()


func get_all_dispatch_definitions() -> Array[DispatchDefinition]:
	return DISPATCH_CATALOG.dispatches.duplicate()


func get_all_shift_definitions() -> Array[ShiftDefinition]:
	return SHIFT_CATALOG.shifts.duplicate()


func validate_all_content() -> ContentValidationReport:
	# 完整校验按需执行，并直接读取 Catalog 原始数组以保留 null 和重复项。
	return ContentValidator.validate_content(
		get_all_floor_definitions(),
		get_all_passenger_definitions(),
		get_all_dispatch_definitions(),
		get_all_shift_definitions()
	)


func get_passenger(raw_value: String) -> PassengerDefinition:
	var passenger_id: StringName = StringName(raw_value.strip_edges())
	return _passengers_by_id.get(passenger_id) as PassengerDefinition


func get_dispatch(raw_value: String) -> DispatchDefinition:
	var dispatch_id: StringName = StringName(raw_value.strip_edges())
	return _dispatches_by_id.get(dispatch_id) as DispatchDefinition


func get_dispatch_floor_relation(
		dispatch_id: String,
		floor_id: String
) -> DispatchFloorRelation:
	var dispatch: DispatchDefinition = get_dispatch(dispatch_id)
	if dispatch == null:
		return null
	return dispatch.get_floor_relation(floor_id)


## 内容层只解析定义，不授予玩家取得权限。registry/ 前缀保留给现有身份资料视图。
func get_document_definition(dispatch_id: String, ref: Dictionary) -> DocumentDefinition:
	if not DispatchDocumentState.valid_ref(ref):
		return null
	var dispatch: DispatchDefinition = get_dispatch(dispatch_id)
	if dispatch == null:
		return null
	var found: DocumentDefinition
	for document: DocumentDefinition in dispatch.documents:
		if document != null and not String(document.document_id).begins_with("registry/") and String(document.document_id) == String(ref.document_id) and document.version == ref.version:
			if found != null:
				return null
			found = document
	if found != null:
		return found
	if ref.version != 1:
		return null
	var id: String = String(ref.document_id)
	if id.begins_with("registry/passenger/"):
		var passenger: PassengerDefinition = get_passenger(id.trim_prefix("registry/passenger/"))
		if passenger == null:
			return null
		var document: DocumentDefinition = _identity_document(id, &"passenger", passenger.passenger_id, &"personnel_record")
		document.title = passenger.display_name
		document.original_text = passenger.archive_text
		document.fields = [_identity_field(&"system_name", &"passenger", passenger.passenger_id, passenger.system_name),
			_identity_field(&"display_name", &"passenger", passenger.passenger_id, passenger.display_name)]
		return document
	if id.begins_with("registry/floor/"):
		var floor: FloorDefinition = get_floor(id.trim_prefix("registry/floor/"))
		if floor == null:
			return null
		var document: DocumentDefinition = _identity_document(id, &"floor", floor.floor_id, &"floor_archive")
		document.title = floor.display_name
		var field: DocumentFieldDefinition = _identity_field(&"floor_id", &"floor", floor.floor_id, String(floor.floor_id))
		field.value_type = "floor_id"
		document.fields = [field, _identity_field(&"display_name", &"floor", floor.floor_id, floor.display_name)]
		return document
	return null


func get_system_reference_documents(dispatch_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dispatch: DispatchDefinition = get_dispatch(dispatch_id)
	if dispatch == null:
		return result
	for document: DocumentDefinition in dispatch.documents:
		if document != null and document.source != null and document.source.kind == &"system_reference":
			result.append({"document_id": String(document.document_id), "version": document.version, "title": document.title})
	return result


func validate_document_definitions(documents: Array) -> ContentValidationReport:
	var report := ContentValidationReport.new()
	ContentValidator.validate_documents(documents, report, "registry", {
		"floor": _floors_by_id, "passenger": _passengers_by_id, "dispatch": _dispatches_by_id})
	return report


func _identity_document(id: String, kind: StringName, owner: StringName, source_kind: StringName) -> DocumentDefinition:
	var document := DocumentDefinition.new()
	document.document_id = StringName(id)
	document.owner_type = kind
	document.owner_id = owner
	document.material_type = source_kind
	document.source = DocumentSourceDefinition.new()
	document.source.source_id = StringName(id)
	document.source.kind = source_kind
	var resource: Resource = get_passenger(String(owner)) if kind == &"passenger" else get_floor(String(owner))
	document.source.origin_ref = resource.resource_path if not resource.resource_path.is_empty() else "ContentRegistry:" + id
	document.source.source_version = "legacy-unversioned"
	return document


func _identity_field(id: StringName, kind: StringName, owner: StringName, value: String) -> DocumentFieldDefinition:
	var field := DocumentFieldDefinition.new()
	field.field_id = id
	field.subject_type = kind
	field.subject_id = owner
	field.comparison_key = id
	field.display_value = value
	field.comparable_value = [value]
	return field
