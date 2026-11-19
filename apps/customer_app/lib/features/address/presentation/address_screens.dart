import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LengthLimitingTextInputFormatter, TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart'
    show PmartFailure, ProblemCode, ProblemFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../data/geocoding_repository.dart';
import '../domain/address.dart';
import 'address_map_preview.dart';
import 'map_pick_screen.dart';
import 'postcode_screen.dart';
import 'address_controller.dart';
import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;

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
  AddressDeleted() => l10n.addressDeleted,
  AddressCommandUnknown() => l10n.addressCommandUnknown,
  AddressConflict() => l10n.addressConflict,
  AddressCommandFailed(:final failure)
      when failure is ProblemFailure &&
          failure.problem.code == ProblemCode.invalidState =>
    l10n.addressDeleteInUse,
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
    // 삭제는 회원 주소록만(비회원 배송지는 이 기기의 목록).
    final canEdit =
        ref.watch(sessionProvider) is MemberSession &&
        (value.value?.addresses.isNotEmpty ?? false);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addressTitle),
        actions: [
          if (canEdit)
            TextButton(
              key: const ValueKey('address-edit'),
              onPressed: () => context.push('/addresses/edit'),
              child: Text(l10n.addressEdit),
            ),
        ],
      ),
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

/// 레퍼런스 3-1 2-3 "주소 편집". 현재 쇼핑 주소는 표시만 하고(서버도 409), 나머지는 확인 뒤 삭제.
/// 지운 결과는 서버 주소록을 다시 읽어 보인다.
class AddressEditScreen extends ConsumerStatefulWidget {
  const AddressEditScreen({super.key});

  @override
  ConsumerState<AddressEditScreen> createState() => _AddressEditScreenState();
}

class _AddressEditScreenState extends ConsumerState<AddressEditScreen> {
  String? _deleting;

