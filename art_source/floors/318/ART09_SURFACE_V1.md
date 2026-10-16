# ART-09 Surface V1 候选

本文件只记录 #76 Pass B。Gate 1 已通过；Gate 2 待人工视觉验收，尚未进入 Lighting Pass。

- base：0bf68370b511eb942e8b05baf29ea90028fc371e。
- [PLAN v1](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6215155999)。
- [Gate 1 约束](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6216438049)与[依赖解锁](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6219043778)。
- 用户在当前 Codex 对话明确“人工批准”后执行。
- 分支 dev/76-floor-318-art-direction；正式入口仍为 scenes/main/main_3d.tscn。

## 源、色板与发布边界

从已提交 V3 另存 floor_318_art09_surface_v1.aseprite，541×272、RGB、单帧、八环境层加隐藏 REFERENCE / GUIDES。
原 V3 源、正式 PNG、Profile、receipt、layout manifest 均保持基线，不覆盖历史 V4 或混用其失败版本。

候选 Palette 为 palette_art09_surface_v1.json，art_approved=false，127 个唯一 RGBA：
V3 工作记录的126个唯一色，加上已存在于正式V3像素中、但漏记于工作记录的不透明黑色。
这只是补齐已有颜色盘点，不新增画面颜色。V3工作色板原文件保留，不把它改成“已通过”。

| 文件 | SHA-256 |
| --- | --- |
| 原 V3 native source | 211fe3a0e0594a4cf893a56534d670b3b26a12ac325d6ceab83d6173fa66785f |
| Surface V1 / door-edge R1 native source | 47ce0384fcb53da85f2800eea22d311aca45cad1cb67d4ca6fbb70d107903fa2 |
| 候选 Palette（制作时文件字节） | fde4d676b83281c31f1327230c41ca7fc5d904e5efdd5d924226a08a7a9db6dc |
| 候选 Palette（canonical LF UTF-8） | 339806ca3ff3420acced4d15d15c4895e204a3eff636c5cfcb0749823bc92004 |

新源约4MB，沿用原生 Aseprite 普通Git跟踪；候选PNG、截图、压缩Profile和日志只留既有忽略目录。
没有引入第三方原始纹理、ImageGen新图、LFS规则或新的资产目录约定。

**这是待验收候选预览，不是已发布默认版本。** 正式启动仍读取 V3。
用于复查的候选已保存为 art_source/floors/.preview/issue-76-surface-v1/floor_318_surface_v1.res；
可重载，不依赖未保存的编辑器内存。Gate2批准后才安排正式Palette/发布stage/receipt接入。

## 确定区域与表面操作

作者脚本位于 tools/aseprite/paint_floor_318_surface_art09.lua。

- main：保护门框 / 壁灯 / 门把区域；对已有墙像素的确定邻域做低对比整理，
  保留原材质的成片差异；沿已有板区整理竖缝。编号后方用连续的平滑过渡减弱纹理，没有牌底、烘焙数字或节点移动。
- main 墙顶：以冻结的 y=2.6m 对应原生 y≈103px 增加窄收口；
  只描述墙顶结构边界，不增加灯、几何或整体受光渐变。
- ceiling：更安静的大面与两条稀疏长向施工缝，保持原水平Quad和2.6m高度。
- ground：保留原48px/0.75m砖缝坐标，降低砖面颗粒及缝线对比；不重新画透视线。
- 门内漆面、mid_left柜体漆面、mid_right桶身：只整理既有表面；
  轮廓、门框五金、商品玻璃、开口和边缘保留。
- far 匹配墙体安静度；front_left / front_right 像素保持。
- 不使用随机数、随机矩形、65/25/10面积生成器或整图生成；不重建构图。
- 八层逐像素 alpha_changes=0；尺寸、Marker、Tween、相机、编号、tint、energy和CRT不变。

## 复现制作

