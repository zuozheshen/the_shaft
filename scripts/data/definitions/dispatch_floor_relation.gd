class_name DispatchFloorRelation
extends Resource


## 该楼层在所属派单中的判断资料。它不定义楼层本身，也不保存送达后的结果。
@export var floor_id: StringName
@export_range(0, 100, 1) var relevance: int = 0
@export var stability_preview: StringName = &"none"
@export var recommendation_eligible: bool = false
@export var initially_recommended: bool = false
