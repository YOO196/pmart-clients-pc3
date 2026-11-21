import 'package:flutter/material.dart';

/// 불러오는 중 자리 표시(스켈레톤). 안의 회색 칸([PmartBone]) 위로 밝은 띠가 천천히 지나간다.
/// 화면 하나에 하나만 둔다(애니메이션 하나 — 칸마다 따로 돌리지 않는다).
/// 기기에서 애니메이션 줄이기를 켰으면 멈춘 회색으로 둔다.
class PmartShimmer extends StatefulWidget {
  const PmartShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<PmartShimmer> createState() => _PmartShimmerState();
}

class _PmartShimmerState extends State<PmartShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHigh;
    final shine = Color.lerp(base, scheme.surface, 0.7)!;
    return Semantics(
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: AnimatedBuilder(
        animation: _c,
        child: ExcludeSemantics(child: widget.child),
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final x = -1.5 + 3 * _c.value;
            return LinearGradient(
              begin: Alignment(x - 0.6, -0.3),
              end: Alignment(x + 0.6, 0.3),
              colors: [base, shine, base],
              stops: const [0.2, 0.5, 0.8],
            ).createShader(rect);
          },
          child: child,
        ),
      ),
    );
  }
}

/// 자리 표시 회색 칸 하나. [PmartShimmer] 안에 둔다.
class PmartBone extends StatelessWidget {
  const PmartBone({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}

/// 상품 2칸 격자 자리 표시(검색 결과·카테고리 목록·영역 전체 보기): 정사각 그림 + 이름 2줄 + 가격.
class PmartGridSkeleton extends StatelessWidget {
  const PmartGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) => PmartShimmer(
    child: LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 16 * 2 - 12) / 2;
        Widget tile() => SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PmartBone(width: w, height: w, radius: 10),
              const SizedBox(height: 10),
              PmartBone(width: w * 0.9, height: 14),
              const SizedBox(height: 6),
              PmartBone(width: w * 0.6, height: 14),
              const SizedBox(height: 8),
              PmartBone(width: w * 0.45, height: 18),
            ],
          ),
        );
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 20,
            children: [for (var i = 0; i < count; i++) tile()],
          ),
        );
      },
    ),
  );
}

/// 목록 자리 표시(주문·리뷰·알림·문의·장바구니 등): 줄마다 [thumb] 그림 칸 + 글 2~3줄.
class PmartListSkeleton extends StatelessWidget {
  const PmartListSkeleton({
    super.key,
    this.rows = 6,
    this.thumb = false,
    this.thumbSize = 64,
    this.shrinkWrap = false,
  });

  final int rows;
  final bool thumb;
  final double thumbSize;

  /// 높이가 정해지지 않은 곳(스크롤 안쪽 등)에 넣을 때 — 줄 수만큼만 차지한다.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => PmartShimmer(
    child: ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: 22),
      itemBuilder: (context, i) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thumb) ...[
            PmartBone(width: thumbSize, height: thumbSize, radius: 8),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PmartBone(width: c.maxWidth * 0.55, height: 16),
                  const SizedBox(height: 8),
                  PmartBone(
                    width: c.maxWidth * (i.isEven ? 0.9 : 0.75),
                    height: 13,
                  ),
                  const SizedBox(height: 6),
                  PmartBone(width: c.maxWidth * 0.4, height: 13),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 상세 화면 자리 표시(상품 상세·주문 상세): 위 큰 그림(또는 머리 상자) + 글 줄들.
class PmartDetailSkeleton extends StatelessWidget {
  const PmartDetailSkeleton({super.key, this.image = true});

  /// true 면 위에 정사각 그림(상품 상세), false 면 낮은 머리 상자(주문 상세).
  final bool image;

  @override
  Widget build(BuildContext context) => PmartShimmer(
    child: LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image)
              PmartBone(width: c.maxWidth, height: c.maxWidth, radius: 0)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: PmartBone(
                  width: c.maxWidth - 32,
                  height: 96,
                  radius: 12,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PmartBone(width: c.maxWidth * 0.3, height: 13),
                  const SizedBox(height: 10),
                  PmartBone(width: c.maxWidth * 0.8, height: 20),
                  const SizedBox(height: 8),
                  PmartBone(width: c.maxWidth * 0.5, height: 20),
                  const SizedBox(height: 16),
                  PmartBone(width: c.maxWidth * 0.35, height: 24),
                  const SizedBox(height: 28),
                  for (var i = 0; i < 4; i++) ...[
                    PmartBone(width: c.maxWidth - 32, height: 14),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
