# 318 结构测试源

`floor_318.aseprite` 是 #75 Pass C 的 RGB 单帧九层可编辑模板（541×272，15,258 bytes）。
七个正式层是 far / main / mid_left / mid_right / ground / front_left / front_right；
REFERENCE 为原生参考层，GUIDES 为普通辅助层，两者默认隐藏并锁定，永不导出。
source SHA-256：`2f75cc4eac4322f3ae47c7a3dab66a39bc749528225780d2f5fbc8be0ace9c0f`。

画面由 Lua 在固定世界尺寸上生成极简矩形、网格、alpha 孔和小标记，
用于验证七层导出、透明、材质恢复和 48/64/80 px/m；并非住宅走廊正式美术。
楼层号码继续由共享 Label3D 动态绘制，PNG 只有空白牌面。

`pipeline_test_palette.json` 的九色仅用于技术校验，`art_approved=false`。
实际绑定为 64 候选；推荐不等于最终批准。最终 D 与 palette 由用户冻结后才能精修。
命令、保护和恢复规则见 [管线文档](../../../docs/development/aseprite-floor-pipeline.md)。
