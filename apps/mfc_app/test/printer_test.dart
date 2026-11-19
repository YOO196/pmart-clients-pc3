import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/packing/data/mock_packing_repository.dart';
import 'package:mfc_app/features/packing/presentation/packing_controller.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/shared/printer/label.dart';
import 'package:mfc_app/shared/printer/label_printer.dart';
import 'package:mfc_app/shared/providers.dart';

import 'support.dart';

void main() {
  setUpAll(initPmartFormatting);

  const label = PackageLabel(
    packageId: 'pkg-1',
    packageVersion: 2,
    qrCode: 'PKG:pkg-1:2',
    orderId: 'order-1',
    deliveryId: 'dlv-1',
    temperatureZone: 'CHILLED',
    bagCount: 1,
  );

  group('ZPL', () {
    test('인계 숫자 6자리가 있으면 가장 크게, 포장 ID 는 작게', () {
      final z = packageLabelZpl(
        const PackageLabel(
          packageId: 'pkg-9',
          packageVersion: 1,
          qrCode: 'PKG:pkg-9:1',
          handoverCode: '482913',
        ),
      );
      expect(z, contains(r'^FO380,28^A0N,70,70^FH\^FD482913^FS'));
      expect(z, contains(r'^A0N,22,22^FH\^FDpkg-9^FS'));
    });

    test('QR 은 서버 qrCode 원문, 포장·주문·배송·온도대·봉투', () {
      final z = packageLabelZpl(label);
      expect(z, startsWith('^XA'));
      expect(z.trim(), endsWith('^XZ'));
      expect(z, contains('^BQN,2,9^FH\\^FDQA,PKG:pkg-1:2^FS'));
      expect(z, contains('^FDpkg-1^FS'));
      expect(z, contains('^FDv2^FS'));
      expect(z, contains('^FDORDER order-1^FS'));
      expect(z, contains('^FDDLV dlv-1^FS'));
      expect(z, contains('^FDCHILLED^FS'));
      expect(z, contains('^FDBAGS 1^FS'));
    });

    test('^·~·\\ 와 ASCII 밖 문자는 16진수로 바꿔 명령으로 해석되지 않게 한다', () {
      final z = packageLabelZpl(
        const PackageLabel(
          packageId: 'a^b~c\\d',
          packageVersion: 1,
          qrCode: 'Q^1',
        ),
      );
      expect(z, contains('^FDa\\5Eb\\7Ec\\5Cd^FS'));
      expect(z, contains('^FDQA,Q\\5E1^FS'));
      final k = packageLabelZpl(
        const PackageLabel(packageId: '가', packageVersion: 1, qrCode: 'Q'),
      );
      expect(k, contains('^FD\\EA\\B0\\80^FS'));
    });
  });

  group('출력', () {
    late MemoryKeyValueStore store;
    late List<(String, int, String)> sent;
    Object? sendError;
    late ProviderContainer c;

    setUp(() {
      store = MemoryKeyValueStore();
      sent = [];
      sendError = null;
      c = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          rawPrintSenderProvider.overrideWithValue((host, port, bytes) async {
            if (sendError != null) throw sendError!;
            sent.add((host, port, utf8.decode(bytes)));
          }),
        ],
      );
      addTearDown(c.dispose);
    });

    Future<PrintOutcome> print() =>
        c.read(labelPrintServiceProvider).print(label);

    test('기본은 미리보기 — 프린터로 보내지 않는다', () async {
      expect(await print(), isA<PrintPreview>());
      expect(sent, isEmpty);
    });

    test('네트워크 모드: 주소가 없으면 미설정, 있으면 ZPL 을 보낸다', () async {
      final ctl = c.read(printerSettingsProvider.notifier);
      await c.read(printerSettingsProvider.future);
      await ctl.save(const PrinterSettings(mode: PrinterMode.networkZpl));
      expect(
        await print(),
        isA<PrintFailed>().having(
          (f) => f.reason,
          'reason',
          PrintFailure.notConfigured,
        ),
      );

      await ctl.save(
        const PrinterSettings(
          mode: PrinterMode.networkZpl,
          host: ' 192.168.0.50 ',
        ),
      );
      expect(await print(), isA<PrintSent>());
      expect(sent.single.$1, '192.168.0.50');
      expect(sent.single.$2, 9100);
      expect(sent.single.$3, contains('PKG:pkg-1:2'));
    });

    test('연결 실패는 연결 불가로 알린다', () async {
      await c.read(printerSettingsProvider.future);
      await c
          .read(printerSettingsProvider.notifier)
          .save(
            const PrinterSettings(
              mode: PrinterMode.networkZpl,
              host: '10.0.0.9',
              port: 6101,
            ),
          );
      sendError = const SocketException('refused');
      expect(
        await print(),
        isA<PrintFailed>().having(
          (f) => f.reason,
          'reason',
          PrintFailure.unreachable,
        ),
      );
    });

    test('설정은 기기에 남는다(앱을 다시 켜도)', () async {
      await c.read(printerSettingsProvider.future);
      await c
          .read(printerSettingsProvider.notifier)
          .save(
            const PrinterSettings(
              mode: PrinterMode.networkZpl,
              host: '10.0.0.9',
              port: 6101,
            ),
          );
      final c2 = ProviderContainer(
        overrides: [secureStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c2.dispose);
      final s = await c2.read(printerSettingsProvider.future);
      expect(s.mode, PrinterMode.networkZpl);
      expect(s.host, '10.0.0.9');
      expect(s.port, 6101);
    });

    test('저장값이 깨졌으면 기본(미리보기)', () async {
      await store.write('mfc.printer.v1', '{not json');
      final s = await c.read(printerSettingsProvider.future);
      expect(s.mode, PrinterMode.preview);
    });
  });

  List<Override> appOverrides() => [
    envProvider.overrideWithValue(PmartEnv.mock),
    taskRepositoryProvider.overrideWithValue(
      MockTaskRepository(latency: Duration.zero, packDemo: true),
    ),
    packingRepositoryProvider.overrideWithValue(
      MockPackingRepository(latency: Duration.zero),
    ),
    secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
  ];

  testWidgets('패킹: 밀봉한 포장의 라벨 출력 → 미리보기에 서버 QR 원문', (t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: appOverrides(),
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    await openRoute(t, '/tasks/task-mock-2');
    // 패킹대 → 장바구니 → 배차 요청 → 담기.
    for (final (id, code) in [
      ('station-scan', 'PAK-C-01'),
      ('pack-cart-scan', 'CRT-C-01'),
    ]) {
      await t.enterText(find.byKey(ValueKey(id)), code);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const ValueKey('pack-min-5')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('request-dispatch')));
    await t.pumpAndSettle();

    await t.enterText(
      find.byKey(const ValueKey('pack-scan')),
      MockTaskRepository.yogurtBarcode,
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.tap(find.byKey(const ValueKey('seal')));
    await t.pumpAndSettle();
    // 밀봉하면 바로 출력 — 프린터가 없으면 미리보기.
    expect(find.byKey(const ValueKey('label-preview')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('label-ok')));
    await t.pumpAndSettle();

    // 다시 출력 = 같은 포장 ID·같은 QR.
    await t.tap(find.byKey(const ValueKey('print-pkg-1')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('label-preview')), findsOneWidget);
    expect(
      t
          .widget<SelectableText>(find.byKey(const ValueKey('label-qr-text')))
          .data,
      'PKG:pkg-1:1',
    );
  });

  testWidgets('프린터 설정: 네트워크인데 주소가 없으면 저장하지 않는다', (t) async {
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: appOverrides(),
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('menu-printer')));
    await t.pumpAndSettle();
    await t.tap(find.text('네트워크 프린터'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('printer-save')));
    await t.pump();
    expect(find.text('IP 주소와 포트(1~65535)를 확인해 주세요'), findsOneWidget);

    await t.enterText(
      find.byKey(const ValueKey('printer-host')),
      '192.168.0.50',
    );
    await t.tap(find.byKey(const ValueKey('printer-save')));
    await t.pumpAndSettle();
    expect(find.text('저장했어요'), findsOneWidget);
  });
}
