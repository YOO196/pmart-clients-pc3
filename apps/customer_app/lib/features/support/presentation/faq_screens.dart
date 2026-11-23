import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartEnv;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/faq_repository.dart';
import '../data/mock_faq_repository.dart';
import '../domain/faq.dart';
import 'inquiry_screens.dart' show SupportRow;

final faqRepositoryProvider = Provider<FaqRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockFaqRepository(),
    PmartEnv.local => ApiFaqRepository(ref.watch(dioProvider)),
  },
);

/// FAQ 목록. 회원 고객만(서버가 비회원 403) — 비회원이면 null(빈 목록과 구분). 실패는 실패로 남는다.
final faqListProvider = FutureProvider.autoDispose.family<FaqList?, FaqQuery>((
  ref,
  query,
) async {
  if (ref.watch(sessionProvider) is! MemberSession) return null;
  return ref
      .watch(faqRepositoryProvider)
      .list(q: query.q, category: query.category);
});

final faqProvider = FutureProvider.autoDispose.family<Faq, String>(
  (ref, faqId) => ref.watch(faqRepositoryProvider).get(faqId),
);

/// 고객센터 메인의 FAQ 구역(레퍼런스 고객센터 메인): 검색칸 · "자주 묻는 질문 >" · 분류 칩.
/// 비회원은 FAQ 를 볼 수 없어(서버 403) 구역을 두지 않는다.
class SupportFaqBlock extends ConsumerWidget {
  const SupportFaqBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (ref.watch(sessionProvider) is! MemberSession) {
      return const SizedBox.shrink();
    }
    final value = ref.watch(faqListProvider(const FaqQuery()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FaqSearchField(
          key: const ValueKey('support-faq-search'),
          onSubmitted: (q) => context.push(
            Uri(
              path: '/support/faqs',
              queryParameters: {if (q.isNotEmpty) 'q': q},
            ).toString(),
          ),
        ),
        const SizedBox(height: 8),
        // 레퍼런스: "자주 묻는 질문" 굵게
        SupportRow(
          key: const ValueKey('support-faqs'),
          label: l10n.faqTitle,
          bold: true,
          onTap: () => context.push('/support/faqs'),
        ),
        switch (value) {
          AsyncData(value: final FaqList list) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in list.categories)
                ActionChip(
                  key: ValueKey('support-faq-cat-${c.category}'),
                  label: Text(c.title),
                  // 레퍼런스: 회색 채운 알약 + 얇은 회색 테두리
                  backgroundColor: theme.colorScheme.surfaceContainer,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  labelStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  // 줄 사이를 좁게(사용자 2026-11-21 "세로 간격 조금 좁히기") — 칩마다 붙던 48 터치 여백을 뺀다.
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: const StadiumBorder(),
                  onPressed: () => context.push(
                    Uri(
                      path: '/support/faqs',
                      queryParameters: {'category': c.category},
                    ).toString(),
                  ),
                ),
            ],
          ),
          // 분류를 못 받았으면 칩 자리를 비워 두지 않고 알린다(빈 FAQ 로 보이지 않는다).
          AsyncError() => Row(
            key: const ValueKey('support-faq-failed'),
            children: [
              Expanded(
                child: Text(
                  l10n.faqLoadFailed,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(faqListProvider(const FaqQuery())),
                child: Text(l10n.faqRetry),
              ),
            ],
          ),
          _ => const SizedBox(height: 40),
        },
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FaqSearchField extends StatefulWidget {
  const _FaqSearchField({
    super.key,
    required this.onSubmitted,
    this.initial,
    this.filled = false,
  });

  /// 회색 채움·테두리 없음(사용자 캡처 "자주 묻는 질문" 목록). 아니면 검은 테두리(고객센터 메인).
  final bool filled;

  final ValueChanged<String> onSubmitted;
  final String? initial;

  @override
  State<_FaqSearchField> createState() => _FaqSearchFieldState();
}

class _FaqSearchFieldState extends State<_FaqSearchField> {
  late final _ctl = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      key: const ValueKey('faq-search-field'),
      controller: _ctl,
      textInputAction: TextInputAction.search,
      maxLength: 100,
      decoration: InputDecoration(
        hintText: l10n.faqSearchHint,
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        filled: widget.filled,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: widget.filled
              ? BorderSide.none
              : BorderSide(color: scheme.onSurface),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: widget.filled
              ? BorderSide.none
              : BorderSide(color: scheme.onSurface),
        ),
        suffixIcon: IconButton(
          key: const ValueKey('faq-search-go'),
          icon: const PmartLineIcon(PmartLineIcons.search, size: 22),
          tooltip: l10n.faqSearchHint,
          onPressed: () => widget.onSubmitted(_ctl.text.trim()),
        ),
      ),
      onSubmitted: (v) => widget.onSubmitted(v.trim()),
    );
  }
}

