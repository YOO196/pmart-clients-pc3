/// 스캔한 값이 어떤 코드인지(채번 지침 5장 — `docs/architecture/identifiers.md`).
/// 형식 검사는 "잘못 찍었는지" 안내용이다. 존재·상태·권한은 서버가 판정한다.
library;

final _shelf = RegExp(r'^[ACF]-[A-Z][0-9]-[0-9]{2}-[1-9]-[0-9]{2}$');
final _other = RegExp(r'^(RCV|PAK|QRT|DSP|RTN|DSL|CRT)-[ACF]-[0-9]{2}$');
final _sku = RegExp(r'^[EB]-[0-9]{8}$');

/// MFC 위치 코드(선반 `C-S1-03-2-04` 또는 `RCV-C-01` 같은 기타 구역).
bool isMfcLocation(String code) {
  final c = code.trim();
  return _shelf.hasMatch(c) || _other.hasMatch(c);
}

/// 카트 위치(`CRT-{온도}-{번호}`).
bool isCartLocation(String code) {
  final c = code.trim();
  return _other.hasMatch(c) && c.startsWith('CRT-');
}

bool isSku(String code) => _sku.hasMatch(code.trim());
