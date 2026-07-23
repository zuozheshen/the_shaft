extends RefCounted


const DEMO_SHIFT: ShiftDefinition = preload("res://data/shifts/demo_shift_001.tres")
const DIALOGUE_PATH := "res://dialogues/passengers/passenger_003.dialogue"
const DESTINATION_FLOOR_IDS: Array[String] = [
	"547",
	"004",
	"900",
	"387",
	"612",
	"742",
	"392",
]


func run(test_runner: Variant) -> void:
	var passenger: PassengerDefinition = ContentRegistry.get_passenger("passenger_003")
	var dispatch: DispatchDefinition = ContentRegistry.get_dispatch("CASE_003")

	test_runner.assert_not_equal(
		"CASE_003 内容 / passenger_003 已登记",
		null,
		passenger
	)
	test_runner.assert_not_equal(
		"CASE_003 内容 / CASE_003 已登记",
		null,
		dispatch
	)
	if passenger == null or dispatch == null:
		return

	test_runner.assert_equal(
		"CASE_003 内容 / 乘客引用正确",
		&"passenger_003",
		dispatch.passenger_id
	)
	test_runner.assert_equal(
		"CASE_003 内容 / 接乘楼层为 387",
		&"387",
		dispatch.pickup_floor_id
	)
	test_runner.assert_equal(
		"CASE_003 内容 / 默认目标为 547",
		&"547",
		dispatch.default_destination_floor_id
	)
	test_runner.assert_equal(
		"CASE_003 内容 / 七个正式楼层均有 relation",
		7,
		dispatch.floor_relations.size()
	)

	var relation_004: DispatchFloorRelation = dispatch.get_floor_relation("004")
	var relation_900: DispatchFloorRelation = dispatch.get_floor_relation("900")
	var relation_547: DispatchFloorRelation = dispatch.get_floor_relation("547")
	test_runner.assert_true(
		"CASE_003 内容 / 004 relation 可推荐",
		relation_004 != null and relation_004.recommendation_eligible
	)
	test_runner.assert_true(
		"CASE_003 内容 / 900 relation 可推荐",
		relation_900 != null and relation_900.recommendation_eligible
	)
	test_runner.assert_true(
		"CASE_003 内容 / 547 是初始推荐",
		relation_547 != null and relation_547.initially_recommended
	)
	test_runner.assert_equal(
		"CASE_003 内容 / 004 保留前导零",
		&"004",
		ContentRegistry.normalize_floor_id("004")
	)

	test_runner.assert_true(
		"CASE_003 内容 / Dialogue 文件可读取",
		FileAccess.file_exists(DIALOGUE_PATH)
	)
	var dialogue_source := FileAccess.get_file_as_string(DIALOGUE_PATH)
	for floor_id: String in DESTINATION_FLOOR_IDS:
		var title := "~ destination_%s" % floor_id
		test_runner.assert_equal(
			"CASE_003 内容 / %s 标题唯一" % title,
			1,
			dialogue_source.count(title)
		)

	test_runner.assert_equal(
		"正式内容 / 楼层数量仍为 7",
		7,
		ContentRegistry.get_all_floor_definitions().size()
	)
	test_runner.assert_equal(
		"正式内容 / 乘客数量为 3",
		3,
		ContentRegistry.get_all_passenger_definitions().size()
	)
	test_runner.assert_equal(
		"正式内容 / 派单数量为 3",
		3,
		ContentRegistry.get_all_dispatch_definitions().size()
	)
	test_runner.assert_equal(
		"正式内容 / 值班派单顺序正确",
		[&"CASE_001", &"CASE_002", &"CASE_003"],
		DEMO_SHIFT.dispatch_ids
	)
