# Draws the app icon with GDI+ and writes:
#   windows/runner/resources/app_icon.ico   (16..256 px, PNG frames)
#   android/app/src/main/res/mipmap-*/ic_launcher.png
#   ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png
#     (full-bleed square, no transparency: iOS rounds the corners itself and
#      shows transparent pixels as black)
#   tool/icon_preview.png                   (256 px, for a quick look)
# Usage: powershell -ExecutionPolicy Bypass -File tool\make_icon.ps1
# Keep this file ASCII: Windows PowerShell 5.1 reads BOM-less UTF-8 as GBK.

param([string]$Root = (Split-Path -Parent $PSScriptRoot))

Add-Type -AssemblyName System.Drawing

function New-RoundedRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Teal rounded square, white airplane, "EN" under it (text only from 48 px up;
# at 16-40 px the plane alone reads better).
# -FullBleed: square edge to edge without alpha (for iOS).
function New-IconBitmap([int]$size, [switch]$FullBleed) {
    $format = if ($FullBleed) { [System.Drawing.Imaging.PixelFormat]::Format24bppRgb } else { [System.Drawing.Imaging.PixelFormat]::Format32bppArgb }
    $bmp = New-Object System.Drawing.Bitmap($size, $size, $format)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $top = [System.Drawing.Color]::FromArgb(255, 0, 105, 92)
    $bottom = [System.Drawing.Color]::FromArgb(255, 38, 166, 154)
    if ($FullBleed) {
        # gradient rect a bit larger than the image: GDI+ draws a dark seam on the first row/column otherwise
        $rect = New-Object System.Drawing.RectangleF(-2, -2, ($size + 4), ($size + 4))
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, [single]60)
        $g.FillRectangle($brush, $rect)
    } else {
        $g.Clear([System.Drawing.Color]::Transparent)
        $pad = [Math]::Max(0.5, $size * 0.04)
        $side = $size - 2 * $pad
        $rect = New-Object System.Drawing.RectangleF($pad, $pad, $side, $side)
        $path = New-RoundedRect $pad $pad $side $side ($size * 0.22)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, [single]60)
        $g.FillPath($brush, $path)
    }

    $white = [System.Drawing.Brushes]::White
    $center = New-Object System.Drawing.StringFormat
    $center.Alignment = [System.Drawing.StringAlignment]::Center
    $center.LineAlignment = [System.Drawing.StringAlignment]::Center
    $pixel = [System.Drawing.GraphicsUnit]::Pixel

    $withText = $size -ge 48
    $planeSize = if ($withText) { $size * 0.40 } else { $size * 0.56 }
    $planeFont = New-Object System.Drawing.Font('Segoe MDL2 Assets', [single]$planeSize, [System.Drawing.FontStyle]::Regular, $pixel)
    $planeBox = if ($withText) {
        New-Object System.Drawing.RectangleF(0, ($size * 0.10), $size, ($size * 0.50))
    } else {
        New-Object System.Drawing.RectangleF(0, 0, $size, $size)
    }
    $g.DrawString([string][char]0xEB4C, $planeFont, $white, $planeBox, $center)

    if ($withText) {
        $textFont = New-Object System.Drawing.Font('Segoe UI', [single]($size * 0.25), [System.Drawing.FontStyle]::Bold, $pixel)
        $textBox = New-Object System.Drawing.RectangleF(0, ($size * 0.56), $size, ($size * 0.34))
        $g.DrawString('EN', $textFont, $white, $textBox, $center)
    }
    $g.Dispose()
    return $bmp
}

function Get-PngBytes([System.Drawing.Bitmap]$bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    return , $ms.ToArray()
}

# ---- Windows .ico (PNG-compressed frames, supported since Vista) ----
$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$frames = @()
foreach ($s in $sizes) {
    $bmp = New-IconBitmap $s
    $frames += , (Get-PngBytes $bmp)
    $bmp.Dispose()
}
$icoPath = Join-Path $Root 'windows\runner\resources\app_icon.ico'
$fs = [System.IO.File]::Create($icoPath)
$w = New-Object System.IO.BinaryWriter($fs)
$w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([UInt16]1); $w.Write([UInt16]32)
    $w.Write([UInt32]$frames[$i].Length); $w.Write([UInt32]$offset)
    $offset += $frames[$i].Length
}
foreach ($f in $frames) { $w.Write($f) }
$w.Close()
Write-Output "ico: $icoPath ($offset bytes)"

# ---- Android launcher icons ----
$android = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($k in $android.Keys) {
    $out = Join-Path $Root "android\app\src\main\res\mipmap-$k\ic_launcher.png"
    $bmp = New-IconBitmap $android[$k]
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
Write-Output 'android mipmaps written'

# ---- iOS app icons: overwrite every Icon-App-<size>@<scale>x.png in the icon set ----
$iosDir = Join-Path $Root 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
if (Test-Path $iosDir) {
    $count = 0
    foreach ($file in Get-ChildItem $iosDir -Filter 'Icon-App-*.png') {
        if ($file.Name -match '^Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$') {
            $px = [int][Math]::Round([double]$Matches[1] * [int]$Matches[2])
            $bmp = New-IconBitmap $px -FullBleed
            $bmp.Save($file.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            $count++
        }
    }
    Write-Output "ios icons written: $count"
}

$preview = New-IconBitmap 256
$preview.Save((Join-Path $Root 'tool\icon_preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$small = New-IconBitmap 32
$small.Save((Join-Path $Root 'tool\icon_preview_32.png'), [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output 'preview written'
