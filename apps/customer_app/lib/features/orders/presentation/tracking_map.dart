import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../address/presentation/map_pick_screen.dart'
    show GeoPoint, mapAvailableProvider;

/// 배송현황 지도(레퍼런스 8-5 "배달중 — 라이더 마커, 이동"). 라이더 마커와 내 배송지 마커만 그린다.
///
/// - [rider] 는 서버가 준 라이더 지금 위치(`DeliveryEta.riderLocation`)다. 바뀌면 마커를 그 자리로 옮긴다.
/// - [home] 은 주문 당시 배송지 지도 핀(`ShippingAddress.geo`). 없으면 그리지 않는다.
/// - 출발지(MFC)는 고객이 받을 길이 계약에 없어 그리지 않는다(사용자 2026-11-19 "빼고 요청도 안 함").
/// - 지나온 길은 서버가 주지 않아 그리지 않는다.
///
/// 카카오 지도는 실서버·키가 있을 때만([mapAvailableProvider]). 목·시험·키 없음이면 지도 대신 안내 칸.
class TrackingMap extends ConsumerStatefulWidget {
  const TrackingMap({super.key, required this.rider, this.home});

  final GeoPoint rider;
  final GeoPoint? home;

  @override
  ConsumerState<TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends ConsumerState<TrackingMap> {
  kakao.KakaoMapController? _map;
  kakao.Poi? _riderPoi;

  static kakao.LatLng _ll(GeoPoint p) => kakao.LatLng(p.lat, p.lng);

  Future<void> _onReady(kakao.KakaoMapController map) async {
    _map = map;
    final scheme = Theme.of(context).colorScheme;
    final riderIcon = await kakao.KImage.fromWidget(
      _RiderMarker(color: scheme.primary),
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
    if (widget.home case final h?) {
      await map.labelLayer.addPoi(
        _ll(h),
        style: kakao.PoiStyle(
          icon: homeIcon,
          anchor: const kakao.KPoint(0.5, 0.5),
        ),
      );
    }
    _riderPoi = await map.labelLayer.addPoi(
      _ll(widget.rider),
      style: kakao.PoiStyle(
        icon: riderIcon,
        anchor: const kakao.KPoint(0.5, 0.5),
      ),
      rank: 1,
    );
    await _fit();
  }

  /// 라이더와 배송지가 함께 보이게 맞춘다(배송지가 없으면 라이더 가운데).
  Future<void> _fit() async {
    final map = _map;
    if (map == null) return;
    final home = widget.home;
    await map.moveCamera(
      home == null
          ? kakao.CameraUpdate.newCenterPosition(
              _ll(widget.rider),
              zoomLevel: 16,
            )
          : kakao.CameraUpdate.fitMapPoints([
              _ll(widget.rider),
              _ll(home),
            ], padding: 80),
    );
  }

  @override
  void didUpdateWidget(TrackingMap old) {
    super.didUpdateWidget(old);
    if (old.rider != widget.rider) {
      _riderPoi?.move(_ll(widget.rider), 800);
      _fit();
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
      option: kakao.KakaoMapOption(position: _ll(widget.rider), zoomLevel: 16),
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
