import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pmart_api_case/pmart_api_case.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/inquiry.dart';

/// 고객센터 문의(case-service 0.2.0, 게이트웨이 `/api/v1/inquiries/**`). 실패는 [PmartFailure] 로 던진다.
/// 문의 내용은 로그에 남기지 않는다.
abstract interface class InquiriesRepository {
  /// `POST /inquiries`(201). 같은 키로 다시 보내면 같은 문의다(중복 생성 없음).
  /// 422 `ORDER_NOT_FOUND`(남의·없는 주문), 403(비회원), 503(주문 확인 불가 — 같은 키로 다시).
  Future<InquiryDetail> create(
    InquiryDraft draft, {
    required IdempotencyKey key,
  });

  /// `GET /inquiries` — 본인 문의만, 최근 순. 실패는 던진다(빈 목록으로 바꾸지 않는다).
  Future<InquiryPage> list({String? cursor});

  /// `GET /inquiries/{inquiryId}` — 상세 + 답변. 남의 문의는 404.
  Future<InquiryDetail> get(String inquiryId);

  /// `POST /inquiry-photos`(201, case 0.14.0) — 한 장. 돌려준 photoId 를 문의 작성 `photoIds` 에 넣는다.
  /// 같은 키 재전송은 같은 photoId. 422 PHOTO_INVALID, 503 저장소 없음(글은 그대로 남길 수 있다).
  Future<String> uploadPhoto(
    Uint8List bytes, {
    required String name,
    required IdempotencyKey key,
  });

  /// `GET /inquiry-photos/{photoId}` — 이미지 바이트(본인 토큰, 공유 캐시 금지).
  Future<Uint8List> photo(String photoId);

  /// `POST /inquiries/{id}/satisfaction`(case 0.15.0) — 답변 뒤 한 번. 409 INQUIRY_NOT_ANSWERED·ALREADY_RATED.
  Future<InquiryDetail> rate(
    String inquiryId, {
    required int score,
    String? comment,
    required IdempotencyKey key,
  });

  /// `POST /inquiries/{id}/closures`(case 0.19.0) — 닫기(다시 열기 없음). 이미 닫힘 409 INQUIRY_CLOSED.
  Future<InquiryDetail> close(String inquiryId, {required IdempotencyKey key});
}

final class ApiInquiriesRepository implements InquiriesRepository {
  ApiInquiriesRepository(Dio dio)
    : _api = api.PmartApiCase(dio: dio).getInquiriesApi(),
      _photos = api.PmartApiCase(dio: dio).getInquiryPhotosApi();

  final api.InquiriesApi _api;
  final api.InquiryPhotosApi _photos;

  @override
  Future<String> uploadPhoto(
    Uint8List bytes, {
    required String name,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _photos.uploadInquiryPhoto(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        file: MultipartFile.fromBytes(bytes, filename: name),
        extra: commandOptions(key).extra,
      ),
    );
    return (res.data ?? (throw UnknownResultFailure(requestId: key.value)))
        .photoId;
  }

  @override
  Future<Uint8List> photo(String photoId) async {
    final res = await pmartGuard(
      () => _photos.getInquiryPhoto(photoId: photoId),
    );
    return res.data ?? (throw const ContractViolationFailure('문의 사진 본문 없음'));
  }

