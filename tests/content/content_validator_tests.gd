extends RefCounted


const VALID_DIALOGUE := "res://tests/fixtures/content_validation/valid.dialogue"
const MISSING_TITLES_DIALOGUE := (
	"res://tests/fixtures/content_validation/missing_titles.dialogue"
)
const INVALID_UNLOCK_DIALOGUE := (
	"res://tests/fixtures/content_validation/invalid_unlock.dialogue"
)


func run(test_runner: Variant) -> void:
	_test_null_entries(test_runner)
	_test_empty_and_duplicate_ids(test_runner)
	_test_invalid_references(test_runner)
	_test_dispatch_data_contracts(test_runner)
	_test_relation_contracts(test_runner)
	_test_shift_and_global_warnings(test_runner)
	_test_dialogue_file_and_titles(test_runner)
	_test_optional_destination_warning(test_runner)
	_test_unlock_contracts(test_runner)
	_test_valid_fixture(test_runner)
	_test_registered_content(test_runner)


func _test_null_entries(test_runner: Variant) -> void:
	var report := ContentValidator.validate_content([null], [null], [null], [null])
	test_runner.assert_true(
		"ContentValidator / null 楼层",
		_has_code(report, "FLOOR_NULL")
	)
	test_runner.assert_true(
		"ContentValidator / null 乘客",
		_has_code(report, "PASSENGER_NULL")
	)
	test_runner.assert_true(
		"ContentValidator / null 派单",
		_has_code(report, "DISPATCH_NULL")
	)
	test_runner.assert_true(
		"ContentValidator / null 值班",
		_has_code(report, "SHIFT_NULL")
	)


func _test_empty_and_duplicate_ids(test_runner: Variant) -> void:
	var empty_floor := _make_floor("")
	var duplicate_floor_a := _make_floor("100")
	var duplicate_floor_b := _make_floor("100")
	var empty_passenger := _make_passenger("", "Empty")
	var duplicate_passenger_a := _make_passenger("PASSENGER", "A")
	var duplicate_passenger_b := _make_passenger("PASSENGER", "B")
	var empty_dispatch := _make_dispatch("", "PASSENGER", "100", VALID_DIALOGUE)
	var duplicate_dispatch_a := _make_dispatch(
		"DISPATCH",
		"PASSENGER",
		"100",
		VALID_DIALOGUE
	)
	var duplicate_dispatch_b := _make_dispatch(
		"DISPATCH",
		"PASSENGER",
		"100",
		VALID_DIALOGUE
	)
	var empty_shift := _make_shift("", [&"DISPATCH"])
	var duplicate_shift_a := _make_shift("SHIFT", [&"DISPATCH"])
	var duplicate_shift_b := _make_shift("SHIFT", [&"DISPATCH"])
	var report := ContentValidator.validate_content(
		[empty_floor, duplicate_floor_a, duplicate_floor_b],
		[empty_passenger, duplicate_passenger_a, duplicate_passenger_b],
		[empty_dispatch, duplicate_dispatch_a, duplicate_dispatch_b],
		[empty_shift, duplicate_shift_a, duplicate_shift_b]
	)
	test_runner.assert_true(
		"ContentValidator / 空 ID",
		_has_codes(report, [
			"FLOOR_ID_EMPTY",
			"PASSENGER_ID_EMPTY",
			"DISPATCH_ID_EMPTY",
			"SHIFT_ID_EMPTY",
		])
	)
	test_runner.assert_true(
		"ContentValidator / 重复 ID",
		_has_codes(report, [
			"FLOOR_ID_DUPLICATE",
			"PASSENGER_ID_DUPLICATE",
			"DISPATCH_ID_DUPLICATE",
			"SHIFT_ID_DUPLICATE",
		])
	)


