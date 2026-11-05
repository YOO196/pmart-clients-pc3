import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../claims/presentation/claims_controller.dart'
    show CommandDone, CommandOutcome, CommandRejected, CommandUnknown;
import '../data/mock_reviews_repository.dart';
import '../data/reviews_repository.dart';
import '../domain/reviews.dart';

final reviewsRepositoryProvider = Provider<ReviewsRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockReviewsRepository(),
    // review-service 는 아직 백엔드에 구현·게이트웨이 경로가 없다(2026-11-04). 호출은 실패하고 화면은 실패 상태를 보인다.
    PmartEnv.local => ApiReviewsRepository(ref.watch(dioProvider)),
  },
);

/// 누적 페이지. 다음 묶음 실패는 받은 목록을 지우지 않고 [loadMoreFailure] 로만 보인다.
@immutable
class PagedList<T> {
  const PagedList({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreFailure,
    this.averageRating,
    this.reviewCount,
  });

  final List<T> items;
  final String? nextCursor;
  final bool loadingMore;
  final PmartFailure? loadMoreFailure;

  /// 상품 리뷰 목록의 서버 요약(`summary`). 그 밖에는 null.
  final double? averageRating;
  final int? reviewCount;

  bool get hasMore => nextCursor != null;

  PagedList<T> copyWith({
    List<T>? items,
    String? nextCursor,
    bool loadingMore = false,
    PmartFailure? loadMoreFailure,
  }) => PagedList(
    items: items ?? this.items,
    nextCursor: nextCursor,
    loadingMore: loadingMore,
    loadMoreFailure: loadMoreFailure,
    averageRating: averageRating,
    reviewCount: reviewCount,
  );
}

/// 리뷰 자격 목록 하나(작성 가능 / 내가 쓴 리뷰). 비회원이면 null — 호출하지 않는다(빈 목록과 구분).
abstract class _EligibilityList
    extends AsyncNotifier<PagedList<ReviewEligibility>?> {
  ReviewState? get serverState;
  bool keep(ReviewEligibility e);

  @override
  Future<PagedList<ReviewEligibility>?> build() async {
    if (ref.watch(sessionProvider) is! MemberSession) return null;
    final page = await ref
        .watch(reviewsRepositoryProvider)
        .eligibilities(state: serverState);
    return PagedList(
      items: page.items.where(keep).toList(),
      nextCursor: page.nextCursor,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      current.copyWith(nextCursor: current.nextCursor, loadingMore: true),
    );
    try {
      final page = await ref
          .read(reviewsRepositoryProvider)
          .eligibilities(state: serverState, cursor: current.nextCursor);
      if (!ref.mounted) return;
      final seen = {for (final e in current.items) e.orderLineId};
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            ...page.items.where(
              (e) => keep(e) && !seen.contains(e.orderLineId),
            ),
          ],
          nextCursor: page.nextCursor,
        ),
      );
    } on PmartFailure catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(nextCursor: current.nextCursor, loadMoreFailure: e),
      );
    }
  }
}

/// "리뷰 쓰기": 서버가 작성 가능(`REV_ELIGIBLE`)이라고 준 품목. 기한은 서버 `eligibleUntil` 을 보이기만 한다.
final writableReviewsProvider =
    AsyncNotifierProvider.autoDispose<
      WritableReviews,
      PagedList<ReviewEligibility>?
    >(WritableReviews.new);

class WritableReviews extends _EligibilityList {
  @override
  ReviewState? get serverState => ReviewState.eligible;

  @override
  bool keep(ReviewEligibility e) => e.writable;
}

/// "내가 쓴 리뷰": 내 리뷰 목록 경로가 계약에 없어 자격 목록의 `reviewId` 로 조합한다(본문은 [reviewProvider]).
final myReviewsProvider =
    AsyncNotifierProvider.autoDispose<MyReviews, PagedList<ReviewEligibility>?>(
      MyReviews.new,
    );

class MyReviews extends _EligibilityList {
  @override
  ReviewState? get serverState => null;

  @override
  bool keep(ReviewEligibility e) => e.written;
}

final reviewProvider = FutureProvider.autoDispose.family<ReviewView, String>(
  (ref, reviewId) => ref.watch(reviewsRepositoryProvider).get(reviewId),
);

