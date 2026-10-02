# 本地代码审查 —— 用 alibaba/open-code-review 的 delegate 模式
#
# 只做「确定性」的那一半：筛出该审哪些文件、每个文件适用什么规则、把 diff 取出来，
# 汇成一份 Markdown 交给 DSH 阅读。实际的审查推理由 DSH 自己的模型完成，
# 所以不需要任何 LLM API Key。
#
# 用法（在仓库根目录执行）：
#   .\tools\ocr\review.ps1                      # 审查工作区改动（含未跟踪文件）
#   .\tools\ocr\review.ps1 -Commit 7582316      # 审查单个提交
#   .\tools\ocr\review.ps1 -From main -To win   # 审查分支区间
#   .\tools\ocr\review.ps1 -Background "背景"    # 补充业务背景，提升审查准确度
#   .\tools\ocr\review.ps1 -Out review.md       # 结果写入文件（默认打印到 stdout）

[CmdletBinding()]
param(
    [string]$Commit,
    [string]$From,
    [string]$To,
    [string]$Background,
    [string]$Out,
    # 每个文件最多取多少行 diff，避免超大改动把上下文撑爆
    [int]$MaxDiffLines = 300,
    # 单个文件 diff 超过这个行数就整体跳过（通常是生成文件或大重构）
    [int]$SkipFileOverLines = 2000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# git 的输出是 UTF-8，PowerShell 默认按本地代码页解码会把中文提交信息变成乱码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
# 让 git 输出英文，便于稳定解析（与 OCR 上游 CI 的做法一致）
$env:LC_ALL = 'C'

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) { throw '当前目录不在 git 仓库里。' }
$repoRoot = $repoRoot.Trim() -replace '/', '\'

# 二进制 55MB 不入库，放在 tools/ocr/bin/ 下（.gitignore 排除了这个子目录）；
# 脚本本身入库，换机器后跑一次 setup.ps1 即可重新拉取。
$exe = Join-Path $PSScriptRoot 'bin\opencodereview.exe'
if (-not (Test-Path $exe)) {
    throw "找不到 ocr 可执行文件：$exe`n请先运行 .\tools\ocr\setup.ps1 重新拉取二进制。"
}

function Invoke-Ocr {
    param([string[]]$Arguments)
    $raw = & $exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "ocr 执行失败（exit $LASTEXITCODE）：`n$($raw -join "`n")"
    }
    return ($raw -join "`n")
}

# delegate preview 的 JSON 按模式返回不同字段（commit 模式没有 merge_base），
# 而 StrictMode 下访问不存在的属性会直接抛错，所以统一走这个安全取值。
function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

# ---------- 1. 确定审查范围，取出待审文件清单 ----------
$previewArgs = @('delegate', 'preview', '--format', 'json')
if ($Commit) { $previewArgs += @('--commit', $Commit) }
elseif ($From -and $To) { $previewArgs += @('--from', $From, '--to', $To) }
elseif ($From -or $To) { throw '-From 与 -To 必须成对使用。' }
if ($Background) { $previewArgs += @('--background', $Background) }

$preview = Invoke-Ocr -Arguments $previewArgs | ConvertFrom-Json

$files = @(Get-Prop $preview 'reviewable_files' @())
if ($files.Count -eq 0) {
    Write-Host '没有需要审查的文件（改动为空，或全部被规则排除）。'
    return
}

# ---------- 2. 解析每个文件适用的规则 ----------
$allPaths = @($files | ForEach-Object { Get-Prop $_ 'path' })
$ruleArgs = @('delegate', 'rule', '--format', 'json') + $allPaths
$ruleText = ''
try {
    $ruleText = Invoke-Ocr -Arguments $ruleArgs
} catch {
    # --format json 在旧版 CLI 上不存在，退回文本输出（内容一样能用）
    $ruleArgs = @('delegate', 'rule') + $allPaths
    $ruleText = Invoke-Ocr -Arguments $ruleArgs
}

# ---------- 3. 取每个文件的 diff ----------
$mode = Get-Prop $preview 'mode'

function Get-FileDiff {
    param([string]$Path, [string]$Status)

    if ($mode -eq 'commit') {
        # --format= 去掉每个文件都会重复的提交头（SHA/Author/Date/提交信息），
        # 提交信息已经在「改动背景」里给过一份了
        return (& git show --format= --no-color (Get-Prop $preview 'commit') -- $Path 2>&1) -join "`n"
    }
    elseif ($mode -eq 'range') {
        $mb = Get-Prop $preview 'merge_base'
        $to = Get-Prop $preview 'to'
        return (& git diff --no-color "$mb..$to" -- $Path 2>&1) -join "`n"
    }
    else {
        # workspace：已跟踪文件走 diff HEAD；新增文件整份都是新代码
        if ($Status -eq 'added') {
            $full = Join-Path $repoRoot $Path
            if (Test-Path $full) { return (Get-Content $full -Raw -Encoding UTF8) }
            return ''
        }
        return (& git diff HEAD --no-color -- $Path 2>&1) -join "`n"
    }
}

