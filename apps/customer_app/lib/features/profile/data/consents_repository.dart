import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;

/// 내 동의 한 항목(customer 0.3.0 `GET /me/consents`). 버전은 서버 값 그대로 — 앱에 상수로 두지 않는다.
@immutable
class MyConsent {
  const MyConsent({
    required this.type,
    required this.required,
    required this.agreed,
    required this.latestVersion,
    this.version,
    this.requiredFor,
  });

  /// 계약 `ConsentType` 값(TERMS_OF_SERVICE·PRIVACY_POLICY·AGE_OVER_14·MARKETING·LOCATION_BASED_SERVICE).
  final String type;
  final bool required;
  final bool agreed;

  /// 이 기능을 쓸 때만 필수(0.6.0 — 위치 약관 `CURRENT_LOCATION`). 재동의 화면에서 묻지 않는다.
  final String? requiredFor;

  /// 고른 버전(없으면 null).
  final String? version;
  final String latestVersion;

  /// 지금 버전에 동의한 상태인지.
  bool get current => agreed && version == latestVersion;
}

@immutable
class MyConsents {
  const MyConsents({required this.items, required this.requiredOutdated});

  final List<MyConsent> items;

  /// 필수 동의 중 지금 버전에 동의하지 않은 것이 있다 → 주문 전 재동의(서버 스위치가 켜지면 구매 불가).
  final bool requiredOutdated;

  MyConsent? get marketing =>
      items.where((c) => c.type == ConsentWire.marketing).firstOrNull;
}

/// 바꿀 동의 하나. [version] 은 서버가 준 latestVersion.
@immutable
class ConsentChange {
  const ConsentChange(this.type, this.version, {required this.agreed});

  final String type;
  final String version;
  final bool agreed;
}

abstract final class ConsentWire {
  static const terms = 'TERMS_OF_SERVICE';
  static const privacy = 'PRIVACY_POLICY';
  static const age14 = 'AGE_OVER_14';
  static const marketing = 'MARKETING';

  /// 위치기반서비스 이용약관(0.6.0 BR-59) — 현재 위치 기능을 쓸 때만 필수.
  static const location = 'LOCATION_BASED_SERVICE';
}

abstract final class ConsentProblemCode {
  /// 필수 동의는 끌 수 없다(422 — 필수 철회 = 탈퇴).
  static const requiredCannotBeWithdrawn =
      'REQUIRED_CONSENT_CANNOT_BE_WITHDRAWN';

  /// 옛 버전으로 보냄(422) — 다시 조회.
  static const versionOutdated = 'CONSENT_VERSION_OUTDATED';
}

/// 로그인해 있는 고객의 동의 조회·변경(customer 0.3.0). 로그인 동의(AUTH_CONSENT)는 auth completions 로 따로 보낸다.
abstract interface class ConsentsRepository {
  Future<MyConsents> list();

  /// `POST /me/consent-changes`. 같은 키 재전송은 같은 결과.
  Future<CommandStatus> change(
    List<ConsentChange> changes, {
    required IdempotencyKey key,
  });
}

final class ApiConsentsRepository implements ConsentsRepository {
  ApiConsentsRepository(Dio dio)
    : _api = api.PmartApiCustomer(dio: dio).getConsentsApi();

  final api.ConsentsApi _api;

  @override
  Future<MyConsents> list() async {
    final res = await pmartGuard(() => _api.listMyConsents());
    return myConsentsFromContract(
      res.data ?? (throw const ContractViolationFailure('내 동의 본문 없음')),
    );
  }

