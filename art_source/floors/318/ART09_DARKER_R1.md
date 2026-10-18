# ART-09 Darker R1 与制作输入分离

#76 Gate 3候选。用户明确要求“制作Darker R1并分离”；[PLAN补充](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6245905692)记录授权。
沿用base0bf68370、分支dev/76-floor-318-art-direction，起点cd4a70b。

## 分离结果

- tools/aseprite/bake_floor_lighting.lua：通用离线工具，无318专属坐标、物件分支或固定127色数量。
- lighting_regions_art09_v1.json：独立具名解析遮罩/保护区域；源为JSON，灰度PNG是查看输出。
- lighting_recipe_art09_v1.json：提取原V1参数；从Surface重建后八张PNG与冻结V1逐字节一致。
- lighting_recipe_art09_darker_r1.json：独立Darker参数，从Surface重新烘焙。
- floor_318_art09_darker_r1.aseprite / palette_art09_darker_r1.json：新候选，原127项RGBA不变，art_approved=false。
- 使用方式与当前遮罩类型范围见docs/development/floor-lighting-bake.md。

原light_floor_318_art09.lua、Surface和Lighting V1源均保留。
新布局需要作者编辑遮罩和光照参数，当前工具不自动识别物件，也不读取手绘PNG遮罩。

## 版本、效果与边界

| 文件 | SHA256 |
| --- | --- |
| 批准Surface，保持 | efc5e04e5c9330e5afe5648a32b16213f0ecd4e4470f8e32a20a187ea670e33f |
| 原Lighting V1，保持 | b3c0f830a643a10cd0bc7a8376e22237ee2c901f564666a6804830dbe44f66ff |
| Darker R1 native | 3a531054eb2f0759b95d03cee8d8b29a50ee6c2e14a916fe62aa675213f82b31 |

新native为4,141,930 bytes，沿用现有普通Git跟踪；不提交预览PNG/Profile/日志。
初版Darker对照后，只在配置中收窄顶部受光、压低墙面非直射基底，保留原V1。
最终供查看文件以-final命名，中间候选与首次配置留在本地预览作诊断。

原生像素抽样的编码RGB加权亮度（非物理照度/感知亮度）相对V1：
墙面非直射样本约-19.2%，顶部受光样本约-2.8%，灯旁受光样本约-1.6%，
地面样本约-6.9%，门约-5.6%，柜体约-6.1%，桶身约-5.4%。
抽样区域和原值在region-comparison.json；不把这些百分比当作画面质量评分。
天花抽样约-6.0%，亮部与非直射部混合，不宣称整张天花都下降同一比例。

八层alpha0变化、两个前景层0像素变化；灯具发光面、把手、商品/付款区、桶口保护区逐像素不变。
材质、相机、动态编号、17灯、Marker、Tween时长、tint白色/energy1和CRT冻结属性直接比较相同。
未新增几何、灯具、shader或整体滤镜；正式V3 PNG/Profile/receipt/manifest保持。

## 当前验证和验收

- Aseprite通用V1重建与严格导出通过，八图逐字节回归通过。
- Darker严格Export通过：固定矩形、精确色板、二值alpha、RGBA Indexed PNG往返。
- 正式main_3d CAM01/CAM02同状态V1/Darker的320×240 feed及2560×1440 CRT已取得。
- 004/612/fallback123/null-reset往返，旧层纹理/色调/显隐与候选像素、CAM02 feed恢复检查通过。
- null/reset产生两条预期Warning；自动自检不等于人工通过。
- Windows PowerShell 5.1 曾按CP936误读无BOM脚本，吞并请求构造行。触发Circuit Breaker后停止；
  用户明确授权“允许修复编码并继续验证”。仅新增UTF-8 BOM，已证明去BOM后每个源字节不变，默认ParseFile通过。
- 编码恢复后拒绝测试发现独立工具出口问题：app.exit(1)未中止脚本，错误后仍打印PASS；
  改为与现有floor_pipeline.lua一致的stderr + Lua error出口，一次修复后局部22项全部通过 / exit0。
  覆盖V1八图精确回归、alpha、未知遮罩/缺层拒绝、既有输出保护、独立两色/单层/32px密度fixture。
  断言未放宽，Darker画面/参数/资源不因验证修复改变。
- 本轮新运行一次统一入口：ALL CHECKS PASS / exit0，1561通过、0失败；
  五阶段通过，existing-tests保留43条既有Warning，其余阶段0Warning。五份日志在预览目录validation/。
- 统一检查后重新启动唯一Issue Editor（session issue-76-floor-318-art-direction@c888ea2f1fd34e4f / PID2572），
  正式main_3d从保存候选重载：八张纹理与严格导出逐像素相同，CAM01/CAM02 feed与最终候选精确一致。
  冻结属性对V1比较通过（数值容差1e-6，本次最大差0），最新game日志无ERROR。

本地入口：art_source/floors/.preview/issue-76-darker-r1/index.md。
候选资源floor_318_darker_r1_final.res已保存，可重载；当前Game留CAM02。
Gate3等待人工在V1/Darker中选择，正式绑定不更新，未push/merge。
