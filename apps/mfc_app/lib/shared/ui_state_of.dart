import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

/// Riverpod [AsyncValue] → [UiState].
///
/// [isEmpty] 는 정상 조회 0건 판정이다. 오류는 절대 EMPTY 로 바꾸지 않는다.
UiState<T> uiStateOf<T>(AsyncValue<T> value, {bool Function(T)? isEmpty}) =>
    switch (value) {
      AsyncData(:final value) =>
        (isEmpty?.call(value) ?? false) ? UiEmpty<T>() : UiReady<T>(value),
      AsyncError(:final error) => UiState<T>.fromFailure(
        error is PmartFailure ? error : ContractViolationFailure(error),
      ),
      _ => UiLoading<T>(),
    };
