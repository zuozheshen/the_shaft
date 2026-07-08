extends Node
class_name DemoFlowManager


# 状态变化后通知界面等监听者，避免其他节点反复查询流程状态。
signal state_changed(new_state_name: String)


const MAX_FRONT_HISTORY_LINES: int = 20


# DemoState 按演示流程顺序排列，用一个简单状态机串起完整体验。
enum DemoState {
	BOOT,
	WAITING_FOR_DISPATCH,
	PASSENGER_BOARDING,
	ROUTE_SELECTION,
	ARRIVAL,
	LOGGING,
	CASE_COMPLETE,
}


var current_state: DemoState = DemoState.BOOT

# 当前案例暂时以内置 GDScript 数据保存，后续会迁移到 data/cases/case_001.json。
# UI 应通过下方 getter 读取，未来替换 CaseManager / PassengerCase / JSON Loader 时无需大改。
# 所有楼层编号都保持为字符串，尤其不能把 "004" 转换为整数。
var current_case: Dictionary = {
	"case_id": "CASE_001",
	"passenger_name": "M. ROWAN",
	"dispatch_from": "612",
	"dispatch_to": "900",
	"recommended_destinations": ["900", "742", "612"],
	"submitted_destination": "",
	"initial_passenger_line": "乘客：你是真人在听吗？我需要去下面。",
	"passenger_record": {
		"name": "M. ROWAN",
		"registration_status": "UNREGISTERED",
		"risk_tag": "LOW",
		"dispatch": "612 → 900",
		"average_stay": "12 MIN",
		"recent_routes": [
			"612 → 900 / APPROVED",
			"612 → 900 / APPROVED",
			"612 → 900 / APPROVED",
		],
		"note": "该乘客近期路线重复率异常。当前自述与历史目的地不完全一致。",
	},
	"dialogue_nodes": [
		[
			{
				"operator": "下面是哪一层？",
				"passenger": "乘客：我不知道编号。只是比这里更低。",
				"status_hint": "目的地解析失败。乘客无法提供标准楼层编号，建议复核历史路线或保持门控关闭。",
			},
			{
				"operator": "你的申请记录显示目标是 900 层。",
				"passenger": "乘客：记录是旧的。那不是我要去的地方。",
				"status_hint": "乘客自述与派单记录冲突。建筑建议查看 RECORD 页，确认近期路线重复情况。",
			},
			{
				"operator": "你看起来不想去系统给你的地方。",
				"passenger": "乘客：你们总是这么说，好像我要去哪里是我决定的。",
				"status_hint": "检测到乘客对路线自主权存在抵触。建议降低询问强度，避免立即开门。",
			},
			{
				"operator": "先留在舱内，等我确认路线。",
				"passenger": "乘客：可以。但别让门开太久。那边会听见。",
				"status_hint": "乘客对门外环境表现出回避。建议查看门外摄像头，并保持乘客舱隔离。",
			},
		],
		[
			{
				"operator": "我会先保持门关闭。",
				"passenger": "乘客：谢谢。至少现在不要开。",
				"status_hint": "乘客明确请求维持隔离。建筑建议保持门控关闭，等待路线复核。",
			},
			{
				"operator": "我需要查看地面摄像头。",
				"passenger": "乘客：别看地上。那不是我的影子。",
				"status_hint": "乘客主动提及影子异常。建议切换至地面摄像头，并标记现场证据。",
			},
			{
				"operator": "门外是什么地方？",
				"passenger": "乘客：我不确定。灯太稳了。",
				"status_hint": "乘客描述门外灯候异常。建筑提示：过度稳定可能表示目标楼层状态不可信。",
			},
			{
				"operator": "暂时结束通话。",
				"passenger": "乘客：好。别把我写成异常。",
				"status_hint": "乘客担心异常归档。建议谨慎填写后续记录，避免过早上报。",
			},
		],
	],
	"floor_database": {
		"900": {
			"description": "派单记录目标层。", "relation": "94%", "access_eval": "可前往",
			"stability": "基本稳定", "message": "该楼层与当前派单高度一致。",
		},
		"742": {
			"description": "系统推荐的中继目标层。", "relation": "78%", "access_eval": "可前往",
			"stability": "轻微波动", "message": "该楼层与当前派单存在关联，但不是派单记录目标。",
		},
		"612": {
			"description": "当前派单起始相关层。", "relation": "63%", "access_eval": "可前往",
			"stability": "稳定", "message": "该楼层仍与当前派单相关，适合暂时复核。",
		},
		"004": {
			"description": "低层服务区。", "relation": "37%", "access_eval": "可前往",
			"stability": "中度波动", "message": "该楼层不在系统推荐中，但可能满足乘客的特殊需求。",
		},
		"387": {
			"description": "旧记录存放层。", "relation": "29%", "access_eval": "可前往",
			"stability": "轻微波动", "message": "该楼层与当前派单存在弱关联，建议谨慎提交。",
		},
		"392": {
			"description": "普通通行层。", "relation": "0%", "access_eval": "可前往",
			"stability": "稳定", "message": "该楼层与当前派单无关联，但建筑允许前往。",
		},
		"547": {
			"description": "普通办公层。", "relation": "0%", "access_eval": "可前往",
			"stability": "基本稳定", "message": "该楼层与当前派单无关联，稳定度未见明显变化。",
		},
	},
	"floor_book_entries": [
		{
			"number": "900", "intro": "派单记录中的目标层，常用于标准人员交接与登记确认。",
			"function": "登记、交接、身份复核、短暂停留。",
			"history": "该层曾在多次垂直调度异常后作为稳定参照层使用。",
			"note": "纸质索引内容可能滞后于建筑当前状态。",
		},
		{
			"number": "742", "intro": "中继楼层，常见于长距离垂直调度中的临时停靠。",
			"function": "中继等待、人员重新编号、短时路线复核。",
			"history": "曾因照明频闪与广播延迟被短暂停用，后恢复为有限通行层。",
			"note": "部分旧版索引将该层标为“等待层”。",
		},
		{
			"number": "612", "intro": "当前派单起始相关层，靠近普通居住与服务混合区。",
			"function": "居民登记、基础服务、短程派单生成。",
			"history": "多次门控校准记录显示，该层门外等待区存在轻微延迟。",
			"note": "该层记录常被用作派单起点参考。",
		},
		{
			"number": "004", "intro": "低层服务区，位于旧维护系统附近。",
			"function": "后勤转运、旧设备暂存、低层人员通行。",
			"history": "早期曾作为备用疏散层使用，后被改为服务与维护混合区。",
			"note": "纸质索引中对该层描述较少，部分信息可能缺失。",
		},
		{
			"number": "387", "intro": "旧记录存放层，保留大量过期派单、登记与复核资料。",
			"function": "纸质记录存储、过期档案转运、人工复查。",
			"history": "该层曾发生多次归档编号错位，后改为低频访问区域。",
			"note": "部分乘客记录可能仍指向该层的旧档案柜。",
		},
		{
			"number": "392", "intro": "普通通行层，服务于常规办公与短时停留。",
			"function": "办公、通行、临时等待。",
			"history": "最近一次维护记录显示通风系统调整完成。",
			"note": "未发现与当前派单直接相关的纸质标记。",
		},
		{
			"number": "547", "intro": "普通办公层，主要供内部人员使用。",
			"function": "办公、会议、文件处理。",
			"history": "该层曾因楼层编号牌更换导致短期导航混乱。",
			"note": "纸质索引中该层信息较完整，但缺少近期状态记录。",
		},
	],
}

