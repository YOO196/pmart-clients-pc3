import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_product_content/pmart_api_product_content.dart' as pc;
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';
import 'package:customer_app/shared/providers.dart';

void main() {
  group('진열 정리', () {
    test('판매중지는 빠지고 일시품절은 뒤로 간다', () {
      const tiles = [
        ProductTile(
          productId: 'a',
          name: 'a',
          saleState: SaleState.temporarilySoldOut,
        ),
        ProductTile(productId: 'b', name: 'b', saleState: SaleState.onSale),
        ProductTile(
          productId: 'c',
          name: 'c',
          saleState: SaleState.saleStopped,
        ),
        ProductTile(productId: 'd', name: 'd', saleState: SaleState.unknown),
      ];
      expect(arrangeForDisplay(tiles).map((t) => t.productId), ['b', 'd', 'a']);
    });

    test('취급하지 않거나 판매 상태를 모르면 담기를 권하지 않는다', () {
      const notCarried = ProductTile(
        productId: 'a',
        name: 'a',
        saleState: SaleState.onSale,
        carried: false,
      );
      const unknownCarried = ProductTile(
        productId: 'b',
        name: 'b',
        saleState: SaleState.onSale,
      );
      expect(notCarried.canOfferAdd, isFalse);
      expect(unknownCarried.canOfferAdd, isTrue);
    });
  });

  group('홈 변환', () {
    test('영역 상태가 UNAVAILABLE 이거나 없으면 그 영역만 실패로 본다', () {
      final home = homeFromContract(
        sf.HomeLayout.fromJson({
          'layoutVersion': 1,
          'sections': [
            {
              'sectionId': 'ok',
              'title': 'A',
              'state': 'OK',
              'items': <Object?>[],
            },
            {'sectionId': 'bad', 'title': 'B', 'state': 'UNAVAILABLE'},
            {'sectionId': 'none', 'title': 'C'},
          ],
        }),
      );
      expect(home.sections.map((s) => s.available), [true, false, false]);
      expect(home.hasUnavailableSection, isTrue);
    });

    test('상품 ID 가 없는 진열 상품은 계약 위반이다(빈 값으로 메우지 않음)', () {
      expect(
        () => homeFromContract(
          sf.HomeLayout.fromJson({
            'layoutVersion': 1,
            'sections': [
              {
                'sectionId': 's',
                'state': 'OK',
                'items': [
                  {'name': 'x'},
                ],
              },
            ],
          }),
        ),
        throwsA(isA<ContractViolationFailure>()),
      );
    });
  });

  group('상품 상세 변환', () {
    test('이미지를 역할별로 나누고 sortOrder 순서로 둔다', () {
      String u(String id) => '/api/v1/content-images/$id';
      final p = productFromContract(
        pc.ProductContent.fromJson({
          'productId': 'x',
          'name': 'x',
          'mainImage': {'imageId': 'M', 'url': u('M'), 'role': 'MAIN'},
          'images': [
            {
              'imageId': 'D2',
              'url': u('D2'),
              'role': 'DESCRIPTION',
              'sortOrder': 2,
            },
            {'imageId': 'T0', 'url': u('T0'), 'role': 'DETAIL', 'sortOrder': 0},
            {'imageId': 'M', 'url': u('M'), 'role': 'MAIN', 'sortOrder': 0},
            {
              'imageId': 'D0',
              'url': u('D0'),
              'role': 'DESCRIPTION',
              'sortOrder': 0,
            },
            {
              'imageId': 'D1',
              'url': u('D1'),
              'role': 'DESCRIPTION',
              'sortOrder': 1,
            },
            {'imageId': 'N', 'url': u('N'), 'sortOrder': 0}, // 역할 없음
          ],
          'options': const <Object>[],
        }),
      );
      expect(p.mainImageUrl, u('M'));
      expect(p.descriptionImageUrls, [u('D0'), u('D1'), u('D2')]);
      expect(p.detailImageUrls, [u('T0')]);
    });

    test('mainImage 가 없으면 images 의 MAIN 을 대표로 쓴다', () {
      final p = productFromContract(
        pc.ProductContent.fromJson({
          'productId': 'x',
          'name': 'x',
          'images': [
            {
              'imageId': 'M',
              'url': '/api/v1/content-images/M',
              'role': 'MAIN',
              'sortOrder': 0,
            },
          ],
          'options': const <Object>[],
        }),
      );
      expect(p.mainImageUrl, '/api/v1/content-images/M');
      expect(p.descriptionImageUrls, isEmpty);
    });

    test('평점 집계가 없으면 null 이다(0점·0건 아님)', () {
      final p = productFromContract(
        pc.ProductContent.fromJson(
          MockCatalogRepository.productJson(
            mockProducts.firstWhere((p) => p.productId == 'P-0006'),
          ),
        ),
      );
      expect(p.rating, isNull);
    });

    test(
      '상품 정보 칸(product-content 0.9.0 BR-100 R1) — 원산지·소비기한·고시 표, 빈 값은 없음',
      () {
        final json = MockCatalogRepository.productJson(
          mockProducts.firstWhere((p) => p.productId == 'P-0006'),
        );
        final p = productFromContract(
          pc.ProductContent.fromJson({
            ...json,
            'origin': '국산',
            'expiryGuide': ' ',
            'legalInfo': [
              {'label': '원산지', 'value': '국산'},
              {'label': null, 'value': '냉장 보관'},
            ],
          }),
        );
        expect(p.origin, '국산');
        expect(p.expiryGuide, isNull);
        expect(p.legalInfo, [
          (label: '원산지', value: '국산'),
          (label: null, value: '냉장 보관'),
        ]);
        // 옛 응답(칸 없음)은 null — 화면이 notices 줄로 대신한다.
        final old = productFromContract(pc.ProductContent.fromJson(json));
        expect(old.origin, isNull);
        expect(old.legalInfo, isNull);
      },
    );

    test('일시품절 옵션은 담기를 권하지 않는다', () {
      final p = productFromContract(
        pc.ProductContent.fromJson(
          MockCatalogRepository.productJson(
            mockProducts.firstWhere((p) => p.productId == 'P-0004'),
          ),
        ),
      );
      expect(p.options.single.availability, Availability.soldOut);
      expect(p.options.single.canOfferAdd, isFalse);
    });

    test('라벨 없는 단일 SKU 옵션에 SKU 코드를 라벨로 쓰지 않는다', () {
      final p = productFromContract(
        pc.ProductContent.fromJson({
          'productId': 'x',
          'name': 'x',
          'options': [
            {
              'sku': 'E-00000001',
              'saleState': 'ON_SALE',
              'availability': {'carried': true, 'state': 'AVAILABLE'},
            },
          ],
        }),
      );
      expect(p.options.single.label, isNull);
      expect(p.options.single.canOfferAdd, isTrue);
    });

    test('가용 조회가 UNKNOWN 이면 품절도 가능도 아니다', () {
      final p = productFromContract(
        pc.ProductContent.fromJson({
          'productId': 'x',
          'name': 'x',
          'options': [
            {
              'sku': 'E-00000099',
              'saleState': 'ON_SALE',
              'availability': {'carried': true, 'state': 'UNKNOWN'},
            },
          ],
        }),
      );
      expect(p.options.single.availability, Availability.unknown);
      expect(p.options.single.canOfferAdd, isFalse);
    });

    test('재고가 붙지 않았으면(센터 모름) 품절이 아니라 "주소 없음" — 담기는 막는다', () {
      final p = productFromContract(
        pc.ProductContent.fromJson({
          'productId': 'x',
          'name': 'x',
          'options': [
            {'sku': 'E-00000098', 'saleState': 'ON_SALE'},
          ],
        }),
      );
      expect(p.options.single.availability, Availability.noCenter);
      expect(p.options.single.canOfferAdd, isFalse);
      expect(p.cannotBuyReason, CannotBuyReason.noCenter);
    });

    test('담을 수 없는 까닭: 조회 실패·배달 안 함·품절을 가른다, 담을 옵션이 있으면 없음', () {
      ProductDetail of(List<Map<String, Object?>> availabilities) =>
          productFromContract(
            pc.ProductContent.fromJson({
              'productId': 'x',
              'name': 'x',
              'options': [
                for (final (i, a) in availabilities.indexed)
                  {
                    'sku': 'E-0000010$i',
                    'saleState': 'ON_SALE',
                    'availability': a,
                  },
              ],
            }),
          );
      expect(
        of([
          {'carried': true, 'state': 'UNKNOWN'},
        ]).cannotBuyReason,
        CannotBuyReason.stockUnknown,
      );
      expect(
        of([
          {'carried': false, 'state': 'UNKNOWN'},
        ]).cannotBuyReason,
        CannotBuyReason.notCarried,
      );
      expect(
        of([
          {'carried': true, 'state': 'SOLD_OUT'},
          {'carried': true, 'state': 'SOLD_OUT'},
        ]).cannotBuyReason,
        CannotBuyReason.soldOut,
      );
      // 하나는 품절, 하나는 조회 실패 — 다 팔렸다고 하지 않는다.
      expect(
        of([
          {'carried': true, 'state': 'SOLD_OUT'},
          {'carried': true, 'state': 'UNKNOWN'},
        ]).cannotBuyReason,
        CannotBuyReason.stockUnknown,
      );
      expect(
        of([
          {'carried': true, 'state': 'SOLD_OUT'},
          {'carried': true, 'state': 'AVAILABLE'},
        ]).cannotBuyReason,
        isNull,
      );
    });
  });

  group('실서버 상세 가격 (BR-36)', () {
    const content = {
      'productId': 'PRD-1',
      'name': '고추장짜글이',
      'options': [
        {
          'sku': 'E-00000017',
          'saleState': 'ON_SALE',
          'price': null,
          'availability': {'carried': true, 'state': 'AVAILABLE'},
        },
        {
          'sku': 'B-00000099',
          'saleState': 'ON_SALE',
          'availability': {'carried': true, 'state': 'AVAILABLE'},
        },
      ],
    };

    ApiCatalogRepository repoWith(FakeAdapter adapter) => ApiCatalogRepository(
      createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      ),
    );

    test('옵션 가격이 비어 오면 GET /prices?skus= 로 채우고, 미설정은 판매 불가', () async {
      final adapter = FakeAdapter((options, _) async {
        if (options.uri.path == '/api/v1/prices') {
          expect(options.uri.queryParametersAll['skus'], [
            'E-00000017,B-00000099',
          ]);
          return const FakeReply(
            200,
            body: {
              'items': [
                {
                  'sku': 'E-00000017',
                  'basePrice': 5480,
                  'priceVersion': 1,
                  'effectiveFrom': '2026-10-30T13:04:45Z',
                },
              ],
              'notSet': ['B-00000099'],
            },
          );
        }
        return const FakeReply(200, body: content);
      });

      final p = await repoWith(adapter).product('PRD-1', mfcId: 'MFC-SEED-01');

      final each = p.options.singleWhere((o) => o.sku == 'E-00000017');
      expect(each.basePrice, 5480);
      expect(each.priceVersion, 1);
      expect(each.canOfferAdd, isTrue);
      final bundle = p.options.singleWhere((o) => o.sku == 'B-00000099');
      expect(bundle.basePrice, isNull);
      expect(bundle.priceNotSet, isTrue);
      expect(bundle.canOfferAdd, isFalse);
    });

    test('가격 조회가 실패해도 상세는 보이고 가격은 확인 중으로 남는다', () async {
      final adapter = FakeAdapter((options, _) async {
        if (options.uri.path == '/api/v1/prices') {
          return const FakeReply.transport(DioExceptionType.connectionTimeout);
        }
        return const FakeReply(200, body: content);
      });

      final p = await repoWith(adapter).product('PRD-1');

      expect(p.name, '고추장짜글이');
      expect(p.options.map((o) => o.basePrice), everyElement(isNull));
      expect(p.options.map((o) => o.priceNotSet), everyElement(isFalse));
    });

    test('상세에 가격이 이미 있으면 가격 API 를 부르지 않는다', () async {
      final adapter = FakeAdapter((options, _) async {
        expect(options.uri.path, isNot('/api/v1/prices'));
        return FakeReply(
          200,
          body: MockCatalogRepository.productJson(
            mockProducts.firstWhere((p) => p.productId == 'P-0001'),
          ),
        );
      });

      final p = await repoWith(adapter).product('P-0001');

      expect(p.options.map((o) => o.basePrice), everyElement(isNotNull));
    });
  });

  test('실서버 구현이 GET /storefront/home 을 생성 클라이언트로 읽는다', () async {
    late Uri requested;
    final adapter = FakeAdapter((options, _) async {
      requested = options.uri;
      return FakeReply(200, body: MockCatalogRepository().homeJson());
    });
    final repo = ApiCatalogRepository(
      createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      ),
    );

    final home = await repo.home(mfcId: 'MFC-MOCK-01');

    expect(requested.path, '/api/v1/storefront/home');
    expect(requested.queryParameters['mfcId'], 'MFC-MOCK-01');
    expect(home.layoutVersion, 7);
    expect(
      home.sections.firstWhere((s) => s.sectionId == 'S-RANK').items,
      isNot(contains(predicate<ProductTile>((t) => t.productId == 'P-0008'))),
    );
  });
}
