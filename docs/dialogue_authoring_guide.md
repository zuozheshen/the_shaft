# Dialogue Manager 乘客对话编写指南

本文只覆盖当前主流程需要的 `.dialogue` 写法，不是 Dialogue Manager 3 的完整语法手册。

目标是让你可以替换 `dialogues/passengers/passenger_001.dialogue` 的内容，同时尽量不破坏：

- 接乘前门外对话
- 开门、乘客进舱、关门流程
- 舱内多层分支问答
- 系统提示
- 推荐楼层解锁
- 目标楼层提交后的乘客反馈
- 左操作台 Transcript 自动记录

不能保证“任何改法都不出错”。但只要按本文规则写，并完成最后的检查清单，通常不会破坏现有流程。

## 信息职责

当前 UI 把几类信息分开显示：

- 当前派单目标：流程任务，例如“前往 612 层接乘”，来自派单/phase，不等于乘客最终想去的地方。
- 乘客自述目标：写在 `.dialogue` 乘客台词里，由玩家询问获得。
- 系统推荐楼层：右侧控制台的推荐列表，可由 `do unlock_floor("742")` 临时加入。
- 已提交目标：玩家最终在右侧控制台提交的楼层，会显示在右侧摘要和左侧 Status/Record 中。

主操作台 `SystemHintLabel` 只显示短操作提示。详细系统判断放在左侧 Status，不要依赖主操作台完整复读。

## 必须保留的标题

当前主操作台代码会主动寻找这些标题：

```dialogue
~ start
~ pickup_start
~ onboard_start
```

目标楼层反馈标题按楼层号命名：

```dialogue
~ destination_900
~ destination_612
~ destination_742
~ destination_004
```

规则：

- `~ start` 必须存在。
- `~ start` 建议只跳到 `pickup_start`。
- `~ pickup_start` 是接乘前、门外乘客对话。
- `~ onboard_start` 是关门后、乘客在舱内的正式问答。
- `~ destination_楼层号` 是提交正式目标楼层后的乘客反馈。

推荐开头：

```dialogue
~ start
=> pickup_start
```

## 接乘前对话

`pickup_start` 只负责确认门外乘客，不负责开门，也不负责让乘客进电梯。

正确写法：

```dialogue
~ pickup_start
Passenger: 这里是 612。你那边是真人操作员吗？
- 我在听。请确认你是 612 层等待乘客。
    do status_hint("门外乘客已完成人工通话确认。请开启舱门完成接乘。")
    do mark_door_greeting_done()
    Passenger: 是我。我就在门外。
    => END
```

关键规则：

- `pickup_start` 里至少要有一个选项调用 `do mark_door_greeting_done()`。
- `mark_door_greeting_done()` 只表示“门外通话确认完成”。
- 真正开门必须由玩家点击开门按钮。
- 真正进入舱内和等待关门仍由旧 phase 流程负责。
- 不要在 `pickup_start` 里跳到 `onboard_start`。

## 舱内对话

`onboard_start` 是关门后才会启动的正式问答入口。

基本结构：

```dialogue
~ onboard_start
Passenger: 你是真人在听，对吧？那我能不能不直接去 900？
- 你想去哪？
    => below_clues
- 系统目前只推荐 900。
    do status_hint("系统当前推荐目标仅为 900。建议继续询问原因。")
    => about_900

~ below_clues
Passenger: 我记不清楼层号。只记得那里地上总是湿的。
- 那听起来像服务区。
    => service_area
- 你为什么不直接申请那个楼层？
    => application_reason
```

关键规则：

- 每个 `=> xxx` 都必须有对应的 `~ xxx`。
- 不想继续分支时，用 `=> END`。
- 不要用“继续”选项模拟下一句；当前主 UI 不提供继续按钮。
- 玩家选完选项后，下一句乘客回复会立即显示。
- 所有玩家选项和乘客台词会自动写入左侧 Transcript，不需要写额外 mutation。

## 可用 mutation

当前 adapter 支持以下 mutation。

### status_hint

更新左侧 Status 的详细系统判断；主操作台只显示“系统判断已更新，请查看左侧 Status。”这类短提示。

```dialogue
do status_hint("乘客担心标准复核流程会覆盖旧记录。")
```

适合用于：

- 重要线索
- 系统判断建议
- 提醒玩家查记录或查楼层索引

不适合用于：

- 普通乘客台词
- 调试信息
- Transcript 备注

### unlock_floor

让右操作台推荐楼层列表加入指定楼层；主操作台只显示“推荐楼层已更新：楼层号。”这类短提示。

```dialogue
do unlock_floor("742")
```

规则：

- 楼层号必须写成字符串。
- `004` 这种前导零楼层必须写成 `"004"`。
- 不要写成 `do unlock_floor(004)`。
- 如果同一段对话同时调用 `status_hint` 和 `unlock_floor`，主操作台会合并显示短提示，例如：`系统判断已更新；推荐楼层已更新：742。`

### mark_door_greeting_done

标记门外乘客确认完成，允许玩家之后点击开门按钮推进接乘。

```dialogue
do mark_door_greeting_done()
```

规则：

- 只在 `pickup_start` 或其他门外确认标题中使用。
- 不要在舱内正式问答里使用。
- 不要把它当成“开门”或“乘客进舱”。

### reply_when_open_door

预留能力：登记“玩家点击开门后显示的乘客回应”。

```dialogue
do reply_when_open_door("乘客：谢谢。")
```

当前建议：

