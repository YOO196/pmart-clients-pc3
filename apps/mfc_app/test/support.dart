import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mfc_app/router.dart';

/// 작업 목록이 없어(크루는 서버가 준 작업만 본다) 테스트는 화면 경로로 바로 들어간다.
Future<void> openRoute(WidgetTester t, String location) async {
  unawaited(
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
        .read(routerProvider)
        .push<void>(location),
  );
  await t.pumpAndSettle();
}
