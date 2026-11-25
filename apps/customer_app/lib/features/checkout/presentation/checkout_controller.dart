import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/order_status.dart';
import '../../../shared/providers.dart';
import '../../../shared/shopping_context.dart';
import '../../address/presentation/address_controller.dart';
import '../../cart/domain/cart.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../coupons/data/coupon_repository.dart' show MockCouponRepository;
import '../../coupons/presentation/coupon_controller.dart'
    show couponRepositoryProvider;
import '../data/checkout_repository.dart';
import '../data/mock_checkout_repository.dart';
import '../data/order_preferences_repository.dart';
import '../domain/checkout.dart';

final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    // 목 주문서는 목 쿠폰함의 쿠폰으로 할인을 흉내 낸다(실서버는 order 가 promotion 에 묻는다).
    PmartEnv.mock =>
      MockCheckoutRepository()
        ..couponOf = switch (ref.watch(couponRepositoryProvider)) {
          final MockCouponRepository m => m.couponJsonOf,
          _ => null,
        },
    PmartEnv.local => ApiCheckoutRepository(ref.watch(dioProvider)),
  },
);

/// 지금 시각. 테스트에서 바꾼다. 서울 날짜·남은 시간 표시에만 쓴다(확정 판단은 서버).
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final orderPreferencesRepositoryProvider = Provider<OrderPreferencesRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockOrderPreferencesRepository(),
    PmartEnv.local => ApiOrderPreferencesRepository(ref.watch(dioProvider)),
  },
);

/// 초안 자원 확보 대기 조회 간격·횟수(계약에 서버 지정 간격이 없다).
final draftPollPolicyProvider = Provider<({Duration interval, int attempts})>(
  (_) => (interval: const Duration(seconds: 2), attempts: 10),
);

/// "주문하기" 한 번에 고객이 고른 배송 조건. 바뀌면 [revision] 이 오르고 초안을 새로 만든다.
@immutable
class CheckoutSetup {
  const CheckoutSetup({
    this.purchaseIntentId,
    this.mode,
    this.window,
    this.outOfStock = OutOfStockPreference.cancelOutOfStockOnly,
    this.deliveryNote = '',
    this.revision = 0,
    this.outOfStockChosen = false,
    this.rememberOutOfStock = false,
    this.couponId,
  });

  final String? purchaseIntentId;
  final DeliveryMode? mode;
  final ArrivalWindow? window;
  final OutOfStockPreference outOfStock;
  final String deliveryNote;
  final int revision;

  /// 고객이 이번에 품절 처리를 직접 골랐다 — 저장된 기본값으로 덮지 않는다.
  final bool outOfStockChosen;

  /// "다음에도 적용"(customer 0.4.0) — 다음 단계로 넘어갈 때 서버에 저장한다.
  final bool rememberOutOfStock;

  /// 고른 장바구니 쿠폰(order 0.18.0). 바꾸면 [revision] 이 올라 주문서를 다시 만든다.
  final String? couponId;

  /// 예약은 슬롯을 골라야 끝난다.
  bool get complete =>
      mode != null && (mode != DeliveryMode.scheduled || window != null);

  CheckoutSetup copyWith({
    String? purchaseIntentId,
    DeliveryMode? mode,
    ArrivalWindow? Function()? window,
    OutOfStockPreference? outOfStock,
    String? deliveryNote,
    bool? outOfStockChosen,
    bool? rememberOutOfStock,
    String? Function()? couponId,
  }) => CheckoutSetup(
    purchaseIntentId: purchaseIntentId ?? this.purchaseIntentId,
    mode: mode ?? this.mode,
    window: window != null ? window() : this.window,
    outOfStock: outOfStock ?? this.outOfStock,
    deliveryNote: deliveryNote ?? this.deliveryNote,
    revision: revision + 1,
    outOfStockChosen: outOfStockChosen ?? this.outOfStockChosen,
    rememberOutOfStock: rememberOutOfStock ?? this.rememberOutOfStock,
    couponId: couponId != null ? couponId() : this.couponId,
  );
}

