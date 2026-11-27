import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 화면을 내리면 위 주소 막대·아래 탭 막대를 접고, 조금이라도 올리면 다시 편다(사용자 2026-11-26 —
/// 레퍼런스 앱처럼). 탭 화면 안 세로 스크롤만 본다(가로 목록은 무시).
class TabChromeHidden extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool hidden) {
    if (state != hidden) state = hidden;
  }
}

final tabChromeHiddenProvider = NotifierProvider<TabChromeHidden, bool>(
  TabChromeHidden.new,
);

/// 세로 스크롤이 움직인 방향으로 [tabChromeHiddenProvider] 를 바꾼다(내리면 접고 올리면 편다).
/// 맨 위 근처(48 안)면 늘 편다. 아주 작은 떨림(2 미만)은 무시한다.
bool handleTabChromeScroll(WidgetRef ref, ScrollUpdateNotification n) {
  if (n.metrics.axis != Axis.vertical) return false;
  final delta = n.scrollDelta ?? 0;
  final notifier = ref.read(tabChromeHiddenProvider.notifier);
  if (n.metrics.extentBefore < 48) {
    notifier.set(false);
  } else if (delta > 2) {
    notifier.set(true);
  } else if (delta < -2) {
    notifier.set(false);
  }
  return false;
}

/// [hidden] 이면 높이를 0 으로 접는다(위에서 아래로 접히는 막대는 [alignment] 로 방향을 정한다).
class CollapseOnScroll extends StatelessWidget {
  const CollapseOnScroll({
    super.key,
    required this.hidden,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final bool hidden;
  final Widget child;
  final Alignment alignment;

  static const duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedAlign(
      duration: duration,
      curve: Curves.easeOut,
      alignment: alignment,
      heightFactor: hidden ? 0 : 1,
      child: child,
    ),
  );
}
