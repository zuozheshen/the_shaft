# ART-04 / Issue #68：正常值班照明

执行范围依据 [PLAN v1](https://github.com/zuozheshen/the_shaft/issues/68#issuecomment-5987056668)、
[正式审批](https://github.com/zuozheshen/the_shaft/issues/68#issuecomment-5987128027) 和
[PLAN v2 颜色校准批准](https://github.com/zuozheshen/the_shaft/issues/68#issuecomment-5987356556)。
实现基线为 `ff0b123cab35634a10b38163067b17afea629a43`。本说明记录实际参数和复查边界，
不代替用户美术/体验验收。

## 玩家操作舱

路径相对正式 `main_3d.tscn` 的 `三维操作舱`。
保留 `灯光/顶灯` 原 Omni 节点，但设为不可见；由 `灯光/正常值班照明` 下的两盏 Spot 接替。
没有新增灯具 Mesh、照明脚本、屏幕补光或 Blender 资产。

| 参数 | 前部工作主光 | 后部辅光 |
| --- | --- | --- |
| 本地位置（米） | (0, 2.32, -0.45) | (0, 2.32, 0.80) |
| 本地 X 旋转 | -65° | -105° |
| Energy | 2.0 | 1.3（前灯的65%） |
| Range | 4.8m | 4.5m |
| Spot 半角 | 70° | 70° |
| Distance / Angle attenuation | 1 / 1 | 1 / 1 |
| Color | (1, 0.9267, 0.8487, 1) | 同前灯 |
| Light 自身 layers / light mask / caster mask | 1 / 1 / 1 | 1 / 1 / 1 |
| Specular | 0.5 | 0.5 |
| Shadow | 开启 | 开启 |
| Size / Blur | 0 / 1.5 | 0 / 1.5 |
| Bias / Normal bias | 0.05 / 0.5 | 0.05 / 0.5 |
| Reverse cull face | true | true |

维持顶部方向、前部工作区较强、后半舱较弱。宽角与范围在批准调试范围内扩展，
使左右设备仍有直接光。PCSS 在实机出现颗粒/锯齿状阴影，按 v1 的回退方案采用 Size=0 的过滤 PCF。
仅在这两盏新灯启用反向阴影剔除，减轻原实体 CSG 墙面的自阴影条纹；没有改几何或材质。
项目原阴影 atlas/filter 配置保持。

### 颜色

当前项目未启用物理光照单位。3600K 换算色 (1,0.7905,0.5676) 和3800K色
(1,0.8102,0.6091) 在正式画面均使浅灰台面明显偏米褐。
PLAN v2 批准以视觉暖中性白校准：使用3600K意图色与中性白按白色权重0.65混合，
得到实际 `Color(1,0.9267,0.8487,1)`。

这是视觉校准色，**不声称最终输出为精确3600K或严格3500–3800K**。
保护 #66 最终连续烟蓝、完全无磨损材质，以及主台干净浅灰；没有用材质改色补偿灯光。

### 最小环境

原 `灯光/环境光` 绑定
`res://assets/art/lighting/normal_cabin_environment.tres`：

- 中性白 COLOR ambient，Energy=0.08，sky contribution=0；
- 默认 Clear Color 背景，无 Sky/HDRI；
- Linear tonemap，Exposure=1；无 CameraAttributes/自动曝光；
- GI、SSAO、SSIL、SSR、Glow、Fog、调整/调色均未启用。

监控 SubViewport 原本共享主 World3D，所以弱回填也作用于监控摄影棚。
最终0.08对原生320×240 feed的前后对照：CAM01闭门平均绝对亮度差约1.53/255，
地面取样 (6,7,6)→(7,8,7)，门面取样 (44,47,48)→(46,49,51)。
900/387 的 CAM02 平均差约0.096/255，取样的楼层主要色块保持。
这不等于监控画面完全无变化；黑位、层次与楼层辨识仍留人工验收。

CRT、CASE、左右屏/LCD 保持原 unshaded 展示链及尺寸、shader和业务更新，
不新增屏幕光。原摄影棚顶灯与 mask4 的楼层 Profile 灯完整保留。

## 监控乘客舱近门占位光

路径相对 `监控摄影棚定位/监控测试摄影棚`：
`监控灯光/门外光占位验证/近门溢光`。
父节点 **visible=false**，默认停用；只在验证时手动启用。
没有与门信号、楼层 Profile 或业务控制器接线。

| 参数 | 实际值 |
| --- | --- |
| 本地位置 | (0, 0.8, -0.2)m |
| 朝向 | 摄影棚本地 (0,0,0)，斜向近门地面 |
| Energy / Specular | 0.3 / 0.2 |
| Range / 半角 | 1.4m / 35° |
| Color | (0.9,0.95,1,1) |
| Light 自身 layers / light mask / caster mask | 2 / 2 / 2 |
| Shadow / Size / Blur | 开启 / 0 / 1.5 |
| Bias / Normal bias | 0.03 / 1.0 |

Light 自身 layers=2 使原 monitor camera 的 cull mask=6 能看见这盏光；
只设置 light mask=2 而保留自身 layers=1 不会在该 camera 下产生照明。
原摄像机、门与两盏摄影棚灯均未因此修改。

位置从 v1 参考1.15m降低到0.8m，以将地面照域约束在前1/3：
最远地面Z约为 `-0.2 + 0.8 × tan(atan(0.2/0.8) + 35°) = 0.7215m`，
小于2.2m舱长的1/3（0.7333m）；后壁Z=2.2m超出1.4m range。
实际效果主要在中央近门地面/门槛附近，不保证整个门框侧壁都获得补光。

正式源场景重载后的四组合比较：
闭门占位光开/关没有像素亮度差超过0.1/255；开门3570像素发生可辨亮度变化，
CAM02开门开/关逐像素相同。原真实门扇负责阴影遮挡。
对照后已恢复默认停用。

**当前业务乘客舱在距玩家舱100m的独立摄影棚，玩家后墙为实墙检修盖。**
该占位只验证监控乘客舱近门溢光原则；没有实现玩家操作舱随开门变化的溢光。
实际影响玩家舱前1/3需要先冻结两空间/门口关系并另行修订范围。

## 复查与交接

1. 仅打开当前 Issue worktree 的一个 Godot Editor，按 `godot-ai.md` 核实 live project path。
2. 运行原正式 `res://scenes/main/main_3d.tscn`；玩家位置(0,1.5,0)、FOV70不变。
3. 用 Q/E 检查主/左/后/右和转向中间画面：屏幕信息优先，设备可读，烟蓝与浅灰本色保持，
   台下/角落较暗但能辨结构，无随机闪烁、过曝、聚光亮斑或大面积纯黑。
4. 检查原CAM/MIC/开关门、左台栏目、右台数字→验证→拨杆，以及实际接乘表现。
   对照900/387两种Profile的CAM01/CAM02和门开/关。
5. 若复查占位光，仅临时启用其父节点，对照闭/开门和光关/开；完成后恢复visible=false，不保存临时状态。
6. 自动检查使用原统一入口 `tests/run_all_tests.ps1`，测试与日志结果记录在 Issue REVIEW。
   逻辑测试、Godot AI实机自检和用户体验验收分别报告。

本轮实机为Godot4.7.2、D3D12 Forward+、RTX4060 Laptop，framebuffer2560×1440。
静态稳定性两次取样相隔100.084秒：13659个网格像素亮度差为0，灯颜色/能量不变；
这不是持续视频或用户体验验收。
同一运行实例各60帧短采样，主视口GPU均值主台约0.932→1.141ms，后方约0.981→1.195ms，
FPS均为240。该指标只覆盖主视口、受帧率上限影响，不代表完整GPU预算或长期性能保证。

提交只涉及两份场景、环境资源和本说明。截图/日志保存在仓库外；不改正式Blend/GLB、
贴图/材质、业务/API、输入、camera/viewport、测试执行器或addon。
本地 REVIEW 停在push/merge前，最终比例、色彩、质感、可读性和操作体验由用户验收。
