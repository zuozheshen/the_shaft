# ART-09 Darker R3

按用户六点反馈制作，见[本轮授权与计划](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6250237392)。
起点4d15a484ba2f029c09da137ff67fd4af91a8f610，dev/76-floor-318-art-direction。
R3为独立Gate 3候选；原Surface、Lighting V1、Darker R1/R2及配置保留。

## 制作内容

1. 墙面：以沿顶面结构的横向受光带替代椭圆光池；line_second中心Y=2.45、半径0.38、gain0.20，
   壁灯局部叠加从0.20降至0.04。保留批准Surface材质，受光遮罩不随X产生云状轮廓。
2. 地面：R2模型base/fields/clamp整体乘0.95，中央相对光池保留。
3. 门：上缘两像素、左侧两像素及把手旁一像素窄受光；门板主体不整体提亮，把手本体保护。
   首轮把手旁受光看似多出五金条，正式实机复查后收窄为1px，初轮证据保留。
4. 桶旁：移除独立墙面/地面桶后椭圆暗斑，保留原墙脚和贴桶底的接触阴影，桶体像素保持。
5. 售货机：仅外框顶部和左右三块ROI亮边归并为四个既有灰阶，569像素变化；该ROI颜色38→4。
   玻璃/商品/付款区、内部陈列和轮廓alpha不变。
6. 318节点：文字/位置/Transform/字号/像素尺寸/颜色/描边/Unshaded逐项完全一致。

输入为批准Surface + lighting_recipe_art09_darker_r3.json + lighting_regions_art09_r3.json +
palette_art09_darker_r3.json，经既有bake_floor_lighting.lua得到中间候选；随后仅执行
refine_floor_318_lighting_r3.lua收边，再交原floor_pipeline.lua严格Export。
收边request字段source/output/report/palette，不覆盖输入；通用baker/Exporter、正式场景和runtime不改。

## 验证与范围

- 最终三步FLOOR LIGHTING BAKE PASS / ART09 R3 RIM PASS / FLOOR_PIPELINE_OK，均exit0。
- 首次制作因PowerShell展平单矩形JSON数组被配置校验拒绝，未保存候选；修正嵌套一次后通过。
  失败诊断author-first-failure.json保留。后续仅一次实机门受光细化，无循环重跑全量。
- 固定八矩形、精确原127色、二值alpha、辅助层排除、RGBA Indexed PNG往返通过。
- 八层alpha相对R2零变化，灯具/把手/商品/付款区/桶口保护区逐像素不变；
  ceiling、mid_right和两个front层逐像素一致。售货机收边ROI外零变化。
- 编码RGB加权像素亮度：整张ground平均相对R2降低4.86%；中央抽样仍高于两侧。
  门板主体抽样完全不变，受光只在窄ROI；桶旁墙面抽样恢复约8.36%。
  数值仅用于检查方向，不代表物理照度；原值/矩形在pixel-comparison-final.json。
- 正式main_3d双机位同状态R2/R3 feed320×240与CRT2560×1440、main/ground/售货机原生1×/nearest4×已取得。
- 单一匹配Issue worktree的Godot4.7.2 / addon4.1.0，session c888ea2f1fd34e4f / PID2572。
  八层材质/Transform/尺寸/显隐、机位/FOV、17灯、编号/Marker/Tween、白tint/energy1、CRT逐字段一致。
- 004/612/fallback123旧层纹理/色调/显隐/alpha恢复及返回R3八图/CAM02 feed精确一致。
- 新游戏进程从保存资源读取且绕过缓存重载，八图与最终导出逐像素一致，双机位feed精确一致。
  冻结属性与318节点跨重启比较通过，容差1e-6，最大数值差0；最新game日志无ERROR。
  Editor保留12条既有Warning，未清除或顺手修改。
- 本轮为候选资产/专用作者步骤；正式runtime、通用协议和测试入口未改，不重跑统一全量。
  上一轮22项工具/1561项统一结果仅为历史，不冒充本轮运行。

R3 native：4,142,571 bytes，SHA256 ef578a598b67d89f7713689e9086a5734f5a5bd1463d6bc48df324e78a8e2537。
沿用普通Git；本轮六文件，PNG/截图/Profile/日志留忽略目录，最终以png-final、masks-final、r3-final-*为准。
本地入口：art_source/floors/.preview/issue-76-darker-r3/index.md。
Gate 3等待人工验收；当前main_3d显示R3 CAM02，正式V3绑定不变，未push/merge。
