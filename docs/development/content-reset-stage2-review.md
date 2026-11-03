# 内容重置第二阶段交接

- 基线：第一阶段提交1539b78ebbff972682c10d97baf4ae8583f737b7。
- 用户明确要求“继续第二阶段”；沿用codex/content-reset及F:/the_shaft_worktrees/content-reset。
- 本阶段只清理独立废弃资源，不更改玩法、公共API、正式场景内容、框架或测试逻辑。

## 删除范围与证据

共删除36项资源及35个导入/UID文件，共71个文件、177697401字节（169.47 MiB）。
这是工作树资源体积；未改写Git历史，历史中的二进制对象不会因此消失。
逐文件路径、原始字节数、删除前SHA-256及分类见 [文件清单](content-reset-stage2-files.json)。

| 范围 | 资源数 | 删除依据 |
| --- | ---: | --- |
| assets/art/metal_plate_02_4k/ | 24 | 无运行时、工具、源文件或许可记录依赖；组内import引用随组删除 |
| assets/art/根目录独立图像 | 9 | ExportedLayers、Metal063 roughness、mountain、testpic、metal_3868、三张thumb及金属划痕均无消费者 |
| scenes/elevator/screen.gdshader | 1 | 路径、文件名及UID均无项目消费者；正式屏幕使用main_console_crt |
| scenes/visuals/cabin_wall_assembly_visual.tscn | 1 | 没有实例化或加载链；其生成器输入及源资源另行保留 |
| assets/audio/sfx/cabin/elevator_running_placeholder.wav | 1 | 正式运行音效已另有资源与接线，无消费者 |

审计覆盖非插件跟踪文本中的完整路径、文件名、UID，以及加载/目录枚举调用。
15个GLB解析其JSON图片/缓冲URI，均无外部文件依赖。
4个Blender源以Blender后台只读打开，禁用嵌入脚本，检查images、libraries及其他外部路径，
无待删项；10个Aseprite源额外检查候选名称，没有发现外链记录。
原始审计JSON、临时脚本及日志保留在项目外，不纳入仓库。

## 保留的依赖

四份Blender源、全部Aseprite源/色板/receipt、重建脚本及来源许可记录保留。
elevator_cabin_v1、elevator_cabin_assembly_v2中的部分材质/贴图/网格虽不在正式渲染链，
仍作为现有生成器的输入、模板或有来源记录的输出保留；不顺带废弃重建管线。
main_console的门按钮材质与control贴图也属于现有材质生成器及Blender源依赖，不按运行时引用单独删除。
scenes/ui的三个业务适配器、DialogueManager、监控摄影棚、通用人物/派单/值班框架及两个插件保留。

只读检查另发现main_console_v2.blend保存有历史issue-67 worktree的绝对纹理路径。
这是源文件既有可移植性问题；相关纹理全部保留，本阶段没有改写或保存blend。

## 验证

- 最终headless editor-import：exit 0，无ERROR；清单采用JSON，未保留临时CSV生成的翻译资源。
- Godot ResourceLoader从正式main_3d及Autoload递归读取的146项静态资源依赖，删除前后路径、依赖边与全部源文件SHA-256完全一致，missing=0。
- 删除71文件后，保留脚本、场景、资源、工具和import中均无这些资源路径或UID的消费者。
- 统一入口`-Check Contracts`：PASS，exit 0，无Warning/ERROR。
- 统一入口`-Check Existing`：1343条断言通过、0条失败；但退出时22个ObjectDB对象、13项资源未释放，出现1条未预期ERROR。入口正确返回失败，不能记为整轮通过。
- 针对该新退出诊断，仅追加一次同测试宿主的verbose运行：1343条断言通过、0条失败、Godot exit 0，未复现退出泄漏或ERROR。间歇性根因尚未定位，未认定与第一阶段MP3问题相同，未修改清理范围外的逻辑或放宽错误过滤。
- 第一阶段已定位、且原main同样存在的ambience.mp3真实入口退出泄漏仍未修复；遵守已有Circuit Breaker，本轮不重复`All`/main-smoke。因此本分支仍无“统一检查全部通过”的结论。
- `git diff --check`通过；79项引擎重写的import换行已逐项验证无语义差异并恢复。插件、缓存、临时脚本、截图及日志均不纳入提交。

本机日志：系统TEMP下shaft-stage2-import-final.log、shaft-stage2-contracts.log、
shaft-stage2-existing.log、shaft-stage2-existing-verbose.log。
结构检查日志目录为the-shaft-checks-edffb38648f1466ba8e00dfdeb86b39d；
首次行为检查日志目录为the-shaft-checks-ad0d99f766bf4a369595335c43641997。

## 交付边界

不push、不merge、不修改GitHub；主工作区main保持不变。
本阶段没有编辑正式场景、模型、材质、摄像头或界面布局，不重新声称Godot AI视觉/人工验收。
第一阶段记录的画面、音效与手感仍待用户最终体验验收。
