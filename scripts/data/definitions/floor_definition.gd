class_name FloorDefinition
extends Resource


## 楼层编号始终保存为字符串，避免 "004" 被转换为整数。
@export var floor_id: StringName

## 操作台和楼层索引书中使用的显示名称。
@export var display_name: String

## 楼层索引书中的通用资料，不包含当前派单的判断。
@export_multiline var description: String
@export_multiline var function_description: String
@export_multiline var maintenance_history: String
@export_multiline var book_note: String

## 控制纸质索引书的稳定显示顺序。
@export var book_order: int = 0
