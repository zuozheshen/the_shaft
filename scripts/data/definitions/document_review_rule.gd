class_name DocumentReviewRule
extends Resource

## 内容配置只匹配确切的已取得字段、来源与值。没有规则就没有正式回应。
@export var question_id: StringName
@export var response_title: String
@export var requirement_key: StringName
@export var applicability_key: StringName
@export var context: Array[Dictionary] = []
## 每组包含 a、b；可选 context。各字段约束包含 ref、route、source_kind、value。
@export var pairs: Array[Dictionary] = []
@export var supplement_action: String
@export var supplement_refs: Array[Dictionary] = []
