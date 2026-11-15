import 'package:pmart_core/pmart_core.dart';

import '../domain/inquiry.dart';
import 'inquiries_repository.dart';

/// ⚠ 화면 개발·시험용 목. 실제 case-service 동작이 아니다.
/// 계약의 뜻만 흉내 낸다: 같은 키 = 같은 문의, 남의·없는 주문 422 `ORDER_NOT_FOUND`, 최근 순 목록, 답변은 상담원만.
final class MockInquiriesRepository implements InquiriesRepository {
  MockInquiriesRepository({
    this.latency = const Duration(milliseconds: 300),
    DateTime Function()? now,
    this.pageSize = 20,
    this.knownOrder,
    bool seed = true,
  }) : _now = now ?? DateTime.now {
    if (seed) _seed();
  }

  final Duration latency;
  final DateTime Function() _now;
  final int pageSize;

  /// 본인 주문인지(없으면 모든 주문 ID 를 받는다).
  final bool Function(String orderId)? knownOrder;

  final _items = <InquiryDetail>[]; // 앞이 최신
  final _byKey = <String, InquiryDetail>{};
  var _seq = 0;

  /// 서버에 도착한 접수 수(같은 키 재전송은 세지 않는다).
  int created = 0;

  /// 마지막으로 접수한 문의가 들어온 곳(시험용).
  InquiryOrigin? lastOrigin;
  String? lastOrderId;

  /// 다음 접수 한 번에 던질 실패(응답 유실 등 시험용). 유실이면 서버에는 접수된 것으로 둔다.
  PmartFailure? failNextCreate;
  bool failNextCreateStored = false;

  void _seed() {
    final t = _now().toUtc();
    _items.addAll([
      InquiryDetail(
        summary: InquirySummary(
          inquiryId: 'inq-seed-2',
          category: InquiryCategory.delivery,
          status: InquiryStatus.received,
          createdAt: t.subtract(const Duration(hours: 3)),
          title: '배송 문의',
        ),
        body: '배송 완료라고 뜨는데 아직 못 받았어요.',
        replies: const [],
      ),
      InquiryDetail(
        summary: InquirySummary(
          inquiryId: 'inq-seed-1',
          category: InquiryCategory.product,
          status: InquiryStatus.answered,
          createdAt: t.subtract(const Duration(days: 2)),
          answeredAt: t.subtract(const Duration(days: 1, hours: 20)),
        ),
        body: '우유 소비기한이 얼마나 남은 상품이 오나요?',
        replies: [
          InquiryReply(
            replyId: 'rep-seed-1',
            body: '[목 답변] 냉장 상품은 남은 기한을 확인하고 보내 드려요.',
            createdAt: t.subtract(const Duration(days: 1, hours: 20)),
          ),
        ],
      ),
    ]);
  }

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  /// 상담원 답변을 흉내 낸다(시험용).
  void answer(String inquiryId, String body) {
    final i = _items.indexWhere((x) => x.summary.inquiryId == inquiryId);
    if (i < 0) return;
    final old = _items[i];
    final at = _now().toUtc();
    final next = InquiryDetail(
      summary: InquirySummary(
        inquiryId: old.summary.inquiryId,
        category: old.summary.category,
        status: InquiryStatus.answered,
        createdAt: old.summary.createdAt,
        orderId: old.summary.orderId,
        title: old.summary.title,
        answeredAt: at,
      ),
      body: old.body,
      replies: [
        ...old.replies,
        InquiryReply(
          replyId: 'rep-${old.replies.length + 1}',
          body: body,
          createdAt: at,
        ),
      ],
    );
    _items[i] = next;
    _byKey.updateAll((_, v) => v.summary.inquiryId == inquiryId ? next : v);
  }

  @override
  Future<InquiryDetail> create(
    InquiryDraft draft, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    final saved = _byKey[key.value];
    if (saved != null) return saved;
    final fail = failNextCreate;
    if (fail != null && !failNextCreateStored) {
      failNextCreate = null;
      throw fail;
    }
    final orderId = draft.orderId;
    if (orderId != null && !(knownOrder?.call(orderId) ?? true)) {
      throw const ProblemFailure(
        Problem(status: 422, code: InquiryProblemCode.orderNotFound),
      );
    }
    _seq += 1;
    created += 1;
    lastOrigin = draft.origin;
    lastOrderId = draft.orderId;
    final made = InquiryDetail(
      summary: InquirySummary(
        inquiryId: 'inq-mock-$_seq',
        category: draft.category,
        status: InquiryStatus.received,
        createdAt: _now().toUtc(),
        orderId: orderId,
        title: draft.title,
      ),
      body: draft.body,
      replies: const [],
    );
    _byKey[key.value] = made;
    _items.insert(0, made);
    if (fail != null) {
      failNextCreate = null;
      failNextCreateStored = false;
      throw fail;
    }
    return made;
  }

  @override
  Future<InquiryPage> list({String? cursor}) async {
    await _wait();
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, _items.length);
    return InquiryPage(
      items: [for (final i in _items.sublist(start, end)) i.summary],
      nextCursor: end < _items.length ? '$end' : null,
    );
  }

  @override
  Future<InquiryDetail> get(String inquiryId) async {
    await _wait();
    for (final i in _items) {
      if (i.summary.inquiryId == inquiryId) return i;
    }
    throw const ProblemFailure(
      Problem(status: 404, code: ProblemCode.notFound),
    );
  }
}
