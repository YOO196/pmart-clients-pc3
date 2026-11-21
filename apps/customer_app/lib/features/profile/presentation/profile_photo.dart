import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pmart_core/pmart_core.dart' show ProblemCode;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/notice.dart';
import '../domain/profile.dart';
import 'profile_avatar.dart';
import 'profile_controller.dart';

/// 프로필 사진을 어디서 가져올지.
enum ProfilePhotoPick { gallery, camera }

/// 사진첩·카메라에서 한 장. 고르지 않으면 null. 권한 거절은 [PlatformException].
typedef ProfilePhotoPicker = Future<Uint8List?> Function(ProfilePhotoPick pick);

/// 기기 사진첩·카메라(image_picker — 리뷰 사진과 같은 패키지). 시험은 이 provider 를 바꿔 끼운다.
final profilePhotoPickerProvider = Provider<ProfilePhotoPicker>(
  (_) => (pick) async {
    final f = await ImagePicker().pickImage(
      source: switch (pick) {
        ProfilePhotoPick.gallery => ImageSource.gallery,
        ProfilePhotoPick.camera => ImageSource.camera,
      },
      // 본인 사진이라 전면 카메라로 연다(기종에 따라 따르지 않을 수 있다).
      preferredCameraDevice: CameraDevice.front,
      // 자르기 화면에서 다시 512px 로 줄인다. 여기서는 디코딩 부담만 줄인다.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    return f == null ? null : await f.readAsBytes();
  },
);

/// 고른 사진을 동그랗게 맞춰 정사각형 512px PNG 로 만든다. 취소하면 null. 시험은 바꿔 끼운다.
typedef ProfilePhotoCropper = Future<Uint8List?> Function(
  BuildContext context,
  Uint8List bytes,
);

final profilePhotoCropperProvider = Provider<ProfilePhotoCropper>(
  (_) =>
      (context, bytes) => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<Uint8List>(
          fullscreenDialog: true,
          builder: (_) => ProfilePhotoCropScreen(bytes: bytes),
        ),
      ),
);

enum _PhotoAction { gallery, camera, restore, clear }

/// 내 정보 가운데 사진 + 카메라 표시(초안 G안, customer 0.15.0 BR-80). 누르면 시트 →
/// 앨범·카메라(→ 맞추기 → 올리기) / 로그인 계정 사진으로 되돌리기 / 기본 이미지로.
/// 서버가 확정한 뒤 프로필을 다시 읽어 그 사진만 보인다(실패하면 이전 사진 그대로).
class ProfilePhotoEditor extends ConsumerStatefulWidget {
  const ProfilePhotoEditor({
    super.key,
    required this.profile,
    this.providerLabel,
    this.radius = 44,
  });

  final Profile profile;

  /// 로그인 계정 이름(예: "Google"). 모르면 null.
  final String? providerLabel;
  final double radius;

  @override
  ConsumerState<ProfilePhotoEditor> createState() => _ProfilePhotoEditorState();
}

class _ProfilePhotoEditorState extends ConsumerState<ProfilePhotoEditor> {
  bool _busy = false;

