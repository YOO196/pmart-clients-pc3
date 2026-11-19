import 'dart:typed_data';

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
  DeliveryIssue? lastDeliveryIssue;
  String? lastDeliveryId;
  InquiryCategory? lastCategory;

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
      photoIds: old.photoIds,
      satisfaction: old.satisfaction,
      closedAt: old.closedAt,
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
    // 서버처럼 내가 올린, 아직 안 붙은 사진만 받는다(하나라도 아니면 문의도 남지 않음).
    if (draft.photoIds.any(
      (p) => !photos.containsKey(p) || _attached.contains(p),
    )) {
      throw const ProblemFailure(
        Problem(status: 422, code: InquiryProblemCode.photoNotFound),
      );
    }
    _attached.addAll(draft.photoIds);
    _seq += 1;
    created += 1;
    lastOrigin = draft.origin;
    lastOrderId = draft.orderId;
    lastDeliveryIssue = draft.deliveryIssue;
    lastDeliveryId = draft.deliveryId;
    lastCategory = draft.category;
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
      photoIds: draft.photoIds,
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

  /// 올린 사진(photoId → 바이트), 아직 문의에 안 붙은 것 포함.
  final photos = <String, Uint8List>{};
  final _photoByKey = <String, String>{};
  final _attached = <String>{};

  /// 다음 사진 올리기를 한 번 실패시킨다(시험용).
  PmartFailure? failNextUpload;

  /// 받은 만족도·닫기 명령 키(시험용).
  final rateKeys = <String>[];
  final closeKeys = <String>[];

  int _index(String inquiryId) {
    final i = _items.indexWhere((x) => x.summary.inquiryId == inquiryId);
    if (i < 0) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    return i;
  }

  InquiryDetail _replace(
    int i, {
    InquiryStatus? status,
    InquirySatisfactionView? satisfaction,
    DateTime? closedAt,
  }) {
    final old = _items[i];
    final next = InquiryDetail(
      summary: InquirySummary(
        inquiryId: old.summary.inquiryId,
        category: old.summary.category,
        status: status ?? old.summary.status,
        createdAt: old.summary.createdAt,
        orderId: old.summary.orderId,
        title: old.summary.title,
        answeredAt: old.summary.answeredAt,
      ),
      body: old.body,
      replies: old.replies,
      photoIds: old.photoIds,
      satisfaction: satisfaction ?? old.satisfaction,
      closedAt: closedAt ?? old.closedAt,
    );
    _items[i] = next;
    return next;
  }

  @override
  Future<String> uploadPhoto(
    Uint8List bytes, {
    required String name,
    required IdempotencyKey key,
  }) async {
    await _wait();
    final fail = failNextUpload;
    if (fail != null) {
      failNextUpload = null;
      throw fail;
    }
    final known = _photoByKey[key.value];
    if (known != null) return known;
    final id = 'inq-photo-${photos.length + 1}';
    photos[id] = bytes;
    _photoByKey[key.value] = id;
    return id;
  }

  @override
  Future<Uint8List> photo(String photoId) async {
    await _wait();
    return photos[photoId] ??
        (throw const ProblemFailure(
          Problem(status: 404, code: ProblemCode.notFound),
        ));
  }

  @override
  Future<InquiryDetail> rate(
    String inquiryId, {
    required int score,
    String? comment,
    required IdempotencyKey key,
  }) async {
    await _wait();
    rateKeys.add(key.value);
    final i = _index(inquiryId);
    final d = _items[i];
    if (d.replies.isEmpty) {
      throw const ProblemFailure(
        Problem(status: 409, code: InquiryProblemCode.notAnswered),
      );
    }
    if (d.satisfaction != null) {
      throw const ProblemFailure(
        Problem(status: 409, code: InquiryProblemCode.alreadyRated),
      );
    }
    return _replace(
      i,
      satisfaction: InquirySatisfactionView(score: score, comment: comment),
    );
  }

  @override
  Future<InquiryDetail> close(
    String inquiryId, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    closeKeys.add(key.value);
    final i = _index(inquiryId);
    if (_items[i].closed) {
      throw const ProblemFailure(
        Problem(status: 409, code: InquiryProblemCode.inquiryClosed),
      );
    }
    return _replace(i, status: InquiryStatus.closed, closedAt: _now().toUtc());
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
