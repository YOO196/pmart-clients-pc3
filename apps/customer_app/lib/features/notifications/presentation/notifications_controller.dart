import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/mock_notifications_repository.dart';
import '../data/notifications_repository.dart';
import '../domain/notifications.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockNotificationsRepository(),
    PmartEnv.local => ApiNotificationsRepository(ref.watch(dioProvider)),
  },
);

/// 설정 변경 접수(ACCEPTED) 뒤 결과 조회 간격·횟수.
final noticePollPolicyProvider = Provider<({Duration interval, int attempts})>(
  (_) => (interval: const Duration(seconds: 1), attempts: 5),
);

/// 알림함 화면 상태. 목록은 서버 값만 담는다.
@immutable
class InboxState {
  const InboxState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.moreFailed = false,
    this.reading = const {},
    this.checking = const {},
  });

  final List<InboxNotice> items;
  final String? nextCursor;
  final bool loadingMore;

  /// 다음 쪽 조회 실패. 이미 받은 목록은 그대로 두고 "다시 시도"를 보인다(PARTIAL).
  final bool moreFailed;

  /// 읽음 처리 요청 중인 알림.
  final Set<String> reading;

  /// 읽음 처리 결과를 모르는 알림(확인 중). 다시 누르면 새로 보내지 않고 조회로 확인한다.
  final Set<String> checking;

  InboxState copyWith({
    List<InboxNotice>? items,
    String? Function()? nextCursor,
    bool? loadingMore,
    bool? moreFailed,
    Set<String>? reading,
    Set<String>? checking,
  }) => InboxState(
    items: items ?? this.items,
    nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
    reading: reading ?? this.reading,
    checking: checking ?? this.checking,
  );
}

/// 알림함. 비회원이면 null(로그인 안내). 조회 실패는 오류로 남긴다(빈 목록으로 바꾸지 않는다).
final inboxProvider =
    AsyncNotifierProvider.autoDispose<InboxController, InboxState?>(
      InboxController.new,
    );

class InboxController extends AsyncNotifier<InboxState?> {
  NotificationsRepository get _repo =>
      ref.read(notificationsRepositoryProvider);

  /// 다시 빌드되면(세션 변경·새로고침) 늘어난다. 늦게 도착한 옛 응답이 새 화면을 덮지 않게 한다.
  int _generation = 0;

  @override
  Future<InboxState?> build() async {
    _generation++;
    if (ref.watch(sessionProvider) is! MemberSession) return null;
    final page = await ref.watch(notificationsRepositoryProvider).list();
    return InboxState(items: page.items, nextCursor: page.nextCursor);
  }

  bool _current(int generation) =>
      ref.mounted && generation == _generation && state.value != null;

  void _update(InboxState Function(InboxState s) f) {
    final s = state.value;
    if (s != null) state = AsyncData(f(s));
  }

  /// 다음 쪽. 실패하면 받은 목록은 두고 [InboxState.moreFailed] 를 켠다.
  Future<void> loadMore() async {
    final s = state.value;
    final cursor = s?.nextCursor;
    if (s == null || cursor == null || s.loadingMore) return;
    final generation = _generation;
    _update((s) => s.copyWith(loadingMore: true, moreFailed: false));
    try {
      final page = await _repo.list(cursor: cursor);
      if (!_current(generation)) return;
      _update(
        (s) => s.copyWith(
          items: [
            ...s.items,
            for (final n in page.items)
              if (!s.items.any((o) => o.notificationId == n.notificationId)) n,
          ],
          nextCursor: () => page.nextCursor,
          loadingMore: false,
        ),
      );
    } on PmartFailure {
      if (!_current(generation)) return;
      _update((s) => s.copyWith(loadingMore: false, moreFailed: true));
    }
  }

