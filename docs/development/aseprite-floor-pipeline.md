# Aseprite 楼层切片管线 V1

## 2026-10-16 收尾：工程保留，美术占位

最新V4材质pass因用户人工视觉验收失败而回滚，当前318美术明确为
provisional / placeholder-quality。恢复V4前的V3混凝土候选，不继续材质迭代或灯光。
共用天花板结构保留，最终顶面材质不属于本Issue完成条件。详见
art_source/floors/318/VISUAL_STATUS.json。下文工程导出规则和历史验收继续有效；
技术Palette获批、PNG验证通过不代表最终美术验收。

本次针对性收尾检查补正两处共享天花板后的兼容记录：入口层数按当前支持ID数量判断，
receipt清单hash按既定canonical LF计算。没有改layout manifest、原七图或Profile字节，
也没有放宽Palette、透明或导入检查。七PNG重新导出及只读Profile/layout检查通过。


## 2026-10-16：共享天花板扩展（已批准实现，未运行自动测试）

[本轮直接批准与范围](https://github.com/zuozheshen/the_shaft/issues/75#issuecomment-6207572871)。
共用切片现在为原七层加 ceiling，合计八个环境平面。原七层职责与尺寸不变；
天花板为 8.45×3.75m 的水平 Quad，中心 (0,2.6,-1.825)，64 px/m 时 541×240。
每个 FloorVisualProfile 均继承 ceiling_visible=true；ceiling_texture=null 时恢复
场景自带的共享混凝土顶面，不沿用上一楼层覆盖。可按楼层替换或隐藏，不复制业务数据。

- 新 CreateTemplate 生成八个环境层＋REFERENCE/GUIDES，合计十层；导出八 PNG。
- 历史九层 V1/V2 源保持原样，读取/参考副本/导出仍接受七环境层；导出七 PNG，
  天花板由共用场景兜底。不得把共享顶面冒充为历史20色色板或旧源中的像素。
- shared/ceiling_concrete_v1.aseprite 是独立顶面源；共享 PNG 为 lossless RGBA、
  nearest、无 mipmaps，色板独立于旧318 Palette。
- 下文的九层/七图命令仍针对保留的 V1/V2 源。新模板按十层/八图执行，
  仍须满足各自获批 Palette 和实际像素门，未放宽发布检查。
- 318三材质新版源、八图、生成原图/完整提示词、两机位截图保留于本地忽略目录
  art_source/floors/.preview/318-material-ceiling-v3。当前仅在正式main_3d中运行时预览；
  正式V2七图、源和Palette未替换。旧receipt只迁移几何清单hash并记录未重新验证。
- 本轮依用户要求不运行CLI fixtures、layout/profile checker、测试套件或统一入口。
  已查看正式场景与两机位画面；最终美术验收仍由用户决定。
- 原有效像素遮罩是新增天花板前的历史记录，本轮未重算，不宣称仍是当前遮罩。


#75 的 C1/C2 采用 Codex → 本地 Aseprite CLI / Lua，不增加 MCP Adapter。
318当前住宅美术V2使用获批64 px/m与20色；正式源为floor_318_residential_v2.aseprite，原结构源与V1保留。
依据 [Pass C REVIEW](https://github.com/zuozheshen/the_shaft/issues/75#issuecomment-6139421496)
C1/C2与三档对比后已按停止点回报；后续用户授权见 [C4记录](https://github.com/zuozheshen/the_shaft/issues/75#issuecomment-6165722805)。V2授权见[V2记录](https://github.com/zuozheshen/the_shaft/issues/75#issuecomment-6167315204)。最终画面验收仍独立进行。

## 输入与边界

- 几何真相：`art_source/floors/floor_slice_layout_v1.json` 的七个 Quad 与完整 Transform；
  先验证 Pass B 的场景/脚本 LF hash。不得为了贴图改摄像机或七层世界尺寸。V2获批更新共享Label的墙面风格，参数与源hash已同步清单。
- 正式主源：`art_source/floors/318/floor_318_residential_v2.aseprite`；`floor_318.aseprite` 保留为结构 fixture。各源均 RGB、单帧，九个唯一顶层图像层。
  七个正式层为 far、main、mid_left、mid_right、ground、front_left、front_right；
  REFERENCE 必须是原生 reference layer；GUIDES 只作辅助。
- REFERENCE / GUIDES 永不参与 Validate 的正式像素扫描或 Export，哪怕可见；
  隐藏的正式层仍完整扫描和导出。组、tilemap、背景层、重复/缺失名称均拒绝。
- 正式层 opacity=255、Normal blend。alpha 只能为 0/255，透明像素为 RGBA(0,0,0,0)。
  非透明像素精确属于指定 palette，包括隐藏层。far、ground 必须连续不透明。
- 从 RGB 精确映射到 palette 索引，再恢复 RGBA，逐像素校验 PNG；
  违规立即失败，禁止近似量化、trim、scale、padding、旋转或自动改变 source。
- 每层矩形从 (0,0) 起，宽高为 ceil(Quad 米数 × 候选 D)；共享画布取最大宽高。
  地面图片顶端指向深处 -Z，底端指向门口 +Z。空的 mid/front 仍导出固定大小透明图。
- `pipeline_test_palette.json` 只有九个技术校验色，`art_approved=false`。
  48/80 保留为忽略目录中的历史候选比较。正式 Palette 为 palette_residential_v2.json；清单已冻结64/20色/固定矩形，export_ready=true。

## 命令

要求 Aseprite 1.3.x / Lua API 41 及 Godot 4.7.x。PowerShell 5.1、7 均可。
可通过参数、ASEPRITE_PATH / GODOT_BIN 或 PATH 指定程序；不在仓库硬编码个人安装路径。
先关闭当前 worktree 的 Godot Editor，避免与批量 importer 竞争。

在仓库根目录，一条命令导出七 PNG、更新已有 318 Profile、导入并检查实际 Godot 像素：

```powershell
powershell.exe -NoProfile -File .\tools\aseprite\floor_pipeline.ps1 -Action Export -Source art_source/floors/318/floor_318_residential_v2.aseprite -PaletteFile art_source/floors/318/palette_residential_v2.json -PixelDensity 64 -BindProfile -VerifyGodot -AsepritePath "$env:ASEPRITE_PATH" -GodotPath "$env:GODOT_BIN"
```

成功需要 Aseprite nonce 完成标记、exit 0、七图校验和 `FLOOR PROFILE CHECKS PASS`，
最后输出 `FLOOR PIPELINE PASS`、七图尺寸/hash 及本次 report 路径。
日志中的 ERROR、缺完成标记或超时都算失败。Godot 首次扫描只精确允许 project.godot 配置的入口 UID 初始化诊断一次，且必须与正式 main_3d 源 UID 一致；随后 checker 验证 ResourceUID 解析路径，其他错误不放行。

原9色模板操作显式使用 `-Diagnostic`；正式20色源应指定 Source/PaletteFile并通过正式门：

| Action | 行为 |
| --- | --- |
| Inspect | 读取保存的源，报告真实层、画布、palette；不保存源 |
| Validate | 严格校验九层和正式像素；不发布 PNG |
| CreateTemplate | 仅在不存在的新 Source 路径创建结构模板；已有源一律拒绝覆盖 |
| PrepareReferenceCopy | 将 Reference 导入原生 REFERENCE，保存到新的 Destination；原源不变 |
| Export | 先暂存七图，验证后发布；可选 BindProfile / VerifyGodot |

参考副本示例：

```powershell
powershell.exe -NoProfile -File .\tools\aseprite\floor_pipeline.ps1 -Action PrepareReferenceCopy -Diagnostic -Reference art_source/floors/318/reference.png -Destination art_source/floors/318/reference_copy.aseprite -AsepritePath "$env:ASEPRITE_PATH"
```

Source 必须位于该楼层源目录或 .staging；Destination 必须是新的 .aseprite。
候选 PNG 可通过 `-OutputDirectory art_source/floors/.staging/compare48` 导出，
但不能同时绑定正式 Profile。候选源应在相同世界坐标重新栅格化，不能缩放另一档 PNG。
CreateTemplate 用于本 Issue 的极简测试矩形，不能生成或替代住宅走廊最终设计。

## 发布、恢复与 Git

源文件只读取磁盘保存版本，batch 前后检查二进制 SHA-256；
不读取或推断 Aseprite GUI 未保存修改，运行前应由操作者保存或提供副本。
仅新模板和新参考副本可保存；既有 source 从不 Save / Save As。

每个 floor 有独占锁；每次运行有独立 request、日志、七图暂存、备份与恢复 journal。
只允许管理已有 receipt 且 PNG hash 未改的输出；未知或手动修改的图拒绝覆盖。正式美术输出还拒绝 Diagnostic 输入误覆盖。
绑定只修改现有 318 FloorVisualProfile 的七个纹理字段与依赖声明，保留 tint、显隐和其他字段；
receipt 的 Profile hash 不符时拒绝覆盖。

单文件以同目录临时文件原子替换，替换前检查原 hash。多文件发布不是一个整体原子事务：
失败时按 journal 恢复已发布且仍匹配本次新 hash 的文件，保留来源不明的并发修改并报告。
受控 Godot importer 允许补 UID/path/default 元数据，但必须保留 source_file 与六项像素设置，
随后记录 .import 新 hash，保证验证失败能恢复准确字节。
进程强制终止/机器断电可能留下部分发布；应停下，按保留的 journal 和 backup 人工核对恢复，
不要删除 recovery 证据或盲目重跑。

住宅美术原生重构、来源/大小与重现命令见 [318源说明](../../art_source/floors/318/README.md)。

PNG 固定 lossless、mipmap=false、size_limit=0、fix_alpha_border=false、
premult_alpha=false、detect_3d/compress_to=0。Godot 检查实际 Texture2D、导入后像素、
七层绑定、palette、二值 alpha、receipt hash 和白色 × Profile tint / Scissor 0.5 / Nearest / Unshaded。
空纹理恢复原透明模式、threshold 与灰盒基色；reset 恢复原 material_override。

源 .aseprite 为小型可编辑资产，普通 Git 跟踪；PNG 沿用仓库已有 LFS。
.godot、.staging、.preview、.backup、截图、日志及临时导出不提交。
不修改全局配置，不自动下载 Aseprite、不 push / merge。正式Palette可指定asset_stage=residential_art_v1/v2，未指定时兼容v1；Diagnostic始终structural_test_only。

## 验证与视觉交接

真实 CLI fixture 测试：

```powershell
powershell.exe -NoProfile -File .\tests\tools\aseprite_pipeline_tests.ps1 -AsepritePath "$env:ASEPRITE_PATH"
```

覆盖重复七图 hash/source 不变、隐藏违规像素、参考高色/可见辅助层排除、
空层固定导出、非法结构/alpha/范围、参考副本拒绝覆盖、失败回滚、未知输出/越界路径及未批准正式门。
这组测试依赖本地 Aseprite，不自动加入 Godot 统一入口。
正式资源或运行时改动仍按 `tests/README.md` 运行统一入口。

C2/C3 必须在正式 main_3d 的实际 320×240 监控视口和 CRT 完成，保留两机位原图：
透明孔由 far 兜底、地面连续、Scissor 无黑/白边或明显轮廓缺失、
318→旧 Profile→三位数 fallback→318 恢复、乘客等待/进出与门的正常深度关系。
48/80 诊断可用原始 PNG 生成运行时 ImageTexture；正式 64 绑定必须另外通过 ResourceLoader 导入验证。
这些是工具自检；用户最终画面、像素颗粒和美术验收仍独立记录。

API 依据：[Sprite](https://www.aseprite.org/api/sprite)、
[Image](https://www.aseprite.org/api/image)、
[Palette](https://www.aseprite.org/api/palette)、
[Layer](https://www.aseprite.org/api/layer)、
[NewLayer](https://www.aseprite.org/api/command/NewLayer)；
Godot 的 3D 自动压缩枚举依据
[原生 Texture importer](https://github.com/godotengine/godot/blob/master/editor/import/resource_importer_texture.cpp)。
