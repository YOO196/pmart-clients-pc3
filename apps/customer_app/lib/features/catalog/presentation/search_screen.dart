import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;
import '../../orders/domain/orders.dart' show FrequentItem;
import '../../orders/presentation/orders_providers.dart'
    show ordersRepositoryProvider;
import 'widgets/product_tile_card.dart' show ProductImage;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart' show IdempotencyKey, PmartFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'widgets/product_tile_card.dart' show ProductTileCard, TileLook;
import 'product_list_view.dart';
import '../../../shared/notice.dart';

/// SCR-SEARCH-001. 자동완성은 실패해도 직접 검색이 된다.
///
/// 검색어 칸이 비어 있으면 회원에게 최근 검색어(`/me/recent-searches`)를, 모두에게 인기 검색어를 보인다. 기록은 서버가 검색할 때 남긴다.
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
    if (keyword.isEmpty) {
      // 레퍼런스: 빈 검색은 "검색어를 입력해주세요" 알림만(검색하지 않는다).
      showNotice(
        context,
        AppLocalizations.of(context).searchEnterKeyword,
        key: const ValueKey('search-empty-toast'),
      );
      return;
    }
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
      messenger.notice(l10n.searchRecentDeleteFailed);
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
    // 비회원·서버 설정 없음은 최근 검색어 구역을 숨긴다(인기 검색어는 그대로).
    final showRecent = failed || loaded != null;
    final Widget body;
    if (!showRecent) {
      body = const SizedBox.shrink();
    } else if (loaded == null) {
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
              runSpacing: 6,
              children: [
                for (final k in items)
                  InputChip(
                    key: ValueKey('recent-$k'),
                    // 줄 사이를 좁힌다(사용자 2026-11-22) — 48dp 터치 여백을 빼고 칩 높이도 줄인다.
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
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
        if (showRecent) ...[
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
                  // 레퍼런스: 오른쪽 회색 작은 글씨
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    textStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                    ),
                  ),
                  child: Text(l10n.searchRecentClear),
                ),
            ],
          ),
          const SizedBox(height: 8),
          body,
        ],
        // 자주 산 상품(order 0.24.0, 백엔드 요청 2026-11-26 F1) — 회원·있을 때만, 실패도 숨김.
        _FrequentItems(spaceAbove: showRecent),
        _PopularKeywords(onPick: widget.onPick, spaceAbove: showRecent),
        // 지금 잘 팔리는 상품(사용자 레퍼런스 2026-11-26).
        const _SellingNow(),
      ],
    );
  }
}

/// 자주 산 상품(검색어를 넣기 전) — 180일 안 2번 이상 산 상품. 칩을 누르면 그 상품 상세.
/// 상품 ID·이름이 없는 줄은 뺀다(SKU 를 화면에 보이지 않는다). 비회원·빈 목록·조회 실패는 영역을 숨긴다.
final frequentItemsProvider = FutureProvider.autoDispose<List<FrequentItem>>((
  ref,
) async {
  if (ref.watch(sessionProvider) is! MemberSession) return const [];
  return ref.watch(ordersRepositoryProvider).frequentItems();
});

class _FrequentItems extends ConsumerWidget {
  const _FrequentItems({required this.spaceAbove});

  final bool spaceAbove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = (ref.watch(frequentItemsProvider).value ?? const [])
        .where((f) => f.productId != null && f.productName != null)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('frequent-items'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spaceAbove) const SizedBox(height: 28),
        Text(
          l10n.searchFrequentTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final f in items)
              ActionChip(
                key: ValueKey('frequent-${f.sku}'),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                avatar: f.imageUrl == null
                    ? null
                    : ProductImage(url: f.imageUrl, size: 22, radius: 11),
                label: Text(f.displayName!),
                onPressed: () => context.push('/products/${f.productId}'),
              ),
          ],
        ),
      ],
    );
  }
}

