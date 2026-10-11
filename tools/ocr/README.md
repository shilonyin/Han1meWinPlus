# 本地代码审查

用 [OpenCodeReview](https://github.com/alibaba/open-code-review)（`ocr`）在本地随时审查改动，
**不需要 LLM API Key** —— 走的是它的 delegate 模式：OCR 只负责「确定性」的那一半
（筛出该审哪些文件、每个文件适用什么规则），实际的审查推理交给 DSH 自己的模型。

## 装一次

二进制 55MB，不入库（`tools/ocr/bin/` 已在 `.gitignore` 里）。换机器或清理过之后跑一次：

```powershell
.\tools\ocr\setup.ps1
```

## 日常用法

```powershell
# 审查当前工作区改动（含未跟踪的新文件）—— 提交前自查最常用
.\tools\ocr\review.ps1 -Out .review.md

# 审查某个提交
.\tools\ocr\review.ps1 -Commit 7582316 -Out .review.md

# 审查分支区间（相对 master 分支的改动）
.\tools\ocr\review.ps1 -From origin/master -To HEAD -Out .review.md

# 补充业务背景，审查会更准（提交信息里说不清的需求意图写这里）
.\tools\ocr\review.ps1 -Background "给播放器加重试，失败 3 次后回退到 720p" -Out .review.md
```

不加 `-Out` 就直接打印到终端。生成后把文件交给 DSH 审查即可，例如：

> 读 `.review.md`，按里面的规则审查这批改动

## 审查规则

规则在仓库根的 [`.opencodereview/rule.json`](../../.opencodereview/rule.json)，已按本项目的
实际约定写好（禁止建议 `dart format`、枚举序列化兼容性、dispose 资源泄漏清单、
ARB 三语言同步等），提交进仓库，团队里每个人共用同一份。

改规则后可以用这条确认它对某个文件是否生效：

```powershell
.\tools\ocr\bin\opencodereview.exe rules check lib/src/core/settings.dart
```

## 可选参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-MaxDiffLines` | 300 | 单个文件最多取多少行 diff，超出部分截断并标注 |
| `-SkipFileOverLines` | 2000 | 单文件 diff 超过这个行数就整体跳过（列进「跳过的文件」段） |

改动特别大时先调小 `-MaxDiffLines`，避免材料过长。

## 为什么只做本地审查

曾经接过一个 GitHub Actions 工作流（PR 上自动审查并贴评论），实测跑通后移除了。
原因是**成本**：`pull_request_target` 事件下，任何人 fork 后开 PR 都会触发审查、
消耗仓库所有者的 LLM 额度。本地审查没有这个问题——只在你自己想看的时候跑，
用 DSH 自己的模型，不产生额外调用。

本地审查的规则文件与当时的 CI 是同一份（`.opencodereview/rule.json`），所以结论口径一致。

## 审查结果的可靠性

审查由 LLM 完成，**结论需要人来判断，不要盲信**。实测中遇到过误报：
它把 `ForEach-Object` 里 `$total += $_.Length` 的累加判成「PowerShell 作用域规则
导致写不回外层、函数恒返回 0」，而实测该函数返回正确值（`ForEach-Object` 的脚本块
不是独立作用域）。

这类语言细节的判断偏差属于模型能力边界，写规则约束收效有限。看到可疑结论时
自己跑一遍验证，比改配置更有效。

## 目录结构

```
tools/ocr/              # 入库：脚本与说明
  setup.ps1             #   拉取二进制
  review.ps1            #   生成审查材料
  README.md
  bin/                  # 不入库（.gitignore 已排除）
    opencodereview.exe  #   55MB 官方预编译二进制
```
