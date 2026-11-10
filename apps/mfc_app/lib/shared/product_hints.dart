import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import 'providers.dart';

/// 상품 보관 온도대(상품 정보 값). 작업자가 고르지 않는다.
enum StorageZone {
  ambient('AMBIENT'),
  chilled('CHILLED'),
  frozen('FROZEN');

  const StorageZone(this.wire);

  final String wire;

  static StorageZone? fromWire(String? w) =>
      values.where((z) => z.wire == w).firstOrNull;
}

/// 화면에서 물건을 확인하는 데 필요한 상품 정보(이름·바코드·온도대).
@immutable
class ProductHint {
  const ProductHint({required this.name, this.barcode, this.zone});

  final String name;
  final String? barcode;
  final StorageZone? zone;
}

/// 이동·실사·적치·패킹 응답에 상품명·바코드·온도대가 없다(BR-52 R19 1·2).
/// 회신 전까지 목만 값을 갖고, 실서버에서는 모른다(null) — 그러면 상품 확인을 건너뛴다.
abstract interface class ProductHints {
  ProductHint? bySku(String sku);

  /// 바코드로 찾기 — (SKU, 정보). 모르면 null.
  (String, ProductHint)? byBarcode(String barcode);
}

final class NoProductHints implements ProductHints {
  const NoProductHints();

  @override
  ProductHint? bySku(String sku) => null;

  @override
  (String, ProductHint)? byBarcode(String barcode) => null;
}

/// 목 상품 정보 — 입고·피킹·패킹 목 데이터와 같은 상품.
final class MockProductHints implements ProductHints {
  const MockProductHints();

  static const catalog = <String, ProductHint>{
    'E-00000001': ProductHint(
      name: '서울우유 1L',
      barcode: '8801115114154',
      zone: StorageZone.chilled,
    ),
    'E-00000002': ProductHint(
      name: '그릭요거트 플레인 400g',
      barcode: '8801115220015',
      zone: StorageZone.chilled,
    ),
    'E-00000005': ProductHint(
      name: '감자칩 오리지널 110g',
      barcode: '8801019606557',
      zone: StorageZone.ambient,
    ),
    'E-00000011': ProductHint(
      name: '국산콩 두부 300g',
      barcode: '8801007001101',
      zone: StorageZone.chilled,
    ),
    'E-00000012': ProductHint(
      name: '무항생제 계란 10구',
      barcode: '8809001002112',
      zone: StorageZone.chilled,
    ),
    'E-00000013': ProductHint(
      name: '슬라이스 치즈 180g',
      barcode: '8801115330013',
      zone: StorageZone.chilled,
    ),
    'E-00000014': ProductHint(
      name: '오렌지주스 1L',
      barcode: '8801056004014',
      zone: StorageZone.chilled,
    ),
    'E-00000015': ProductHint(
      name: '닭가슴살 샐러드',
      barcode: '8809002003115',
      zone: StorageZone.chilled,
    ),
    'E-00000021': ProductHint(
      name: '생수 2L',
      barcode: '8801056021021',
      zone: StorageZone.ambient,
    ),
    'E-00000022': ProductHint(
      name: '컵라면 소컵 65g',
      barcode: '8801043022022',
      zone: StorageZone.ambient,
    ),
    'E-00000031': ProductHint(
      name: '냉동 왕만두 1kg',
      barcode: '8801007310014',
      zone: StorageZone.frozen,
    ),
  };

  @override
  ProductHint? bySku(String sku) => catalog[sku];

  @override
  (String, ProductHint)? byBarcode(String barcode) {
    for (final e in catalog.entries) {
      if (e.value.barcode == barcode) return (e.key, e.value);
    }
    return null;
  }
}

final productHintsProvider = Provider<ProductHints>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => const MockProductHints(),
    PmartEnv.local => const NoProductHints(),
  },
);
