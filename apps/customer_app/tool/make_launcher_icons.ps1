# 고객앱 런처 아이콘(바로픽) 만들기 — 원본: apps/customer_app/branding/app_icon.png (정사각, 둥근 모서리 투명)
# 실행: pwsh apps/customer_app/tool/make_launcher_icons.ps1  (저장소 루트에서)
# 만드는 것:
#   mipmap-*/ic_launcher.png            — 옛 아이콘(원본을 그대로 줄임)
#   mipmap-*/ic_launcher_foreground.png — 적응형 아이콘 앞면(108dp, 그라데이션 위에 원본을 68dp 로, 가장자리는 부드럽게 섞음)
#   mipmap-anydpi-v26/ic_launcher.xml   — 적응형 아이콘(앞면 + 같은 그라데이션 배경색)
# 새 패키지 없이 System.Drawing 만 쓴다.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$app = Split-Path -Parent $PSScriptRoot
$src = Join-Path $app 'branding/app_icon.png'
$res = Join-Path $app 'android/app/src/main/res'

function Resize([System.Drawing.Image]$img, [int]$size) {
  $out = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($out)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.DrawImage($img, 0, 0, $size, $size)
  $g.Dispose()
  return $out
}

$img = [System.Drawing.Bitmap]::new($src)

# 1) 옛 아이콘
$legacy = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($d in $legacy.Keys) {
  $b = Resize $img $legacy[$d]
  $b.Save((Join-Path $res "mipmap-$d/ic_launcher.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $b.Dispose()
}

# 2) 적응형 앞면 — 432px(= 108dp × 4) 에서 그리고 줄인다
$N = 432; $S = 272  # 원본을 68dp 로(원형 마스크에서도 손잡이·바퀴가 잘리지 않게)
$tl = @(165, 53, 247); $br = @(120, 20, 230)  # 원본 가장자리 색(왼쪽 위 → 오른쪽 아래)
$scaled = Resize $img $S
$fg = [System.Drawing.Bitmap]::new($N, $N, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$off = ($N - $S) / 2
$R = $S * 0.46; $F = $S * 0.08; $c = $N / 2
for ($y = 0; $y -lt $N; $y++) {
  for ($x = 0; $x -lt $N; $x++) {
    $t = ($x + $y) / (2 * ($N - 1))
    $bg = @(0, 1, 2 | ForEach-Object { $tl[$_] + ($br[$_] - $tl[$_]) * $t })
    $dist = [Math]::Sqrt(($x - $c) * ($x - $c) + ($y - $c) * ($y - $c))
    $w = [Math]::Min(1, [Math]::Max(0, ($R - $dist) / $F))
    $r = $bg[0]; $gg = $bg[1]; $bb = $bg[2]
    if ($w -gt 0) {
      $sx = [Math]::Min($S - 1, [Math]::Max(0, [int]($x - $off)))
      $sy = [Math]::Min($S - 1, [Math]::Max(0, [int]($y - $off)))
      $p = $scaled.GetPixel($sx, $sy)
      $a = $w * $p.A / 255
      $r = $p.R * $a + $r * (1 - $a); $gg = $p.G * $a + $gg * (1 - $a); $bb = $p.B * $a + $bb * (1 - $a)
    }
    $fg.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, [int]$r, [int]$gg, [int]$bb))
  }
}
$adaptive = @{ 'mdpi' = 108; 'hdpi' = 162; 'xhdpi' = 216; 'xxhdpi' = 324; 'xxxhdpi' = 432 }
foreach ($d in $adaptive.Keys) {
  $b = Resize $fg $adaptive[$d]
  $b.Save((Join-Path $res "mipmap-$d/ic_launcher_foreground.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $b.Dispose()
}
$fg.Dispose(); $scaled.Dispose(); $img.Dispose()

# 3) 적응형 아이콘 xml (앞면이 불투명이라 배경색은 가장자리 평균색)
$any = Join-Path $res 'mipmap-anydpi-v26'
New-Item -ItemType Directory -Force $any | Out-Null
@'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'@ | Set-Content -NoNewline -Encoding utf8NoBOM (Join-Path $any 'ic_launcher.xml')
@'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#8E25EE</color>
</resources>
'@ | Set-Content -NoNewline -Encoding utf8NoBOM (Join-Path $res 'values/ic_launcher_background.xml')
'done'
