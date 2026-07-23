class_name DispatchCatalog
extends Resource


## 明确登记可用派单，避免运行时扫描目录加载测试或废弃资源。
@export var dispatches: Array[DispatchDefinition] = []
