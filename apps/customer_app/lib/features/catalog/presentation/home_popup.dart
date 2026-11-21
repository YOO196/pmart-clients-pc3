import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart' show toSeoulWallClock;

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';

/// 홈 팝업(storefront 0.9.0 배너 자리 POPUP — 백엔드 요청서 2026-11-21 ②). 서버는 기록하지 않고 앱이 bannerId 로 기억한다.
/// 사용자 결정(2026-11-21): 가운데 카드(A). "오늘 그만 보기" = 오늘(서울 날짜) 동안 안 보임,
/// "닫기" = 이번 실행 동안 안 보임(다음에 앱을 켜면 다시).
const _hiddenTodayKey = 'pmart.home.popup.hiddenToday';

/// "오늘 그만 보기"를 누른 배너(오늘 서울 날짜일 때만 유효).
final class PopupHiddenStore {
  PopupHiddenStore(this._store);

  final SecureKeyValueStore _store;

  Future<Set<String>> hiddenOn(String day) async {
    final raw = await _store.read(_hiddenTodayKey);
    if (raw == null) return const {};
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      if (j['day'] != day) return const {};
      return {...(j['ids'] as List<Object?>).whereType<String>()};
    } on Object {
      return const {};
    }
  }

  Future<void> hide(String day, Iterable<String> ids) async {
    final kept = await hiddenOn(day);
    await _store.write(
      _hiddenTodayKey,
      jsonEncode({
        'day': day,
        'ids': [...kept, ...ids],
      }),
    );
  }
}

final popupHiddenStoreProvider = Provider<PopupHiddenStore>(
  (ref) => PopupHiddenStore(ref.watch(secureStoreProvider)),
);

/// 팝업 기억 단위 = 배너 + 이미지(백엔드 요청 2026-11-21 R2). 같은 배너라도 이미지가 바뀌면(이미지 주소의 imageId)
/// "오늘 그만 보기"·"닫기" 기록과 상관없이 다시 보인다.
String popupSeenKey(HomeBanner b) => '${b.bannerId}|${b.imageUrl ?? ''}';

/// 서울 날짜(yyyy-MM-dd).
String seoulDay(DateTime now) {
  final s = toSeoulWallClock(now);
  return '${s.year.toString().padLeft(4, '0')}-'
      '${s.month.toString().padLeft(2, '0')}-'
      '${s.day.toString().padLeft(2, '0')}';
}

/// 이번 실행 동안의 팝업 상태: 이미 띄웠는지, [닫기]로 닫은 배너.
final popupSessionProvider = NotifierProvider<PopupSession, PopupSessionState>(
  PopupSession.new,
);

typedef PopupSessionState = ({bool shown, Set<String> closed});

class PopupSession extends Notifier<PopupSessionState> {
  @override
  PopupSessionState build() => (shown: false, closed: const {});

  void markShown() => state = (shown: true, closed: state.closed);

  void close(Iterable<String> ids) =>
      state = (shown: state.shown, closed: {...state.closed, ...ids});
}

/// 지금 띄울 팝업 배너(서버 순서). 오늘 그만 보기·이번 실행에 닫은 것은 뺀다.
/// 조회 실패는 팝업을 띄우지 않는다(팝업은 덧붙인 안내라 홈을 막지 않는다).
final homePopupProvider = FutureProvider.autoDispose<List<HomeBanner>>((
  ref,
) async {
  final repo = ref.watch(catalogRepositoryProvider);
  final List<HomeBanner> all;
  try {
    all = await repo.banners(placement: 'POPUP');
  } on PmartFailure {
    return const [];
  }
  if (all.isEmpty) return const [];
  final day = seoulDay(ref.read(homeClockProvider)());
  final hidden = await ref.read(popupHiddenStoreProvider).hiddenOn(day);
  final closed = ref.read(popupSessionProvider).closed;
  return [
    for (final b in all)
      if (!hidden.contains(popupSeenKey(b)) &&
          !closed.contains(popupSeenKey(b)))
        b,
  ];
});