  /// 알림을 열었다. 안 읽은 알림이면 읽음 처리한다(이동을 막지 않는다).
  /// 결과를 모르면 새 키로 다시 보내지 않고 `GET /me/notifications/{id}` 로 확인한다.
  Future<void> open(InboxNotice notice) async {
    final s = state.value;
    if (s == null || notice.read) return;
    final id = notice.notificationId;
    if (s.reading.contains(id)) return;
    if (s.checking.contains(id)) return _resolve(id, _generation);
    final generation = _generation;
    _update((s) => s.copyWith(reading: {...s.reading, id}));
    try {
      final updated = await _repo.markRead(id, key: IdempotencyKey.generate());
      if (!_current(generation)) return;
      _replace(updated);
    } on UnknownResultFailure {
      if (!_current(generation)) return;
      await _resolve(id, generation);
    } on PmartFailure {
      // 서버가 거절했다(403·404 등). 서버가 준 상태를 그대로 둔다.
    } finally {
      if (_current(generation)) {
        _update((s) => s.copyWith(reading: {...s.reading}..remove(id)));
      }
    }
  }

  /// "확인 중"인 알림의 읽음 여부를 서버에 묻는다.
  Future<void> _resolve(String id, int generation) async {
    try {
      final latest = await _repo.get(id);
      if (!_current(generation)) return;
      _replace(latest);
      _update((s) => s.copyWith(checking: {...s.checking}..remove(id)));
    } on PmartFailure {
      if (!_current(generation)) return;
      _update((s) => s.copyWith(checking: {...s.checking, id}));
    }
  }

  void _replace(InboxNotice n) => _update(
    (s) => s.copyWith(
      items: [
        for (final o in s.items) o.notificationId == n.notificationId ? n : o,
      ],
    ),
  );
}

/// 알림 상세(목적지 참조 포함). 비회원이면 null.
final noticeDetailProvider = FutureProvider.autoDispose
    .family<InboxNotice?, String>((ref, id) async {
      if (ref.watch(sessionProvider) is! MemberSession) return null;
      return ref.watch(notificationsRepositoryProvider).get(id);
    });

/// 설정 한 줄의 진행 상태.
enum SettingRowStatus { sending, checking }

String settingRowKey(NoticeCategory c, NoticeChannel ch) =>
    '${c.name}/${ch.name}';

@immutable
class NoticeSettingsState {
  const NoticeSettingsState({required this.settings, this.rows = const {}});

  /// 서버가 마지막으로 준 설정. 스위치는 이 값만 보인다.
  final NoticeSettings settings;
  final Map<String, SettingRowStatus> rows;
}

/// 수신 설정. 비회원이면 null.
final noticeSettingsProvider =
    AsyncNotifierProvider.autoDispose<
      NoticeSettingsController,
      NoticeSettingsState?
    >(NoticeSettingsController.new);

typedef _Pending = ({
  IdempotencyKey key,
  NoticeSettingChange change,
  int? expectedVersion,
  String? requestId,
});

class NoticeSettingsController extends AsyncNotifier<NoticeSettingsState?> {
  NotificationsRepository get _repo =>
      ref.read(notificationsRepositoryProvider);

  /// 결과를 모르는 변경. 줄마다 키·본문을 보관해 "다시 확인"은 같은 키·같은 본문으로만 보낸다.
  final _pending = <String, _Pending>{};

  @override
  Future<NoticeSettingsState?> build() async {
    _pending.clear();
    if (ref.watch(sessionProvider) is! MemberSession) return null;
    final s = await ref.watch(notificationsRepositoryProvider).settings();
    return NoticeSettingsState(settings: s);
  }

  void _setRow(String row, SettingRowStatus? status) {
    final s = state.value;
    if (s == null) return;
    state = AsyncData(
      NoticeSettingsState(
        settings: s.settings,
        rows: {...s.rows}..remove(row),
      ).withRow(row, status),
    );
  }

