import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/catalog/domain/catalog.dart';
import 'package:customer_app/features/catalog/presentation/widgets/product_tile_card.dart';
import 'package:customer_app/l10n/gen/app_localizations.dart';
import 'package:customer_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);

  // 실서버 시험 상품처럼 긴 이름 + 배지 + 상태 문구(가장 긴 경우).
  const tile = ProductTile(
    productId: 'P-LONG',
    name: '[시험] 국산콩으로 만든 부드러운 손두부 300g 2개입 기획 묶음 상품',
    saleState: SaleState.temporarilySoldOut,
    basePrice: 12900,
    rating: 4.5,
    reviewCount: 1234,
    badge: DisplayBadge.rank,
    rank: 1,
  );

  Widget rail(double textScale, {double width = 148}) => ProviderScope(
    overrides: [envProvider.overrideWithValue(PmartEnv.mock)],
    child: MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: ProductTileCard.heightFor(context, width),
                child: const ProductTileCard(tile: tile, rail: true),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // 360dp 화면의 가로 진열 폭은 약 98(railWidthOf), 2칸 격자는 약 158.
  for (final width in [98.0, 148.0]) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('가로 진열 카드는 긴 이름·상태 문구에서도 넘치지 않는다(폭 $width, 글자 크기 $scale)', (
        t,
      ) async {
        await t.pumpWidget(rail(scale, width: width));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'RenderFlex overflow 없음');
        // 상태 문구는 사진 위에 한 번(아래 줄에 더하지 않는다 — 높이 고정).
        expect(find.text('일시품절'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('tile-status-P-LONG')),
          findsOneWidget,
        );
      });
    }
  }
}
