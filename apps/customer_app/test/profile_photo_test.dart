// 내 정보 프로필 사진 바꾸기(customer 0.15.0 BR-80, 초안 G안).
// 시트(앨범·카메라·되돌리기·기본) → 맞추기 → 올리기. 서버가 확정한 뒤 다시 읽은 사진만 보이고, 결과 불명은 같은 키로 한 번 더.
import 'dart:ui' show ImageByteFormat, PictureRecorder, instantiateImageCodec;

import 'package:customer_app/features/profile/data/mock_profile_repository.dart';
import 'package:customer_app/l10n/gen/app_localizations.dart';
import 'package:customer_app/features/profile/data/profile_repository.dart';
import 'package:customer_app/features/profile/domain/profile.dart';
import 'package:customer_app/features/profile/presentation/profile_controller.dart';
import 'package:customer_app/features/profile/presentation/profile_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import 'support/app_harness.dart';

// 1×1 PNG(투명).
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

final _cropped = Uint8List.fromList([..._png, 0]);

class _Picks {
  final picks = <ProfilePhotoPick>[];
  final crops = <Uint8List>[];
  Uint8List? picked = _png;
  PlatformException? error;
  bool cancelCrop = false;

  List<Override> get overrides => [
    profilePhotoPickerProvider.overrideWithValue((pick) async {
      picks.add(pick);
      if (error case final e?) throw e;
      return picked;
    }),
    profilePhotoCropperProvider.overrideWithValue((context, bytes) async {
      crops.add(bytes);
      return cancelCrop ? null : _cropped;
    }),
    profilePollPolicyProvider.overrideWithValue((
      interval: Duration.zero,
      attempts: 3,
    )),
  ];
}

Future<void> _openInfo(WidgetTester t) async {
  await t.tap(find.text('마이페이지').last);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('my-login')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('login-kakao')));
  await t.pumpAndSettle();
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('my-info')));
  await t.pumpAndSettle();
}

Future<void> _sheet(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('info-photo-edit')));
  await t.pumpAndSettle();
}

Finder _avatar(String key) => find.descendant(
  of: find.byKey(const ValueKey('info-avatar')),
  matching: find.byKey(ValueKey(key)),
);

