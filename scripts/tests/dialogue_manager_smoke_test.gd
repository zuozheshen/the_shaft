extends Control

# Dialogue Manager 烟雾测试文本。
# 这里先用脚本内置文本，不依赖外部 .dialogue 文件，避免导入问题干扰测试。
const TEST_DIALOGUE_TEXT := """
~ start

Passenger: 你是真人在听吗？
Passenger: 请选择回应。
- 是，我在听。
    Passenger: 那就别太快关门。
    do status_hint("乘客确认操作员为人工口")
    => END
- 请按标准格式陈述目的地。
    Passenger: ……低优先级补给路线。
    do unlock_floor("742")
    => END
- 我需要先核对记录。
    Passenger: 记录里不会写这个。
    do add_log("玩家选择先核对记录")
    => END
"""
const DIALOGUE_FILE_PATH := "res://dialogues/test/dm_smoke_test.dialogue"

var dialogue_label: Label
var debug_log_label: Label
var continue_button: Button
var choice_buttons: Array[Button] = []

var current_line
var dialogue_resource
var debug_lines: Array[String] = []

# 当前“继续”按钮要前往的下一行 id。
var current_continue_next_id: String = ""


func _ready() -> void:
	print("DialogueManagerSmokeTest _ready 已运行")

	# 根节点铺满窗口，避免 Control 尺寸为 0 导致 UI 不显示。
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_build_test_ui()

	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null:
		dialogue_label.text = "未找到 /root/DialogueManager，请确认插件已启用。"
		_append_debug("错误：未找到 DialogueManager 自动加载单例。")
		return

	# 关键：DialogueResource 只创建一次。
	# 后续所有 next_id 都必须基于同一个 resource 继续读取。
	dialogue_resource = load(DIALOGUE_FILE_PATH)

	_append_debug("直接 load .dialogue 资源：" + DIALOGUE_FILE_PATH)
	_append_debug("load 结果：" + str(dialogue_resource))

	if dialogue_resource == null:
		dialogue_label.text = "load .dialogue 失败。"
		_append_debug("错误：load .dialogue 返回 null。")
		return

	_append_debug("测试开始：读取 Dialogue Manager 对话。")
	await _load_line("start")


func _build_test_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 40
	panel.offset_right = -40
	panel.offset_bottom = -40
	add_child(panel)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(box)

	dialogue_label = Label.new()
	dialogue_label.text = "测试场景已启动，正在读取对话……"
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.custom_minimum_size = Vector2(0, 80)
	box.add_child(dialogue_label)

	for i in range(3):
		var button := Button.new()
		button.text = "选项 " + str(i + 1)
		button.visible = false
		button.disabled = true
		button.pressed.connect(_on_choice_pressed.bind(i))
		choice_buttons.append(button)
		box.add_child(button)

	# 单独的“继续”按钮。
	# 不复用选项按钮，避免继续按钮和选项按钮的 pressed 信号互相干扰。
	continue_button = Button.new()
	continue_button.text = "继续"
	continue_button.visible = false
	continue_button.disabled = true
	continue_button.pressed.connect(_on_continue_pressed)
	box.add_child(continue_button)

	debug_log_label = Label.new()
	debug_log_label.text = "DebugLog："
	debug_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_log_label.custom_minimum_size = Vector2(0, 300)
	box.add_child(debug_log_label)


func _load_line(title: String) -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if dm == null:
		dialogue_label.text = "未找到 /root/DialogueManager，请确认插件已启用。"
		_append_debug("错误：未找到 DialogueManager 自动加载单例。")
		_clear_choices()
		return

	if dialogue_resource == null:
		dialogue_label.text = "DialogueResource 为空。"
		_append_debug("错误：dialogue_resource 为空。")
		_clear_choices()
		return

	current_line = await dm.call(
		"get_next_dialogue_line",
		dialogue_resource,
		title,
		[self]
	)

	if current_line == null:
		dialogue_label.text = "对话结束。"
		_append_debug("对话结束。")
		_clear_choices()
		return

	var speaker := ""
	if current_line.character != "":
		speaker = current_line.character + "："

	dialogue_label.text = speaker + current_line.text
	_append_debug("读取到对白：" + dialogue_label.text)
	_append_debug("next_id: " + str(current_line.next_id))
	_append_debug("选项数量: " + str(current_line.responses.size()))

	# 当前行有选项：显示选项按钮。
	if not current_line.responses.is_empty():
		_show_choices(current_line.responses)
		return

	# 当前行没有选项，但还有下一行：显示“继续”按钮。
	# 这样玩家能看见乘客回复，不会被自动跳到 END 覆盖。
	if current_line.next_id != "":
		_show_continue_button(current_line.next_id)
		return

	# 当前行没有选项，也没有下一行：对话自然结束。
	_clear_choices()
	_append_debug("当前对白没有后续。")


func _show_choices(responses: Array) -> void:
	_clear_choices()

	for i in min(responses.size(), choice_buttons.size()):
		var response = responses[i]
		choice_buttons[i].visible = true
		choice_buttons[i].disabled = not response.is_allowed
		choice_buttons[i].text = response.text


func _show_continue_button(next_id: String) -> void:
	_clear_choices()

	current_continue_next_id = next_id
	continue_button.visible = true
	continue_button.disabled = false


func _clear_choices() -> void:
	for button in choice_buttons:
		button.visible = false
		button.disabled = true
		button.text = ""

	if continue_button != null:
		continue_button.visible = false
		continue_button.disabled = true

	current_continue_next_id = ""


func _on_choice_pressed(index: int) -> void:
	if current_line == null:
		_append_debug("错误：current_line 为空，无法处理选项。")
		return

	if index >= current_line.responses.size():
		_append_debug("错误：选项索引超出范围。")
		return

	var response = current_line.responses[index]
	_append_debug("选择：" + response.text)

	_clear_choices()
	await _load_line(response.next_id)


func _on_continue_pressed() -> void:
	if current_continue_next_id == "":
		_append_debug("错误：继续按钮没有 next_id。")
		return

	var next_id := current_continue_next_id
	_clear_choices()
	await _load_line(next_id)


# 以下三个方法是给 TEST_DIALOGUE_TEXT 里的 do xxx(...) 调用的。
# 目前只写入 DebugLog，不改主流程。

func status_hint(text: String) -> void:
	_append_debug("系统提示：" + text)


func unlock_floor(floor_id: String) -> void:
	_append_debug("解锁推荐楼层：" + floor_id)


func add_log(text: String) -> void:
	_append_debug("日志：" + text)


func _append_debug(text: String) -> void:
	debug_lines.append(text)

	if debug_log_label != null:
		debug_log_label.text = "DebugLog：\n" + "\n".join(debug_lines)

	print(text)