/// 자주 묻는 질문 목록 — 검색어·분류로 서버에 묻는다(앱에서 거르지 않는다).
class FaqListScreen extends ConsumerStatefulWidget {
  const FaqListScreen({super.key, this.q, this.category});

  final String? q;
  final String? category;

  @override
  ConsumerState<FaqListScreen> createState() => _FaqListScreenState();
}

class _FaqListScreenState extends ConsumerState<FaqListScreen> {
  late String? _q = widget.q;
  late String? _category = widget.category;

  /// 펼친 질문(레퍼런스 고객센터 3 — 목록 안에서 답을 펼친다, 사용자 2026-11-23).
  final Set<String> _open = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = faqListProvider(FaqQuery(q: _q, category: _category));
    final value = ref.watch(provider);
    // 분류 칩은 조건 없는 목록의 categories 로 그린다(검색 결과에 따라 칩이 바뀌지 않게).
    final all = ref.watch(faqListProvider(const FaqQuery())).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.faqTitle)),
      body: switch (value) {
        AsyncData(value: null) => LoginRequired(message: l10n.faqLoginNeeded),
        // 검색칸·질문 유형·질문 목록이 한 화면으로 같이 내려간다(사용자 2026-11-20: 질문 유형을 누르면 아래 목록이
        // 좁은 칸에 갇혀 안 보였다 — 알약이 여러 줄이면 고정된 위쪽이 화면을 다 차지했다).
        _ => CustomScrollView(
          key: const ValueKey('faq-scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _FaqSearchField(
                      filled: true,
                      initial: _q,
                      onSubmitted: (q) =>
                          setState(() => _q = q.isEmpty ? null : q),
                    ),
                  ),
                  // 레퍼런스 고객센터 메인 "자주 묻는 질문" 알약 모양 + 고른 것은 검게(사용자 2026-11-21), 4줄 넘으면 [더보기].
                  const SizedBox(height: 14),
                  const PmartSectionGap(height: 8),
                  if (all != null)
                    FaqTypeChips(
                      categories: all.categories,
                      selected: _category,
                      onSelected: (c) => setState(() => _category = c),
                    ),
                  const PmartSectionGap(height: 8),
                ],
              ),
            ),
            if (value case AsyncData(value: final FaqList list)
                when list.items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.only(top: 4, bottom: 24),
                sliver: SliverList.separated(
                  itemCount: list.items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) {
                    final f = list.items[i];
                    final open = _open.contains(f.faqId);
                    // 레퍼런스 고객센터 3: 누르면 그 자리에서 답이 펼쳐진다 — 회색 바탕, 질문 굵게, ⌃.
                    return Container(
                      color: open ? theme.colorScheme.surfaceContainer : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            key: ValueKey('faq-${f.faqId}'),
                            onTap: () => setState(
                              () => open
                                  ? _open.remove(f.faqId)
                                  : _open.add(f.faqId),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    // 사용자 캡처: "[분류] 질문" 한 줄 제목
                                    child: Text(
                                      '[${f.categoryTitle}] ${f.question}',
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontSize: 16,
                                            fontWeight: open
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PmartLineIcon(
                                    open
                                        ? PmartLineIcons.chevronUp
                                        : PmartLineIcons.chevronDown,
                                    size: 20,
                                    color: open
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.outline,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (open)
                            Padding(
                              key: ValueKey('faq-open-${f.faqId}'),
                              padding: const EdgeInsets.fromLTRB(26, 0, 20, 24),
                              child: FaqAnswer(answer: f.answer),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              )
            else
              // 불러오는 중·없음·실패는 남은 자리에(조회 실패를 빈 목록으로 보이지 않는다).
              SliverFillRemaining(
                child: UiStateView<FaqList?>(
                  loading: (_) => const PmartListSkeleton(),
                  state: uiStateOf(value, isEmpty: (l) => l!.items.isEmpty),
                  onRetry: () => ref.invalidate(provider),
                  empty: (_) => Center(
                    key: const ValueKey('faq-empty'),
                    child: Text(l10n.faqEmpty),
                  ),
                  ready: (_, _) => const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      },
    );
  }
}

/// FAQ 하나 — 답은 마크다운으로 그린다. 목록에서 넘겨 받으면 다시 묻지 않는다.
class FaqDetailScreen extends ConsumerWidget {
  const FaqDetailScreen({super.key, required this.faqId, this.initial});

  final String faqId;
  final Faq? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget body(Faq f) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          f.categoryTitle,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          f.question,
          key: const ValueKey('faq-question'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        FaqAnswer(key: const ValueKey('faq-answer'), answer: f.answer),
      ],
    );
    final first = initial;
    if (first != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.faqTitle)),
        body: body(first),
      );
    }
    final value = ref.watch(faqProvider(faqId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.faqTitle)),
      body: UiStateView<Faq>(
        state: uiStateOf(value),
        onRetry: () => ref.invalidate(faqProvider(faqId)),
        ready: (context, f) => body(f),
      ),
    );
  }
}