  Future<void> _delete(Address a) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addressDeleteConfirmTitle),
        content: Text(l10n.addressDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.addressDeleteCancel),
          ),
          TextButton(
            key: const ValueKey('address-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.addressDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = a.addressId);
    final outcome = await ref
        .read(addressBookProvider.notifier)
        .remove(a.addressId);
    if (!mounted) return;
    setState(() => _deleting = null);
    messenger.showSnackBar(
      SnackBar(content: Text(addressOutcomeText(l10n, outcome))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = ref.watch(addressBookProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addressEditTitle)),
      body: UiStateView<AddressBook?>(
        state: uiStateOf(value),
        onRetry: () => ref.invalidate(addressBookProvider),
        ready: (context, book) {
          final addresses = book?.addresses ?? const <Address>[];
          if (addresses.isEmpty) return Center(child: Text(l10n.addressEmpty));
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: addresses.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = addresses[i];
              final current = a.addressId == book!.context.shoppingAddressId;
              return Padding(
                key: ValueKey('address-edit-${a.addressId}'),
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: 14),
                      child: Icon(Icons.place, size: 22),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                a.label ?? a.roadAddress,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (current)
                                Container(
                                  key: const ValueKey('address-current-badge'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    l10n.addressCurrent,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${a.roadAddress} ${a.detailAddress}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (!current) ...[
                            const SizedBox(height: 10),
                            OutlinedButton(
                              key: ValueKey('address-delete-${a.addressId}'),
                              onPressed: _deleting == null
                                  ? () => _delete(a)
                                  : null,
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                minimumSize: const Size(0, 34),
                              ),
                              child: _deleting == a.addressId
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(l10n.addressDelete),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
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
/// [preview] = 서버 좌표로 미리보기만 보임(고객 확인 전), [picked] = 큰 지도에서 확인함.
enum _PinState { none, picking, preview, picked, notFound, failed }

/// SCR-ADDRESS-EDIT-001 주소 상세(레퍼런스 2-7-1). 도로명주소는 주소 검색에서만 고른다(직접 입력하지 않음 — 판정이 도로명 기준, ADR-0023).
/// 고르면 서버 좌표 변환으로 지도 미리보기를 보이고, "지도에서 위치 확인"으로 큰 지도에서 핀을 맞춘다(7-2).

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, this.initial});

  /// 이미 고른 주소 검색 결과(처음 실행 주소 화면). 있으면 도로명을 채우고 바로 지도 핀으로 간다.
  final PostcodeResult? initial;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _form = GlobalKey<FormState>();
  final _road = TextEditingController();
  final _detail = TextEditingController();
  final _password = TextEditingController();
  final _directions = TextEditingController();

  /// 고객이 큰 지도에서 확인한 배달 위치(보낼 `geo`). 확인 전에는 null — 서버가 도로명으로 채운다.
  GeoPoint? _geo;

  /// 서버 주소 변환 좌표(미리보기·큰 지도 시작 위치). 보내지 않는다.
  GeoPoint? _preview;
  String? _jibun;
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
        if (mounted) _geocode();
      });
    }
  }

  /// 주소 검색 → 서버 좌표 변환 → 미리보기(레퍼런스 2-7-1). 큰 지도는 "지도에서 위치 확인"으로 연다(7-2).
  Future<void> _search() async {
    final picked = await ref.read(addressSearchProvider)(context);
    if (picked == null || !mounted) return;
    setState(() {
      _road.text = picked.roadAddress;
      _postalCode = picked.zoneNo;
      _geo = null;
      _preview = null;
      _jibun = null;
    });
    await _geocode();
  }

  Future<void> _geocode() async {
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
    setState(() {
      _preview = start == null ? null : (lat: start.lat, lng: start.lng);
      _jibun = start?.jibunAddress;
      _pin = start == null
          ? _PinState.notFound
          : (_geo == null ? _PinState.preview : _PinState.picked);
    });
  }

  /// 큰 지도에서 배달 위치를 맞춘다. 앞서 맞춘 핀이 있으면 거기서 시작한다.
  Future<void> _openMap() async {
    if (_pin == _PinState.failed) await _geocode();
    final start = _geo ?? _preview;
    if (start == null || !mounted) return;
    final point = await ref.read(mapPickProvider)(
      context,
      start,
      _road.text.trim(),
    );
    if (point == null || !mounted) return;
    setState(() {
      _geo = point;
      _pin = _PinState.picked;
    });
  }

  @override
  void dispose() {
    for (final c in [_road, _detail, _password, _directions]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 공동현관 비밀번호·찾아오는 길 → 계약 `entranceMethod`·`entranceNote`(칸이 하나라 이어 붙인다, 100자).
  /// 비밀번호를 넣으면 PASSWORD, 아니면 지금까지의 기본값처럼 FREE.
  ({EntranceMethod method, String? note}) _entrance() {
    final password = _password.text.trim();
    final directions = _directions.text.trim();
    final note = [
      if (password.isNotEmpty) password,
      if (directions.isNotEmpty) directions,
    ].join(' · ');
    return (
      method: password.isEmpty ? EntranceMethod.free : EntranceMethod.password,
      note: note.isEmpty ? null : note,
    );
  }

  String? _noteLength(String? _) {
    final note = _entrance().note;
    return note != null && note.length > AddressLimits.entranceNote
        ? AppLocalizations.of(context)
              .addressEntranceTooLong(AddressLimits.entranceNote)
        : null;
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? AppLocalizations.of(context).fieldRequired
      : null;

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final entrance = _entrance();
    final outcome = await ref
        .read(addressBookProvider.notifier)
        .add(
          AddressDraft(
            roadAddress: _road.text.trim(),
            detailAddress: _detail.text.trim(),
            // 받는 분·연락처는 보내지 않는다 — 주문 초안이 회원 프로필 값을 쓴다(BR-60 R1·R2).
            entranceMethod: entrance.method,
            entranceNote: entrance.note,
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

  /// 레퍼런스 2-7-1 입력 칸: 위에 회색 이름(있으면), 둥근 테두리 칸 안에 예시 글. 글자 수는 보이지 않는다(상한만).
  Widget _field(
    String key,
    TextEditingController c, {
    String? label,
    String? hint,
    required int max,
    bool required = true,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    FormFieldValidator<String>? validator,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 13.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          TextFormField(
            key: ValueKey(key),
            controller: c,
            keyboardType: keyboard,
            inputFormatters: [
              LengthLimitingTextInputFormatter(max),
              ...?formatters,
            ],
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
            decoration: InputDecoration(
              // 칸 이름은 위에 따로 둔다 — 칸 안에는 예시만.
              hintText: hint ?? label,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 14,
              ),
            ),
            validator: validator ?? (required ? _required : null),
          ),
        ],
      ),
    );
  }

  /// 도로명 제목(크게)·지번(작게). 주소를 아직 고르지 않았으면 검색 칸.
  Widget _addressHeader(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final road = _road.text.trim();
    if (road.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: TextFormField(
          key: const ValueKey('f-road'),
          controller: _road,
          readOnly: true,
          onTap: _search,
          decoration: InputDecoration(
            hintText: l10n.addressSearchHint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: IconButton(
              key: const ValueKey('address-search'),
              icon: const PmartLineIcon(PmartLineIcons.search, size: 22),
              tooltip: l10n.addressSearchTitle,
              onPressed: _search,
            ),
          ),
          validator: _required,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 0, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  road,
                  key: const ValueKey('f-road'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_jibun case final j?) ...[
                  const SizedBox(height: 4),
                  Text(
                    j,
                    key: const ValueKey('address-jibun'),
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14.5),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('address-search'),
            onPressed: _search,
            child: Text(l10n.addressChange),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chosen = _road.text.trim().isNotEmpty;
    final small = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addressDetailTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 24),
          children: [
            if (chosen) ...[
              AddressMapPreview(
                point: _geo ?? _preview,
                onOpen: _pin == _PinState.picking || _pin == _PinState.notFound
                    ? null
                    : _openMap,
              ),
              const SizedBox(height: 6),
            ],
            Text(
              switch (_pin) {
                _PinState.none => l10n.addressPinNone,
                _PinState.picking => l10n.addressPinPicking,
                _PinState.preview => l10n.addressPinPreview,
                _PinState.picked => l10n.addressPinPicked,
                _PinState.notFound => l10n.addressPinNotFound,
                _PinState.failed => l10n.addressPinFailed,
              },
              key: const ValueKey('address-pin-state'),
              style: small,
            ),
            const SizedBox(height: 4),
            _addressHeader(l10n),
            _field(
              'f-detail',
              _detail,
              hint: l10n.addressDetailHint,
              max: AddressLimits.detailAddress,
            ),
            _field(
              'f-entrance-password',
              _password,
              label: l10n.addressEntrancePassword,
              hint: l10n.addressEntrancePasswordHint,
              max: AddressLimits.entranceNote,
              required: false,
              validator: _noteLength,
            ),
            _field(
              'f-note',
              _directions,
              label: l10n.addressDirections,
              hint: l10n.addressDirectionsHint,
              max: AddressLimits.entranceNote,
              required: false,
              validator: _noteLength,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 6, 0),
                  child: Text('•', style: small),
                ),
                Expanded(child: Text(l10n.addressEntranceGuide, style: small)),
              ],
            ),
            // 개발 빌드 전용: 카카오 지도가 안 되는 x86 에뮬레이터에서 시험할 때 권역 안 실제 도로명주소를 넣는다.
            if (showDevTestGeo) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const ValueKey('dev-test-geo'),
                icon: const Icon(Icons.science_outlined),
                label: Text(l10n.devTestGeoButton),
                onPressed: () => setState(() {
                  _road.text = DevTestAddress.roadAddress;
                  _postalCode = DevTestAddress.postalCode;
                  _geo = DevTestAddress.geo;
                  _preview = DevTestAddress.geo;
                  _pin = _PinState.picked;
                }),
              ),
            ],
          ],
        ),
      ),
      // 레퍼런스: 아래 고정 "주소 등록"(위에 얇은 선).
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: CommandButton(
              key: const ValueKey('address-save'),
              label: l10n.addressRegister,
              onPressed: _save,
            ),
          ),
        ),
      ),
    );
  }
}
