import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:tosspayments_widget_sdk_flutter/model/payment_info.dart';
import 'package:tosspayments_widget_sdk_flutter/model/payment_widget_options.dart';
import 'package:tosspayments_widget_sdk_flutter/payment_widget.dart';
import 'package:tosspayments_widget_sdk_flutter/widgets/agreement.dart';
import 'package:tosspayments_widget_sdk_flutter/widgets/payment_method.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/payment_repository.dart';
import '../domain/payment.dart';
import 'toss_payment_page.dart' show pgReturnFromToss;

/// 주문서형 결제위젯 세션(BR-34 회신 §3). 주문서 화면이 결제수단·약관 위젯을 그리고,
/// "결제하기" 뒤 결제 진입이 PAY 가 되면 같은 위젯으로 결제창을 연다([launch]).
///
/// 위젯은 주문서가 살아 있는 동안만 유지한다. 결제창 자체는 SDK 가 결제수단 위젯의 context 로 띄우므로
/// 주문서 화면이 아래에 남아 있어야 한다.
abstract interface class PgWidgetSession implements PgLauncher {
  /// 결제수단·약관 위젯. [amount] 는 동의한 견적의 총액(서버 값)이다. 바뀌면 위젯 금액도 갱신한다.
  Widget build(BuildContext context, {required int amount});

  /// 위젯이 그려져 결제창을 열 수 있는 상태인지.
  ValueListenable<bool> get ready;

  /// 필수 약관에 모두 동의했는지. 결제하기 전에 확인한다.
  Future<bool> requiredTermsAgreed();

  void dispose();
}

/// 결제창 금액이 주문서 위젯에 그린 금액과 다름. 금액을 고치지 않고 결제를 멈춘다(BR-34 회신 §4).
const pgAmountMismatchCode = 'PG_AMOUNT_MISMATCH';

/// 토스 결제위젯 세션. 키는 `GET /payment-widget-config` 응답만 쓴다(앱 설정에 두지 않는다).
final class TossPgWidgetSession implements PgWidgetSession {
  TossPgWidgetSession(PaymentWidgetConfig config)
    : _widget = PaymentWidget(
        clientKey: config.clientKey,
        customerKey: config.customerKey,
      );

  static const _methods = 'order-sheet-methods';
  static const _agreement = 'order-sheet-agreement';

  final PaymentWidget _widget;
  final ValueNotifier<bool> _ready = ValueNotifier(false);
  PaymentMethodWidgetControl? _methodsControl;
  AgreementWidgetControl? _agreementControl;
  int? _renderedAmount;
  bool _rendering = false;
  bool _disposed = false;

  @override
  ValueListenable<bool> get ready => _ready;

  @override
  Widget build(BuildContext context, {required int amount}) =>
      _TossWidgets(session: this, amount: amount);

  /// 첫 그리기 중(토스 위젯은 다 그려지기 전까지 높이가 거의 0 이라 빈칸으로 보인다).
  final ValueNotifier<bool> _loading = ValueNotifier(true);

  Future<void> _render(int amount) async {
    if (_rendering || _disposed) return;
    _rendering = true;
    try {
      final methods = _widget.renderPaymentMethods(
        selector: _methods,
        amount: Amount(value: amount),
      );
      final agreement = _widget.renderAgreement(selector: _agreement);
      _methodsControl = await methods;
      _agreementControl = await agreement;
      _renderedAmount = amount;
      if (!_disposed) _ready.value = true;
    } on Object {
      // 키 오류·네트워크 등. 결제 버튼을 열지 않는다. 주문서가 "다시 시도"를 보인다.
      if (!_disposed) _ready.value = false;
    } finally {
      _rendering = false;
      if (!_disposed) _loading.value = false;
    }
  }

  Future<void> _updateAmount(int amount) async {
    final control = _methodsControl;
    if (control == null || _renderedAmount == amount) return;
    try {
      await control.updateAmount(amount: amount);
      _renderedAmount = amount;
    } on Object {
      // 갱신 실패면 금액 불일치로 결제창을 열지 않게 된다([launch]).
    }
  }

  @override
  Future<bool> requiredTermsAgreed() async {
    final control = _agreementControl;
    if (control == null) return false;
    try {
      return (await control.getAgreementStatus()).agreedRequiredTerms;
    } on Object {
      return false;
    }
  }

  @override
  Future<PgReturn> launch(PaymentEntry entry) async {
    if (!_ready.value) return const PgFailed('PG_RENDER_FAILED');
    // 서버는 payment.amount = 동의한 견적 총액이라고 보장한다. 다르면 금액을 고치지 않고 멈춘다.
    if (_renderedAmount != entry.amount) {
      return const PgFailed(pgAmountMismatchCode);
    }
    try {
      final result = await _widget.requestPayment(
        paymentInfo: PaymentInfo(
          orderId: entry.pgOrderId,
          orderName: entry.orderName,
        ),
      );
      return pgReturnFromToss(result, entry);
    } on Object {
      // SDK 가 결제창을 못 열었다(위젯 없음 등). 결과를 받지 못한 것이지 실패 확정이 아니다.
      return const PgNoReturn();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ready.dispose();
    _loading.dispose();
  }
}

class _TossWidgets extends StatefulWidget {
  const _TossWidgets({required this.session, required this.amount});

  final TossPgWidgetSession session;
  final int amount;

  @override
  State<_TossWidgets> createState() => _TossWidgetsState();
}

class _TossWidgetsState extends State<_TossWidgets> {
  @override
  void initState() {
    super.initState();
    widget.session._render(widget.amount);
  }

  @override
  void didUpdateWidget(covariant _TossWidgets old) {
    super.didUpdateWidget(old);
    if (old.amount != widget.amount) widget.session._updateAmount(widget.amount);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ValueListenableBuilder<bool>(
        valueListenable: widget.session._loading,
        builder: (context, loading, _) => loading
            ? Row(
                key: const ValueKey('pg-widget-loading'),
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).payMethodsLoading),
                ],
              )
            : const SizedBox.shrink(),
      ),
      PaymentMethodWidget(
        paymentWidget: widget.session._widget,
        selector: TossPgWidgetSession._methods,
      ),
      AgreementWidget(
        paymentWidget: widget.session._widget,
        selector: TossPgWidgetSession._agreement,
      ),
    ],
  );
}

/// 목 세션. 위젯 자리에 안내 문구만 두고, 결제창은 [fallback](목 결제창)에 맡긴다.
final class MockPgWidgetSession implements PgWidgetSession {
  MockPgWidgetSession(this.fallback);

  final PgLauncher fallback;
  final ValueNotifier<bool> _ready = ValueNotifier(true);

  @override
  ValueListenable<bool> get ready => _ready;

  @override
  Widget build(BuildContext context, {required int amount}) => Text(
    AppLocalizations.of(context).payMethodsMock,
    key: const ValueKey('pg-widget-mock'),
  );

  @override
  Future<bool> requiredTermsAgreed() async => true;

  @override
  Future<PgReturn> launch(PaymentEntry entry) => fallback.launch(entry);

  @override
  void dispose() => _ready.dispose();
}
