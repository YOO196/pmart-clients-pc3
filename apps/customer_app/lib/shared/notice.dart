import 'package:flutter/material.dart';

/// 화면 아래 잠깐 뜨는 알림(스낵바) — 앱의 모든 알림은 여기로 띄운다(사용자 2026-11-20 "팝업창이 버튼을 가리는데 늦게 사라져").
///
/// - 짧게: 글만 있으면 [noticeDuration], 버튼이 있으면 누를 틈을 주어 [noticeWithActionDuration].
/// - 버튼이 달려도 스스로 닫힌다(Flutter 기본은 `persist` 라 안 닫힌다).
/// - 앞 알림을 기다리지 않는다 — 밀린 알림을 지우고 바로 바꾼다.
/// - 본문 아래에 붙은 버튼·떠 있는 막대([NoticeClearance])가 보이면 그 위로 띄운다.
///   (`Scaffold.bottomNavigationBar` 에 둔 버튼은 스낵바가 원래 그 위에 뜬다.)
const noticeDuration = Duration(seconds: 2);
const noticeWithActionDuration = Duration(seconds: 4);

/// 알림과 그 아래 것(화면 끝·버튼·막대) 사이.
const _gap = 12.0;

extension NoticeMessenger on ScaffoldMessengerState {
  void notice(
    String text, {
    Key? key,
    SnackBarAction? action,
    Duration? duration,
  }) {
    this
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          key: key,
          behavior: SnackBarBehavior.floating,
          persist: false,
          duration:
              duration ??
              (action == null ? noticeDuration : noticeWithActionDuration),
          margin: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            _gap + _NoticeClearanceState.lift(),
          ),
          // 버튼이 조금 길어도 글 옆에 둔다(기본은 폭의 1/4 을 넘으면 아랫줄로 내려 알림이 두 배로 커진다).
          actionOverflowThreshold: 0.5,
          content: Text(text),
          action: action,
        ),
      );
  }
}

/// [context] 에서 가장 가까운 메신저로 알림을 띄운다. 기다린 뒤 띄울 때는 메신저를 먼저 잡아 두고
/// [NoticeMessenger.notice] 를 쓴다.
void showNotice(
  BuildContext context,
  String text, {
  Key? key,
  SnackBarAction? action,
  Duration? duration,
}) =>
    ScaffoldMessenger.of(context)
        .notice(text, key: key, action: action, duration: duration);

/// 본문 아래에 붙어 있는 버튼·떠 있는 막대를 감싼다 — 보이는 동안 알림이 이 위로 뜬다.
///
/// 탭 화면은 알림을 탭 바깥 Scaffold 가 그려서, 화면 본문 안 아래 버튼을 모르고 그 위에 덮는다.
class NoticeClearance extends StatefulWidget {
  const NoticeClearance({super.key, required this.child});

  final Widget child;

  @override
  State<NoticeClearance> createState() => _NoticeClearanceState();
}

class _NoticeClearanceState extends State<NoticeClearance> {
  static final _mounted = <_NoticeClearanceState>{};

  /// 지금 보이는 것 가운데 가장 높은 것의 높이(+ 화면 끝과의 틈). 없으면 0.
  static double lift() {
    var lift = 0.0;
    for (final s in _mounted) {
      final h = s._visibleHeight();
      if (h > lift) lift = h;
    }
    return lift;
  }

  double _visibleHeight() {
    if (!mounted) return 0;
    // 다른 탭(가려진 가지)·다른 화면 아래에 깔린 것은 뺀다.
    if (!TickerMode.valuesOf(context).enabled) return 0;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return 0;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.height <= 0) return 0;
    // 막대가 화면 끝에서 조금 떠 있는 만큼(약 10)을 더한다.
    return box.size.height + 10;
  }

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void dispose() {
    _mounted.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
