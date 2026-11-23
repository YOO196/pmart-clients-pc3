import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/reviews/domain/reviews.dart';
import 'package:customer_app/features/reviews/presentation/reviews_controller.dart';
import 'package:customer_app/features/support/data/mock_inquiries_repository.dart';
import 'package:customer_app/features/support/presentation/inquiry_controller.dart';

import 'support/app_harness.dart';

/// 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// 문의 사진(case 0.14.0)·만족도(0.15.0)·닫기(0.19.0) — 목 저장소 기준.
void main() {
  setUpAll(initPmartFormatting);

  late MockInquiriesRepository repo;
  setUp(() => repo = MockInquiriesRepository(latency: Duration.zero));

  Future<void> start(WidgetTester t, {int pick = 2}) async {
    await t.pumpWidget(
      testApp([
        inquiriesRepositoryProvider.overrideWithValue(repo),
        reviewPhotoPickerProvider.overrideWithValue(
          (_, max) async => [
            for (var i = 0; i < pick && i < max; i++)
              ReviewPhotoFile(name: 'p$i.png', bytes: _png),
          ],
        ),
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
  }

  Future<void> push(WidgetTester t, String path) async {
    unawaited(GoRouter.of(t.element(find.byType(Scaffold).first)).push(path));
    await t.pumpAndSettle();
  }

  // 초안 17: [문의 남기기]는 아래 고정이라 굴리지 않아도 보인다.
  Future<FilledButton> submit(WidgetTester t) async =>
      t.widget(find.byKey(const ValueKey('inq-submit')));

  testWidgets(
    '사진을 고르면 바로 올리고, 실패한 사진이 있으면 보낼 수 없다. 다시 올리기는 같은 키, 접수되면 상세에 사진',
    (t) async {
      await start(t);
      await push(t, '/support/inquiries/new');
      await t.tap(find.byKey(const ValueKey('inq-kind')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('inq-cat-product')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('inq-body')), '상품이 깨져 왔어요');
      await t.pumpAndSettle();

      repo.failNextUpload = const NetworkFailure(
        DioExceptionType.connectionError,
      );
      await t.ensureVisible(find.byKey(const ValueKey('inq-photo-add')));
      await t.tap(find.byKey(const ValueKey('inq-photo-add')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('inq-photo-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('inq-photo-1')), findsOneWidget);
      expect(find.text('올리지 못했어요'), findsOneWidget);
      expect((await submit(t)).onPressed, isNull);
      expect(repo.photos.length, 1);

      await t.ensureVisible(find.text('다시 올리기'));
      await t.pumpAndSettle();
      await t.tap(find.text('다시 올리기'));
      await t.pumpAndSettle();
      expect(repo.photos.length, 2);
      expect((await submit(t)).onPressed, isNotNull);

      await t.tap(find.byKey(const ValueKey('inq-submit')));
      await t.pumpAndSettle();
      // 완료 화면에 사진 수, 내 문의 내역 → 상세에 사진.
      expect(find.text('2장'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('inq-done-list')));
      await t.pumpAndSettle();
      await t.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('inquiry-'),
            )
            .first,
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('inquiry-body')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inquiry-photo-inq-photo-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inquiry-photo-inq-photo-2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('답변 전에는 만족도가 없고, 답변 뒤 한 번 남기면 남긴 점수로 바뀐다', (t) async {
    await start(t);
    await push(t, '/support/inquiries/inq-seed-2'); // 답변 전
    expect(find.byKey(const ValueKey('inquiry-rate')), findsNothing);
    GoRouter.of(t.element(find.byType(Scaffold).last)).pop();
    await t.pumpAndSettle();

    await push(t, '/support/inquiries/inq-seed-1'); // 답변 있음
    expect(find.byKey(const ValueKey('inquiry-rate')), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('inquiry-rate-4')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('inquiry-rate-4')));
    await t.enterText(
      find.byKey(const ValueKey('inquiry-rate-comment')),
      '빨리 답해 주셨어요',
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('inquiry-rate-send')));
    await t.tap(find.byKey(const ValueKey('inquiry-rate-send')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('inquiry-rate')), findsNothing);
    expect(find.text('남긴 평가: 도움이 되었어요 · 빨리 답해 주셨어요'), findsOneWidget);
    expect(repo.rateKeys.length, 1);
  });

  testWidgets('문의 닫기: 확인 뒤 닫히고, 닫기 버튼이 사라진다', (t) async {
    await start(t);
    await push(t, '/support/inquiries/inq-seed-2');
    await t.tap(find.byKey(const ValueKey('inquiry-close')));
    await t.pumpAndSettle();
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(repo.closeKeys, isEmpty);

    await t.tap(find.byKey(const ValueKey('inquiry-close')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('inquiry-close-confirm')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('inquiry-close')), findsNothing);
    expect(find.byKey(const ValueKey('inquiry-closed-note')), findsOneWidget);
    expect(find.text('종료'), findsOneWidget);
  });
}
