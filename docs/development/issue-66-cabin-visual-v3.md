# ART-03 / #66：舱体视觉 V3

最终设计遵循 Issue 的有效修订及用户在执行会话中明确的「连续烟灰蓝、完全不要磨损」。
大面不再分成重复板格；不连接掉漆、划痕、局部磨亮、旧化或替换板色差贴图。

四壁使用共享的干净喷漆材质与整面 QuadMesh。顶边、地脚和护角为窄 BoxMesh。
唯一墙面检修门位于后墙，具备折边盖板、把手及四个紧固件；后方正式视角能看到完整盖板。
天花保留一块小型盖板，无实际洞口，后方视角上缘可见。
点检记录是印刷纸张与夹板，不赋予交互或新业务。

主台仅对原导入模型的十个外壳子节点使用材质覆盖；原模型、源文件及功能模块不改写。
乘客舱门使用干净金属材质，中央密封缝与折边附着于原左右门扇动画根。
门框内折边、导向槽与前沿收边位于固定门区。门扇尺寸、实际间隙和运动范围不变。
所有新增节点只用于视觉，不生成碰撞，不挂载业务脚本。

资源入口：

- `scenes/visuals/cabin_assembly_v3_visual.tscn`：四壁、收边、后墙与天花盖板。
- `scenes/visuals/passenger_cabin_assembly_v3_visual.tscn`：固定门框与门槛细节。
- `assets/art/materials/elevator_cabin_v3/`：原生材质与两块闭合折边盖板 ArrayMesh。
- `assets/art/textures/elevator_cabin_v3/`：三张实际使用的橡胶凸点/法线及点检记录位图。
  橡胶纹理只表示统一的防滑凸点与材料颗粒；墙面、主台外壳、门扇与盖板不使用旧化位图。
- `art_source/elevator_cabin_visual_v3_source.py`：重建原生材质、视觉场景与盖板 Mesh。
  位图作为独立资源保留，来源与 SHA-256 记录在同目录 `provenance.json`。

在包含 `project.godot` 的已提交 #66 worktree 执行：

```powershell
python art_source/elevator_cabin_visual_v3_source.py --godot "<Godot 4.7 executable>" --scratch-dir "<repo 外临时目录>"
```

未修改灯光、WorldEnvironment、曝光、后处理、玩家机位/FOV、监控分辨率、Q/E、
action_id、碰撞、UI、门动画或业务信号。正式启动入口仍为 `res://scenes/main/main_3d.tscn`。

视觉截图与运行时日志保留在仓库外 REVIEW 证据目录，不进入 Git。
旧 V1/V2 已提交资源保持历史可恢复；V3 中未接入的实验贴图和磨耗 Mesh 已移出工作版本。
回滚由本轮独立 commit 的六个场景/包装文件、原生资源与生成器组成，不覆盖原 Blender/GLB 源。
