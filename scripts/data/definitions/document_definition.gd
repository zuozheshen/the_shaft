class_name DocumentDefinition
extends Resource

@export var document_id: StringName
@export var version: int = 1
@export var owner_type: StringName
@export var owner_id: StringName
@export var material_type: StringName
@export var title: String
@export_multiline var original_text: String
@export var source: DocumentSourceDefinition
@export var fields: Array[DocumentFieldDefinition] = []

func snapshot() -> Dictionary:
	var values: Dictionary = {}
	for field: DocumentFieldDefinition in fields:
		values[String(field.field_id)] = field.snapshot(source)
	return {"document_id": String(document_id), "version": version,
		"owner_type": String(owner_type), "owner_id": String(owner_id),
		"material_type": String(material_type), "title": title, "original_text": original_text,
		"source": source.snapshot() if source != null else {}, "fields": values}
