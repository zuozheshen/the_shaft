class_name PassengerCatalog
extends Resource


## 明确列出可用乘客，避免运行时扫描目录加载测试资源。
@export var passengers: Array[PassengerDefinition] = []
