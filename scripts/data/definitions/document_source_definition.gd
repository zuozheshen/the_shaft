class_name DocumentSourceDefinition
extends Resource

const KINDS: Array[StringName] = [&"passenger_upload", &"system_reference",
		&"personnel_record", &"duty_record", &"floor_archive", &"call_excerpt"]

@export var source_id: StringName
@export var kind: StringName
@export var origin_ref: String
@export var source_version: String
## 原始资料更新时间未知时留空；它与玩家取得时间不是同一时间。
@export var updated_at: String

## 仅由本单运行时填充的审查出处；不进入资料正文或详情标签。
var review_origin: Dictionary = {}

func snapshot() -> Dictionary:
	var result := {"source_id": String(source_id), "kind": String(kind),
		"origin_ref": origin_ref, "source_version": source_version, "updated_at": updated_at}
	if not review_origin.is_empty():
		result["review_origin"] = review_origin.duplicate(true)
	return result
