import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers.dart';

/// 상세설명(롱이미지 조각)·상세정보 표 이미지. 화면 폭에 맞추고 높이는 원본 비율을 따른다.
/// 조각을 위아래로 붙여 한 장처럼 보이게 하려고 간격·모서리를 두지 않는다.
class ContentImage extends ConsumerWidget {
  const ContentImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 받지 못한 조각은 빈칸 대신 작은 자리표시로 보인다(설명이 끊긴 것을 알 수 있게).
    final placeholder = Container(
      height: 96,
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image_outlined),
    );
    // 서버 이미지는 게이트웨이 상대 경로다(ProductImage 와 같은 방식으로 출처를 붙인다).
    final u = resolveImageUrl(url, ref.watch(imageOriginProvider));
    if (u == null) return placeholder;
    return Image.network(
      u,
      width: double.infinity,
      fit: BoxFit.fitWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
