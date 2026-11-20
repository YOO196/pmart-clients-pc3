import 'package:flutter/material.dart';

/// 왼쪽 정렬 제목 머리줄의 값(레퍼런스 주소·환경설정·문의하기 화면 — ← 옆 약 43dp 에서 제목 시작).
/// `AppBar(centerTitle: false, titleSpacing: pmartLeftTitleSpacing, …)`
const pmartLeftTitleSpacing = 0.0;

/// 레퍼런스 확인 창(2026-11-20 비교): 흰 상자(모서리 10), 제목 16sp, 회색 본문 14sp,
/// 오른쪽 아래 채운 사각 확인 단추 + 그 왼쪽 회색 글자 취소. 확인만 있는 안내 창은 [cancelLabel] 을 비운다.
/// 확인 = true, 취소·바깥 누름 = false/null.
Future<bool?> showPmartConfirm(
  BuildContext context, {
  String? title,
  String? body,
  Widget? content,
  required String confirmLabel,
  String? cancelLabel,
  Key? confirmKey,
  Key? cancelKey,
  bool barrierDismissible = true,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (context) => PmartConfirmDialog(
    title: title,
    body: body,
    content: content,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    confirmKey: confirmKey,
    cancelKey: cancelKey,
  ),
);

class PmartConfirmDialog extends StatelessWidget {
  const PmartConfirmDialog({
    super.key,
    this.title,
    this.body,
    this.content,
    required this.confirmLabel,
    this.cancelLabel,
    this.confirmKey,
    this.cancelKey,
  });

  final String? title;
  final String? body;
  final Widget? content;
  final String confirmLabel;
  final String? cancelLabel;
  final Key? confirmKey;
  final Key? cancelKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title case final t?)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  t,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (body case final b?) ...[
              if (title != null) const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  b,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (content case final c?) ...[
              if (title != null || body != null) const SizedBox(height: 10),
              c,
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (cancelLabel case final c?)
                  TextButton(
                    key: cancelKey,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      minimumSize: const Size(64, 40),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(c),
                  ),
                const SizedBox(width: 6),
                FilledButton(
                  key: confirmKey,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    textStyle: theme.textTheme.labelLarge,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 라우트를 가운데 창으로 띄우는 페이지(레퍼런스: 주문 취소 "주문을 취소할까요?"). go_router `pageBuilder` 에서 쓴다.
class PmartDialogPage<T> extends Page<T> {
  const PmartDialogPage({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) =>
      DialogRoute<T>(context: context, settings: this, builder: (_) => child);
}

/// 라우트를 아래 시트로 띄우는 페이지(레퍼런스: 예약시간 변경 시트).
class PmartSheetPage<T> extends Page<T> {
  const PmartSheetPage({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
    settings: this,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => child,
  );
}
