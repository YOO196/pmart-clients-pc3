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

  // 사용자 폰 캡처(2026-11-25, 1080px = 411dp): 지도 높이 100.
  static const height = 100.0;

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
          // 핀(사용자 레퍼런스 그림 36.5×47.2, 위에서 25.9).
          Positioned(
            top: 25.9,
            left: 0,
            right: 0,
            child: Center(
              child: Image.asset(
                'assets/images/address_pin.png',
                key: const ValueKey('address-map-pin'),
                width: 36.5,
                height: 47.2,
              ),
            ),
          ),
          if (onOpen case final open?)
            // "지도에서 위치 확인": 높이 21, 오른쪽 13·아래 9.5, 글자 12.5 굵게.
            Positioned(
              right: 13,
              bottom: 9.5,
              child: Material(
                color: const Color(0xE6333333),
                shape: const StadiumBorder(),
                child: InkWell(
                  key: const ValueKey('address-map'),
                  customBorder: const StadiumBorder(),
                  onTap: open,
                  child: Container(
                    height: 21,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Text(
                      AppLocalizations.of(context).addressMapCheck,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w700,
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
