import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../l10n/gen/app_localizations.dart';

/// 우편번호 검색에서 고른 주소. 배송 가능 판정은 서버가 [roadAddress] 로 한다(ADR-0023).
@immutable
class PostcodeResult {
  const PostcodeResult({
    required this.roadAddress,
    this.zoneNo,
    this.buildingName,
  });

  final String roadAddress;
  final String? zoneNo;
  final String? buildingName;

  @override
  String toString() => 'PostcodeResult(…)';
}

/// 다음(카카오) 우편번호 서비스 결과(JS `oncomplete` data)를 옮긴다. 도로명이 없으면 null.
PostcodeResult? postcodeFromJson(Map<String, Object?> data) {
  String? text(String key) => switch (data[key]) {
    final String v when v.trim().isNotEmpty => v.trim(),
    _ => null,
  };
  // 고객이 지번을 눌렀어도 판정은 도로명으로 하므로 도로명(없으면 자동 도로명)을 쓴다.
  final road = text('roadAddress') ?? text('autoRoadAddress');
  if (road == null) return null;
  return PostcodeResult(
    roadAddress: road,
    zoneNo: text('zonecode'),
    buildingName: text('buildingName'),
  );
}

/// 키 없이 쓰는 무료 웹 서비스. 결과는 앱으로만 넘기고 로그에 남기지 않는다.
const _postcodeHtml = '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>html,body,#wrap{margin:0;padding:0;width:100%;height:100%;}</style>
<script src="https://t1.kakaocdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
</head><body><div id="wrap"></div>
<script>
  // 2026 도메인·이름 변경(옛 주소는 2026-11-30 종료): t1.daumcdn.net → t1.kakaocdn.net, daum.Postcode → kakao.Postcode.
  // 옛 주소를 쓰면 검색 창 위에 개발자용 "도메인 종료 안내"가 고객에게 보였다(라이더앱 #63 과 같게).
  var Postcode = (window.kakao && kakao.Postcode) || daum.Postcode;
  new Postcode({
    oncomplete: function(data) {
      window.flutter_inappwebview.callHandler('onComplete', JSON.stringify(data));
    },
    // 서비스 공지·배너를 고객에게 보이지 않는다.
    banner: false,
    width: '100%', height: '100%'
  }).embed(document.getElementById('wrap'));
</script>
</body></html>
''';

/// SCR-ADDRESS 주소 검색. 고르면 [PostcodeResult] 로 닫힌다(취소는 null).
class PostcodeScreen extends StatefulWidget {
  const PostcodeScreen({super.key});

  @override
  State<PostcodeScreen> createState() => _PostcodeScreenState();
}

class _PostcodeScreenState extends State<PostcodeScreen> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addressSearchTitle)),
      body: _failed
          ? Center(child: Text(l10n.addressSearchFailed))
          : InAppWebView(
              initialData: InAppWebViewInitialData(
                data: _postcodeHtml,
                baseUrl: WebUri('https://postcode.pmart.local/'),
              ),
              onWebViewCreated: (controller) => controller.addJavaScriptHandler(
                handlerName: 'onComplete',
                callback: (List<dynamic> args) {
                  final raw = args.isEmpty ? null : args.first;
                  if (raw is! String) return;
                  final decoded = jsonDecode(raw);
                  if (decoded is! Map<String, Object?>) return;
                  final result = postcodeFromJson(decoded);
                  if (result != null && mounted) {
                    Navigator.of(context).pop(result);
                  }
                },
              ),
              onReceivedError: (_, request, _) {
                // 페이지 자체를 못 불러오면 안내한다(하위 리소스 실패는 무시).
                if ((request.isForMainFrame ?? false) && mounted) {
                  setState(() => _failed = true);
                }
              },
            ),
    );
  }
}
