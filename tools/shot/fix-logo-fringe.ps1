# 去掉锁标图里的白边瑕疵
#
# 症状：红色圆角方块的边缘有一条淡粉色描边，在浅色底上尤其明显
#   （右侧圆角实测 R=246 G=180 B=200，主色是 R=237 G=80 B=126，
#    G 高出 100，等于混入了大量白）。
#
# 成因：原图在白底上制作，抠成透明时边缘与白色做了插值。
#
# 判据经过两轮修正，务必留意这两个坑：
#   1. 不能只按颜色判断——图标内部「白色 H 与红底的交界」抗锯齿后同样是浅粉。
#   2. 不能全图扫——右侧蓝色文字「Han1meWinPlus」的 G 值天然在 140 上下，
#      它的抗锯齿像素共 16491 个，会全部被误判（实测踩过）。
#   所以这里限定在红色图标区域（靠主色自动圈定），再叠加「靠近外轮廓」。
#
# 用法（仓库根目录）：
#   .\tools\shot\fix-logo-fringe.ps1 -Path docs\logo-lockup.png -DryRun   # 先看会改多少
#   .\tools\shot\fix-logo-fringe.ps1 -Path docs\logo-lockup.png

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Out,
    [switch]$DryRun,
    # G 通道超过主色 G 多少判定为偏淡（主色 G=80）
    [int]$GreenTolerance = 25,
    [int]$MinAlpha = 8,
    # 判定「外轮廓」的搜索半径：该距离内存在全透明像素才算外边缘
    [int]$EdgeRadius = 3
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$src = (Resolve-Path $Path).Path
if (-not $Out) { $Out = $src }

$img = New-Object System.Drawing.Bitmap $src
$w = $img.Width; $h = $img.Height

# 先整图读进数组，避免循环里反复 GetPixel
$px = New-Object 'System.Drawing.Color[,]' $w, $h
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) { $px[$x, $y] = $img.GetPixel($x, $y) }
}

# 主色 = 不透明像素里出现次数最多的颜色
$hist = @{}
for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
        $p = $px[$x, $y]
        if ($p.A -lt 250) { continue }
        $key = "$($p.R),$($p.G),$($p.B)"
        if ($hist.ContainsKey($key)) { $hist[$key]++ } else { $hist[$key] = 1 }
    }
}
$dominant = ($hist.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
$dr, $dg, $db = $dominant -split ',' | ForEach-Object { [int]$_ }
Write-Host "主色: R=$dr G=$dg B=$db" -ForegroundColor Cyan

# 圈定图标区域：主色的 R 明显高于 G/B（红色），据此找出它所在的连续块。
# 注意：右边缘那条淡边（实测 R=246 G=180 B=200）的 G 被抬高，跟主色差值超阈值，
# 会被严格判据漏掉，导致图标范围切在淡边左侧、反而修不到它。
# 所以这里用「R 明显大于 G」这个更宽松的红色判据。
$colHasRed = New-Object 'bool[]' $w
for ($x = 0; $x -lt $w; $x++) {
    $n = 0
    for ($y = 0; $y -lt $h; $y++) {
        $p = $px[$x, $y]
        if ($p.A -lt 200) { continue }
        # 红色系：R 显著高于 G（蓝字、白字都不满足）
        if ($p.R -gt $p.G + 60) { $n++ }
    }
    $colHasRed[$x] = $n -gt ($h * 0.10)
}
# 取最长的一段连续红色列作为图标范围
$iconX0 = -1; $iconX1 = -1; $bestLen = 0; $runStart = -1
for ($x = 0; $x -le $w; $x++) {
    $inRun = ($x -lt $w) -and $colHasRed[$x]
    if ($inRun -and $runStart -lt 0) { $runStart = $x }
    if (-not $inRun -and $runStart -ge 0) {
        $len = $x - $runStart
        if ($len -gt $bestLen) { $bestLen = $len; $iconX0 = $runStart; $iconX1 = $x - 1 }
        $runStart = -1
    }
}
if ($iconX0 -lt 0) { throw '没能圈定红色图标区域，请检查图片' }
# 边界外扩一点，确保紧贴透明区的淡边也纳入处理
$iconX0 = [Math]::Max(0, $iconX0 - 2)
$iconX1 = [Math]::Min($w - 1, $iconX1 + 4)
Write-Host "图标横向范围: x=$iconX0..$iconX1" -ForegroundColor Cyan

function Test-NearTransparent {
    param([int]$cx, [int]$cy, [int]$radius)
    for ($dy = -$radius; $dy -le $radius; $dy++) {
        for ($dx = -$radius; $dx -le $radius; $dx++) {
            $nx = $cx + $dx; $ny = $cy + $dy
            if ($nx -lt 0 -or $ny -lt 0 -or $nx -ge $w -or $ny -ge $h) { continue }
            if ($px[$nx, $ny].A -le 2) { return $true }
        }
    }
    return $false
}

$fixed = 0; $total = 0; $skippedInner = 0
for ($y = 0; $y -lt $h; $y++) {
    for ($x = $iconX0; $x -le $iconX1; $x++) {
        $p = $px[$x, $y]
        if ($p.A -le $MinAlpha) { continue }
        $total++

        $whiteness = $p.G - $dg
        if ($whiteness -le $GreenTolerance) { continue }

        if (-not (Test-NearTransparent -cx $x -cy $y -radius $EdgeRadius)) {
            $skippedInner++
            continue
        }

        # 注意：这条淡边并不都是「半透明过渡」，实测右边缘是 A=236 的**实心**像素
        # 从顶贯穿到底（G 恒定 180）。所以这里不按 alpha 加权，直接按白化程度
        # 向主色收敛，alpha 原样保留。
        $share = [Math]::Min(1.0, $whiteness / (255.0 - $dg))
        $nr = [Math]::Round($p.R - ($p.R - $dr) * $share)
        $ng = [Math]::Round($p.G - ($p.G - $dg) * $share)
        $nb = [Math]::Round($p.B - ($p.B - $db) * $share)

        # 白化严重的直接归到主色，避免残留淡边
        if ($p.G -ge 170) { $nr = $dr; $ng = $dg; $nb = $db }

        $nr = [int][Math]::Min(255, [Math]::Max(0, $nr))
        $ng = [int][Math]::Min(255, [Math]::Max(0, $ng))
        $nb = [int][Math]::Min(255, [Math]::Max(0, $nb))

        if ($nr -ne $p.R -or $ng -ne $p.G -or $nb -ne $p.B) {
            $fixed++
            if (-not $DryRun) {
                $img.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($p.A, $nr, $ng, $nb))
            }
        }
    }
}

Write-Host "图标区不透明像素: $total" -ForegroundColor Yellow
Write-Host "  偏淡且在外轮廓 -> 修正: $fixed" -ForegroundColor Yellow
Write-Host "  偏淡但在内部（白 H 交界）-> 跳过: $skippedInner" -ForegroundColor DarkGray

if ($DryRun) {
    $img.Dispose()
    Write-Host '（DryRun，未写入）' -ForegroundColor DarkGray
    return
}

$tmp = "$Out.tmp.png"
$img.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
Move-Item $tmp $Out -Force
Write-Host "已写入 $Out" -ForegroundColor Green



