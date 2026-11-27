import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../l10n/gen/app_localizations.dart';
import '../field_widgets.dart' show ActionScope;
import '../printer/reprint.dart';
import '../pda_theme.dart';
import '../providers.dart';
import 'scanner.dart';
import '../pda_decor.dart';
import '../pda_motion.dart';

/// 테스트용 일괄 동작(목 모드 전용) — 예: 남은 박스 전부 스캔. 동작 안에서도 실제 스캔과 같은 처리를 부른다.
@immutable
class TestAction {
  const TestAction(this.key, this.label, this.run);

  final String key;
  final String label;
  final VoidCallback run;
}

/// 테스트용 스캔 값(목 모드 전용). 고르면 실제 스캔과 같은 [ScanInput.onScan] 을 탄다.
@immutable
class TestScan {
  const TestScan(this.label, this.value);

  final String label;
  final String value;
}

/// 스캔 입력. 스캔 받는 자리는 키보드 웨지(하드웨어 스캐너)의 입력을 받고, 그 긴 보라 칸을 누르면 카메라 스캐너가 열린다
/// (사용자 2026-11-19 "코드 스캔 바가 버튼 역할, 카메라 아이콘은 빼").
/// 두 경로 모두 같은 [onScan] 으로 간다. 실제 앱(안드로이드)은 스캔으로만 확인한다 — 화면 키보드가 뜨지 않아
/// 손으로 칠 수 없다. (PC 브라우저처럼 실제 키보드가 달린 곳에서는 키 입력을 스캐너와 구별하지 못한다 — 개발 확인용.)
/// 목 모드(`PMART_ENV=mock` — 웹 미리보기·테스트)에서만 [testValues] 드롭다운이 보인다.
class ScanInput extends ConsumerStatefulWidget {
  const ScanInput({
    super.key,
    required this.id,
    required this.label,
    required this.cameraTitle,
    required this.onScan,
    this.continuous = true,
    this.autofocus = true,
    this.testValues = const [],
    this.testActions = const [],
    this.reprint,
  });

  /// 입력칸(누르면 카메라) 키는 `ValueKey(id)`.
  final String id;
  final String label;
  final String cameraTitle;
  final ScanHandler onScan;
  final bool continuous;
  final bool autofocus;

  /// 그 단계에 맞는 더미 스캔 값(틀린 값 포함). 목 모드에서만 쓴다.
  final List<TestScan> testValues;

  /// 일괄 처리 같은 테스트 동작. 목 모드에서만 쓴다.
  final List<TestAction> testActions;

  /// 상품 스캔 자리면 그 자리에서 찍을 수 있는 상품들 — "바코드가 안 찍혀요"(재출력) 버튼을 아래에 둔다.
  /// null 이면 버튼이 없다(위치·카트·포장 QR 같은 자리). 빈 목록이면 버튼은 있되 누를 수 없다.
  final List<ReprintTarget>? reprint;

  @override
  ConsumerState<ScanInput> createState() => _ScanInputState();
}

