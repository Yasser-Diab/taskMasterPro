$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$sourcePath = Join-Path $root "media\app-logo\TaskMaster_Pro_Black_Gold_Transparent_main-logo.png"
$brandBg = [System.Drawing.Color]::FromArgb(255, 11, 11, 12)

function New-DirectoryForFile([string]$Path) {
  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

function New-BrandBitmap(
  [System.Drawing.Image]$Source,
  [int]$Width,
  [int]$Height,
  [Nullable[System.Drawing.Color]]$Background,
  [double]$Padding,
  [switch]$Monochrome
) {
  $bitmap = New-Object System.Drawing.Bitmap $Width, $Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.Clear([System.Drawing.Color]::Transparent)
  if ($Background.HasValue) {
    $graphics.Clear($Background.Value)
  }
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

  $maxWidth = [Math]::Max(1, [int]($Width * (1 - (2 * $Padding))))
  $maxHeight = [Math]::Max(1, [int]($Height * (1 - (2 * $Padding))))
  $scale = [Math]::Min($maxWidth / $Source.Width, $maxHeight / $Source.Height)
  $targetWidth = [int]($Source.Width * $scale)
  $targetHeight = [int]($Source.Height * $scale)
  $x = [int](($Width - $targetWidth) / 2)
  $y = [int](($Height - $targetHeight) / 2)
  $graphics.DrawImage($Source, $x, $y, $targetWidth, $targetHeight)
  $graphics.Dispose()

  if ($Monochrome) {
    for ($pixelY = 0; $pixelY -lt $bitmap.Height; $pixelY++) {
      for ($pixelX = 0; $pixelX -lt $bitmap.Width; $pixelX++) {
        $pixel = $bitmap.GetPixel($pixelX, $pixelY)
        if ($pixel.A -lt 18) {
          $bitmap.SetPixel($pixelX, $pixelY, [System.Drawing.Color]::Transparent)
        } else {
          $bitmap.SetPixel($pixelX, $pixelY, [System.Drawing.Color]::FromArgb($pixel.A, 255, 255, 255))
        }
      }
    }
  }

  return $bitmap
}

function Save-Png(
  [System.Drawing.Image]$Image,
  [string]$Path
) {
  New-DirectoryForFile $Path
  $Image.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Save-Bmp(
  [System.Drawing.Image]$Image,
  [string]$Path
) {
  New-DirectoryForFile $Path
  $Image.Save($Path, [System.Drawing.Imaging.ImageFormat]::Bmp)
}

function Get-PngBytes([System.Drawing.Image]$Image) {
  $stream = New-Object System.IO.MemoryStream
  $Image.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
  $bytes = $stream.ToArray()
  $stream.Dispose()
  return $bytes
}

function Write-UInt16LE([System.IO.BinaryWriter]$Writer, [int]$Value) {
  $Writer.Write([UInt16]$Value)
}

function Write-UInt32LE([System.IO.BinaryWriter]$Writer, [long]$Value) {
  $Writer.Write([UInt32]$Value)
}

function Save-Ico(
  [System.Drawing.Image]$Source,
  [string]$Path,
  [int[]]$Sizes
) {
  New-DirectoryForFile $Path
  $images = New-Object System.Collections.Generic.List[byte[]]
  foreach ($size in $Sizes) {
    $iconBitmap = New-BrandBitmap -Source $Source -Width $size -Height $size -Background $brandBg -Padding 0.08
    $images.Add((Get-PngBytes $iconBitmap))
    $iconBitmap.Dispose()
  }

  $file = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
  $writer = New-Object System.IO.BinaryWriter $file
  Write-UInt16LE $writer 0
  Write-UInt16LE $writer 1
  Write-UInt16LE $writer $Sizes.Count

  $offset = 6 + (16 * $Sizes.Count)
  for ($i = 0; $i -lt $Sizes.Count; $i++) {
    $size = $Sizes[$i]
    $bytes = $images[$i]
    $sizeByte = $size
    if ($size -ge 256) {
      $sizeByte = 0
    }
    $writer.Write([byte]$sizeByte)
    $writer.Write([byte]$sizeByte)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    Write-UInt16LE $writer 1
    Write-UInt16LE $writer 32
    Write-UInt32LE $writer $bytes.Length
    Write-UInt32LE $writer $offset
    $offset += $bytes.Length
  }

  foreach ($bytes in $images) {
    $writer.Write($bytes)
  }
  $writer.Dispose()
  $file.Dispose()
}

$source = [System.Drawing.Image]::FromFile($sourcePath)
try {
  Save-Ico -Source $source -Path (Join-Path $root "windows\runner\resources\app_icon.ico") -Sizes @(16, 24, 32, 48, 64, 128, 256)

  $androidIconSizes = @{
    "mipmap-mdpi" = 48
    "mipmap-hdpi" = 72
    "mipmap-xhdpi" = 96
    "mipmap-xxhdpi" = 144
    "mipmap-xxxhdpi" = 192
  }

  foreach ($density in $androidIconSizes.Keys) {
    $size = $androidIconSizes[$density]
    $dir = Join-Path $root "android\app\src\main\res\$density"
    $launcher = New-BrandBitmap -Source $source -Width $size -Height $size -Background $brandBg -Padding 0.08
    Save-Png $launcher (Join-Path $dir "ic_launcher.png")
    Save-Png $launcher (Join-Path $dir "ic_launcher_round.png")
    $launcher.Dispose()

    $foregroundSize = [int]($size * 2.25)
    $foreground = New-BrandBitmap -Source $source -Width $foregroundSize -Height $foregroundSize -Background ([Nullable[System.Drawing.Color]]$null) -Padding 0.22
    Save-Png $foreground (Join-Path $dir "ic_launcher_foreground.png")
    $foreground.Dispose()

    $mono = New-BrandBitmap -Source $source -Width $foregroundSize -Height $foregroundSize -Background ([Nullable[System.Drawing.Color]]$null) -Padding 0.22 -Monochrome
    Save-Png $mono (Join-Path $dir "ic_launcher_monochrome.png")
    $mono.Dispose()
  }

  $notificationSizes = @{
    "drawable-mdpi" = 24
    "drawable-hdpi" = 36
    "drawable-xhdpi" = 48
    "drawable-xxhdpi" = 72
    "drawable-xxxhdpi" = 96
  }

  foreach ($density in $notificationSizes.Keys) {
    $size = $notificationSizes[$density]
    $notification = New-BrandBitmap -Source $source -Width $size -Height $size -Background ([Nullable[System.Drawing.Color]]$null) -Padding 0.06 -Monochrome
    Save-Png $notification (Join-Path $root "android\app\src\main\res\$density\ic_notification.png")
    $notification.Dispose()
  }

  $splash = New-BrandBitmap -Source $source -Width 960 -Height 480 -Background ([Nullable[System.Drawing.Color]]$null) -Padding 0.08
  Save-Png $splash (Join-Path $root "android\app\src\main\res\drawable-nodpi\splash_logo.png")
  $splash.Dispose()

  $sidebar = New-BrandBitmap -Source $source -Width 164 -Height 314 -Background $brandBg -Padding 0.10
  Save-Bmp $sidebar (Join-Path $root "installer\assets\wizard-sidebar.bmp")
  $sidebar.Dispose()

  $small = New-BrandBitmap -Source $source -Width 55 -Height 55 -Background $brandBg -Padding 0.08
  Save-Bmp $small (Join-Path $root "installer\assets\wizard-small.bmp")
  $small.Dispose()
} finally {
  $source.Dispose()
}

Write-Host "Generated TaskMaster Pro branding assets from $sourcePath"
