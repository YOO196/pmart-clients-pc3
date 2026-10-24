import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../domain/address.dart';
import 'address_repository.dart';

/// 목 구현. 도로명에 "제주"가 있으면 권역 밖, "확인"이 있으면 판정 불명으로 저장한다.
base class MockAddressRepository implements AddressRepository {
  MockAddressRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  static const homeMfcId = 'MFC-MOCK-01';

  final _addresses = <Map<String, Object?>>[
    {
      'addressId': 'addr-1',
      'version': 1,
      'label': '집',
      'roadAddress': '서울 송파구 올림픽로 300',
      'detailAddress': '101동 1001호',
      'receiverName': '김피마',
      'receiverPhone': '010-0000-0000',
      'entranceMethod': 'PASSWORD',
      'serviceability': {'state': 'SERVICEABLE', 'mfcId': homeMfcId},
    },
  ];
  final _addedByKey = <String, Map<String, Object?>>{};
  String? _shoppingAddressId = 'addr-1';
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
          : {'state': 'SERVICEABLE', 'mfcId': 'MFC-MOCK-02'},
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

  @override
  Future<ShoppingContext> context() async {
    await _wait();
    return contextFromContract(api.ShoppingContext.fromJson(_contextJson()));
  }
}
