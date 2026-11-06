extends RefCounted
## 预览与回归专用材料；来源不等于已核实事实，不写入正式 Catalog。
const Base := preload("res://tests/fixtures/runtime/test_documents.gd")

static func definitions() -> Array[DocumentDefinition]:
	var result: Array[DocumentDefinition] = []
	for version in [1, 2, 3]:
		var task: DocumentDefinition = Base.document("preview/task", &"passenger_upload", version, &"TEST_REPAIR_ORDER")
		task.title = "维修任务表"
		task.original_text = "乘客提交 / 维修任务表\n工单 R-001\n作业楼层：001\n修订：%d\n\n" % version + (
			"检修记录：检查设备外壳、固定件与接线。\n" if version == 1 else
			"补充记录：接线已重新固定，请按本版任务范围复核。\n").repeat(24)
		result.append(task)
	var identity: DocumentDefinition = Base.document("preview/identity", &"passenger_upload", 1, &"TEST_IDENTITY")
	identity.title = "身份证明"
	identity.original_text = "乘客提交 / 身份证明\n姓名：测试维修员\n证件编号：ID-001\n\n此份材料为乘客上传原文。\n上传不代表内容已被核实。\n".repeat(12)
	result.append(identity)
	var floor_doc: DocumentDefinition = Base.document("preview/floor", &"floor_archive")
	floor_doc.title = "001 楼层档案"
	floor_doc.owner_type = &"floor"
	floor_doc.owner_id = &"001"
	floor_doc.fields[0].subject_type = &"floor"
	floor_doc.fields[0].subject_id = &"001"
	floor_doc.original_text = "右台调阅 / 楼层档案\n楼层：001\n名称：测试设备层\n\n调阅记录仅描述档案来源。\n".repeat(16)
	result.append(floor_doc)
	var floor_v2: DocumentDefinition = floor_doc.duplicate(true)
	floor_v2.version = 2
	floor_v2.source.source_version = "2"
	result.append(floor_v2)
	var personnel: DocumentDefinition = Base.document("preview/personnel", &"personnel_record")
	personnel.title = "左台人员档案"
	personnel.original_text = "左台查询完成后取得的测试档案，不是乘客上传。"
	result.append(personnel)
	var first_v2: DocumentDefinition = Base.document("preview/first_v2", &"passenger_upload", 2)
	first_v2.title = "首次取得v2的测试资料"
	result.append(first_v2)
	var rules: DocumentDefinition = Base.regulation()
	rules.document_id = &"preview/rules"
	rules.title = "当班核验规程"
	rules.original_text = "系统参考 / 当班核验规程\n请阅读材料的来源、版本及作业范围。\n例外条款须结合当前情况自行审阅。\n".repeat(12)
	for field in rules.fields:
		field.display_value = "规程条款示例 / 请结合适用条件审阅"
	result.append(rules)
	var rules_v2: DocumentDefinition = rules.duplicate(true)
	rules_v2.version = 2
	rules_v2.source.source_version = "2"
	result.append(rules_v2)
	var sample: DocumentDefinition = Base.document("preview/sample", &"system_reference", 1, &"TEST_SAMPLE")
	sample.owner_type = &"system"
	sample.owner_id = &"TEST_SAMPLE"
	sample.title = "工作证样板"
	sample.original_text = "系统参考 / 工作证样板\n姓名：示例\n编号：示例\n样板仅说明格式，不能当作乘客提交。\n".repeat(12)
	result.append(sample)
	return result

static func ref(id: String, version: int = 1) -> Dictionary:
	return {"document_id": "preview/" + id, "version": version}

static func submit_initial(manager: DemoFlowManager) -> RefCounted:
	return manager.receive_passenger_batch(manager.get_document_session_id(), &"preview:first",
		[ref("identity"), ref("task")])

static func acquire_floor(manager: DemoFlowManager) -> RefCounted:
	return manager.accept_right_lookup_result(manager.get_document_session_id(), &"preview:right:1", [ref("floor")])

static func supplement(manager: DemoFlowManager) -> RefCounted:
	return manager.receive_passenger_batch(manager.get_document_session_id(), &"preview:supplement:2", [ref("task", 2)])