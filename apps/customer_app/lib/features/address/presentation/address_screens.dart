import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../data/geocoding_repository.dart';
import '../domain/address.dart';
import 'map_pick_screen.dart';
import 'postcode_screen.dart';
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

/// 시험 주소 버튼을 보일지. 릴리스 빌드에서는 보이지 않는다.
const showDevTestGeo = !kReleaseMode;

/// 주소 검색 화면을 띄운다(시험에서 바꿔 끼운다). 고르면 결과, 취소는 null.
typedef AddressSearch = Future<PostcodeResult?> Function(BuildContext context);

final addressSearchProvider = Provider<AddressSearch>(
  (_) =>
      (context) => Navigator.of(context).push<PostcodeResult>(
        MaterialPageRoute(builder: (_) => const PostcodeScreen()),
      ),
);

/// 지도에서 배달 위치를 맞춘다(시험에서 바꿔 끼운다). 확인하면 좌표, 취소는 null.
typedef MapPick = Future<GeoPoint?> Function(
  BuildContext context,
  GeoPoint initial,
  String roadAddress,
);

final mapPickProvider = Provider<MapPick>(
  (_) =>
      (context, initial, road) => Navigator.of(context).push<GeoPoint>(
        MaterialPageRoute(
          builder: (_) => MapPickScreen(initial: initial, roadAddress: road),
        ),
      ),
);

/// 배달 위치(지도 핀) 상태. 판정은 서버가 도로명으로 하므로 위치를 못 맞춰도 저장은 된다.
enum _PinState { none, picking, picked, notFound, failed }

/// SCR-ADDRESS-EDIT-001. 도로명주소는 주소 검색에서만 고른다(직접 입력하지 않음 — 판정이 도로명 기준, ADR-0023).
/// 고르면 서버 좌표 변환으로 지도를 열고, 고객이 핀으로 배달 위치를 맞춘다.

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
  GeoPoint? _geo;
  String? _postalCode;
  _PinState _pin = _PinState.none;

  /// 주소 검색 → 서버 좌표 변환 → 지도 핀.
  Future<void> _search() async {
    final picked = await ref.read(addressSearchProvider)(context);
    if (picked == null || !mounted) return;
    setState(() {
      _road.text = picked.roadAddress;
      _postalCode = picked.zoneNo;
      _geo = null;
    });
    await _locate();
  }

  Future<void> _locate() async {
    final road = _road.text.trim();
    if (road.isEmpty) return;
    setState(() => _pin = _PinState.picking);
    final List<AddressCandidate> found;
    try {
      found = await ref.read(geocodingRepositoryProvider).geocode(road);
    } on PmartFailure {
      // 조회 실패는 "주소 없음"이 아니다. 주소는 그대로 저장할 수 있다.
      if (mounted) setState(() => _pin = _PinState.failed);
      return;
    }
    if (!mounted) return;
    final start = found.firstOrNull;
    if (start == null) {
      setState(() => _pin = _PinState.notFound);
      return;
    }
    final initial = _geo ?? (lat: start.lat, lng: start.lng);
    final point = await ref.read(mapPickProvider)(context, initial, road);
    if (!mounted) return;
    setState(() {
      if (point != null) _geo = point;
      _pin = _geo == null ? _PinState.none : _PinState.picked;
    });
  }

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
            postalCode: _postalCode,
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
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextFormField(
                key: const ValueKey('f-road'),
                controller: _road,
                readOnly: true,
                onTap: _search,
                decoration: InputDecoration(
                  labelText: l10n.addressRoad,
                  hintText: l10n.addressSearchHint,
                  suffixIcon: IconButton(
                    key: const ValueKey('address-search'),
                    icon: const Icon(Icons.search),
                    tooltip: l10n.addressSearchTitle,
                    onPressed: _search,
                  ),
                ),
                validator: _required,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (_pin) {
                        _PinState.none => l10n.addressPinNone,
                        _PinState.picking => l10n.addressPinPicking,
                        _PinState.picked => l10n.addressPinPicked,
                        _PinState.notFound => l10n.addressPinNotFound,
                        _PinState.failed => l10n.addressPinFailed,
                      },
                      key: const ValueKey('address-pin-state'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (_road.text.trim().isNotEmpty && _pin != _PinState.picking)
                    TextButton(
                      key: const ValueKey('address-map'),
                      onPressed: _locate,
                      child: Text(l10n.addressPinAdjust),
                    ),
                ],
              ),
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
            // 개발 빌드 전용: 카카오 지도가 안 되는 x86 에뮬레이터에서 시험할 때 권역 안 실제 도로명주소를 넣는다.
            if (showDevTestGeo) ...[
              OutlinedButton.icon(
                key: const ValueKey('dev-test-geo'),
                icon: const Icon(Icons.science_outlined),
                label: Text(l10n.devTestGeoButton),
                onPressed: () => setState(() {
                  _road.text = DevTestAddress.roadAddress;
                  _postalCode = DevTestAddress.postalCode;
                  _geo = DevTestAddress.geo;
                  _pin = _PinState.picked;
                }),
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
