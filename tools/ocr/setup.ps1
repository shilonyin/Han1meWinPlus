# 拉取本地代码审查所需的 ocr CLI（OpenCodeReview 官方预编译二进制）
#
# 二进制有 55MB，不入库，所以换机器或清理过 tools/ocr/bin/ 之后需要跑一次这个脚本。
# 装好后用 .\tools\ocr\review.ps1 做审查 —— 走 delegate 模式，不需要任何 LLM API Key。
#
# 用法：
#   .\tools\ocr\setup.ps1                 # 装默认版本 v1.12.11
#   .\tools\ocr\setup.ps1 -Version 1.12.11

[CmdletBinding()]
param(
    # 与 CI 工作流里 pin 的版本保持一致，避免本地和 CI 行为漂移
    [string]$Version = '1.12.11'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) { throw '当前目录不在 git 仓库里。' }
$repoRoot = $repoRoot.Trim() -replace '/', '\'

$dest = Join-Path $PSScriptRoot 'bin'
$exe = Join-Path $dest 'opencodereview.exe'
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# 平台包名固定为 win32-x64：这个 fork 只维护 Windows。
# 官方 npm 包通过 optionalDependencies 分发各平台二进制，这里直接取 Windows 那一份。
$pkg = '@alibaba-group/ocr-win32-x64'
$tmp = Join-Path $repoRoot 'tools\ocr\.dl'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

Write-Host "正在拉取 $pkg@$Version ..."

# --ignore-scripts：npm 的 postinstall 会 spawn 子进程，在受限环境里会被拦，
# 而我们只需要解包出来的二进制，不需要它跑安装脚本。
# --cache 指到仓库内，避免污染全局 npm 缓存。
#
# 整个下载流程包在 try/finally 里：npm 失败（版本号写错、断网）时若把 .dl 留在
# 仓库里，它会出现在 git status 里，看起来像一份没写完的改动。
try {
    Push-Location $tmp
    try {
        npm init -y 2>&1 | Out-Null
        npm install "$pkg@$Version" --no-audit --no-fund --ignore-scripts --cache (Join-Path $tmp 'npm-cache') 2>&1 |
            Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
    }
    finally {
        Pop-Location
    }

    $src = Join-Path $tmp "node_modules\$pkg\bin\opencodereview.exe"
    if (-not (Test-Path $src)) {
        throw "解包后找不到二进制：$src"
    }

    Copy-Item $src $exe -Force
}
finally {
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
}

$ver = (& $exe version 2>&1 | Select-Object -First 1)
Write-Host ''
Write-Host "已安装：$ver"
Write-Host "位置：  $exe"
Write-Host ''
Write-Host '现在可以用：'
Write-Host '  .\tools\ocr\review.ps1              # 审查工作区改动'
Write-Host '  .\tools\ocr\review.ps1 -Commit HEAD # 审查最新提交'
