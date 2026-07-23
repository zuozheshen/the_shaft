extends RefCounted


func run(test_runner: Variant) -> void:
	var report := ContentValidationReport.new()
	report.add_error(&"TEST_ERROR", "fixture:report", "错误消息")
	report.add_warning(&"TEST_WARNING", "fixture:report", "警告消息")

	test_runner.assert_true("ContentValidationReport / 可识别 Error", report.has_errors())
	test_runner.assert_true("ContentValidationReport / 可识别 Warning", report.has_warnings())
	test_runner.assert_equal("ContentValidationReport / Error 数量", 1, report.get_error_count())
	test_runner.assert_equal("ContentValidationReport / Warning 数量", 1, report.get_warning_count())
	test_runner.assert_true(
		"ContentValidationReport / Error 格式包含字段",
		report.get_errors()[0] == "[ERROR][TEST_ERROR][fixture:report] 错误消息"
	)
	test_runner.assert_true(
		"ContentValidationReport / Warning 格式包含字段",
		report.get_warnings()[0] == "[WARNING][TEST_WARNING][fixture:report] 警告消息"
	)

	var error_copy: Array[String] = report.get_errors()
	error_copy.clear()
	test_runner.assert_equal(
		"ContentValidationReport / Error getter 返回副本",
		1,
		report.get_error_count()
	)
	var all_lines_copy: Array[String] = report.get_all_lines()
	all_lines_copy.clear()
	test_runner.assert_equal(
		"ContentValidationReport / 全部行 getter 返回副本",
		2,
		report.get_all_lines().size()
	)
