class_name DispatchDocumentState
extends RefCounted

## 每次开单生成新身份；即使派单 ID 相同，旧引用和回调也不能沿用。
static var _next_session_id: int = 0
var session_id: int
# 只保存本次派单有限的已配置事件，随资料会话销毁。
var passenger_events: Dictionary[String, Dictionary] = {}
var review_operations: Dictionary = {}
var _documents: Dictionary = {}
var _latest: Dictionary = {}
var _event_payloads: Dictionary = {}
var _events: Array[Dictionary] = []
var _requests: Array[Dictionary] = []
var _request_payloads: Dictionary = {}
var _requirements: Dictionary = {}
var _challenges: Array[Dictionary] = []
var _challenge_payloads: Dictionary = {}

const ROUTES: Dictionary = {
	"passenger": ["passenger_upload"], "system": ["system_reference"],
	"left": ["personnel_record", "duty_record"], "right": ["floor_archive"],
	"main": ["call_excerpt"],
}

func _init() -> void:
	_next_session_id += 1
	session_id = _next_session_id

func close() -> void:
	session_id = 0
	passenger_events.clear()
	review_operations.clear()
	_documents.clear()
	_latest.clear()
	_event_payloads.clear()
	_events.clear()
	_requests.clear()
	_request_payloads.clear()
	_requirements.clear()
	_challenges.clear()
	_challenge_payloads.clear()

func matches_session(expected: int) -> bool:
	return expected > 0 and expected == session_id

## 已提交事件是唯一依据；不因收件数量、系统资料或查询记录推定初始提交已完成。
func has_initial_submission(expected: int) -> bool:
	if not matches_session(expected):
		return false
	for event: Dictionary in _events:
		if event.route == "passenger":
			return true
	return false

## 仅应用层调用；W 端口不暴露通用取得方法。候选快照先完整校验，再一次提交。
func receive(expected: int, event_id: StringName, documents: Array, route: String,
		acquired_at: float = -1.0) -> Dictionary:
	if not matches_session(expected):
		return outcome(false, "STALE_SESSION")
	if event_id == &"" or not ROUTES.has(route) or (documents.is_empty() and route != "passenger"):
		return outcome(false, "INVALID_EVENT")
	var report := ContentValidationReport.new()
	ContentValidator.validate_documents(documents, report)
	if report.has_errors():
		return outcome(false, "INVALID_DOCUMENT")
	var payload: Array[Dictionary] = []
	var ids: Dictionary = {}
	for document: DocumentDefinition in documents:
		var item: Dictionary = document.snapshot()
		if item.source.kind not in ROUTES[route]:
			return outcome(false, "SOURCE_ROUTE_DENIED")
		if ids.has(item.document_id):
			return outcome(false, "BATCH_DOCUMENT_DUPLICATE")
		ids[item.document_id] = true
		payload.append(item)
	payload.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.document_id < b.document_id)
	var event_key: String = route + ":" + String(event_id)
	if _event_payloads.has(event_key):
		return outcome(_event_payloads[event_key] == payload,
			"UNCHANGED" if _event_payloads[event_key] == payload else "EVENT_CONFLICT")
	var pending: Array[Dictionary] = []
	for item: Dictionary in payload:
		var id: String = item.document_id
		var version: int = item.version
		if _latest.has(id):
			var previous: Dictionary = _documents[id][_latest[id]].document
			if not _same_identity(previous, item):
				return outcome(false, "DOCUMENT_IDENTITY_CONFLICT")
			if version < int(_latest[id]):
				return outcome(false, "STALE_VERSION")
			if version == int(_latest[id]):
				if previous != item:
					return outcome(false, "VERSION_CONFLICT")
				continue
		pending.append(item)
	# 从此处到返回不调用外部代码、不发信号；调用方只在整个提交完成后通知。
	_event_payloads[event_key] = payload.duplicate(true)
	# 首个空上传仍提交一个完成事件；后续无新资料的重试保持幂等。
	var completes_initial: bool = route == "passenger" and not has_initial_submission(expected)
	if pending.is_empty() and not completes_initial:
		return outcome(true, "UNCHANGED")
	var timestamp: float = Time.get_unix_time_from_system() if acquired_at < 0 else acquired_at
	var refs: Array[Dictionary] = []
	for item: Dictionary in pending:
		var change_kind: String = "updated" if _latest.has(item.document_id) else "received"
		if not _documents.has(item.document_id):
			_documents[item.document_id] = {}
		_documents[item.document_id][item.version] = {"document": item.duplicate(true),
			"session_id": session_id, "acquired_at": timestamp, "sequence": _events.size() + 1,
			"route": route, "event_id": String(event_id), "change_kind": change_kind}
		_latest[item.document_id] = item.version
		refs.append({"document_id": item.document_id, "version": item.version})
	_events.append({"session_id": session_id, "event_id": String(event_id),
		"route": route, "document_refs": refs, "committed_at": timestamp})
	return outcome(true, "INITIAL_SUBMISSION_COMPLETED" if pending.is_empty() else "DOCUMENTS_ACQUIRED", true)