void main() {
  test('Profile.photoSource 를 읽는다(없으면 null)', () {
    Profile read(api.ProfilePhotoSourceEnum? s) => profileFromContract(
      api.Profile(accountId: 'a', version: 1, photoSource: s),
    );
    expect(
      read(api.ProfilePhotoSourceEnum.CUSTOM).photoSource,
      ProfilePhotoSource.custom,
    );
    expect(
      read(api.ProfilePhotoSourceEnum.NONE).photoSource,
      ProfilePhotoSource.none,
    );
    expect(
      read(api.ProfilePhotoSourceEnum.PROVIDER).photoSource,
      ProfilePhotoSource.provider,
    );
    expect(read(null).photoSource, isNull);
  });

  testWidgets('앨범 → 맞추기 → 올리기: 서버 확정 뒤 새 사진과 알림, 시트는 로그인 계정 사진이면 되돌리기를 숨긴다', (
    t,
  ) async {
    final profile = MockProfileRepository(latency: Duration.zero);
    final picks = _Picks();
    await t.pumpWidget(testApp(picks.overrides, profile: profile));
    await t.pumpAndSettle();
    await _openInfo(t);
    expect(_avatar('profile-avatar-default'), findsOneWidget);

    await _sheet(t);
    expect(find.text('프로필 사진'), findsWidgets);
    expect(find.byKey(const ValueKey('photo-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-restore')), findsNothing);
    expect(find.byKey(const ValueKey('photo-clear')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('photo-gallery')));
    await t.pumpAndSettle();
    expect(picks.picks, [ProfilePhotoPick.gallery]);
    expect(picks.crops.single, _png);
    expect(profile.photoChanges.single, isA<ProfilePhotoUpload>());
    expect((profile.photoChanges.single as ProfilePhotoUpload).bytes, _cropped);
    expect(find.text('프로필 사진을 바꿨어요'), findsOneWidget);
    expect(_avatar('profile-avatar-image'), findsOneWidget);
  });

  testWidgets('직접 올린 사진이면 되돌리기(로그인 계정 이름)·기본으로가 보이고, 기본으로 → 기본 아바타', (t) async {
    final profile = MockProfileRepository(latency: Duration.zero)
      ..photoSource = ProfilePhotoSource.custom
      ..imageBytes = _png
      ..profileImageUrl = '/api/v1/me/profile-image?v=c1';
    await t.pumpWidget(testApp(_Picks().overrides, profile: profile));
    await t.pumpAndSettle();
    await _openInfo(t);
    expect(_avatar('profile-avatar-image'), findsOneWidget);

    await _sheet(t);
    expect(find.byKey(const ValueKey('photo-restore')), findsOneWidget);
    expect(find.text('카카오 계정 사진을 써요'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('photo-clear')));
    await t.pumpAndSettle();
    expect(profile.photoChanges.single, isA<ProfilePhotoClear>());
    expect(profile.photoSource, ProfilePhotoSource.none);
    expect(_avatar('profile-avatar-default'), findsOneWidget);

    // 기본 이미지면 [기본 이미지로 바꾸기]를 숨긴다.
    await _sheet(t);
    expect(find.byKey(const ValueKey('photo-clear')), findsNothing);
    expect(find.byKey(const ValueKey('photo-restore')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('photo-close')));
    await t.pumpAndSettle();
    expect(profile.photoChanges, hasLength(1));
  });

  testWidgets('되돌리기 → 로그인 계정 사진이 다시 보인다', (t) async {
    final profile = MockProfileRepository(latency: Duration.zero)
      ..photoSource = ProfilePhotoSource.none
      ..providerImageBytes = _png;
    await t.pumpWidget(testApp(_Picks().overrides, profile: profile));
    await t.pumpAndSettle();
    await _openInfo(t);
    await _sheet(t);
    await t.tap(find.byKey(const ValueKey('photo-restore')));
    await t.pumpAndSettle();
    expect(profile.photoChanges.single, isA<ProfilePhotoRestore>());
    expect(find.text('프로필 사진을 바꿨어요'), findsOneWidget);
    expect(_avatar('profile-avatar-image'), findsOneWidget);
  });

  testWidgets('결과 불명은 같은 키로 한 번 더 보내고, 거절이면 이전 사진 그대로 + 실패 알림', (t) async {
    final profile = MockProfileRepository(latency: Duration.zero)
      ..photoFailure = const UnknownResultFailure();
    await t.pumpWidget(testApp(_Picks().overrides, profile: profile));
    await t.pumpAndSettle();
    await _openInfo(t);
    await _sheet(t);
    await t.tap(find.byKey(const ValueKey('photo-gallery')));
    await t.pumpAndSettle();
    expect(profile.photoKeys, hasLength(2));
    expect(profile.photoKeys.toSet(), hasLength(1));
    expect(find.text('프로필 사진을 바꿨어요'), findsOneWidget);

    // 거절(400 VALIDATION_FAILED) — 사진은 서버 값 그대로.
    profile.photoFailure = const ProblemFailure(
      Problem(status: 400, code: ProblemCode.validationFailed),
    );
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await _sheet(t);
    await t.tap(find.byKey(const ValueKey('photo-camera')));
    await t.pumpAndSettle();
    expect(profile.photoSource, ProfilePhotoSource.custom);
    expect(find.text('이 사진은 쓸 수 없어요. 다른 사진을 골라 주세요'), findsOneWidget);
  });

  testWidgets('고르기 취소·맞추기 취소는 아무것도 보내지 않고, 카메라 권한 거절은 안내', (t) async {
    final profile = MockProfileRepository(latency: Duration.zero);
    final picks = _Picks()..picked = null;
    await t.pumpWidget(testApp(picks.overrides, profile: profile));
    await t.pumpAndSettle();
    await _openInfo(t);
    await _sheet(t);
    await t.tap(find.byKey(const ValueKey('photo-gallery')));
    await t.pumpAndSettle();
    expect(picks.crops, isEmpty);

    picks
      ..picked = _png
      ..cancelCrop = true;
    await _sheet(t);
    await t.tap(find.byKey(const ValueKey('photo-gallery')));
    await t.pumpAndSettle();
    expect(picks.crops, hasLength(1));

    picks.error = PlatformException(code: 'camera_access_denied');
    await _sheet(t);
    await t.tap(find.byKey(const ValueKey('photo-camera')));
    await t.pumpAndSettle();
    expect(find.text('카메라·사진 권한을 허용해 주세요'), findsOneWidget);
    expect(profile.photoChanges, isEmpty);
  });

  testWidgets('맞추기 화면: [완료]는 512px 정사각형 PNG 를 돌려준다', (t) async {
    Uint8List? result;
    // 3×2 사진 — 원은 짧은 변에 맞춘다.
    final source = await t.runAsync(() async {
      final recorder = PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 30, 20),
        Paint()..color = const Color(0xFF6A4EE0),
      );
      final img = await recorder.endRecording().toImage(30, 20);
      final data = await img.toByteData(format: ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Uint8List>(
                MaterialPageRoute(
                  builder: (_) => ProfilePhotoCropScreen(bytes: source!),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    // 사진을 읽는 동안 돌아가는 표시가 있어 pumpAndSettle 대신 시간만큼 넘긴다.
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pump();
    await t.pumpAndSettle();
    expect(find.text('사진 맞추기'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('photo-crop-rotate')));
    await t.pump();
    await t.runAsync(() async {
      await t.tap(find.byKey(const ValueKey('photo-crop-done')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await t.pumpAndSettle();
    expect(result, isNotNull);
    final size = await t.runAsync(() async {
      final codec = await instantiateImageCodec(result!);
      final f = await codec.getNextFrame();
      return (f.image.width, f.image.height);
    });
    expect(size, (512, 512));
  });
}