func _test_invalid_references(test_runner: Variant) -> void:
	var floor := _make_floor("100")
	var passenger := _make_passenger("PASSENGER", "Passenger")
	var dispatch := _make_dispatch(
		"DISPATCH",
		"MISSING_PASSENGER",
		"999",
		"res://tests/fixtures/content_validation/does_not_exist.dialogue"
	)
	dispatch.default_destination_floor_id = &"998"
	var report := ContentValidator.validate_content(
		[floor],
		[passenger],
		[dispatch],
		[_make_shift("SHIFT", [&"DISPATCH"])]
	)
	test_runner.assert_true(
		"ContentValidator / 无效基础引用",
		_has_codes(report, [
			"DISPATCH_PASSENGER_MISSING",
			"DISPATCH_PICKUP_FLOOR_MISSING",
			"DISPATCH_DEFAULT_FLOOR_MISSING",
			"DIALOGUE_FILE_UNREADABLE",
		])
	)


func _test_dispatch_data_contracts(test_runner: Variant) -> void:
	var bundle := _make_valid_bundle()
	var dispatch: DispatchDefinition = bundle.dispatches[0]
	dispatch.pickup_data.erase("after_open_hint")
	dispatch.camera_feeds.erase(DispatchPhase.ARRIVED_AT_PICKUP)
	dispatch.camera_feeds[DispatchPhase.WAITING_FOR_PICKUP] = ["only one"]
	var front_state: Dictionary = dispatch.front_phase_texts[
		DispatchPhase.ARRIVED_AT_PICKUP
	]
	front_state.erase("state")
	var front_task: Dictionary = dispatch.front_phase_texts[
		DispatchPhase.WAITING_FOR_PICKUP
	]
	front_task.erase("task")
	var report := _validate_bundle(bundle)
	test_runner.assert_true(
		"ContentValidator / pickup_data 缺键",
		_has_code(report, "PICKUP_DATA_KEY_MISSING")
	)
	test_runner.assert_true(
		"ContentValidator / camera 缺阶段",
		_has_code(report, "CAMERA_PHASE_MISSING")
	)
	test_runner.assert_true(
		"ContentValidator / camera 数量不是 2",
		_has_code(report, "CAMERA_FEED_COUNT_INVALID")
	)
	test_runner.assert_true(
		"ContentValidator / front 缺 state 或 task",
		_has_code(report, "FRONT_FIELD_MISSING")
	)


func _test_relation_contracts(test_runner: Variant) -> void:
	var bundle := _make_valid_bundle()
	var dispatch: DispatchDefinition = bundle.dispatches[0]
	dispatch.floor_relations.clear()
	var missing_relation_report := _validate_bundle(bundle)
	test_runner.assert_true(
		"ContentValidator / 默认目标缺 relation",
		_has_code(missing_relation_report, "DISPATCH_DEFAULT_RELATION_MISSING")
	)

	bundle = _make_valid_bundle()
	dispatch = bundle.dispatches[0]
	var relation: DispatchFloorRelation = dispatch.floor_relations[0]
	relation.relevance = 101
	relation.stability_preview = &"none"
	relation.initially_recommended = true
	relation.recommendation_eligible = false
	var invalid_relation_report := _validate_bundle(bundle)
	test_runner.assert_true(
		"ContentValidator / relation 组合与范围",
		_has_codes(invalid_relation_report, [
			"DISPATCH_RELATION_RECOMMENDATION_INVALID",
			"DISPATCH_RELATION_RELEVANCE_OUT_OF_RANGE",
			"DISPATCH_RELATION_STABILITY_PREVIEW_EMPTY",
		])
	)


