---
name: the-shaft-devlog
description: Create evidence-based local development-log drafts for The Shaft and, only after an explicit user request, synchronize a specified log through an already authorized Feishu connection. Use when the user says “整理开发日志”, “同步开发日志”, or asks to create, update, review, or deduplicate an Issue-based development log.
---

# The Shaft 开发日志

## 工作边界

- 将 `docs/devlog/` 作为本地日志的唯一工作目录，使用 `template.md` 创建或更新 Issue 对应的草稿。
- 不修改游戏功能、Godot 场景、GDScript 逻辑、Dialogue Manager 对话内容或资源文件。
- 不执行 `git commit` 或 `git push`。
- 不将 Token、密钥、App Secret、Cookie 或其他凭据写入仓库、日志或 `sync-state.json`。
- 不创建飞书应用，不安装或自行选择第三方飞书 MCP，也不要求用户提供 App Secret。

## 生成本地日志

当用户说“整理开发日志”或要求创建、更新、检查开发日志时：

1. 先检查 Git 状态、相关 diff、最近 commit 和 `docs/devlog/` 中已有日志。
2. 确认 Issue 编号；未提供时写为“未关联 Issue”，不要猜测。
3. 只记录能由 Git 输出、文件内容、Godot 实际运行结果或用户明确说明支持的事实。
4. 在日志中分别填写代码实现、Godot 运行、用户验收、Git 提交和飞书同步；未执行或未确认的项必须明确标注。
5. 未经用户明确确认，不得写“已验收”。
6. 只生成或更新本地草稿，不得调用飞书或任何外部同步服务。

## 同步开发日志

当且仅当用户明确说“同步开发日志”时：

1. 确认要同步的本地日志和 Issue 编号，并检查用户已授权的飞书连接是否实际可用。
2. 从日志的 Git 提交部分取得已有 commit hash；没有提交时使用空提交标识，但不得伪造 hash。
3. 使用 Issue 编号与 commit hash 的组合检查 `docs/devlog/sync-state.json`，防止重复同步。
4. 只追加或更新该 Issue 对应的飞书日志区块；不得覆盖飞书整篇文档。
5. 同步成功后，将 Issue 编号、commit hash、目标文档标识和同步时间写入 `sync-state.json`，且不得写入凭据。
6. 同步失败时保留本地日志，在本地日志中记录失败事实与下一步；不得删除或标记为“已同步”。

## 证据标准

- 将代码变更与运行结果分开记录：有 diff 不等于 Godot 已运行；Godot 已运行不等于用户已验收。
- 只记录已存在的 commit；不要把未提交修改写成提交完成。
- 不根据计划、推测或叙述宣称功能完成。
- 输出时说明已检查的证据来源与仍未验证的内容。
