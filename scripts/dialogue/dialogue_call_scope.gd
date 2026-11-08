extends RefCounted
## 仅代表一次解析。旧协程恢复时仍拿着自己的身份，不能借用当前派单。

var _adapter: WeakRef
var _manager: WeakRef
var _session: int
var _generation: int
var _resource: DialogueResource


func _init(adapter: Node, manager: Node, session: int, generation: int, resource: DialogueResource) -> void:
	_adapter = weakref(adapter)
	_manager = weakref(manager)
	_session = session
	_generation = generation
	_resource = resource


func is_current(adapter: Node, manager: Node) -> bool:
	return adapter != null and manager != null and _session > 0 \
		and adapter == _adapter.get_ref() and manager == _manager.get_ref() \
		and manager.get_document_session_id() == _session \
		and adapter.parse_generation == _generation and adapter.dialogue_resource == _resource


func _send(kind: StringName, value: String = "") -> void:
	var adapter := _adapter.get_ref() as Node
	var manager := _manager.get_ref() as Node
	if is_current(adapter, manager):
		adapter.forward_scoped_mutation(self, kind, value)


func status_hint(value: String) -> void:
	_send(&"status_hint", value)


func unlock_floor(value: String) -> void:
	_send(&"unlock_floor", value)


func mark_door_greeting_done() -> void:
	_send(&"door_greeting")


func reply_when_open_door(value: String) -> void:
	_send(&"open_reply", value)


func reply_when_close_door(value: String) -> void:
	_send(&"close_reply", value)
