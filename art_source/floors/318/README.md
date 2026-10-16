# 318 住宅走廊美术 V2

## 当前状态：provisional / placeholder-quality

2026-10-16：最新V4材质pass人工视觉验收失败，已撤回至紧邻前版V3混凝土候选。
最终318及天花材质未完成，整体灯光与表面美术方向延期到独立Issue。
#75的数据、Profile、七层几何、64 px/m与CLI导出工程保留；旧V2资料如下仅是历史制作记录，
其Palette/管线获批不等于最终美术验收。详见同目录VISUAL_STATUS.json。


用户在 2026-10-14 批准已展示的构图参考、64 px/m 与 20 色 Palette。
[批准记录与实施范围](https://github.com/zuozheshen/the_shaft/issues/75#issuecomment-6167315204)。
最终画面与体验仍需用户验收。

V1源floor_318_residential_v1.aseprite、palette_residential_v1.json、reference/floor_318_concept_v1.png及paint_floor_318.lua保留供历史比较。V1源SHA256仍为ffb652c9b9bca087220f02f5d8a85f640b192e2772fead76f4106ddb87d8e66b；当前正式manifest/七图已指向V2。

## 源与参考

- 正式 RGB 单帧九层源：`floor_318_residential_v2.aseprite`，541×272，
  2,287,148 bytes，普通 Git 跟踪。
- 原结构测试源 `floor_318.aseprite` 保留，15,258 bytes，hash不变；
  `pipeline_test_palette.json` 继续仅用于技术 fixture。
- 正式 Palette：`palette_residential_v2.json`，floor-318-residential-v2，
  透明黑+19不透明色，alpha仅0/255。
- 概念参考：`reference/floor_318_concept_v2.png`，1,776,501 bytes，沿用 PNG LFS。
  由内置imagegen精确编辑已展示的V2候选图，删除右门并灰化混凝土；只作构图/材质参考；
  另以完整高色图嵌入原生 REFERENCE 层。正式像素没有采样或缩小该图。
- 原用户图仅留本地证据，SHA256：
  `a2cb773353e2e5e3e80208783de9025fc57168140fd55156826a0f2da0479daf`。
- 正式源 SHA256：
  `97b7005c2766eda3fb3e4bde7e0bc96044abab8ae184d85d322cdfd82689335a`。

REFERENCE / GUIDES 隐藏并锁定，永不导出。七个正式层仍是
far / main / mid_left / mid_right / ground / front_left / front_right。
`tools/aseprite/paint_floor_318_v2.lua` 从结构源复制，在原生像素坐标中按批准参考重绘；
使用明确色板索引、矩形/扫描线轮廓与可控像素簇，不使用抗锯齿、近似量化或AI缩图。
V2按获批单门灰混凝土参考重绘：不使用随机斑点/掉漆，保留大块灰阶和少量接缝；原图细颗粒不进入正式像素。完整ImageGen提示词见reference/floor_318_concept_v2_prompt.txt。

## 七层职责

| 层 | 原生尺寸 | 内容 |
| --- | --- | --- |
| far | 541×266 | 连续不透明灰混凝土、单左门内凹边兜底 |
| main | 532×272 | 灰色裸混凝土墙/梁、单左门、公共照明；无编号牌面 |
| mid_left | 164×230 | 灰黑售货机、暗玻璃与小面积低饱和产品 |
| mid_right | 169×233 | 普通金属垃圾桶 |
| ground | 541×240 | 连续不透明单一灰色，无拼缝/地垫/反光块 |
| front_left | 42×154 | 近门左收边，真实透明轮廓 |
| front_right | 45×160 | 近门右收边，真实透明轮廓 |

适配原七个平面及两个机位，未把参考图透视复制进整个纹理。
共享楼层号继续动态显示：318/004等保留原编号与前导零，空值---；无FLOOR前缀/牌面/粗描边，深灰字Y=2.16、Z=-3.095，主墙Z=-3.10，字号64/.005。等待态实机确认乘客挡住数字下沿后，公共编号上移0.11m；附注能力保留，所有楼层共用节点与排版。摄像机、Quad、Marker、灯光和业务不变。

## 正式导出

配置 ASEPRITE_PATH / GODOT_BIN，关闭当前 worktree Editor 后运行：

```powershell
powershell.exe -NoProfile -File .\tools\aseprite\floor_pipeline.ps1 -Action Export -Source art_source/floors/318/floor_318_residential_v2.aseprite -PaletteFile art_source/floors/318/palette_residential_v2.json -PixelDensity 64 -BindProfile -VerifyGodot -AsepritePath "$env:ASEPRITE_PATH" -GodotPath "$env:GODOT_BIN"
```

正式输入不用 Diagnostic。receipt 标为 residential_art_v2；
已发布正式美术拒绝被 Diagnostic 输入覆盖。
Export只读源、检查SHA、严格Palette后发布七图，不覆盖可编辑源。
修改/重绘应另存新源后比较，不覆盖唯一版本。

## 原生重构重现

作者脚本使用 request JSON。以下示例只生成新的忽略目录源；
正式绑定须单独通过上方管线：

```powershell
$assetRoot = (Get-Location).Path
$null = New-Item -ItemType Directory -Path art_source/floors/.staging -Force
$layout = Get-Content art_source/floors/floor_slice_layout_v1.json -Raw -Encoding UTF8 | ConvertFrom-Json
$palette = Get-Content art_source/floors/318/palette_residential_v2.json -Raw -Encoding UTF8 | ConvertFrom-Json
$layers = @($layout.layers | ForEach-Object {
  @{id=$_.id;size=$_.quad_size_m;origin=$_.local_transform.origin;width=$layout.status.final_export_rectangles.($_.id)[0];height=$layout.status.final_export_rectangles.($_.id)[1]}
})
$request = @{template=(Join-Path $assetRoot 'art_source/floors/318/floor_318.aseprite');reference=(Join-Path $assetRoot 'art_source/floors/318/reference/floor_318_concept_v2.png');output=(Join-Path $assetRoot 'art_source/floors/.staging/residential-v2-rebuild.aseprite');report=(Join-Path $assetRoot 'art_source/floors/.staging/residential-v2-rebuild.json');density=64;palette=$palette;layers=$layers}
[IO.File]::WriteAllText((Join-Path $assetRoot 'art_source/floors/.staging/residential-v2-rebuild-request.json'),($request | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
& $env:ASEPRITE_PATH --batch --script-param "request=art_source/floors/.staging/residential-v2-rebuild-request.json" --script tools/aseprite/paint_floor_318_v2.lua
```

Lua JSON 输入须 UTF-8无BOM；Windows PowerShell5.1的 Set-Content UTF8带BOM，
可改用 `[IO.File]::WriteAllText(path,json,[Text.UTF8Encoding]::new($false))`。
GUI exe完成前不要仅凭旧 LASTEXITCODE 判断；实际进程应等待完成，核对 exit与 RESIDENTIAL V2 PAINT PASS。
原生100%与2×/4× nearest轮廓、真实main_3d/CRT双机位和乘客动作分别验证。
完整发布、恢复、导入与测试规则见 [管线文档](../../../docs/development/aseprite-floor-pipeline.md)。