final checkoutSetupProvider =
    NotifierProvider<CheckoutSetupController, CheckoutSetup>(
      CheckoutSetupController.new,
    );

class CheckoutSetupController extends Notifier<CheckoutSetup> {
  @override
  CheckoutSetup build() => const CheckoutSetup();

  /// 장바구니 "주문하기". 누를 때마다 새 주문 의도를 연다(이전 선택은 유지한다).
  /// 같은 의도로 다시 보내면 서버는 견적 만료 전까지 예전 초안을 그대로 돌려준다 — 장바구니를 바꾼 뒤에도
  /// 최소 주문 미달 초안이 돌아와 넘어가지 못했다(백엔드 안내 2026-10-31 주문서 §3: 진입 1회마다 새 값).
  /// 쿠폰은 주문서마다 새로 고른다(지난 주문에 쓴 쿠폰이 남아 막히지 않게).
  void begin() => state = state.copyWith(
    purchaseIntentId: IdempotencyKey.generate().value,
    couponId: () => null,
  );

  /// 만료된 초안을 다시 만들 때 새 주문 의도를 연다(같은 의도로 보내면 만료 초안이 돌아온다).
  void renewIntent() =>
      state = state.copyWith(purchaseIntentId: IdempotencyKey.generate().value);

  void setMode(DeliveryMode mode) => state = state.copyWith(
    mode: mode,
    window: mode == DeliveryMode.scheduled ? null : () => null,
  );

  void setWindow(ArrivalWindow window) =>
      state = state.copyWith(window: () => window);

  void setOutOfStock(OutOfStockPreference p) =>
      state = state.copyWith(outOfStock: p, outOfStockChosen: true);

  /// 저장된 "다음에도 적용" 값을 기본으로(고객이 이번에 고르기 전에만). 저장된 값이 있으면 체크도 켠다.
  void applySavedOutOfStock(OutOfStockPreference p) {
    if (state.outOfStockChosen) return;
    if (state.outOfStock == p && state.rememberOutOfStock) return;
    state = state.copyWith(outOfStock: p, rememberOutOfStock: true);
  }

  void setRememberOutOfStock(bool v) =>
      state = state.copyWith(rememberOutOfStock: v);

  void setNote(String note) => state = state.copyWith(deliveryNote: note);

  /// 쿠폰 고르기·빼기(null). 같은 값이면 그대로 둔다(주문서를 다시 만들지 않는다).
  void setCoupon(String? couponId) {
    if (state.couponId == couponId) return;
    state = state.copyWith(couponId: () => couponId);
  }

  /// 주문이 확정되면 다음 주문을 위해 비운다.
  void finish() => state = const CheckoutSetup();
}

final deliveryOptionsProvider =
    FutureProvider.autoDispose<List<DeliveryOption>>((ref) async {
      final mfcId = ref.watch(currentMfcIdProvider);
      if (mfcId == null) {
        // 담당 센터가 없으면(권역 밖·주소 없음) 조회할 수 없다. 빈 목록이 아니라 오류다.
        throw const ProblemFailure(
          Problem(status: 422, code: 'OUT_OF_SERVICE_AREA'),
        );
      }
      // 배달팁 적용액은 서버 상품액(장바구니 selectedItemAmount)으로만 묻는다. 모르면 기본 팁만 받는다.
      final itemAmount = ref.watch(
        cartControllerProvider.select((c) => c.value?.cart.selectedItemAmount),
      );
      return ref
          .watch(checkoutRepositoryProvider)
          .options(mfcId, itemAmount: itemAmount);
    });

/// 날짜(서울 `YYYY-MM-DD`)별 슬롯. 실패하면 자동 재시도하지 않는다("다시 조회").
final slotsProvider = FutureProvider.autoDispose.family<List<Slot>, String>((
  ref,
  date,
) async {
  final mfcId = ref.watch(currentMfcIdProvider);
  if (mfcId == null) {
    throw const ProblemFailure(
      Problem(status: 422, code: 'OUT_OF_SERVICE_AREA'),
    );
  }
  return ref.watch(checkoutRepositoryProvider).slots(mfcId, date);
});

