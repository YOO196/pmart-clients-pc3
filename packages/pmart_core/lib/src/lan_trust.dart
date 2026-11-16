import 'dart:convert';
import 'dart:io';

/// LAN 개발용 사설 루트 CA(공개 인증서 — 비밀값 아님). 백엔드 ADR-0057, 원본
/// `pmart-backend/deploy/lan/tls/pmart-lan-root-ca.crt`.
/// - CN=PMart LAN Dev Root CA 2026, 만료 2036-11-09
/// - SHA-256 88:2B:5A:45:CA:2D:75:60:6D:D1:26:6B:B8:77:70:A4:10:0E:0B:F9:C4:42:96:BD:58:03:FC:7D:8A:DB:3D:37
/// CA 가 바뀌면 이 값을 원본으로 바꾼다.
const _pmartLanRootCaPem = '''
-----BEGIN CERTIFICATE-----
MIIEbjCCAtagAwIBAgIUTYt7okZ8mTcxWRf8ATEpxwtztOUwDQYJKoZIhvcNAQEL
BQAwPTEWMBQGA1UECgwNUE1hcnQgTEFOIERldjEjMCEGA1UEAwwaUE1hcnQgTEFO
IERldiBSb290IENBIDIwMjYwHhcNMjYxMTEyMDkzMjQyWhcNMzYxMTA5MDkzMjQy
WjA9MRYwFAYDVQQKDA1QTWFydCBMQU4gRGV2MSMwIQYDVQQDDBpQTWFydCBMQU4g
RGV2IFJvb3QgQ0EgMjAyNjCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGB
ALUwRr9C06O1yBXIrw8VJs6g/KkNNS2anBw0zt0ZoZYqMuwZ69yUHMjTMgojiQzD
2CEB6k8/gWw90nTBPtQxLaqidEDKgmmSts264US2LnBoSyMFyoDcJ/qL9Dg48AK6
qjoZIHjvknpGBAZwqb+vasIIDzfRdygSZGYn2GZ+sDv/iX4in8h2QbLtcYFCwI1Y
ZM0xcuH6T7DCtEE5mLeaKx8GAd3ltan5sas18G6t5rE9zZnuWz5B8YyeeG4MGDu3
sRyIhchqyPqSXcj6Q0yopQFirfctYziTGdiAjRFiMBOFi+oOatplWdadFGeDmi6b
2PeGSgp4frMLCA6QrNbYUyzfi2NfQhPJwxIhJCqfgsaUajPSPHRznPwmJe+DKZsE
fSggb2/qtXO4UhOuAfWhRZ4x3x+T96sktuOLvO8wRv1LTBARLK8iha9pFVlVbDx7
gjesUdeIrWQetVQuRVJNVLcIWC4g1rEQkdgY58B61qw1zfTb6Z82zl4hZnhUBCFf
8wIDAQABo2YwZDAfBgNVHSMEGDAWgBTBt9iMiqdDMeZnUABza3mDSCubaTASBgNV
HRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBBjAdBgNVHQ4EFgQUwbfYjIqn
QzHmZ1AAc2t5g0grm2kwDQYJKoZIhvcNAQELBQADggGBAHbye+YCRvBoCM/5Kgxw
XNBGMwaedpgjdVKeoL2e+PJ3KSMX23QRz5jerOU365BY/WuKTXgejEa/Zas+S4zU
bJPSM55AMFTubQrGxyoQzDnCsamiP07EOzd95b3RbeyLMe05MTjpDuUBCULDnwPu
pxu22ZP8Hw74zgNbsQ5ClEl8vexanNbGWX4z9AZGyUwvZXlPvNgLhm/utcelreMK
qCFz4IFXdmBL09LiVCMlWoeBDD6NrTGjswVuEolk7GWxnM7um2pltqCD3ATa3dcm
flWL+zJeD/rBNwEpUGNM4u/vphThqq80OmMj/SRxM5HAmGASaU5Mt8LKhUBaA29W
r7wtXIpsdCCEZfSVlzJaiTukUS38PV2TwqCFzxopYrmf8ULmU7eWZFXErpKYQ6Ms
cE5TgXmvLY41HPkJDK9F0ZvcWQNOJqpLKvrKjf+jfz9qpNwmYrju5QUCKquEnfHm
zLoVClVLqplri2DWRXynHWygNlZAMWE0brv3VVRbY55KOA==
-----END CERTIFICATE-----
''';

/// Dart HTTP(Dio·`Image.network` 이 쓰는 `HttpClient`)가 LAN HTTPS 게이트웨이(`https://192.168.0.40:8443`)를
/// 믿게 한다. 안드로이드의 `network_security_config`·기기에 설치한 CA 는 Dart HTTP 에 적용되지 않는다.
///
/// **lan/debug 빌드에서만 부른다**(ADR-0057 T6 — 운영 빌드에는 넣지 않는다). 부르는 쪽이 `kReleaseMode` 로 막는다.
/// 기본 신뢰 목록(시스템 CA)은 그대로 두고 이 CA 하나를 더한다. 두 번 불러도 된다.
void trustPmartLanRootCa() {
  try {
    SecurityContext.defaultContext.setTrustedCertificatesBytes(
      utf8.encode(_pmartLanRootCaPem),
    );
  } on TlsException {
    // 이미 더했다(같은 인증서를 두 번 넣으면 BoringSSL 이 거절한다).
  }
}