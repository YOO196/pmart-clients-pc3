import 'package:pmart_core/pmart_core.dart';

/// 이 기기의 비회원 배송지 ID 와 고른 배송지. 서버에 비회원 배송지 목록 경로가 없어(같은 기기 단건 조회만)
/// ID 만 기기에 둔다. 주소·연락처 원문은 두지 않는다(서버 조회로 받는다).
final class GuestAddressStore {
  GuestAddressStore(this._store);

  static const _idsKey = 'pmart.guest.addressIds';
  static const _selectedKey = 'pmart.guest.shoppingAddressId';

  final SecureKeyValueStore _store;

  Future<List<String>> ids() async {
    final raw = await _store.read(_idsKey);
    if (raw == null || raw.isEmpty) return const [];
    return raw.split('\n').where((s) => s.isNotEmpty).toList();
  }

  Future<void> add(String id) async {
    final current = await ids();
    if (current.contains(id)) return;
    await _store.write(_idsKey, [...current, id].join('\n'));
  }

  /// 서버에 없는(만료·삭제) 배송지를 지운다.
  Future<void> retain(Iterable<String> alive) async {
    final keep = (await ids()).where(alive.contains).toList();
    await _store.write(_idsKey, keep.join('\n'));
    final selected = await this.selected();
    if (selected != null && !keep.contains(selected)) {
      await _store.delete(_selectedKey);
    }
  }

  Future<String?> selected() => _store.read(_selectedKey);

  Future<void> select(String id) => _store.write(_selectedKey, id);
}