/// 인기 검색어(search 0.5.2 — 검색 첫 화면, 비회원도). 레퍼런스(사용자 2026-11-26): 굵은 제목 아래 회색 둥근 상자에
/// 순위 하나씩 3초마다 위로 바뀌어 보이고 오른쪽 [펼쳐서 보기 ⌄] — 펼치면 서버 순서대로 두 줄 목록, [접기 ⌃].
/// 집계가 없으면(빈 목록) 구역을 숨긴다. 못 읽어도 숨긴다 — 자동완성처럼 없어도 검색은 되는 보조 칸이라
/// 실패 안내를 띄우지 않는다("인기 검색어가 없다"고 말하지도 않는다). 순위 변동 화살표는 계약에 없다(BR-110).
class _PopularKeywords extends ConsumerStatefulWidget {
  const _PopularKeywords({required this.onPick, required this.spaceAbove});

  final ValueChanged<String> onPick;
  final bool spaceAbove;

  @override
  ConsumerState<_PopularKeywords> createState() => _PopularKeywordsState();
}

class _PopularKeywordsState extends ConsumerState<_PopularKeywords> {
  bool _open = false;
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      final n = ref.read(popularKeywordsProvider).value?.length ?? 0;
      if (!_open && n > 1 && mounted) setState(() => _index = (_index + 1) % n);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = ref.watch(popularKeywordsProvider).value;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final current = _index % items.length;
    Widget entry(int i, {bool dense = false}) => InkWell(
      key: ValueKey('popular-${i + 1}'),
      onTap: () => widget.onPick(items[i]),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 0 : 10),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${i + 1}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child: Text(
                items[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
    // 왼쪽 줄 1…n, 오른쪽 줄 n+1… (세로로 읽는 순위)
    final half = (items.length + 1) ~/ 2;
    Widget column(int from, int to) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (var i = from; i < to; i++) entry(i)],
    );
    final toggle = InkWell(
      key: ValueKey(_open ? 'popular-collapse' : 'popular-expand'),
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _open ? l10n.searchPopularCollapse : l10n.searchPopularExpand,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 2),
            Transform.flip(
              flipY: _open,
              child: PmartLineIcon(
                PmartLineIcons.chevronDown,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      key: const ValueKey('popular-keywords'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.spaceAbove) const SizedBox(height: 28),
        Text(
          l10n.searchPopularTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: column(0, half)),
                        const SizedBox(width: 16),
                        Expanded(child: column(half, items.length)),
                      ],
                    ),
                    Align(alignment: Alignment.centerRight, child: toggle),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: ClipRect(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, a) => SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                          child: KeyedSubtree(
                            key: ValueKey('popular-now-$current'),
                            child: entry(current, dense: true),
                          ),
                        ),
                      ),
                    ),
                    toggle,
                  ],
                ),
        ),
      ],
    );
  }
}

/// 검색 첫 화면 "지금 잘 팔리는 상품"(레퍼런스 "이 가게에서 지금 잘 팔리는 상품") — 지금 주소 센터 인기순 앞 10개
/// 가로 줄(search `sort=POPULAR`). 비었거나 못 읽으면 구역을 숨긴다(검색은 그대로 된다).
class _SellingNow extends ConsumerWidget {
  const _SellingNow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = ref
        .watch(productListProvider(const ProductQuery(sort: SortKey.popular)))
        .value
        ?.items
        .take(10)
        .toList();
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final width = ProductTileCard.railWidthOf(context) * 1.25;
    return Column(
      key: const ValueKey('search-selling'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 36),
        Text(
          l10n.searchSellingTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: width + 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox(
              width: width,
              child: ProductTileCard(
                key: ValueKey('search-selling-${items[i].productId}'),
                rail: true,
                look: TileLook.grid3,
                tile: items[i],
                onTap: () => context.push(
                  '/products/${items[i].productId}',
                  extra: items[i],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
