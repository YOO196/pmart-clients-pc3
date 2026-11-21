import 'package:flutter/material.dart';


import 'package:pmart_core/pmart_core.dart';

import '../l10n/gen/pmart_ui_localizations.dart';
import 'skeleton.dart';
import 'ui_state.dart';

/// 고객 앱이 상태 화면을 레퍼런스 모양으로 그리게 하는 테마 값(라이더·MFC 앱은 없음 → 지금 모양 그대로).
/// 레퍼런스(2026-11-20 비교, 5-2 네트워크 오류·로딩 아이콘): 불러오는 중은 작은 원형만, 오류는 아이콘 없이
/// "화면을 불러오지 못했어요" + 테두리 알약 "다시 시도하기".
@immutable
class PmartStateStyle extends ThemeExtension<PmartStateStyle> {
  const PmartStateStyle({this.reference = false});

  final bool reference;

  static bool of(BuildContext context) =>
      Theme.of(context).extension<PmartStateStyle>()?.reference ?? false;

  @override
  PmartStateStyle copyWith({bool? reference}) =>
      PmartStateStyle(reference: reference ?? this.reference);

  @override
  PmartStateStyle lerp(PmartStateStyle? other, double t) => other ?? this;
}

/// [UiState] 7종을 서로 다른 모습으로 그린다.
///
/// READY·PARTIAL 의 본문은 [ready] 가 그린다. PARTIAL 이면 위에 안내 띠를 붙인다.
class UiStateView<T> extends StatelessWidget {
  const UiStateView({
    super.key,
    required this.state,
    required this.ready,
    this.onRetry,
    this.onCheckAgain,
    this.empty,
    this.loading,
  });

  /// LOADING 화면을 그 화면 모양의 자리 표시로 바꾸고 싶을 때(예 [PmartGridSkeleton]).
  final WidgetBuilder? loading;

  final UiState<T> state;
  final Widget Function(BuildContext context, T data) ready;

  /// ERROR·PARTIAL 의 "다시 시도".
  final VoidCallback? onRetry;

  /// RESULT_UNKNOWN 의 "다시 확인"(짝 조회). 원래 요청을 다시 보내는 버튼이 아니다.
  final VoidCallback? onCheckAgain;

  /// EMPTY 화면을 바꾸고 싶을 때.
  final WidgetBuilder? empty;

  @override
  Widget build(BuildContext context) {
    final l10n = PmartUiLocalizations.of(context);
    final reference = PmartStateStyle.of(context);
    final theme = Theme.of(context);
    return switch (state) {
      UiLoading() when loading != null => KeyedSubtree(
        key: const ValueKey('ui-loading'),
        child: loading!(context),
      ),
      // 사용자 2026-11-21 "로딩 모양이 별로" — 가운데 동그라미 대신 목록 모양 자리 표시(홈처럼 회색 뼈대가 반짝임).
      // 높이가 정해진 곳은 화면을 채우고, 스크롤 안쪽처럼 정해지지 않은 곳은 세 줄만.
      UiLoading() when reference => Semantics(
        key: const ValueKey('ui-loading'),
        label: l10n.stateLoading,
        child: LayoutBuilder(
          builder: (context, c) => c.hasBoundedHeight
              ? const PmartListSkeleton()
              : const PmartListSkeleton(rows: 3, shrinkWrap: true),
        ),
      ),
      UiError(:final failure) when reference => _Centered(
        key: const ValueKey('ui-error'),
        children: [
          Text(
            failure is SessionExpiredFailure
                ? l10n.stateSessionExpired
                : _isConfigRequired(failure)
                ? l10n.stateConfigRequired
                : l10n.stateScreenLoadFailed,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 16),
          ),
          _RequestId(failure.requestId),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                minimumSize: const Size(104, 36),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                foregroundColor: theme.colorScheme.onSurface,
                textStyle: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
              ),
              child: Text(l10n.actionRetryScreen),
            ),
          ],
        ],
      ),
      UiLoading() => _Centered(
        key: const ValueKey('ui-loading'),
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l10n.stateLoading),
        ],
      ),
      UiReady(:final data) => ready(context, data),
      UiEmpty() =>
        empty?.call(context) ??
            _Centered(
              key: const ValueKey('ui-empty'),
              children: [
                const Icon(Icons.inbox_outlined, size: 48),
                const SizedBox(height: 12),
                Text(l10n.stateEmpty),
              ],
            ),
      UiPartial(:final data) => Column(
        key: const ValueKey('ui-partial'),
        children: [
          MaterialBanner(
            content: Text(l10n.statePartial),
            leading: const Icon(Icons.warning_amber_rounded),
            actions: [
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: Text(l10n.actionRetry))
              else
                const SizedBox.shrink(),
            ],
          ),
          Expanded(child: ready(context, data)),
        ],
      ),
      UiError(:final failure) => _Centered(
        key: const ValueKey('ui-error'),
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            failure is SessionExpiredFailure
                ? l10n.stateSessionExpired
                : _isConfigRequired(failure)
                ? l10n.stateConfigRequired
                : l10n.stateErrorTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.stateErrorBody, textAlign: TextAlign.center),
          _RequestId(failure.requestId),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
          ],
        ],
      ),
      UiForbidden(:final requestId) => _Centered(
        key: const ValueKey('ui-forbidden'),
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.stateForbiddenTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.stateForbiddenBody, textAlign: TextAlign.center),
          _RequestId(requestId),
        ],
      ),
      UiResultUnknown(:final requestId) => _Centered(
        key: const ValueKey('ui-result-unknown'),
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 48),
          const SizedBox(height: 12),
          Text(
            l10n.stateUnknownTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.stateUnknownBody, textAlign: TextAlign.center),
          _RequestId(requestId),
          if (onCheckAgain != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onCheckAgain,
              child: Text(l10n.actionCheckAgain),
            ),
          ],
        ],
      ),
    };
  }

  static bool _isConfigRequired(PmartFailure f) =>
      f is ProblemFailure && f.problem.code == ProblemCode.configRequired;
}

class _Centered extends StatelessWidget {
  const _Centered({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class _RequestId extends StatelessWidget {
  const _RequestId(this.requestId);

  final String? requestId;

  @override
  Widget build(BuildContext context) {
    final id = requestId;
    if (id == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SelectableText(
        PmartUiLocalizations.of(context).requestIdLabel(id),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
