import 'package:flutter/foundation.dart';

/// 고객센터 AI 상담(customer-assistant-service 0.1.0, 백엔드 요청 2026-11-09 customer-chat-assistant).
/// 회원만. 질문 하나씩 답한다(앞 질문을 기억하지 않는다). AI 상담은 취소·환불을 실행하지 않는다.
/// 답변·근거는 서버 값 그대로 보인다 — 앱이 지어내지 않는다.

/// 계약 한도.
const chatQuestionMax = 500;

/// 계약 `CustomerAnswerState`. PROCESSING 은 202(처리 중)에서만 온다.
enum ChatAnswerState {
  answered,
  noGrounding,
  realtimeDataRequired,
  orderStatus,
  outOfScope,
  processing;

  /// 모르는 값은 null(계약 위반으로 다룬다 — 답으로 그리지 않는다).
  static ChatAnswerState? fromWire(String? wire) => switch (wire) {
    'ANSWERED' => answered,
    'NO_GROUNDING' => noGrounding,
    'REALTIME_DATA_REQUIRED' => realtimeDataRequired,
    'ORDER_STATUS' => orderStatus,
    'OUT_OF_SCOPE' => outOfScope,
    'PROCESSING' => processing,
    _ => null,
  };
}

@immutable
class ChatCitation {
  const ChatCitation({
    required this.title,
    required this.excerpt,
    this.section,
  });

  final String title;
  final String? section;
  final String excerpt;
}

/// 주문 요약(서버가 응답 때마다 새로 읽은 값). 상태 이름은 서버 문구([statusLabel])를 그대로 보인다.
@immutable
class ChatOrder {
  const ChatOrder({
    required this.orderId,
    required this.statusLabel,
    this.orderedAt,
    this.itemCount,
    this.totalAmount,
    this.arrivalDate,
    this.arrivalStart,
    this.arrivalEnd,
  });

  final String orderId;
  final String statusLabel;
  final DateTime? orderedAt;
  final int? itemCount;
  final int? totalAmount;

  /// 도착 예정 시간대(Asia/Seoul 벽시계 문자열 그대로 — 서버가 만든 값).
  final String? arrivalDate;
  final String? arrivalStart;
  final String? arrivalEnd;
}

/// 고객센터 문의 남기기 연결.
@immutable
class ChatHandoff {
  const ChatHandoff({required this.message, this.buttonLabel, this.orderId});

  final String message;
  final String? buttonLabel;
  final String? orderId;
}

@immutable
class ChatAnswer {
  const ChatAnswer({
    required this.answerId,
    required this.state,
    required this.answer,
    this.citations = const [],
    this.order,
    this.recentOrders = const [],
    this.handoff,
    this.extractive = false,
  });

  final String answerId;
  final ChatAnswerState state;
  final String answer;
  final List<ChatCitation> citations;
  final ChatOrder? order;

  /// `REALTIME_DATA_REQUIRED` 일 때 고를 최근 주문.
  final List<ChatOrder> recentOrders;
  final ChatHandoff? handoff;

  /// 안내 원문 발췌(`BASELINE_EXTRACTIVE`).
  final bool extractive;
}

/// 상담 종류(레퍼런스 "채팅 상담 선택 — 일반 문의 / 주문 건에 대한 문의").
/// 화면 안 구분일 뿐 서버에 보내지 않는다 — 주문 건이면 질문마다 `orderId` 를 붙인다.
sealed class ChatTopic {
  const ChatTopic();
}

/// 일반 문의(주문 없이 묻는다).
final class ChatTopicGeneral extends ChatTopic {
  const ChatTopicGeneral();
}

/// 주문 건에 대한 문의 — 아직 주문을 고르는 중.
final class ChatTopicPickingOrder extends ChatTopic {
  const ChatTopicPickingOrder();
}

/// 주문 건에 대한 문의 — 고른 주문으로 묻는다.
final class ChatTopicOrder extends ChatTopic {
  const ChatTopicOrder(this.order);

  final ChatOrder order;
}

abstract final class ChatProblemCode {
  static const rateLimited = 'RATE_LIMITED';
  static const orderNotFound = 'ORDER_NOT_FOUND';
  static const configRequired = 'CONFIG_REQUIRED';
}

/// 질문 한 번의 진행.
enum ChatTurnStatus {
  sending,
  answered,

  /// 서버가 거절했다(확정).
  rejected,

  /// 답을 받았는지 모른다(타임아웃·5xx·처리 중) — 같은 키로만 다시 확인한다.
  unknown,
}

@immutable
class ChatTurn {
  const ChatTurn({
    required this.id,
    required this.question,
    required this.status,
    this.orderId,
    this.answer,
    this.rejectCode,
    this.rejectStatus,
    this.serverDetail,
  });

  /// 질문의 Idempotency-Key 값(화면 키로도 쓴다).
  final String id;
  final String question;
  final String? orderId;
  final ChatTurnStatus status;
  final ChatAnswer? answer;
  final String? rejectCode;
  final int? rejectStatus;

  /// 거절 때 서버가 준 안내 문장(요청 제한 — 백엔드: 그대로 보여도 된다).
  final String? serverDetail;

  ChatTurn copyWith({
    ChatTurnStatus? status,
    ChatAnswer? answer,
    String? rejectCode,
    int? rejectStatus,
    String? serverDetail,
  }) => ChatTurn(
    id: id,
    question: question,
    orderId: orderId,
    status: status ?? this.status,
    answer: answer ?? this.answer,
    rejectCode: rejectCode ?? this.rejectCode,
    rejectStatus: rejectStatus ?? this.rejectStatus,
    serverDetail: serverDetail ?? this.serverDetail,
  );
}
