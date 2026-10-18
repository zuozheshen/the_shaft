# 楼层离线光照制作

适用于当前固定平面、固定机位的烘焙基础光照。Godot继续读取最终纹理，不新增runtime系统。

## 三份独立输入

1. 已批准Surface原生源：材质/轮廓底图，不从Lighting成品反推。
2. 具名遮罩JSON：灯位、范围、门/设备区域、接触部与保护区。
3. 光照参数JSON：环境底亮度、各遮罩增减量、区域模型与最终系数上下限。

入口为tools/aseprite/bake_floor_lighting.lua。脚本不含楼层ID、物件坐标、固定层名或127色数量。
几何从已有layout manifest按层传入；recipe选择vertical/ground/ceiling坐标。
所有颜色映射回调用方提供的批准色集，保留每个alpha值；保护区直接保留原像素。

## 遮罩与参数

遮罩源schema_version=1，masks对象以名字索引：

| kind | space | 参数与含义 |
| --- | --- | --- |
| rect_union | pixel | rects为闭区间[x0,y0,x1,y1]数组，组合区域/保护区 |
| ellipse | world | center/radius为二维数值，平滑椭圆权重 |
| line_second | world | center/radius沿第二坐标形成平滑接触带 |
| x_squared | world | radius控制两侧衰减权重 |

vertical的world为X/Y，ground/ceiling为X/Z，方向沿已冻结平面Transform。
光照参数schema_version=1，layers按ID索引；每层声明coordinates、model、clamp、
可选protect名字列表及regions区域替代模型；passthrough=true逐像素保留。
model包含base、可选height(origin/range/gain)和按顺序累加的fields(mask/gain)。

遮罩的JSON是可编辑制作源；mask_preview_directory输出对应灰度PNG供查看。
这些预览不属于正式美术输出、不受127色色板限制、不提交Git。
当前不读取手绘PNG遮罩，也不自动识别新布局物件；新布局需要作者编辑相应区域数据。

## 执行

request字段：source、output、report、surface_gate=2、density、canvas、palette、
layers(每层id/width/height/size/origin)、recipe与masks的绝对路径。
可选mask_preview_directory必须为已有空目录。
palette.art_approved=false表示输出仍待人工验收；批准的输入Surface与候选审批分开记录。

    aseprite --batch --script-param "request=<absolute request.json>" --script tools/aseprite/bake_floor_lighting.lua

Windows GUI exe须等待实际进程退出，核查report.ok和FLOOR LIGHTING BAKE PASS。
输出必须是新路径；脚本拒绝覆盖，配置未知引用在另存前拒绝。
然后使用既有floor_pipeline.lua严格Export，沿用精确Palette、二值alpha与PNG往返检查。
不借旧V2发布身份，不自动BindProfile或修改正式receipt。

318示例：lighting_recipe_art09_v1.json可重建冻结V1；lighting_recipe_art09_darker_r1.json生成Darker。
二者共享lighting_regions_art09_v1.json，并从同一已批准Surface重新烘焙。
回滚切换已有候选即可，原Surface/V1保持独立。

## 工具回归

Windows PowerShell 5.1 或 PowerShell 7 执行：

```powershell
powershell.exe -NoProfile -File .\tests\tools\floor_lighting_bake_tests.ps1 -AsepritePath "F:\Aseprite-v1.3.18.6-Windows\aseprite.exe"
```

请替换为本机 Aseprite 路径，也可设置 ASEPRITE_PATH 后省略参数。
测试脚本使用 UTF-8 BOM，避免 Windows PowerShell 5.1 用系统代码页误读中文注释；JSON 显式按 UTF-8 读取。
22 项检查覆盖冻结源、V1 八图精确回归、alpha、未知遮罩/缺层拒绝、拒绝覆盖，以及独立两色单层/32px 密度 fixture。
失败时检查进程退出码与 report.ok；工具使用与现有导出器一致的 Lua error 出口，不打印成功标记。
日志位于命令显示的 art_source/floors/.staging/lighting-tests-* 忽略目录。
此局部工具验证不能替代 tests/README.md 中的统一入口或人工视觉验收。
