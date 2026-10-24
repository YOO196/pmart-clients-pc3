import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'product_list_view.dart';

/// SCR-SEARCH-001. 자동완성은 실패해도 직접 검색이 된다.
///
/// 최근 검색어(`/me/recent-searches`)는 로그인 단계에서 붙인다.
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
      setState(() => _suggestions = const []);
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

  void _submit(String text) {
    final keyword = text.trim();
    if (keyword.isEmpty) return;
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
        title: TextField(
          key: const ValueKey('search-field'),
          controller: _controller,
          textInputAction: TextInputAction.search,
          maxLength: 100,
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            counterText: '',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _submit,
        ),
        actions: [
          IconButton(
            key: const ValueKey('search-submit'),
            tooltip: l10n.searchSubmit,
            icon: const Icon(Icons.search),
            onPressed: () => _submit(_controller.text),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (submitted != null)
            ProductListView(baseQuery: ProductQuery(keyword: submitted)),
          if (_suggestions.isNotEmpty)
            Material(
              elevation: 4,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in _suggestions)
                    ListTile(
                      leading: const Icon(Icons.search),
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
