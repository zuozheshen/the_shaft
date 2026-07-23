# 乘客案例制作清单

本清单用于当前数据链：

`PassengerDefinition → DispatchDefinition → Dialogue → Catalog → Shift → ContentValidator → 流程测试`

它只覆盖现有 Schema 和单轮 Dialogue 入口，不包含摄像头上下文解析、多轮对话、后果、存档或新楼层。

## 一、确定身份与路线

- [ ] 1. 确定唯一且稳定的 `passenger_id` 和 `dispatch_id`，并全局搜索确认没有重复。
- [ ] 2. 在 `data/passengers/` 创建 `PassengerDefinition`，填写 `passenger_id`、`system_name`、`display_name` 和 `archive_text`；不要为单个案例扩展 Schema。
- [ ] 3. 从已登记楼层中确定 `pickup_floor_id` 和 `default_destination_floor_id`，所有楼层 ID 都按字符串处理，带前导零的编号不得转为整数。

## 二、创建派单资源

- [ ] 4. 在 `data/dispatches/` 创建 `DispatchDefinition`，为全部需要支持的正式楼层建立 `DispatchFloorRelation`。
  - 每条 relation 填写 `floor_id`、`relevance`、`stability_preview`、`recommendation_eligible` 和 `initially_recommended`。
  - 默认目标必须有 relation。
  - `initially_recommended = true` 时，`recommendation_eligible` 也必须为 `true`。
- [ ] 5. 填写 `pickup_data` 的七个非空 String：
  - `arrival_status_hint`
  - `outside_audio_idle`
  - `after_open_line`
  - `after_open_hint`
  - `after_close_line`
  - `after_close_hint`
  - `after_close_status_hint`
- [ ] 6. 填写八个活动阶段的 `camera_feeds`；每个阶段恰好包含“舱内”和“门外”两个非空 String。
  - `WAITING_FOR_PICKUP`
  - `ARRIVED_AT_PICKUP`
  - `DOOR_GREETING_DONE`
  - `BOARDING_WAIT_DOOR_CLOSE`
  - `PASSENGER_ONBOARD`
  - `ARRIVED_AT_DESTINATION`
  - `DROPOFF_FEEDBACK`
  - `DROPOFF_WAIT_DOOR_CLOSE`
- [ ] 7. 填写同样八个阶段的 `front_phase_texts`；每阶段都有非空 `state` 和 `task`。
  - 只使用模板系统已经支持的占位符。
  - 目标尚未确定时，不要在画面或任务文字中提前写死远端目标。

## 三、编写 Dialogue

- [ ] 8. 创建对应 `.dialogue` 文件并编写唯一的 `pickup_start`。
- [ ] 9. 编写唯一的 `onboard_start`，只调用当前 Adapter 已支持的方法。
- [ ] 10. 为派单需要覆盖的每个已登记楼层编写唯一的 `destination_<floor_id>`。
- [ ] 11. 逐项检查每个 `unlock_floor("<floor_id>")`：
  - 楼层已经登记。
  - 派单存在对应 relation。
  - relation 的 `recommendation_eligible = true`。
  - 带前导零的 ID 在 Dialogue 和 relation 中完全一致。

## 四、接入正式内容

- [ ] 12. 在 `PassengerCatalog` 末尾登记新乘客。
- [ ] 13. 在 `DispatchCatalog` 末尾登记新派单。
- [ ] 14. 将派单加入目标 `ShiftDefinition`，复核顺序且不修改 `shift_id`。
- [ ] 15. 将 Dialogue 路径追加到 `project.godot` 的 `locale/translations_pot_files`，保留原有条目和其他项目设置。

## 五、自动与手动验证

- [ ] 16. 更新测试，锁定 ID、引用、楼层关系、推荐、前导零、状态隔离、值班闭环和正式内容数量；不要比较整段长台词。
- [ ] 17. 运行 `ContentRegistry.validate_all_content()` 和全部 headless 测试。
  - 正式内容 Error 必须为 0。
  - 比较修改前后的 Warning，确认新案例没有引入目标标题、relation、稳定性、占位符或解锁资格问题。
  - 使用 120 秒硬超时，检查退出码、Parse Error 和 Invalid call。
- [ ] 18. 在 Godot 4.7 中手动完成整条派单。
  - 分别验证门外通话和直接开门接乘。
  - 验证初始推荐和 Dialogue 解锁后的新增推荐。
  - 输入带前导零的楼层。
  - 检查八个阶段的 UI / 摄像头文字是否符合物理位置。
  - 走完每个 destination 分支，并确认末单后只结束一次值班。

## 提交前保护检查

- [ ] 运行 `git diff --check`。
- [ ] 检查 `git diff --name-status` 与 `git diff --stat`。
- [ ] 确认没有修改旧案例、楼层资源、Dialogue Manager 插件、3D 场景或美术。
- [ ] 确认 `.godot/`、日志、临时文件和编辑器备份没有进入版本控制。
