import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/features/profile/domain/profile.dart';

void main() {
  // 고객앱은 본인만 보므로 번호를 가리지 않는다(사용자 2026-11-26).
  test('화면 번호는 가리지 않은 번호를 하이픈으로, 없으면 서버가 가린 값', () {
    const full = Profile(
      accountId: 'a',
      version: 1,
      phone: '01012345678',
      phoneMasked: '010-****-5678',
    );
    expect(full.phoneDisplay, '010-1234-5678');
    const onlyMasked = Profile(
      accountId: 'a',
      version: 1,
      phoneMasked: '010-****-5678',
    );
    expect(onlyMasked.phoneDisplay, '010-****-5678');
    const none = Profile(accountId: 'a', version: 1);
    expect(none.phoneDisplay, isNull);
  });
}
