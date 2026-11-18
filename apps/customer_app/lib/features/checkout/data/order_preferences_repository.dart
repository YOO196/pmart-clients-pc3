import 'package:dio/dio.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/checkout.dart' show OutOfStockPreference;

/// 내 주문 기본 설정(customer 0.4.0 `/me/order-preferences`). 지금은 품절 처리 "다음에도 적용" 하나.
/// order 는 이 값을 읽지 않는다 — 앱이 다음 주문서의 기본값으로 읽어 주문서 요청에 그대로 보낸다.
class OrderPreferences {
  const OrderPreferences({required this.version, this.outOfStock});

  /// 저장 안 했으면 null(기본값으로 바꾸지 않는다).
  final OutOfStockPreference? outOfStock;
  final int version;
}

abstract interface class OrderPreferencesRepository {
  /// `GET /me/order-preferences`. 저장 안 했으면 outOfStock null·version 0.
  Future<OrderPreferences> get();

  /// `PUT /me/order-preferences`. 같은 키 재전송은 같은 결과.
  Future<OrderPreferences> save(
    OutOfStockPreference p, {
    required IdempotencyKey key,
  });
}

final class ApiOrderPreferencesRepository
    implements OrderPreferencesRepository {
  ApiOrderPreferencesRepository(Dio dio)
    : _api = api.PmartApiCustomer(dio: dio).getPreferencesApi();

  final api.PreferencesApi _api;

  @override
  Future<OrderPreferences> get() async {
    final res = await pmartGuard(() => _api.getMyOrderPreferences());
    return orderPreferencesFromContract(
      res.data ?? (throw const ContractViolationFailure('주문 기본 설정 본문 없음')),
    );
  }

  @override
  Future<OrderPreferences> save(
    OutOfStockPreference p, {
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.updateMyOrderPreferences(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        updateMyOrderPreferencesRequest: api.UpdateMyOrderPreferencesRequest(
          outOfStockPreference: switch (p) {
            OutOfStockPreference.cancelOutOfStockOnly =>
              api.OutOfStockPreference.CANCEL_OOS_ONLY,
            OutOfStockPreference.cancelAll =>
              api.OutOfStockPreference.CANCEL_ALL,
          },
        ),
        extra: commandOptions(key).extra,
      ),
    );
    return orderPreferencesFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }
}

OrderPreferences orderPreferencesFromContract(api.OrderPreferences p) =>
    OrderPreferences(
      version: p.version,
      outOfStock: switch (p.outOfStockPreference) {
        api.OrderPreferencesOutOfStockPreferenceEnum.CANCEL_OOS_ONLY =>
          OutOfStockPreference.cancelOutOfStockOnly,
        api.OrderPreferencesOutOfStockPreferenceEnum.CANCEL_ALL =>
          OutOfStockPreference.cancelAll,
        _ => null,
      },
    );

/// ⚠ 화면 개발·시험용 목.
final class MockOrderPreferencesRepository
    implements OrderPreferencesRepository {
  MockOrderPreferencesRepository({this.latency = Duration.zero});

  final Duration latency;
  OutOfStockPreference? stored;
  int version = 0;

  /// 저장에 보낸 (값, 키).
  final saves = <(OutOfStockPreference, String)>[];

  /// 다음 저장/조회에 던질 실패(시험용).
  PmartFailure? failNextSave;
  PmartFailure? failNextGet;

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<OrderPreferences> get() async {
    await _wait();
    if (failNextGet case final f?) {
      failNextGet = null;
      throw f;
    }
    return OrderPreferences(version: version, outOfStock: stored);
  }

  @override
  Future<OrderPreferences> save(
    OutOfStockPreference p, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    saves.add((p, key.value));
    if (failNextSave case final f?) {
      failNextSave = null;
      throw f;
    }
    if (stored != p) version += 1;
    stored = p;
    return OrderPreferences(version: version, outOfStock: stored);
  }
}
