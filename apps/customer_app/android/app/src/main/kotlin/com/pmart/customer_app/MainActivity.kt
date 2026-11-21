package com.pmart.customer_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 네이버 로그인 SDK 가 FragmentActivity 를 요구한다(flutter_naver_login 2.1).
class MainActivity : FlutterFragmentActivity() {
    // 개발 도구(flutter run·IDE 디버그)는 "디버거가 붙을 때까지 main 을 시작하지 말라"는 start-paused 를 실행 정보에 붙인다.
    // 최근 앱 목록·앱 다시 만들기는 그 실행 정보를 그대로 다시 쓰는데, 그때는 디버거가 없어 첫 화면을 영영 못 그리고
    // 보라색 시작 화면에 멈춘다(2026-11-21 실기기 — VM 서비스 pause_isolates_on_start=true·PauseStart 로 확인).
    // 처음 켤 때만 따르고, 다시 열 때는 뗀다. 정식(release) 빌드는 원래 이 값을 쓰지 않는다.
    override fun onCreate(savedInstanceState: Bundle?) {
        val relaunched = savedInstanceState != null ||
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (relaunched) intent.removeExtra("start-paused")
        super.onCreate(savedInstanceState)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 휴대폰 번호 확인(OCTOMO): 문자 앱을 받는 번호·본문을 채워 연다. 보내기는 고객이 누른다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pmart/sms")
            .setMethodCallHandler { call, result ->
                if (call.method != "compose") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val to = call.argument<String>("to") ?: ""
                val body = call.argument<String>("body") ?: ""
                val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$to"))
                    .putExtra("sms_body", body)
                try {
                    startActivity(intent)
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
