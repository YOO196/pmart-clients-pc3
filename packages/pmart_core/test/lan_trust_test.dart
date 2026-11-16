import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

void main() {
  test('LAN 루트 CA 를 기본 신뢰 목록에 더한다 — 두 번 불러도 던지지 않는다', () {
    trustPmartLanRootCa();
    expect(trustPmartLanRootCa, returnsNormally);
  });
}
