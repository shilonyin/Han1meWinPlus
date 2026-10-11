# 按 README 的 8 张截图逐个提示，你翻页、回车即截
#
# 用法（仓库根目录）：
#   .\tools\shot\shoot-readme.ps1              # 交互式，逐个提示
#   .\tools\shot\shoot-readme.ps1 -SkipExisting # 已存在的跳过
#   .\tools\shot\shoot-readme.ps1 -Only appearance,network
#
# 每张图只做「取图」这一步，打码请自行处理（做法见 tools/shot/README.md）。

[CmdletBinding()]
param(
    [string[]]$Only,
    [switch]$SkipExisting,
    # 先输出到临时目录，检查打码后再放进 docs/screenshots
    [string]$OutDir = '.dsh_shots\readme'
)

$ErrorActionPreference = 'Stop'

$targets = @(
    @{ File = 'home.jpg';            Page = '首页（分区浏览，含首页推荐大图与下方影片卡片）' }
    @{ File = 'search.jpg';          Page = '搜索结果（输入关键词后回车，停在结果列表）' }
    @{ File = 'library.jpg';         Page = '我的（侧栏第五个「我的」，停在「喜欢的影片」页签）' }
    @{ File = 'previews.jpg';        Page = '新番预告（侧栏第二个「新番」）' }
    @{ File = 'appearance.png';      Page = '设置 → 外观 → 主题与色彩' }
    @{ File = 'player-settings.png'; Page = '设置 → 播放 → 播放设置' }
    @{ File = 'network.png';         Page = '设置 → 网络 → 网络设置' }
    @{ File = 'diagnostics.png';     Page = '设置 → 网络 → 站点可用性诊断' }
)

if ($Only) { $targets = $targets | Where-Object { $Only -contains ($_.File -split '\.')[0] } }
if (-not $targets) { throw '没有匹配的截图目标' }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host ''
Write-Host '准备就绪。请把应用窗口摆成 1280x720 逻辑尺寸，然后逐张翻页。' -ForegroundColor Cyan
Write-Host '每次回车前，先确认应用里已经是目标页面。' -ForegroundColor Cyan
Write-Host ''

$done = 0
foreach ($t in $targets) {
    $out = Join-Path $OutDir $t.File

    if ($SkipExisting -and (Test-Path $out)) {
        Write-Host "跳过（已存在）：$($t.File)" -ForegroundColor DarkGray
        continue
    }

    Write-Host ("─" * 72) -ForegroundColor DarkGray
    Write-Host "目标：$($t.File)" -ForegroundColor Yellow
    Write-Host "页面：$($t.Page)"
    $answer = Read-Host '翻好后回车截图（输入 s 跳过 / q 退出）'

    if ($answer -eq 'q') { break }
    if ($answer -eq 's') { Write-Host '已跳过' -ForegroundColor DarkGray; continue }

    & (Join-Path $PSScriptRoot 'capture.ps1') -Out $out
    $done++
}

Write-Host ''
Write-Host "本次截了 $done 张，输出在 $OutDir" -ForegroundColor Green
Write-Host '接下来：' -ForegroundColor Cyan
Write-Host '  1. 逐张打码（封面整体模糊；用户名 / 头像 / UID 模糊）'
Write-Host '  2. 确认无误后覆盖到 docs/screenshots\'
Write-Host '  3. 删掉 .dsh_shots\readme（已在 .gitignore 里，不会入库）'
