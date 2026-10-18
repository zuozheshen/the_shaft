# ART09 Darker R3 正式发布

2026-10-18，用户明确“验收，推送合并删除”，并单独确认“包括远端分支”。
[Gate 3验收及发布授权](https://github.com/zuozheshen/the_shaft/issues/76#issuecomment-6250616387)。
批准固定native SHA256 ef578a598b67d89f7713689e9086a5734f5a5bd1463d6bc48df324e78a8e2537，画面不再迭代。

## 持久接入

- 正式八PNG从floor_318_art09_darker_r3.aseprite由原CLI/Lua严格导出，与验收候选八图逐字节一致。
- 批准副本palette_art09_darker_r3_approved.json使用原127项RGBA，art_approved=true；
  候选Palette及旧版本源保持，作者输入无需修改审批标记。
- 独立发布stage art09_darker_r3；仅在既有allowlist增加此值，不借V2/Diagnostic身份。
- 现有318 FloorVisualProfile纹理路径/白tint/energy1/显隐保持，版本元数据标为human accepted。
- manifest只更新审批/Palette/当前美术状态；层几何、provenance source fingerprints不变。
- VISUAL_STATUS与PROJECT_STATE、制作/发布文档同步；旧V3恢复记录保留为历史。
- 8 PNG继续既有Git LFS，源.aseprite继续普通Git；不提交截图、日志、缓存或临时导出。

## 本次验证

- 正式CLI Export / BindProfile / VerifyGodot通过，真实receipt为art09_darker_r3。
- 首次发布前被Palette hash门拒绝：Windows物理CRLF hash与canonical LF不一致；
  修正为既定canonical LF一次后通过，拒绝时正式资产未写入，未弱化校验。
- 最终Profile/layout checker通过；metadata完成后再次检查source/Palette/receipt/Profile实际匹配。
- Aseprite CLI回归58项全部通过，含负例、拒绝覆盖、部分发布失败回滚和源不变。
- 正式接入后新运行一次统一入口：ALL CHECKS PASS / exit0；1561通过、0失败。
  五阶段通过，existing-tests 43条既有Warning，其余0Warning；不为机械导入状态重跑全量。
- 唯一Issue Editor / Godot4.7.2 / addon4.1.0，session 8d3f1ae17dd35e44 / PID43032。
  新游戏进程读取正式data/presentation/floor_visuals/floor_318_visual.tres与assets/art/floors/318/*.png；
  八个Imported Texture2D与验收候选逐像素一致，CAM01/CAM02 feed精确一致，未创建运行时ImageTexture替换。
- 正式main_3d中004/612/fallback123往返恢复及返回正式318 feed通过。
- 相机/八层几何/材质/17灯/Marker/Tween/CRT等冻结属性逐字段一致，数值容差1e-6，最大差0；
  318节点文字、位置、字号、颜色/描边/Unshaded完全一致，最新game日志无ERROR。
- 自动与Godot AI自检独立于人工验收；本次人工Gate3明确已通过。

主工作区原54项未提交修改保持；只在Issue外部worktree制作和发布。
推送/PR/合并SHA、main同步、证据归档和分支/worktree删除结果写回#76。
不自动同步开发日志或飞书。

## Receipt 固定输入

- source: art_source/floors/318/floor_318_art09_darker_r3.aseprite
- source_sha256: ef578a598b67d89f7713689e9086a5734f5a5bd1463d6bc48df324e78a8e2537
- palette_source: art_source/floors/318/palette_art09_darker_r3_approved.json
- palette_sha256: ad399aa7a921f7ba1aefafba4249ee47daf7a737e8a42e2aad5804d39d187bd8
- layout_sha256: 77af5ad8cbd0598fc7b502cdf90b0b80cdf9b607a685980a1eb43be1e983af35
- profile_sha256: eb988fd123122ede7610f35aba0a7f21291b7cd84a573dd7b1ec96e09a1a33d1
