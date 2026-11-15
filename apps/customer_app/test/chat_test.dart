import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_customer_assistant/pmart_api_customer_assistant.dart'
    as api;
import 'package:pmart_ui/pmart_ui.dart';

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

    testWidgets('답변과 근거 보기', (t) async {
      await open(t, mock());
      await ask(t, '준비 중인 주문도 취소돼요?');
      expect(
        find.byKey(const ValueKey('chat-answer-answered')),
        findsOneWidget,
      );
      expect(find.textContaining('[목 답변]'), findsOneWidget);
      expect(find.textContaining('[목 근거]'), findsNothing); // 접혀 있다
      await t.tap(find.byKey(const ValueKey('chat-citations')));
      await t.pumpAndSettle();
      expect(find.textContaining('[목 근거]'), findsOneWidget);
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

    testWidgets('요청 제한: 서버 안내 문장 + 문의 남기기 버튼', (t) async {
      await open(t, mock(MockChatScenario.rateLimited));
      await ask(t, '또 질문');
      expect(find.byKey(const ValueKey('chat-rejected')), findsOneWidget);
      expect(find.textContaining('질문이 너무 빨라요'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-handoff')), findsOneWidget);
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