要求已配置 ASEPRITE_PATH，版本支持 Lua API41。命令在当前 Issue worktree 根执行。
输出必须是不存在的新路径；脚本拒绝覆盖已有源。以下 request 只生成候选，不调用 BindProfile 或正式发布：

    $palette = Get-Content art_source/floors/318/palette_art09_surface_v1.json -Raw | ConvertFrom-Json
    $layout = Get-Content art_source/floors/floor_slice_layout_v1.json -Raw | ConvertFrom-Json
    $source = Join-Path (Get-Location) 'art_source/floors/318/floor_318_surfaces_v3.aseprite'
    if ((Get-FileHash -LiteralPath $source).Hash -ne '211FE3A0E0594A4CF893A56534D670B3B26A12AC325D6CEAB83D6173FA66785F') { throw 'V3 source mismatch' }
    $directory = Join-Path (Get-Location) 'art_source/floors/.preview/art09-surface-rebuild'
    $null = New-Item -ItemType Directory -Path $directory -Force
    $layers = @($layout.layers | ForEach-Object {
        $rect = $layout.status.final_export_rectangles.($_.id)
        @{id=$_.id;width=$rect[0];height=$rect[1]}
    })
    $request = @{source=$source;output=(Join-Path $directory 'surface.aseprite');report=(Join-Path $directory 'author-report.json');preview_directory=$directory;density=64;pass='surface';palette=$palette;layers=$layers}
    $requestPath = Join-Path $directory 'author-request.json'
    [IO.File]::WriteAllText($requestPath,($request | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    & $env:ASEPRITE_PATH --batch --script-param "request=$requestPath" --script tools/aseprite/paint_floor_318_surface_art09.lua

Windows GUI exe 应等待实际进程退出并检查日志 / report；不能只看旧 LASTEXITCODE。
制作成功标记为 ART09 SURFACE AUTHOR PASS。实际执行 request / stdout / stderr 留在候选目录。

严格导出沿用现有 floor_pipeline.lua 的 Export：
source为新候选源、canvas=[541,272]、palette为上述候选、layers按ID索引固定width/height，
output_directory为忽略目录中的png子目录，preview/report也在该目录。
实际完整 export-request.json 已保留；完成标记 FLOOR_PIPELINE_OK issue76-surface-v1。
它验证固定矩形、精确色板、二值alpha、辅助层排除和精确RGB→Indexed→RGBA的PNG round-trip，
不替代正式发布授权，也不把art_approved改为true。

## Gate 2 证据

本地忽略目录 art_source/floors/.preview/issue-76-surface-v1/：

| 内容 | 文件 |
| --- | --- |
| 双机位基线 / 候选 | before-cam01/02-feed.png、after-cam01/02-feed.png；对应-crt.png |
| main / ceiling / ground 局部 | before-* / after-*-crop-1x.png 与4x.png；4x仅nearest复制源像素 |
| 源与导出制作检查 | author-request.json、author-report.json、export-request.json、export-report.json、相应日志 |
| 可重载候选 | floor_318_surface_v1.res；内嵌八张候选纹理 |
| 运行时比对 / 恢复 | before-runtime.json、after-runtime.json、surface-verification.json、profile-restore-check.json |

原始feed为320×240；CRT为真实主台2560×1440，未拼接或重画实机截图。
before / after均从同一正式main_3d、相同门开启状态和两机位取得。
当前阶段只评估Surface；门关、候梯、登舱和Lighting完整矩阵属于后续Gate3交付。

Aseprite严格导出已通过、源文件未变，八层alpha未变；两前景层保持透明原像素。
运行时比对八层Transform / size / unshaded / nearest / scissor / albedo无差异，
17盏既有灯的Transform / energy / color / visible / cull均相同，CRT、编号、tint与倍率相同。
318候选→004 / 612→318候选，以及fallback123 / reset共享天花板恢复检查通过。

第一次制作被严格色板断言拦下，定位为V3工作记录缺少原有不透明黑；
补齐候选盘点后重试一次通过，没有改正式V3或放宽校验。

Godot AI观察和自动检查不代表人工美术通过。
Gate2需要人工判断墙面是否仍像混凝土、墙顶是否清楚、地面是否过于网格化，以及门柜桶是否协调；
不为通过Gate2提前加入Lighting。

## 本轮统一验证

在候选代码与源冻结后，退出Godot Editor并执行一次：

    powershell.exe -NoProfile -File .\tests\run_all_tests.ps1 -GodotPath "$env:GODOT_BIN"

ALL CHECKS PASS / exit0；1561通过、0失败。
version、editor-import、scene-contracts、existing-tests、main-smoke全部通过。
existing-tests报告43条warning，包含已有destination反馈缺失、非法阶段转换及空/无效Profile等诊断；
没有把warning写成零，也未处理范围外剧情内容。
完整五份日志保存在本地候选目录validation/，不提交Git。

本轮自动验证不等于Gate2人工视觉通过。正式V3绑定与源未被候选替换，未push/merge。

## 门框边缘反馈修正 R1

用户反馈“门的边缘比较粗糙”。仅整理main既有门框周边的84×134像素区域：
外缘碎亮点 / 灰白毛边、窄金属面、内侧暗缝和原门槛边带收成连续线。
main实际修改3065个像素；区域外0变化、alpha0变化。
门板主体及把手逐像素保留，其余七层导出PNG与首次Surface候选逐字节相同。

当前原生源SHA256更新为47ce0384fcb53da85f2800eea22d311aca45cad1cb67d4ca6fbb70d107903fa2；
首次Surface源67bfad5c...保留在提交59d8d5b及本地修改前备份，V3源仍未改。
Palette127色及art_approved=false保持。没有改相机、Quad、灯光、tint或CRT。

补充作者步骤为tools/aseprite/refine_floor_318_door_edge.lua：
先执行本文件原制作命令生成首次Surface源，再给该脚本传入request JSON，
source指向首次Surface源、output为不存在的新.aseprite路径、
report为本地报告路径、palette读取palette_art09_surface_v1.json。
沿用--batch --script-param "request=<request.json>" --script调用；
成功标记ART09 DOOR EDGE PASS，之后仍用既有floor_pipeline.lua严格Export。
脚本拒绝覆盖输入；校验通过后才更新本Issue候选源，原稿由Git及忽略目录备份保留。

证据目录：art_source/floors/.preview/issue-76-door-edge-v1/。
index.md包含门原生1× / nearest3× / 6×与正式CAM01/CAM02的before-after。
当前可重载候选为floor_318_surface_door_r1_final.res，已应用于同一worktree正式main_3d，
Game留在CAM02。正式默认Profile仍为V3；Gate2尚未通过，没有发布或进入Lighting。

本轮Aseprite作者步骤与八层精确RGBA导出均exit0。
运行时八层属性、17盏既有灯、CRT、编号及tint/energy保持；浮点比对容差1e-6，
JSON往返的最大数值差约9.8e-19，没有实际调灯。
纯视觉局部修正未重复Godot全量测试；前述1561/0属于首次Surface统一检查。
当前修正的依据是局部像素约束、严格导出和正式双机位复查，最终边缘观感仍待人工确认。
