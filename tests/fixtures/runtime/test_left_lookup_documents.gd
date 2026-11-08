extends RefCounted
## 只用于测试和预览。工作范围与更新时间来自文档定义。

const Docs := preload("res://tests/fixtures/runtime/test_documents.gd")
const PERSONNEL := "left_fixture/personnel"
const WORK := "left_fixture/work"
const HANDOVER := "left_fixture/handover"


static func definitions(owner: StringName, include_scroll_samples: bool = false) -> Array[DocumentDefinition]:
	var documents: Array[DocumentDefinition] = [
		_record(PERSONNEL, &"personnel_record", "人员档案", "身份记录：测试人员。", owner),
		_record(WORK, &"duty_record", "维修任务表", "当班有效。覆盖范围：001、002。", owner),
		_record(HANDOVER, &"duty_record", "交接记录", "当班交接：检查设施外观。", owner),
		_record("left_fixture/other", &"duty_record", "其他人员记录", "用于验证人员过滤。", &"TEST_PERSON_003"),
		Docs.document("left_fixture/upload", &"passenger_upload", 1, &"TEST_WORK_PERMIT", owner),
	]
	# 手动预览阅读正常长度的正文。只有滚动测试需要长文档。
	if include_scroll_samples:
		for document: DocumentDefinition in documents:
			for line: int in range(1, 51):
				document.original_text += "\n阅读位置测试行 %02d" % line
	return documents


static func _record(id: String, kind: StringName, title: String, body: String,
		owner: StringName) -> DocumentDefinition:
	var document := Docs.document(id, kind, 1, StringName(kind), owner)
	document.title = title
	document.original_text = body
	document.source.origin_ref = "res://tests/fixtures/runtime/test_left_lookup_documents.gd"
	document.source.updated_at = "2026-11-08 08:30"
	document.fields.clear()
	if id == WORK:
		for floor: String in ["001", "002"]:
			var field := Docs.field("work_floor_" + floor, floor, "floor_id")
			field.subject_id = owner
			field.display_value = "覆盖楼层：" + floor
			document.fields.append(field)
	return document


static func revised_work(documents: Array[DocumentDefinition]) -> DocumentDefinition:
	for document: DocumentDefinition in documents:
		if String(document.document_id) == WORK and document.version == 1:
			var revised := document.duplicate(true) as DocumentDefinition
			revised.version = 2
			revised.source.source_version = "2"
			revised.source.updated_at = "2026-11-08 09:00"
			return revised
	return null