  @override
  Future<CommandStatus> change(
    List<ConsentChange> changes, {
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.changeMyConsents(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        changeMyConsentsRequest: api.ChangeMyConsentsRequest(
          changes: [
            for (final c in changes)
              api.ChangeMyConsentsRequestChangesInner(
                consentType: api.ConsentType.values.firstWhere(
                  (v) => v.value == c.type,
                  orElse: () =>
                      throw ContractViolationFailure('모르는 동의 항목 ${c.type}'),
                ),
                version: c.version,
                agreed: c.agreed,
              ),
          ],
        ),
        extra: commandOptions(key).extra,
      ),
    );
    final status = res.data?.status.value;
    if (status == null) throw UnknownResultFailure(requestId: key.value);
    return CommandStatus.parse(status);
  }
}

MyConsents myConsentsFromContract(api.ListMyConsents200Response r) =>
    MyConsents(
      requiredOutdated: r.requiredConsentOutdated,
      items: [
        for (final c in r.items)
          MyConsent(
            type: c.consentType.value,
            required: c.required_,
            agreed: c.agreed,
            version: c.version,
            latestVersion: c.latestVersion,
            requiredFor: c.requiredFor?.value,
          ),
      ],
    );

/// ⚠ 화면 개발·시험용 목. 서버 버전 값은 백엔드 알림(2026-11-17 consents §1)과 같게 둔다.
final class MockConsentsRepository implements ConsentsRepository {
  MockConsentsRepository({this.latency = Duration.zero, this.outdated = false});

  final Duration latency;

  /// 필수 약관 버전이 바뀌어 다시 동의해야 하는 고객인지.
  bool outdated;

  bool marketingAgreed = false;
  final changes = <(List<ConsentChange>, String)>[];
  PmartFailure? failNextChange;
  PmartFailure? failNextList;

  static const _latest = {
    ConsentWire.terms: '2026-11-17',
    ConsentWire.privacy: '2026-11-17',
    ConsentWire.age14: '1',
    ConsentWire.marketing: '2026-11-17',
    ConsentWire.location: '2026-11-19',
  };

  /// 선택 항목(마케팅)·기능 필수(위치 약관 — 0.6.0)는 필수 목록이 아니다.
  static bool _optional(String type) =>
      type == ConsentWire.marketing || type == ConsentWire.location;

  bool locationAgreed = false;

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<MyConsents> list() async {
    await _wait();
    if (failNextList case final f?) {
      failNextList = null;
      throw f;
    }
    return MyConsents(
      requiredOutdated: outdated,
      items: [
        for (final MapEntry(key: type, value: latest) in _latest.entries)
          if (type == ConsentWire.location)
            MyConsent(
              type: type,
              required: false,
              requiredFor: 'CURRENT_LOCATION',
              agreed: locationAgreed,
              version: locationAgreed ? latest : null,
              latestVersion: latest,
            )
          else if (type == ConsentWire.marketing)
            MyConsent(
              type: type,
              required: false,
              agreed: marketingAgreed,
              version: marketingAgreed ? latest : null,
              latestVersion: latest,
            )
          else
            MyConsent(
              type: type,
              required: true,
              agreed: !outdated,
              version: outdated ? '2026-01-01' : latest,
              latestVersion: latest,
            ),
      ],
    );
  }

  @override
  Future<CommandStatus> change(
    List<ConsentChange> changes, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    this.changes.add((changes, key.value));
    if (failNextChange case final f?) {
      failNextChange = null;
      throw f;
    }
    for (final c in changes) {
      if (_latest[c.type] != c.version) {
        throw const ProblemFailure(
          Problem(status: 422, code: ConsentProblemCode.versionOutdated),
        );
      }
      if (c.type == ConsentWire.marketing) {
        marketingAgreed = c.agreed;
      } else if (c.type == ConsentWire.location) {
        locationAgreed = c.agreed;
      } else if (!c.agreed) {
        throw const ProblemFailure(
          Problem(
            status: 422,
            code: ConsentProblemCode.requiredCannotBeWithdrawn,
          ),
        );
      }
    }
    final required = _latest.keys.where((k) => !_optional(k));
    if (required.every((k) => changes.any((c) => c.type == k && c.agreed))) {
      outdated = false;
    }
    return CommandStatus.applied;
  }
}
