import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_case/pmart_api_case.dart' as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/support/data/inquiries_repository.dart';
import 'package:customer_app/features/support/data/mock_inquiries_repository.dart';
import 'package:customer_app/features/support/domain/inquiry.dart';
import 'package:customer_app/features/support/presentation/inquiry_controller.dart';

import 'support/app_harness.dart';

/// 고객센터 문의(case-service 0.2.0 inquiries) — 목 저장소 기준. 실서버 확인은 아니다.
void main() {
  setUpAll(initPmartFormatting);

  late MockInquiriesRepository repo;
  setUp(() => repo = MockInquiriesRepository(latency: Duration.zero));

  const draft = InquiryDraft(
    category: InquiryCategory.delivery,
    body: '배송 완료인데 못 받았어요',
  );

  group('계약 → 화면 모델', () {
    test('문의 상세: 종류·상태·답변을 옮기고, 빈 제목·주문은 null', () {
      final d = inquiryFromContract(
        api.Inquiry.fromJson({
          'inquiryId': 'INQ-1',
          'category': 'DELIVERY',
          'orderId': null,
          'title': ' ',
          'status': 'ANSWERED',
          'origin': 'INQUIRY_PAGE',
          'createdAt': '2026-11-09T01:00:00Z',
          'answeredAt': '2026-11-09T02:00:00Z',
          'version': 2,
          'caseId': 'CASE-1',
          'body': '배송 문의',
          'replies': [
            {
              'replyId': 'R-1',
              'authorType': 'AGENT',
              'body': '확인해 드릴게요',
              'createdAt': '2026-11-09T02:00:00Z',
            },
            {'replyId': 'R-2', 'authorType': 'AGENT', 'body': ''},
          ],
        }),
      );
      expect(d.summary.category, InquiryCategory.delivery);
      expect(d.summary.status, InquiryStatus.answered);
      expect(d.summary.title, isNull);
      expect(d.summary.orderId, isNull);
      expect(d.body, '배송 문의');
      expect([for (final r in d.replies) r.body], ['확인해 드릴게요']);
    });

    test('모르는 상태는 unknown(다른 상태로 바꿔 보이지 않는다)', () {
      expect(InquiryStatus.fromWire('ESCALATED'), InquiryStatus.unknown);
      expect(InquiryCategory.fromWire('BILLING'), isNull);
    });
  });

  group('문의 남기기', () {
    test('접수되면 목록 맨 앞에 온다', () async {
      final out = await InquirySubmitter(repo).submit(draft);
      final made = (out as InquirySubmitted).inquiry;
      expect(made.summary.status, InquiryStatus.received);
      expect((await repo.list()).items.first.inquiryId, made.summary.inquiryId);
    });

    test('응답을 잃으면 결과 불명 — 다시 확인은 같은 키·같은 본문이라 문의가 하나만 생긴다', () async {
      repo
        ..failNextCreate = const UnknownResultFailure()
        ..failNextCreateStored = true;
      final submitter = InquirySubmitter(repo);
      expect(await submitter.submit(draft), isA<InquiryUnknown>());
      expect(submitter.hasPending, isTrue);
      // 화면이 본문을 잠그지만, 혹시 다른 본문이 와도 보관한 본문으로 다시 보낸다.
      final again = await submitter.submit(
        const InquiryDraft(category: InquiryCategory.other, body: '다른 내용'),
      );
      expect((again as InquirySubmitted).inquiry.body, draft.body);
      expect(repo.created, 1);
      expect(submitter.hasPending, isFalse);
    });

    test('남의·없는 주문은 422 ORDER_NOT_FOUND 거절 — 다음 전송은 새 키', () async {
      final strict = MockInquiriesRepository(
        latency: Duration.zero,
        knownOrder: (id) => id == 'order-mine',
      );
      final submitter = InquirySubmitter(strict);
      final out = await submitter.submit(
        const InquiryDraft(
          category: InquiryCategory.order,
          body: '문의',
          orderId: 'order-other',
        ),
      );
      expect((out as InquiryRejected).code, InquiryProblemCode.orderNotFound);
      expect(submitter.hasPending, isFalse);
      expect(strict.created, 0);
    });
  });

  group('화면', () {
    Future<void> bigScreen(WidgetTester t) async {
      t.view
        ..physicalSize = const Size(400, 1600)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }

    Future<void> openSupport(WidgetTester t, {bool login = true}) async {
      await bigScreen(t);
      await t.pumpWidget(
        testApp([inquiriesRepositoryProvider.overrideWithValue(repo)]),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
      if (login) {
        await t.tap(find.byKey(const ValueKey('my-login')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('login-kakao')));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('my-support')));
      await t.pumpAndSettle();
    }

    testWidgets('비회원은 문의를 남길 수 없다 — 로그인 안내', (t) async {
      await openSupport(t, login: false);
      expect(find.text('무엇을 도와드릴까요?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('support-new-inquiry')));
      await t.pumpAndSettle();
      expect(find.text('문의는 로그인한 뒤에 남길 수 있어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('inq-submit')), findsNothing);
    });

    testWidgets('종류·내용을 채워야 보낼 수 있고, 접수되면 문의 상세로 간다', (t) async {
      await openSupport(t);
      await t.tap(find.byKey(const ValueKey('support-new-inquiry')));
      await t.pumpAndSettle();
      FilledButton submit() =>
          t.widget(find.byKey(const ValueKey('inq-submit')));
      expect(submit().onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('inq-cat-delivery')));
      await t.enterText(find.byKey(const ValueKey('inq-body')), '배송이 늦어요');
      await t.pumpAndSettle();
      expect(submit().onPressed, isNotNull);
      await t.tap(find.byKey(const ValueKey('inq-submit')));
      await t.pumpAndSettle();
      expect(repo.created, 1);
      expect(find.text('문의 내용'), findsOneWidget);
      expect(find.byKey(const ValueKey('inquiry-body')), findsOneWidget);
      expect(find.text('배송이 늦어요'), findsOneWidget);
      expect(find.text('아직 답변 전이에요. 상담원이 확인하고 있어요.'), findsOneWidget);
    });

    testWidgets('주문 고르기: 내 주문 목록에서 고르면 그 주문으로 접수된다(종류는 "주문"이 기본)', (t) async {
      await openSupport(t);
      await t.tap(find.byKey(const ValueKey('support-new-inquiry')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('inq-order')), findsNothing);
      await t.tap(find.byKey(const ValueKey('inq-pick-order')));
      await t.pumpAndSettle();
      expect(find.text('어떤 주문에 대한 문의인가요?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('inq-pick-order-seed-1')));
      await t.pumpAndSettle();
      expect(find.text('주문 order-seed-1'), findsOneWidget);
      expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('inq-cat-order')))
            .selected,
        isTrue,
      );
      await t.enterText(find.byKey(const ValueKey('inq-body')), '포장이 찢어졌어요');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('inq-submit')));
      await t.pumpAndSettle();
      expect(repo.lastOrderId, 'order-seed-1');
    });

    testWidgets('결과 불명: 본문을 잠그고 "다시 확인"만 — 눌러도 문의는 하나', (t) async {
      await openSupport(t);
      await t.tap(find.byKey(const ValueKey('support-new-inquiry')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('inq-cat-other')));
      await t.enterText(find.byKey(const ValueKey('inq-body')), '기타 문의');
      await t.pumpAndSettle();
      repo
        ..failNextCreate = const UnknownResultFailure()
        ..failNextCreateStored = true;
      await t.tap(find.byKey(const ValueKey('inq-submit')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('inq-message')), findsOneWidget);
      expect(find.text('접수됐는지 다시 확인'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byKey(const ValueKey('inq-body'))).enabled,
        isFalse,
      );
      await t.tap(find.byKey(const ValueKey('inq-submit')));
      await t.pumpAndSettle();
      expect(repo.created, 1);
      expect(find.byKey(const ValueKey('inquiry-body')), findsOneWidget);
    });

    testWidgets('내 문의: 최근 순 목록 · 상태, 답변 완료 문의는 답변을 보인다', (t) async {
      await openSupport(t);
      await t.tap(find.byKey(const ValueKey('support-my-inquiries')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('inquiry-inq-seed-2')), findsOneWidget);
      expect(find.text('접수'), findsOneWidget);
      expect(find.text('답변 완료'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('inquiry-inq-seed-1')));
      await t.pumpAndSettle();
      expect(find.textContaining('[목 답변]'), findsOneWidget);
    });

    testWidgets('목록 조회 실패는 "문의 없음"이 아니라 오류로 보인다', (t) async {
      await bigScreen(t);
      await t.pumpWidget(
        testApp([
          inquiriesRepositoryProvider.overrideWithValue(_FailingRepository()),
        ]),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-login')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-support')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('support-my-inquiries')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('inquiries-empty')), findsNothing);
      expect(find.text('남긴 문의가 없어요'), findsNothing);
    });
  });
}

final class _FailingRepository implements InquiriesRepository {
  @override
  Future<InquiryDetail> create(
    InquiryDraft draft, {
    required IdempotencyKey key,
  }) => throw const NetworkFailure(DioExceptionType.connectionError);

  @override
  Future<InquiryDetail> get(String inquiryId) =>
      throw const NetworkFailure(DioExceptionType.connectionError);

  @override
  Future<InquiryPage> list({String? cursor}) =>
      throw const NetworkFailure(DioExceptionType.connectionError);
}