/// 팝업을 띄운다. 이미지를 누르면 닫고 [onOpen](배너가 가리키는 영역·상품·카테고리).
Future<void> showHomePopup(
  BuildContext context,
  WidgetRef ref,
  List<HomeBanner> banners, {
  required void Function(HomeBanner) onOpen,
}) async {
  ref.read(popupSessionProvider.notifier).markShown();
  final ids = [for (final b in banners) popupSeenKey(b)];
  final result = await showDialog<_PopupResult>(
    context: context,
    builder: (_) => HomePopupDialog(banners: banners),
  );
  // 바깥을 눌러 닫거나 뒤로 가기도 [닫기]와 같다.
  ref.read(popupSessionProvider.notifier).close(ids);
  switch (result) {
    case _HideToday():
      final day = seoulDay(ref.read(homeClockProvider)());
      await ref.read(popupHiddenStoreProvider).hide(day, ids);
    case _Open(:final banner):
      onOpen(banner);
    case _Close() || null:
      break;
  }
}

sealed class _PopupResult {
  const _PopupResult();
}

final class _HideToday extends _PopupResult {
  const _HideToday();
}

final class _Close extends _PopupResult {
  const _Close();
}

final class _Open extends _PopupResult {
  const _Open(this.banner);
  final HomeBanner banner;
}

/// 가운데 카드(사용자 결정 2026-11-21 A): 아래 [오늘 그만 보기 | 닫기], 여럿이면 옆으로 넘김·"1 / N".
/// 크기(백엔드 요청 2026-11-21 R2): 창 폭 = 화면 폭의 80%, 그림 칸 4:5 고정, 그림은 칸 안에 다 보이게(contain).
class HomePopupDialog extends ConsumerStatefulWidget {
  const HomePopupDialog({super.key, required this.banners});

  final List<HomeBanner> banners;

  @override
  ConsumerState<HomePopupDialog> createState() => _HomePopupDialogState();
}

class _HomePopupDialogState extends ConsumerState<HomePopupDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final origin = ref.watch(imageOriginProvider);
    final banners = widget.banners;
    final text = theme.textTheme.bodyLarge?.copyWith(fontSize: 15);
    return Dialog(
      key: const ValueKey('home-popup'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width * 0.1,
      ),
      clipBehavior: Clip.antiAlias,
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  key: const ValueKey('home-popup-pages'),
                  itemCount: banners.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final b = banners[i];
                    final url = resolveImageUrl(b.imageUrl, origin);
                    final canOpen =
                        b.link != BannerLink.none &&
                        (b.linkRef?.isNotEmpty ?? false);
                    final fallback = ColoredBox(
                      color: scheme.primaryContainer,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            b.altText ?? '',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ),
                    );
                    return Semantics(
                      button: canOpen,
                      label: b.altText,
                      child: GestureDetector(
                        key: ValueKey('home-popup-image-${b.bannerId}'),
                        onTap: canOpen
                            ? () => Navigator.of(context).pop(_Open(b))
                            : null,
                        child: url == null
                            ? fallback
                            : Image.network(
                                url,
                                fit: BoxFit.contain,
                                cacheWidth:
                                    (MediaQuery.sizeOf(context).width *
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ))
                                        .round(),
                                errorBuilder: (_, _, _) => fallback,
                              ),
                      ),
                    );
                  },
                ),
                if (banners.length > 1)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_index + 1} / ${banners.length}',
                        key: const ValueKey('home-popup-count'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const ValueKey('home-popup-hide-today'),
                    onTap: () => Navigator.of(context).pop(const _HideToday()),
                    child: Center(
                      child: Text(l10n.popupHideToday, style: text),
                    ),
                  ),
                ),
                Container(width: 1, height: 16, color: scheme.outlineVariant),
                Expanded(
                  child: InkWell(
                    key: const ValueKey('home-popup-close'),
                    onTap: () => Navigator.of(context).pop(const _Close()),
                    child: Center(
                      child: Text(
                        l10n.popupClose,
                        style: text?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
