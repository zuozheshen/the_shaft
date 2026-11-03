# 内容重置第一阶段交接

- 基线：e46053cb4e7a13aa5233b2be1d5d9b4aadceac90。
- 分支：codex/content-reset；worktree：F:/the_shaft_worktrees/content-reset。
- 用户批准本次第一阶段：清空旧内容与楼层书，保留整体框架。

## 实际结果

正式入口启动于318，空舱待机；运行时只登记318、001（TEST 01）、002（TEST 02）。
318沿用ART09 Darker R3；测试层仅使用背景、地面等通用占位，侧面占位板隐藏以避免遮住编号。
旧七层、三名乘客、三条派单、三份对白、演示值班及其专属Profile已删除。
楼层索引书、四个热点、两个书页视口、书本输入锁、三段专属音效与专项测试全部移除。
camera_feeds及其getter/校验、无消费者的旧UI信号/入口、书本字段与楼层排序逻辑同步清理。
三个现用UI适配器保留；右台不再显示静态关联度和稳定度。

通用流程、人物展示、对话适配器等框架继续保留。
测试改用 tests/fixtures/runtime/ 中的无剧情内存数据，测试编号不注册进正式Catalog。
新增 content_reset_tests.gd 直接验证正式三层空舱，通用测试完成后恢复Registry。

## 自动逻辑验证

统一入口运行一次：版本、editor-import、scene-contracts均通过。
existing-tests：1343通过、0失败；43个Warning包含既有降级/无效配置用例。
main-smoke未通过：进程退出码为0，但退出日志含1条未预期ERROR，统一入口正确判为失败。

具体为 ambience.mp3 的 AudioStreamMP3 / AudioStreamPlaybackMP3 退出时未释放。
verbose最小复现定位后，在未修改的F:/the_shaft main也复现同一问题。
因此未修改原有音效、未放宽错误过滤；已停止该根因的变体重试，没有再次循环全量测试。
逻辑测试通过不应写成统一检查全部通过。日志保存在本机系统临时目录，不提交仓库。

统一检查后仅对两个新增测试层的附加文字/侧面占位板做视觉调整，并修改文档/注释，未改变流程逻辑。

## Godot AI视觉与运行时自检

Godot 4.7.2 / Godot AI 4.1.0，唯一会话project_path已核对为本worktree。
正式main_3d运行成功；运行时确认318、SHIFT_IDLE、无活动派单、无乘客、无楼层书，Catalog恰好三层。
通过现有右台验证/行驶入口产生001→002→318真实到站记录，左台显示相应日志。
截图确认318保留原视觉、右台书本消失且屏幕无旧关联评估、左台可显示真实日志；
新测试层侧面占位板移除后，001三位编号完整可见。
早期临时game_eval发生过缩进错误和8秒调用时限，已停止对应运行；最终运行与项目代码无这些错误。
现有音效组件与资源接线保留，未把截图自检当成人工听感验收。

## 人工验收与后续范围

画面、字号、音效、焦点与操作节奏仍待用户在本worktree验收。
第一阶段交付时尚未执行独立废弃美术资源清理；后续第二阶段结果见 [第二阶段交接](content-reset-stage2-review.md)。
Blender/Aseprite源、来源和许可记录继续保留。
main未改动；不push、不merge、不写入GitHub，不删除本worktree或分支。