func _test_shift_and_global_warnings(test_runner: Variant) -> void:
	var missing_dispatch_bundle := _make_valid_bundle()
	var shift: ShiftDefinition = missing_dispatch_bundle.shifts[0]
	shift.dispatch_ids.append(&"MISSING_DISPATCH")
	var missing_dispatch_report := _validate_bundle(missing_dispatch_bundle)
	test_runner.assert_true(
		"ContentValidator / 值班引用不存在派单",
		_has_code(missing_dispatch_report, "SHIFT_DISPATCH_MISSING")
	)

	var bundle := _make_valid_bundle()
	bundle.passengers.append(_make_passenger("UNUSED_PASSENGER", "Unused"))
	bundle.dispatches.append(
		_make_dispatch("UNUSED_DISPATCH", "PASSENGER", "100", VALID_DIALOGUE)
	)
	var warning_report := _validate_bundle(bundle)
	test_runner.assert_true(
		"ContentValidator / 未引用派单 Warning",
		_has_code(warning_report, "DISPATCH_UNREFERENCED")
	)
	test_runner.assert_true(
		"ContentValidator / 未引用乘客 Warning",
		_has_code(warning_report, "PASSENGER_UNREFERENCED")
	)


func _test_dialogue_file_and_titles(test_runner: Variant) -> void:
	var missing_file_bundle := _make_valid_bundle()
	var dispatch: DispatchDefinition = missing_file_bundle.dispatches[0]
	dispatch.dialogue_path = "res://tests/fixtures/content_validation/not_found.dialogue"
	var missing_file_report := _validate_bundle(missing_file_bundle)
	test_runner.assert_true(
		"ContentValidator / Dialogue 文件不存在",
		_has_code(missing_file_report, "DIALOGUE_FILE_UNREADABLE")
	)

	var title_bundle := _make_valid_bundle()
	dispatch = title_bundle.dispatches[0]
	dispatch.dialogue_path = MISSING_TITLES_DIALOGUE
	var recommended_relation := _make_relation("200", true)
	dispatch.floor_relations.append(recommended_relation)
	title_bundle.floors.append(_make_floor("200"))
	var title_report := _validate_bundle(title_bundle)
	test_runner.assert_true(
		"ContentValidator / 缺 pickup_start",
		_has_code(title_report, "DIALOGUE_PICKUP_START_MISSING")
	)
	test_runner.assert_true(
		"ContentValidator / 缺 onboard_start",
		_has_code(title_report, "DIALOGUE_ONBOARD_START_MISSING")
	)
	test_runner.assert_true(
		"ContentValidator / 缺默认 destination",
		_has_code(title_report, "DIALOGUE_DEFAULT_DESTINATION_MISSING")
	)
	test_runner.assert_true(
		"ContentValidator / 推荐楼层缺 destination",
		_has_code(title_report, "DIALOGUE_RECOMMENDED_DESTINATION_MISSING")
	)


func _test_optional_destination_warning(test_runner: Variant) -> void:
	var bundle := _make_valid_bundle()
	bundle.floors.append(_make_floor("200"))
	var dispatch: DispatchDefinition = bundle.dispatches[0]
	dispatch.floor_relations.append(_make_relation("200", false))
	var report := _validate_bundle(bundle)
	test_runner.assert_equal(
		"ContentValidator / 普通可达楼层缺 destination 不产生 Error",
		0,
		report.get_error_count()
	)
	test_runner.assert_true(
		"ContentValidator / 普通可达楼层缺 destination 产生 Warning",
		_has_code(report, "DIALOGUE_REGISTERED_DESTINATION_MISSING")
	)


func _test_unlock_contracts(test_runner: Variant) -> void:
	var bundle := _make_valid_bundle()
	bundle.floors.append(_make_floor("200"))
	bundle.floors.append(_make_floor("300"))
	var dispatch: DispatchDefinition = bundle.dispatches[0]
	dispatch.dialogue_path = INVALID_UNLOCK_DIALOGUE
	dispatch.floor_relations.append(_make_relation("300", false))
	var report := _validate_bundle(bundle)
	test_runner.assert_true(
		"ContentValidator / unlock 不存在楼层",
		_has_code(report, "DIALOGUE_UNLOCK_FLOOR_MISSING")
	)
	test_runner.assert_true(
		"ContentValidator / unlock 无 relation",
		_has_code(report, "DIALOGUE_UNLOCK_RELATION_MISSING")
	)
	test_runner.assert_true(
		"ContentValidator / unlock 不具备推荐资格",
		_has_code(report, "DIALOGUE_UNLOCK_NOT_ELIGIBLE")
	)


