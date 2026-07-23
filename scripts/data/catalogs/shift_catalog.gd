class_name ShiftCatalog
extends Resource


## 明确登记正式值班，避免校验器扫描目录并误读测试资源。
@export var shifts: Array[ShiftDefinition] = []