/// 주문서 상태.
@immutable
class DraftState {
  const DraftState({
    required this.draft,
    required this.request,
    required this.setupRevision,
    required this.cartVersion,
    this.agreedQuote,
    this.previousQuote,
    this.paying = false,
    this.checkoutUnknown = false,
    this.lastStart,
  });

  final OrderDraft draft;
  final DraftRequest request;
  final int setupRevision;
  final int cartVersion;

  /// 고객이 보고 동의한 견적. 결제 진입의 acceptedQuoteVersion.
  final Quote? agreedQuote;

  /// 견적이 바뀌었을 때 이전 견적(전후 비교용). null 이 아니면 재동의 전이다.
  final Quote? previousQuote;
  final bool paying;

  /// 결제 진입 결과를 모른다. 초안 조회로만 확인한다(결제 버튼을 다시 열지 않는다).
  final bool checkoutUnknown;
  final CheckoutStart? lastStart;

  bool get needsReconsent => previousQuote != null;

  /// 결제 버튼을 열어도 되는지. 결제 진입 전 초안(DRAFT·REVIEW)이고, 막는 사유가 없고,
  /// 최소주문을 채웠고, 재동의가 끝났을 때만. PAY 는 이미 결제 진입한 뒤라 새로 진입하지 않는다.
  bool get canPay =>
      draft.awaitingCheckout &&
      draft.blockers.isEmpty &&
      draft.quote?.minOrderSatisfied == true &&
      agreedQuote != null &&
      !needsReconsent &&
      !paying &&
      !checkoutUnknown &&
      lastStart is! CheckoutAccepted;

  DraftState copyWith({
    OrderDraft? draft,
    Quote? Function()? agreedQuote,
    Quote? Function()? previousQuote,
    bool? paying,
    bool? checkoutUnknown,
    CheckoutStart? Function()? lastStart,
  }) => DraftState(
    draft: draft ?? this.draft,
    request: request,
    setupRevision: setupRevision,
    cartVersion: cartVersion,
    agreedQuote: agreedQuote != null ? agreedQuote() : this.agreedQuote,
    previousQuote: previousQuote != null ? previousQuote() : this.previousQuote,
    paying: paying ?? this.paying,
    checkoutUnknown: checkoutUnknown ?? this.checkoutUnknown,
    lastStart: lastStart != null ? lastStart() : this.lastStart,
  );
}

/// 주문서를 만들 수 없는 이유.
final class CheckoutBlocked implements Exception {
  const CheckoutBlocked(this.reason);

  final CheckoutBlockReason reason;
}

enum CheckoutBlockReason {
  notMember,
  noShoppingAddress,
  noSelectedItems,
  setupIncomplete,
}

/// 배송 선택 "다음"에서 주문서로 넘어가도 되는지(서버 판정만 쓴다).
enum CheckoutGate {
  /// 주문서로 간다(그 밖의 오류·대기는 주문서 화면이 보여 준다).
  proceed,

  /// 서버가 최소 주문금액 미달이라고 했다(초안 blockers 의 MIN_ORDER_AMOUNT 또는 견적 minOrderSatisfied=false).
  /// 부족액은 초안 견적의 minOrderShortfall 로 안내한다.
  minOrderUnmet,

  /// 서버가 초안을 거절했다(계정·권역·상품·가격·센터 변경 등). 사유는 [DraftController] 의 오류로 본다.
  rejected,
}

/// 주문서를 그대로 둔 채 새 초안을 받는 중(라이더 요청사항·품절 시 요청사항을 바꿨을 때). 그동안 주문서는 누를 수 없다.
final draftRenewingProvider = NotifierProvider<DraftRenewing, bool>(
  DraftRenewing.new,
);

class DraftRenewing extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
}

/// 결제 시도가 끝난 뒤 초안이 결제 대기로 돌아오는지 다시 읽는 간격·횟수.
final draftReturnPollIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 1),
);
final draftReturnPollTimesProvider = Provider<int>((_) => 10);

final draftControllerProvider =
    AsyncNotifierProvider<DraftController, DraftState?>(DraftController.new);

class DraftController extends AsyncNotifier<DraftState?> {
  CheckoutRepository get _repo => ref.read(checkoutRepositoryProvider);

