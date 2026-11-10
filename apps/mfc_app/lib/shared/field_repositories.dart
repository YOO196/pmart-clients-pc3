import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../features/quality/data/mock_quality_repository.dart';
import '../features/quality/data/quality_repository.dart';
import '../features/stock_count/data/mock_stock_count_repository.dart';
import '../features/stock_count/data/stock_count_repository.dart';
import '../features/stock_move/data/mock_stock_move_repository.dart';
import '../features/stock_move/data/stock_move_repository.dart';
import 'providers.dart';

/// 품질검사·재고 이동·재고 실사 업무의 연결(2026-11-10 — 화면은 아직, 연결 계층만).
/// `PMART_ENV=mock` 이면 목, `local` 이면 계약 API.

final qualityRepositoryProvider = Provider<QualityRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockQualityRepository(
      returns: switch (ref.watch(stockMoveRepositoryProvider)) {
        final MockStockMoveRepository m => m,
        _ => null,
      },
    ),
    PmartEnv.local => ApiQualityRepository(ref.watch(dioProvider)),
  },
);

final stockMoveRepositoryProvider = Provider<StockMoveRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockStockMoveRepository(),
    PmartEnv.local => ApiStockMoveRepository(ref.watch(dioProvider)),
  },
);

final stockCountRepositoryProvider = Provider<StockCountRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockStockCountRepository(),
    PmartEnv.local => ApiStockCountRepository(ref.watch(dioProvider)),
  },
);