/// 주문 하나의 리뷰 자격(주문 상세). 비회원이면 null.
final orderReviewEligibilitiesProvider = FutureProvider.autoDispose
    .family<List<ReviewEligibility>?, String>((ref, orderId) async {
      if (ref.watch(sessionProvider) is! MemberSession) return null;
      final repo = ref.watch(reviewsRepositoryProvider);
      final out = <ReviewEligibility>[];
      String? cursor;
      // 주문 하나의 품목 수만큼이라 몇 묶음 안에 끝난다. 끝없이 돌지 않게 상한을 둔다.
      for (var i = 0; i < 10; i++) {
        final page = await repo.eligibilities(orderId: orderId, cursor: cursor);
        out.addAll(page.items.where((e) => e.orderId == orderId));
        cursor = page.nextCursor;
        if (cursor == null) break;
      }
      return out;
    });

/// 상품 리뷰 목록(공개). 비회원도 본다.
final productReviewsProvider = AsyncNotifierProvider.autoDispose
    .family<ProductReviews, PagedList<ReviewView>, String>(ProductReviews.new);

class ProductReviews extends AsyncNotifier<PagedList<ReviewView>> {
  ProductReviews(this.productId);

  final String productId;

  @override
  Future<PagedList<ReviewView>> build() async {
    final page = await ref
        .watch(reviewsRepositoryProvider)
        .productReviews(productId);
    return PagedList(
      items: page.items,
      nextCursor: page.nextCursor,
      averageRating: page.averageRating,
      reviewCount: page.reviewCount,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      current.copyWith(nextCursor: current.nextCursor, loadingMore: true),
    );
    try {
      final page = await ref
          .read(reviewsRepositoryProvider)
          .productReviews(productId, cursor: current.nextCursor);
      if (!ref.mounted) return;
      final seen = {for (final r in current.items) r.reviewId};
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            ...page.items.where((r) => !seen.contains(r.reviewId)),
          ],
          nextCursor: page.nextCursor,
        ),
      );
    } on PmartFailure catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(nextCursor: current.nextCursor, loadMoreFailure: e),
      );
    }
  }
}

/// 리뷰 작성. 한 번 누르면 한 번만 보낸다.
/// - 결과를 모르면(5xx·타임아웃) 다시 보내지 않고 이 주문의 자격을 조회해 `reviewId` 가 생겼는지 확인한다.
/// - 그래도 모르면 키와 본문을 보관한다. "다시 확인"을 누를 때만 **같은 키·같은 본문**으로 다시 보낸다(새 리뷰가 아니다).
/// - Problem 응답은 거절로 끝내고 키를 버린다(다음 등록은 새 사용자 행위 = 새 키).
class ReviewSubmitter {
  ReviewSubmitter(this._repo, this.target);

  final ReviewsRepository _repo;
  final ReviewTarget target;

  IdempotencyKey? _key;
  ({int rating, String? text})? _body;

  /// 결과를 모르는 채 보관 중인 요청이 있다(입력을 바꾸면 안 된다).
  bool get pending => _key != null;

  Future<CommandOutcome<ReviewView>> submit({
    required int rating,
    String? text,
  }) async {
    final body = _body ??= (rating: rating, text: text);
    final key = _key ??= IdempotencyKey.generate();
    try {
      final review = await _repo.create(
        orderLineId: target.orderLineId,
        rating: body.rating,
        text: body.text,
        key: key,
      );
      _clear();
      return CommandDone(review);
    } on UnknownResultFailure {
      // 반영 여부를 모른다. 아래에서 조회로 확인한다.
    } on ProblemFailure catch (f) {
      _clear();
      return CommandRejected(f.problem.code);
    } on PmartFailure {
      // Problem 이 아닌 4xx(경로 없음 등)·세션 만료: 반영되지 않았다.
      _clear();
      return const CommandRejected(ProblemCode.unknown);
    }
    try {
      final page = await _repo.eligibilities(orderId: target.orderId);
      final e = page.items
          .where((e) => e.orderLineId == target.orderLineId)
          .firstOrNull;
      if (e?.reviewId case final id?) {
        final review = await _repo.get(id);
        _clear();
        return CommandDone(review);
      }
    } on PmartFailure {
      // 조회도 실패했다. 모르는 채로 둔다.
    }
    return const CommandUnknown();
  }

  void _clear() {
    _key = null;
    _body = null;
  }
}
