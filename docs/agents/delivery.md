# 交付

本文件是 LinkUp 仓库的交付契约：`AGENTS.md` 的变更流程在验证通过后指向这里。通用 Git 规范（提交拆分、命名、push/PR 授权边界）见 `talang-git` skill 的 `references/CONVENTIONS.md` 与 `references/REVIEW-AND-TRACKER.md`；本文件只写这个仓库自己的约定。

## 触发

准备 commit、push 或开 PR 时读本文件。只想跑验证、不打算交付时不需要。

## PR 正文

正文是评审界面。评审者读完它就该知道为什么改、关键行为怎么变、什么证据支持、合并要不要额外处理，而不必先通读 raw diff。

沿用以下五节，顺序固定：

```markdown
## 背景
## 变更轮廓
## 验证汇总
## 评审注意事项
## 风险与回滚
```

| 节 | 装什么 | 不装什么 |
| --- | --- | --- |
| 背景 | 从 issue 或规格说明要解决的问题，用仓库的领域语言 | 从 diff 猜出来的动机 |
| 变更轮廓 | 语义树或 diff 重绘所有权与调用顺序；证据紧邻它支持的那条论断 | 文件清单、源码复述 |
| 验证汇总 | 实际执行的命令、对象、结果；未运行的必要检查如实说明 | 计划要跑什么 |
| 评审注意事项 | 迁移步骤、刻意不包含的范围、反直觉决定、需要人工确认项 | `None` / `N/A` 填空 |
| 风险与回滚 | 可逆性、影响范围、回滚是否只需 revert 代码 | 局部低风险改动的风险段落 |

完成标准：五节都在，没有占位文本，`base`/`head`/commit 范围/链接真实有效。

正文发出后需要改写时用 API 补丁，不要用 `gh pr edit`：

```bash
gh api -X PATCH "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/pulls/<N>" -F body=@pr_body.md
```

`gh pr edit` 在本仓库会因为查询已弃用的 Projects classic 卡片而整体失败，正文不会被更新。

## Review Gate

### 接线改动

`flutter build apk` 只证明 Kotlin 能编译，不证明它在系统里的行为。**接线**指 `android/` 下的 Manifest 声明、Kotlin 调用图、MethodChannel 两侧的通道名与 wire 键。

改动接线时必须满足两条：

1. **跨语言契约断言**：通道名、命令名、wire 键、Manifest 声明和关键调用路径直接对两侧源码断言，落在 `flutter test` 里。`test/android_runtime_contract_test.dart` 是标准写法——它读源文件而不是模拟行为，所以 Kotlin 改错时它会翻红。纯 Dart 的 fake 复刻不了这条：它和被测的 Kotlin 各自演化，Kotlin 写错时测试仍然通过。
2. **双轴 review**：跑 `/code-review`，Standards 与 Spec 两轴分开报告。这类改动的缺陷形态是"实现了规格但做错了"，Spec 轴是唯一能发现它的检查。

### 评审的验证证据

reviewer 以 PR 正文"验证汇总"里列出的命令与结果为验证证据，不自己重跑。需要判定某条验收条件无法验证时，结论里必须写出失败的工具链与原始错误（`Because LinkUp requires Flutter SDK version …` 这类）；本机共享 SDK 与 `pubspec.yaml` 不一致时，先按 `AGENTS.md` 变更流程第 0 步取仓库声明的版本再下结论，否则会把"用错 SDK"读成"跑不了"。

### 已评估并接受

reviewer 提不出确定性检查的判断类意见（重复代码、边界取舍、覆盖强度），由作者决定接受还是改。接受时写进 PR 正文"风险与回滚"，一句话包含：结论、为什么接受、如果后来出问题会怎样。理由是这类意见没有可自动化的判定，仓库里不留结论时下一轮 review 会原样重提，作者被迫重新判断一次。

### 长期决策

命中 `talang-adr` 的触发面时写 ADR，状态字段写清生命周期。ADR 负责理由与被拒绝的替代方案，README 负责用户可观察的行为，两者不互相复制。

## Tracker

Issue 用 `gh` 读写，约定见 [issue-tracker.md](issue-tracker.md)。关联票在 PR 正文首行用 `Closes #N` 声明，GitHub 据此在合并时关票。

验收条件未满足时保持票 open。代码存在、PR 已创建或已合并都不能单独证明目标完成。
