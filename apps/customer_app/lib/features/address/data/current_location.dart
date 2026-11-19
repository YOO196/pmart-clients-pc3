import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// 휴대폰 현재 위치 한 번 읽은 결과. 좌표는 로그·저장에 남기지 않는다(주소 찾기 한 번에만 쓴다).
@immutable
sealed class LocationFix {
  const LocationFix();
}

final class LocationFound extends LocationFix {
  const LocationFound(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  String toString() => 'LocationFound(…)';
}

/// 휴대폰 위치 기능이 꺼져 있다.
final class LocationServiceOff extends LocationFix {
  const LocationServiceOff();
}

/// 위치 권한 거부. [forever] 면 OS 가 다시 묻지 않는다 — 설정에서 바꿔야 한다.
final class LocationDenied extends LocationFix {
  const LocationDenied({this.forever = false});

  final bool forever;
}

/// 시간 안에 위치를 못 받음 등.
final class LocationUnavailable extends LocationFix {
  const LocationUnavailable();
}

/// "현재 위치로 찾기"의 위치 원천. 기기는 geolocator(Android 위치 서비스), 목·시험은 고정 좌표.
abstract interface class CurrentLocationSource {
  /// 권한이 없으면 묻는다(OS 창). 위치기반서비스 약관 동의 뒤에만 부른다.
  Future<LocationFix> current();

  /// 앱 설정(권한) 또는 휴대폰 위치 설정을 연다.
  Future<void> openSettings({required bool locationService});
}

final class DeviceCurrentLocationSource implements CurrentLocationSource {
  const DeviceCurrentLocationSource();

  @override
  Future<LocationFix> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationServiceOff();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.deniedForever:
          return const LocationDenied(forever: true);
        case LocationPermission.denied || LocationPermission.unableToDetermine:
          return const LocationDenied();
        case LocationPermission.whileInUse || LocationPermission.always:
          break;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationFound(p.latitude, p.longitude);
    } on Object {
      // 시간 초과·단말 오류 — 주소 검색으로 안내한다(좌표를 지어내지 않는다).
      return const LocationUnavailable();
    }
  }

  @override
  Future<void> openSettings({required bool locationService}) async {
    if (locationService) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}

/// ⚠ 목·시험용. 기본은 서울 송파구 올림픽로 300 근처.
final class MockCurrentLocationSource implements CurrentLocationSource {
  MockCurrentLocationSource({
    this.fix = const LocationFound(37.5126, 127.1025),
  });

  LocationFix fix;
  int calls = 0;
  final settingsOpened = <bool>[];

  @override
  Future<LocationFix> current() async {
    calls++;
    return fix;
  }

  @override
  Future<void> openSettings({required bool locationService}) async =>
      settingsOpened.add(locationService);
}
