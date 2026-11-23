# Flutter 시험을 파일 하나씩 돌리며 메모리를 잰다(메모리 새는 시험 파일 찾기, 사용자 지시 2026-11-23).
# - 한 번에 한 파일, 그 파일의 시험 프로세스(자식 flutter_tester 등)만 잰다 — 다른 세션의 시험은 건드리지 않는다.
# - 프로세스 트리 Private 메모리 합이 -MaxGB 를 넘거나 -TimeoutSec 이 지나면 그 트리만 끄고 다음 파일로 간다.
# - PC 실메모리 남은 양이 -MinFreeGB 아래면 시작하지 않고 기다렸다가, 오래 모자라면 멈춘다.
# 사용(앱/패키지 폴더에서): powershell -File ..\..\tools\flutter_test_mem.ps1 [-Path test] [-MaxGB 3] [-TimeoutSec 300]
# 결과: build\test-mem.csv (file, status, peakGB, seconds) — status = pass·fail·killed-mem·killed-time
param(
  [string]$Path = 'test',
  [double]$MaxGB = 3,
  [int]$TimeoutSec = 300,
  [double]$MinFreeGB = 4,
  [string]$Out = 'build\test-mem.csv'
)
$ErrorActionPreference = 'Stop'

function Get-FreeGB { [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1) }

function Get-Tree([int]$RootId) {
  $all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId
  $ids = @($RootId); $i = 0
  while ($i -lt $ids.Count) {
    $ids += @($all | Where-Object { $_.ParentProcessId -eq $ids[$i] } | ForEach-Object { [int]$_.ProcessId })
    $i++
  }
  $ids
}

function Get-TreeGB([int[]]$Ids) {
  $sum = 0
  foreach ($id in $Ids) { $p = Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p) { $sum += $p.PrivateMemorySize64 } }
  [math]::Round($sum / 1GB, 2)
}

New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
'file,status,peakGB,seconds' | Set-Content -Encoding utf8 $Out
$files = Get-ChildItem -Recurse -Filter '*_test.dart' $Path | Sort-Object FullName
$n = 0
foreach ($f in $files) {
  $n++
  $rel = Resolve-Path -Relative $f.FullName
  $waited = 0
  while ((Get-FreeGB) -lt $MinFreeGB) {
    if ($waited -ge 600) { Write-Host "실메모리 $MinFreeGB GB 미만 10분 — 멈춤"; exit 2 }
    Start-Sleep 10; $waited += 10
  }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $proc = Start-Process cmd -ArgumentList '/c', "flutter test --concurrency=1 `"$rel`" > NUL 2>&1" -PassThru -WindowStyle Hidden
  $peak = 0; $status = $null
  while (-not $proc.HasExited) {
    $gb = Get-TreeGB (Get-Tree $proc.Id)
    if ($gb -gt $peak) { $peak = $gb }
    if ($gb -gt $MaxGB) { $status = 'killed-mem' }
    elseif ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) { $status = 'killed-time' }
    if ($status) { & taskkill /T /F /PID $proc.Id 2>&1 | Out-Null; break }
    Start-Sleep -Milliseconds 1000
  }
  $proc.WaitForExit()
  if (-not $status) { $status = if ($proc.ExitCode -eq 0) { 'pass' } else { 'fail' } }
  $sec = [math]::Round($sw.Elapsed.TotalSeconds)
  "$rel,$status,$peak,$sec" | Add-Content -Encoding utf8 $Out
  Write-Host ("[{0}/{1}] {2} {3} {4}GB {5}s" -f $n, $files.Count, $status, $rel, $peak, $sec)
}
Write-Host "끝 — $Out"
