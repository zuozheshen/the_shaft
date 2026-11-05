class_name DocumentFieldDefinition
extends Resource

@export var field_id: StringName
@export var subject_type: StringName
@export var subject_id: StringName
@export var comparison_key: StringName
@export_multiline var display_value: String
@export_enum("string", "floor_id", "bool", "int", "float") var value_type: String = "string"
@export var has_value: bool = true
## Godot Resource 使用单元素 Array 序列化不同标量类型；快照中的 comparable_value 是标量。
@export var comparable_value: Array = [""]
@export var source: DocumentSourceDefinition
## 仅规程条款填写；这是后续适用性判断的绑定，不是已知缺件清单。
@export var requirement_key: StringName
@export var required_material_type: StringName
@export var applicability_key: StringName

func snapshot(default_source: DocumentSourceDefinition) -> Dictionary:
	var effective_source: DocumentSourceDefinition = source if source != null else default_source
	return {"field_id": String(field_id), "subject_type": String(subject_type),
		"subject_id": String(subject_id), "comparison_key": String(comparison_key),
		"display_value": display_value, "value_type": value_type, "has_value": has_value,
		"comparable_value": comparable_value[0] if has_value and comparable_value.size() == 1 else null,
		"source": effective_source.snapshot() if effective_source != null else {},
		"requirement_key": String(requirement_key), "required_material_type": String(required_material_type),
		"applicability_key": String(applicability_key)}
