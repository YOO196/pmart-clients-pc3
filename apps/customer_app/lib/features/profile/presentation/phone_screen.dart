import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../domain/profile.dart';
import 'profile_controller.dart';

/// 휴대폰 번호 등록(회원가입 직후)·변경(마이). 저장은 서버 결과(APPLIED)로만 확정한다.
///
/// 가입 직후([signup])에는 저장할 때까지 닫지 않는다. 서버가 저장을 제공하지 않거나(501)
/// 결과를 확인하지 못했을 때만 "나중에 하기"를 연다(가입을 막지 않는다).
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key, this.signup = false});

  final bool signup;

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  ProfileChangeOutcome? _last;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool get _canSkip =>
      _last is ProfileChangeUnsupported || _last is ProfileChangeUnknown;

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(profileProvider.notifier)
        .changePhone(_phone.text);
    if (!mounted) return;
    setState(() => _last = outcome);
    if (outcome is ProfileChangeApplied) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.phoneSaved)));
      context.pop(true);
    }
  }

  String? _message(AppLocalizations l10n) => switch (_last) {
    null || ProfileChangeApplied() => null,
    ProfileChangePending() => l10n.phonePending,
    ProfileChangeUnsupported() => l10n.phoneUnsupported,
    ProfileChangeRejected() => l10n.phoneRejected,
    ProfileChangeUnknown() => l10n.phoneUnknown,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(profileProvider).value;
    final message = _message(l10n);
    return PopScope(
      canPop: !widget.signup || _canSkip,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.signup ? l10n.phoneSignupTitle : l10n.phoneTitle),
          automaticallyImplyLeading: !widget.signup,
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.signup ? l10n.phoneSignupGuide : l10n.phoneGuide),
              if (!widget.signup && (profile?.hasPhone ?? false)) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.phoneCurrent(profile!.phoneMasked!),
                  key: const ValueKey('phone-current'),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('phone-input'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                maxLength: 13,
                decoration: InputDecoration(
                  labelText: l10n.addressPhone,
                  hintText: '010-1234-5678',
                ),
                validator: (v) =>
                    PhoneInput.valid(v ?? '') ? null : l10n.phoneInvalid,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message, key: const ValueKey('phone-message')),
              ],
              const SizedBox(height: 16),
              CommandButton(
                key: const ValueKey('phone-save'),
                label: l10n.phoneSave,
                onPressed: _save,
              ),
              if (widget.signup && _canSkip)
                TextButton(
                  key: const ValueKey('phone-later'),
                  onPressed: () => context.pop(false),
                  child: Text(l10n.phoneLater),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
