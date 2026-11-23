// search 0.11.0 `/search/filters` 의 영양 필터(nutrition: 저당·저나트륨·고단백 — 같은 키 여러 값은 모두 만족, AND).
// 앱은 서버가 준 필터 묶음을 그대로 그린다 — 이름·여러 개 고르기·값·건수 모두 서버 값(백엔드 알림 2026-11-23).
import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_search/pmart_api_search.dart' as sr;

void main() {
  test('영양 필터 묶음: 서버 이름·여러 개 고르기·값·건수 그대로, 토큰은 nutrition.<값>', () {
    final attrs = filtersFromContract(
      sr.GetSearchFilters200Response.fromJson({
        'attributes': [
          {
            'key': 'nutrition',
            'label': '영양',
            'multiSelect': true,
            'values': [
              {'value': 'LOW_SUGAR', 'label': '저당', 'count': 53},
              {'value': 'LOW_SODIUM', 'label': '저나트륨', 'count': 52},
              {'value': 'HIGH_PROTEIN', 'label': '고단백', 'count': 34},
            ],
          },
        ],
      }),
    );
    final n = attrs.single;
    expect((n.key, n.label, n.multiSelect), ('nutrition', '영양', true));
    expect([for (final v in n.values) (v.label, v.count)], [
      ('저당', 53),
      ('저나트륨', 52),
      ('고단백', 34),
    ]);
    expect(n.token(n.values.first), 'nutrition.LOW_SUGAR');
  });
}