# 三份状态是 FRONT 到 LEFT 的临时桥接，后续会由正式 PassengerCase 替换。
# 对话历史只用于 TRANSCRIPT，操作历史只用于 SYSTEM LOG，提示只用于 STATUS。
var front_dialogue_history: Array[String] = []
var front_operation_history: Array[String] = []
var current_building_status_hint: String = "暂无前台通话。"


func _ready() -> void:
	print_current_state()


func _unhandled_input(event: InputEvent) -> void:
	# ui_accept 作为早期原型的快捷推进方式，已被界面处理的输入不会走到这里。
	if event.is_action_pressed("ui_accept"):
		advance_state()
		get_viewport().set_input_as_handled()


func advance_state() -> void:
	# 每次只推进一个阶段，让按钮和快捷键共用同一套状态转换逻辑。
	match current_state:
		DemoState.BOOT:
			current_state = DemoState.WAITING_FOR_DISPATCH
		DemoState.WAITING_FOR_DISPATCH:
			current_state = DemoState.PASSENGER_BOARDING
		DemoState.PASSENGER_BOARDING:
			current_state = DemoState.ROUTE_SELECTION
		DemoState.ROUTE_SELECTION:
			current_state = DemoState.ARRIVAL
		DemoState.ARRIVAL:
			current_state = DemoState.LOGGING
		DemoState.LOGGING:
			current_state = DemoState.CASE_COMPLETE
		DemoState.CASE_COMPLETE:
			# 完成状态是流程终点，继续操作不会重复发送状态变化。
			return

	print_current_state()
	state_changed.emit(get_current_state_name())