- 一般不要在正式乘客文件里使用。
- 现在的主流程更推荐：门外确认用 `mark_door_greeting_done()`，开门后的固定提示由门控流程显示。

### reply_when_close_door

预留能力：登记“玩家点击关门后显示的乘客回应”。

```dialogue
do reply_when_close_door("乘客：好了，现在能听见你了。")
```

当前建议同上：一般不要用，除非明确要做特殊门控回应。

## 目标楼层反馈

当乘客已上电梯并关门后，右操作台提交目标楼层会触发：

```dialogue
~ destination_楼层号
```

例如：

```dialogue
~ destination_900
do status_hint("目标 900 已确认。该目标与派单记录一致。")
Passenger: 好吧。那就是记录上的地方。
=> END

~ destination_612
do status_hint("目标 612 已确认。返回起点可维持流程安全，但可能无法推进乘客问题。")
Passenger: 送回去？那我可能又要坐回那张长椅上了。
=> END

~ destination_004
do status_hint("目标 004 已确认。该楼层与乘客服务区线索相符。")
Passenger: 你查到了？前面的零还在吗？
=> END
```

规则：

- 接乘前提交 `612` 是“前往接乘楼层”，不会触发 `destination_612`。
- 乘客上电梯并关门后提交 `612`，才是正式目的楼层反馈。
- 你希望玩家可能提交的楼层，都应提供对应 `destination_楼层号`。
- 没有对应标题时，主操作台不会显示该楼层的 DM 乘客反馈。

## 常见错误

### 错误：跳到不存在的标题

```dialogue
- 我会查旧记录。
    => old_record
```

但文件里实际写的是：

```dialogue
~ old_records
```

修复：统一名字。

### 错误：接乘前直接跳舱内对话

不要这样写：

```dialogue
~ pickup_start
Passenger: 你能开门吗？
- 可以。
    => onboard_start
```

原因：这样会绕过开门、进舱、关门 phase。

### 错误：把推荐楼层写成数字

不要这样写：

```dialogue
do unlock_floor(004)
```

正确写法：

```dialogue
do unlock_floor("004")
```

### 错误：用 mutation 写 Transcript

不要再写：

```dialogue
do add_transcript_note("玩家选择先核对记录")
```

当前主流程已经自动记录玩家选项和乘客台词。

## 推荐模板

新乘客文件可以从这个骨架开始：

```dialogue
~ start
=> pickup_start

~ pickup_start
Passenger: 这里是 612。你能听见我吗？
- 我在听。请确认你是等待乘客。
    do status_hint("门外乘客已完成人工通话确认。请开启舱门完成接乘。")
    do mark_door_greeting_done()
    Passenger: 是我。我在门外。
    => END

~ onboard_start
Passenger: 现在能听见你了。我不确定该不该直接去 900。
- 为什么不直接去 900？
    => about_900
- 你真正想找什么？
    => target_clues

~ about_900
Passenger: 900 是记录上的地方，但记录不一定能说明我为什么来。
- 我会把这个作为依据。
    do status_hint("乘客认为标准目标无法完整解释需求。")
    => case_summary

~ target_clues
Passenger: 我想先确认一件旧东西还在不在。
- 我会查楼层索引。
    do unlock_floor("742")
    => case_summary

~ case_summary
Passenger: 我不是拒绝流程。我只是想带着依据过去。
=> END

~ destination_900
do status_hint("目标 900 已确认。")
Passenger: 好吧。那就是记录上的地方。
=> END

~ destination_612
do status_hint("目标 612 已确认。")
Passenger: 送回去？那我可能又要重新等一次。
=> END
```

## 替换前检查清单

替换 `.dialogue` 后，至少检查：

- 文件里有 `~ start`。
- `~ start` 会进入 `pickup_start`。
- 文件里有 `~ pickup_start`。
- `pickup_start` 至少一个选项调用 `do mark_door_greeting_done()`。
- 文件里有 `~ onboard_start`。
- 每个 `=> xxx` 都能找到 `~ xxx`。
- 每个可能提交的正式目标都有 `~ destination_楼层号`。
- `unlock_floor` 的楼层号都用字符串。
- 没有 `do add_transcript_note(...)`。
- 没有在接乘前跳到 `onboard_start`。

可以用 PowerShell 做简单跳转检查：

```powershell
$lines = Get-Content dialogues\passengers\passenger_001.dialogue -Encoding UTF8
$titles = @{}
foreach ($line in $lines) {
	if ($line -match '^~\s+(.+)$') {
		$titles[$matches[1].Trim()] = $true
	}
}
$missing = @()
foreach ($line in $lines) {
	if ($line -match '=>\s+(.+)$') {
		$target = $matches[1].Trim()
		if ($target -ne 'END' -and -not $titles.ContainsKey($target)) {
			$missing += $target
		}
	}
}
if ($missing.Count -eq 0) {
	'All dialogue targets exist.'
} else {
	$missing | Sort-Object -Unique
}
```

## Godot 内测试流程

每次替换对话后，建议按这个顺序试一遍：

1. 运行主场景。
2. 右操作台提交 `612` 到接乘点。
3. 主操作台开麦，确认出现 `pickup_start` 里的门外对话。
4. 选择门外确认选项。
5. 点击开门，确认乘客进入舱内。
6. 点击关门，确认进入舱内问答。
7. 点击几个舱内选项，确认 Transcript 自动记录玩家选项和乘客回复。
8. 走到含 `unlock_floor("742")` 的分支，确认右操作台出现 `742`。
9. 提交 `900`、`612` 或其他目标，确认主操作台显示对应 `destination_xxx` 反馈。
