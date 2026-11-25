import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

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
/// 지도 가운데는 [rider] → [home]. 둘 다 아직 없으면(주문·주소 변환을 읽는 중) "지도 위치를 확인하고 있어요" 칸.
/// 카카오 지도는 실서버·키가 있을 때만([mapAvailableProvider]). 목·시험·키 없음이면 지도 대신 안내 칸.
class TrackingMap extends ConsumerStatefulWidget {
  const TrackingMap({
    super.key,
    required this.rider,
    this.home,
    this.riderStale = false,
  });

  final GeoPoint? rider;
  final GeoPoint? home;
  final bool riderStale;

  /// 마커가 이전 점에서 새 점으로 움직이는 시간.
  static const glide = Duration(seconds: 1);

  /// 지도 아래를 덮는 시트 높이(화면 비율 — [TrackMapLayout] 의 처음 크기와 같게). 마커는 그 위에 맞춘다.
  static const sheetFraction = 0.45;

  @override
  ConsumerState<TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends ConsumerState<TrackingMap> {
  kakao.KakaoMapController? _map;
  kakao.Poi? _riderPoi;
  kakao.PoiStyle? _riderStyle;
  kakao.PoiStyle? _riderDimStyle;
  kakao.PoiStyle? _homeStyle;
  kakao.Poi? _homePoi;
  bool? _shownStale;

  /// 카메라를 맞춘 적이 있는지·그때 라이더가 있었는지. 처음 한 번 + 라이더가 처음 나타날 때 한 번만 맞춘다 —
  /// 그 뒤 위치가 오가거나(구독 끊김·서버가 잠깐 비움) 움직여도 카메라는 그대로(사용자 2026-11-19 "지도가 다른 위치로 튐").
  bool _fitted = false;
  bool _fittedWithRider = false;

  /// 한 번 그린 지도의 시작 위치. 위치를 잠깐 둘 다 모르게 돼도 지도를 다시 만들지 않는다.
  GeoPoint? _start;

  static kakao.LatLng _ll(GeoPoint p) => kakao.LatLng(p.lat, p.lng);

  Future<void> _onReady(kakao.KakaoMapController map) async {
    // 그림 마커는 미리 읽어 둬야 위젯을 그림으로 바꿀 때 빈칸이 되지 않는다.
    await precacheImage(const AssetImage(RiderMarker.asset), context);
    if (!mounted) return;
    final riderIcon = await kakao.KImage.fromWidget(
      const RiderMarker(),
      RiderMarker.size,
      context: context,
    );
    if (!mounted) return;
    final riderDimIcon = await kakao.KImage.fromWidget(
      const RiderMarker(stale: true),
      RiderMarker.size,
      context: context,
    );
    if (!mounted) return;
    final homeIcon = await kakao.KImage.fromWidget(
      const HomeMarker(),
      HomeMarker.size,
      context: context,
    );
    if (!mounted) return;
    const center = kakao.KPoint(0.5, 0.5);
    _riderStyle = kakao.PoiStyle(icon: riderIcon, anchor: center);
    _riderDimStyle = kakao.PoiStyle(icon: riderDimIcon, anchor: center);
    _homeStyle = kakao.PoiStyle(
      icon: homeIcon,
      anchor: const kakao.KPoint(0.5, 0.5),
    );
    _map = map;
    await _syncHome();
    await _syncRider(animate: false);
    await _fit();
  }

  /// 내 배송지 마커 — 주문·주소 변환이 늦게 와도 그때 그린다.
  Future<void> _syncHome() async {
    final map = _map;
    final style = _homeStyle;
    final home = widget.home;
    if (map == null || style == null || home == null) return;
    final poi = _homePoi;
    if (poi == null) {
      _homePoi = await map.labelLayer.addPoi(_ll(home), style: style);
    } else {
      await poi.move(_ll(home));
    }
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
      _riderPoi = await map.labelLayer.addPoi(
        _ll(rider),
        style: style,
        rank: 1,
      );
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
    final points = [?widget.rider, ?widget.home];
    if (map == null || points.isEmpty) return;
    final withRider = widget.rider != null;
    if (_fitted && (_fittedWithRider || !withRider)) return;
    _fitted = true;
    _fittedWithRider = withRider;
    await map.moveCamera(
      kakao.CameraUpdate.fitMapPoints([
        for (final p in visibleFitPoints(points, TrackingMap.sheetFraction))
          _ll(p),
      ], padding: 60),
    );
  }

  @override
  void didUpdateWidget(TrackingMap old) {
    super.didUpdateWidget(old);
    final moved = old.rider != widget.rider;
    if (moved || old.riderStale != widget.riderStale) {
      _syncRider();
    }
    if (old.home != widget.home) _syncHome();
    // 카메라는 [_fit] 이 정한 때(처음·라이더가 처음 나타날 때)만 — 나머지는 마커만 움직이거나 숨긴다.
    if (old.rider == null && widget.rider != null) _fit();
  }

  @override
  Widget build(BuildContext context) {
    final start = _start ??= widget.rider ?? widget.home;
    if (start == null) {
      // 지도 가운데를 아직 모른다(주문·주소 변환을 읽는 중, 또는 둘 다 없음) — 위치를 지어내지 않는다.
      final theme = Theme.of(context);
      return Container(
        key: const ValueKey('track-map-pending'),
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context).trackMapPending,
          textAlign: TextAlign.center,
        ),
      );
    }
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
      option: kakao.KakaoMapOption(position: _ll(start), zoomLevel: 16),
      onMapReady: _onReady,
    );
  }
}

