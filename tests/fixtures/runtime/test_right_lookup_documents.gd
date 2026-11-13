extends RefCounted
## 无剧情楼层档案。版本及静态停靠数据只在测试进程中配置。

const Base := preload("res://tests/fixtures/runtime/test_documents.gd")


static func document(floor_id: StringName, version: int = 1) -> DocumentDefinition:
	var record: DocumentDefinition = Base.document("right/floor/%s" % floor_id, &"floor_archive")
	record.version = version
	record.owner_type = &"floor"
	record.owner_id = floor_id
	record.title = "%s 楼层档案" % floor_id
	record.original_text = "当前记录：设备维护区。\n历史记录：曾作物资周转。"
	record.source.source_id = &"设施档案"
	record.source.source_version = str(version)
	record.source.updated_at = "2026-01-01"
	record.fields = []
	var values := {
		"current_function": "设备维护" if version == 1 else "设施检修",
		"current_area": "东翼设备与通风机房",
		"administrative_access_conditions": "须出示当班工作凭证并经值班人员核对",
		"historical_function": "物资周转",
	}
	for id: String in values:
		var field := DocumentFieldDefinition.new()
		field.field_id = StringName(id)
		field.subject_type = &"floor"
		field.subject_id = floor_id
		field.comparison_key = field.field_id
		field.display_value = values[id]
		field.comparable_value = [values[id]]
		record.fields.append(field)
	return record


static func install_blocked_floor() -> FloorDefinition:
	var blocked := FloorDefinition.new()
	blocked.floor_id = &"005"
	blocked.display_name = "无停靠平台的测试层"
	blocked.elevator_accessible = false
	blocked.elevator_block_reason = "该层无电梯停靠平台。"
	ContentRegistry.get("_floors_by_id")[blocked.floor_id] = blocked
	ContentRegistry.get("_ordered_floors").append(blocked)
	return blocked


static func remove_blocked_floor(blocked: FloorDefinition) -> void:
	ContentRegistry.get("_floors_by_id").erase(blocked.floor_id)
	ContentRegistry.get("_ordered_floors").erase(blocked)
