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
