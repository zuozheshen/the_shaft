extends RefCounted
## 只在测试进程注入的无剧情数据；不修改正式 Catalog 或资源文件。

static var _profiles: Array[PassengerVisualProfile] = []
static var _saved: Dictionary = {}

static func profile(index: int) -> PassengerVisualProfile:
	if _profiles.is_empty():
		for n in range(1, 4):
			var item := PassengerVisualProfile.new()
			item.passenger_id = StringName("TEST_PERSON_%03d" % n)
			var texture := GradientTexture2D.new()
			texture.width = 8
			texture.height = 16
			item.texture = texture
			item.tint = Color(0.5 + n * 0.1, 0.7, 0.8, 1)
			item.visual_scale = Vector2(1 + (n - 1) * 0.02, 1)
			_profiles.append(item)
	return _profiles[index - 1]

static func dispatch(index: int) -> DispatchDefinition:
	var item := DispatchDefinition.new()
	item.dispatch_id = StringName("TEST_CASE_%03d" % index)
	item.passenger_id = profile(index).passenger_id
	item.pickup_floor_id = [&"612", &"900", &"387"][index - 1]
	item.default_destination_floor_id = [&"900", &"742", &"547"][index - 1]
	item.dialogue_path = "res://tests/fixtures/runtime/test_passenger.dialogue"
	for key: String in ContentValidator.PICKUP_DATA_KEYS:
		item.pickup_data[key] = "TEST " + key
	for phase: String in DispatchPhase.get_all():
		if phase != DispatchPhase.SHIFT_IDLE:
			item.front_phase_texts[phase] = {"state": "TEST", "task": "TEST"}
	for id: String in floor_ids():
		var relation := DispatchFloorRelation.new()
		relation.floor_id = StringName(id)
		relation.recommendation_eligible = id in ["900", "742", "004", "547"]
		relation.initially_recommended = relation.floor_id == item.default_destination_floor_id
		relation.relevance = 50
		relation.stability_preview = &"stable"
		item.floor_relations.append(relation)
	return item

static func shift() -> ShiftDefinition:
	var item := ShiftDefinition.new()
	item.shift_id = &"TEST_SHIFT"
	item.dispatch_ids = [&"TEST_CASE_001", &"TEST_CASE_002", &"TEST_CASE_003"]
	return item

static func floor_ids() -> Array[String]:
	return ["900", "742", "612", "004", "387", "392", "547", "318", "001", "002"]

static func floor_profiles() -> Array[FloorVisualProfile]:
	var result: Array[FloorVisualProfile] = []
	for id: String in floor_ids():
		var item := FloorVisualProfile.new()
		item.floor_id = StringName(id)
		result.append(item)
	return result

static func install(registry: Node) -> void:
	for key: String in ["_floors_by_id", "_passengers_by_id", "_dispatches_by_id", "_ordered_floors"]:
		_saved[key] = registry.get(key)
	var floors := {}
	var ordered: Array[FloorDefinition] = []
	for id: String in floor_ids():
		var item := FloorDefinition.new()
		item.floor_id = StringName(id)
		item.display_name = "TEST " + id
		floors[item.floor_id] = item
		ordered.append(item)
	var passengers := {}
	var dispatches := {}
	for n in range(1, 4):
		var person := PassengerDefinition.new()
		person.passenger_id = profile(n).passenger_id
		person.system_name = "TEST"
		person.display_name = "TEST %d" % n
		person.archive_text = "TEST ARCHIVE {dispatch}"
		passengers[person.passenger_id] = person
		var item := dispatch(n)
		dispatches[item.dispatch_id] = item
	registry.set("_floors_by_id", floors)
	registry.set("_ordered_floors", ordered)
	registry.set("_passengers_by_id", passengers)
	registry.set("_dispatches_by_id", dispatches)

static func restore(registry: Node) -> void:
	for key: String in _saved:
		registry.set(key, _saved[key])
	_saved.clear()

static func prepare_scene(main: Node) -> void:
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.initial_floor = "900"
	manager.initial_shift = shift()
	var coordinator := main.find_child("监控表现协调器", true, false) as MonitorPresentationCoordinator3D
	coordinator.floor_visual_profiles = floor_profiles()
	coordinator.passenger_visual_profiles = [profile(1), profile(2), profile(3)]
	prepare_visual(main)

static func prepare_visual(root: Node) -> void:
	if root is MonitorStageController3D:
		root.initial_passenger_profile = profile(1)
	if root is PassengerVisual3D:
		root.initial_profile = profile(1)
	for child in root.get_children():
		prepare_visual(child)
