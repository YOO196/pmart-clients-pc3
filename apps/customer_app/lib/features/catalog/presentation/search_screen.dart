import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart' show IdempotencyKey, PmartFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'product_list_view.dart';

/// SCR-SEARCH-001. 자동완성은 실패해도 직접 검색이 된다.
///
/// 검색어 칸이 비어 있으면 회원에게 최근 검색어(`/me/recent-searches`)를 보인다. 기록은 서버가 검색할 때 남긴다.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _suggestSeq = 0;
  List<String> _suggestions = const [];
  String? _submitted;

  /// "원래 검색어로 다시 찾기" — 서버 오타 교정을 끈다(search 0.4.0 noCorrection).
  bool _noCorrection = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final keyword = text.trim();
    if (keyword.isEmpty) {
      // 칸을 비우면 결과 대신 최근 검색어로 돌아간다(방금 검색한 것이 서버에 남았을 수 있어 다시 읽는다).
      if (_submitted != null) ref.invalidate(recentSearchesProvider);
      setState(() {
        _suggestions = const [];
        _submitted = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final seq = ++_suggestSeq;
      List<String> found;
      try {
        found = await ref.read(catalogRepositoryProvider).suggestions(keyword);
      } on Exception {
        found = const [];
      }
      // 늦게 온 이전 입력의 제안은 버린다.
      if (!mounted || seq != _suggestSeq) return;
      setState(() => _suggestions = found);
    });
  }

  void _submit(String text, {bool noCorrection = false}) {
    final keyword = text.trim();
    if (keyword.isEmpty) return;
    _noCorrection = noCorrection;
    _debounce?.cancel();
    _suggestSeq++;
    _controller.text = keyword;
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = const [];
      _submitted = keyword;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final submitted = _submitted;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 14,
        title: SizedBox(
          height: 40,
          child: TextField(
            key: const ValueKey('search-field'),
            controller: _controller,
            textInputAction: TextInputAction.search,
            maxLength: 100,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontSize: 14),
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              counterText: '',
              // 레퍼런스 3-4: 칸 안 오른쪽 회색 ⓧ 로 지우기
              suffixIcon: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _controller.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: const ValueKey('search-clear'),
                        tooltip: l10n.searchClear,
                        icon: const PmartLineIcon(
                          PmartLineIcons.clearCircle,
                          size: 20,
                        ),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 40,
                minHeight: 40,
              ),
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainer,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _onChanged,
            onSubmitted: _submit,
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('search-submit'),
            tooltip: l10n.searchSubmit,
            icon: const PmartLineIcon(PmartLineIcons.search, size: 23),
            onPressed: () => _submit(_controller.text),
          ),
          const CartIconButton(),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          if (submitted != null)
            ProductListView(
              baseQuery: ProductQuery(
                keyword: submitted,
                noCorrection: _noCorrection,
              ),
              onKeyword: _submit,
            )
          else
            _RecentSearches(onPick: _submit),
          if (_suggestions.isNotEmpty)
            Material(
              elevation: 4,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in _suggestions)
                    ListTile(
                      leading: const PmartLineIcon(PmartLineIcons.search),
                      title: Text(s),
                      onTap: () => _submit(s),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 최근 검색어. 비회원·서버 설정 없음은 숨기고, 조회 실패는 "없음"이 아니라 실패로 보인다.
/// 지우기는 서버가 받은 뒤 다시 읽어 보인다(먼저 지운 척하지 않는다).
class _RecentSearches extends ConsumerStatefulWidget {
  const _RecentSearches({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  ConsumerState<_RecentSearches> createState() => _RecentSearchesState();
}

class _RecentSearchesState extends ConsumerState<_RecentSearches> {
  /// 지우는 중인 검색어(전체 삭제는 '' — 버튼 비활성).
  final _busy = <String>{};

  Future<void> _remove(String? keyword) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(recentSearchesRepositoryProvider);
    final key = IdempotencyKey.generate();
    setState(() => _busy.add(keyword ?? ''));
    try {
      if (keyword == null) {
        await repo.clear(key: key);
      } else {
        await repo.delete(keyword, key: key);
      }
      ref.invalidate(recentSearchesProvider);
    } on PmartFailure {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.searchRecentDeleteFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(keyword ?? ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = ref.watch(recentSearchesProvider);
    // 다시 읽는 동안에는 앞 목록을 그대로 둔다(깜빡이지 않게).
    final failed = value.hasError && !value.isLoading;
    final loaded = failed ? null : value.value;
    if (!failed && loaded == null) return const SizedBox.shrink();
    final Widget body;
    if (loaded == null) {
      body = Row(
        key: const ValueKey('recent-error'),
        children: [
          Expanded(child: Text(l10n.searchRecentLoadFailed)),
          TextButton(
            onPressed: () => ref.invalidate(recentSearchesProvider),
            child: Text(l10n.searchRecentRetry),
          ),
        ],
      );
    } else {
      final items = loaded;
      body = items.isEmpty
          ? Text(
              l10n.searchRecentEmpty,
              key: const ValueKey('recent-empty'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in items)
                  InputChip(
                    key: ValueKey('recent-$k'),
                    label: Text(k),
                    onPressed: _busy.contains(k)
                        ? null
                        : () => widget.onPick(k),
                    deleteButtonTooltipMessage: l10n.searchRecentDelete(k),
                    onDeleted: _busy.contains(k) ? null : () => _remove(k),
                  ),
              ],
            );
    }
    final items = loaded;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.searchRecentTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (items != null && items.isNotEmpty)
              TextButton(
                key: const ValueKey('recent-clear'),
                onPressed: _busy.contains('') ? null : () => _remove(null),
                child: Text(l10n.searchRecentClear),
              ),
          ],
        ),
        const SizedBox(height: 8),
        body,
      ],
    );
  }
}
