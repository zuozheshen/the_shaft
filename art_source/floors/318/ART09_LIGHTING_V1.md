# ART-09 Lighting V1 候选

Issue #76 Pass C，Gate 2 已人工通过；Gate 3 Lighting 待人工验收。

## 审批、基线与资产

- 用户在当前 Codex 对话回复“批准继续”，对应 [Gate 2 记录](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6229976280)。
- 方向沿用 [PLAN v1](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6215155999)及[Gate 1 冻结约束](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6216438049)。
- repo base：0bf68370b511eb942e8b05baf29ea90028fc371e；本轮起点：4b488a48dd01180672e5b28e52890adeecc7660e。
- worktree：F:/the_shaft_worktrees/issue-76-floor-318-art-direction，分支 dev/76-floor-318-art-direction。

| 资产 | SHA256 |
| --- | --- |
| 已批准 Surface 原生源，保持不变 | efc5e04e5c9330e5afe5648a32b16213f0ecd4e4470f8e32a20a187ea670e33f |
| 新 floor_318_art09_lighting_v1.aseprite | b3c0f830a643a10cd0bc7a8376e22237ee2c901f564666a6804830dbe44f66ff |
| Lighting Palette，canonical LF UTF-8 | cbb818a8adebdd851d63c4334b1f6ec9fbaf0f64f890512bf06c886b52190b36 |
| Surface Palette，批准元数据更新后 canonical LF UTF-8 | fe6ac53cc6cc9fc526e669fcf23625d53e8687087c0f8c2b6b7475ab6e77d983 |

新原生源仍为541×272、RGB、单帧、八环境层及隐藏REFERENCE/GUIDES，沿用现有普通Git跟踪。
Lighting Palette 的127项RGBA与批准的Surface逐项相同，art_approved=false。
Surface Palette仅更新人工批准元数据为true；颜色不变。旧false元数据留在本地审批前快照及Git历史。
原V3源、正式PNG、Profile、receipt、layout manifest及共享默认天花未改。

## Bake 为主的 Hybrid

固定光影由 tools/aseprite/light_floor_318_art09.lua 在 Aseprite 中完成。
Godot八平面继续Unshaded、nearest、Alpha Scissor 0.5；tint保持白色、energy倍率1。
没有新增shader、Light3D、几何、道具、整体曝光或CRT参数。

| 部位 | 确定的基础明暗 |
| --- | --- |
| main / far | 顶部宽缓受光向下衰减，左右大面略沉，墙脚轻微压暗；保留纹理组织与编号缓冲区 |
| 既有住户门 | 门板随高度轻微衰减，已有内侧窄缝略沉；门框边界、把手与图中门位置不动 |
| ceiling | 在原水平平面按世界X/Z形成低频明暗，墙顶交界略沉；不新增灯具或施工缝 |
| ground | 在原水平平面按世界X/Z计算宽受光，墙脚、售货柜和桶脚接触处略沉；原砖缝与投影不动 |
| 售货柜 / 桶 | 既有上缘略亮、右侧略沉、下部较稳；商品/付款模块、壁灯发光面和门把逐像素保留 |

不使用随机数、抖动或整图重绘。颜色只映射回既有127色，不扩色或引入第三方输入。
六层实际改像素：far103630、main100740、mid_left1828、mid_right1077、ground107292、ceiling104578。
八层alpha_changes均为0；front_left / front_right像素保持。
ceiling实际输出7色，Surface为2色；低频分级是否自然仍属Gate 3人工判断。

## 复现与回滚

1. 输入为上述已批准Surface源，核实SHA；输出必须是不存在的新路径，脚本拒绝覆盖。
2. request JSON字段：source、output、report、pass='lighting'、density=64、surface_gate=2、
   palette读取palette_art09_lighting_v1.json；layers逐层包含id、width、height、size、origin，
   尺寸与Transform读取既有floor_slice_layout_v1.json，不重新设计。
3. Aseprite命令：--batch --script-param "request=<absolute request.json>" --script tools/aseprite/light_floor_318_art09.lua。
   Windows GUI exe等待实际退出并检查report/stdout/stderr；作者成功标记ART09 LIGHTING AUTHOR PASS。
4. 继续使用floor_pipeline.lua的Export严格验证固定矩形、精确Palette、二值alpha、辅助层排除和RGBA Indexed PNG往返。
   导出目录仅为既有忽略预览区，不使用正式BindProfile或借用历史V2发布身份。

实际author-request.json与export-request.json保存在下述本地证据目录，可直接审阅参数。
回滚预览只需应用已批准Surface的floor_318_surface_vending_right_final.res；正式默认仍为V3。
Gate 3通过后再接入最终发布stage/receipt/绑定；当前不把候选冒充正式发布。

## Godot AI 与 Gate 3 证据

本地目录：art_source/floors/.preview/issue-76-lighting-v1/，阅读入口index.md。
当前候选资源为floor_318_lighting_v1_final.res，八张纹理内嵌压缩保存，可从磁盘重载。

- 同一正式res://scenes/main/main_3d.tscn、Issue worktree，Godot4.7.2 / addon4.1.0。
- Surface与Lighting均有CAM01/CAM02、门关/门开、等待、真实登舱Tween代表帧的feed与CRT。
  原始feed320×240，完整CRT2560×1440；native局部另存1×及nearest4×，不拼接或重绘实机截图。
- 采用当前正式场景已有passenger_001占位Profile，不新增或替换乘客美术。
  登舱实际采样0.08s和0.35s；记录真实位置和BOARDING/busy状态，实际定时器存在帧间差异，不宣称逐帧对齐。
  CAM02在0.35s乘客经过近机位会遮屏，另提供0.08s可读代表帧。
  Tween结束前取消预览，不宣称这些截图是实际业务到达318或完成登舱。
- 八层Transform/size/显隐/材质模式、相机/FOV、17盏既有灯、动态编号、Marker、Tween时长、tint/energy和CRT直接内存比较一致。
- Lighting→004 / 612 / fallback123→Lighting：旧层八层纹理或场景fallback、tint、显隐、alpha核对通过；
  返回候选八张纹理像素及CAM02 feed精确恢复。null/reset恢复共享天花，再返回候选检查通过。
  null检查产生两条预期Warning，未描述为零warning。
- 保护区检查：壁灯发光面、门把、售货柜玻璃/商品/付款模块与Surface逐像素相同。

本轮在候选源与制作脚本冻结后退出编辑器，运行一次统一入口：
powershell.exe -NoProfile -File tests/run_all_tests.ps1 -GodotPath <configured GODOT_BIN>。
ALL CHECKS PASS / exit0；1561通过、0失败，existing-tests保留43条已有Warning，其他四阶段0Warning。
完整五份日志在本地证据validation/；未反复重跑全量。
测试后重启唯一Issue Editor并重新启动正式main_3d，从磁盘加载floor_318_lighting_v1_final.res，
八张纹理逐像素匹配严格导出，CAM01/CAM02 feed与初次候选精确相同。
冷重载后冻结属性对比通过；JSON浮点往返容差1e-6，最大差约9.8e-19。
候选资源metadata明确为ART09 Lighting V1 candidate / Gate 3 human review pending，正式Profile仍V3。
测试清理只恢复了97项已经证明无内容差异的导入机械状态；没有因此重跑全量。
自动检查、Godot AI自检与人工美术验收分别记录；Gate 3尚未通过，未push/merge。