func get_documents(expected: int, received_only: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not matches_session(expected):
		return result
	for id: String in _latest:
		var item: Dictionary = _documents[id][_latest[id]]
		if not received_only or item.route == "passenger":
			result.append(item.duplicate(true))
	return result

func get_document(expected: int, ref: Dictionary) -> Dictionary:
	if not matches_session(expected) or not valid_ref(ref):
		return {}
	return _documents.get(ref.document_id, {}).get(ref.version, {}).duplicate(true)

func get_field(expected: int, ref: Dictionary) -> Dictionary:
	if not valid_ref(ref, true):
		return {}
	var receipt: Dictionary = get_document(expected, ref)
	if receipt.is_empty():
		return {}
	var field: Dictionary = receipt.document.fields.get(String(ref.field_id), {}).duplicate(true)
	if not field.is_empty():
		field["ref"] = {"document_id": String(ref.document_id), "version": ref.version, "field_id": String(ref.field_id)}
		field["acquired_at"] = receipt.acquired_at
		# source 只说明原始出处；取得身份始终属于包住该字段的文档，不能由覆盖提升。
		field["acquisition"] = {
			"document_ref": {"document_id": receipt.document.document_id, "version": receipt.document.version},
			"route": receipt.route, "document_source": receipt.document.source.duplicate(true),
		}
	return field

func get_events(expected: int) -> Array[Dictionary]:
	return _events.duplicate(true) if matches_session(expected) else []

func get_requests(expected: int) -> Array[Dictionary]:
	return _requests.duplicate(true) if matches_session(expected) else []

func get_challenges(expected: int) -> Array[Dictionary]:
	return _challenges.duplicate(true) if matches_session(expected) else []

func get_clause(expected: int, ref: Dictionary) -> Dictionary:
	var field: Dictionary = get_field(expected, ref)
	var receipt: Dictionary = get_document(expected, ref)
	if field.is_empty() or receipt.is_empty() or receipt.document.source.kind != "system_reference":
		return {}
	if field.requirement_key == "" or field.required_material_type == "" or field.applicability_key == "":
		return {}
	return field

## 适用性由 Manager 接入口先判定；这里只检查实收和记录，不制造自动补件。
func record_material_request(expected: int, request_id: StringName, ref: Dictionary, target: Dictionary) -> Dictionary:
	if not matches_session(expected):
		return outcome(false, "STALE_SESSION")
	if not has_initial_submission(expected):
		return outcome(false, "INITIAL_SUBMISSION_REQUIRED")
	var clause: Dictionary = get_clause(expected, ref)
	if request_id == &"" or clause.is_empty() or target.get("type") != "passenger" or String(target.get("id", "")).is_empty():
		return outcome(false, "INVALID_CLAUSE")
	var payload: Dictionary = {"clause_ref": clause.ref, "target_subject": target.duplicate(true)}
	if _request_payloads.has(request_id) and _request_payloads[request_id] != payload:
		return outcome(false, "EVENT_CONFLICT")
	for receipt: Dictionary in get_documents(expected, true):
		var document: Dictionary = receipt.document
		if (document.material_type == clause.required_material_type
				and document.owner_type == target.type and document.owner_id == target.id):
			return outcome(true, "ALREADY_PROVIDED")
	var key: String = var_to_str([clause.requirement_key, target.type, target.id])
	if _requirements.has(key):
		_request_payloads[request_id] = payload.duplicate(true)
		return outcome(true, "REQUEST_ALREADY_RECORDED")
	_request_payloads[request_id] = payload.duplicate(true)
	_requirements[key] = String(request_id)
	_requests.append({"request_id": String(request_id), "requirement_key": clause.requirement_key,
		"clause_ref": clause.ref.duplicate(true), "target_subject": target.duplicate(true),
		"required_material_type": clause.required_material_type, "created_at": Time.get_unix_time_from_system()})
	return outcome(true, "MATERIAL_REQUESTED", true)

func record_challenge(expected: int, challenge_id: StringName, a_ref: Dictionary, b_ref: Dictionary) -> Dictionary:
	if not matches_session(expected):
		return outcome(false, "STALE_SESSION")
	if not has_initial_submission(expected):
		return outcome(false, "INITIAL_SUBMISSION_REQUIRED")
	var a: Dictionary = get_field(expected, a_ref)
	var b: Dictionary = get_field(expected, b_ref)
	if challenge_id == &"" or a.is_empty() or b.is_empty() or not a.has_value or not b.has_value:
		return outcome(false, "INVALID_FIELD_REF")
	if a_ref.document_id == b_ref.document_id and a_ref.version == b_ref.version:
		return outcome(false, "SAME_DOCUMENT")
	var payload: Dictionary = {"a_ref": a.ref, "b_ref": b.ref}
	if _challenge_payloads.has(challenge_id):
		return outcome(_challenge_payloads[challenge_id] == payload,
			"UNCHANGED" if _challenge_payloads[challenge_id] == payload else "EVENT_CONFLICT")
	_challenge_payloads[challenge_id] = payload.duplicate(true)
	var record: Dictionary = payload.duplicate(true)
	record["challenge_id"] = String(challenge_id)
	record["created_at"] = Time.get_unix_time_from_system()
	_challenges.append(record)
	return outcome(true, "CHALLENGE_RECORDED", true)

static func valid_ref(ref: Dictionary, field: bool = false) -> bool:
	var document_id: Variant = ref.get("document_id")
	if not (document_id is String or document_id is StringName) or String(document_id).is_empty():
		return false
	if not ref.get("version") is int or ref.version <= 0:
		return false
	if not field:
		return true
	var field_id: Variant = ref.get("field_id")
	return (field_id is String or field_id is StringName) and not String(field_id).is_empty()

static func outcome(succeeded: bool, code: String, changed: bool = false) -> Dictionary:
	return {"succeeded": succeeded, "code": code, "changed": changed}

static func _same_identity(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["owner_type", "owner_id", "material_type"]:
		if a[key] != b[key]:
			return false
	if a.source.kind != b.source.kind or a.source.source_id != b.source.source_id:
		return false
	for id: String in a.fields:
		if not b.fields.has(id):
			continue
		for key: String in ["subject_type", "subject_id", "comparison_key", "value_type"]:
			if a.fields[id][key] != b.fields[id][key]:
				return false
	return true


## 正式审查只接受该文档最新取得版本；保留历史阅读能力。
func get_current_field(expected: int, ref: Dictionary) -> Dictionary:
	if not valid_ref(ref, true) or _latest.get(String(ref.document_id)) != ref.version:
		return {}
	return get_field(expected, ref)
