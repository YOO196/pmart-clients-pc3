import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 네트워크 없이 응답을 돌려주는 dio 어댑터. 받은 요청을 순서대로 기록한다.
final class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this._handler);

  final Future<FakeReply> Function(RequestOptions options, int index) _handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = requests.length;
    requests.add(options);
    final reply = await _handler(options, index);
    if (reply.throwType != null) {
      throw DioException(requestOptions: options, type: reply.throwType!);
    }
    return ResponseBody.fromString(
      reply.body == null ? '' : jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [reply.contentType],
        for (final e in reply.headers.entries) e.key: [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class FakeReply {
  const FakeReply(
    this.status, {
    this.body,
    this.contentType = 'application/json',
    this.headers = const {},
  }) : throwType = null;

  const FakeReply.problem(
    this.status,
    Map<String, Object?> problem, {
    this.headers = const {},
  }) : body = problem,
       contentType = 'application/problem+json',
       throwType = null;

  const FakeReply.transport(DioExceptionType type)
    : status = 0,
      body = null,
      contentType = '',
      headers = const {},
      throwType = type;

  final int status;
  final Object? body;
  final String contentType;
  final Map<String, String> headers;
  final DioExceptionType? throwType;
}

Map<String, Object?> problemBody(
  String code, {
  int status = 409,
  bool retryable = false,
}) => {
  'type': 'about:blank',
  'title': 't',
  'status': status,
  'code': code,
  'traceId': 'trace-1',
  'retryable': retryable,
};

Map<String, Object?> commandBody(String status, {String requestId = 'k-1'}) => {
  'status': status,
  'requestId': requestId,
};
