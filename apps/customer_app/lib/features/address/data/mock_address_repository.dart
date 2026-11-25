import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../domain/address.dart';
import 'address_repository.dart';

/// 목 구현. 도로명에 "제주"가 있으면 권역 밖, "확인"이 있으면 판정 불명으로 저장한다.
base class MockAddressRepository implements AddressRepository {
  MockAddressRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  // 라이더앱 목과 같은 지점·배송지(PC 5 요청 rider-app/2026-11-16-pc1-request-shared-mock-order — 목 전용).
  static const homeMfcId = 'MFC-BSJ-01';

  final _addresses = <Map<String, Object?>>[
    {
      'addressId': 'addr-1',
      'version': 1,
      'label': '집',
      'roadAddress': '부산 부산진구 전포대로 210',
      'detailAddress': '전포 한빛아파트 103동 1203호',
      'receiverName': '김피마',
      'receiverPhone': '010-0000-0000',
      'entranceMethod': 'PASSWORD',
      'serviceability': {'state': 'SERVICEABLE', 'mfcId': homeMfcId},
    },
  ];
  final _addedByKey = <String, Map<String, Object?>>{};
  String? _shoppingAddressId = 'addr-1';

  /// 시험용: 쇼핑 주소를 정하지 않은 회원(주소는 있음).
  void clearShoppingAddress() => _shoppingAddressId = null;
  String? _mfcId = homeMfcId;
  int contextVersion = 1;
  int _seq = 1;

  /// 다음 쇼핑 주소 선택을 "반영됐지만 응답 잃음"으로 만든다.
  bool loseNextSelection = false;

  Future<void> _wait() => Future<void>.delayed(latency);

  Map<String, Object?> _contextJson() => {
    'accountId': 'acct-mock-1',
    'shoppingAddressId': _shoppingAddressId,
    'mfcId': _mfcId,
    'shoppingContextVersion': contextVersion,
  };

  @override
  Future<AddressBook> book() async {
    await _wait();
    final res = api.ListMyAddresses200Response.fromJson({
      'items': _addresses,
      'shoppingContext': _contextJson(),
    });
    return AddressBook(
      addresses: [for (final a in res.items!) addressFromContract(a)],
      context: contextFromContract(res.shoppingContext!),
    );
  }

  @override
  Future<Address> add(AddressDraft draft, {required IdempotencyKey key}) async {
    await _wait();
    final existing = _addedByKey[key.value];
    if (existing != null) {
      return addressFromContract(api.Address.fromJson(existing));
    }
    final road = draft.roadAddress;
    final json = <String, Object?>{
      'addressId': 'addr-${++_seq}',
      'version': 1,
      'label': draft.label,
      'roadAddress': road,
      'detailAddress': draft.detailAddress,
      'receiverName': draft.receiverName,
      'receiverPhone': draft.receiverPhone,
      'entranceMethod': switch (draft.entranceMethod) {
        EntranceMethod.free => 'FREE',
        EntranceMethod.password => 'PASSWORD',
        EntranceMethod.call => 'CALL',
        EntranceMethod.other => 'OTHER',
        null => null,
      },
      'serviceability': road.contains('제주')
          ? {'state': 'OUT_OF_SERVICE_AREA'}
          : road.contains('확인')
          ? {'state': 'UNKNOWN'}
          : {'state': 'SERVICEABLE', 'mfcId': 'MFC-BHU-01'},
    };
    _addresses.add(json);
    _addedByKey[key.value] = json;
    return addressFromContract(api.Address.fromJson(json));
  }

  @override
  Future<ShoppingContext> select(
    String addressId, {
    required int expectedVersion,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (expectedVersion != contextVersion) {
      throw const ProblemFailure(
        Problem(status: 409, code: ProblemCode.versionConflict),
      );
    }
    final address = _addresses
        .where((a) => a['addressId'] == addressId)
        .firstOrNull;
    if (address == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    _shoppingAddressId = addressId;
    _mfcId = (address['serviceability'] as Map?)?['mfcId'] as String?;
    contextVersion++;
    if (loseNextSelection) {
      loseNextSelection = false;
      throw UnknownResultFailure(requestId: key.value, httpStatus: 504);
    }
    return contextFromContract(api.ShoppingContext.fromJson(_contextJson()));
  }

  /// 다음 삭제를 "반영됐지만 응답 잃음"으로 만든다.
  bool loseNextDelete = false;

  /// 받은 삭제 명령 키(시험용).
  final deleteKeys = <String>[];

  @override
  Future<void> delete(String addressId, {required IdempotencyKey key}) async {
    await _wait();
    deleteKeys.add(key.value);
    if (addressId == _shoppingAddressId) {
      throw const ProblemFailure(
        Problem(status: 409, code: ProblemCode.invalidState),
      );
    }
    final before = _addresses.length;
    _addresses.removeWhere((a) => a['addressId'] == addressId);
    if (_addresses.length == before) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    if (loseNextDelete) {
      loseNextDelete = false;
      throw UnknownResultFailure(requestId: key.value, httpStatus: 504);
    }
  }

  final _guestAddresses = <String, Map<String, Object?>>{};
  final _guestByKey = <String, Map<String, Object?>>{};

  @override
  Future<Address> addGuest(
    AddressDraft draft, {
    required IdempotencyKey key,
  }) async {
    final existing = _guestByKey[key.value];
    if (existing != null) {
      await _wait();
      return addressFromContract(api.Address.fromJson(existing));
    }
    final saved = await add(draft, key: key);
    // 회원 주소록에 섞지 않는다.
    final json = _addresses.removeLast()
      ..['addressId'] = 'guest-${saved.addressId}';
    _addedByKey.remove(key.value);
    _guestAddresses[json['addressId']! as String] = json;
    _guestByKey[key.value] = json;
    return addressFromContract(api.Address.fromJson(json));
  }

  @override
  Future<Address> guest(String guestAddressId) async {
    await _wait();
    final json = _guestAddresses[guestAddressId];
    if (json == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    return addressFromContract(api.Address.fromJson(json));
  }

  @override
  Future<AddressDraft> guestDraft(String guestAddressId) async {
    await _wait();
    final json = _guestAddresses[guestAddressId];
    if (json == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    return draftFromContract(api.Address.fromJson(json));
  }

  /// 연락처를 비운 주소 ID(시험 확인용).
  final clearedPhones = <String>[];

  @override
  Future<bool> clearStoredPhone(
    String addressId, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    final json = _addresses
        .where((a) => a['addressId'] == addressId)
        .firstOrNull;
    if (json == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    final phone = json['receiverPhone'] as String?;
    if (phone == null || phone.trim().isEmpty) return false;
    json['receiverPhone'] = null;
    json['version'] = (json['version']! as int) + 1;
    clearedPhones.add(addressId);
    return true;
  }

  @override
  Future<AddressDraft> draft(String addressId) async {
    await _wait();
    final json = _addresses
        .where((a) => a['addressId'] == addressId)
        .firstOrNull;
    if (json == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    return draftFromContract(api.Address.fromJson(json));
  }

  /// 수정한 주소 ID(시험 확인용).
  final updated = <String>[];

  @override
  Future<void> update(
    String addressId,
    AddressDraft draft, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    final json = _addresses
        .where((a) => a['addressId'] == addressId)
        .firstOrNull;
    if (json == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    final input = addressInputToContract(draft).toJson()
      ..remove('receiverName')
      ..remove('receiverPhone')
      ..removeWhere((_, v) => v == null);
    json
      ..addAll(input)
      ..['version'] = (json['version']! as int) + 1;
    updated.add(addressId);
  }

  @override
  Future<ShoppingContext> context() async {
    await _wait();
    return contextFromContract(api.ShoppingContext.fromJson(_contextJson()));
  }
}
