import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;

/// 처음 로딩 화면 프로모션(storefront 0.9.0 배너 자리 SPLASH — 백엔드 요청서 2026-11-21 ①).
/// 서버에 지금 걸린 SPLASH 배너(정렬 순서 첫째). 없으면 null.
class SplashBannerRef {
  const SplashBannerRef({required this.bannerId, required this.imageUrl});

  final String bannerId;
  final String imageUrl;
}

/// 기기에 받아 둔 로딩 화면 이미지(다음 실행에 바로 그린다 — 사용자 결정 2026-11-21 "다음 실행부터").
class SplashPromo {
  const SplashPromo({required this.bannerId, required this.bytes});

  final String bannerId;
  final Uint8List bytes;
}

abstract interface class SplashBannerSource {
  /// `GET /storefront/banners?placement=SPLASH`(토큰 없음). 걸린 것이 없으면 null. 조회 실패는 던진다.
  Future<SplashBannerRef?> current();

  /// 이미지 본문(배너 이미지는 이미지 ID 마다 안 바뀐다 — 1년 캐시 가능).
  Future<Uint8List> download(String url);
}

final class ApiSplashBannerSource implements SplashBannerSource {
  ApiSplashBannerSource(this._dio, {required this.resolveUrl})
    : _api = sf.PmartApiStorefront(dio: _dio).getStorefrontApi();

  final Dio _dio;
  final sf.StorefrontApi _api;

  /// 상대 경로 이미지 주소를 게이트웨이 주소로.
  final String? Function(String url) resolveUrl;

  /// 받아 둘 최대 크기 — 넘으면 받지 않는다(로딩 화면은 지금 그림으로).
  static const maxBytes = 5 * 1024 * 1024;

  @override
  Future<SplashBannerRef?> current() async {
    final res = await _api.listBanners(placement: 'SPLASH');
    final items = [...?res.data?.items]
      ..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
    for (final b in items) {
      final id = b.bannerId;
      final url = b.imageUrl;
      if (id != null && url != null && url.isNotEmpty) {
        return SplashBannerRef(bannerId: id, imageUrl: url);
      }
    }
    return null;
  }

  @override
  Future<Uint8List> download(String url) async {
    final full = resolveUrl(url) ?? url;
    final res = await _dio.get<List<int>>(
      full,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data ?? const <int>[];
    if (data.isEmpty || data.length > maxBytes) {
      throw StateError('splash image size ${data.length}');
    }
    return Uint8List.fromList(data);
  }
}

/// 목 모드: 걸린 로딩 화면 배너 없음(지금 로딩 화면). 시험·캡처는 [banner]·[bytes] 를 넣는다.
final class MockSplashBannerSource implements SplashBannerSource {
  MockSplashBannerSource({this.banner, this.bytes});

  SplashBannerRef? banner;
  Uint8List? bytes;

  /// 다음 조회에 던질 실패(시험용).
  Object? failNext;
  final downloads = <String>[];

  @override
  Future<SplashBannerRef?> current() async {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
    return banner;
  }

  @override
  Future<Uint8List> download(String url) async {
    downloads.add(url);
    return bytes ?? Uint8List(0);
  }
}

/// 받아 둔 로딩 화면 이미지 저장소.
abstract interface class SplashPromoStore {
  Future<SplashPromo?> read();
  Future<void> save(SplashPromo promo);
  Future<void> clear();
}

/// 앱 지원 폴더의 `splash_promo/`(배너 ID 글 + 이미지 파일). 읽기 실패는 없는 것으로 본다(지금 로딩 화면).
final class FileSplashPromoStore implements SplashPromoStore {
  Future<Directory> _dir() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/splash_promo',
  );

  @override
  Future<SplashPromo?> read() async {
    try {
      final d = await _dir();
      final id = File('${d.path}/banner.id');
      final img = File('${d.path}/banner.img');
      if (!await id.exists() || !await img.exists()) return null;
      final bytes = await img.readAsBytes();
      if (bytes.isEmpty) return null;
      return SplashPromo(
        bannerId: (await id.readAsString()).trim(),
        bytes: bytes,
      );
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> save(SplashPromo promo) async {
    final d = await _dir();
    await d.create(recursive: true);
    // 이미지를 먼저 쓰고 ID 를 나중에 — 중간에 끊기면 ID 가 옛것이라 다음에 다시 받는다.
    await File('${d.path}/banner.img').writeAsBytes(promo.bytes, flush: true);
    await File('${d.path}/banner.id')
        .writeAsString(promo.bannerId, flush: true);
  }

  @override
  Future<void> clear() async {
    final d = await _dir();
    if (await d.exists()) await d.delete(recursive: true);
  }
}

final class MemorySplashPromoStore implements SplashPromoStore {
  MemorySplashPromoStore([this.promo]);

  SplashPromo? promo;

  @override
  Future<SplashPromo?> read() async => promo;

  @override
  Future<void> save(SplashPromo p) async => promo = p;

  @override
  Future<void> clear() async => promo = null;
}

/// 뒤에서 서버의 지금 SPLASH 배너에 맞춘다: 없으면 지우고, 받아 둔 것과 다르면 새로 받아 저장(다음 실행에 보인다).
/// 조회·받기 실패는 받아 둔 것을 그대로 둔다(서버가 "없다"고 한 것이 아니다).
Future<void> refreshSplashPromo(
  SplashBannerSource source,
  SplashPromoStore store,
) async {
  final SplashBannerRef? now;
  try {
    now = await source.current();
  } on Object {
    return;
  }
  if (now == null) {
    await store.clear();
    return;
  }
  final kept = await store.read();
  if (kept?.bannerId == now.bannerId) return;
  try {
    final bytes = await source.download(now.imageUrl);
    if (bytes.isEmpty) return;
    await store.save(SplashPromo(bannerId: now.bannerId, bytes: bytes));
  } on Object {
    return;
  }
}
