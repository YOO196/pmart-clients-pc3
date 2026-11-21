import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart' show ProblemCode;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/sms_composer.dart';
import '../../address/presentation/phone_number_formatter.dart';
import '../../profile/domain/profile.dart' show PhoneInput;
import '../domain/auth.dart';
import 'auth_controller.dart';
import 'signup_steps.dart';

/// 로그인 중 휴대폰 확인(AUTH_IDENTITY — auth 0.6.0, BR-64 회신 2026-11-20).
/// 번호 입력 → "{받는 번호}로 {숫자}를 문자로 보내 주세요" → "보냈어요"(누를 때만 서버에 묻는다 — OCTOMO 월 한도) → 회원.
/// 이미 가입된 번호(R3)는 그 제공자로 로그인 안내, 탈퇴 번호(R4)는 가입 가능한 날짜 안내.
/// 모양은 내 정보의 휴대폰 확인 화면(레퍼런스 13)과 같다.
class IdentityView extends ConsumerStatefulWidget {
  const IdentityView({
    super.key,
    required this.waiting,
    required this.purpose,
    required this.providerLabel,
    required this.onClose,
  });

  final LoginNeedsIdentity waiting;
  final LoginPurpose purpose;
  final String Function(SocialProvider) providerLabel;
  final VoidCallback onClose;

  @override
  ConsumerState<IdentityView> createState() => _IdentityViewState();
}

class _IdentityViewState extends ConsumerState<IdentityView> {
  final _phone = TextEditingController();
  String? _info;

  /// [문자 앱 열기]로 문자 앱에 다녀오는 중. 앱으로 돌아오면(resumed) [보냈어요]를 한 번 대신 누른다
  /// (사용자 2026-11-21 — 문자를 보냈는지 앱은 알 수 없어 자동으로 돌아오게는 못 함). 확인 조회는 OCTOMO 월 한도를
  /// 쓰므로 문자 앱을 연 번마다 한 번만 묻는다.
  bool _awaySms = false;
  late final AppLifecycleListener _life = AppLifecycleListener(
    onResume: _checkAfterSms,
  );

  static final _mobile010 = RegExp(r'^010\d{8}$');

  @override
  void initState() {
    super.initState();
    _life; // 생성(구독)
  }

  @override
  void dispose() {
    _life.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _checkAfterSms() {
    if (!_awaySms || !mounted) return;
    _awaySms = false;
    final w = widget.waiting;
    if (w.start == null) return;
    if (ref.read(loginFlowProvider(widget.purpose)) is LoginWorking) return;
    _ctl.confirmIdentity(w);
  }

  LoginFlowController get _ctl =>
      ref.read(loginFlowProvider(widget.purpose).notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final w = widget.waiting;
    final busy = ref.watch(loginFlowProvider(widget.purpose)) is LoginWorking;
    final digits = PhoneInput.normalize(_phone.text);

    final String title;
    final List<Widget> body;
    final Widget button;
    if (w.conflict case final c?) {
      final joined = c.joinedAt == null
          ? null
          : DateFormat('y.M.d', 'ko').format(toSeoulWallClock(c.joinedAt!));
      title = c.alreadyRegistered ? l10n.idAlreadyTitle : l10n.idRejoinTitle;
      body = [
        Text(
          c.alreadyRegistered
              ? l10n.idAlreadyBody(
                  c.provider == null ? '' : widget.providerLabel(c.provider!),
                )
              : l10n.idRejoinBody(
                  c.rejoinAvailableAt == null
                      ? '-'
                      : DateFormat(
                          'y년 M월 d일',
                          'ko',
                        ).format(toSeoulWallClock(c.rejoinAvailableAt!)),
                ),
          key: const ValueKey('id-conflict-body'),
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
        ),
        if (c.alreadyRegistered && (joined != null || c.emailMasked != null))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [?joined, ?c.emailMasked].join(' · '),
              key: const ValueKey('id-conflict-account'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ];
      button = c.alreadyRegistered && c.provider != null
          ? CommandButton(
              key: const ValueKey('id-login-with'),
              label: l10n.idLoginWith(widget.providerLabel(c.provider!)),
              onPressed: busy ? null : () => _ctl.start(c.provider!),
            )
          : CommandButton(
              key: const ValueKey('id-close'),
              label: l10n.actionConfirm,
              onPressed: () async => widget.onClose(),
            );
    } else if (w.start case final s?) {
      title = l10n.pvSendTitle;
      final pending = w.status == 'PENDING';
      body = [
        _Box(label: l10n.pvSendTo, value: s.sendTo, valueKey: 'id-send-to'),
        const SizedBox(height: 12),
        _Box(label: l10n.pvSendText, value: s.text, valueKey: 'id-send-text'),
        const SizedBox(height: 12),
        Text(
          l10n.pvSendGuide,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('id-open-sms'),
                onPressed: () async {
                  _awaySms = true;
                  final ok = await ref.read(smsComposerProvider)(
                    s.sendTo,
                    s.text,
                  );
                  if (!ok) _awaySms = false;
                  if (!ok && mounted) {
                    setState(() => _info = l10n.pvNoSmsApp);
                  }
                },
                child: Text(l10n.pvOpenSms),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('id-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: s.text));
                  if (mounted) setState(() => _info = l10n.pvCopied);
                },
                child: Text(l10n.pvCopy),
              ),
            ),
          ],
        ),
        if (pending)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.pvNotArrived(w.remainingAttempts ?? 0),
              key: const ValueKey('id-pending'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ];
      button = CommandButton(
        key: const ValueKey('id-sent'),
        label: l10n.pvSent,
        onPressed: busy ? null : () => _ctl.confirmIdentity(w),
      );
    } else {
      title = w.newAccount ? l10n.idJoinTitle : l10n.idExistingTitle;
      final error = switch ((w.status, w.lastError)) {
        ('EXPIRED', _) => l10n.pvExpired,
        ('FAILED', _) => l10n.pvTooManyAttempts,
        (_, 'PHONE_NOT_SUPPORTED') => l10n.pvPhoneInvalid,
        (_, 'TOO_MANY_VERIFICATIONS') => l10n.pvTooMany,
        (_, ProblemCode.unknownResult) => l10n.pvCheckLater,
        (_, null) => null,
        _ => l10n.pvStartFailed,
      };
      body = [
        TextField(
          key: const ValueKey('id-phone'),
          controller: _phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          inputFormatters: const [PhoneNumberFormatter()],
          style: const TextStyle(fontSize: 15),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.pvPhoneLabel,
            hintText: l10n.pvPhoneHint,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            errorText: error,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.pvInputGuide,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
      button = CommandButton(
        key: const ValueKey('id-next'),
        label: l10n.pvNext,
        onPressed: busy || !_mobile010.hasMatch(digits)
            ? null
            : () => _ctl.startIdentity(w, digits),
      );
    }

    return Scaffold(
      key: const ValueKey('login-identity'),
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('id-cancel'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
          onPressed: widget.onClose,
        ),
        title: Text(l10n.pvTitle),
        actions: [if (w.newAccount) const SignupStepCount(step: 2)],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, w.newAccount ? 8 : 20, 20, 20),
        children: [
          // 새 가입 단계 2/3(약관 동의 E안의 단계 표시 — 사용자 2026-11-21). 기존 회원 번호 확인은 단계 없이.
          if (w.newAccount) const SignupSteps(step: 2),
          Text(
            title,
            key: const ValueKey('id-title'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),
          ...body,
          if (_info case final i?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(i, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: button,
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final String valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(
        value,
        key: ValueKey(valueKey),
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
