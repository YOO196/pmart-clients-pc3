import 'package:flutter/material.dart';
import 'package:pmart_ui/pmart_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/geocoding_repository.dart';

typedef GeoPoint = ({double lat, double lng});

final geocodingRepositoryProvider = Provider<GeocodingRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockGeocodingRepository(),
    // 고객·비회원 토큰 모두 쓸 수 있다(guest-paths). 토큰 없이는 401.
    PmartEnv.local => ApiGeocodingRepository(
      ref.watch(sessionProvider) is MemberSession
          ? ref.watch(dioProvider)
          : ref.watch(guestDioProvider),
    ),
  },
);

/// 카카오 네이티브 앱 키(빌드 때 `--dart-define-from-file=.secrets/customer.env`). 비면 지도를 쓰지 않는다.
const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');

/// 지도 위젯. 실서버이고 키가 있을 때만 카카오 지도, 그 밖(목·시험·키 없음)은 지도 없이 좌표만 확인한다.
/// 카카오 지도는 arm 기기에서만 동작한다(x86 에뮬레이터 불가).
final mapAvailableProvider = Provider<bool>(
  (ref) =>
      ref.watch(envProvider) == PmartEnv.local && kakaoNativeAppKey.isNotEmpty,
);

/// SCR-ADDRESS 지도에서 배달 위치 맞추기. 지도 가운데 핀이 배달 위치다. 확인하면 [GeoPoint] 로 닫힌다.
///
/// 핀 좌표는 배달 위치 참고일 뿐이다. 배송 가능 판정은 서버가 고른 도로명주소로 한다(ADR-0023).
class MapPickScreen extends ConsumerStatefulWidget {
  const MapPickScreen({
    super.key,
    required this.initial,
    required this.roadAddress,
  });

  final GeoPoint initial;
  final String roadAddress;

  @override
  ConsumerState<MapPickScreen> createState() => _MapPickScreenState();
}

class _MapPickScreenState extends ConsumerState<MapPickScreen> {
  late GeoPoint _pin = widget.initial;
  String? _pinLabel;
  bool _lookupFailed = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _describe(_pin);
  }

  /// 핀 위치의 주소를 보여 준다(표시용). 늦게 온 이전 응답은 버린다.
  Future<void> _describe(GeoPoint p) async {
    final seq = ++_seq;
    try {
      final found = await ref
          .read(geocodingRepositoryProvider)
          .reverse(p.lat, p.lng);
      if (!mounted || seq != _seq) return;
      setState(() {
        _pinLabel = found.firstOrNull?.label;
        _lookupFailed = false;
      });
    } on PmartFailure {
      if (!mounted || seq != _seq) return;
      setState(() {
        _pinLabel = null;
        _lookupFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mapAvailable = ref.watch(mapAvailableProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mapPickTitle)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (mapAvailable)
                  kakao.KakaoMap(
                    option: kakao.KakaoMapOption(
                      position: kakao.LatLng(
                        widget.initial.lat,
                        widget.initial.lng,
                      ),
                      zoomLevel: 17,
                    ),
                    onMapReady: (_) {},
                    onCameraMoveEnd: (position, _) {
                      final p = (
                        lat: position.position.latitude,
                        lng: position.position.longitude,
                      );
                      setState(() => _pin = p);
                      _describe(p);
                    },
                  )
                else
                  Container(
                    key: const ValueKey('map-unavailable'),
                    color: theme.colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.mapUnavailable,
                      textAlign: TextAlign.center,
                    ),
                  ),
                // 지도 가운데 고정 핀(핀 끝이 가운데에 오도록 아이콘 높이 절반만큼 올린다).
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: PmartLineIcon(PmartLineIcons.pin,
                      size: 40,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.roadAddress, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    _lookupFailed
                        ? l10n.mapPinLookupFailed
                        : _pinLabel == null
                        ? l10n.mapPinChecking
                        : l10n.mapPinHere(_pinLabel!),
                    key: const ValueKey('map-pin-label'),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.mapPinGuide, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('map-confirm'),
                    onPressed: () => Navigator.of(context).pop(_pin),
                    child: Text(l10n.mapConfirm),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
