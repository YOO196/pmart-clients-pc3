import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';

/// 새 가입 단계 수: 약관 동의 → 휴대폰 확인 → 내 정보.
const signupStepTotal = 3;

/// 새 가입 단계 표시(약관 동의 E안, 사용자 2026-11-21 — 초안 `../고객앱 ui/03_약관동의/consent_mix.html`):
/// 세 칸 진행 막대(높이 4, 지난·지금 단계는 주 색) + "지금 단계 · 다음: 다음 단계"(12.5 굵게, 주 색).
/// 약관 동의(1)·휴대폰 확인(2)·가입 직후 내 정보(3) 화면 맨 위에 같이 쓴다. 재동의·기존 회원 확인·마이의 내 정보는 쓰지 않는다.
class SignupSteps extends StatelessWidget {
  const SignupSteps({super.key, required this.step});

  /// 1부터.
  final int step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = switch (step) {
      1 => l10n.signupStep1,
      2 => l10n.signupStep2,
      _ => l10n.signupStep3,
    };
    return Column(
      key: ValueKey('signup-steps-$step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 18),
          child: Row(
            children: [
              for (var i = 1; i <= signupStepTotal; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 앱바 오른쪽 "n / 3"(회색 작은 글자).
class SignupStepCount extends StatelessWidget {
  const SignupStepCount({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Center(
        child: Text(
          AppLocalizations.of(context).consentStepCount(step, signupStepTotal),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
