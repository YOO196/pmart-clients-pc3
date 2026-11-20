import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_customer_assistant/pmart_api_customer_assistant.dart'
    as api;
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/orders/presentation/orders_screens.dart'
    show OrderDetailScreen;
import 'package:customer_app/features/support/data/chat_repository.dart';
import 'package:customer_app/features/support/data/mock_chat_repository.dart';
import 'package:customer_app/features/support/data/mock_inquiries_repository.dart';
import 'package:customer_app/features/support/domain/chat.dart';
import 'package:customer_app/features/support/presentation/chat_controller.dart';
import 'package:customer_app/features/support/presentation/inquiry_controller.dart';

import 'support/app_harness.dart';

/// 고객센터 AI 상담(customer-assistant-service 0.1.0) — 목 저장소 기준. 실서버·실제 답변 확인은 아니다.
void main() {
  setUpAll(initPmartFormatting);

  MockChatRepository mock([MockChatScenario? scenario]) => MockChatRepository(
    latency: Duration.zero,
    script: scenario == null ? null : (_) => scenario,
  );

  group('계약 → 화면 모델', () {
    Map<String, dynamic> base(Map<String, dynamic> extra) => {
      'answerId': 'CANS-1',
      'requestId': 'k-1',
      'state': 'ANSWERED',
      'answer': '답',
      'citations': <Map<String, dynamic>>[],
      'answerMode': 'GENERATIVE',
      'askedAt': '2026-11-09T07:10:00Z',
      ...extra,
    };

    test('주문 상태 답: 주문 카드·문의 연결을 옮긴다', () {
      final a = chatAnswerFromContract(
        api.CustomerAnswer.fromJson(
          base({
            'state': 'ORDER_STATUS',
            'answerMode': 'ORDER_TEMPLATE',
            'order': {
              'orderId': 'ORD-1',
              'status': 'PREPARING',
              'statusLabel': '상품 준비 중',
              'itemCount': 2,
              'totalAmount': 12000,
              'arrivalWindow': {
                'date': '2026-11-09',
                'start': '14:00',
                'end': '15:00',
              },
            },
            'handoff': {
              'target': 'INQUIRY',
              'message': '문의를 남겨 주세요',
              'buttonLabel': '고객센터에 문의 남기기',
              'orderId': 'ORD-1',
            },
          }),
        ),
      );
      expect(a.state, ChatAnswerState.orderStatus);
      expect(a.order!.statusLabel, '상품 준비 중');
      expect(a.order!.arrivalStart, '14:00');
      expect(a.handoff!.orderId, 'ORD-1');
      expect(a.extractive, isFalse);
    });

    test('근거·발췌 표시, 없는 값은 비워 둔다', () {
      final a = chatAnswerFromContract(
        api.CustomerAnswer.fromJson(
          base({
            'answerMode': 'BASELINE_EXTRACTIVE',
            'citations': [
              {
                'documentId': 'docs/business/customer-faq/02-cancel.md',
                'title': '주문 취소',
                'section': null,
                'excerpt': '취소는 …',
              },
            ],
          }),
        ),
      );
      expect(a.extractive, isTrue);
      expect(a.citations.single.title, '주문 취소');
      expect(a.citations.single.section, isNull);
      expect(a.order, isNull);
      expect(a.recentOrders, isEmpty);
      expect(a.handoff, isNull);
    });
  });

  group('대화', () {
    ProviderContainer container(MockChatRepository repo) {
      final c = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatProcessingPolicyProvider.overrideWithValue((
            interval: Duration.zero,
            attempts: 2,
          )),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('질문마다 새 키, 답이 붙는다', () async {
      final repo = mock();
      final c = container(repo);
      await c.read(chatProvider.notifier).ask('취소할 수 있나요?');
      await c.read(chatProvider.notifier).ask('환불은요?');
      final turns = c.read(chatProvider);
      expect(
        [for (final t in turns) t.status],
        [ChatTurnStatus.answered, ChatTurnStatus.answered],
      );
      expect(repo.sentKeys.toSet(), hasLength(2));
    });

    test('202 처리 중이면 같은 키로 다시 물어 답을 받는다(질문은 한 번만 센다)', () async {
      final repo = mock(MockChatScenario.processingOnce);
      final c = container(repo);
      await c.read(chatProvider.notifier).ask('오래 걸리는 질문');
      expect(c.read(chatProvider).single.status, ChatTurnStatus.answered);
      expect(repo.sentKeys, hasLength(2));
      expect(repo.sentKeys.toSet(), hasLength(1));
      expect(repo.answered, 1);
    });

    test('응답을 잃으면 결과 불명 — 다시 확인은 같은 키', () async {
      final repo = mock(MockChatScenario.lostOnce);
      final c = container(repo);
      await c.read(chatProvider.notifier).ask('유실');
      final turn = c.read(chatProvider).single;
      expect(turn.status, ChatTurnStatus.unknown);
      await c.read(chatProvider.notifier).recheck(turn.id);
      expect(c.read(chatProvider).single.status, ChatTurnStatus.answered);
      expect(repo.sentKeys.toSet(), hasLength(1));
      expect(repo.answered, 1);
    });

    test('주문을 고르면 같은 질문을 orderId 와 함께 새 키로 보낸다 → 주문 상태 답', () async {
      final repo = mock(MockChatScenario.realtime);
      final c = container(repo);
      await c.read(chatProvider.notifier).ask('내 주문 어디쯤이에요?');
      final first = c.read(chatProvider).single;
      expect(first.answer!.state, ChatAnswerState.realtimeDataRequired);
      final picked = first.answer!.recentOrders.first;
      await c
          .read(chatProvider.notifier)
          .ask(first.question, orderId: picked.orderId);
      final turns = c.read(chatProvider);
      expect(turns, hasLength(2));
      expect(turns[1].answer!.state, ChatAnswerState.orderStatus);
      expect(turns[1].answer!.order!.orderId, picked.orderId);
      expect(repo.sentOrderIds, [null, picked.orderId]);
      expect(repo.sentKeys.toSet(), hasLength(2));
    });

    test('429 요청 제한은 거절 — 서버 안내 문장을 들고 있다', () async {
      final c = container(mock(MockChatScenario.rateLimited));
      await c.read(chatProvider.notifier).ask('또 질문');
      final t = c.read(chatProvider).single;
      expect(t.status, ChatTurnStatus.rejected);
      expect(t.rejectCode, ChatProblemCode.rateLimited);
      expect(t.serverDetail, contains('질문이 너무 빨라요'));
    });
  });

  group('화면', () {
    Future<void> open(
      WidgetTester t,
      MockChatRepository repo, {
      MockInquiriesRepository? inquiries,
      bool login = true,
      bool general = true,
    }) async {
      t.view
        ..physicalSize = const Size(400, 1600)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        testApp([
          chatRepositoryProvider.overrideWithValue(repo),
          chatProcessingPolicyProvider.overrideWithValue((
            interval: Duration.zero,
            attempts: 2,
          )),
          if (inquiries != null)
            inquiriesRepositoryProvider.overrideWithValue(inquiries),
        ]),
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
      await t.tap(find.byKey(const ValueKey('support-chat')));
      await t.pumpAndSettle();
      if (login && general) {
        await t.tap(find.byKey(const ValueKey('chat-topic-general')));
        await t.pumpAndSettle();
      }
    }

    Future<void> ask(WidgetTester t, String q) async {
      await t.enterText(find.byKey(const ValueKey('chat-input')), q);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-send')));
      await t.pumpAndSettle();
    }

    testWidgets('비회원은 쓸 수 없다 — 로그인 안내', (t) async {
      await open(t, mock(), login: false);
      expect(find.text('AI 채팅 상담은 로그인한 뒤에 쓸 수 있어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-input')), findsNothing);
    });

    testWidgets('답변만 보이고 근거는 보이지 않는다(서버가 근거를 줘도)', (t) async {
      await open(t, mock());
      await ask(t, '준비 중인 주문도 취소돼요?');
      expect(
        find.byKey(const ValueKey('chat-answer-answered')),
        findsOneWidget,
      );
      expect(find.textContaining('[목 답변]'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-citations')), findsNothing);
      expect(find.textContaining('[목 근거]'), findsNothing);
      expect(find.textContaining('근거 보기'), findsNothing);
      expect(find.byKey(const ValueKey('chat-handoff')), findsNothing);
    });

    testWidgets('근거 없음 → 문의 남기기: 질문이 본문 초안, origin 은 AI 상담', (t) async {
      final inquiries = MockInquiriesRepository(latency: Duration.zero);
      await open(t, mock(MockChatScenario.noGrounding), inquiries: inquiries);
      await ask(t, '포인트는 언제 생기나요?');
      expect(
        find.byKey(const ValueKey('chat-answer-noGrounding')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('chat-handoff')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('inq-body')))
            .controller!
            .text,
        '포인트는 언제 생기나요?',
      );
      await t.tap(find.byKey(const ValueKey('inq-cat-other')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('inq-submit')));
      await t.pumpAndSettle();
      expect(inquiries.created, 1);
      expect(inquiries.lastOrigin?.wire, 'ASSISTANT_HANDOFF');
    });

    testWidgets('주문이 필요한 질문: 최근 주문을 고르면 주문 상태 답', (t) async {
      final repo = mock(MockChatScenario.realtime);
      await open(t, repo);
      await ask(t, '내 주문 어디쯤이에요?');
      await t.tap(find.byKey(const ValueKey('chat-order-order-seed-4')).first);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-answer-orderStatus')),
        findsOneWidget,
      );
      expect(repo.sentOrderIds, [null, 'order-seed-4']);
    });

    testWidgets('취소 같은 실행 요청: 최근 주문 카드 → 누르면 그 주문 상세(AI 는 취소하지 않는다)', (
      t,
    ) async {
      final repo = mock(MockChatScenario.outOfScope);
      await open(t, repo);
      await ask(t, '주문 취소해 주세요');
      expect(
        find.byKey(const ValueKey('chat-answer-outOfScope')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chat-action-orders')), findsOneWidget);
      expect(
        find.text('최근 주문이에요. 주문을 누르면 주문 상세에서 취소·반품을 신청할 수 있는지 볼 수 있어요.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chat-handoff')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chat-order-order-seed-4')).last);
      await t.pumpAndSettle();
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(repo.sentOrderIds, [null], reason: '카드를 눌러도 질문을 다시 보내지 않는다');
    });

    testWidgets('실행 요청의 최근 주문 조회 실패는 오류 + 다시 시도', (t) async {
      final repo = mock(MockChatScenario.outOfScope)
        ..failNextRecentOrders = true;
      await open(t, repo);
      await ask(t, '환불해 주세요');
      expect(
        find.byKey(const ValueKey('chat-action-orders-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('chat-action-orders-empty')),
        findsNothing,
      );
      await t.tap(find.text('다시 시도').last);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-action-orders')), findsOneWidget);
    });

    testWidgets('요청 제한: 서버 안내 문장 + 문의 남기기 버튼', (t) async {
      await open(t, mock(MockChatScenario.rateLimited));
      await ask(t, '또 질문');
      expect(find.byKey(const ValueKey('chat-rejected')), findsOneWidget);
      expect(find.textContaining('질문이 너무 빨라요'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-handoff')), findsOneWidget);
    });

    testWidgets('상담 종류를 고르기 전에는 입력할 수 없다(레퍼런스 2-1)', (t) async {
      await open(t, mock(), general: false);
      expect(find.byKey(const ValueKey('chat-topic-general')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-topic-order')), findsOneWidget);
      expect(
        t.widget<TextField>(find.byKey(const ValueKey('chat-input'))).enabled,
        isFalse,
      );
      await t.tap(find.byKey(const ValueKey('chat-topic-general')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-topic-general-chosen')),
        findsOneWidget,
      );
      expect(
        t.widget<TextField>(find.byKey(const ValueKey('chat-input'))).enabled,
        isTrue,
      );
    });

    // 사용자 2026-11-20: "일반 문의"를 고른 뒤 상담종료를 눌러도 "일반 문의" 칸이 남았다.
    testWidgets('상담종료: 대화와 고른 상담 종류 기록을 모두 비우고 처음 선택으로', (t) async {
      await open(t, mock(), general: false);
      await t.tap(find.byKey(const ValueKey('chat-topic-general')));
      await t.pumpAndSettle();
      await ask(t, '배송비가 얼마예요?');
      expect(
        find.byKey(const ValueKey('chat-topic-general-chosen')),
        findsOneWidget,
      );

      await t.tap(find.byKey(const ValueKey('chat-end')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-end-ok')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-topic-general-chosen')),
        findsNothing,
      );
      expect(find.text('배송비가 얼마예요?'), findsNothing);
      expect(find.byKey(const ValueKey('chat-topic-general')), findsOneWidget);
      expect(
        t.widget<TextField>(find.byKey(const ValueKey('chat-input'))).enabled,
        isFalse,
      );
    });

    testWidgets('주문 건 문의: 최근 주문을 고르면 그 뒤 질문마다 orderId 를 붙인다(레퍼런스 2-4)', (
      t,
    ) async {
      final repo = mock();
      await open(t, repo, general: false);
      await t.tap(find.byKey(const ValueKey('chat-topic-order')));
      await t.pumpAndSettle();
      expect(find.text('최근 주문이에요. 어떤 주문에 대해 문의하시나요?'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byKey(const ValueKey('chat-input'))).enabled,
        isFalse,
      );
      await t.tap(find.byKey(const ValueKey('chat-recent-order-seed-1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-topic-bar')), findsOneWidget);
      // 고르면 바로 응답: 고른 주문 카드 + 안내 + 주문 상세(질문은 대신 보내지 않는다)
      expect(
        find.byKey(const ValueKey('chat-topic-order-ack')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chat-order-order-seed-1')), findsOne);
      expect(find.text('주문 상세 보기'), findsOneWidget);
      expect(repo.sentKeys, isEmpty);
      await ask(t, '언제 와요?');
      await ask(t, '포장은요?');
      expect(repo.sentOrderIds, ['order-seed-1', 'order-seed-1']);
      expect(repo.sentKeys.toSet(), hasLength(2));

      // 종류 바꾸기 → 처음 선택지로
      await t.tap(find.byKey(const ValueKey('chat-topic-change')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-topic-order')), findsOneWidget);
    });

    testWidgets('대화는 한 줄 시간순: 주문 1 → 질문·답 → 종류 바꾸기 → 주문 2 는 앞 대화 아래에 쌓인다', (
      t,
    ) async {
      await open(t, mock(), general: false);
      double y(Finder f) => t.getTopLeft(f).dy;
      await t.tap(find.byKey(const ValueKey('chat-topic-order')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-recent-order-seed-4')));
      await t.pumpAndSettle();
      await ask(t, '첫 주문 언제 와요?');
      final firstQuestion = find.text('첫 주문 언제 와요?');

      await t.tap(find.byKey(const ValueKey('chat-topic-change')));
      await t.pumpAndSettle();
      // 다시 고르는 버튼은 앞 대화 아래(맨 끝)에 나온다.
      expect(
        y(find.byKey(const ValueKey('chat-topic-order')).last),
        greaterThan(y(firstQuestion)),
      );
      await t.tap(find.byKey(const ValueKey('chat-topic-order')).last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-recent-order-seed-1')).last);
      await t.pumpAndSettle();
      await ask(t, '두 번째 주문은요?');

      // 앞에서 고른 주문 1 은 지워지지 않고 그 자리에 남는다.
      final picks = find.byKey(const ValueKey('chat-topic-order-picked'));
      expect(picks, findsNWidgets(2));
      // 시스템 주문 ID 는 보이지 않고 주문 시각 · 상태로 구분한다(주문 1 = 상품 준비 중, 주문 2 = 배송 완료).
      expect(
        find.descendant(
          of: picks.first,
          matching: find.textContaining('상품 준비 중'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('order-seed'), findsNothing);
      // 순서: 주문 1 고름 < 첫 질문 < 주문 2 고름 < 두 번째 질문
      expect(y(picks.first), lessThan(y(firstQuestion)));
      expect(y(firstQuestion), lessThan(y(picks.last)));
      expect(y(picks.last), lessThan(y(find.text('두 번째 주문은요?'))));
    });

    testWidgets('주문을 고른 뒤 "주문 상세 보기" → 그 주문 상세', (t) async {
      await open(t, mock(), general: false);
      await t.tap(find.byKey(const ValueKey('chat-topic-order')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-recent-order-seed-4')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-topic-order-detail')));
      await t.pumpAndSettle();
      expect(find.byType(OrderDetailScreen), findsOneWidget);
    });

    testWidgets('최근 주문 조회 실패는 "주문 없음"이 아니라 오류 — 다시 시도', (t) async {
      final repo = mock()..failNextRecentOrders = true;
      await open(t, repo, general: false);
      await t.tap(find.byKey(const ValueKey('chat-topic-order')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-recent-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-recent-empty')), findsNothing);
      await t.tap(find.byKey(const ValueKey('chat-recent-retry')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-recent-order-seed-4')),
        findsOneWidget,
      );
    });

    testWidgets('최근 주문이 없으면 안내하고 일반 문의로 이어 간다', (t) async {
      final repo = mock()..noRecentOrders = true;
      await open(t, repo, general: false);
      await t.tap(find.byKey(const ValueKey('chat-topic-order')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-recent-empty')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chat-topic-general-instead')));
      await t.pumpAndSettle();
      await ask(t, '포인트는요?');
      expect(repo.sentOrderIds, [null]);
    });

    testWidgets('응답 유실: "다시 확인"으로 같은 질문의 답을 받는다', (t) async {
      final repo = mock(MockChatScenario.lostOnce);
      await open(t, repo);
      await ask(t, '유실');
      expect(find.byKey(const ValueKey('chat-unknown')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chat-recheck')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-answer-answered')),
        findsOneWidget,
      );
      expect(repo.sentKeys.toSet(), hasLength(1));
    });
  });
}
