# 把新截的图规格化成 README 用的尺寸与格式
#
# 用法（仓库根目录）：
#   .\tools\shot\prepare-readme.ps1 -Src 'C:\Users\24243\Desktop\新建文件夹'
#
# 做三件事：
#   1. 按内容对应到 README 的文件名
#   2. 缩放到 1280x720（比例已有，个别非 16:9 的居中裁剪）
#   3. 按现有约定转格式：内容页 .jpg、设置页 .png
#
# 输出到 .dsh_shots\readme，由你核对后再覆盖到 docs/screenshots。

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Src,
    [string]$OutDir = '.dsh_shots\readme',
    # 内容页用 jpg 体积更小；设置页文字多，用 png 保持锐利
    [int]$JpegQuality = 88
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 源文件名里的时间戳 -> README 目标名。按截图内容与时间顺序对应。
$map = @(
    @{ Match = '11-49-27'; Out = 'home.jpg' }             # 首页
    @{ Match = '11-49-59'; Out = 'search.jpg' }           # 搜索 / 分类列表
    @{ Match = '11-50-39'; Out = 'library.jpg' }          # 我的
    @{ Match = '11-52-14'; Out = 'previews.jpg' }         # 新番预告
    @{ Match = '11-52-33'; Out = 'appearance.png' }       # 外观
    @{ Match = '11-52-47'; Out = 'player-settings.png' }  # 播放
    @{ Match = '11-59-38'; Out = 'network.png' }          # 网络（IP 打码后重新导出）
    @{ Match = '11-53-38'; Out = 'diagnostics.png' }      # 诊断
)

if (-not (Test-Path $Src)) { throw "源目录不存在：$Src" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = Get-ChildItem $Src -File | Where-Object { $_.Extension -match '^\.(png|jpg|jpeg)$' }

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq 'image/jpeg' }
$jpegParams = New-Object System.Drawing.Imaging.EncoderParameters 1
$jpegParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, [long]$JpegQuality)

$report = @()
foreach ($m in $map) {
    $srcFile = $files | Where-Object { $_.Name -like "*$($m.Match)*" } | Select-Object -First 1
    if (-not $srcFile) {
        Write-Warning "没找到匹配 $($m.Match) 的源文件，跳过 $($m.Out)"
        continue
    }

    $img = [System.Drawing.Image]::FromFile($srcFile.FullName)
    try {
        $targetW = 1280; $targetH = 720
        $targetRatio = $targetW / $targetH
        $srcRatio = $img.Width / $img.Height

        # 比例不符时居中裁剪，避免拉伸变形
        $cropW = $img.Width; $cropH = $img.Height
        $cropX = 0; $cropY = 0
        if ([math]::Abs($srcRatio - $targetRatio) -gt 0.002) {
            if ($srcRatio -gt $targetRatio) {
                $cropW = [int][math]::Round($img.Height * $targetRatio)
                $cropX = [int](($img.Width - $cropW) / 2)
            } else {
                $cropH = [int][math]::Round($img.Width / $targetRatio)
                $cropY = [int](($img.Height - $cropH) / 2)
            }
            Write-Host "  居中裁剪 $($srcFile.Name)：$($img.Width)x$($img.Height) -> ${cropW}x${cropH}" -ForegroundColor DarkYellow
        }

        $bmp = New-Object System.Drawing.Bitmap $targetW, $targetH
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $destRect = New-Object System.Drawing.Rectangle 0, 0, $targetW, $targetH
        $srcRect = New-Object System.Drawing.Rectangle $cropX, $cropY, $cropW, $cropH
        $g.DrawImage($img, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()

        $outPath = Join-Path $OutDir $m.Out
        if ([System.IO.Path]::GetExtension($m.Out).ToLowerInvariant() -in @('.jpg', '.jpeg')) {
            $bmp.Save($outPath, $jpegCodec, $jpegParams)
        } else {
            $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        $bmp.Dispose()

        $report += [PSCustomObject]@{
            目标   = $m.Out
            源文件 = $srcFile.Name
            '输出KB' = [math]::Round((Get-Item $outPath).Length / 1KB)
        }
    } finally {
        $img.Dispose()
    }
}

Write-Host ''
$report | Format-Table -AutoSize
Write-Host "输出目录：$OutDir" -ForegroundColor Green
Write-Host '核对无误后覆盖到 docs\screenshots\，再删掉本目录。' -ForegroundColor Cyan
