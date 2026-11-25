import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/auth/data/auth_repository.dart'
    show SocialTokenSource;
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:customer_app/features/orders/presentation/orders_screens.dart'
    show OrderDetailScreen;
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';
import 'package:customer_app/features/withdrawal/data/withdrawal_repository.dart';
import 'package:customer_app/features/withdrawal/domain/withdrawal.dart';
import 'package:customer_app/features/withdrawal/presentation/withdrawal_screen.dart';

import 'package:customer_app/features/address/presentation/address_controller.dart'
    show guestAddressStoreProvider;

import 'support/app_harness.dart';

/// 회원 탈퇴(customer 0.12.0, ADR-0077 — 백엔드 요청 2026-11-20 customer-withdrawal).
void main() {
  setUpAll(initPmartFormatting);

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<({MockWithdrawalRepository repo, MockProfileRepository profile})>
  login(
    WidgetTester t, {
    MockWithdrawalRepository? repo,
    MockProfileRepository? profile0,
    SocialTokenSource? source,
    String loginKey = 'login-kakao',
  }) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final r = repo ?? MockWithdrawalRepository(latency: Duration.zero);
    final profile = profile0 ?? MockProfileRepository(latency: Duration.zero);
    await t.pumpWidget(
      testApp(
        [
          withdrawalRepositoryProvider.overrideWithValue(r),
          if (source != null)
            socialTokenSourceProvider.overrideWithValue(source),
        ],
        auth: MockAuthRepository(latency: Duration.zero),
        profile: profile,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(key('my-login'));
    await t.pumpAndSettle();
    await t.tap(key(loginKey));
    await t.pumpAndSettle();
    return (repo: r, profile: profile);
  }

  /// 로그인 → 내 정보 → 회원 탈퇴.
  Future<({MockWithdrawalRepository repo, MockProfileRepository profile})> open(
    WidgetTester t, {
    MockWithdrawalRepository? repo,
    SocialTokenSource? source,
    String loginKey = 'login-kakao',
  }) async {
    final r = await login(t, repo: repo, source: source, loginKey: loginKey);
    await t.tap(key('my-info'));
    await t.pumpAndSettle();
    await t.ensureVisible(key('info-withdraw'));
    await t.tap(key('info-withdraw'));
    await t.pumpAndSettle();
    return r;
  }

  bool member(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
              .read(sessionProvider)
          is MemberSession;

  bool submitEnabled(WidgetTester t) =>
      t.widget<FilledButton>(key('wd-submit')).onPressed != null;

  testWidgets('안내를 확인해야 누를 수 있고, 재인증 뒤 완료면 이 기기 로그인을 지우고 홈으로', (t) async {
    final (:repo, profile: _) = await open(t);
    expect(key('wd-form'), findsOneWidget);
    expect(submitEnabled(t), isFalse);

    await t.tap(key('wd-reason-delivery'));
    await t.pump();
    await t.enterText(key('wd-reason-text'), '배달이 늦었어요');
    await t.tap(key('wd-agree'));
    await t.pump();
    expect(submitEnabled(t), isTrue);
    // 재인증할 소셜(이번에 로그인한 카카오)을 단추에 보인다.
    expect(find.text('카카오로 다시 로그인하고 탈퇴하기'), findsOneWidget);

    await t.tap(key('wd-submit'));
    await t.pumpAndSettle();
    expect(repo.requests.single, (
      provider: SocialProvider.kakao,
      reasonCode: 'DELIVERY',
      reasonText: '배달이 늦었어요',
    ));
    expect(key('withdrawal'), findsNothing);
    expect(member(t), isFalse);
    expect(find.text('탈퇴가 완료됐어요'), findsOneWidget);
    // 탈퇴 뒤에도 지금 주소로 둘러본다 — 그 주소가 비회원 배송지로(주소 검색 화면 아님, 사용자 2026-11-25).
    final store = ProviderScope.containerOf(
      t.element(find.byType(Scaffold).first),
    ).read(guestAddressStoreProvider);
    expect(await store.ids(), isNotEmpty);
  });

  group('제공자 연결 끊기(백엔드 요청 2026-11-21 — 동의는 처음 가입 때만)', () {
    testWidgets('탈퇴가 받아들여지면 로그인 제공자에 연결 끊기를 부른다', (t) async {
      final source = MockSocialTokenSource();
      await open(t, source: source);
      await t.tap(key('wd-agree'));
      await t.pump();
      await t.tap(key('wd-submit'));
      await t.pumpAndSettle();
      expect(source.forgotten, contains((SocialProvider.kakao, true)));
    });

    testWidgets('재인증을 닫으면(탈퇴 안 보냄) 끊지 않는다', (t) async {
      final source = _CancelAfterFirst();
      await open(t, source: source);
      await t.tap(key('wd-agree'));
      await t.pump();
      await t.tap(key('wd-submit'));
      await t.pumpAndSettle();
      expect(source.revoked, isFalse);
    });

    testWidgets('서버가 거절하면(다른 계정 403) 끊지 않는다', (t) async {
      final source = MockSocialTokenSource();
      final repo = MockWithdrawalRepository(latency: Duration.zero)
        ..failNext = const ProblemFailure(
          Problem(status: 403, code: 'REAUTHENTICATION_MISMATCH'),
        );
      await open(t, repo: repo, source: source);
      await t.tap(key('wd-agree'));
      await t.pump();
      await t.tap(key('wd-submit'));
      await t.pumpAndSettle();
      expect(source.forgotten.where((f) => f.$2), isEmpty);
    });

    testWidgets('로그아웃은 연결을 끊지 않고 계정 선택만 지운다', (t) async {
      final source = MockSocialTokenSource();
      await login(t, source: source);
      final container = ProviderScope.containerOf(
        t.element(find.byType(Scaffold).first),
      );
      await container.read(sessionProvider.notifier).signOut();
      await t.pumpAndSettle();
      expect(source.forgotten, [(SocialProvider.kakao, false)]);
    });
  });
  testWidgets('재인증 화면을 닫으면 아무것도 보내지 않는다', (t) async {
    // 로그인(첫 번째)은 되고, 탈퇴 재인증(두 번째)은 고객이 닫는다.
    final (:repo, profile: _) = await open(t, source: _CancelAfterFirst());
    await t.tap(key('wd-agree'));
    await t.pump();
    await t.tap(key('wd-submit'));
    await t.pumpAndSettle();
    expect(repo.requestKeys, isEmpty);
    expect(key('wd-form'), findsOneWidget);
    expect(key('wd-error'), findsNothing);
    expect(member(t), isTrue);
  });

  testWidgets('진행 중 주문이 있으면 "탈퇴 처리 대기": 사유를 누르면 그 주문으로, 로그인은 유지', (t) async {
    final repo = MockWithdrawalRepository(latency: Duration.zero)
      ..obligationsNext = [
        {'kind': 'ORDER_IN_PROGRESS', 'ref': 'order-seed-4'},
        {'kind': 'REFUND_IN_PROGRESS', 'ref': 'claim-x'},
      ];
    final (repo: _, :profile) = await open(t, repo: repo);
    await t.tap(key('wd-agree'));
    await t.pump();
    await t.tap(key('wd-submit'));
    await t.pumpAndSettle();

    expect(key('wd-status'), findsOneWidget);
    expect(t.widget<Text>(key('wd-status-title')).data, '탈퇴 처리 대기 중이에요');
    expect(find.text('진행 중인 주문이 있어요'), findsOneWidget);
    expect(find.text('진행 중인 환불이 있어요'), findsOneWidget);
    expect(member(t), isTrue);
    expect(profile.withdrawPending, isTrue);
    expect(find.text('탈퇴가 완료됐어요'), findsNothing);

    await t.tap(key('wd-obligation-0'));
    await t.pumpAndSettle();
    expect(find.byType(OrderDetailScreen), findsOneWidget);
  });

  testWidgets('서버가 아직 모르면 "확인 중" — 완료로 보이지 않는다', (t) async {
    final repo = MockWithdrawalRepository(latency: Duration.zero)
      ..unknownNext = true;
    await open(t, repo: repo);
    await t.tap(key('wd-agree'));
    await t.pump();
    await t.tap(key('wd-submit'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(key('wd-status-title')).data, '탈퇴를 확인하고 있어요');
    expect(member(t), isTrue);
  });

  testWidgets('대기 중 철회: 재인증 뒤 REVOKED 면 안내하고 다시 탈퇴 안내 화면', (t) async {
    final repo = MockWithdrawalRepository(latency: Duration.zero)
      ..obligationsNext = [
        {'kind': 'CLAIM_IN_PROGRESS', 'ref': 'claim-x'},
      ];
    final (repo: _, :profile) = await open(t, repo: repo);
    await t.tap(key('wd-agree'));
    await t.pump();
    await t.tap(key('wd-submit'));
    await t.pumpAndSettle();
    expect(key('wd-status'), findsOneWidget);

    await t.tap(key('wd-revoke'));
    await t.pumpAndSettle();
    expect(repo.revokeKeys, hasLength(1));
    expect(find.text('탈퇴를 철회했어요'), findsOneWidget);
    expect(key('wd-form'), findsOneWidget);
    expect(profile.withdrawPending, isFalse);
    expect(member(t), isTrue);
  });

  testWidgets('다른 소셜 계정으로 재인증하면(403) 안내하고 넘어가지 않는다', (t) async {
    final repo = MockWithdrawalRepository(latency: Duration.zero)
      ..failNext = const ProblemFailure(
        Problem(
          status: 403,
          code: WithdrawalProblemCode.reauthenticationMismatch,
        ),
      );
    await open(t, repo: repo);
    await t.tap(key('wd-agree'));
    await t.pump();
    await t.tap(key('wd-submit'));
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(key('wd-error')).data,
      '이 계정에 연결된 카카오 계정으로 다시 로그인해 주세요',
    );
    expect(key('wd-form'), findsOneWidget);
    expect(member(t), isTrue);
  });

  testWidgets('결과를 모르면 완료로 보이지 않고, 다시 누르면 같은 키로 보낸다', (t) async {
    final repo = MockWithdrawalRepository(latency: Duration.zero)
      ..failNext = const NetworkFailure(DioExceptionType.connectionError);
    await open(t, repo: repo);
    await t.tap(key('wd-agree'));
    await t.pump();
    await t.tap(key('wd-submit'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(key('wd-error')).data, contains('결과를 확인하지 못했어요'));
    expect(member(t), isTrue);
    expect(key('wd-form'), findsOneWidget);

    await t.tap(key('wd-submit'));
    await t.pumpAndSettle();
    expect(repo.requestKeys, hasLength(2));
    expect(repo.requestKeys.toSet(), hasLength(1));
    expect(member(t), isFalse);
  });

  testWidgets('이미 대기 중인 계정: 마이 위에 띠, 누르면 접수 화면이 아니라 상태부터', (t) async {
    final repo = MockWithdrawalRepository(latency: Duration.zero)
      ..items.add({
        'withdrawalId': 'wd-old',
        'state': 'BLOCKED_BY_OBLIGATIONS',
        'requestedAt': '2026-11-20T01:00:00Z',
        'lastCheckedAt': '2026-11-20T01:10:00Z',
        'openObligations': [
          {'kind': 'PAYMENT_UNKNOWN', 'ref': 'order-seed-4'},
        ],
      });
    await login(
      t,
      repo: repo,
      profile0: MockProfileRepository(latency: Duration.zero)
        ..withdrawPending = true,
    );
    expect(key('my-withdraw-pending'), findsOneWidget);

    await t.tap(key('my-withdraw-pending'));
    await t.pumpAndSettle();
    expect(key('wd-status'), findsOneWidget);
    expect(key('wd-form'), findsNothing);
    expect(find.text('결제 결과를 확인 중인 주문이 있어요'), findsOneWidget);
    expect(t.widget<Text>(key('wd-last-checked')).data, contains('마지막 확인'));
  });

  test('계약 → 앱: 모르는 상태는 확인 중, 모르는 의무는 "그 밖"', () {
    final w = withdrawalFromContract(
      api.Withdrawal.fromJson({
        'withdrawalId': 'w-1',
        'state': 'UNKNOWN',
        'requestedAt': '2026-11-20T01:00:00Z',
        'openObligations': [
          {'kind': 'SOMETHING_NEW', 'ref': ' '},
          {'kind': 'CLAIM_IN_PROGRESS', 'ref': 'c-1'},
        ],
      }),
    );
    expect(w.state, WithdrawalState.unknown);
    expect(w.state.waiting, isTrue);
    expect(w.state.done, isFalse);
    expect(w.obligations[0].kind, ObligationKind.other);
    expect(w.obligations[0].ref, isNull);
    expect(w.obligations[1].kind.refersToClaim, isTrue);
  });
}

/// 첫 번째(로그인)는 되고 그 뒤(재인증)는 고객이 닫는 제공자.
final class _CancelAfterFirst implements SocialTokenSource {
  @override
  Future<void> abandonSignup(SocialProvider provider) async {}

  int _calls = 0;

  @override
  Future<SocialCredential?> obtain(
    SocialProvider provider, {
    bool withdrawal = false,
  }) async => _calls++ == 0 ? SocialCredential('token-${provider.name}') : null;

  @override
  Future<SocialCredential?> obtainSilently(SocialProvider provider) async =>
      null;

  bool revoked = false;

  @override
  Future<void> forget(SocialProvider provider, {bool revoke = false}) async {
    if (revoke) revoked = true;
  }
}
