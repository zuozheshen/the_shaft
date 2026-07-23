extends Node


const FLOOR_CATALOG: FloorCatalog = preload("res://data/catalogs/floor_catalog.tres")
const PASSENGER_CATALOG: PassengerCatalog = preload("res://data/catalogs/passenger_catalog.tres")
const DISPATCH_CATALOG: DispatchCatalog = preload("res://data/catalogs/dispatch_catalog.tres")

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

	_ordered_floors.sort_custom(
		func(first: FloorDefinition, second: FloorDefinition) -> bool:
			return first.book_order < second.book_order
	)
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
	# 只清理首尾空格，绝不转换成整数，确保 004 保持为 004。
	return StringName(raw_value.strip_edges())


func has_floor(raw_value: String) -> bool:
	return _floors_by_id.has(normalize_floor_id(raw_value))


func get_floor(raw_value: String) -> FloorDefinition:
	var floor_id: StringName = normalize_floor_id(raw_value)
	return _floors_by_id.get(floor_id) as FloorDefinition


func get_all_floors() -> Array[FloorDefinition]:
	return _ordered_floors.duplicate()


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
