import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:mfc_app/features/lot_label/lot_label.dart';
import 'package:mfc_app/l10n/gen/app_localizations.dart';
import 'package:mfc_app/shared/lot_code.dart';
import 'package:mfc_app/shared/printer/label.dart';
import 'package:mfc_app/shared/providers.dart';

void main() {
  group('찍은 LOT 라벨 읽기', () {
    test('괄호 꼴 GS1', () {
      final c = parseLotCode('(01)08801115220015(17)261105(10)L261105001')!;
      expect(c.gtin, '08801115220015');
      expect(c.expiry, '261105');
      expect(c.lotNo, 'L261105001');
      expect(c.sameProduct(['8801115220015']), isTrue);
      expect(c.sameProduct(['8809999999999']), isFalse);
    });

    test('스캐너 원문 — ]C1, 가변 길이 뒤 GS', () {
      final c = parseLotCode(
        ']C10108801115220015\u001d10L261105001\u001d17261105',
      );
      expect(c!.lotNo, 'L261105001', reason: '가변 길이 (10) 은 GS 까지');
      expect(c.expiry, '261105');
      final d = parseLotCode(']C1010880111522001517261105\u001d10L261105001')!;
      expect(d.lotNo, 'L261105001');
      expect(d.expiry, '261105');
    });

    test('예전 QR LOT:{lotId}', () {
      expect(parseLotCode('LOT:LOT-Y-1024')!.lotId, 'LOT-Y-1024');
      expect(parseLotCode('LOT:'), isNull);
    });

    test('상품 바코드·칸·장바구니는 LOT 라벨이 아니다', () {
      expect(parseLotCode('8801115220015'), isNull);
      expect(parseLotCode('2990000000024'), isNull);
      expect(parseLotCode('C-S1-01-1-01'), isNull);
      expect(parseLotCode('CRT-C-01'), isNull);
      expect(parseLotCode('(01)08801115220015'), isNull, reason: '(10) 없음');
    });
  });

  group('LOT 라벨 ZPL', () {
    test('GS1-128(D 모드) 값 그대로, 장수', () {
      final z = const LotLabel(
        lotId: 'LOT-1',
        lotNo: 'L261118001',
        sku: 'E-1',
        labelValue: 'LOT:LOT-1',
        gs1: '(01)08801115220015(17)261231(10)L261118001',
        expiryDate: '2026-12-31',
        receivedOn: '2026-11-18',
        copies: 3,
      ).zpl();
      expect(
        z,
        contains(
          r'^BCN,180,Y,N,N,D^FH\^FD(01)08801115220015(17)261231(10)L261118001^FS',
        ),
      );
      expect(z, contains('^PQ3'));
      expect(z, contains('LOT L261118001'));
      expect(z, contains('EXP 2026-12-31'));
      expect(z, isNot(contains('^BQN')));
    });

    test('상품 바코드가 없어 GS1 이 없으면 예전 QR 값', () {
      final z = const LotLabel(
        lotId: 'LOT-1',
        lotNo: 'L1',
        sku: 'E-1',
        labelValue: 'LOT:LOT-1',
      ).zpl();
      expect(z, contains(r'^BQN,2,8^FH\^FDQA,LOT:LOT-1^FS'));
      expect(z, contains('^PQ1'));
    });
  });

  group('연동(mfc-inventory 0.21.0)', () {
    test('라벨 조회: 경로·필드, 404 LOT_NOT_FOUND', () async {
      var i = 0;
      final adapter = FakeAdapter((_, _) async {
        i++;
        return i == 1
            ? const FakeReply(
                200,
                body: {
                  'labelValue': 'LOT:LOT-1',
                  'lotId': 'LOT-1',
                  'lotNo': 'L261118001',
                  'gs1': '(01)08801115220015(10)L261118001',
                  'sku': 'E-1',
                  'productName': '요거트',
                  'barcodes': ['8801115220015'],
                  'tracking': 'TRACKED',
                  'expiryDate': '2026-12-31',
                  'receivedAt': '2026-11-17T23:30:00Z',
                  'onHand': 4,
                },
              )
            : FakeReply.problem(404, problemBody('LOT_NOT_FOUND', status: 404));
      });
      final repo = ApiLotLabelRepository(
        createPmartDio(
          baseUrl: 'http://test.invalid/api/v1',
          sourceSystem: sourceSystem,
          tokens: TokenStore(MemoryKeyValueStore()),
          refresher: (_) async => null,
          adapter: adapter,
          delay: (_) async {},
        ),
      );
      final l = await repo.label('MFC-1', 'LOT-1');
      expect(
        adapter.requests.single.uri.path,
        '/api/v1/mfcs/MFC-1/lot-labels/LOT-1',
      );
      expect(l.lotNo, 'L261118001');
      expect(l.gs1, startsWith('(01)'));
      // 납입일은 서울 날짜(UTC 23:30 = 다음 날 08:30).
      expect(seoulDay(l.receivedAt!), '2026-11-18');
      await expectLater(
        repo.label('MFC-1', 'LOT-X'),
        throwsA(
          isA<ProblemFailure>().having(
            (f) => f.problem.code,
            'code',
            'LOT_NOT_FOUND',
          ),
        ),
      );
    });
  });

  testWidgets('재출력: 미리보기 모드면 라벨 값·장수를 화면에', (t) async {
    final repo = MockLotLabelRepository(latency: Duration.zero);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          lotLabelRepositoryProvider.overrideWithValue(repo),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    printLotLabels(context, ref, 'LOT-Y-1024', copies: 2),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('lot-label-preview')), findsOneWidget);
    expect(find.text('LOT 라벨 미리보기 (2장)'), findsOneWidget);
    expect(repo.requested, ['LOT-Y-1024']);
  });
}
