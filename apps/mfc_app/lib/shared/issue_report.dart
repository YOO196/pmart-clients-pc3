import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../l10n/gen/app_localizations.dart';
import 'providers.dart';

/// 현장 예외(이동·보충·적치·복귀·실사). 피킹 결품(`shortage`) 밖의 것은 보낼 경로가 계약에 없다(BR-52 R19 7).
enum FieldIssue {
  /// 출발 칸에 물건이 없음.
  sourceEmpty,

  /// 출발 칸에 모자람.
  sourceShort,

  /// 도착 칸을 쓸 수 없음(가득·막힘).
  targetUnusable,

  /// 칸에 갈 수 없음.
  locationBlocked,

  /// 파손 발견.
  damaged,

  /// 온도 유지 안 됨(냉장·냉동 취소품).
  temperature,
}

@immutable
class IssueReport {
  const IssueReport({
    required this.area,
    required this.targetId,
    required this.issue,
    this.location,
    this.qty,
  });

  /// 어느 업무의 무엇(move·putaway·return·count 와 대상 ID).
  final String area;
  final String targetId;
  final FieldIssue issue;
  final String? location;
  final int? qty;
}

abstract interface class IssueReporter {
  /// 보낼 경로가 있는지. 없으면 화면은 "관리자에게 알려 주세요"만 보인다.
  bool get available;

  /// 보낸 결과. 같은 키 재전송은 한 번만 남는다.
  Future<bool> report(IssueReport r, {required IdempotencyKey key});
}

/// 목 — 받은 보고를 남긴다.
final class MockIssueReporter implements IssueReporter {
  final reports = <IssueReport>[];
  final _keys = <String>{};

  @override
  bool get available => true;

  @override
  Future<bool> report(IssueReport r, {required IdempotencyKey key}) async {
    if (_keys.add(key.value)) reports.add(r);
    return true;
  }
}

/// 실서버 — 경로가 생기기 전(R19 7). 추측해 부르지 않는다.
final class UnavailableIssueReporter implements IssueReporter {
  const UnavailableIssueReporter();

  @override
  bool get available => false;

  @override
  Future<bool> report(IssueReport r, {required IdempotencyKey key}) async =>
      false;
}

final issueReporterProvider = Provider<IssueReporter>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockIssueReporter(),
    PmartEnv.local => const UnavailableIssueReporter(),
  },
);

String fieldIssueText(AppLocalizations l10n, FieldIssue i) => switch (i) {
  FieldIssue.sourceEmpty => l10n.issueSourceEmpty,
  FieldIssue.sourceShort => l10n.issueSourceShort,
  FieldIssue.targetUnusable => l10n.issueTargetUnusable,
  FieldIssue.locationBlocked => l10n.issueLocationBlocked,
  FieldIssue.damaged => l10n.issueDamaged,
  FieldIssue.temperature => l10n.issueTemperature,
};

/// "문제 보고" 버튼 — 사유를 고르면 보낸다. 보냈으면 [onReported].
class IssueButton extends ConsumerStatefulWidget {
  const IssueButton({
    super.key,
    required this.id,
    required this.area,
    required this.targetId,
    required this.issues,
    required this.onReported,
    this.location,
    this.qty,
  });

  final String id;
  final String area;
  final String targetId;
  final List<FieldIssue> issues;
  final String? location;
  final int? qty;
  final ValueChanged<FieldIssue> onReported;

  @override
  ConsumerState<IssueButton> createState() => _IssueButtonState();
}

class _IssueButtonState extends ConsumerState<IssueButton> {
  /// 사유를 고른 뒤 확정 전까지 같은 키(다시 눌러도 한 번만 남는다).
  IdempotencyKey? _key;
  bool _busy = false;

  Future<void> _open() async {
    final l10n = AppLocalizations.of(context);
    final reporter = ref.read(issueReporterProvider);
    if (!reporter.available) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.issueNoPath)));
      return;
    }
    final issue = await showDialog<FieldIssue>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.issueTitle),
        children: [
          for (final i in widget.issues)
            SimpleDialogOption(
              key: ValueKey('${widget.id}-${i.name}'),
              onPressed: () => Navigator.of(context).pop(i),
              child: Text(fieldIssueText(l10n, i)),
            ),
        ],
      ),
    );
    if (issue == null || !mounted) return;
    setState(() => _busy = true);
    final key = _key ??= IdempotencyKey.generate();
    final ok = await reporter.report(
      IssueReport(
        area: widget.area,
        targetId: widget.targetId,
        issue: issue,
        location: widget.location,
        qty: widget.qty,
      ),
      key: key,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _key = null;
      widget.onReported(issue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextButton.icon(
      key: ValueKey(widget.id),
      onPressed: _busy ? null : _open,
      icon: const Icon(Icons.report_problem_outlined),
      label: Text(l10n.issueReport),
    );
  }
}
