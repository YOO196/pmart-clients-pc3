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
        SupportRow(
          key: const ValueKey('support-faqs'),
          label: l10n.faqTitle,
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
        const Divider(),
      ],
    );
  }
}

class _FaqSearchField extends StatefulWidget {
  const _FaqSearchField({super.key, required this.onSubmitted, this.initial});

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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.onSurface),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.onSurface),
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
        _ => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _FaqSearchField(
                initial: _q,
                onSubmitted: (q) => setState(() => _q = q.isEmpty ? null : q),
              ),
            ),
            if (all != null)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    for (final c in <FaqCategory?>[null, ...all.categories])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: ValueKey('faq-cat-${c?.category ?? 'all'}'),
                          label: Text(c?.title ?? l10n.ordersFilterAll),
                          selected: _category == c?.category,
                          onSelected: (_) =>
                              setState(() => _category = c?.category),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: UiStateView<FaqList?>(
                state: uiStateOf(value, isEmpty: (l) => l!.items.isEmpty),
                onRetry: () => ref.invalidate(provider),
                empty: (_) => Center(
                  key: const ValueKey('faq-empty'),
                  child: Text(l10n.faqEmpty),
                ),
                ready: (context, list) => ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: list!.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final f = list.items[i];
                    return InkWell(
                      key: ValueKey('faq-${f.faqId}'),
                      onTap: () =>
                          context.push('/support/faqs/${f.faqId}', extra: f),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.categoryTitle,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    f.question,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            ),
                            PmartLineIcon(
                              PmartLineIcons.chevronRight,
                              size: 18,
                              color: theme.colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
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
        MarkdownBody(
          key: const ValueKey('faq-answer'),
          data: f.answer,
          // 링크는 열지 않는다(앱 밖으로 나가지 않게). 원문 그대로 보인다.
          styleSheet: MarkdownStyleSheet.fromTheme(theme)
              .copyWith(p: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
        ),
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
