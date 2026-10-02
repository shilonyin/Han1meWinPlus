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

# 审查分支区间（相对 win 分支的改动）
.\tools\ocr\review.ps1 -From origin/win -To HEAD -Out .review.md

# 补充业务背景，审查会更准（提交信息里说不清的需求意图写这里）
.\tools\ocr\review.ps1 -Background "给播放器加重试，失败 3 次后回退到 720p" -Out .review.md
```

不加 `-Out` 就直接打印到终端。生成后把文件交给 DSH 审查即可，例如：

> 读 `.review.md`，按里面的规则审查这批改动

## 审查规则

规则在仓库根的 [`.opencodereview/rule.json`](../../.opencodereview/rule.json)，已按本项目的
实际约定写好（禁止建议 `dart format`、枚举序列化兼容性、dispose 资源泄漏清单、
ARB 三语言同步等），提交进仓库后本地和 CI 共用同一份。

改规则后可以用这条确认它对某个文件是否生效：

```powershell
.tools\ocr\bin\opencodereview.exe rules check lib/src/core/settings.dart
```

## 可选参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-MaxDiffLines` | 300 | 单个文件最多取多少行 diff，超出部分截断并标注 |
| `-SkipFileOverLines` | 2000 | 单文件 diff 超过这个行数就整体跳过（列进「跳过的文件」段） |

改动特别大时先调小 `-MaxDiffLines`，避免材料过长。

## 和 CI 的关系

[`.github/workflows/ocr-review.yml`](../../.github/workflows/ocr-review.yml) 在 PR 上做同样的事，
但走的是真实 LLM 调用（需要配 `OCR_LLM_AUTH_TOKEN`）。两边 pin 的都是 v1.12.11，
规则文件也共用，所以本地看到的结论和 CI 基本一致。

## 目录结构

```
tools/ocr/              # 入库：脚本与说明
  setup.ps1             #   拉取二进制
  review.ps1            #   生成审查材料
  README.md
  bin/                  # 不入库（.gitignore 已排除）
    opencodereview.exe  #   55MB 官方预编译二进制
```
