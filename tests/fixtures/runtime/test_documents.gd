extends RefCounted
## 只提供无剧情数据与测试适用性依赖；不注册到正式 Catalog。

static func document(id: String, kind: StringName = &"passenger_upload", version: int = 1,
		material: StringName = &"TEST_ID", owner: StringName = &"TEST_PERSON_001") -> DocumentDefinition:
	var result := DocumentDefinition.new()
	result.document_id = StringName(id)
	result.version = version
	result.owner_type = &"passenger"
	result.owner_id = owner
	result.material_type = material
	result.title = "TEST " + id
	result.original_text = "TEST ORIGINAL " + id
	result.source = DocumentSourceDefinition.new()
	result.source.source_id = StringName("TEST_SOURCE/" + id)
	result.source.kind = kind
	result.source.origin_ref = "res://tests/fixtures/runtime/test_documents.gd#" + id
	result.source.source_version = str(version)
	result.source.updated_at = "TEST_TIME_V%d" % version
	result.fields = [field("destination", "001" if version == 1 else "002", "floor_id")]
	return result

static func field(id: String, value: Variant, type: String = "string") -> DocumentFieldDefinition:
	var result := DocumentFieldDefinition.new()
	result.field_id = StringName(id)
	result.subject_type = &"passenger"
	result.subject_id = &"TEST_PERSON_001"
	result.comparison_key = &"destination_floor" if type == "floor_id" else StringName(id)
	result.display_value = str(value)
	result.value_type = type
	result.comparable_value = [value]
	return result

static func regulation() -> DocumentDefinition:
	var result: DocumentDefinition = document("rules", &"system_reference", 1, &"TEST_RULE")
	result.owner_type = &"system"
	result.owner_id = &"TEST_GENERAL_RULES"
	result.fields.clear()
	for key: String in ["applicable", "not_applicable", "unknown"]:
		var clause: DocumentFieldDefinition = field(key, "TEST REQUIREMENT")
		clause.subject_type = &"system"
		clause.subject_id = &"TEST_GENERAL_RULES"
		clause.requirement_key = &"TEST_REQUIRE_PERMIT"
		clause.required_material_type = &"TEST_WORK_PERMIT"
		clause.applicability_key = StringName(key)
		result.fields.append(clause)
	return result

static func definitions() -> Array[DocumentDefinition]:
	var result: Array[DocumentDefinition] = [document("identity"), document("second"),
		document("permit", &"passenger_upload", 1, &"TEST_WORK_PERMIT"),
		document("permit", &"passenger_upload", 2, &"TEST_WORK_PERMIT"),
		document("other_permit", &"passenger_upload", 1, &"TEST_WORK_PERMIT", &"TEST_PERSON_002"),
		regulation(), document("sample", &"system_reference", 1, &"TEST_WORK_PERMIT"),
		document("work", &"duty_record"), document("personnel", &"personnel_record"),
		document("floor", &"floor_archive"), document("excerpt", &"call_excerpt")]
	result[0].fields.append(field("false", false, "bool"))
	result[0].fields.append(field("zero", 0, "int"))
	result[0].fields.append(field("empty", ""))
	var missing: DocumentFieldDefinition = field("missing", "")
	missing.has_value = false
	missing.comparable_value = []
	result[0].fields.append(missing)
	return result

static func ref(id: String, version: int = 1, field_id: String = "") -> Dictionary:
	var result: Dictionary = {"document_id": id, "version": version}
	if not field_id.is_empty():
		result["field_id"] = field_id
	return result

static func applicability(clause: Dictionary, context: Dictionary) -> StringName:
	if context.passenger_id == "" or clause.applicability_key == "unknown":
		return &"UNRESOLVED"
	return &"APPLICABLE" if clause.applicability_key == "applicable" else &"NOT_APPLICABLE"
