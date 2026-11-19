import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;
import '../../profile/domain/profile.dart' show Profile;
import '../../profile/presentation/profile_controller.dart'
    show profileProvider;
import '../data/geocoding_repository.dart';
import '../domain/address.dart';
import 'map_pick_screen.dart';
import 'phone_number_formatter.dart';
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
              // 레퍼런스: 왼쪽 위치 표시, 오른쪽 선택 표시.
              controlAffinity: ListTileControlAffinity.trailing,
              secondary: const Icon(Icons.place, size: 22),
              title: Text(
                a.label ?? a.roadAddress,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    '${a.roadAddress} ${a.detailAddress}',
                    serviceabilityText(l10n, a.serviceability),
                  ].join('\n'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
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
  const AddressFormScreen({super.key, this.initial});

  /// 이미 고른 주소 검색 결과(처음 실행 주소 화면). 있으면 도로명을 채우고 바로 지도 핀으로 간다.
  final PostcodeResult? initial;

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

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _road.text = initial.roadAddress;
      _postalCode = initial.zoneNo;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _locate();
      });
    }
  }

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

  /// 받는 분·연락처를 물을지. 레퍼런스 주소 상세(2-7-1)에는 두 칸이 없다 — 회원은 프로필 이름·연락처로 채운다(BR-60).
  /// 계약 `AddressInput` 이 아직 두 값을 필수로 받아서, 프로필에 없거나 프로필을 못 읽으면 그 칸만 묻는다.
  /// 비회원은 프로필이 없어 둘 다 묻는다(BR-60 R1 회신 뒤 뺀다).
  _Receiver _receiver() {
    if (ref.watch(sessionProvider) is! MemberSession) {
      return const _Receiver(member: false, askName: true, askPhone: true);
    }
    return switch (ref.watch(profileProvider)) {
      AsyncData(value: final p?) => _Receiver(
        member: true,
        askName: _profileName(p) == null,
        askPhone: p.phone == null,
        profile: p,
      ),
      // 읽는 중에는 칸을 숨기고, 저장 때 다 읽힐 때까지 기다린다.
      AsyncLoading() => const _Receiver(
        member: true,
        askName: false,
        askPhone: false,
        loading: true,
      ),
      // 못 읽었으면 값을 지어내지 않고 묻는다.
      _ => const _Receiver(member: true, askName: true, askPhone: true),
    };
  }

  static String? _profileName(Profile p) => switch (p.nickname?.trim()) {
    final n? when n.isNotEmpty => n,
    _ => p.name,
  };

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    var receiver = _receiver();
    if (receiver.loading) {
      try {
        await ref.read(profileProvider.future);
      } on PmartFailure {
        // 아래에서 다시 판단한다(칸이 보이게 된다).
      }
      if (!mounted) return;
      receiver = _receiver();
      // 프로필에 없어 이제 칸을 보여야 하면 입력을 받은 뒤 다시 누르게 한다.
      if (receiver.askName || receiver.askPhone) {
        setState(() {});
        return;
      }
    }
    final profile = receiver.profile;
    final receiverName = receiver.askName
        ? _name.text.trim()
        : _profileName(profile!)!;
    final receiverPhone = receiver.askPhone
        ? _phone.text.trim()
        : PhoneNumberFormatter.format(profile!.phone!);
    // 회원이 처음 넣은 연락처는 프로필에도 남겨 다음부터 묻지 않는다(BR-32 — 본인 확인 없는 연락처).
    // 저장이 안 돼도(옛 서버·형식) 주소는 그 번호로 저장한다.
    if (receiver.askPhone && profile != null) {
      await ref
          .read(profileProvider.notifier)
          .changeProfile(phone: receiverPhone);
      if (!mounted) return;
    }
    final outcome = await ref
        .read(addressBookProvider.notifier)
        .add(
          AddressDraft(
            label: _label.text.trim().isEmpty ? null : _label.text.trim(),
            roadAddress: _road.text.trim(),
            detailAddress: _detail.text.trim(),
            receiverName: receiverName,
            receiverPhone: receiverPhone,
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
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: c,
      maxLength: max,
      keyboardType: keyboard,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
      validator: required ? _required : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final receiver = _receiver();
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
            if (receiver.askName)
              _field(
                'f-name',
                _name,
                l10n.addressReceiver,
                AddressLimits.receiverName,
              ),
            if (receiver.askPhone)
              _field(
                'f-phone',
                _phone,
                receiver.member ? l10n.addressMyPhone : l10n.addressPhone,
                AddressLimits.receiverPhone,
                keyboard: TextInputType.phone,
                formatters: const [PhoneNumberFormatter()],
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

/// 주소 입력에서 받는 분·연락처를 물을지([_AddressFormScreenState._receiver]).
final class _Receiver {
  const _Receiver({
    required this.member,
    required this.askName,
    required this.askPhone,
    this.profile,
    this.loading = false,
  });

  final bool member;
  final bool askName;
  final bool askPhone;

  /// 회원 프로필(읽었을 때만). 묻지 않는 값은 여기서 채운다.
  final Profile? profile;

  /// 프로필을 읽는 중.
  final bool loading;
}