  @override
  Future<InquiryDetail> rate(
    String inquiryId, {
    required int score,
    String? comment,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.rateInquiry(
        inquiryId: inquiryId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        rateInquiryRequest: api.RateInquiryRequest(
          score: score,
          comment: comment,
        ),
        extra: commandOptions(key).extra,
      ),
    );
    return inquiryFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<InquiryDetail> close(
    String inquiryId, {
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.closeInquiry(
        inquiryId: inquiryId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        closeInquiryRequest: api.CloseInquiryRequest(),
        extra: commandOptions(key).extra,
      ),
    );
    return inquiryFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<InquiryDetail> create(
    InquiryDraft draft, {
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.createInquiry(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        createInquiryRequest: api.CreateInquiryRequest(
          category: _categoryToContract(draft.category),
          orderId: draft.orderId,
          title: draft.title,
          body: draft.body,
          origin: switch (draft.origin) {
            InquiryOrigin.inquiryPage =>
              api.CreateInquiryRequestOriginEnum.INQUIRY_PAGE,
            InquiryOrigin.assistantHandoff =>
              api.CreateInquiryRequestOriginEnum.ASSISTANT_HANDOFF,
          },
          deliveryIssue: switch (draft.deliveryIssue) {
            DeliveryIssue.delayed => api.InquiryDeliveryIssue.DELAYED,
            DeliveryIssue.notReceived => api.InquiryDeliveryIssue.NOT_RECEIVED,
            DeliveryIssue.misdelivered => api.InquiryDeliveryIssue.MISDELIVERED,
            null => null,
          },
          deliveryId: draft.deliveryId,
          photoIds: draft.photoIds.isEmpty ? null : draft.photoIds,
        ),
        extra: commandOptions(key).extra,
      ),
    );
    return inquiryFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<InquiryPage> list({String? cursor}) async {
    final res = await pmartGuard(() => _api.listInquiries(cursor: cursor));
    final data =
        res.data ?? (throw const ContractViolationFailure('문의 목록 본문 없음'));
    final items =
        data.items ?? (throw const ContractViolationFailure('문의 목록 items 없음'));
    return InquiryPage(
      items: [for (final s in items) inquirySummaryFromContract(s)],
      nextCursor: switch (data.page?.nextCursor) {
        final String c when c.isNotEmpty => c,
        _ => null,
      },
    );
  }

  @override
  Future<InquiryDetail> get(String inquiryId) async {
    final res = await pmartGuard(() => _api.getInquiry(inquiryId: inquiryId));
    return inquiryFromContract(
      res.data ?? (throw const ContractViolationFailure('Inquiry 본문 없음')),
    );
  }
}

api.InquiryCategory _categoryToContract(InquiryCategory c) => switch (c) {
  InquiryCategory.order => api.InquiryCategory.ORDER,
  InquiryCategory.delivery => api.InquiryCategory.DELIVERY,
  InquiryCategory.payment => api.InquiryCategory.PAYMENT,
  InquiryCategory.refund => api.InquiryCategory.REFUND,
  InquiryCategory.product => api.InquiryCategory.PRODUCT,
  InquiryCategory.account => api.InquiryCategory.ACCOUNT,
  InquiryCategory.other => api.InquiryCategory.OTHER,
};

String? _text(String? v) => (v == null || v.trim().isEmpty) ? null : v;

InquirySummary inquirySummaryFromContract(api.InquirySummary s) =>
    InquirySummary(
      inquiryId: s.inquiryId,
      category: InquiryCategory.fromWire(s.category.value),
      status: InquiryStatus.fromWire(s.status.value),
      createdAt: s.createdAt,
      orderId: _text(s.orderId),
      title: _text(s.title),
      answeredAt: s.answeredAt,
    );

InquiryDetail inquiryFromContract(api.Inquiry i) => InquiryDetail(
  summary: InquirySummary(
    inquiryId: i.inquiryId,
    category: InquiryCategory.fromWire(i.category.value),
    status: InquiryStatus.fromWire(i.status.value),
    createdAt: i.createdAt,
    orderId: _text(i.orderId),
    title: _text(i.title),
    answeredAt: i.answeredAt,
  ),
  body: i.body,
  replies: [
    for (final r in i.replies)
      // 본문 없는 답변은 빈 말풍선으로 그리지 않는다.
      if (_text(r.body) case final body?)
        InquiryReply(replyId: r.replyId, body: body, createdAt: r.createdAt),
  ],
  photoIds: [for (final p in i.photos ?? const <api.InquiryPhoto>[]) p.photoId],
  satisfaction: switch (i.satisfaction) {
    null => null,
    final s => InquirySatisfactionView(
      score: s.score,
      comment: _text(s.comment),
    ),
  },
  closedAt: i.closedAt,
);
