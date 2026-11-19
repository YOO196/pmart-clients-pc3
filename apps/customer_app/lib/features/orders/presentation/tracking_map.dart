import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../address/presentation/map_pick_screen.dart'
    show GeoPoint, mapAvailableProvider;

/// 배송현황 지도(레퍼런스 8-5 "배달중 — 라이더 마커, 이동"). 라이더 마커와 내 배송지 마커만 그린다.
///
/// - [rider] 는 서버가 준 라이더 지금 위치(`DeliveryEta.riderLocation` — SSE `ETA_UPDATED` 로 받는다,
///   PC 5 요청 2026-11-19 `clients/all/2026-11-19-notice-live-rider-location.md`). 바뀌면 마커가 [glide] 동안
///   새 자리로 미끄러져 간다. null 이면 라이더 마커를 숨긴다(서버가 주지 않으면 지어내지 않는다).
/// - [riderStale] 이면(서버가 받은 지 60초 넘음) 마커를 흐리게 한다.
/// - [home] 은 주문 당시 배송지 지도 핀(`ShippingAddress.geo`). 없으면 그리지 않는다.
/// - 출발지(MFC)는 고객이 받을 길이 계약에 없어 그리지 않는다(사용자 2026-11-19 "빼고 요청도 안 함").
/// - 지나온 길은 서버가 주지 않아 그리지 않는다.
///
/// [rider]·[home] 중 하나는 있어야 한다(지도 가운데). 카카오 지도는 실서버·키가 있을 때만([mapAvailableProvider]).
/// 목·시험·키 없음이면 지도 대신 안내 칸.
class TrackingMap extends ConsumerStatefulWidget {
  const TrackingMap({
    super.key,
    required this.rider,
    this.home,
    this.riderStale = false,
  }) : assert(rider != null || home != null);

  final GeoPoint? rider;
  final GeoPoint? home;
  final bool riderStale;

  /// 마커가 이전 점에서 새 점으로 움직이는 시간.
  static const glide = Duration(seconds: 1);

  @override
  ConsumerState<TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends ConsumerState<TrackingMap> {
  kakao.KakaoMapController? _map;
  kakao.Poi? _riderPoi;
  kakao.PoiStyle? _riderStyle;
  kakao.PoiStyle? _riderDimStyle;
  bool? _shownStale;

  static kakao.LatLng _ll(GeoPoint p) => kakao.LatLng(p.lat, p.lng);

  Future<void> _onReady(kakao.KakaoMapController map) async {
    final scheme = Theme.of(context).colorScheme;
    final riderIcon = await kakao.KImage.fromWidget(
      _RiderMarker(color: scheme.primary),
      const Size(44, 44),
      context: context,
    );
    if (!mounted) return;
    final riderDimIcon = await kakao.KImage.fromWidget(
      Opacity(opacity: 0.4, child: _RiderMarker(color: scheme.primary)),
      const Size(44, 44),
      context: context,
    );
    if (!mounted) return;
    final homeIcon = await kakao.KImage.fromWidget(
      _HomeMarker(color: scheme.primary),
      const Size(40, 40),
      context: context,
    );
    if (!mounted) return;
    const center = kakao.KPoint(0.5, 0.5);
    _riderStyle = kakao.PoiStyle(icon: riderIcon, anchor: center);
    _riderDimStyle = kakao.PoiStyle(icon: riderDimIcon, anchor: center);
    if (widget.home case final h?) {
      await map.labelLayer.addPoi(
        _ll(h),
        style: kakao.PoiStyle(icon: homeIcon, anchor: center),
      );
    }
    _map = map;
    await _syncRider(animate: false);
    await _fit();
  }

  /// 라이더 마커를 지금 값에 맞춘다 — 없으면 숨김, 처음이면 만들기, 있으면 미끄러지듯 옮기기, 오래됨이면 흐리게.
  Future<void> _syncRider({bool animate = true}) async {
    final map = _map;
    final normal = _riderStyle;
    final dim = _riderDimStyle;
    if (map == null || normal == null || dim == null) return;
    final rider = widget.rider;
    final poi = _riderPoi;
    if (rider == null) {
      await poi?.hide();
      return;
    }
    final style = widget.riderStale ? dim : normal;
    if (poi == null) {
      _riderPoi = await map.labelLayer.addPoi(_ll(rider), style: style, rank: 1);
      _shownStale = widget.riderStale;
      return;
    }
    if (!poi.visible) await poi.show();
    if (_shownStale != widget.riderStale) {
      await poi.changeStyles(style);
      _shownStale = widget.riderStale;
    }
    await poi.move(
      _ll(rider),
      animate ? TrackingMap.glide.inMilliseconds : null,
    );
  }

  /// 라이더와 배송지가 함께 보이게 맞춘다(하나만 있으면 그 가운데).
  Future<void> _fit() async {
    final map = _map;
    if (map == null) return;
    final points = [?widget.rider, ?widget.home];
    await map.moveCamera(
      points.length == 1
          ? kakao.CameraUpdate.newCenterPosition(
              _ll(points.single),
              zoomLevel: 16,
            )
          : kakao.CameraUpdate.fitMapPoints([
              for (final p in points) _ll(p),
            ], padding: 80),
    );
  }

  @override
  void didUpdateWidget(TrackingMap old) {
    super.didUpdateWidget(old);
    final moved = old.rider != widget.rider;
    if (moved || old.riderStale != widget.riderStale) {
      _syncRider();
      // 마커가 나타나거나 사라질 때만 화면을 다시 맞춘다(움직일 때마다 카메라가 흔들리지 않게).
      if ((old.rider == null) != (widget.rider == null)) _fit();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(mapAvailableProvider)) {
      final theme = Theme.of(context);
      return Container(
        key: const ValueKey('track-map-unavailable'),
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context).trackMapUnavailable,
          textAlign: TextAlign.center,
        ),
      );
    }
    return kakao.KakaoMap(
      key: const ValueKey('track-map'),
      option: kakao.KakaoMapOption(
        position: _ll((widget.rider ?? widget.home)!),
        zoomLevel: 16,
      ),
      onMapReady: _onReady,
    );
  }
}

/// 라이더 마커: 브랜드색 원 + 흰 테두리(지금 위치 한 점).
class _RiderMarker extends StatelessWidget {
  const _RiderMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Color(0x40000000))],
      ),
    ),
  );
}

/// 내 배송지 마커: 흰 원 안에 얇은 선 집 아이콘.
class _HomeMarker extends StatelessWidget {
  const _HomeMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: PmartLineIcon(PmartLineIcons.home, size: 20, color: color),
    ),
  );
}