  @override
  Future<DraftState?> build() async => null;

  DraftState? get _current => state.value;

  /// 배송 선택 "다음"이 방금 초안을 만들고 확인했다. 바로 이어지는 주문서 진입은 다시 조회하지 않는다.
  bool _justPrepared = false;

  void _set(DraftState next) {
    if (ref.mounted) state = AsyncData(next);
  }

  DraftRequest _request(CheckoutSetup setup) {
    final book = ref.read(addressBookProvider).value;
    if (book == null) {
      throw const CheckoutBlocked(CheckoutBlockReason.notMember);
    }
    final addressId = book.context.shoppingAddressId;
    if (addressId == null) {
      throw const CheckoutBlocked(CheckoutBlockReason.noShoppingAddress);
    }
    final cart = ref.read(cartControllerProvider).value?.cart;
    final shortages = ref.read(stockShortageProvider);
    final lines = [
      for (final l in cart?.lines ?? const <CartLine>[])
        // 숨긴 품목(지금 주소로 배달 안 함)은 선택이 남아 있어도 보내지 않는다 — 같은 422 가 되풀이된다.
        if (l.selected &&
            l.purchasable &&
            !hiddenAtCurrentAddress(l, shortages))
          DraftLine(cartItemId: l.cartItemId, sku: l.sku, quantity: l.quantity),
    ];
    if (lines.isEmpty) {
      throw const CheckoutBlocked(CheckoutBlockReason.noSelectedItems);
    }
    if (!setup.complete || setup.purchaseIntentId == null) {
      throw const CheckoutBlocked(CheckoutBlockReason.setupIncomplete);
    }
    return DraftRequest(
      purchaseIntentId: setup.purchaseIntentId!,
      lines: lines,
      shoppingAddressId: addressId,
      expectedMfcId: book.context.mfcId,
      mode: setup.mode!,
      window: setup.window,
      outOfStock: setup.outOfStock,
      deliveryNote: setup.deliveryNote.trim().isEmpty
          ? null
          : setup.deliveryNote.trim(),
      couponId: setup.couponId,
    );
  }

