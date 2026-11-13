# LAN 루트 CA 를 USB 로 연결한 Android 기기(PDA·폰)에 넣고, 설치 화면을 연다.
#
# 왜: 직원 로그인 화면(Keycloak, https://192.168.0.40:8443/iam/…)은 LAN 사설 CA 인증서를 쓴다(백엔드 ADR-0057).
#     기기에 이 CA 가 없으면 로그인 창(Chrome Custom Tab)이 "연결이 비공개로 설정되어 있지 않습니다"에서 멈춘다.
# 한계: Android 11 부터 CA 인증서는 사람이 설정 화면에서 직접 설치해야 한다(adb 로 대신 눌러 줄 수 없다).
#       이 스크립트는 파일을 기기의 Download 폴더에 넣고 보안 설정 화면을 여는 데까지만 한다.
#
# 실행(저장소 루트에서):  pwsh tools/install_lan_ca.ps1            # 기기가 하나일 때
#                         pwsh tools/install_lan_ca.ps1 -Serial <기기 일련번호>
# 필요: 기기의 USB 디버깅 켜기, ../pmart-backend 를 옆 폴더에 받아 둘 것(인증서는 공개 파일 — 개인키 아님).
param(
  [string]$Serial = '',
  [string]$CaFile = ''
)
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
if (-not $CaFile) { $CaFile = Join-Path (Split-Path -Parent $repo) 'pmart-backend\deploy\lan\tls\pmart-lan-root-ca.crt' }
if (-not (Test-Path $CaFile)) { Write-Error "CA 파일이 없다: $CaFile  (pmart-backend 를 옆 폴더에 받고 git pull)"; exit 1 }

$adb = (Get-Command adb -ErrorAction SilentlyContinue)?.Source
if (-not $adb) {
  foreach ($p in @("$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe", "$env:ANDROID_HOME\platform-tools\adb.exe", "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe")) {
    if ($p -and (Test-Path $p)) { $adb = $p; break }
  }
}
if (-not $adb) { Write-Error 'adb 를 찾지 못했다(Android SDK platform-tools).'; exit 1 }

$devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' } | ForEach-Object { ($_ -split '\t')[0] })
if (-not $Serial) {
  if ($devices.Count -eq 0) {
    Write-Host '연결된 기기가 없다. 확인: USB 케이블(충전 전용 아님), 기기의 "USB 디버깅" 켜기, 기기 화면의 "USB 디버깅 허용" 누르기.'
    & $adb devices
    exit 2
  }
  if ($devices.Count -gt 1) { Write-Host "기기가 여러 대다. -Serial 로 고른다: $($devices -join ', ')"; exit 2 }
  $Serial = $devices[0]
}

$model = (& $adb -s $Serial shell getprop ro.product.model).Trim()
$release = (& $adb -s $Serial shell getprop ro.build.version.release).Trim()
$target = '/sdcard/Download/pmart-lan-root-ca.crt'
& $adb -s $Serial push $CaFile $target | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error '기기에 파일을 넣지 못했다.'; exit 1 }
# 같은 인증서의 DER(이진) 사본도 넣는다 — 글자(PEM) 파일을 "설치되지 않았습니다"로 거절하는 기기가 있다.
$pem = Get-Content -Raw $CaFile
$body = ($pem -replace '-----BEGIN CERTIFICATE-----', '' -replace '-----END CERTIFICATE-----', '' -replace '\s', '')
$der = Join-Path ([IO.Path]::GetTempPath()) 'pmart-lan-root-ca-der.cer'
[IO.File]::WriteAllBytes($der, [Convert]::FromBase64String($body))
& $adb -s $Serial push $der '/sdcard/Download/pmart-lan-root-ca-der.cer' | Out-Null
Remove-Item $der -ErrorAction SilentlyContinue
& $adb -s $Serial shell am start -a android.settings.SECURITY_SETTINGS | Out-Null

Write-Host "기기: $model (Android $release, $Serial)"
Write-Host "넣은 파일: 기기의 Download/pmart-lan-root-ca.crt, pmart-lan-root-ca-der.cer(같은 인증서의 다른 형식)"
Write-Host ''
Write-Host '기기에서 이어서 한다(보안 설정 화면을 열어 뒀다 — 메뉴 이름은 기기마다 조금 다르다):'
Write-Host '  1. 보안(또는 "보안 및 개인정보 보호" → "기타 보안 설정")'
Write-Host '  2. 암호화 및 사용자 인증 정보 → 인증서 설치(또는 "기기 저장공간에서 설치")'
Write-Host '  3. "CA 인증서" → 경고에서 "무시하고 설치" → 화면 잠금 확인'
Write-Host '  4. Download 폴더의 pmart-lan-root-ca.crt 선택'
Write-Host '     "설치되지 않았습니다"가 뜨면: 3번에서 "CA 인증서"를 골랐는지 본다("VPN 및 앱 사용자 인증서"·"Wi-Fi 인증서"는 개인 키가 없어 거절된다).'
Write-Host '     "CA 인증서"였는데도 거절되면 같은 폴더의 pmart-lan-root-ca-der.cer 를 고른다.'
Write-Host ''
Write-Host '확인: 기기의 Chrome 에서 https://192.168.0.40:8443/iam/realms/pmart-staff/.well-known/openid-configuration 을 열어'
Write-Host '      경고 없이 글자(JSON)가 보이면 된 것이다. 그 뒤 앱에서 다시 로그인한다.'
Write-Host '      설치된 것은 설정 → 보안 → 신뢰할 수 있는 사용자 인증 정보 → "사용자" 탭의 "PMart LAN Dev Root CA 2026".'