  /// 스위치 한 번 = 키 하나. 결과 불명은 같은 키로 한 번만 다시 보낸다.
  Future<SettingChangeOutcome> change(
    NoticeSettingItem item,
    bool enabled,
  ) async {
    final s = state.value;
    if (s == null) return const SettingChangeRejected('NOT_MEMBER');
    final row = settingRowKey(item.category, item.channel);
    if (s.rows.containsKey(row)) return const SettingChangeUnknown();
    _pending[row] = (
      key: IdempotencyKey.generate(),
      change: NoticeSettingChange(
        category: item.category,
        channel: item.channel,
        enabled: enabled,
      ),
      expectedVersion: s.settings.version,
      requestId: null,
    );
    return _run(row, resendOnUnknown: true);
  }

  /// "확인 중" 줄을 다시 확인한다. 접수 ID 가 있으면 결과 조회, 없으면 같은 키·같은 본문 재전송(새 변경이 아니다).
  Future<SettingChangeOutcome> recheck(String row) {
    if (!_pending.containsKey(row)) {
      return Future.value(const SettingChangeUnknown());
    }
    return _run(row, resendOnUnknown: false);
  }

  Future<SettingChangeOutcome> _run(
    String row, {
    required bool resendOnUnknown,
  }) async {
    final p = _pending[row]!;
    _setRow(row, SettingRowStatus.sending);
    Future<SettingChangeOutcome> send() => _repo.changeSettings(
      [p.change],
      expectedVersion: p.expectedVersion,
      key: p.key,
    );
    SettingChangeOutcome outcome;
    if (p.requestId case final id?) {
      outcome = SettingChangePending(id);
    } else {
      outcome = await send();
      if (outcome is SettingChangeUnknown && resendOnUnknown) {
        outcome = await send();
      }
    }
    if (outcome case SettingChangePending(:final requestId)) {
      _pending[row] = (
        key: p.key,
        change: p.change,
        expectedVersion: p.expectedVersion,
        requestId: requestId,
      );
      final policy = ref.read(noticePollPolicyProvider);
      for (var i = 0; i < policy.attempts; i++) {
        if (i > 0) await Future<void>.delayed(policy.interval);
        if (!ref.mounted) return outcome;
        try {
          final checked = await _repo.settingChange(requestId);
          if (checked is! SettingChangePending) {
            outcome = checked;
            break;
          }
        } on PmartFailure {
          // 조회 실패는 결과가 아니다. 계속 확인 중이다.
        }
      }
    }
    if (!ref.mounted) return outcome;
    switch (outcome) {
      case SettingChangeApplied() || SettingChangeRejected():
        _pending.remove(row);
        _setRow(row, null);
        if (outcome is SettingChangeApplied ||
            (outcome as SettingChangeRejected).code ==
                ProblemCode.versionConflict) {
          await _reload();
        }
      case SettingChangePending() || SettingChangeUnknown():
        _setRow(row, SettingRowStatus.checking);
        // 서버 값으로 다시 그린다. 서버가 이미 바라던 값이면 확인된 것이다.
        await _reload();
        final now = state.value?.settings.items.where(
          (i) => settingRowKey(i.category, i.channel) == row,
        );
        if (now != null &&
            now.isNotEmpty &&
            now.first.enabled == p.change.enabled &&
            ref.mounted) {
          _pending.remove(row);
          _setRow(row, null);
          outcome = const SettingChangeApplied();
        }
    }
    return outcome;
  }

  Future<void> _reload() async {
    try {
      final fresh = await _repo.settings();
      if (!ref.mounted) return;
      final s = state.value;
      state = AsyncData(
        NoticeSettingsState(settings: fresh, rows: s?.rows ?? const {}),
      );
    } on PmartFailure {
      // 다시 읽기 실패는 마지막 서버 값을 그대로 둔다(바뀐 것으로 보이지 않는다).
    }
  }
}

extension on NoticeSettingsState {
  NoticeSettingsState withRow(String row, SettingRowStatus? status) =>
      status == null
      ? this
      : NoticeSettingsState(settings: settings, rows: {...rows, row: status});
}
