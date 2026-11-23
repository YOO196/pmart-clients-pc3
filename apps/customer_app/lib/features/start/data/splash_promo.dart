import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;

/// 처음 로딩 화면 프로모션(storefront 0.9.0 배너 자리 SPLASH — 백엔드 요청서 2026-11-21 ①).
/// 서버에 지금 걸린 SPLASH 배너(정렬 순서 첫째). 없으면 null.
class SplashBannerRef {
  const SplashBannerRef({
    required this.bannerId,
    required this.imageUrl,
    this.endsAt,
  });

  final String bannerId;
  final String imageUrl;

  /// 편성 끝 시각(storefront 0.13.0 `Banner.endsAt`, UTC). null = 끝 없음.
  final DateTime? endsAt;
}

/// 기기에 받아 둔 로딩 화면 이미지(다음 실행에 바로 그린다 — 사용자 결정 2026-11-21 "다음 실행부터").
/// 같은 배너라도 이미지가 바뀌면(이미지 주소 = `/storefront/banner-images/{imageId}`) 새로 받는다(백엔드 요청 2026-11-21 R1).
class SplashPromo {
  const SplashPromo({
    required this.bannerId,
    required this.bytes,
    this.imageUrl,
    this.top,
    this.bottom,
    this.endsAt,
  });

  final String bannerId;
  final Uint8List bytes;

  /// 받아 둔 배너의 끝 시각(storefront 0.13.0). 지났으면 다음 실행에 그리지 않는다(백엔드 회신 2026-11-23 §2 —
  /// 서버에서 내려간 배너가 한 실행 더 보이던 것). null = 끝 없음(예전에 저장한 것 포함).
  final DateTime? endsAt;

  /// [now] 에 아직 보여도 되는지.
  bool liveAt(DateTime now) => endsAt == null || now.isBefore(endsAt!);

  /// 받은 이미지의 주소(이미지 ID 가 들어 있다). 예전에 저장한 것은 없다 → 다음에 다시 받는다.
  final String? imageUrl;

  /// 그림 위·아래 가장자리 색 — 화면이 그림보다 길면 남는 위·아래를 이 색으로 채운다(`contain`).
  final ui.Color? top;
  final ui.Color? bottom;
}

/// 그림 맨 위·맨 아래 줄의 평균 색(작게 풀어 계산). 풀지 못하면 (null, null).
Future<(ui.Color?, ui.Color?)> splashEdgeColors(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData();
    final w = image.width;
    final h = image.height;
    image.dispose();
    codec.dispose();
    if (data == null || w == 0 || h == 0) return (null, null);
    ui.Color row(int y) {
      var r = 0, g = 0, b = 0;
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        r += data.getUint8(i);
        g += data.getUint8(i + 1);
        b += data.getUint8(i + 2);
      }
      return ui.Color.fromARGB(255, r ~/ w, g ~/ w, b ~/ w);
    }

    return (row(0), row(h - 1));
  } on Object {
    return (null, null);
  }
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
        return SplashBannerRef(bannerId: id, imageUrl: url, endsAt: b.endsAt);
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
      final url = File('${d.path}/banner.url');
      final edge = File('${d.path}/banner.edge');
      final ends = File('${d.path}/banner.ends');
      if (!await id.exists() || !await img.exists()) return null;
      final bytes = await img.readAsBytes();
      if (bytes.isEmpty) return null;
      // 가장자리 색 "위,아래"(ARGB 정수) — 받을 때 계산해 둔 것. 없거나 깨졌으면 검정.
      final edges = switch (await edge.exists()
          ? (await edge.readAsString()).trim().split(',')
          : const <String>[]) {
        [final a, final b] => (
          int.tryParse(a) == null ? null : ui.Color(int.parse(a)),
          int.tryParse(b) == null ? null : ui.Color(int.parse(b)),
        ),
        _ => (null, null),
      };
      return SplashPromo(
        bannerId: (await id.readAsString()).trim(),
        bytes: bytes,
        imageUrl: await url.exists() ? (await url.readAsString()).trim() : null,
        top: edges.$1,
        bottom: edges.$2,
        endsAt: await ends.exists()
            ? DateTime.tryParse((await ends.readAsString()).trim())
            : null,
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
    await File('${d.path}/banner.url')
        .writeAsString(promo.imageUrl ?? '', flush: true);
    await File('${d.path}/banner.edge').writeAsString(
      '${promo.top?.toARGB32() ?? ''},${promo.bottom?.toARGB32() ?? ''}',
      flush: true,
    );
    await File(
      '${d.path}/banner.ends',
    ).writeAsString(promo.endsAt?.toUtc().toIso8601String() ?? '', flush: true);
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
  // 배너와 이미지가 둘 다 같을 때만 그대로 — 이미지만 바뀌어도 새로 받는다(백엔드 요청 2026-11-21 R1).
  if (kept != null &&
      kept.bannerId == now.bannerId &&
      kept.imageUrl == now.imageUrl) {
    // 그림은 같고 기간만 바뀌었으면 받지 않고 끝 시각만 고친다.
    if (kept.endsAt != now.endsAt) {
      await store.save(
        SplashPromo(
          bannerId: kept.bannerId,
          bytes: kept.bytes,
          imageUrl: kept.imageUrl,
          top: kept.top,
          bottom: kept.bottom,
          endsAt: now.endsAt,
        ),
      );
    }
    return;
  }
  try {
    final bytes = await source.download(now.imageUrl);
    if (bytes.isEmpty) return;
    // 로딩 화면은 그림을 다 보이고(contain) 남는 위·아래를 가장자리 색으로 — 받을 때 한 번 계산해 둔다.
    final (top, bottom) = await splashEdgeColors(bytes);
    await store.save(
      SplashPromo(
        bannerId: now.bannerId,
        bytes: bytes,
        imageUrl: now.imageUrl,
        top: top,
        bottom: bottom,
        endsAt: now.endsAt,
      ),
    );
  } on Object {
    return;
  }
}
