class_name DocumentReviewMatcher
extends RefCounted


static func context_matches(state: DispatchDocumentState, constraints: Array) -> bool:
	for item: Dictionary in constraints:
		if not _matches(state.get_current_field(state.session_id, item.ref), item):
			return false
	return true


static func challenge_matches(rule: DocumentReviewRule, state: DispatchDocumentState,
		a: Dictionary, b: Dictionary) -> bool:
	if rule.requirement_key != &"" or not context_matches(state, rule.context):
		return false
	for pair: Dictionary in rule.pairs:
		if ((_matches(a, pair.a) and _matches(b, pair.b)) or (_matches(a, pair.b) and _matches(b, pair.a))) \
				and context_matches(state, pair.get("context", [])):
			return true
	return false


static func _matches(field: Dictionary, constraint: Dictionary) -> bool:
	if field.is_empty() or not field.has_value:
		return false
	return field.ref == constraint.ref and field.acquisition.route == constraint.route \
		and field.acquisition.document_source.kind == constraint.source_kind \
		and typeof(field.comparable_value) == typeof(constraint.value) and field.comparable_value == constraint.value


static func valid(rule: DocumentReviewRule) -> bool:
	if rule == null or String(rule.question_id).strip_edges().is_empty() or rule.response_title.strip_edges().is_empty():
		return false
	if rule.requirement_key != &"":
		if rule.applicability_key == &"" or not rule.pairs.is_empty() \
				or rule.supplement_action.is_empty() or rule.supplement_refs.is_empty():
			return false
	elif rule.pairs.is_empty() or rule.applicability_key != &"" \
			or not rule.supplement_action.is_empty() or not rule.supplement_refs.is_empty():
		return false
	if not _valid_context(rule.context):
		return false
	for pair: Dictionary in rule.pairs:
		if not _valid_constraint(pair.get("a")) or not _valid_constraint(pair.get("b")) \
				or pair.a.ref.document_id == pair.b.ref.document_id or not _valid_context(pair.get("context", [])):
			return false
	var supplement_ids := {}
	for ref: Dictionary in rule.supplement_refs:
		if not DispatchDocumentState.valid_ref(ref) or supplement_ids.has(String(ref.document_id)):
			return false
		supplement_ids[String(ref.document_id)] = true
	return true


static func _valid_context(value: Variant) -> bool:
	if not value is Array:
		return false
	for constraint: Variant in value:
		if not _valid_constraint(constraint):
			return false
	return true


static func _valid_constraint(value: Variant) -> bool:
	if not value is Dictionary or not value.get("ref") is Dictionary:
		return false
	var kinds: Array = DispatchDocumentState.ROUTES.get(value.get("route", ""), [])
	return DispatchDocumentState.valid_ref(value.ref, true) and value.get("source_kind") in kinds \
		and value.has("value") and typeof(value.value) in [TYPE_STRING, TYPE_BOOL, TYPE_INT, TYPE_FLOAT]
