# 人工体验、预览与美术工具验证

[返回测试索引](../README.md)

按 [Godot 视觉流程](../../docs/development/godot-ai.md)核对项目和会话。实机预览命令从已导入 worktree 的根目录执行，由用户运行并反馈。相应 headless 检查见[测试索引](../README.md#按改动定位专项)。

## 人工体验验收

在 Godot 4.7 运行正式入口，确认初始318、空舱待机与三个台位。
使用 CAM 02 检查318；输入001、验证、执行，再前往002并返回318，
确认只在实际到站后切换视觉、编号前导零正确、过程中不能开门。
检查门、椅子转向、按钮、滚轮、键盘、验证及拨杆的已有音效；书本及其专属音效应消失。
左台显示中性空态/真实日志，MIC 提示“对话功能暂时停用”，右台不显示旧关联评估。
正式空舱不显示 COMM，也不创建对话适配器；鼠标和手柄均应能操作三台，转向后焦点正常恢复。
对话/UI 源文件保留，无剧情夹具在测试实例中单独启用，不影响正式操作舱的临时停用状态。

Headless 不验证字体可读性、D3D12 画面、音频或节奏；Godot AI 自检和用户人工验收分别记录。
相关素材变更记录见[历史基线](historical-baselines.md#门按钮帽素材)。

## 实机预览

### 三文件陈述拖选原型

在 Godot 中运行 `res://tests/preview/statement_selection_preview.tscn`。
维修申请已打开，当班任务单在「已调阅资料」，维修核验规程在「规程 / 样板」。
在维修申请中拖选「001」后点「加入比对」，槽内会显示「001」和资料出处。
说明文字和跨行片段也可加入。手柄用方向键选择段落，按 A 高亮，松开再按 A 加入。
可点槽位旁的「定位原文」回到出处。自动回归见 [W 终端专项](documents-and-consoles.md#w-呼出终端定向检查)。

### 休息入口与设置页

在独立游戏窗口验证显示预览和 15 秒回退。用实体手柄确认返回路径与按键，检查布局和实际音量。自动覆盖见[休息入口与开发者页](runtime-and-structure.md#休息入口与开发者页)。

### 手动资料预览

```powershell
godot.cmd --path . --scene res://tests/preview/verification_workspace_preview.tscn
```

预览安装仅进程内的无剧情夹具，直接复用正式main_3d与唯一运行层/W组件。
在612接乘层执行真实登舱命令后，身份证明和维修任务表从乘客原子上传进入乘客材料；
楼层档案由预览驱动模拟右台查询完成取得。另有系统规程和样板，未伪装系统乘客档案。
默认打开三窗；F6提交维修任务表v2，旧窗仍可“查看新版”。
关闭旧窗后，从乘客材料打开维修任务表最新版，再展开窗内“历史版本”重开v1；
左右台结果和系统参考也沿同一路径从各自栏目打开最新、在文档内读旧版。
历史入口仅在已取得旧版确实存在时出现，默认折叠；仅首次取得v2不会显示虚构v1。
展开历史滚到列表起点，收折恢复先前正文位置。目录找回原窗时只置顶聚焦，其他资料仍可继续阅读。
「整理窗口」收折目录留出阅读区；“目录”可重新打开。正式默认入口和Catalog仍是空舱。
F6仅为预览脚本输入，不新增正式 InputMap 或自动剧情。审查与证据托盘的操作见 [W 审查预览](#w-审查预览)。
小屏局部补偿字号，四窗可见行数较少，须独立滚动；最终阅读密度与手柄体验待用户验收。

### 左台乘客档案预览

```powershell
godot.cmd --path . --scene res://tests/preview/left_lookup_preview.tscn
```

预览中按 Q 转到左台，按「乘客档案」查询 P-017，连续按键切换三份文档。滚轮只滚动当前正文。
按「调阅」直接打开 W 中这一份。收起 W、切换到另一份再调阅，可保留两窗并自动并排。
W 的规程/样板和已调阅资料中另有夹具参考及右台来源档案，左台文档须由玩家调阅。
F6 更新维修任务表，从系统日志重新进入档案可查看新版。F7 切换到无工作记录乘客。
正式默认入口仍为空舱。实机可读性、铭牌和手柄体验单独验收。

### W 审查预览

```powershell
godot.cmd --path . --scene res://tests/preview/document_review_preview.tscn
```

在预览中按 W 打开「维修核验规程」，将条款「加入比对」，保留另一项为空，再点「提出质疑」。收件箱可查看工作许可补件，收起 W 后从主监视器读取回应。
也可依次点击「维修申请」和「当班任务单」目的楼层字段旁的「加入比对」，再点「提出质疑」。收起 W 查看乘客回应。

### 主台通话摘录预览

```powershell
godot.cmd --path . --scene res://tests/preview/call_excerpt_preview.tscn
```

面向主台，等监视器显示陈述末页后按麦克风底座的浅灰方块，再按 W 从「陈述摘录」打开乘客原文。复按只提示已取得，未完整呈现的陈述不可摘录。正式入口保持空舱，按「摘录」显示无派单。

### 右台楼层档案预览

```powershell
godot.cmd --path . --scene res://tests/preview/right_lookup_preview.tscn
```

转向右台，用实体数字键输入 001，再按「调阅档案」打开 W。F6 更新 001 的来源版本，
收起 W 后再次按调阅键先刷新摘要，再按一次取得新版。005 为不支持静态停靠的测试层。正式空舱无需预览夹具。

### 运输改送预览

可复用[右台楼层档案预览](#右台楼层档案预览)。用右台拨杆到 612 接乘，回主台 OPEN，等乘客登舱后 CLOSE。再用右台去 900，到站后保持门关闭，拨杆改去 742。最终到站后在主台 OPEN，等乘客离舱，再 CLOSE 结单。

## 318 美术工具验证

以下命令用于独立美术制作流程。原空舱内容重置验收未要求运行本节命令。

### #75 Pass A/B 只读布局检查

此步骤只读布局与清单。

```powershell
godot.cmd --headless --path . --script res://tools/aseprite/validate_floor_profile.gd -- --check-layout
```

成功要求退出码 0 和 `LAYOUT CHECKS PASS`。它实例化正式 main_3d，对照
`art_source/floors/floor_slice_layout_v1.json` 检查七个 Quad、完整 Transform、
320×240 机位参数、固定遮挡、Marker、共享编号字号/描边/颜色/贴墙位置和规范化 LF 源文件 hash。
`--print-layout` 可附加输出当前几何 JSON；命令始终只读正式源和清单。
mask 来自 B 的实机校对与固定 Box 射线计算，命令不把几何一致性冒充截图验收。
几何门只读冻结清单；318 正式美术以 ART09 Darker R3 Profile 与 receipt 为准。

### #75 Pass C CLI 与导入校验

CLI 需要本地 Aseprite 1.3.x，运行前先设置 `ASEPRITE_PATH`。Profile 校验需要已导入的 Godot 项目。

```powershell
powershell.exe -NoProfile -File .\tests\tools\aseprite_pipeline_tests.ps1 -AsepritePath "$env:ASEPRITE_PATH"
godot.cmd --headless --path . --script res://tools/aseprite/validate_floor_profile.gd -- --check-profile --density=64
```

检查 CLI 和 Profile 命令均返回退出码 0，分别出现 `ASEPRITE PIPELINE TESTS PASS` 和 `FLOOR PROFILE CHECKS PASS`。

CLI fixture 覆盖正式隐藏层违规、辅助层/参考层排除、RGB 精确 palette、
二值 alpha、固定空层、重复七图 hash/source 不变、新参考副本及拒绝覆盖、
部分发布失败回滚、未知输出与越界路径、未批准正式导出门。
Profile 检查实际七图导入尺寸/像素与 receipt、材质 Scissor 0.5、白色 × tint 和冻结几何。
运行时测试另验证 null/reset 恢复原透明模式、threshold 与 material_override。
CLI 的通过范围限于本节工具验证。工程收尾和人工体验按[测试索引](../README.md#何时运行)执行。
318 正式源与测试 fixture 的色板不同；正式输入使用显式 Source/PaletteFile，禁止以诊断输入误覆盖正式美术。
完整命令和失败恢复见 [管线文档](../../docs/development/aseprite-floor-pipeline.md)。
