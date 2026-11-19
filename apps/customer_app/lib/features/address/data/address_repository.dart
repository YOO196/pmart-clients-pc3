import 'package:dio/dio.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/address.dart';

/// 회원 주소록·쇼핑 주소, 비회원 배송지. 실패는 [PmartFailure] 로 던진다.
abstract interface class AddressRepository {
  Future<AddressBook> book();

  /// `POST /me/addresses`. 권역 밖이어도 저장된다(serviceability 로 구분).
  /// 짝 조회 경로가 없어서 결과 불명은 같은 [key] 재전송으로 해소한다.
  Future<Address> add(AddressDraft draft, {required IdempotencyKey key});

  /// `POST /me/shopping-address-selections`. 결과 불명은 [context] 로 확인한다.
  Future<ShoppingContext> select(
    String addressId, {
    required int expectedVersion,
    required IdempotencyKey key,
  });

  Future<ShoppingContext> context();

  /// `POST /guest-delivery-addresses`(토큰 없음, X-Device-Id). 결과 불명은 같은 [key] 재전송으로 해소한다.
  Future<Address> addGuest(AddressDraft draft, {required IdempotencyKey key});

  /// `GET /guest-delivery-addresses/{id}`(같은 기기만).
  Future<Address> guest(String guestAddressId);

  /// 같은 비회원 배송지를 입력값 그대로(받는 분 전화·출입 메모·핀 포함) 읽는다 — 로그인 뒤 회원 주소록에 옮길 때 쓴다.
  /// 서버에 옮기는 경로가 없어 앱이 이 값으로 `POST /me/addresses` 한다(고객 확인 뒤).
  Future<AddressDraft> guestDraft(String guestAddressId);
}

final class ApiAddressRepository implements AddressRepository {
  ApiAddressRepository(Dio dio, this._deviceId)
    : _addresses = api.PmartApiCustomer(dio: dio).getAddressesApi();

  final api.AddressesApi _addresses;
  final DeviceIdProvider _deviceId;

