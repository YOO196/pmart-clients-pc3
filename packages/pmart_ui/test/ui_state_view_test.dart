import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: PmartTheme.light(),
  locale: const Locale('ko'),
  supportedLocales: PmartUiLocalizations.supportedLocales,
  localizationsDelegates: const [
    PmartUiLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  Future<void> pump(
    WidgetTester t,
    UiState<List<String>> state, {
    VoidCallback? onRetry,
    VoidCallback? onCheckAgain,
  }) => t.pumpWidget(
    _host(
      UiStateView<List<String>>(
        state: state,
        onRetry: onRetry,
        onCheckAgain: onCheckAgain,
        ready: (_, items) => ListView(
          key: const ValueKey('ready-body'),
          children: [for (final i in items) Text(i)],
        ),
      ),
    ),
  );

  testWidgets('7가지 상태가 서로 다른 화면으로 그려진다', (t) async {
    final cases = <UiState<List<String>>, Key>{
      const UiLoading(): const ValueKey('ui-loading'),
      const UiReady(['사과']): const ValueKey('ready-body'),
      const UiEmpty(): const ValueKey('ui-empty'),
      const UiPartial(['사과'], missing: {'banner'}): const ValueKey(
        'ui-partial',
      ),
      const UiError(NetworkFailure(DioExceptionType.connectionError)):
          const ValueKey('ui-error'),
      const UiForbidden(): const ValueKey('ui-forbidden'),
      const UiResultUnknown(): const ValueKey('ui-result-unknown'),
    };
    for (final MapEntry(key: state, value: key) in cases.entries) {
      await pump(t, state);
      expect(find.byKey(key), findsOneWidget, reason: '$state');
    }
  });

  testWidgets('조회 실패는 빈 목록 화면이 아니라 오류 화면이다', (t) async {
    var retried = 0;
    await pump(
      t,
      const UiError(
        NetworkFailure(DioExceptionType.receiveTimeout, requestId: 'rid-7'),
      ),
      onRetry: () => retried++,
    );

    expect(find.byKey(const ValueKey('ui-empty')), findsNothing);
    expect(find.text('정보를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('문의 번호 rid-7'), findsOneWidget);
    await t.tap(find.text('다시 시도'));
    expect(retried, 1);
  });

  testWidgets('결과 불명은 실패로 그리지 않고 "다시 확인"만 둔다', (t) async {
    var checked = 0;
    await pump(
      t,
      const UiResultUnknown(requestId: 'k-1'),
      onCheckAgain: () => checked++,
    );

    expect(find.text('처리 결과를 확인하고 있어요'), findsOneWidget);
    expect(find.text('정보를 불러오지 못했어요'), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
    await t.tap(find.text('다시 확인'));
    expect(checked, 1);
  });

  testWidgets('부분 조회는 받은 내용을 보여 주면서 안내 띠를 붙인다', (t) async {
    await pump(t, const UiPartial(['사과', '배'], missing: {'eta'}));

    expect(find.text('일부 정보를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('사과'), findsOneWidget);
    expect(find.text('배'), findsOneWidget);
  });

  test('실패 → 화면 상태 변환', () {
    expect(
      UiState<int>.fromFailure(const UnknownResultFailure(requestId: 'k')),
      isA<UiResultUnknown<int>>(),
    );
    expect(
      UiState<int>.fromFailure(
        const ProblemFailure(Problem(status: 403, code: ProblemCode.forbidden)),
      ),
      isA<UiForbidden<int>>(),
    );
    expect(
      UiState<int>.fromFailure(
        const ProblemFailure(
          Problem(status: 409, code: ProblemCode.versionConflict),
        ),
      ),
      isA<UiError<int>>(),
    );
  });

  testWidgets('명령 버튼은 실행 중 다시 눌리지 않는다', (t) async {
    var calls = 0;
    final gate = Completer<void>();
    await t.pumpWidget(
      _host(
        CommandButton(
          label: '주문하기',
          onPressed: () {
            calls++;
            return gate.future;
          },
        ),
      ),
    );

    await t.tap(find.text('주문하기'));
    await t.pump();
    await t.tap(find.byType(FilledButton));
    await t.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await t.pumpAndSettle();
    expect(find.text('주문하기'), findsOneWidget);
    await t.tap(find.text('주문하기'));
    expect(calls, 2);
  });

  testWidgets('onPressed 가 null 이면 비활성이다', (t) async {
    await t.pumpWidget(
      _host(const CommandButton(label: '결제하기', onPressed: null)),
    );
    final button = t.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