func get_current_state_name() -> String:
	# 界面和调试输出使用可读名称，不需要了解枚举对应的整数值。
	return str(DemoState.keys()[current_state])


func print_current_state() -> void:
	print("Current demo state: ", get_current_state_name())


func add_front_dialogue(
		operator_text: String,
		passenger_text: String,
		status_hint: String
) -> void:
	# 一次选择写入成对台词，并把该选项的建筑判断交给 LEFT STATUS。
	front_dialogue_history.append("操作员：%s" % operator_text)
	var formatted_passenger_text: String = passenger_text
	if not formatted_passenger_text.begins_with("乘客："):
		formatted_passenger_text = "乘客：%s" % formatted_passenger_text
	front_dialogue_history.append(formatted_passenger_text)
	current_building_status_hint = status_hint

	# 每次移除一整组问答，避免 20 行上限把操作员与乘客台词拆开。
	while front_dialogue_history.size() > MAX_FRONT_HISTORY_LINES:
		front_dialogue_history.pop_front()
		front_dialogue_history.pop_front()


func add_front_operation(operation_text: String) -> void:
	# 当前是临时操作历史缓存：虽从 FRONT 事件开始，现在也接收 RIGHT 目标楼层操作。
	# 这些记录只供 LEFT SYSTEM LOG 使用，后续会由 PassengerCase 或统一事件系统替换。
	front_operation_history.append(operation_text)
	if front_operation_history.size() > MAX_FRONT_HISTORY_LINES:
		front_operation_history.pop_front()


func get_front_dialogue_history() -> Array[String]:
	# 返回副本，避免 LEFT 界面意外改写共享对话缓存。
	var history_copy: Array[String] = []
	history_copy.assign(front_dialogue_history)
	return history_copy


func get_front_operation_history() -> Array[String]:
	# 返回副本，避免 LEFT 界面意外改写共享操作缓存。
	var history_copy: Array[String] = []
	history_copy.assign(front_operation_history)
	return history_copy


func get_current_building_status_hint() -> String:
	return current_building_status_hint


# 以下方法是当前案例的临时访问接口，正式数据层接入后可保持 UI 调用方式不变。
func get_current_case() -> Dictionary:
	return current_case.duplicate(true)


func get_case_id() -> String:
	return str(current_case.get("case_id", ""))


func get_passenger_name() -> String:
	return str(current_case.get("passenger_name", ""))


func get_dispatch_from() -> String:
	return str(current_case.get("dispatch_from", ""))


func get_dispatch_to() -> String:
	return str(current_case.get("dispatch_to", ""))


func get_dispatch_text() -> String:
	return "%s → %s" % [get_dispatch_from(), get_dispatch_to()]


func get_recommended_destinations() -> Array:
	return current_case.get("recommended_destinations", []).duplicate(true)


func get_initial_passenger_line() -> String:
	return str(current_case.get("initial_passenger_line", ""))


func get_dialogue_nodes() -> Array:
	return current_case.get("dialogue_nodes", []).duplicate(true)


func get_passenger_record() -> Dictionary:
	return current_case.get("passenger_record", {}).duplicate(true)


func get_floor_database() -> Dictionary:
	return current_case.get("floor_database", {}).duplicate(true)


func get_floor_book_entries() -> Array:
	return current_case.get("floor_book_entries", []).duplicate(true)


func get_submitted_destination() -> String:
	return str(current_case.get("submitted_destination", ""))


func set_submitted_destination(destination: String) -> void:
	# 目标仍按字符串保存，避免 004 这样的正式楼层编号丢失前导零。
	current_case["submitted_destination"] = destination.strip_edges()
