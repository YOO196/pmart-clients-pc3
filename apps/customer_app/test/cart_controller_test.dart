import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/cart/presentation/cart_controller.dart';
import 'package:customer_app/shared/providers.dart';

/// 원결과 조회 횟수를 센다.
base class _CountingCart extends MockCartRepository {
  _CountingCart() : super(latency: Duration.zero);

  int lookups = 0;
  final keys = <String>[];

  @override
  Future<CartChangeOutcome> change(
    String cartId,
    CartChange change, {
    required IdempotencyKey key,
    required int expectedVersion,
  }) {
    keys.add(key.value);
    return super.change(
      cartId,
      change,
      key: key,
      expectedVersion: expectedVersion,
    );
  }

  @override
  Future<CartChangeOutcome> lookup(String cartId, IdempotencyKey key) {
    lookups++;
    keys.add(key.value);
    return super.lookup(cartId, key);
  }
}

void main() {
  late _CountingCart repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _CountingCart();
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        envProvider.overrideWithValue(PmartEnv.mock),
        cartRepositoryProvider.overrideWithValue(repo),
        cartResolvePolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 3,
        )),
      ],
    );
    addTearDown(container.dispose);
    await container.read(cartControllerProvider.future);
  });

  CartController controller() =>
      container.read(cartControllerProvider.notifier);
  CartState state() => container.read(cartControllerProvider).requireValue;
  CartLine line(String sku) => state().cart.lineForSku(sku)!;

  test('같은 SKU 담기는 합산이 아니라 절대 수량 설정이다', () async {
    expect(line('E-00000001').quantity, 2);

    final outcome = await controller().submit(
      const AddItem(sku: 'E-00000001', quantity: 5),
    );

    expect(outcome, isA<CartChangeApplied>());
    expect(line('E-00000001').quantity, 5);
    expect(
      state().cart.lines.where((l) => l.sku == 'E-00000001'),
      hasLength(1),
    );
  });

  test('선택 변경은 응답으로 바로 반영되고, 합계는 뒤에서 서버 값으로 다시 받는다', () async {
    final versionBefore = state().cart.version;
    await controller().submit(
      SetSelected(cartItemId: line('E-00000005').cartItemId, selected: false),
    );
    // 서버가 APPLIED 로 확정한 선택·버전은 바로 반영. 합계는 앱이 계산하지 않고 비워 둔다(확인 중).
    expect(line('E-00000005').selected, isFalse);
    expect(state().cart.version, versionBefore + 1);
    expect(state().amountStale, isTrue);
    expect(state().cart.selectedItemAmount, isNull);
    expect(state().canChange, isTrue);

    for (var i = 0; i < 20 && state().amountStale; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    // 서울우유 2,980 × 2 만 남는다(목 서버 계산).
    expect(state().amountStale, isFalse);
    expect(state().cart.selectedItemAmount, 5960);
  });

  test('응답을 잃은 변경은 같은 키 원결과 조회로 반영 확인하고 두 번 적용하지 않는다', () async {
    final versionBefore = repo.version;
    repo.loseNextResponse = true;

    final outcome = await controller().submit(
      const AddItem(sku: 'E-00000002', quantity: 1),
    );

    expect(outcome, isA<CartChangeApplied>());
    expect(repo.version, versionBefore + 1);
    expect(repo.lookups, 1);
    expect(repo.keys.toSet(), hasLength(1), reason: '변경·조회가 같은 키');
    expect(state().sync, CartSync.stable);
    expect(line('E-00000002').quantity, 1);
  });

  test('원결과 조회가 계속 실패하면 확인 중을 유지하고 다른 변경을 막는다', () async {
    repo
      ..loseNextResponse = true
      ..lookupFailures = 10;

    final outcome = await controller().submit(
      const AddItem(sku: 'E-00000002', quantity: 1),
    );

    expect(outcome, isA<CartChangeUnknown>());
    expect(state().sync, CartSync.unknown);
    expect(state().canChange, isFalse);
    // 확정 전에는 화면에 반영하지 않는다.
    expect(state().cart.lineForSku('E-00000002'), isNull);
    // 새 변경은 받지 않는다.
    expect(
      await controller().submit(const AddItem(sku: 'E-00000003', quantity: 1)),
      isNull,
    );

    repo.lookupFailures = 0;
    final checked = await controller().checkAgain();

    expect(checked, isA<CartChangeApplied>());
    expect(state().sync, CartSync.stable);
    expect(line('E-00000002').quantity, 1);
  });

  test('서버에 닿지 않은 변경은 조회 결과 미적용으로 확정된다', () async {
    repo.dropNextRequest = true;

    final outcome = await controller().submit(
      const AddItem(sku: 'E-00000002', quantity: 1),
    );

    expect(outcome, isA<CartChangeNotApplied>());
    expect(state().notice, isA<NoticeNotApplied>());
    expect(state().canChange, isTrue);
    expect(state().cart.lineForSku('E-00000002'), isNull);
  });

  test('버전 충돌이면 최신 장바구니를 다시 받고 안내한다(자동 재적용 없음)', () async {
    repo.bumpVersionElsewhere();

    final outcome = await controller().submit(
      SetQuantity(cartItemId: line('E-00000001').cartItemId, quantity: 3),
    );

    expect(outcome, isA<CartVersionConflict>());
    expect(state().notice, isA<NoticeReloadedAfterConflict>());
    expect(state().cart.version, repo.version);
    expect(line('E-00000001').quantity, 2);
  });

  test('구매 상한 초과는 서버가 준 상한·권장 수량과 함께 거절된다', () async {
    final outcome = await controller().submit(
      SetQuantity(cartItemId: line('E-00000001').cartItemId, quantity: 11),
    );

    expect(outcome, isA<CartChangeRejected>());
    final r = outcome! as CartChangeRejected;
    expect(r.code, CartProblemCode.quantityLimitExceeded);
    expect(r.limit?.limitUnits, 10);
    expect(r.limit?.suggestedQuantity, 10);
    expect(line('E-00000001').quantity, 2);
  });

  test('낱개와 묶음은 같은 기초상품으로 합산해 상한을 본다', () async {
    // 낱개 2개가 있는 상태에서 2입 묶음 5개 = 10개 → 합계 12개.
    final outcome = await controller().submit(
      const AddItem(sku: 'B-00000011', quantity: 5),
    );
    expect(
      (outcome! as CartChangeRejected).code,
      CartProblemCode.quantityLimitExceeded,
    );
  });

  test('가용 부족은 서버가 확인한 가용 수량으로 안내한다', () async {
    final outcome = await controller().submit(
      const AddItem(sku: 'E-00000003', quantity: 5),
    );
    final r = outcome! as CartChangeRejected;
    expect(r.code, CartProblemCode.insufficientAvailableQuantity);
    expect(r.availableQty, MockCartRepository.lowStockQty);
  });
}