  /// 주문서 진입. 조건·장바구니가 그대로면 기존 초안을 다시 조회하고(타이머를 새로 시작하지 않는다),
  /// 바뀌었으면 새 초안을 만든다.
  Future<void> enter({bool keepVisible = false}) async {
    final justPrepared = _justPrepared;
    _justPrepared = false;
    final setup = ref.read(checkoutSetupProvider);
    final cartVersion =
        ref.read(cartControllerProvider).value?.cart.version ?? -1;
    final current = _current;
    if (current != null &&
        current.setupRevision == setup.revision &&
        current.cartVersion == cartVersion &&
        !current.draft.expired) {
      // 배송 선택 "다음"(prepare)이 방금 만들고 확인한 초안이면 주문서 진입에서 다시 조회하지 않는다.
      if (!justPrepared) await refresh();
      return;
    }
    // 이미 초안이 있는데 조건·장바구니가 바뀌었다. 같은 의도면 서버가 예전 초안을 돌려주므로 새 의도로 만든다.
    if (current != null) {
      ref.read(checkoutSetupProvider.notifier).renewIntent();
    }
    final setupNow = ref.read(checkoutSetupProvider);
    // 주문서를 그대로 두고 바꾸는 중이면 로딩 화면으로 바꾸지 않는다(화면 전체가 다시 그려지지 않게).
    if (!keepVisible || current == null) state = const AsyncLoading();
    try {
      final request = _request(setupNow);
      final draft = await _createWithResend(request);
      if (ref.mounted) ref.read(stockShortageProvider.notifier).clear();
      _set(
        DraftState(
          draft: draft,
          request: request,
          setupRevision: setupNow.revision,
          cartVersion: cartVersion,
          agreedQuote: draft.quote,
        ),
      );
      await _pollWhileWaiting();
    } on CheckoutBlocked catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
    } on PmartFailure catch (e, st) {
      if (!ref.mounted) return;
      if (e case ProblemFailure(:final problem)
          when problem.code == CheckoutProblemCode.insufficientStock) {
        ref
            .read(stockShortageProvider.notifier)
            .set(
              stockShortagesOf([
                for (final d in problem.details)
                  (field: d.field, reason: d.reason),
              ]),
            );
      }
      state = AsyncError(e, st);
    }
  }

  /// 주문서 진입 전에 초안을 먼저 만들어 서버의 최소 주문 판정을 본다. 앱은 금액을 계산하지 않는다.
  /// 판정 전(견적 없음)이면 막지 않는다 — 주문서가 서버 값으로 다시 막는다(결제 버튼).
  Future<CheckoutGate> prepare() async {
    await enter();
    _justPrepared = state.value != null;
    return switch (state) {
      // 예전 계약(422 거절)도 같은 뜻으로 받는다.
      AsyncError(error: ProblemFailure(:final problem))
          when problem.code == CheckoutProblemCode.minOrderAmount =>
        CheckoutGate.minOrderUnmet,
      AsyncData(value: final DraftState s)
          when s.draft.blockers.contains(DraftBlocker.minOrderAmount) ||
              s.draft.quote?.minOrderSatisfied == false =>
        CheckoutGate.minOrderUnmet,
      AsyncError(error: ProblemFailure(:final problem))
          when CheckoutProblemCode.draftRejections.contains(problem.code) =>
        CheckoutGate.rejected,
      _ => CheckoutGate.proceed,
    };
  }

  Future<OrderDraft> _createWithResend(DraftRequest request) async {
    final key = IdempotencyKey.generate();
    UnknownResultFailure? last;
    for (var i = 0; i < 3; i++) {
      try {
        return await _repo.createDraft(request, key: key);
      } on UnknownResultFailure catch (f) {
        // 같은 키·같은 본문 재전송은 기존 초안을 돌려준다(새 초안을 만들지 않는다).
        last = f;
      }
    }
    throw last!;
  }

  Future<void> _pollWhileWaiting() async {
    final policy = ref.read(draftPollPolicyProvider);
    for (var i = 0; i < policy.attempts; i++) {
      final current = _current;
      if (current == null || current.draft.next != DraftNext.wait) return;
      await Future<void>.delayed(policy.interval);
      if (!ref.mounted) return;
      await refresh();
    }
  }

  /// 초안을 다시 조회한다. 견적이 바뀌었으면 재동의 전까지 결제를 막는다.
  /// 결제창을 닫았거나 실패한 뒤 — 서버가 확보분을 풀고 초안을 결제 대기로 돌리는 데 잠깐 걸린다. 한 번만 읽으면
  /// 아직 "결제 진행 중"이라 [결제하기]가 막힌 채 "결제를 준비하고 있어요"가 남았다(사용자 2026-11-25).
  /// 결제 대기로 돌아올 때까지 1초마다 다시 읽는다(최대 [draftReturnPollTimes] 번).
  Future<void> refreshUntilPayable() async {
    final times = ref.read(draftReturnPollTimesProvider);
    for (var i = 0; i < times; i++) {
      await refresh();
      if (!ref.mounted) return;
      final now = _current;
      if (now == null || now.lastStart is! CheckoutAccepted) return;
      await Future<void>.delayed(ref.read(draftReturnPollIntervalProvider));
      if (!ref.mounted) return;
    }
  }

  Future<void> refresh() async {
    final current = _current;
    if (current == null) return;
    try {
      final draft = await _repo.getDraft(current.draft.draftId);
      if (!ref.mounted) return;
      final latest = _current ?? current;
      final agreed = latest.agreedQuote;
      final changed =
          agreed != null &&
          draft.quote != null &&
          draft.quote!.version != agreed.version &&
          !latest.needsReconsent;
      // 결제 진입 결과 불명의 짝 조회: 초안의 결제가 시작됐으면 진입이 받아들여진 것이다.
      // 아직 시작 전이면 계속 "확인 중"이다(실패로 단정하지 않는다).
      final started =
          draft.status == OrderStatus.paymentPending ||
          switch (draft.resources?.payment) {
            PaymentProgress.started ||
            PaymentProgress.approved ||
            PaymentProgress.failed ||
            PaymentProgress.mismatch => true,
            _ => false,
          };
      final resolved = latest.checkoutUnknown && started;
      _set(
        latest.copyWith(
          draft: draft,
          previousQuote: changed ? () => agreed : null,
          checkoutUnknown: latest.checkoutUnknown && !started,
          lastStart: resolved
              ? () => CheckoutAccepted(draft.draftId)
              // 결제 시도가 끝나 초안으로 돌아왔다(실패·취소). 새 키로 다시 결제 진입할 수 있다.
              : draft.awaitingCheckout && latest.lastStart is CheckoutAccepted
              ? () => null
              : null,
        ),
      );
    } on PmartFailure catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
    }
  }

  /// 바뀐 견적에 동의한다.
  void agreeToNewQuote() {
    final current = _current;
    if (current == null || current.draft.quote == null) return;
    _set(
      current.copyWith(
        agreedQuote: () => current.draft.quote,
        previousQuote: () => null,
        lastStart: () => null,
      ),
    );
  }

  /// "결제하기". 고객이 동의한 견적 버전으로 결제 진입을 요청한다.
  Future<CheckoutStart?> pay() async {
    final current = _current;
    if (current == null || !current.canPay) return null;
    _set(current.copyWith(paying: true, lastStart: () => null));
    final start = await _repo.startCheckout(
      current.draft.draftId,
      expectedVersion: current.draft.version,
      acceptedQuoteVersion: current.agreedQuote!.version,
      key: IdempotencyKey.generate(),
    );
    if (!ref.mounted) return start;
    _set(
      (_current ?? current).copyWith(
        paying: false,
        checkoutUnknown: start is CheckoutUnknown,
        lastStart: () => start,
      ),
    );
    if (start is CheckoutReQuote) await refresh();
    if (start is CheckoutUnknown) await refresh();
    return start;
  }

  /// 주문서를 새로 만든다. 만료된 초안이면 새 주문 의도로(⑤ 안내 §3), 그 밖(조회 오류 재시도)은 같은 의도로.
  Future<void> recreate() async {
    if (_current?.draft.expired ?? false) {
      ref.read(checkoutSetupProvider.notifier).renewIntent();
    }
    state = const AsyncData(null);
    await enter();
  }

  /// 주문서의 요청사항(라이더·품절 시)을 바꿨다 — 새 의도로 초안을 다시 만들되 **주문서는 그대로 둔다**(사용자 2026-11-20:
  /// "라이더 요청사항을 바꾸면 화면 전체가 다시 그려진다"). 받는 동안 [draftRenewingProvider] 로 주문서를 막는다.
  /// 새 초안이 오면 그 값(서버 확정)으로 바뀐다. 초안이 없거나 만료면 [recreate] 와 같다.
  Future<void> renewInPlace() async {
    if (_current == null || _current!.draft.expired) return recreate();
    final busy = ref.read(draftRenewingProvider.notifier)..set(true);
    try {
      await enter(keepVisible: true);
    } finally {
      if (ref.mounted) busy.set(false);
    }
  }

  /// 쿠폰을 고르거나(couponId) 뺐다(null) — 주문서를 그대로 둔 채 새 초안을 받는다(배송 방식 바꿀 때와 같음, order 0.18.0).
  /// 할인액·쓸 수 있는지는 새 초안 견적(서버)으로만 보인다.
  Future<void> changeCoupon(String? couponId) async {
    final setup = ref.read(checkoutSetupProvider.notifier);
    if (ref.read(checkoutSetupProvider).couponId == couponId) return;
    setup.setCoupon(couponId);
    await renewInPlace();
  }

  /// 내 연락처를 바꿨다 — 연락처는 초안을 만들 때 사본으로 고정되므로(BR-37) 새 의도로 초안을 다시 만든다.
  /// 같은 의도면 서버가 예전 초안(옛 연락처)을 돌려준다(BR-60 R3).
  Future<void> contactChanged() async {
    ref.read(checkoutSetupProvider.notifier).renewIntent();
    state = const AsyncData(null);
    await enter();
  }
}
