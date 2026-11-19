// 픽PDA 앱 아이콘 만들기(사용자 2026-11-20 로고 — 보라 P + 장바구니). 원본: tool/icon/pick_pda_icon.png
// 실행(이 앱 밖 임시 프로젝트에서 package:image 로): dart run gen_launcher_icon.dart <원본> <android/app/src/main/res>
// 원본은 투명 대신 검은 바탕에 둥근 사각이 그려져 있다 → 가장자리에서 이어진 검은 칸을 투명으로 바꾸고 둥근 사각만 잘라 쓴다.
// - mipmap-*/ic_launcher.png: 둥근 사각 그대로(모서리 투명) — Android 7 이하·적응형 아이콘 없는 런처.
// - mipmap-*/ic_launcher_foreground.png + mipmap-anydpi-v26/ic_launcher.xml: 적응형 아이콘. 런처가 모양(원·둥근 사각)을
//   잘라 쓰므로 투명 모서리를 안쪽 색으로 채운 정사각을 보이는 영역(108dp 중 가운데 72dp)에 꽉 채운다.
import 'dart:io';

import 'package:image/image.dart' as img;

bool _dark(img.Pixel p) => p.r + p.g + p.b < 90;

void main(List<String> args) {
  final raw = img.decodeImage(File(args[0]).readAsBytesSync())!.convert(numChannels: 4);
  final res = args[1];

  // 1) 가장자리에서 이어진 검은 칸(바깥 바탕)만 투명으로 — 그림 안의 진한 색은 건드리지 않는다.
  final w = raw.width, h = raw.height;
  final seen = List<bool>.filled(w * h, false);
  final stack = <int>[];
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = y * w + x;
    if (seen[i] || !_dark(raw.getPixel(x, y))) return;
    seen[i] = true;
    stack.add(i);
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  var minX = w, minY = h, maxX = 0, maxY = 0;
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    raw.setPixelRgba(x, y, 0, 0, 0, 0);
    push(x + 1, y);
    push(x - 1, y);
    push(x, y + 1);
    push(x, y - 1);
  }
  // 검은 바탕과 둥근 사각 사이 어두운 가장자리 한 줄도 투명으로(테두리에 검은 선이 남지 않게).
  final edge = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (raw.getPixel(x, y).a == 0) continue;
      final p = raw.getPixel(x, y);
      final nearHole = [for (final d in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) (x + d.$1, y + d.$2)]
          .any((q) => q.$1 >= 0 && q.$2 >= 0 && q.$1 < w && q.$2 < h && raw.getPixel(q.$1, q.$2).a == 0);
      if (nearHole && p.r + p.g + p.b < 450) edge.add(y * w + x);
    }
  }
  for (final i in edge) {
    raw.setPixelRgba(i % w, i ~/ w, 0, 0, 0, 0);
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (raw.getPixel(x, y).a == 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  final box = img.copyCrop(raw, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  final side = box.width > box.height ? box.width : box.height;
  final square = img.copyResize(box, width: side, height: side, interpolation: img.Interpolation.cubic);

  // 2) 적응형 전경: 투명 모서리 → 가운데 쪽으로 걸어가 처음 만나는 불투명 색으로 채운다.
  final filled = img.Image.from(square);
  final c = side / 2;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final here = square.getPixel(x, y);
      if (here.a > 250) {
        filled.setPixelRgba(x, y, here.r, here.g, here.b, 255);
        continue;
      }
      var fx = x.toDouble(), fy = y.toDouble();
      final dx = (c - x) / side * 4, dy = (c - y) / side * 4;
      img.Pixel p = square.getPixel(x, y);
      while (p.a <= 250) {
        fx += dx;
        fy += dy;
        p = square.getPixel(fx.round().clamp(0, side - 1), fy.round().clamp(0, side - 1));
      }
      filled.setPixelRgba(x, y, p.r, p.g, p.b, 255);
    }
  }
  // 둥근 사각의 밝은 테두리가 적응형 아이콘에 비치지 않게 바깥 5% 를 잘라 낸다(그림은 가운데에 있어 안 잘린다).
  final cut = (side * 0.05).round();
  final edgeless = img.copyCrop(filled, x: cut, y: cut, width: side - 2 * cut, height: side - 2 * cut);

  const dens = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
  dens.forEach((name, k) {
    final dir = '$res/mipmap-$name';
    final legacy = img.copyResize(square, width: (48 * k).round(), interpolation: img.Interpolation.average);
    File('$dir/ic_launcher.png').writeAsBytesSync(img.encodePng(legacy));
    final canvas = (108 * k).round(), inner = (72 * k).round();
    final fg = img.Image(width: canvas, height: canvas, numChannels: 4);
    final art = img.copyResize(edgeless, width: inner, interpolation: img.Interpolation.average);
    img.compositeImage(fg, art, dstX: (canvas - inner) ~/ 2, dstY: (canvas - inner) ~/ 2);
    File('$dir/ic_launcher_foreground.png').writeAsBytesSync(img.encodePng(fg));
  });
}
