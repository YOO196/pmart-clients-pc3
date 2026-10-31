import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/shared/providers.dart';

void main() {
  group('이미지 주소', () {
    test('서버의 상대 경로(/api/v1/content-images/…)는 게이트웨이 출처를 붙인다', () {
      expect(
        resolveImageUrl(
          '/api/v1/content-images/IMG-1',
          'http://192.168.0.40:8080',
        ),
        'http://192.168.0.40:8080/api/v1/content-images/IMG-1',
      );
    });

    test('완전한 주소는 그대로, 비었거나 출처를 모르는 상대 경로는 자리표시(null)', () {
      expect(
        resolveImageUrl('https://cdn.example/a.png', null),
        'https://cdn.example/a.png',
      );
      expect(resolveImageUrl(null, 'http://h'), isNull);
      expect(resolveImageUrl('', 'http://h'), isNull);
      expect(resolveImageUrl('/api/v1/content-images/IMG-1', null), isNull);
      expect(resolveImageUrl('content-images/IMG-1', 'http://h'), isNull);
    });

    test('실서버는 API 기본 주소의 출처(경로 /api/v1 제외)를 쓴다', () {
      final c = ProviderContainer(
        overrides: [
          envProvider.overrideWithValue(PmartEnv.local),
          apiBaseUrlProvider.overrideWithValue(
            'http://192.168.0.40:8080/api/v1',
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(imageOriginProvider), 'http://192.168.0.40:8080');
    });
  });
}
