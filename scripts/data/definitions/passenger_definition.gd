class_name PassengerDefinition
extends Resource


## 乘客的永久唯一 ID；同一人物在不同派单中继续使用这个值。
@export var passenger_id: StringName

## 系统记录名称与操作界面的常用称呼都是稳定身份资料。
@export var system_name: String
@export var display_name: String

## 左侧乘客档案的基础内容。{dispatch} 仅在显示时替换为当前派单号。
@export_multiline var archive_text: String
