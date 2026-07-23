# The Shaft 开发日志

本目录保存以 Issue 为单位的本地开发日志草稿，以及不含凭据的同步去重状态。

## 使用方式

- 用户说“整理开发日志”时，先检查 Git 状态、相关 diff、最近提交和已有日志，再根据 `template.md` 创建或更新对应的本地草稿。
- 用户明确说“同步开发日志”时，才可使用已获授权的飞书连接同步指定日志；同步前使用 Issue 编号和 commit hash 检查 `sync-state.json`，避免重复同步。
- 未提供 Issue 编号时，在日志中写明“未关联 Issue”，不要猜测或补造编号。
- 将同步失败记录在本地日志的“已知问题与下一步”中，并保留本地草稿。

## 命名建议

建议使用 `YYYY-MM-DD-issue-<编号>.md`；没有 Issue 编号时使用 `YYYY-MM-DD-untracked.md`。

## 边界

- 本目录不存储飞书 App Secret、Token 或其他凭据。
- 本目录不代表功能验收结论；“已验收”必须有用户明确确认。
- Codex 不会为日志工作流执行 commit 或 push。