class _ScanInputState extends ConsumerState<ScanInput>
    with TickerProviderStateMixin {
  final _text = TextEditingController();
  final _focus = FocusNode();

  /// 스캔 결과 표시 — 받아들이면 초록, 아니면 빨강 테두리가 잠깐 빛나고(빨강은 좌우로 흔들림) 사라진다
  /// (사용자 2026-11-26 "다 개선해" — 성공·실패가 눈에 잘 안 보였다). 값 1 = 표시 없음.
  late final _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    value: 1,
  );
  bool _flashOk = true;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _flash.dispose();
    _shake.dispose();
    super.dispose();
  }

  /// 화면의 [ScanInput.onScan] 을 부르고 결과를 보인다(하드웨어 스캐너·카메라 같은 길).
  ScanFeedback _handle(String code) {
    final fb = widget.onScan(code);
    if (!mounted) return fb;
    setState(() => _flashOk = fb.ok);
    if (!fb.ok) PdaHaptics.error();
    if (!PdaMotion.reduced(context)) {
      _flash.forward(from: 0);
      if (!fb.ok) _shake.forward(from: 0);
    }
    return fb;
  }

  void _submit(String v) {
    final code = v.trim();
    _text.clear();
    // 하드웨어 스캐너(키보드 웨지)가 다음 입력을 계속 받게 한다.
    _focus.requestFocus();
    if (code.isEmpty) return;
    PdaHaptics.scanned();
    _handle(code);
  }

  Future<void> _camera() async {
    await ref
        .read(cameraScannerProvider)
        .open(
          context,
          onScan: _handle,
          title: widget.cameraTitle,
          continuous: widget.continuous,
        );
    // 카메라를 닫으면 스캔 칸으로 돌아온다 — 하드웨어 스캐너 입력도 계속 받는다.
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => _row(context);

  Widget _row(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          // 타이핑 칸이 아니라 "스캔 받는 자리"다(사용자 2026-11-13: 바코드만 찍는다 — 손 입력 칸은 숨긴다).
          // 하드웨어 스캐너(키보드 웨지)는 글자 + Enter 를 보내므로 받을 자리는 있어야 한다. 그래서 입력칸은 두되
          // 화면 키보드를 띄우지 않고(TextInputType.none), 커서·글자·붙여넣기 메뉴를 보이지 않게 한다.
          // 눌러서 이 자리를 고르면(포커스) 스캐너 입력이 여기로 온다.
          // 보이는 것은 진짜 단추(누르면 카메라, 눌림 물결·그림자), 그 밑에 스캐너 입력을 받는 칸을 숨겨 둔다.
          // 예전엔 입력칸을 단추처럼 칠해 글자가 안내 글씨(왼쪽·작게)였고 포커스 테두리가 안쪽에 그려져 허술해 보였다
          // (사용자 2026-11-20 "그 버튼이랑 폰트가 여전히 별로, 없어 보여").
          child: AnimatedBuilder(
            animation: Listenable.merge([_flash, _shake]),
            builder: (context, child) {
              final glow = 1 - _flash.value;
              final s = _shake.value;
              final color = _flashOk ? PdaColors.ok : PdaColors.danger;
              return Transform.translate(
                offset: Offset(math.sin(s * math.pi * 2) * 5 * (1 - s), 0),
                // 바깥 빛(버튼 뒤에 깔려 글자를 가리지 않는다) + 테두리(앞)
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: glow > 0
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4 * glow),
                              blurRadius: 16,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: DecoratedBox(
                    key: ValueKey('${widget.id}-flash'),
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: glow > 0
                          ? Border.all(
                              color: color.withValues(alpha: glow),
                              width: 3,
                            )
                          : null,
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: SizedBox(
              height: 60,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 하드웨어 스캐너(키보드 웨지)는 글자 + Enter 를 보내므로 받을 자리는 있어야 한다 — 화면 키보드 없이, 보이지 않게.
                  Opacity(
                    opacity: 0,
                    child: TextField(
                      key: ValueKey(widget.id),
                      controller: _text,
                      focusNode: _focus,
                      autofocus: widget.autofocus,
                      keyboardType: TextInputType.none,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: _submit,
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _focus,
                    builder: (context, _) => _ScanButton(
                      label: widget.label,
                      secondary: ActionScope.secondaryScanOf(context),
                      // 스캐너 입력을 받는 중이면 바깥에 옅은 보라 테두리(안쪽이 아니라 — 글자·아이콘을 가리지 않게).
                      ready: _focus.hasFocus,
                      onTap: () {
                        _focus.requestFocus();
                        unawaited(_camera());
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // "바코드가 안 찍혀요"(재출력) — 단추 사이에 글줄로 끼어 있던 것을 스캔 줄 오른쪽 네모 단추로.
        if (widget.reprint case final targets?) ...[
          const SizedBox(width: 8),
          BarcodeReprintButton(id: widget.id, targets: targets, compact: true),
        ],
        if (ref.watch(envProvider) == PmartEnv.mock &&
            (widget.testValues.isNotEmpty || widget.testActions.isNotEmpty))
          PopupMenuButton<String>(
            key: ValueKey('${widget.id}-test'),
            tooltip: l10n.testScan,
            icon: const Icon(Icons.science_outlined),
            onSelected: (v) {
              final action = widget.testActions
                  .where((a) => 'action:${a.key}' == v)
                  .firstOrNull;
              if (action != null) {
                action.run();
              } else {
                _submit(v);
              }
            },
            itemBuilder: (_) => [
              for (final a in widget.testActions)
                PopupMenuItem(
                  key: ValueKey('${widget.id}-action-${a.key}'),
                  value: 'action:${a.key}',
                  child: Text(
                    a.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              if (widget.testActions.isNotEmpty && widget.testValues.isNotEmpty)
                const PopupMenuDivider(),
              for (final t in widget.testValues)
                PopupMenuItem(
                  key: ValueKey('${widget.id}-test-${t.value}'),
                  value: t.value,
                  child: Text('${t.label}  ${t.value}'),
                ),
            ],
          ),
      ],
    );
  }
}

/// 스캔 단추 — 다른 주 단추(FilledButton)와 같은 높이·모서리·글자(17·700), 가운데 아이콘 + 글자.
class _ScanButton extends StatelessWidget {
  const _ScanButton({
    required this.label,
    required this.ready,
    required this.onTap,
    this.secondary = false,
  });

  final String label;
  final bool ready;
  final VoidCallback onTap;

  /// 주 단추가 따로 있으면 옅은 보라 바탕·보라 글자(그림자 없음).
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelLarge;
    // 주 스캔 단추는 그라데이션 + 은은히 숨 쉬는 빛(지금 할 일, 사용자 2026-11-27)
    return Pressable(
      child: BreathingGlow(
        radius: 14,
        active: !secondary && !ready,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              if (ready)
                BoxShadow(
                  color: secondary
                      ? PdaColors.primary.withValues(alpha: 0.35)
                      : PdaColors.lilac,
                  spreadRadius: secondary ? 1.5 : 3,
                )
              else if (!secondary)
                BoxShadow(
                  color: PdaColors.primary.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Material(
            color: secondary ? PdaColors.lilac : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: secondary
                  ? null
                  : const BoxDecoration(gradient: PdaGradients.primary),
              child: InkWell(
                onTap: onTap,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 스캐너(총) 그림 대신 바코드 그림(사용자 2026-11-20).
                    BarcodeIcon(
                      size: 28,
                      color: secondary ? PdaColors.primary : Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text?.copyWith(
                          color: secondary ? PdaColors.dark : Colors.white,
                          fontSize: 19,
                          // 옅은 바탕은 대비가 약해 같은 크기도 작아 보인다 — 조금 크고 굵게(사용자 2026-11-20).
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 바코드 그림(세로 막대) — Material 아이콘에 맨 바코드가 없어 직접 그린다. 크기를 키워도 선이 또렷하다.
class BarcodeIcon extends StatelessWidget {
  const BarcodeIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _BarcodePainter(
        color ?? IconTheme.of(context).color ?? Colors.black,
      ),
    ),
  );
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.color);

  final Color color;

  /// 막대·틈 폭(단위) — 막대, 틈, 막대, 틈 … (실제 바코드처럼 굵기가 섞이게).
  static const _pattern = [2, 1, 1, 1, 3, 1, 1, 2, 2, 1, 1, 1, 3, 1, 1, 1, 2];

  @override
  void paint(Canvas canvas, Size size) {
    final total = _pattern.fold(0, (a, b) => a + b);
    final unit = size.width * 0.9 / total;
    final top = size.height * 0.18, bottom = size.height * 0.82;
    final paint = Paint()..color = color;
    var x = size.width * 0.05;
    for (final (i, w) in _pattern.indexed) {
      if (i.isEven) {
        canvas.drawRect(Rect.fromLTRB(x, top, x + w * unit, bottom), paint);
      }
      x += w * unit;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.color != color;
}