  @override
  Future<Address> addGuest(
    AddressDraft draft, {
    required IdempotencyKey key,
  }) async {
    final deviceId = await _deviceId.get();
    final res = await pmartGuard(
      () => _addresses.createGuestDeliveryAddress(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xDeviceId: deviceId,
        addressInput: addressInputToContract(draft),
        extra: commandOptions(key).extra,
      ),
    );
    return addressFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<Address> guest(String guestAddressId) async {
    final deviceId = await _deviceId.get();
    final res = await pmartGuard(
      () => _addresses.getGuestDeliveryAddress(
        guestAddressId: guestAddressId,
        xDeviceId: deviceId,
      ),
    );
    return addressFromContract(
      res.data ?? (throw const ContractViolationFailure('배송지 본문 없음')),
    );
  }

  @override
  Future<AddressDraft> guestDraft(String guestAddressId) async {
    final deviceId = await _deviceId.get();
    final res = await pmartGuard(
      () => _addresses.getGuestDeliveryAddress(
        guestAddressId: guestAddressId,
        xDeviceId: deviceId,
      ),
    );
    return draftFromContract(
      res.data ?? (throw const ContractViolationFailure('배송지 본문 없음')),
    );
  }

  @override
  Future<AddressBook> book() async {
    final res = await pmartGuard(() => _addresses.listMyAddresses());
    final body =
        res.data ?? (throw const ContractViolationFailure('주소록 본문 없음'));
    final ctx = body.shoppingContext;
    return AddressBook(
      addresses: [
        for (final a in body.items ?? <api.Address>[]) addressFromContract(a),
      ],
      // 컨텍스트가 빠지면 현재 쇼핑 주소를 "없음"으로 단정하지 않는다.
      context: ctx == null
          ? throw const ContractViolationFailure('shoppingContext 없음')
          : contextFromContract(ctx),
    );
  }

  @override
  Future<Address> add(AddressDraft draft, {required IdempotencyKey key}) async {
    final res = await pmartGuard(
      () => _addresses.addMyAddress(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        addressInput: addressInputToContract(draft),
        extra: commandOptions(key).extra,
      ),
    );
    return addressFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<ShoppingContext> select(
    String addressId, {
    required int expectedVersion,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _addresses.selectShoppingAddress(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xExpectedVersion: expectedVersion,
        selectShoppingAddressRequest: api.SelectShoppingAddressRequest(
          addressId: addressId,
        ),
        extra: commandOptions(key, expectedVersion: expectedVersion).extra,
      ),
    );
    return contextFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<ShoppingContext> context() async {
    final res = await pmartGuard(() => _addresses.getShoppingContext());
    return contextFromContract(
      res.data ??
          (throw const ContractViolationFailure('ShoppingContext 본문 없음')),
    );
  }
}

api.AddressInput addressInputToContract(AddressDraft draft) => api.AddressInput(
  label: draft.label,
  roadAddress: draft.roadAddress,
  detailAddress: draft.detailAddress,
  postalCode: draft.postalCode,
  receiverName: draft.receiverName,
  receiverPhone: draft.receiverPhone,
  entranceMethod: switch (draft.entranceMethod) {
    EntranceMethod.free => api.AddressInputEntranceMethodEnum.FREE,
    EntranceMethod.password => api.AddressInputEntranceMethodEnum.PASSWORD,
    EntranceMethod.call => api.AddressInputEntranceMethodEnum.CALL,
    EntranceMethod.other => api.AddressInputEntranceMethodEnum.OTHER,
    null => null,
  },
  entranceNote: draft.entranceNote,
  geo: switch (draft.geo) {
    final g? => api.AddressInputGeo(lat: g.lat, lng: g.lng),
    null => null,
  },
);

Address addressFromContract(api.Address a) => Address(
  addressId:
      a.addressId ?? (throw const ContractViolationFailure('addressId 없음')),
  version: a.version ?? 0,
  label: a.label,
  roadAddress: a.roadAddress,
  detailAddress: a.detailAddress,
  receiverName: a.receiverName,
  entranceMethod: switch (a.entranceMethod) {
    api.AddressEntranceMethodEnum.FREE => EntranceMethod.free,
    api.AddressEntranceMethodEnum.PASSWORD => EntranceMethod.password,
    api.AddressEntranceMethodEnum.CALL => EntranceMethod.call,
    api.AddressEntranceMethodEnum.OTHER => EntranceMethod.other,
    null => null,
  },
  serviceability: switch (a.serviceability?.state?.value) {
    'SERVICEABLE' => Serviceability.serviceable,
    'OUT_OF_SERVICE_AREA' => Serviceability.outOfArea,
    _ => Serviceability.unknown,
  },
  mfcId: a.serviceability?.mfcId,
);

/// 저장된 배송지를 다시 등록할 입력값으로(서버 판정·ID·버전은 빼고 고객이 넣은 값만).
AddressDraft draftFromContract(api.Address a) => AddressDraft(
  label: a.label,
  roadAddress: a.roadAddress,
  detailAddress: a.detailAddress,
  receiverName: a.receiverName,
  receiverPhone: a.receiverPhone,
  postalCode: a.postalCode,
  entranceNote: a.entranceNote,
  entranceMethod: switch (a.entranceMethod) {
    api.AddressEntranceMethodEnum.FREE => EntranceMethod.free,
    api.AddressEntranceMethodEnum.PASSWORD => EntranceMethod.password,
    api.AddressEntranceMethodEnum.CALL => EntranceMethod.call,
    api.AddressEntranceMethodEnum.OTHER => EntranceMethod.other,
    null => null,
  },
  // 고객이 찍은 핀만 옮긴다 — 서버가 도로명으로 채운 좌표(GEOCODE)는 회원 주소 저장 때 서버가 다시 채운다.
  geo: switch ((a.geo?.lat, a.geo?.lng, a.geoSource)) {
    (final num lat, final num lng, api.AddressGeoSourceEnum.PIN) => (
      lat: lat.toDouble(),
      lng: lng.toDouble(),
    ),
    _ => null,
  },
);

ShoppingContext contextFromContract(api.ShoppingContext c) => ShoppingContext(
  shoppingAddressId: c.shoppingAddressId,
  mfcId: c.mfcId,
  version:
      c.shoppingContextVersion ??
      (throw const ContractViolationFailure('shoppingContextVersion 없음')),
);
