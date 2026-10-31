import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/address/data/address_repository.dart';
import 'package:customer_app/features/address/domain/address.dart';
import 'package:customer_app/shared/providers.dart';

void main() {
  late FakeAdapter adapter;

  ApiAddressRepository repo() {
    adapter = FakeAdapter(
      (_, _) async => const FakeReply(
        201,
        body: {
          'addressId': 'addr-1',
          'version': 1,
          'roadAddress': '[시험] 부산 부산진구 서면역 부근',
          'detailAddress': '1층',
          'receiverName': '홍길동',
          'receiverPhone': '01000000000',
          'serviceability': {'state': 'SERVICEABLE', 'mfcId': 'MFC-SEED-01'},
        },
      ),
    );
    return ApiAddressRepository(
      createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      ),
      DeviceIdProvider(MemoryKeyValueStore()),
    );
  }

  const base = AddressDraft(
    roadAddress: '[시험] 부산 부산진구 서면역 부근',
    detailAddress: '1층',
    receiverName: '홍길동',
    receiverPhone: '01000000000',
  );

  test('시험 좌표를 넣으면 주소 추가 본문에 geo 가 실린다(BR-29 전 개발용)', () async {
    final saved = await repo().add(
      const AddressDraft(
        roadAddress: '[시험] 부산 부산진구 서면역 부근',
        detailAddress: '1층',
        receiverName: '홍길동',
        receiverPhone: '01000000000',
        geo: DevTestGeo.seomyeon,
      ),
      key: IdempotencyKey('k-1'),
    );

    final body = jsonDecode(
      adapter.requests.single.data as String,
    ) as Map<String, dynamic>;
    expect(body['geo'], {'lat': 35.1578, 'lng': 129.0597});
    expect(saved.serviceability, Serviceability.serviceable);
    expect(saved.mfcId, 'MFC-SEED-01');
  });

  test('좌표가 없으면 geo 를 보내지 않는다(추측 좌표를 만들지 않는다)', () async {
    await repo().add(base, key: IdempotencyKey('k-2'));

    final body = jsonDecode(
      adapter.requests.single.data as String,
    ) as Map<String, dynamic>;
    expect(body.containsKey('geo'), isFalse);
  });
}
