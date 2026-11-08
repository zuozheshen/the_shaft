extends RefCounted

const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const MAIN := preload("res://scenes/main/main_3d.tscn")
const DIALOGUE := "res://tests/fixtures/runtime/test_call_excerpt.dialogue"
const FIRST := &"TEST_CASE_001"
const SECOND := &"TEST_CASE_002"


static func prepare() -> Node:
	# 两张测试单同层、同一资源，换单时必须凭 session 而非资源路径隔离。
	var dispatches: Dictionary = ContentRegistry.get("_dispatches_by_id").duplicate()
	for id: StringName in [FIRST, SECOND]:
		var item := (dispatches[id] as DispatchDefinition).duplicate() as DispatchDefinition
		item.pickup_floor_id = &"612"
		item.dialogue_path = DIALOGUE
		item.default_destination_floor_id = &"900"
		var relations: Array[DispatchFloorRelation] = []
		for relation in item.floor_relations:
			var copy := relation.duplicate() as DispatchFloorRelation
			copy.initially_recommended = copy.floor_id == &"900"
			relations.append(copy)
		item.floor_relations = relations
		dispatches[id] = item
	ContentRegistry.set("_dispatches_by_id", dispatches)
	var main := MAIN.instantiate()
	Content.prepare_scene(main)
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.initial_floor = "612"
	manager.initial_shift = null
	return main
