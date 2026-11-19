import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../data/inquiries_repository.dart';
import '../data/mock_inquiries_repository.dart';
import '../domain/inquiry.dart';

final inquiriesRepositoryProvider = Provider<InquiriesRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockInquiriesRepository(now: ref.watch(clockProvider)),
    PmartEnv.local => ApiInquiriesRepository(ref.watch(dioProvider)),
  },
);

/// 내 문의 목록(최근 순). 비회원이면 null(빈 목록과 구분). 조회 실패는 실패로 남는다.
@immutable
class InquiryListState {
  const InquiryListState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  final List<InquirySummary> items;
  final String? nextCursor;
  final bool loadingMore;

  /// 다음 쪽 조회 실패 — 이미 받은 줄은 그대로 두고 "더 보기"를 다시 누르게 한다.
  final bool moreFailed;
}

class InquiryListController extends AsyncNotifier<InquiryListState?> {
  @override
  Future<InquiryListState?> build() async {
    if (ref.watch(sessionProvider) is! MemberSession) return null;
    final page = await ref.watch(inquiriesRepositoryProvider).list();
    return InquiryListState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final s = state.value;
    final cursor = s?.nextCursor;
    if (s == null || cursor == null || s.loadingMore) return;
    state = AsyncData(
      InquiryListState(items: s.items, nextCursor: cursor, loadingMore: true),
    );
    try {
      final page = await ref
          .read(inquiriesRepositoryProvider)
          .list(cursor: cursor);
      state = AsyncData(
        InquiryListState(
          items: [...s.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on PmartFailure {
      state = AsyncData(
        InquiryListState(items: s.items, nextCursor: cursor, moreFailed: true),
      );
    }
  }
}

final inquiryListProvider =
    AsyncNotifierProvider.autoDispose<InquiryListController, InquiryListState?>(
      InquiryListController.new,
    );

final inquiryProvider = FutureProvider.autoDispose
    .family<InquiryDetail, String>(
      (ref, inquiryId) => ref.watch(inquiriesRepositoryProvider).get(inquiryId),
    );

/// 문의 사진 바이트(본인 토큰). 실패는 실패로(빈 칸으로 바꾸지 않는다).
final inquiryPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, photoId) => ref.watch(inquiriesRepositoryProvider).photo(photoId),
    );

/// 만족도·닫기처럼 서버가 바뀐 문의를 돌려주는 명령. 결과를 모르면 같은 키로 한 번 더 보내고,
/// 그래도 모르면 상세를 다시 읽어 [applied] 로 반영 여부를 본다. 거절(Problem)은 그대로 던진다.
Future<InquiryDetail?> runInquiryCommand(
  WidgetRef ref,
  String inquiryId,
  Future<InquiryDetail> Function(IdempotencyKey key) send, {
  required bool Function(InquiryDetail d) applied,
}) async {
  final key = IdempotencyKey.generate();
  for (var i = 0; i < 2; i++) {
    try {
      final d = await send(key);
      ref.invalidate(inquiryProvider(inquiryId));
      ref.invalidate(inquiryListProvider);
      return d;
    } on ProblemFailure {
      rethrow;
    } on PmartFailure {
      continue;
    }
  }
  try {
    final d = await ref.read(inquiriesRepositoryProvider).get(inquiryId);
    ref.invalidate(inquiryProvider(inquiryId));
    return applied(d) ? d : null;
  } on PmartFailure {
    return null;
  }
}

@immutable
sealed class InquirySubmitOutcome {
  const InquirySubmitOutcome();
}

final class InquirySubmitted extends InquirySubmitOutcome {
  const InquirySubmitted(this.inquiry);

  final InquiryDetail inquiry;
}

/// 서버가 거절했다(확정). [code] 는 Problem code.
final class InquiryRejected extends InquirySubmitOutcome {
  const InquiryRejected(this.code, {this.status});

  final String code;
  final int? status;
}

/// 접수됐는지 모른다(타임아웃·5xx·503). 같은 키로만 다시 보낸다 — 서버는 같은 키를 같은 문의로 본다.
final class InquiryUnknown extends InquirySubmitOutcome {
  const InquiryUnknown();
}

/// 문의 남기기. 한 번 누르면 한 번만 보낸다.
/// 결과를 모르면 키와 본문을 보관해 두고, 사용자가 "다시 확인"을 누르면 **같은 키·같은 본문**으로 다시 보낸다
/// (새 문의가 아니다). 그동안 본문을 고칠 수 없게 화면이 잠근다.
class InquirySubmitter {
  InquirySubmitter(this._repo);

  final InquiriesRepository _repo;
  IdempotencyKey? _key;
  InquiryDraft? _pending;

  /// 결과를 모르는 접수가 남아 있다.
  bool get hasPending => _pending != null;

  Future<InquirySubmitOutcome> submit(InquiryDraft draft) async {
    final sending = _pending ?? draft;
    final key = _key ??= IdempotencyKey.generate();
    _pending = sending;
    try {
      final made = await _repo.create(sending, key: key);
      _clear();
      return InquirySubmitted(made);
    } on ProblemFailure catch (f) {
      _clear();
      return InquiryRejected(f.problem.code, status: f.problem.status);
    } on PmartFailure {
      return const InquiryUnknown();
    }
  }

  void _clear() {
    _key = null;
    _pending = null;
  }
}
