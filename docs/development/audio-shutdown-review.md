# 音频退出修复交接

- 基线：fa6aa60ceb3af93170ed750dc21adc841575b504，codex/content-reset，外部worktree延续前两阶段。
- 用户在最小对照和具体方案说明后明确要求“修复”；本次落实该方案，不修改GitHub，不自动合并/推送。

## 修复范围

正式当前主场景由RuntimeConnector3D接管根窗口正常关闭，保留原有关闭策略供节点移除时恢复。
request_quit防重复请求、暂停新业务、调用AudioShutdown停止音频并等待弱引用失效；
成功后才quit，最多等待真实时间1秒，失败明确ERROR且退出1。
AudioShutdown不是Autoload/Manager，不负责玩法或派单，不修改音频源、音量、导入配置或美术。

flow runner在播放器移出场景时记录弱引用，在最终退出前等待音频线程释放；
node_removed回调只观察，不在退出树过程中重入stop，实际停止由原生PREDELETE执行。
新增回归覆盖MP3/2D WAV/3D WAV、显式持有强引用的超时反例、释放后恢复和已移除播放器。

main-smoke读取project.godot实际入口，在Autoload注册完成后加载，运行初始化，
确认循环MP3处于播放状态、正常退出接线有效，然后两次请求关闭。
同时要求初始化和清理完成标记，以及非零退出码/ERROR严格判断。
新增测试宿主的故意持有播放实例反例，验证正式退出失败通路确实返回1。

## 自动验证

先通过音频专项12条断言、正常关闭smoke和1355条行为回归。
故意持有MP3播放实例的真实进程反例按预期在1秒超时，报ERROR且exit 1；正常路径exit 0。

最终统一入口仅运行一次：

```powershell
powershell.exe -NoProfile -File .\tests\run_all_tests.ps1 -GodotPath 'F:\godot\Godot_v4.7.2-stable_win64.exe'
```

| 检查 | 结果 |
| --- | --- |
| 版本与项目根 | PASS，Godot 4.7.2，单一项目 |
| editor-import | PASS，0 Warning / 0 ERROR |
| scene-contracts | PASS，37项自测，0 Warning / 0 ERROR |
| existing-tests | 1355通过、0失败，43个既有降级/无效输入Warning，无ERROR或退出泄漏 |
| main-smoke | PASS，真实配置入口、循环MP3播放、连续关闭请求、清理完成，0 Warning / 0 ERROR |
| 总结 | ALL CHECKS PASS，exit 0 |

系统TEMP日志：shaft-audio-fix-all.log；完整分阶段目录：
the-shaft-checks-4d6df28e21c04f3cbc72fca7acb0688d。
音频专项及反例日志分别为shaft-audio-fix-focused.log、shaft-audio-fix-negative.log。
79项引擎生成的import换行已验证与HEAD归一化后相同并恢复；不因这些机械变化重跑检查。
最终统一检查后仅补充文档和恢复无语义差异的导入换行，没有再修改运行逻辑。


## 工程边界

这修复应用正常退出和测试宿主收尾；没有补丁引擎。
--quit-after、Editor Stop、强制结束等绕过关闭回调的路径仍可能复现Godot自身问题，
不得把更改后的正常关闭smoke称为对任意强制退出都安全。
此前13项偶发资源错误没有verbose对象清单，不能追溯证明它们每项均为同一根因；
本次通过实际弱引用和完整退出日志验证当前路径，保留旧失败记录。

先前试验曾遇到SceneTree脚本静态引用业务类早于Autoload注册的编译错误，
以及node_removed中stop导致process group重入错误；均已按首个失败阶段缩小并修正。
未放宽任何已有ERROR过滤或删除失败断言，不循环重跑全量检查。

## 视觉与人工验收

本次没有修改场景、布局、模型、Camera或素材，不声明Godot AI视觉验收。
人工实际窗口关闭、音效听感及操作节奏仍由用户最终验收。
本地提交后停在push/merge前，主工作区main不变。
