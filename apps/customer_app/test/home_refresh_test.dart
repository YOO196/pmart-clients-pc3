import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart';
import 'package:customer_app/features/catalog/presentation/home_screen.dart';

import 'support/app_harness.dart';

/// 홈 조회를 세고, [gate] 가 있으면 테스트가 정한 때에 응답한다.
final class _CountingHome extends MockCatalogRepository {
  _CountingHome() : super(latency: Duration.zero);

  int calls = 0;
  Completer<void>? gate;

  @override
  Future<HomeView> home({String? mfcId, HomeTab? tab}) async {
    if (tab == null) {
      calls++;
      final g = gate;
      if (g != null) await g.future;
    }
    return super.home(mfcId: mfcId, tab: tab);
  }
}

void main() {
  late DateTime now;
  late _CountingHome catalog;

  setUp(() {
    now = DateTime(2026, 11, 6, 12);
    catalog = _CountingHome();
  });

  Future<void> start(WidgetTester t) async {
    await t.pumpWidget(
      testApp([
        homeClockProvider.overrideWithValue(() => now),
      ], catalog: catalog),
    );
    await t.pumpAndSettle();
    expect(catalog.calls, 1);
  }

  Future<void> leaveAndReturn(WidgetTester t) async {
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.text('홈').last);
    await t.pump();
    await t.pump();
  }

  testWidgets('1분 안에 홈으로 돌아오면 다시 읽지 않는다', (t) async {
    await start(t);
    now = now.add(const Duration(seconds: 59));
    await leaveAndReturn(t);
    await t.pumpAndSettle();
    expect(catalog.calls, 1);
  });

  testWidgets('1분이 지나 홈으로 돌아오면 다시 읽는다', (t) async {
    await start(t);
    now = now.add(const Duration(minutes: 1));
    await leaveAndReturn(t);
    await t.pumpAndSettle();
    expect(catalog.calls, 2);

    // 방금 다시 읽었으니 곧바로 다시 돌아와도 읽지 않는다
    await leaveAndReturn(t);
    await t.pumpAndSettle();
    expect(catalog.calls, 2);
  });

  testWidgets('다시 읽는 동안 지금 홈을 그대로 둔다(자리 표시로 바뀌지 않음)', (t) async {
    await start(t);
    catalog.gate = Completer<void>();
    now = now.add(const Duration(minutes: 2));
    await leaveAndReturn(t);
    expect(catalog.calls, 2);
    expect(find.byType(HomeSkeleton), findsNothing);

    catalog.gate!.complete();
    await t.pumpAndSettle();
    expect(find.byType(HomeSkeleton), findsNothing);
  });

  testWidgets('상품 상세에서 뒤로 와도 1분이 지났으면 다시 읽는다', (t) async {
    await start(t);
    final tile = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('tile-'),
    );
    // 상품 진열은 배송 카드·배너·검색창·카테고리 아래에 있다.
    await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await t.pumpAndSettle();
    await t.ensureVisible(tile.first);
    await t.pumpAndSettle();
    await t.tap(tile.first);
    await t.pumpAndSettle();
    expect(find.byType(HomeScreen).hitTestable(), findsNothing);
    now = now.add(const Duration(minutes: 1));
    await t.binding.handlePopRoute(); // 시스템 뒤로
    await t.pumpAndSettle();
    expect(catalog.calls, 2);
  });
}
