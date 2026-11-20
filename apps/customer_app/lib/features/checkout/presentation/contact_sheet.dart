import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../address/presentation/address_controller.dart';
import '../../address/presentation/phone_number_formatter.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/profile_controller.dart';
import 'checkout_controller.dart';

/// 주문서 "내 연락처"(레퍼런스 6-3) — 번호를 받아 프로필에 저장하고(BR-32), 쇼핑 주소에 예전 연락처가
/// 저장돼 있으면 비운 뒤(그래야 프로필 번호를 쓴다), 초안을 새로 만든다(BR-60 R2·R3).
/// 이 주문만의 연락처 칸은 계약에 없다.
Future<void> editMyContact(BuildContext context, WidgetRef ref) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const ContactSheet(),
  );
  if (saved ?? false) {
    await ref.read(draftControllerProvider.notifier).contactChanged();
  }
}

class ContactSheet extends ConsumerStatefulWidget {
  const ContactSheet({super.key});

  @override
  ConsumerState<ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<ContactSheet> {
  final _focus = FocusNode();
  late final _phone = TextEditingController(
    text: switch (ref.read(profileProvider).value?.phone) {
      final p? => PhoneNumberFormatter.format(p),
      null => '',
    },
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _focus.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final l10n = AppLocalizations.of(context);
    if (!PhoneInput.valid(_phone.text)) {
      setState(() => _error = l10n.infoPhoneInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref
        .read(profileProvider.notifier)
        .changeProfile(phone: _phone.text);
    if (!mounted) return;
    final failed = switch (outcome) {
      ProfileChangeApplied() => null,
      ProfileChangeRejected(:final code)
          when code == ProblemCode.validationFailed =>
        l10n.infoPhoneInvalid,
      ProfileChangeUnsupported() => l10n.contactSaveUnsupported,
      ProfileChangeRejected() => l10n.contactSaveFailed,
      // 접수만 됐거나 결과를 모른다 — 저장됐다고 하지 않는다.
      ProfileChangePending() ||
      ProfileChangeUnknown() => l10n.contactSaveUnknown,
    };
    if (failed != null) {
      setState(() {
        _busy = false;
        _error = failed;
      });
      return;
    }
    // 쇼핑 주소에 예전 연락처가 있으면 그것이 먼저 쓰인다 — 비워서 프로필 번호를 따르게 한다(회신 R3).
    final addressId = ref
        .read(addressBookProvider)
        .value
        ?.context
        .shoppingAddressId;
    if (addressId != null) {
      try {
        await ref
            .read(addressRepositoryProvider)
            .clearStoredPhone(addressId, key: IdempotencyKey.generate());
      } on PmartFailure {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = l10n.contactAddressFailed;
        });
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        key: const ValueKey('contact-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.contactTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('contact-close'),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('contact-phone-input'),
            controller: _phone,
            focusNode: _focus,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.phone,
            inputFormatters: const [PhoneNumberFormatter()],
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17),
            decoration: InputDecoration(
              hintText: l10n.contactHint,
              errorText: _error,
              contentPadding: const EdgeInsets.fromLTRB(16, 18, 8, 18),
              // 레퍼런스 6-3: 칸 안 오른쪽 [번호 변경] — 누르면 번호를 지우고 새로 입력
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: OutlinedButton(
                  key: const ValueKey('contact-phone-clear'),
                  onPressed: _busy
                      ? null
                      : () {
                          _phone.clear();
                          _focus.requestFocus();
                        },
                  style: OutlinedButton.styleFrom(
                    textStyle: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                    ),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(l10n.contactChange),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: 34),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.contactGuide,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          CommandButton(
            key: const ValueKey('contact-done'),
            label: l10n.contactDone,
            onPressed: _busy ? null : _done,
          ),
        ],
      ),
    );
  }
}
