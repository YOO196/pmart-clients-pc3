import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/features/reviews/presentation/reviews_screens.dart';
import 'package:customer_app/l10n/gen/app_localizations.dart';

/// 리뷰 사진 크게 보기 — 전체 화면, 옆으로 넘기기, 닫기, 못 그리는 사진은 안내.
void main() {
  Widget host(List<String?> urls, {int initial = 0}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('ko'),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          key: const ValueKey('open'),
          onPressed: () =>
              openReviewPhotoViewer(context, urls, initial: initial),
          child: const Text('open'),
        ),
      ),
    ),
  );

  testWidgets('누른 사진부터 열고, 옆으로 넘기면 번호가 바뀌고, 닫으면 돌아온다', (t) async {
    await t.pumpWidget(host(const [null, null, null], initial: 1));
    await t.tap(find.byKey(const ValueKey('open')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('review-photo-viewer')), findsOneWidget);
    expect(
      t
          .widget<Text>(find.byKey(const ValueKey('review-photo-viewer-count')))
          .data,
      '2 / 3',
    );
    await t.drag(find.byType(PageView), const Offset(-600, 0));
    await t.pumpAndSettle();
    expect(
      t
          .widget<Text>(find.byKey(const ValueKey('review-photo-viewer-count')))
          .data,
      '3 / 3',
    );

    await t.tap(find.byKey(const ValueKey('review-photo-viewer-close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-photo-viewer')), findsNothing);
  });

  testWidgets('그릴 수 없는 사진은 빈 화면이 아니라 "불러오지 못했어요", 한 장이어도 "1 / 1"(레퍼런스)', (
    t,
  ) async {
    await t.pumpWidget(host(const [null]));
    await t.tap(find.byKey(const ValueKey('open')));
    await t.pumpAndSettle();
    expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
    expect(
      t
          .widget<Text>(find.byKey(const ValueKey('review-photo-viewer-count')))
          .data,
      '1 / 1',
    );
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}
