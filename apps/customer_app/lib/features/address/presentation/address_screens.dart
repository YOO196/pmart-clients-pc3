import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/address.dart';
import 'address_controller.dart';

String serviceabilityText(AppLocalizations l10n, Serviceability s) =>
    switch (s) {
      Serviceability.serviceable => l10n.serviceable,
      Serviceability.outOfArea => l10n.serviceOutOfArea,
      Serviceability.unknown => l10n.serviceUnknown,
    };

String addressOutcomeText(
  AppLocalizations l10n,
  AddressCommandOutcome o,
) => switch (o) {
  AddressSaved(:final address) =>
    '${l10n.addressSaved}\n${serviceabilityText(l10n, address.serviceability)}',
  ShoppingAddressChanged() => l10n.shoppingAddressChanged,
  AddressCommandUnknown() => l10n.addressCommandUnknown,
  AddressConflict() => l10n.addressConflict,
  AddressCommandFailed() => l10n.addressCommandFailed,
};

/// 로그인이 필요한 화면의 안내. 로그인하면 이 화면에 머문다.
class LoginRequired extends StatelessWidget {
  const LoginRequired({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('go-login'),
            onPressed: () => context.push('/login'),
            child: Text(l10n.loginTitle),
          ),
        ],
      ),
    );
  }
}

/// SCR-ADDRESS-001. 쇼핑 주소를 고르면 둘러보기·장바구니가 그 센터 기준으로 다시 조회된다.
class AddressListScreen extends ConsumerWidget {
  const AddressListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(addressBookProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addressTitle)),
      floatingActionButton: value.value == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('address-add'),
              onPressed: () => context.push('/addresses/new'),
              icon: const Icon(Icons.add),
              label: Text(l10n.addressAdd),
            ),
      // 비회원도 배송지를 등록한다(업무 문서: 비회원 배송지). 비회원 배송지는 이 기기에서만 보인다.
      body: UiStateView<AddressBook?>(
        state: uiStateOf(value),
        onRetry: () => ref.invalidate(addressBookProvider),
        ready: (context, book) => _AddressList(book: book!),
      ),
    );
  }
}

class _AddressList extends ConsumerStatefulWidget {
  const _AddressList({required this.book});

  final AddressBook book;

  @override
  ConsumerState<_AddressList> createState() => _AddressListState();
}

class _AddressListState extends ConsumerState<_AddressList> {
  bool _busy = false;

  Future<void> _select(String addressId) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(addressBookProvider.notifier)
        .select(addressId);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(
      SnackBar(content: Text(addressOutcomeText(l10n, outcome))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = widget.book;
    if (book.addresses.isEmpty) {
      return Center(child: Text(l10n.addressEmpty));
    }
    return RadioGroup<String>(
      groupValue: book.context.shoppingAddressId,
      onChanged: (id) {
        if (id != null && !_busy) _select(id);
      },
      child: ListView(
        children: [
          if (_busy) const LinearProgressIndicator(),
          for (final a in book.addresses)
            RadioListTile<String>(
              key: ValueKey('address-${a.addressId}'),
              value: a.addressId,
              enabled: !_busy,
              title: Text(a.label ?? a.roadAddress),
              subtitle: Text(
                [
                  '${a.roadAddress} ${a.detailAddress}',
                  serviceabilityText(l10n, a.serviceability),
                ].join('\n'),
              ),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }
}

/// SCR-ADDRESS-EDIT-001. 주소 검색·지도 확인은 지도 키 결정 뒤 붙인다(지금은 직접 입력).
/// 시험 좌표 버튼을 보일지. 릴리스 빌드에서는 보이지 않는다.
const showDevTestGeo = !kReleaseMode;

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key});

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _road = TextEditingController();
  final _detail = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  EntranceMethod _entrance = EntranceMethod.free;
  ({double lat, double lng})? _geo;

  @override
  void dispose() {
    for (final c in [_label, _road, _detail, _name, _phone, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? AppLocalizations.of(context).fieldRequired
      : null;

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(addressBookProvider.notifier)
        .add(
          AddressDraft(
            label: _label.text.trim().isEmpty ? null : _label.text.trim(),
            roadAddress: _road.text.trim(),
            detailAddress: _detail.text.trim(),
            receiverName: _name.text.trim(),
            receiverPhone: _phone.text.trim(),
            entranceMethod: _entrance,
            entranceNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
            geo: _geo,
          ),
        );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(addressOutcomeText(l10n, outcome))),
    );
    if (outcome is AddressSaved || outcome is AddressCommandUnknown) {
      context.pop();
    }
  }

  Widget _field(
    String key,
    TextEditingController c,
    String label,
    int max, {
    bool required = true,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: c,
      maxLength: max,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label),
      validator: required ? _required : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addressAdd)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(
              'f-label',
              _label,
              l10n.addressLabel,
              AddressLimits.label,
              required: false,
            ),
            _field(
              'f-road',
              _road,
              l10n.addressRoad,
              AddressLimits.roadAddress,
            ),
            _field(
              'f-detail',
              _detail,
              l10n.addressDetail,
              AddressLimits.detailAddress,
            ),
            _field(
              'f-name',
              _name,
              l10n.addressReceiver,
              AddressLimits.receiverName,
            ),
            _field(
              'f-phone',
              _phone,
              l10n.addressPhone,
              AddressLimits.receiverPhone,
              keyboard: TextInputType.phone,
            ),
            DropdownButtonFormField<EntranceMethod>(
              initialValue: _entrance,
              decoration: InputDecoration(labelText: l10n.addressEntrance),
              items: [
                for (final m in EntranceMethod.values)
                  DropdownMenuItem(
                    value: m,
                    child: Text(switch (m) {
                      EntranceMethod.free => l10n.entranceFree,
                      EntranceMethod.password => l10n.entrancePassword,
                      EntranceMethod.call => l10n.entranceCall,
                      EntranceMethod.other => l10n.entranceOther,
                    }),
                  ),
              ],
              onChanged: (m) => setState(() => _entrance = m ?? _entrance),
            ),
            const SizedBox(height: 12),
            _field(
              'f-note',
              _note,
              l10n.addressEntranceNote,
              AddressLimits.entranceNote,
              required: false,
            ),
            // 개발 빌드 전용: 주소 검색(BR-29)이 없어 좌표를 보낼 수 없으므로 LAN 시험 권역 좌표를 넣는다.
            if (showDevTestGeo) ...[
              OutlinedButton.icon(
                key: const ValueKey('dev-test-geo'),
                icon: const Icon(Icons.science_outlined),
                label: Text(l10n.devTestGeoButton),
                onPressed: () => setState(() {
                  _geo = DevTestGeo.seomyeon;
                  if (_road.text.trim().isEmpty) {
                    _road.text = l10n.devTestGeoRoad;
                  }
                }),
              ),
              if (_geo case final g?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    l10n.devTestGeoSet(g.lat.toString(), g.lng.toString()),
                    key: const ValueKey('dev-test-geo-set'),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            CommandButton(
              key: const ValueKey('address-save'),
              label: l10n.addressSave,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
