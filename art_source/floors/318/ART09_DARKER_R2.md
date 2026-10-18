# ART-09 Darker R2

用户在Darker R1后明确要求三点调整：[对应计划记录](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6250116215)。
基线3d52f9fc753338902406619ec64785dd0f19de0b，沿用dev/76-floor-318-art-direction。
R2为Gate 3独立候选；Surface、Lighting V1与Darker R1保留。

## 实际调整

- 墙上部：宽软椭圆受光中心X/Y=(-0.3,2.35)，半径(1.75,0.85)，增量0.30；
  沿用R1环境基底和壁灯受光，不使用硬条状渐变。
- 门框：已有门洞区域内加窄内框遮罩，原凹缝再沉；门把保护区直接保留。
- 墙脚：接触带半径0.22，增量-0.11；桶后墙面局部软阴影，未改变桶体。
- 地面：中央软光池中心X/Z=(-0.2,-1.6)，半径(1.45,1.8)，增量0.32；
  两侧轻微衰减，墙边接触带和桶后地面局部加深。
- ceiling、mid_left、mid_right、两个front层相对R1逐像素一致；只改变far/main/ground。

制作输入：lighting_recipe_art09_darker_r2.json、lighting_regions_art09_r2.json、
palette_art09_darker_r2.json；从批准Surface重新烘焙，既有通用工具不改。
原127项RGBA逐项一致，art_approved=false；无新增色、道具、几何、灯、shader或runtime逻辑。

## 验证

- Aseprite批处理作者及原严格Export均exit0：FLOOR LIGHTING BAKE PASS / FLOOR_PIPELINE_OK。
- 八层固定矩形、精确色板、二值alpha、RGBA Indexed PNG往返通过；相对R1八层alpha零变化。
- 灯具发光面、把手、商品/付款区、桶口逐像素不变。
- 编码RGB加权亮度抽样相对R1：上部墙+10.5%，门框左内侧-9.3%、右内侧-2.2%，
  墙脚-5.3%，桶后墙-8.8%，地面中央+5.3%、左右约-1.2%，桶后地面-9.4%。
  这是指定矩形的像素数值，不是物理照度或感知亮度；区域和原值在pixel-comparison.json。
- 正式main_3d同状态R1/R2 CAM01/CAM02 feed320×240和完整CRT2560×1440已保存。
- 单一Issue Editor/session路径严格匹配，Godot4.7.2 / addon4.1.0；八层材质/Transform/显隐、
  相机/FOV、17灯、编号/Marker/Tween、白tint/energy1、CRT逐字段比较一致（容差1e-6，最大差0）。
- 004/612/fallback123旧层纹理/色调/显隐/alpha恢复通过，返回R2八图与CAM02 feed精确恢复。
- 新游戏进程读取保存的floor_318_darker_r2_final.res，并绕过缓存重载：八图与导出逐像素一致，
  双机位feed精确一致，冻结属性比较通过。资源审批与制作路径元数据已正确标为R2。
- 最新新游戏日志无ERROR；Editor保留12条既有shadow/unused Warning，无新增错误。
- 本轮纯视觉候选，不重复运行上一轮22项工具/1561项统一检查；工具、协议、测试和正式runtime未改。
  以上历史通过结果不写成本轮重跑。

R2 native：4,149,069 bytes，SHA256 11e0aa58aedc8338eed726857dec7d5ade22bb2d54cc72bdb7a3e50a45f2f269。
实际大小以文件为准；普通Git沿用既有资产跟踪方式，截图/PNG/Profile/日志保留忽略目录。
本地证据入口：art_source/floors/.preview/issue-76-darker-r2/index.md。
Gate 3人工选择待完成；正式V3绑定/PNG/receipt/manifest、场景/脚本/layout均未改，未push/merge。
