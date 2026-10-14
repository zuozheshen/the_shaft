# 318 住宅走廊美术 V1

用户在 2026-10-14 批准已展示的构图参考、64 px/m 与 26 色 Palette。
[批准记录与实施范围](https://github.com/zuozheshen/the_shaft/issues/75#issuecomment-6165722805)。
最终画面与体验仍需用户验收。

## 源与参考

- 正式 RGB 单帧九层源：`floor_318_residential_v1.aseprite`，541×272，
  2,297,365 bytes，普通 Git 跟踪。
- 原结构测试源 `floor_318.aseprite` 保留，15,258 bytes，hash不变；
  `pipeline_test_palette.json` 继续仅用于技术 fixture。
- 正式 Palette：`palette_residential_v1.json`，floor-318-residential-v1，
  透明黑+25不透明色，alpha仅0/255。
- 概念参考：`reference/floor_318_concept_v1.png`，1,609,118 bytes，沿用 PNG LFS。
  由 imagegen 根据用户住宅走廊参考生成，只作构图/材质参考；
  另以完整高色图嵌入原生 REFERENCE 层。正式像素没有采样或缩小该图。
- 原用户图仅留本地证据，SHA256：
  `a2cb773353e2e5e3e80208783de9025fc57168140fd55156826a0f2da0479daf`。
- 正式源 SHA256：
  `ffb652c9b9bca087220f02f5d8a85f640b192e2772fead76f4106ddb87d8e66b`。

REFERENCE / GUIDES 隐藏并锁定，永不导出。七个正式层仍是
far / main / mid_left / mid_right / ground / front_left / front_right。
`tools/aseprite/paint_floor_318.lua` 从结构源复制，在原生像素坐标中按批准参考重绘；
使用明确色板索引、矩形/扫描线轮廓与可控像素簇，不使用抗锯齿、近似量化或AI缩图。
首轮实机发现反光条纹与碎点偏多，已合并为较宽低对比反光，减少墙/门碎点并整理植物叶片。

## 七层职责

| 层 | 原生尺寸 | 内容 |
| --- | --- | --- |
| far | 541×266 | 连续不透明后墙/住户门内凹边的兜底 |
| main | 532×272 | 灰绿墙裙、混凝土、双住户门、公共照明与空白共享编号承载 |
| mid_left | 164×230 | 公告栏、扶手、小型垃圾桶与垃圾袋 |
| mid_right | 169×233 | 管道、少量盆栽和包裹 |
| ground | 541×240 | 连续不透明方砖、低对比光斑与住户地垫 |
| front_left | 42×154 | 近门左收边，真实透明轮廓 |
| front_right | 45×160 | 近门右收边，真实透明轮廓 |

适配原七个平面及两个机位，未把参考图透视复制进整个纹理。
共享楼层号继续动态显示，图中牌面空白；摄像机、Quad、Marker、灯光和业务不变。

## 正式导出

配置 ASEPRITE_PATH / GODOT_BIN，关闭当前 worktree Editor 后运行：

```powershell
powershell.exe -NoProfile -File .\tools\aseprite\floor_pipeline.ps1 -Action Export -Source art_source/floors/318/floor_318_residential_v1.aseprite -PaletteFile art_source/floors/318/palette_residential_v1.json -PixelDensity 64 -BindProfile -VerifyGodot -AsepritePath "$env:ASEPRITE_PATH" -GodotPath "$env:GODOT_BIN"
```

正式输入不用 Diagnostic。receipt 标为 residential_art_v1；
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
$palette = Get-Content art_source/floors/318/palette_residential_v1.json -Raw -Encoding UTF8 | ConvertFrom-Json
$layers = @($layout.layers | ForEach-Object {
  @{id=$_.id;size=$_.quad_size_m;origin=$_.local_transform.origin;width=$layout.status.final_export_rectangles.($_.id)[0];height=$layout.status.final_export_rectangles.($_.id)[1]}
})
$request = @{template=(Join-Path $assetRoot 'art_source/floors/318/floor_318.aseprite');reference=(Join-Path $assetRoot 'art_source/floors/318/reference/floor_318_concept_v1.png');output=(Join-Path $assetRoot 'art_source/floors/.staging/residential-rebuild.aseprite');report=(Join-Path $assetRoot 'art_source/floors/.staging/residential-rebuild.json');density=64;palette=$palette;layers=$layers}
[IO.File]::WriteAllText((Join-Path $assetRoot 'art_source/floors/.staging/residential-rebuild-request.json'),($request | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
& $env:ASEPRITE_PATH --batch --script-param "request=art_source/floors/.staging/residential-rebuild-request.json" --script tools/aseprite/paint_floor_318.lua
```

Lua JSON 输入须 UTF-8无BOM；Windows PowerShell5.1的 Set-Content UTF8带BOM，
可改用 `[IO.File]::WriteAllText(path,json,[Text.UTF8Encoding]::new($false))`。
GUI exe完成前不要仅凭旧 LASTEXITCODE 判断；实际进程应等待完成，核对 exit与 RESIDENTIAL PAINT PASS。
原生100%与2×/4× nearest轮廓、真实main_3d/CRT双机位和乘客动作分别验证。
完整发布、恢复、导入与测试规则见 [管线文档](../../../docs/development/aseprite-floor-pipeline.md)。
