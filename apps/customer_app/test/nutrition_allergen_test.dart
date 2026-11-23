// 상품 상세 영양·알레르기 — 초안 14 B(사용자 2026-11-23 "B해줘"), product-content 0.6.0.
// 모르는 것은 "정보 없음"(알레르기 "없음"·0 으로 보이지 않는다), 값은 서버 그대로.
import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';
import 'package:customer_app/features/catalog/presentation/product_detail_screen.dart'
    show NutritionAllergenSection;
import 'package:customer_app/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_product_content/pmart_api_product_content.dart'
    as pc;
import 'package:pmart_ui/pmart_ui.dart';

void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> show(
    WidgetTester t, {
    ProductNutrition? nutrition,
    ProductAllergens? allergens,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: PmartCustomerTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NutritionAllergenSection(
              nutrition: nutrition,
              allergens: allergens,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  test('계약 → 앱: basisUnit ML·빈 칸 null, 알레르기 원문 공백은 없음', () {
    final p = productFromContract(
      pc.ProductContent.fromJson({
        'productId': 'P-1',
        'name': 'a',
        'contentVersion': 1,
        'productVersion': 1,
        'options': <Object?>[],
        'nutrition': {
          'basisUnit': 'ML',
          'energyKcal': 62,
          'sodiumMg': null,
        },
        'allergens': {
          'contains': <String>[],
          'mayContain': ['땅콩'],
          'text': '  ',
        },
      }),
    );
    expect(p.nutrition!.basis, NutritionBasis.milliliter);
    expect((p.nutrition!.energyKcal, p.nutrition!.sodiumMg), (62, null));
    expect(p.allergens!.mayContain, ['땅콩']);
    expect(p.allergens!.text, isNull);
    expect(p.allergens!.unknown, isFalse);
  });

  testWidgets('둘 다 있음: 분홍 알레르기 칸(함유·같은 시설·원문) + 영양 표, 빈 칸은 "정보 없음"', (t) async {
    await show(
      t,
      nutrition: const ProductNutrition(
        basis: NutritionBasis.gram,
        energyKcal: 95,
        sodiumMg: 1250,
        sugarsG: null,
        proteinG: 9.2,
        fatG: 3.8,
      ),
      allergens: const ProductAllergens(
        contains: ['우유'],
        mayContain: ['대두', '밀'],
        text: '우유 함유',
      ),
    );
    expect(key('allergen-box'), findsOneWidget);
    expect(
      find.descendant(of: key('allergen-contains'), matching: find.text('우유')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('allergen-may-contain'),
        matching: find.text('밀'),
      ),
      findsOneWidget,
    );
    expect(find.text('표시사항 원문: 우유 함유'), findsOneWidget);
    expect(find.text('100g당'), findsOneWidget);
    String row(int i) => t.widget<Text>(key('nutrition-row-$i')).data!;
    expect([for (var i = 0; i < 5; i++) row(i)], [
      '95kcal',
      '1,250mg',
      '정보 없음',
      '9.2g',
      '3.8g',
    ]);
  });

  testWidgets('함유는 비고 같은 시설만 있으면 함유 "정보 없음"', (t) async {
    await show(t, allergens: const ProductAllergens(mayContain: ['땅콩']));
    expect(key('allergen-contains-none'), findsOneWidget);
    expect(key('allergen-may-contain'), findsOneWidget);
    expect(key('nutrition-unknown'), findsOneWidget);
  });

  testWidgets('둘 다 모르면 "정보 없음" 안내 — "알레르기 없음"으로 보이지 않는다', (t) async {
    await show(t, allergens: const ProductAllergens());
    expect(key('allergen-box'), findsNothing);
    expect(key('allergen-unknown'), findsOneWidget);
    expect(find.text('알레르기 정보가 없어요 · 표시사항을 꼭 확인해 주세요'), findsOneWidget);
    expect(key('nutrition-unknown'), findsOneWidget);
    expect(find.textContaining('없음'), findsNothing);
  });
}
