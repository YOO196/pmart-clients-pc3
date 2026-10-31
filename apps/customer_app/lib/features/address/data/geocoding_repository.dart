import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pmart_api_delivery_serviceability/pmart_api_delivery_serviceability.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';

/// 주소 ↔ 좌표 후보(계약 `AddressLookup`, BR-30). 지도 시작 위치·핀 위치 안내용이다.
/// 배송 가능 판정은 서버가 도로명주소로 따로 한다(ADR-0023).
@immutable
class AddressCandidate {
  const AddressCandidate({
    required this.lat,
    required this.lng,
    this.roadAddress,
    this.jibunAddress,
    this.zoneNo,
    this.buildingName,
  });

  final double lat;
  final double lng;
  final String? roadAddress;
  final String? jibunAddress;
  final String? zoneNo;
  final String? buildingName;

  /// 화면에 보일 주소(도로명이 없으면 지번).
  String? get label => roadAddress ?? jibunAddress;

  @override
  String toString() => 'AddressCandidate(…)';
}

/// 조회 실패는 [PmartFailure] 로 던진다(0건과 구분: 0건은 빈 목록).
/// 카카오 장애 503 DEPENDENCY_UNAVAILABLE, 사용량 소진 429 QUOTA_EXCEEDED, 키 미설정 422 CONFIG_REQUIRED.
abstract interface class GeocodingRepository {
  /// `GET /address-geocodes?query=`
  Future<List<AddressCandidate>> geocode(String query);

  /// `GET /address-reverse-geocodes?lat=&lng=` — 표시용. 이 결과로 도로명주소를 바꾸지 않는다.
  Future<List<AddressCandidate>> reverse(double lat, double lng);
}

final class ApiGeocodingRepository implements GeocodingRepository {
  ApiGeocodingRepository(Dio dio)
    : _api = api.PmartApiDeliveryServiceability(dio: dio).getGeocodingApi();

  final api.GeocodingApi _api;

  @override
  Future<List<AddressCandidate>> geocode(String query) async {
    final res = await pmartGuard(
      () => _api.searchAddressGeocodes(query: query),
    );
    return candidatesFromContract(
      res.data ?? (throw const ContractViolationFailure('주소 검색 본문 없음')),
    );
  }

  @override
  Future<List<AddressCandidate>> reverse(double lat, double lng) async {
    final res = await pmartGuard(
      () => _api.searchAddressReverseGeocodes(lat: lat, lng: lng),
    );
    return candidatesFromContract(
      res.data ?? (throw const ContractViolationFailure('좌표 주소 본문 없음')),
    );
  }
}

List<AddressCandidate> candidatesFromContract(api.AddressLookupResult r) => [
  for (final c in r.results)
    // 좌표가 없는 후보는 지도에 둘 수 없다(0,0 으로 만들지 않는다).
    if (c.lat != null && c.lng != null)
      AddressCandidate(
        lat: c.lat!.toDouble(),
        lng: c.lng!.toDouble(),
        roadAddress: c.roadAddress,
        jibunAddress: c.jibunAddress,
        zoneNo: c.zoneNo,
        buildingName: c.buildingName,
      ),
];

/// 목: 어떤 주소든 서면역 부근 좌표 하나. "없는주소"면 0건.
final class MockGeocodingRepository implements GeocodingRepository {
  MockGeocodingRepository({this.latency = const Duration(milliseconds: 200)});

  final Duration latency;

  /// 다음 조회를 이 실패로 만든다.
  PmartFailure? failNext;

  @override
  Future<List<AddressCandidate>> geocode(String query) async {
    await Future<void>.delayed(latency);
    if (failNext case final f?) {
      failNext = null;
      throw f;
    }
    if (query.contains('없는주소')) return const [];
    return [
      AddressCandidate(
        lat: 35.1529,
        lng: 129.0596,
        roadAddress: query,
        zoneNo: '47296',
      ),
    ];
  }

  @override
  Future<List<AddressCandidate>> reverse(double lat, double lng) async {
    await Future<void>.delayed(latency);
    return [
      AddressCandidate(
        lat: lat,
        lng: lng,
        roadAddress: '부산 부산진구 중앙대로 672',
        buildingName: '삼정타워',
      ),
    ];
  }
}