  Future<void> _open() async {
    final l10n = AppLocalizations.of(context);
    final source = widget.profile.photoSource;
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      // 항목 4개 + 닫기가 기본 높이(화면 9/16)를 넘을 수 있어 내용 높이만큼 연다.
      isScrollControlled: true,
      builder: (context) => _PhotoSheet(
        // 이미 로그인 계정 사진이면 되돌리기를, 이미 기본 이미지면 기본으로를 숨긴다(모르면 둘 다 보인다).
        showRestore: source != ProfilePhotoSource.provider,
        showClear: source != ProfilePhotoSource.none,
        providerLabel: widget.providerLabel,
      ),
    );
    if (action == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ProfilePhotoChange change;
    switch (action) {
      case _PhotoAction.gallery || _PhotoAction.camera:
        final Uint8List? raw;
        try {
          raw = await ref.read(profilePhotoPickerProvider)(
            action == _PhotoAction.camera
                ? ProfilePhotoPick.camera
                : ProfilePhotoPick.gallery,
          );
        } on PlatformException catch (e) {
          messenger.notice(
            e.code.endsWith('_access_denied')
                ? l10n.infoPhotoPermission
                : l10n.infoPhotoFailed,
          );
          return;
        }
        if (raw == null || !mounted) return;
        final cropped = await ref.read(profilePhotoCropperProvider)(
          context,
          raw,
        );
        if (cropped == null || !mounted) return;
        change = ProfilePhotoUpload(cropped);
      case _PhotoAction.restore:
        change = const ProfilePhotoRestore();
      case _PhotoAction.clear:
        change = const ProfilePhotoClear();
    }
    setState(() => _busy = true);
    final outcome = await ref
        .read(profileProvider.notifier)
        .changePhoto(change);
    if (mounted) setState(() => _busy = false);
    messenger.notice(switch (outcome) {
      ProfileChangeApplied() => l10n.infoPhotoChanged,
      ProfileChangePending() ||
      ProfileChangeUnknown() => l10n.infoPhotoChecking,
      ProfileChangeRejected(code: ProblemCode.validationFailed) =>
        l10n.infoPhotoInvalid,
      ProfileChangeRejected(code: ProblemCode.invalidState) =>
        l10n.infoPhotoWithdrawPending,
      _ => l10n.infoPhotoFailed,
    }, key: const ValueKey('info-photo-notice'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final r = widget.radius;
    return Semantics(
      button: true,
      label: l10n.infoPhotoEdit,
      child: GestureDetector(
        key: const ValueKey('info-photo-edit'),
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : _open,
        child: SizedBox(
          width: r * 2 + 4,
          height: r * 2 + 4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              KeyedSubtree(
                key: const ValueKey('info-avatar'),
                child: ProfileAvatar(profile: widget.profile, radius: r),
              ),
              if (_busy)
                Container(
                  key: const ValueKey('info-photo-busy'),
                  width: r * 2,
                  height: r * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surface.withValues(alpha: 0.6),
                  ),
                  alignment: Alignment.center,
                  child: const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              // 카메라 표시(30·흰 바탕·옅은 테두리).
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surface,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  alignment: Alignment.center,
                  child: PmartLineIcon(
                    PmartLineIcons.camera,
                    size: 17,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoSheet extends StatelessWidget {
  const _PhotoSheet({
    required this.showRestore,
    required this.showClear,
    required this.providerLabel,
  });

  final bool showRestore;
  final bool showClear;
  final String? providerLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget act(
      _PhotoAction a,
      String key,
      PmartLineIcon icon,
      String title, {
      String? note,
      Color? color,
    }) => InkWell(
      key: ValueKey(key),
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).pop(a),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final sub = scheme.onSurfaceVariant;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                l10n.infoPhotoSheetTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            act(
              _PhotoAction.gallery,
              'photo-gallery',
              PmartLineIcon(PmartLineIcons.image, color: sub),
              l10n.infoPhotoGallery,
            ),
            act(
              _PhotoAction.camera,
              'photo-camera',
              PmartLineIcon(PmartLineIcons.camera, color: sub),
              l10n.infoPhotoCamera,
            ),
            if (showRestore)
              act(
                _PhotoAction.restore,
                'photo-restore',
                PmartLineIcon(PmartLineIcons.undo, color: sub),
                l10n.infoPhotoRestore,
                note: switch (providerLabel) {
                  final p? => l10n.infoPhotoRestoreNote(p),
                  null => l10n.infoPhotoRestoreNoteUnknown,
                },
              ),
            if (showClear)
              act(
                _PhotoAction.clear,
                'photo-clear',
                PmartLineIcon(PmartLineIcons.trash, color: scheme.tertiary),
                l10n.infoPhotoClear,
                color: scheme.tertiary,
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton.tonal(
                key: const ValueKey('photo-close'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: scheme.surfaceContainerHigh,
                  foregroundColor: scheme.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  l10n.infoPhotoClose,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 고른 사진을 원 안에 맞춘다(초안 G-2): 끌어서 옮기고 두 손가락으로 키우고 [돌리기]로 90°씩.
/// [완료]는 원을 감싼 정사각형을 [outputSize]px PNG 로 그려 돌려준다(계약: 앱이 자르고 줄여 2MB 이하로 보낸다).
class ProfilePhotoCropScreen extends StatefulWidget {
  const ProfilePhotoCropScreen({super.key, required this.bytes});

  final Uint8List bytes;

  static const outputSize = 512;

  @override
  State<ProfilePhotoCropScreen> createState() => _ProfilePhotoCropScreenState();
}

class _ProfilePhotoCropScreenState extends State<ProfilePhotoCropScreen> {
  ui.Image? _image;
  bool _failed = false;
  bool _exporting = false;

  /// 화면 px / 사진 px.
  double _scale = 0;
  double _baseScale = 1;

  /// 원 가운데에서 사진 가운데까지(화면 px).
  Offset _offset = Offset.zero;
  int _turns = 0;

  /// 원 지름(화면 px). 레이아웃에서 정한다.
  double _d = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Size get _turned {
    final i = _image!;
    return _turns.isOdd
        ? Size(i.height.toDouble(), i.width.toDouble())
        : Size(i.width.toDouble(), i.height.toDouble());
  }

  double get _minScale => _d / math.min(_turned.width, _turned.height);

  /// 원이 사진 밖으로 나가지 않게 크기·위치를 맞춘다.
  void _fit() {
    if (_image == null || _d <= 0) return;
    _scale = _scale.clamp(_minScale, _minScale * 6);
    final t = _turned;
    final mx = math.max(0.0, (t.width * _scale - _d) / 2);
    final my = math.max(0.0, (t.height * _scale - _d) / 2);
    _offset = Offset(_offset.dx.clamp(-mx, mx), _offset.dy.clamp(-my, my));
  }

  Future<void> _done() async {
    final image = _image;
    if (image == null || _d <= 0) return;
    setState(() => _exporting = true);
    const out = ProfilePhotoCropScreen.outputSize;
    final k = out / _d;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, out + 0.0, out + 0.0),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas
      ..translate(out / 2 + _offset.dx * k, out / 2 + _offset.dy * k)
      ..rotate(_turns * math.pi / 2)
      ..scale(_scale * k);
    canvas.drawImage(
      image,
      Offset(-image.width / 2, -image.height / 2),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(out, out);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    picture.dispose();
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _exporting = false;
        _failed = true;
      });
      return;
    }
    Navigator.of(context).pop(data.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = scheme.inverseSurface;
    final onInk = scheme.onInverseSurface;
    final barText = theme.textTheme.titleMedium?.copyWith(
      color: onInk,
      fontSize: 16,
    );
    return Scaffold(
      backgroundColor: ink,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('photo-crop-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.infoPhotoCropCancel, style: barText),
                  ),
                  Expanded(
                    child: Text(
                      l10n.infoPhotoCropTitle,
                      textAlign: TextAlign.center,
                      style: barText?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('photo-crop-done'),
                    onPressed: (_image == null || _exporting || _failed)
                        ? null
                        : _done,
                    child: Text(
                      l10n.infoPhotoCropDone,
                      style: barText?.copyWith(
                        color: PmartBrand.lavender,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  _d = math.min(300, math.min(c.maxWidth, c.maxHeight) - 48);
                  if (_failed) {
                    return Center(
                      child: Text(
                        l10n.infoPhotoInvalid,
                        key: const ValueKey('photo-crop-failed'),
                        style: TextStyle(color: onInk),
                      ),
                    );
                  }
                  final image = _image;
                  if (image == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  _fit();
                  return GestureDetector(
                    key: const ValueKey('photo-crop-area'),
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (_) => _baseScale = _scale,
                    onScaleUpdate: (d) => setState(() {
                      _scale = _baseScale * d.scale;
                      _offset += d.focalPointDelta;
                      _fit();
                    }),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CropPainter(
                              image: image,
                              scale: _scale,
                              offset: _offset,
                              turns: _turns,
                              diameter: _d,
                              dim: ink.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 22,
                          child: Text(
                            l10n.infoPhotoCropHint,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: onInk.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              height: 64,
              child: Center(
                child: TextButton.icon(
                  key: const ValueKey('photo-crop-rotate'),
                  onPressed: _image == null
                      ? null
                      : () => setState(() {
                          _turns = (_turns + 1) % 4;
                          _fit();
                        }),
                  icon: PmartLineIcon(
                    PmartLineIcons.refresh,
                    size: 20,
                    color: onInk,
                  ),
                  label: Text(
                    l10n.infoPhotoRotate,
                    style: TextStyle(color: onInk, fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.scale,
    required this.offset,
    required this.turns,
    required this.diameter,
    required this.dim,
  });

  final ui.Image image;
  final double scale;
  final Offset offset;
  final int turns;
  final double diameter;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas
      ..save()
      ..translate(center.dx + offset.dx, center.dy + offset.dy)
      ..rotate(turns * math.pi / 2)
      ..scale(scale);
    canvas.drawImage(
      image,
      Offset(-image.width / 2, -image.height / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    final circle = Rect.fromCircle(center: center, radius: diameter / 2);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(circle),
      Paint()..color = dim,
    );
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.scale != scale ||
      old.offset != offset ||
      old.turns != turns ||
      old.diameter != diameter ||
      old.dim != dim;
}