/// 라이더 마커: 브랜드색 옅은 원(후광) 위 흰 원판 + 그림자, 안에 채운 오토바이. 오래된 위치면 회색·흐리게.
class RiderMarker extends StatelessWidget {
  const RiderMarker({super.key, this.stale = false});

  final bool stale;

  /// 사용자 제작 캐릭터(위에서 본 라이더, 브랜드색) — 레퍼런스 지도 핀 약 58dp(1080px = 411dp 캡처에서 약 150px).
  static const asset = 'assets/images/tracking/rider_pin.png';
  static const size = Size(58, 60);

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(asset, width: size.width, height: size.height);
    if (!stale) return img;
    // 오래된 위치(60초 넘음): 흑백 + 흐리게.
    return Opacity(
      opacity: 0.6,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      ),
    );
  }
}

/// 시트 오른쪽 라이더 캐릭터(사용자 제작, 브랜드색). 레퍼런스 약 72×62dp.
class RiderArt extends StatelessWidget {
  const RiderArt({super.key, this.width = 72});

  final double width;

  static const asset = 'assets/images/tracking/rider_sheet.png';

  @override
  Widget build(BuildContext context) =>
      Image.asset(asset, width: width, height: width * 284 / 329);
}

/// 내 배송지 마커(사용자 레퍼런스 2026-11-25): 진한 동그라미 안에 흰 집, 그림자.
class HomeMarker extends StatelessWidget {
  const HomeMarker({super.key});

  // 레퍼런스 약 30dp(908px 시트 = 411dp 에서 66px).
  static const size = Size(30, 30);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: CustomPaint(painter: _HomePinPainter()),
  );
}

class _HomePinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final circle = Path()
      ..addOval(Rect.fromCircle(center: const Offset(16, 16), radius: 15));
    canvas
      ..drawShadow(circle, Colors.black, 2.5, false)
      ..drawPath(circle, Paint()..color = const Color(0xFF1B1B1F));
    // 흰 집(지붕 + 몸통, 문은 비움)
    const c = Offset(16, 16.5);
    final house = Path()
      ..moveTo(c.dx, c.dy - 7.5)
      ..lineTo(c.dx + 7.5, c.dy - 1)
      ..lineTo(c.dx + 5.4, c.dy - 1)
      ..lineTo(c.dx + 5.4, c.dy + 6.5)
      ..lineTo(c.dx + 1.7, c.dy + 6.5)
      ..lineTo(c.dx + 1.7, c.dy + 2.4)
      ..lineTo(c.dx - 1.7, c.dy + 2.4)
      ..lineTo(c.dx - 1.7, c.dy + 6.5)
      ..lineTo(c.dx - 5.4, c.dy + 6.5)
      ..lineTo(c.dx - 5.4, c.dy - 1)
      ..lineTo(c.dx - 7.5, c.dy - 1)
      ..close();
    canvas.drawPath(house, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_HomePinPainter oldDelegate) => false;
}

