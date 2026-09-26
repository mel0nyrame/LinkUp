# Issue 跟踪：GitHub

本仓库的 Issue 和规格保存在 GitHub Issues 中，使用 `gh` CLI 操作。

## 常用操作

- **创建 Issue**：`gh issue create --title "..." --body "..."`。多行正文使用 heredoc。
- **读取 Issue**：`gh issue view <number> --json number,title,body,labels,comments`；需要筛选字段时加 `--jq`。显式指定字段可避开默认视图查询已弃用的 Projects classic 字段。
- **列出 Issue**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，按需加 `--label` 和调整 `--state`。
- **评论**：`gh issue comment <number> --body "..."`
- **增删标签**：`gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **关闭**：`gh issue close <number> --comment "..."`

通过 `git remote -v` 确认仓库；在克隆目录内运行时，`gh` 会自动识别仓库。

## 将 PR 纳入需求分流

**PR 作为需求入口：否。** 如果改为“是”，`/triage` 才将外部 PR 视为需求。

启用后，PR 使用与 Issue 相同的分类和状态标签，并通过对应的 `gh pr` 命令操作：

- **读取 PR**：`gh pr view <number> --json number,title,body,labels,comments`；用 `gh pr diff <number>` 读取差异。
- **列出待分流的外部 PR**：`gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`，只保留 `authorAssociation` 为 `CONTRIBUTOR`、`FIRST_TIME_CONTRIBUTOR` 或 `NONE` 的 PR；排除 `OWNER`、`MEMBER` 和 `COLLABORATOR`。
- **评论、关闭和修改标签**：评论用 `gh pr comment`，关闭用 `gh pr close`。修改标签使用 API（`gh pr edit` 在本仓库会失败，见 [交付约定](delivery.md)）：`gh api -X PATCH "repos/<owner>/<repo>/issues/<number>" -f 'labels[]=<label>'`。

Issue 和 PR 共用编号。遇到无法确定类型的 `#42`，先运行 `gh pr view 42 --json url`；若不是 PR，再运行 `gh issue view 42 --json url`。读取 `url` 可确认对象存在；只读取 `number` 可能直接回显输入编号。

## 技能要求 `publish to the issue tracker` 时

创建 GitHub Issue。

## 技能要求 `fetch the relevant ticket` 时

使用上文的“读取 Issue”命令。

## Wayfinder 操作

供 `/wayfinder` 使用。**Map** 是一个 Issue，关联的 **child ticket** 也是 Issue。

- **Map**：创建带 `wayfinder:map` 标签的 Issue，用于保存 Notes、Decisions-so-far 和 Fog：`gh issue create --label wayfinder:map`。
- **Child ticket**：优先通过 GitHub 子 Issue 关联到 map（使用 `gh api` 的 sub-issues 端点）。若仓库未启用子 Issue，则在 map 正文中列任务清单，并在 child 正文顶部写 `Part of #<map>`。使用 `wayfinder:<type>` 标签，其中 `<type>` 为 `research`、`prototype`、`grilling` 或 `task`。票据被认领后，将其分配给负责人。
- **阻塞关系**：以 GitHub 原生 Issue 依赖为准，供界面直接查看。执行 `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`；`<blocker-db-id>` 是阻塞票据的数据库 `id`（用 `gh api repos/<owner>/<repo>/issues/<n> --jq .id` 获取），不是 `#number` 或 `node_id`。`issue_dependencies_summary.blocked_by` 只统计仍打开的阻塞票据。若依赖功能不可用，则在 child 正文顶部写 `Blocked by: #<n>, #<n>`。所有阻塞票据关闭后，child 才解除阻塞。
- **可领取票据**：按 map 的顺序列出仍打开的 child；排除存在打开的阻塞票据或已分配负责人的票据，剩余的第一张即为可领取票据。阻塞状态读取 `issue_dependencies_summary.blocked_by`；使用正文回退方案时，检查 `Blocked by` 中的 Issue 是否仍打开。
- **认领**：`gh issue edit <n> --add-assignee @me`，作为本会话首次写入操作。
- **完成**：用 `gh issue comment <n> --body "<answer>"` 回复，再用 `gh issue close <n>` 关闭，最后把上下文指针（gist 与链接）追加到 map 的 Decisions-so-far。
