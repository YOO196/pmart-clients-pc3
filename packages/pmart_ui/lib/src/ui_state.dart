import 'package:flutter/foundation.dart';
import 'package:pmart_core/pmart_core.dart';

/// 모든 비동기 화면의 상태 7종 (client-architecture §5.4, Commerce D.6).
///
/// - [UiEmpty] 는 "정상 조회 결과 0건"일 때만 쓴다. 조회 실패는 [UiError] 다.
/// - [UiResultUnknown] 은 변경 요청의 결과를 아직 모르는 상태다. 실패로 그리지 않는다.
@immutable
sealed class UiState<T> {
  const UiState();

  /// [PmartFailure] 를 화면 상태로 바꾼다.
  factory UiState.fromFailure(PmartFailure failure) => switch (failure) {
    UnknownResultFailure() => UiResultUnknown<T>(requestId: failure.requestId),
    ProblemFailure(:final problem) when problem.code == ProblemCode.forbidden =>
      UiForbidden<T>(reason: problem.code, requestId: failure.requestId),
    _ => UiError<T>(failure),
  };
}

final class UiLoading<T> extends UiState<T> {
  const UiLoading();
}

final class UiReady<T> extends UiState<T> {
  const UiReady(this.data);

  final T data;
}

/// 정상 조회 0건. 조회 실패를 이 상태로 바꾸지 않는다.
final class UiEmpty<T> extends UiState<T> {
  const UiEmpty();
}

/// 일부 영역만 받은 상태. [missing] 은 못 받은 영역 이름(화면이 정한다).
final class UiPartial<T> extends UiState<T> {
  const UiPartial(this.data, {required this.missing});

  final T data;
  final Set<String> missing;
}

final class UiError<T> extends UiState<T> {
  const UiError(this.failure);

  final PmartFailure failure;
}

final class UiForbidden<T> extends UiState<T> {
  const UiForbidden({this.reason, this.requestId});

  /// 서버 사유 코드(FORBIDDEN, NO_ROLE, OUT_OF_CENTER_SCOPE …). 표시 문구는 화면이 정한다.
  final String? reason;
  final String? requestId;
}

/// 변경 요청 결과 불명. 짝 조회로 해소될 때까지 같은 행위를 막는다.
final class UiResultUnknown<T> extends UiState<T> {
  const UiResultUnknown({this.requestId});

  final String? requestId;
}