$sb = [System.Text.StringBuilder]::new()
$null = $sb.AppendLine('# 本地代码审查材料')
$null = $sb.AppendLine()
$null = $sb.AppendLine("> 由 tools/ocr/review.ps1 生成（OpenCodeReview v1.12.11 delegate 模式）。")
$null = $sb.AppendLine('> 文件清单与规则来自 OCR 的确定性筛选；diff 由 git 直接取出。')
$null = $sb.AppendLine()
$null = $sb.AppendLine('## 审查范围')
$null = $sb.AppendLine()
$null = $sb.AppendLine("- 模式：``$(Get-Prop $preview 'mode')``")
$commitSha = Get-Prop $preview 'commit'
if ($commitSha) { $null = $sb.AppendLine("- 提交：``$commitSha``") }
$mb = Get-Prop $preview 'merge_base'
if ($mb) { $null = $sb.AppendLine("- merge-base：``$mb`` → ``$(Get-Prop $preview 'to')``") }
$null = $sb.AppendLine("- 待审文件：$(Get-Prop $preview 'reviewable_count' 0) 个（总改动 $(Get-Prop $preview 'total_files' 0) 个文件，+$(Get-Prop $preview 'total_insertions' 0) -$(Get-Prop $preview 'total_deletions' 0)）")
if ($Background) { $null = $sb.AppendLine("- 业务背景：$Background") }
$null = $sb.AppendLine()

# 把 OCR 给的背景（通常是提交信息）也带上，审查时很有用
$bg = Get-Prop $preview 'background'
if ($bg) {
    $null = $sb.AppendLine('## 改动背景（来自提交信息）')
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('```')
    $null = $sb.AppendLine($bg.Trim())
    $null = $sb.AppendLine('```')
    $null = $sb.AppendLine()
}

$null = $sb.AppendLine('## 待审文件清单')
$null = $sb.AppendLine()
foreach ($f in $files) {
    $null = $sb.AppendLine("- ``$(Get-Prop $f 'path')`` [$(Get-Prop $f 'status')] +$(Get-Prop $f 'insertions' 0) -$(Get-Prop $f 'deletions' 0)")
}
$null = $sb.AppendLine()

$null = $sb.AppendLine('## 适用规则')
$null = $sb.AppendLine()
$null = $sb.AppendLine($ruleText.Trim())
$null = $sb.AppendLine()

$null = $sb.AppendLine('## 改动内容')
$null = $sb.AppendLine()

$skipped = @()
$n = 0
foreach ($f in $files) {
    $n++
    $path = Get-Prop $f 'path'
    $diff = Get-FileDiff -Path $path -Status (Get-Prop $f 'status')
    $lines = @($diff -split "`n")

    if ($lines.Count -gt $SkipFileOverLines) {
        $skipped += "$path（$($lines.Count) 行，超过 $SkipFileOverLines 行上限）"
        continue
    }
    if ($lines.Count -gt $MaxDiffLines) {
        $diff = ($lines | Select-Object -First $MaxDiffLines) -join "`n"
        $diff += "`n... （已截断，原 diff 共 $($lines.Count) 行）"
    }

    $null = $sb.AppendLine("### $n/$($files.Count) ``$path``")
    $null = $sb.AppendLine()
    $null = $sb.AppendLine('```diff')
    $null = $sb.AppendLine($diff.TrimEnd())
    $null = $sb.AppendLine('```')
    $null = $sb.AppendLine()
}

if ($skipped.Count -gt 0) {
    $null = $sb.AppendLine('## 跳过的文件')
    $null = $sb.AppendLine()
    foreach ($s in $skipped) { $null = $sb.AppendLine("- $s") }
    $null = $sb.AppendLine()
}

$result = $sb.ToString()

if ($Out) {
    $outPath = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $repoRoot $Out }
    [System.IO.File]::WriteAllText($outPath, $result, [System.Text.UTF8Encoding]::new($false))
    Write-Host "已写入 $outPath"
    Write-Host "待审 $($files.Count) 个文件；接下来把该文件交给 DSH 审查即可。"
}
else {
    Write-Output $result
}