/// 한집배달 아이콘(사용자 제공 그림 2026-11-25): 채운 집 안에 "1" 을 뚫은 모양. 34×31 판에 그린다.
class SingleHomeIcon extends StatelessWidget {
  const SingleHomeIcon({super.key, required this.color, this.width = 15});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 31 / 34,
    child: CustomPaint(painter: _SingleHomePainter(color)),
  );
}

class _SingleHomePainter extends CustomPainter {
  const _SingleHomePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..scale(size.width / 34, size.height / 31)
      ..saveLayer(const Rect.fromLTWH(0, 0, 34, 31), Paint());
    final fill = Paint()
      ..color = color
      ..strokeJoin = StrokeJoin.round;
    final house = Path()
      ..moveTo(0.6, 12.6)
      ..lineTo(17, 0.6)
      ..lineTo(33.4, 12.6)
      ..lineTo(33.4, 13.6)
      ..lineTo(29.6, 13.6)
      ..lineTo(29.6, 29.4)
      ..lineTo(4.6, 29.4)
      ..lineTo(4.6, 13.6)
      ..lineTo(0.6, 13.6)
      ..close();
    canvas
      ..drawPath(house, fill)
      // 모서리를 조금 둥글게
      ..drawPath(
        house,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round,
      );
    // "1" 뚫기: 세로 획(아래까지) + 왼쪽 위 깃.
    final one = Path()
      ..moveTo(15.2, 10.8)
      ..lineTo(19.6, 10.8)
      ..lineTo(19.6, 31)
      ..lineTo(15.2, 31)
      ..lineTo(15.2, 17)
      ..lineTo(14, 17)
      ..lineTo(10.8, 17)
      ..lineTo(10.8, 14.6)
      ..close();
    canvas
      ..drawPath(one, Paint()..blendMode = BlendMode.clear)
      ..restore();
  }

  @override
  bool shouldRepaint(_SingleHomePainter old) => old.color != color;
}

/// 아래 시트에 가려지지 않게 맞출 점들. 실제 점들의 남북 폭 아래로 [sheetFraction] 만큼 빈 점을 하나 더해,
/// 화면 전체에 맞춰도 실제 점들은 시트 위(1 - sheetFraction) 영역에 들어오게 한다(사용자 2026-11-19 "두 마커가 가려지지 않게").
/// 점이 하나거나 아주 가까우면 약 300m 폭으로 넓혀 너무 확대되지 않게 한다. 좌표를 지어내는 게 아니라 카메라 범위만 정한다.
List<GeoPoint> visibleFitPoints(List<GeoPoint> points, double sheetFraction) {
  const minSpan = 0.003;
  var minLat = points.first.lat, maxLat = points.first.lat;
  var minLng = points.first.lng, maxLng = points.first.lng;
  for (final p in points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
    if (p.lng > maxLng) maxLng = p.lng;
  }
  if (maxLat - minLat < minSpan) {
    final mid = (maxLat + minLat) / 2;
    minLat = mid - minSpan / 2;
    maxLat = mid + minSpan / 2;
  }
  if (maxLng - minLng < minSpan) {
    final mid = (maxLng + minLng) / 2;
    minLng = mid - minSpan / 2;
    maxLng = mid + minSpan / 2;
  }
  final span = maxLat - minLat;
  final visible = 1 - sheetFraction;
  return [
    (lat: maxLat, lng: minLng),
    (lat: maxLat, lng: maxLng),
    (lat: minLat, lng: minLng),
    (lat: minLat, lng: maxLng),
    // 시트가 덮는 만큼 아래로 늘린 빈 점.
    (
      lat: minLat - span * (sheetFraction / visible),
      lng: (minLng + maxLng) / 2,
    ),
  ];
}
