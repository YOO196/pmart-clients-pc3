import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart' as kakao;

import '../../../l10n/gen/app_localizations.dart';
import 'map_pick_screen.dart' show GeoPoint, mapAvailableProvider;

/// 주소 상세 위 지도 미리보기(레퍼런스 2-7-1: 330×94dp, 가운데 핀, 오른쪽 아래 "지도에서 위치 확인").
/// 미리보기는 보기만 한다(끌어서 맞추는 것은 [onOpen] 의 큰 지도 화면). [point] 가 없으면 빈 칸에 핀만.
/// 카카오 지도는 실서버·키가 있을 때만([mapAvailableProvider]) — 목·시험은 회색 칸.
class AddressMapPreview extends ConsumerWidget {
  const AddressMapPreview({super.key, required this.point, this.onOpen});

  final GeoPoint? point;

  /// 큰 지도 화면을 연다. null 이면 버튼을 숨긴다(위치를 못 찾았을 때).
  final VoidCallback? onOpen;

  static const height = 94.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = point;
    final live = p != null && ref.watch(mapAvailableProvider);
    return SizedBox(
      key: const ValueKey('address-map-preview'),
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (live)
            IgnorePointer(
              child: kakao.KakaoMap(
                // 위치가 바뀌면 새로 그린다(미리보기는 카메라를 옮기지 않는다).
                key: ValueKey('preview-${p.lat}-${p.lng}'),
                option: kakao.KakaoMapOption(
                  position: kakao.LatLng(p.lat, p.lng),
                  zoomLevel: 17,
                ),
                onMapReady: (_) {},
              ),
            )
          else
            ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
          const Center(
            child: Padding(
              // 핀 끝이 가운데에 오게 핀 높이만큼 올린다.
              padding: EdgeInsets.only(bottom: 34),
              child: SizedBox(width: 34, height: 40, child: _Pin()),
            ),
          ),
          if (onOpen case final open?)
            Positioned(
              right: 12,
              bottom: 9,
              child: Material(
                color: const Color(0xE6333333),
                shape: const StadiumBorder(),
                child: InkWell(
                  key: const ValueKey('address-map'),
                  customBorder: const StadiumBorder(),
                  onTap: open,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    child: Text(
                      AppLocalizations.of(context).addressMapCheck,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 진한 물방울 핀(레퍼런스 핀 모양 — 그림은 직접 그린다).
class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PinPainter());
}

class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w / 2;
    final body = Path()
      ..moveTo(w / 2, h)
      ..quadraticBezierTo(w * 0.12, h * 0.62, 0, r)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..quadraticBezierTo(w * 0.88, h * 0.62, w / 2, h)
      ..close();
    canvas
      ..drawShadow(body, Colors.black, 2, false)
      ..drawPath(body, Paint()..color = const Color(0xFF3A3A3C))
      ..drawCircle(
        Offset(w / 2, r),
        r * 0.42,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
  }

  @override
  bool shouldRepaint(_PinPainter oldDelegate) => false;
}
