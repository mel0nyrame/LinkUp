# 按改动范围运行 CI 检查

- **状态**：Active / implemented
- **日期**：2026-09-27
- **范围**：`master` 的 push、任意目标分支的 PR 和手动触发的 CI

## Problem

仅修改文档的提交也会安装 Flutter 依赖、生成代码、分析并运行全部测试。这些检查不能为纯文档差异提供更多验证，却增加反馈时间和运行成本。叠放 PR 以功能分支为目标时，也需要与直接提交到 `master` 的 PR 相同的自动验证。

## Decision

CI 对 `master` 的 push 和所有目标分支的 PR 启动，文档和代码差异共用一个检查状态。签出代码后，以触发事件的基准提交和 HEAD 的差异判断路径：只有明确列入文档范围的文件变化时，运行 `git diff --check`；其他变化运行原有 Dart 检查，涉及 Android、依赖或 CI 工作流时继续构建 debug APK。手动触发或无法确认基准提交时运行完整检查。

文档范围由 [CI 工作流](../../.github/workflows/ci.yml) 中的路径规则负责。新增路径默认进入完整检查，避免未知文件被误归为文档。发布工作流保持完整验证。

## Alternatives considered

- **用 workflow 的 `paths` 过滤器跳过纯文档提交**：[GitHub 的路径过滤规则](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushpull_requestpull_request_targetpathspaths-ignore)会让被跳过的必需检查停留在 Pending，阻塞 PR 合并；也无法提供文档检查结果。
- **为文档和代码分别创建工作流**：可以隔离运行环境，但需要维护多个检查状态和必需检查配置；当前单一 CI 工作流能完成分流。
- **按“关键代码”进一步拆分测试范围**：路径无法可靠表达认证调用链和跨语言接线的影响；除纯文档外保留完整 Dart 检查。

## Consequences / Risks

纯文档差异只检查新增内容的空白错误，不验证链接或 Markdown 语义。文档路径的判定必须保持显式；若文档目录开始承载可执行内容，应收紧路径规则。无法识别的文件和基准提交会增加 CI 成本，但不会跳过代码检查。所有目标分支的 PR 都会消耗 CI 资源，包括叠放 PR；它们也因此获得与普通 PR 相同的代码检查。