/// 자주 묻는 질문 "질문 유형"(사용자 2026-11-21): 굵은 구역 제목 + 레퍼런스 알약(회색 채움·얇은 테두리, 14 보통,
/// 높이 약 33dp, 사이 10·줄 사이 10 — 레퍼런스 15 에서 좁힘, 사용자 2026-11-21). 고른 것은 검정 바탕·흰 글자. 4줄을 넘으면 4줄까지만 + [더보기 ⌄]
/// (펼치면 [접기 ⌃]). 4줄 밖의 유형을 고른 채로 열리면 펼쳐 보인다.
class FaqTypeChips extends StatefulWidget {
  const FaqTypeChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<FaqCategory> categories;

  /// 고른 분류(null = 전체).
  final String? selected;
  final ValueChanged<String?> onSelected;

  static const maxLines = 4;

  @override
  State<FaqTypeChips> createState() => _FaqTypeChipsState();
}

class _FaqTypeChipsState extends State<FaqTypeChips> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodyMedium?.copyWith(fontSize: 14);
    final entries = <(String?, String)>[
      (null, l10n.ordersFilterAll),
      for (final c in widget.categories) (c.category, c.title),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.faqTypeLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final fit = chipsFitInLines(
                [for (final e in entries) e.$2],
                c.maxWidth,
                style,
                lines: FaqTypeChips.maxLines,
              );
              final selectedAt = entries.indexWhere(
                (e) => e.$1 == widget.selected,
              );
              final more = fit < entries.length;
              final open = _expanded || selectedAt >= fit;
              final shown = open ? entries.length : fit;
              return Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      // 줄 사이 15 → 10(사용자 2026-11-21 "세로 간격 조금 좁히기").
                      runSpacing: 10,
                      children: [
                        for (final (value, label) in entries.take(shown))
                          _chip(theme, scheme, style, value, label),
                      ],
                    ),
                  ),
                  if (more)
                    TextButton(
                      key: const ValueKey('faq-types-more'),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant,
                        textStyle: style,
                      ),
                      onPressed: () => setState(() => _expanded = !open),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(open ? l10n.faqTypesLess : l10n.faqTypesMore),
                          const SizedBox(width: 2),
                          PmartLineIcon(
                            open
                                ? PmartLineIcons.chevronUp
                                : PmartLineIcons.chevronDown,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(
    ThemeData theme,
    ColorScheme scheme,
    TextStyle? style,
    String? value,
    String label,
  ) {
    final on = widget.selected == value;
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        key: ValueKey('faq-cat-${value ?? 'all'}'),
        borderRadius: BorderRadius.circular(17),
        onTap: () => widget.onSelected(value),
        child: Container(
          height: 33,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: on ? scheme.onSurface : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: on ? scheme.onSurface : scheme.outlineVariant,
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: style?.copyWith(
                color: on ? scheme.surface : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [labels] 알약(글자 폭 + 안쪽 여백 28 + 테두리 2, 사이 10)을 [maxWidth] 폭 Wrap 에 놓을 때 [lines] 줄 안에 드는 개수.
int chipsFitInLines(
  List<String> labels,
  double maxWidth,
  TextStyle? style, {
  required int lines,
}) {
  var line = 1;
  var x = 0.0;
  for (final (i, label) in labels.indexed) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 28 + 2;
    tp.dispose();
    final next = x == 0 ? w : x + 10 + w;
    if (next > maxWidth && x > 0) {
      line++;
      if (line > lines) return i;
      x = w;
    } else {
      x = next;
    }
  }
  return labels.length;
}

/// FAQ 답(마크다운). 답 안 링크는 **앱 안 화면**(예 "주문내역 바로가기" → `/orders`, 레퍼런스 고객센터 3)만
/// 연다 — 앱 밖 주소·모르는 경로는 열지 않는다(앱 밖으로 나가지 않게).
class FaqAnswer extends StatelessWidget {
  const FaqAnswer({super.key, required this.answer});

  final String answer;

  /// 열어도 되는 앱 안 경로의 앞부분.
  static const inAppPrefixes = [
    '/orders',
    '/claims',
    '/support',
    '/me',
    '/addresses',
    '/notifications',
    '/categories',
    '/search',
    '/cart',
  ];

  static bool opens(String? href) =>
      href != null &&
      !href.startsWith('//') &&
      inAppPrefixes.any(
        (p) => href == p || href.startsWith('$p/') || href.startsWith('$p?'),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: answer,
      onTapLink: (_, href, _) {
        if (opens(href)) context.push(href!);
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
