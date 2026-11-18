import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_api_mfc_inventory/pmart_api_mfc_inventory.dart' as inv;
import 'package:pmart_core/pmart_core.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/printer/label.dart';
import '../../shared/printer/printer_ui.dart';
import '../../shared/providers.dart';
import '../tasks/presentation/task_controllers.dart' show currentMfcIdProvider;

/// LOT 라벨 인쇄 정보(mfc-inventory 0.20.0·0.21.0 `LotLabel`). 라벨 값은 서버 것 그대로 — 화면이 만들지 않는다.
@immutable
class LotLabelInfo {
  const LotLabelInfo({
    required this.lotId,
    required this.lotNo,
    required this.sku,
    required this.labelValue,
    this.gs1,
    this.productName,
    this.expiryDate,
    this.receivedAt,
  });

  final String lotId;
  final String lotNo;
  final String sku;

  /// 예전 QR 값 `LOT:{lotId}` — 상품 바코드가 없어 GS1 을 못 만들 때 QR 로 쓴다.
  final String labelValue;

  /// GS1-128 괄호 꼴(상품 바코드가 없으면 null).
  final String? gs1;
  final String? productName;
  final String? expiryDate;
  final DateTime? receivedAt;
}

abstract interface class LotLabelRepository {
  /// `GET /mfcs/{mfcId}/lot-labels/{lotId}` — 없는 LOT 은 404 LOT_NOT_FOUND.
  Future<LotLabelInfo> label(String mfcId, String lotId);
}

final class ApiLotLabelRepository implements LotLabelRepository {
  ApiLotLabelRepository(Dio dio)
    : _api = inv.PmartApiMfcInventory(dio: dio).getLotLabelsApi();

  final inv.LotLabelsApi _api;

  @override
  Future<LotLabelInfo> label(String mfcId, String lotId) async {
    final res = await pmartGuard(
      () => _api.getLotLabel(mfcId: mfcId, lotId: lotId),
    );
    final l = res.data ?? (throw const ContractViolationFailure('라벨 본문 없음'));
    return LotLabelInfo(
      lotId: l.lotId,
      lotNo: l.lotNo,
      sku: l.sku,
      labelValue: l.labelValue,
      gs1: l.gs1,
      productName: l.productName,
      expiryDate: l.expiryDate,
      receivedAt: l.receivedAt,
    );
  }
}

/// 목: 상품 바코드가 있는 LOT 은 GS1, `LOT-NOBC-…` 는 바코드가 없어 QR.
final class MockLotLabelRepository implements LotLabelRepository {
  MockLotLabelRepository({this.latency = const Duration(milliseconds: 200)});

  final Duration latency;
  final requested = <String>[];

  @override
  Future<LotLabelInfo> label(String mfcId, String lotId) async {
    await Future<void>.delayed(latency);
    requested.add(lotId);
    final no =
        'L261118${(lotId.hashCode.abs() % 1000).toString().padLeft(3, '0')}';
    return LotLabelInfo(
      lotId: lotId,
      lotNo: no,
      sku: 'SKU-MOCK',
      labelValue: 'LOT:$lotId',
      gs1: lotId.startsWith('LOT-NOBC')
          ? null
          : '(01)08801234567890(17)261231(10)$no',
      expiryDate: '2026-12-31',
    );
  }
}

final lotLabelRepositoryProvider = Provider<LotLabelRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockLotLabelRepository(),
    PmartEnv.local => ApiLotLabelRepository(ref.watch(dioProvider)),
  },
);

/// LOT 라벨 [copies] 장을 뽑는다(인쇄 정보는 서버 조회 — 실패하면 출력하지 않고 알린다). 재출력도 같은 값이다.
Future<void> printLotLabels(
  BuildContext context,
  WidgetRef ref,
  String lotId, {
  int copies = 1,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final LotLabelInfo info;
  try {
    info = await ref
        .read(lotLabelRepositoryProvider)
        .label(ref.read(currentMfcIdProvider), lotId);
  } on PmartFailure catch (f) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          f is ProblemFailure && f.problem.code == 'LOT_NOT_FOUND'
              ? l10n.lotLabelNotFound
              : l10n.lotLabelLoadError,
        ),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await printLabel(
    context,
    ref,
    LotLabel(
      lotId: info.lotId,
      lotNo: info.lotNo,
      sku: info.sku,
      labelValue: info.labelValue,
      gs1: info.gs1,
      productName: info.productName,
      expiryDate: info.expiryDate,
      receivedOn: info.receivedAt == null ? null : seoulDay(info.receivedAt!),
      copies: copies,
    ),
    sentText: l10n.lotLabelSent(copies),
  );
}

/// 서울 날짜 `YYYY-MM-DD`(라벨 글꼴에 한글이 없어 숫자만).
String seoulDay(DateTime instant) {
  final d = instant.toUtc().add(const Duration(hours: 9));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