func _test_valid_fixture(test_runner: Variant) -> void:
	var report := _validate_bundle(_make_valid_bundle())
	test_runner.assert_equal(
		"ContentValidator / 合法 fixture 不产生 Error",
		0,
		report.get_error_count()
	)


func _test_registered_content(test_runner: Variant) -> void:
	var report: ContentValidationReport = ContentRegistry.validate_all_content()
	report.print_to_output()
	test_runner.assert_equal(
		"ContentValidator / 正式内容 Error 为 0",
		0,
		report.get_error_count()
	)


func _make_valid_bundle() -> Dictionary:
	var floor := _make_floor("100")
	var passenger := _make_passenger("PASSENGER", "Passenger")
	var dispatch := _make_dispatch(
		"DISPATCH",
		"PASSENGER",
		"100",
		VALID_DIALOGUE
	)
	var shift := _make_shift("SHIFT", [&"DISPATCH"])
	return {
		"floors": [floor],
		"passengers": [passenger],
		"dispatches": [dispatch],
		"shifts": [shift],
	}


func _make_floor(floor_id: String) -> FloorDefinition:
	var floor := FloorDefinition.new()
	floor.floor_id = StringName(floor_id)
	return floor


func _make_passenger(
	passenger_id: String,
	display_name: String
) -> PassengerDefinition:
	var passenger := PassengerDefinition.new()
	passenger.passenger_id = StringName(passenger_id)
	passenger.display_name = display_name
	passenger.system_name = "SYSTEM"
	passenger.archive_text = "ARCHIVE"
	return passenger


func _make_dispatch(
	dispatch_id: String,
	passenger_id: String,
	floor_id: String,
	dialogue_path: String
) -> DispatchDefinition:
	var dispatch := DispatchDefinition.new()
	dispatch.dispatch_id = StringName(dispatch_id)
	dispatch.passenger_id = StringName(passenger_id)
	dispatch.pickup_floor_id = StringName(floor_id)
	dispatch.default_destination_floor_id = StringName(floor_id)
	dispatch.dialogue_path = dialogue_path
	for key: String in ContentValidator.PICKUP_DATA_KEYS:
		dispatch.pickup_data[key] = "value"
	for phase: String in DispatchPhase.get_all():
		if phase == DispatchPhase.SHIFT_IDLE:
			continue
		dispatch.camera_feeds[phase] = ["cabin", "outside"]
		dispatch.front_phase_texts[phase] = {
			"state": "state",
			"task": "task",
		}
	dispatch.floor_relations.append(_make_relation(floor_id, true))
	return dispatch


func _make_relation(
	floor_id: String,
	recommendation_eligible: bool
) -> DispatchFloorRelation:
	var relation := DispatchFloorRelation.new()
	relation.floor_id = StringName(floor_id)
	relation.relevance = 50
	relation.stability_preview = &"stable"
	relation.recommendation_eligible = recommendation_eligible
	relation.initially_recommended = recommendation_eligible
	return relation


func _make_shift(shift_id: String, dispatch_ids: Array) -> ShiftDefinition:
	var shift := ShiftDefinition.new()
	shift.shift_id = StringName(shift_id)
	for dispatch_id: Variant in dispatch_ids:
		shift.dispatch_ids.append(StringName(String(dispatch_id)))
	return shift


func _validate_bundle(bundle: Dictionary) -> ContentValidationReport:
	return ContentValidator.validate_content(
		bundle.floors,
		bundle.passengers,
		bundle.dispatches,
		bundle.shifts
	)


func _has_code(report: ContentValidationReport, code: String) -> bool:
	var marker := "][%s][" % code
	for line: String in report.get_all_lines():
		if marker in line:
			return true
	return false


func _has_codes(report: ContentValidationReport, codes: Array) -> bool:
	for code: Variant in codes:
		if not _has_code(report, String(code)):
			return false
	return true
