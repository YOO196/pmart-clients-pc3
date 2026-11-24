import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// 서버 사진을 기기 디스크에도 저장해 두는지. 앱(`main.dart`)이 켠다 — 위젯 시험은 끈 채로(디스크 캐시는
/// sqflite·path_provider 플러그인이 필요해 시험 환경에서 돌지 않는다) 기본 [NetworkImage] 를 쓴다.
///
/// 서버 이미지는 이미지 ID 마다 내용이 바뀌지 않고 `Cache-Control: public, max-age=31536000, immutable`
/// 이다(content-images·banner-images·review-photos — 백엔드 로딩 계획 회신 2026-11-25). 그래서 한 번 받은 사진은
/// 앱을 다시 켜도 다시 받지 않는다(로딩 구조 문서 S3).
bool pmartImageDiskCache = false;

/// [Image.network] 대신 쓴다 — 인자는 같고, [pmartImageDiskCache] 가 켜져 있으면 디스크 캐시를 거친다.
/// [cacheWidth]·[cacheHeight] 는 [Image.network] 처럼 그 크기로만 디코드한다(메모리).
Image pmartNetworkImage(
  String src, {
  Key? key,
  double? width,
  double? height,
  BoxFit? fit,
  Alignment alignment = Alignment.center,
  int? cacheWidth,
  int? cacheHeight,
  String? semanticLabel,
  bool excludeFromSemantics = false,
  ImageErrorWidgetBuilder? errorBuilder,
  ImageLoadingBuilder? loadingBuilder,
  ImageFrameBuilder? frameBuilder,
  bool gaplessPlayback = false,
  FilterQuality filterQuality = FilterQuality.medium,
  Color? color,
  BlendMode? colorBlendMode,
}) {
  final ImageProvider base = pmartImageDiskCache
      ? CachedNetworkImageProvider(src)
      : NetworkImage(src);
  return Image(
    key: key,
    image: ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, base),
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    semanticLabel: semanticLabel,
    excludeFromSemantics: excludeFromSemantics,
    errorBuilder: errorBuilder,
    loadingBuilder: loadingBuilder,
    frameBuilder: frameBuilder,
    gaplessPlayback: gaplessPlayback,
    filterQuality: filterQuality,
    color: color,
    colorBlendMode: colorBlendMode,
  );
}
