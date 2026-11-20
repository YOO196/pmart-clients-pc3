import 'package:flutter/material.dart';
import 'package:pmart_ui/pmart_ui.dart';
import 'package:tosspayments_widget_sdk_flutter/model/payment_info.dart';
import 'package:tosspayments_widget_sdk_flutter/model/payment_widget_options.dart';
import 'package:tosspayments_widget_sdk_flutter/model/tosspayments_result.dart';
import 'package:tosspayments_widget_sdk_flutter/payment_widget.dart';
import 'package:tosspayments_widget_sdk_flutter/widgets/agreement.dart';
import 'package:tosspayments_widget_sdk_flutter/widgets/payment_method.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/payment_repository.dart';
import '../domain/payment.dart';

/// 토스 결제위젯 결과를 앱 결과로 바꾼다. 인증 성공도 결제 완료가 아니다(서버 승인·주문 확정은 따로).
///
/// 결과의 orderId·amount 가 서버가 준 값과 다르면 승인 요청을 보내지 않는다(결제 안내 R2).
PgReturn pgReturnFromToss(Result result, PaymentEntry entry) {
  if (result.success case final s?) {
    if (s.orderId != entry.pgOrderId || s.amount != entry.amount) {
      return const PgFailed(TossPgLauncher.resultMismatch);
    }
    return PgAuthenticated(
      paymentKey: s.paymentKey,
      pgOrderId: s.orderId,
      amount: entry.amount,
    );
  }
  // 승인 대기(해외 간편결제 등): 결과는 서버 조회로만 판단한다.
  if (result.pending != null) return const PgNoReturn();
  if (result.fail case final f?) {
    return f.errorCode == tossUserCancelCode
        ? const PgCancelled()
        : PgFailed(f.errorCode);
  }
  return const PgNoReturn();
}

/// 토스 결제위젯(결제수단·약관)을 전체 화면으로 띄운다. 주문서 안의 위젯 세션이 없을 때(앱 재시작 뒤
/// 진행 중 결제 복구 등)만 쓴다. 키는 `GET /payment-widget-config` 응답([config])만 쓴다.
final class TossPgLauncher implements PgLauncher {
  const TossPgLauncher(this.navigator, this.config);

  final GlobalKey<NavigatorState> navigator;

  /// 지금 세션의 결제위젯 설정. 없으면(비회원·미조회) 결제창을 열지 않는다.
  final PaymentWidgetConfig? Function() config;

  /// 결제창 결과의 주문번호·금액이 서버 값과 다름.
  static const resultMismatch = 'PG_RESULT_MISMATCH';

  /// 결제위젯 설정이 없어 결제창을 열 수 없음.
  static const configMissing = 'PG_CONFIG_REQUIRED';

  @override
  Future<PgReturn> launch(PaymentEntry entry) async {
    final cfg = config();
    if (cfg == null) return const PgFailed(configMissing);
    final nav = navigator.currentState;
    if (nav == null) return const PgNoReturn();
    final ret = await nav.push<PgReturn>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TossPaymentPage(entry: entry, config: cfg),
      ),
    );
    // 뒤로가기 등으로 결과 없이 닫힘 = 고객이 결제창을 닫았다.
    return ret ?? const PgCancelled();
  }
}

class TossPaymentPage extends StatefulWidget {
  const TossPaymentPage({super.key, required this.entry, required this.config});

  final PaymentEntry entry;
  final PaymentWidgetConfig config;

  @override
  State<TossPaymentPage> createState() => _TossPaymentPageState();
}

class _TossPaymentPageState extends State<TossPaymentPage> {
  static const _methods = 'methods';
  static const _agreement = 'agreement';

  late final PaymentWidget _widget;
  PaymentMethodWidgetControl? _methodsControl;
  AgreementWidgetControl? _agreementControl;
  bool _requesting = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    // customerKey = 회원 accountId(결제 명세 D6, 2026-11-02). 서버 응답 값을 가공 없이 쓴다.
    _widget = PaymentWidget(
      clientKey: widget.config.clientKey,
      customerKey: widget.config.customerKey,
    );
    _render();
  }

  /// 결제수단·약관을 그린다. 키가 잘못됐거나 그리기에 실패하면 결제창을 닫고 실패로 돌려준다.
  Future<void> _render() async {
    try {
      final methods = _widget.renderPaymentMethods(
        selector: _methods,
        amount: Amount(value: widget.entry.amount),
      );
      final agreement = _widget.renderAgreement(selector: _agreement);
      _methodsControl = await methods;
      _agreementControl = await agreement;
    } on Object catch (e) {
      _close(PgFailed(e is Fail ? e.errorCode : 'PG_RENDER_FAILED'));
    }
  }

  void _close(PgReturn ret) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(ret);
  }

  Future<void> _pay() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_methodsControl == null || _agreementControl == null) return;
    setState(() => _requesting = true);
    try {
      final agreement = await _agreementControl!.getAgreementStatus();
      if (agreement.agreedRequiredTerms != true) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.tossAgreementRequired)),
        );
        return;
      }
      final result = await _widget.requestPayment(
        paymentInfo: PaymentInfo(
          orderId: widget.entry.pgOrderId,
          orderName: widget.entry.orderName,
        ),
      );
      _close(pgReturnFromToss(result, widget.entry));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: !_requesting,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tossTitle),
          leading: IconButton(
            icon: const PmartLineIcon(PmartLineIcons.close),
            onPressed: _requesting ? null : () => _close(const PgCancelled()),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    PaymentMethodWidget(
                      paymentWidget: _widget,
                      selector: _methods,
                    ),
                    AgreementWidget(
                      paymentWidget: _widget,
                      selector: _agreement,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('toss-pay'),
                    onPressed: _requesting ? null : _pay,
                    child: Text(l10n.payButton(formatKrw(widget.entry.amount))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
