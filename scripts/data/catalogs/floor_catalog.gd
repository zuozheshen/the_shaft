class_name FloorCatalog
extends Resource


## 明确列出可用楼层，避免运行时扫描目录造成注册顺序不稳定。
@export var floors: Array[FloorDefinition] = []
