class_name FloorDefinition
extends Resource


## 最小楼层身份；编号保持字符串，测试层 001 的前导零不可丢失。
@export var floor_id: StringName
@export var display_name: String

## 静态停靠能力。门、运动和乘客动作由运行时联锁检查。
@export var elevator_accessible: bool = true
@export var elevator_block_reason: String = ""
