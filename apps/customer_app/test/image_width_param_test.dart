import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/shared/providers.dart';

/// product-content 0.3.0 서버 축소 이미지 `?w=`(240·480·720) — 백엔드 요청 2026-11-19 상세 속도 R3.
void main() {
  const img = '/api/v1/content-images/IMG-1';

  test('그릴 폭(물리 화소)에 맞는 가장 작은 값, 넘으면 720', () {
    expect(withImageWidth(img, 216), '$img?w=240');
    expect(withImageWidth(img, 240), '$img?w=240');
    expect(withImageWidth(img, 400), '$img?w=480');
    expect(withImageWidth(img, 1080), '$img?w=720');
  });

  test('콘텐츠 이미지가 아니거나 이미 쿼리가 있으면 그대로', () {
    expect(
      withImageWidth('https://cdn.example/a.jpg', 300),
      'https://cdn.example/a.jpg',
    );
    expect(withImageWidth('$img?w=480', 300), '$img?w=480');
    expect(withImageWidth(null, 300), isNull);
  });

  // 백엔드 요청 2026-11-20 review-photo-thumbnails(review 0.4.0).
  test('리뷰 사진도 축소 폭(?w=)을 붙인다 — 썸네일 240/480, 크게 보기 720', () {
    const photo = '/api/v1/review-photos/RP-1';
    expect(withImageWidth(photo, 216), '$photo?w=240');
    expect(withImageWidth(photo, 288), '$photo?w=480');
    expect(withImageWidth(photo, 720), '$photo?w=720');
    expect(withImageWidth('$photo?w=240', 720), '$photo?w=240');
  });

  // 백엔드 회신 2026-11-25 BR-99(storefront 0.16.0): 배너 그림 축소본 360·720·1080·1440 JPEG.
  test('배너 그림은 360·720·1080·1440 단계로 ?w= 를 붙인다', () {
    const banner = '/api/v1/storefront/banner-images/BIMG-1';
    expect(withImageWidth(banner, 300), '$banner?w=360');
    expect(withImageWidth(banner, 700), '$banner?w=720');
    expect(withImageWidth(banner, 1079), '$banner?w=1080');
    expect(withImageWidth(banner, 1200), '$banner?w=1440');
    expect(withImageWidth(banner, 3000), '$banner?w=1440');
    expect(withImageWidth('$banner?w=720', 1080), '$banner?w=720');
  });
}
