#Requires -Version 5.1
<#
.SYNOPSIS
    Erzeugt das App-Symbol src\WePrintEasy.ico (16 bis 256 Pixel) und eine
    PNG-Vorschau aus dem Logo der Website (website\public\favicon.svg).

.DESCRIPTION
    Gezeichnet wird mit GDI+ direkt in jeder Groesse (keine Skalierung eines
    grossen Bildes), damit auch 16 x 16 scharf bleibt. Bis 64 Pixel werden die
    Bilder als 32-Bit-DIB gespeichert (laedt jede .NET-/Windows-Version), 256 als PNG.

    Aufruf:  powershell -File .\tools\New-WpeIcon.ps1
#>
[CmdletBinding()]
param(
    [string]$IconPath,
    [string]$PreviewPath
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot ist in Parameter-Vorgaben von Windows PowerShell 5.1 noch leer
$root = Split-Path -Parent $PSScriptRoot
if (-not $IconPath) { $IconPath = Join-Path $root 'src\WePrintEasy.ico' }
if (-not $PreviewPath) { $PreviewPath = Join-Path $root 'docs\weprinteasy-icon.png' }
Add-Type -AssemblyName System.Drawing

$navy = [System.Drawing.Color]::FromArgb(0x00, 0x46, 0x8C)
$paper = [System.Drawing.Color]::FromArgb(0xCF, 0xE0, 0xF4)
$amber = [System.Drawing.Color]::FromArgb(0xF0, 0xA5, 0x00)
$ink = [System.Drawing.Color]::FromArgb(0x0B, 0x18, 0x30)

function New-RoundRect([single]$X, [single]$Y, [single]$W, [single]$H, [single]$R) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $R
    $p.AddArc($X, $Y, $d, $d, 180, 90)
    $p.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $p.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $p.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-WpeIconBitmap([int]$Size) {
    <# Logo im 32er-Raster (wie favicon.svg), auf $Size skaliert. #>
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    $s = [single]($Size / 32.0)
    $g.ScaleTransform($s, $s)

    $fill = { param($Path, $Color) $b = New-Object System.Drawing.SolidBrush($Color); $g.FillPath($b, $Path); $b.Dispose(); $Path.Dispose() }
    $pen = { param($Color, [single]$Width) $p = New-Object System.Drawing.Pen($Color, $Width); $p.StartCap = 'Round'; $p.EndCap = 'Round'; $p.LineJoin = 'Round'; $p }

    & $fill (New-RoundRect 0 0 32 32 8) $navy
    & $fill (New-RoundRect 9.5 6.5 11 6 1) $paper
    & $fill (New-RoundRect 5.5 11.5 21 9.5 2.6) ([System.Drawing.Color]::White)
    $out = New-RoundRect 9.75 17.25 12.5 9 1
    $b = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White); $g.FillPath($b, $out); $b.Dispose()
    $p = & $pen $navy 1.5; $g.DrawPath($p, $out); $p.Dispose(); $out.Dispose()
    if ($Size -ge 24) {
        # Textzeilen auf dem Ausdruck - bei 16/20 Pixel nur noch Rauschen
        $p = & $pen $navy 1.4
        $g.DrawLine($p, 12.5, 20.5, 19.5, 20.5)
        $g.DrawLine($p, 12.5, 23, 17, 23)
        $p.Dispose()
    }
    # Haken-Abzeichen: "das ist der Standarddrucker"
    $b = New-Object System.Drawing.SolidBrush($amber); $g.FillEllipse($b, 18.9, 2.4, 11.2, 11.2); $b.Dispose()
    $p = & $pen $navy 1.5; $g.DrawEllipse($p, 18.9, 2.4, 11.2, 11.2); $p.Dispose()
    $p = & $pen $ink 1.7
    $g.DrawLines($p, [System.Drawing.PointF[]]@(
            (New-Object System.Drawing.PointF(22.2, 8.1)),
            (New-Object System.Drawing.PointF(23.75, 9.65)),
            (New-Object System.Drawing.PointF(26.7, 6.55))))
    $p.Dispose()
    $g.Dispose()
    return $bmp
}

function ConvertTo-IconDib([System.Drawing.Bitmap]$Bitmap) {
    <# 32-Bit-DIB fuer ICO: BITMAPINFOHEADER, BGRA-Zeilen von unten nach oben, danach die AND-Maske. #>
    $w = $Bitmap.Width; $h = $Bitmap.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $Bitmap.LockBits($rect, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pixels = New-Object byte[] ($data.Stride * $h)
    [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
    $Bitmap.UnlockBits($data)

    $maskStride = [int]([Math]::Ceiling($w / 32.0) * 4)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([int]40); $bw.Write([int]$w); $bw.Write([int]($h * 2)); $bw.Write([int16]1); $bw.Write([int16]32)
    $bw.Write([int]0); $bw.Write([int]($w * $h * 4 + $maskStride * $h)); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0); $bw.Write([int]0)
    for ($y = $h - 1; $y -ge 0; $y--) { $bw.Write($pixels, $y * $data.Stride, $w * 4) }
    for ($y = $h - 1; $y -ge 0; $y--) {
        $row = New-Object byte[] $maskStride
        for ($x = 0; $x -lt $w; $x++) {
            if ($pixels[$y * $data.Stride + $x * 4 + 3] -eq 0) { $row[[int][Math]::Floor($x / 8)] = $row[[int][Math]::Floor($x / 8)] -bor (0x80 -shr ($x % 8)) }
        }
        $bw.Write($row)
    }
    $bw.Flush()
    # Komma: das Byte-Array als Ganzes zurueckgeben (sonst zerlegt die Pipeline es)
    return , $ms.ToArray()
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$images = foreach ($size in $sizes) {
    $bmp = New-WpeIconBitmap $size
    if ($size -ge 256) {
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = $ms.ToArray()
        $bmp.Save([IO.Path]::GetFullPath($PreviewPath), [System.Drawing.Imaging.ImageFormat]::Png)
    } else {
        [byte[]]$bytes = ConvertTo-IconDib $bmp
    }
    $bmp.Dispose()
    [pscustomobject]@{ Size = $size; Bytes = $bytes }
}

$fs = [IO.File]::Create([IO.Path]::GetFullPath($IconPath))
$bw = New-Object System.IO.BinaryWriter($fs)
try {
    $bw.Write([int16]0); $bw.Write([int16]1); $bw.Write([int16]$images.Count)
    $offset = 6 + 16 * $images.Count
    foreach ($i in $images) {
        $dim = if ($i.Size -ge 256) { 0 } else { $i.Size }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([int16]1); $bw.Write([int16]32); $bw.Write([int]$i.Bytes.Length); $bw.Write([int]$offset)
        $offset += $i.Bytes.Length
    }
    foreach ($i in $images) { $bw.Write($i.Bytes) }
} finally {
    $bw.Dispose()
}
Write-Host "Symbol erstellt: $([IO.Path]::GetFullPath($IconPath)) ($($sizes -join ', ') px)"
