// 고객 계정 이용제한·정지(customer 0.16.0 CU-7, 백엔드 알림 2026-11-23): 로그인 403 ACCOUNT_SUSPENDED,
// 문의·리뷰 작성 403 ACCOUNT_RESTRICTED(details until), /me restriction·restrictedUntil.
import 'package:customer_app/features/auth/data/auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';
import 'package:customer_app/features/profile/domain/profile.dart';
import 'package:customer_app/features/support/data/mock_inquiries_repository.dart';
import 'package:customer_app/features/support/presentation/inquiry_controller.dart';
import 'package:customer_app/l10n/gen/app_localizations_ko.dart';
import 'package:customer_app/shared/account_restriction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(initPmartFormatting);
  final l10n = AppLocalizationsKo();
  final until = DateTime.utc(2026, 11, 30, 5); // 서울 11월 30일 14:00

  Problem problem(String code) => Problem(
    status: 403,
    code: code,
    details: [ProblemDetail(field: 'until', reason: until.toIso8601String())],
  );

  test('로그인 403 ACCOUNT_SUSPENDED → 정지 결과(풀리는 시각), 안내 "11월 30일 14:00까지 계정이 정지됐어요…"', () {
    final o = authFailureToOutcome(
      ProblemFailure(problem(AccountRestrictionCode.suspended)),
    );
    expect(o, isA<LoginSuspended>().having((s) => s.until, 'until', until));
    expect(
      suspendedText(l10n, (o as LoginSuspended).until),
      '11월 30일 14:00까지 계정이 정지됐어요. 그동안 로그인·주문을 할 수 없어요.',
    );
    // 기한을 모르면 기한 없이.
    expect(suspendedText(l10n, null), l10n.accountSuspended);
  });

  test('내 정보 제한: 기한 안이면 막음, 지나면 풀림', () {
    final p = Profile(
      accountId: 'a',
      version: 1,
      restriction: AccountRestriction.restricted,
      restrictedUntil: until,
    );
    expect(p.writingBlockedAt(DateTime.utc(2026, 11, 29)), isTrue);
    expect(p.writingBlockedAt(DateTime.utc(2026, 12, 1)), isFalse);
    expect(
      const Profile(
        accountId: 'a',
        version: 1,
      ).writingBlockedAt(DateTime.now()),
      isFalse,
    );
  });

  Future<void> openNewInquiry(
    WidgetTester t, {
    required MockInquiriesRepository inquiries,
    MockProfileRepository? profile,
  }) async {
    t.view
      ..physicalSize = const Size(400, 1600)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        inquiriesRepositoryProvider.overrideWithValue(inquiries),
      ], profile: profile),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    router.push('/support/inquiries/new').ignore();
    await t.pumpAndSettle();
  }

  testWidgets(
    '문의 남기기: 서버가 이용제한(403 ACCOUNT_RESTRICTED)이면 "…까지 문의·리뷰를 쓸 수 없어요"',
    (t) async {
      final inquiries = MockInquiriesRepository(latency: Duration.zero)
        ..failNextCreate = ProblemFailure(
          problem(AccountRestrictionCode.restricted),
        );
      await openNewInquiry(t, inquiries: inquiries);
      await t.tap(find.byKey(const ValueKey('inq-kind')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('inq-cat-other')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('inq-body')), '문의');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('inq-submit')));
      await t.pumpAndSettle();
      expect(find.text('11월 30일 14:00까지 문의·리뷰를 쓸 수 없어요.'), findsOneWidget);
      expect(inquiries.created, 0);
    },
  );

  testWidgets('문의 남기기: 내 정보가 이용제한 중이면 미리 막고 이유 한 줄', (t) async {
    final profile = MockProfileRepository(latency: Duration.zero)
      ..restriction = AccountRestriction.restricted
      ..restrictedUntil = DateTime.now().toUtc().add(const Duration(days: 3));
    await openNewInquiry(
      t,
      inquiries: MockInquiriesRepository(latency: Duration.zero),
      profile: profile,
    );
    expect(find.byKey(const ValueKey('inq-reason')), findsOneWidget);
    expect(find.textContaining('문의·리뷰를 쓸 수 없어요'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('inq-kind')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('inq-cat-other')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('inq-body')), '문의');
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('inq-submit')))
          .onPressed,
      isNull,
    );
  });
}
