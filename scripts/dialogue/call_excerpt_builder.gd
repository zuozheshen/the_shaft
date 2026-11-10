extends RefCounted
## 只封装已完整呈现的乘客原句。事件出处属于来源，不属于台词。


static func build(excerpt: Dictionary, session: int, passenger_id: StringName,
		resource_path: String) -> DocumentDefinition:
	if excerpt.get("session") != session or excerpt.get("passenger_id") != passenger_id \
			or excerpt.get("resource_path") != resource_path or resource_path.is_empty():
		return null
	var event_id: String = excerpt.get("source_event_id", "")
	var title: String = excerpt.get("title", "")
	var version: String = excerpt.get("source_version", "")
	var rows: Array = excerpt.get("rows", [])
	var presented_at: float = excerpt.get("presented_at", 0.0)
	if event_id.is_empty() or title.is_empty() or version.is_empty() or rows.is_empty() or presented_at <= 0.0:
		return null

	var id := "call_%s" % event_id.replace(":", "_")
	var origin := "%s#%s/%s" % [resource_path, title, event_id]
	var occurred := Time.get_datetime_string_from_unix_time(int(excerpt.occurred_at))
	var presented := Time.get_datetime_string_from_unix_time(int(presented_at))
	var document := DocumentDefinition.new()
	document.document_id = StringName(id)
	document.owner_type = &"passenger"
	document.owner_id = passenger_id
	document.material_type = &"call_excerpt"
	document.title = "乘客陈述摘录"
	document.original_text = "乘客陈述，未经核实。"
	document.source = _source(id, origin, version)
	if excerpt.has("question_id"):
		document.source.review_origin = {"question_id": String(excerpt.question_id),
			"refs": excerpt.review_refs.duplicate(true)}
	for index in rows.size():
		var row: Dictionary = rows[index]
		var raw: String = row.get("text", "")
		var line_id: String = row.get("line_id", "")
		var speaker: String = row.get("speaker", "")
		if raw.strip_edges().is_empty() or line_id.is_empty() or speaker.to_lower() in ["操作员", "operator"]:
			return null
		var field := DocumentFieldDefinition.new()
		field.field_id = StringName("utterance_%03d" % (index + 1))
		field.subject_type = &"passenger"
		field.subject_id = passenger_id
		field.comparison_key = &"spoken_quote"
		field.display_value = "%s：%s" % ["乘客" if speaker in ["", "Passenger"] else speaker, raw]
		field.comparable_value = [raw]
		field.source = _source("%s_%d" % [id, index + 1], "%s/%s" % [origin, line_id], version)
		field.source_note = "原句顺序 %d · 事件 %s · 发生 %s UTC · 呈现 %s UTC" % [
			index + 1, event_id, occurred, presented]
		document.fields.append(field)
	return document


static func _source(id: String, origin: String, version: String) -> DocumentSourceDefinition:
	var source := DocumentSourceDefinition.new()
	source.source_id = StringName(id)
	source.kind = &"call_excerpt"
	source.origin_ref = origin
	source.source_version = version
	return source
