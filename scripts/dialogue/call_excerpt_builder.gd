extends RefCounted
## 只封装已经呈现的原句；不提取地点、确定性或其他结论。


static func build(excerpt: Dictionary, session: int, passenger_id: StringName,
		dispatch_id: StringName, resource_path: String) -> DocumentDefinition:
	if excerpt.get("session") != session or excerpt.get("passenger_id") != passenger_id \
			or excerpt.get("resource_path") != resource_path or resource_path.is_empty():
		return null
	var generation: int = excerpt.get("generation", 0)
	var version: String = excerpt.get("source_version", "")
	var rows: Array = excerpt.get("rows", [])
	if generation <= 0 or version.is_empty() or rows.size() not in [1, 3]:
		return null

	var id := "call_%d_%d" % [session, generation]
	var document := DocumentDefinition.new()
	document.document_id = StringName(id)
	document.owner_type = &"passenger"
	document.owner_id = passenger_id
	document.material_type = &"call_excerpt"
	document.title = "通话摘录 · %s" % str(rows.back().get("sequence", 0))
	document.original_text = "乘客陈述，未经核实。以下为通话原文，按呈现顺序排列。"
	document.source = _source(id, "%s#%s" % [resource_path, id], version)
	var previous: int = 0
	for index in rows.size():
		var row: Dictionary = rows[index]
		var operator := index == 1
		var sequence: int = row.get("sequence", 0)
		var raw: String = row.get("text", "")
		var line_id: String = row.get("line_id", "")
		if sequence <= previous or raw.strip_edges().is_empty() or line_id.is_empty() \
				or row.get("role") != ("operator" if operator else "passenger"):
			return null
		previous = sequence
		var speaker: String = row.get("speaker", "")
		var field := DocumentFieldDefinition.new()
		field.field_id = StringName("utterance_%03d" % (index + 1))
		field.subject_type = &"dispatch" if operator else &"passenger"
		field.subject_id = dispatch_id if operator else passenger_id
		field.comparison_key = &"spoken_quote"
		field.display_value = "%s：%s" % [speaker if not speaker.is_empty() else "未标明说话人", raw]
		field.comparable_value = [raw]
		field.source = _source("%s_%d" % [id, sequence],
			"%s#%s" % [resource_path, line_id], version)
		field.source_note = "原句 · %s · 顺序 %d · %s UTC · %s" % [
			field.source.origin_ref, sequence,
			Time.get_datetime_string_from_unix_time(int(row.occurred_at)), id]
		document.fields.append(field)
	return document


static func _source(id: String, origin: String, version: String) -> DocumentSourceDefinition:
	var source := DocumentSourceDefinition.new()
	source.source_id = StringName(id)
	source.kind = &"call_excerpt"
	source.origin_ref = origin
	source.source_version = version
	return source
