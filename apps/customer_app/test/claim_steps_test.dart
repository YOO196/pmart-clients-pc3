// 취소·반품 상세 단계 막대 — 초안 08 상세 표(상태값 → 단계, 사용자 2026-11-23 "취소 반품부터해줘").
import 'package:customer_app/features/claims/domain/claims.dart';
import 'package:customer_app/features/claims/presentation/claims_screens.dart'
    show claimSteps;
import 'package:customer_app/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('ko'));
  });

  ClaimView claim(ClaimType type, ClaimState state, {bool fee = false}) =>
      ClaimView(
        claimId: 'c',
        version: 1,
        orderId: 'o',
        type: type,
        state: state,
        lines: const [],
        refunds: const [],
        feePayment: fee
            ? const ReturnFeeView(state: ReturnFeeState.waiting, amount: 9000)
            : null,
      );

  test('취소: 접수 → 확인 → 환불 진행 → 완료', () {
    int? at(ClaimState s) =>
        claimSteps(l10n, claim(ClaimType.cancel, s))?.current;
    expect(
      claimSteps(l10n, claim(ClaimType.cancel, ClaimState.opened))!.steps,
      ['접수', '확인', '환불 진행', '완료'],
    );
    expect(at(ClaimState.opened), 0);
    expect(at(ClaimState.stopPending), 1);
    expect(at(ClaimState.decided), 1);
    expect(at(ClaimState.inProgress), 2);
    expect(at(ClaimState.closed), 3);
    expect(at(ClaimState.withdrawn), isNull);
    expect(at(ClaimState.rejected), isNull);
    expect(at(ClaimState.unknown), isNull);
  });

  test('반품(고객 사유 — 회수비): 접수 → 회수비 결제 → 회수·검수 → 환불', () {
    final s = claimSteps(
      l10n,
      claim(ClaimType.returnItems, ClaimState.feePending, fee: true),
    )!;
    expect(s.steps, ['접수', '회수비 결제', '회수·검수', '환불']);
    expect(s.current, 1);
    expect(
      claimSteps(
        l10n,
        claim(ClaimType.returnItems, ClaimState.cancelled, fee: true),
      ),
      isNull,
    );
    expect(
      claimSteps(
        l10n,
        claim(ClaimType.returnItems, ClaimState.recoveryFailed, fee: true),
      ),
      isNull,
    );
  });

  test('반품(회사 잘못 — 회수비 없음): 접수 → 확인 → 회수·검수 → 환불, 교환은 막대 없음', () {
    final s = claimSteps(
      l10n,
      claim(ClaimType.returnItems, ClaimState.inProgress),
    )!;
    expect(s.steps, ['접수', '확인', '회수·검수', '환불']);
    expect(s.current, 2);
    expect(
      claimSteps(l10n, claim(ClaimType.exchange, ClaimState.opened)),
      isNull,
    );
  });
}
