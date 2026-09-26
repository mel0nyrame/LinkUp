# 分流标签

技能使用两种分类角色和五种标准状态角色。本文件将这些角色映射到本仓库 Issue 跟踪器中的标签。

## 分类角色

| 标准角色 | 跟踪器标签 | 含义 |
| --- | --- | --- |
| `bug` | `bug` | 已要求的行为发生故障 |
| `enhancement` | `enhancement` | 新行为或改进 |

## 状态角色

| 标准角色 | 跟踪器标签 | 含义 |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | 等待维护者评估 |
| `needs-info` | `needs-info` | 等待报告人补充信息 |
| `ready-for-agent` | `ready-for-agent` | 需求已明确，可由自主 Agent 实施 |
| `ready-for-human` | `ready-for-human` | 需要人工实施 |
| `wontfix` | `wontfix` | 不计划处理 |

每个已分流的 Issue 或纳入分流范围的 PR，恰好有一个分类标签和一个状态标签。状态标签互斥。技能提到标准角色时，使用此表对应的跟踪器标签。
