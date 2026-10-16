# 共用楼层天花板 V1

当前材质为provisional / placeholder-quality。保留所有正常楼层共用天花板的设计与结构，
最终天花材质延期至独立Issue；不得把本文件的制作记录当成最终人工美术验收。

用户于2026-10-16批准将天花板加入所有楼层的共用结构。原七层保留，新增 ceiling。

- 原生源 ceiling_concrete_v1.aseprite；共享纹理 assets/art/floors/shared/ceiling_concrete_v1.png。
- 8.45×3.75m，541×240px，目标64 px/m；顶高2.6m，世界固定，独立水平Quad。
- 内置ImageGen生成正常曝光的正交混凝土材质；Aseprite真正采样、映射候选色板并保存源/PNG。
- 默认适用于所有现有与fallback Profile；可通过 ceiling_texture / ceiling_visible 单独覆盖。
- 保留旧318源与20色发布门；共享顶面不冒充旧Palette中的资产。
- 完整提示词与来源hash见同目录 prompt / provenance。三张生成原图与制作Lua留本地
  art_source/floors/.preview/318-material-ceiling-v3，不依赖外部generated_images路径加载。
- 本轮只做Godot正式场景视觉观察，未运行自动测试；用户画面验收待完成。
