import 'package:dio/dio.dart';
import 'package:pmart_api_search/pmart_api_search.dart' as sr;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;

/// 본인 최근 검색어(search 0.2.0 `/me/recent-searches`, 고객 토큰만).
/// 기록은 서버가 검색할 때 알아서 남긴다(앱이 따로 보내지 않는다). 실패는 [PmartFailure] 로 던진다.
abstract interface class RecentSearchesRepository {
  /// 최신순 검색어. 서버 설정이 없으면 422 CONFIG_REQUIRED.
  Future<List<String>> list();

  /// 하나 지우기(없어도 성공). 같은 키 재전송은 같은 결과.
  Future<void> delete(String keyword, {required IdempotencyKey key});

  /// 모두 지우기(없어도 성공).
  Future<void> clear({required IdempotencyKey key});
}

final class ApiRecentSearchesRepository implements RecentSearchesRepository {
  ApiRecentSearchesRepository(Dio dio)
    : _api = sr.PmartApiSearch(dio: dio).getRecentSearchesApi();

  final sr.RecentSearchesApi _api;

  @override
  Future<List<String>> list() async {
    final res = await pmartGuard(() => _api.listRecentSearches());
    final items =
        res.data?.items ??
        (throw const ContractViolationFailure('RecentSearches 본문 없음'));
    return [
      for (final i in items)
        if (i.keyword?.trim() case final k? when k.isNotEmpty) k,
    ];
  }

  @override
  Future<void> delete(String keyword, {required IdempotencyKey key}) async {
    await pmartGuard(
      () => _api.deleteRecentSearch(
        keyword: keyword,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        extra: commandOptions(key).extra,
      ),
    );
  }

  @override
  Future<void> clear({required IdempotencyKey key}) async {
    await pmartGuard(
      () => _api.clearRecentSearches(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        extra: commandOptions(key).extra,
      ),
    );
  }
}

/// 목 구현. 서버처럼 같은 검색어는 하나만, 최신순.
final class MockRecentSearchesRepository implements RecentSearchesRepository {
  MockRecentSearchesRepository({
    this.latency = const Duration(milliseconds: 300),
    List<String> seeded = const ['우유', '감귤', '감자칩'],
  }) : keywords = [...seeded];

  final Duration latency;
  final List<String> keywords;

  /// 다음 조회·삭제를 한 번 실패시킨다(시험용).
  bool failNextList = false;
  bool failNextDelete = false;

  /// 받은 삭제 명령 키(시험용).
  final deleteKeys = <String>[];

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<List<String>> list() async {
    await _wait();
    if (failNextList) {
      failNextList = false;
      throw const NetworkFailure(DioExceptionType.connectionError);
    }
    return List.unmodifiable(keywords);
  }

  @override
  Future<void> delete(String keyword, {required IdempotencyKey key}) async {
    await _wait();
    deleteKeys.add(key.value);
    if (failNextDelete) {
      failNextDelete = false;
      throw const NetworkFailure(DioExceptionType.connectionError);
    }
    keywords.remove(keyword);
  }

  @override
  Future<void> clear({required IdempotencyKey key}) async {
    await _wait();
    deleteKeys.add(key.value);
    keywords.clear();
  }
}
