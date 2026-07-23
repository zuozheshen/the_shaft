class_name ContentValidationReport
extends RefCounted


var errors: Array[String] = []
var warnings: Array[String] = []


func add_error(code: StringName, context: String, message: String) -> void:
	errors.append(_format_line("ERROR", code, context, message))


func add_warning(code: StringName, context: String, message: String) -> void:
	warnings.append(_format_line("WARNING", code, context, message))


func has_errors() -> bool:
	return not errors.is_empty()


func has_warnings() -> bool:
	return not warnings.is_empty()


func get_error_count() -> int:
	return errors.size()


func get_warning_count() -> int:
	return warnings.size()


func get_errors() -> Array[String]:
	return errors.duplicate()


func get_warnings() -> Array[String]:
	return warnings.duplicate()


func get_all_lines() -> Array[String]:
	var lines: Array[String] = errors.duplicate()
	lines.append_array(warnings)
	return lines


func print_to_output() -> void:
	for line: String in get_all_lines():
		print(line)


func _format_line(
	severity: String,
	code: StringName,
	context: String,
	message: String
) -> String:
	return "[%s][%s][%s] %s" % [severity, code, context, message]
