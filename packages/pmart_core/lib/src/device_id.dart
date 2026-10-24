import 'package:uuid/uuid.dart';

import 'storage.dart';

/// 설치 단위 기기 ID(`X-Device-Id`). 처음 요청할 때 만들고 보안 저장소에 보관한다.
final class DeviceIdProvider {
  DeviceIdProvider(this._store);

  static const _key = 'pmart.deviceId';

  final SecureKeyValueStore _store;
  Future<String>? _pending;

  Future<String> get() => _pending ??= _loadOrCreate();

  Future<String> _loadOrCreate() async {
    final existing = await _store.read(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _store.write(_key, created);
    return created;
  }
}
