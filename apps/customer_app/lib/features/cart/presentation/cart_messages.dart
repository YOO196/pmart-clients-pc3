import '../../../l10n/gen/app_localizations.dart';
import '../domain/cart.dart';
import 'cart_controller.dart';

/// 거절 사유 문구. 수량·상한은 서버가 준 값만 쓴다.
String cartRejectionText(AppLocalizations l10n, CartChangeRejected r) =>
    switch (r.code) {
      CartProblemCode.quantityLimitExceeded => [
        switch (r.limit?.limitUnits) {
          final int limit => l10n.cartRejectLimit(limit),
          null => l10n.cartRejectLimitUnknown,
        },
        if (r.limit?.suggestedQuantity case final int q when q > 0)
          l10n.cartRejectLimitSuggest(q),
      ].join('\n'),
      CartProblemCode.insufficientAvailableQuantity => switch (r.availableQty) {
        final int n when n > 0 => l10n.cartRejectAvailable(n),
        _ => l10n.cartRejectAvailableUnknown,
      },
      CartProblemCode.skuNotSaleable => l10n.cartRejectNotSaleable,
      'CONFIG_REQUIRED' => l10n.cartRejectConfig,
      _ => l10n.cartRejectOther,
    };

String cartNoticeText(AppLocalizations l10n, CartNotice notice) =>
    switch (notice) {
      NoticeRejected(:final rejection) => cartRejectionText(l10n, rejection),
      NoticeReloadedAfterConflict() => l10n.cartNoticeConflict,
      NoticeNotApplied() => l10n.cartNoticeNotApplied,
      NoticeReloadFailed() => l10n.cartNoticeReloadFailed,
      NoticeSoldOutDeselected(:final count) => l10n.cartNoticeSoldOutDeselected(
        count,
      ),
    };

/// 다른 화면에서 담은 결과 한 줄(상품 카드 `+` 등). 서버가 확정한 결과만 "담았어요"로 보인다.
String cartOutcomeText(AppLocalizations l10n, CartChangeOutcome outcome) =>
    switch (outcome) {
      CartChangeApplied() => l10n.cartAdded,
      CartChangeRejected() => cartRejectionText(l10n, outcome),
      CartVersionConflict() => l10n.cartNoticeConflict,
      CartChangeUnknown() => l10n.cartChangeUnknown,
      CartChangeNotApplied() => l10n.cartNoticeNotApplied,
    };
