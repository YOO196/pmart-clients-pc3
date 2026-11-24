# customer_app 시험 메모리 점검 — 2026-11-23

- 누가: PC1 프론트(사용자 "9번해줘" → "이 시험 md 파일로 남겨줘")
- 도구: `tools/flutter_test_mem.ps1` — 시험 파일 하나씩, 그 파일의 시험 프로세스 트리 Private 메모리만 잰다. 3GB 또는 3분을 넘으면 그 트리만 끈다. 남은 실메모리 4GB 미만이면 시작하지 않는다.
- 실행(앱 폴더): `powershell -ExecutionPolicy Bypass -File ..\..\tools\flutter_test_mem.ps1 -Path test -MaxGB 3 -TimeoutSec 180 -Out build\test-mem-after.csv`
- 규칙(CLAUDE.md): 전체는 `--concurrency=1`, 평소엔 바뀐 기능의 시험 파일만. 끝나면 남은 `flutter_tester` 가 없는지 확인.

## 결과 요약
- 시험 파일 **92개 모두 pass**. 강제 종료(killed-mem·killed-time) 0개.
- 가장 큰 것 1.51GB(`test/tracking_test.dart`). 대부분 0.9~1.5GB.
- 걸린 시간 합 약 18분 17초. 끝난 뒤 남은 `flutter_tester` 0개.

## 고치기 전에 있던 문제 — `cart_screen_test.dart` 20GB
- 고치기 전 점검: `cart_screen_test.dart` 만 3GB 를 넘어 강제 종료(killed-mem 3.03GB·52초). 전체 시험을 함께 돌리면 `flutter_tester` 가 20GB 넘게 잡아 PC1 메모리가 바닥나 다른 세션의 build·vitest 가 깨졌다.
- 시험을 하나씩 재 보니(2.5GB·2분 제한) **"선택 품목이 없으면 선택 삭제·주문을 누를 수 없다"** 하나만 2.5GB 를 넘었다. 단계별 진단으로 "품목 선택 체크를 누른 뒤 첫 프레임이 끝나지 않음"까지 좁혔다.
- 원인(앱 코드): `lib/features/cart/presentation/cart_screen.dart` `_toggleSelect` 의 반복문이 반영 뒤 위젯의 `line.selected`(다시 그려지기 전의 옛 값)와 비교했다. 응답이 바로 오는 목(mock)에서는 같은 `SetSelected` 를 끝없이 다시 보내며 메모리가 늘었다. 실서버에서도 응답이 빠르면 같은 요청을 한 번 더 보낼 수 있었다.
- 고침: 장바구니 컨트롤러의 지금 값(서버 반영본)과 비교. 그 시험 1.27GB·8초로 통과.

## 파일별 결과 (큰 순)
| 파일 | 상태 | 최대 GB | 초 |
|---|---|---|---|
| `test/tracking_test.dart` | pass | 1.51 | 25 |
| `test/claims_test.dart` | pass | 1.49 | 25 |
| `test/chat_test.dart` | pass | 1.46 | 24 |
| `test/reviews_test.dart` | pass | 1.44 | 28 |
| `test/withdrawal_test.dart` | pass | 1.42 | 20 |
| `test/catalog_screens_test.dart` | pass | 1.40 | 19 |
| `test/redelivery_payment_test.dart` | pass | 1.40 | 17 |
| `test/review_report_test.dart` | pass | 1.40 | 14 |
| `test/faq_test.dart` | pass | 1.38 | 18 |
| `test/orders_reference_a_test.dart` | pass | 1.38 | 21 |
| `test/receipt_confirmation_test.dart` | pass | 1.38 | 16 |
| `test/return_fee_test.dart` | pass | 1.37 | 16 |
| `test/address_delete_test.dart` | pass | 1.36 | 19 |
| `test/checkout_contact_test.dart` | pass | 1.36 | 13 |
| `test/coupons_test.dart` | pass | 1.36 | 17 |
| `test/inquiry_photos_rating_test.dart` | pass | 1.36 | 11 |
| `test/logout_keep_address_test.dart` | pass | 1.36 | 12 |
| `test/order_detail_actions_test.dart` | pass | 1.36 | 16 |
| `test/account_restriction_test.dart` | pass | 1.35 | 11 |
| `test/auth_address_screens_test.dart` | pass | 1.35 | 16 |
| `test/cart_merge_test.dart` | pass | 1.35 | 15 |
| `test/consents_test.dart` | pass | 1.35 | 12 |
| `test/home_reference_c_test.dart` | pass | 1.35 | 17 |
| `test/inquiries_test.dart` | pass | 1.35 | 15 |
| `test/notifications_test.dart` | pass | 1.35 | 23 |
| `test/order_sheet_payment_test.dart` | pass | 1.35 | 13 |
| `test/orders_test.dart` | pass | 1.35 | 16 |
| `test/review_request_notice_test.dart` | pass | 1.35 | 13 |
| `test/address_map_test.dart` | pass | 1.34 | 12 |
| `test/cart_screen_test.dart` | pass | 1.34 | 19 |
| `test/delivery_issue_test.dart` | pass | 1.34 | 12 |
| `test/login_identity_test.dart` | pass | 1.34 | 13 |
| `test/order_preferences_test.dart` | pass | 1.34 | 12 |
| `test/payment_screens_test.dart` | pass | 1.34 | 12 |
| `test/phone_verification_test.dart` | pass | 1.34 | 13 |
| `test/recent_searches_test.dart` | pass | 1.34 | 11 |
| `test/review_extras_test.dart` | pass | 1.34 | 18 |
| `test/checkout_screens_test.dart` | pass | 1.33 | 13 |
| `test/delivery_phase_test.dart` | pass | 1.33 | 13 |
| `test/order_list_gap_test.dart` | pass | 1.33 | 12 |
| `test/page_transitions_test.dart` | pass | 1.33 | 14 |
| `test/ux_polish_test.dart` | pass | 1.33 | 10 |
| `test/wishlist_test.dart` | pass | 1.33 | 16 |
| `test/address_receiver_test.dart` | pass | 1.32 | 10 |
| `test/category_picks_test.dart` | pass | 1.32 | 11 |
| `test/home_popup_test.dart` | pass | 1.32 | 11 |
| `test/my_claims_test.dart` | pass | 1.32 | 11 |
| `test/profile_google_test.dart` | pass | 1.32 | 10 |
| `test/profile_photo_test.dart` | pass | 1.32 | 12 |
| `test/push_test.dart` | pass | 1.32 | 12 |
| `test/session_expiry_test.dart` | pass | 1.32 | 10 |
| `test/signup_abandon_test.dart` | pass | 1.32 | 10 |
| `test/start_flow_test.dart` | pass | 1.32 | 12 |
| `test/custom_tabs_test.dart` | pass | 1.31 | 10 |
| `test/discount_display_test.dart` | pass | 1.31 | 10 |
| `test/google_login_test.dart` | pass | 1.31 | 11 |
| `test/section_timer_test.dart` | pass | 1.31 | 9 |
| `test/terms_view_test.dart` | pass | 1.31 | 9 |
| `test/banner_auto_test.dart` | pass | 1.30 | 11 |
| `test/cart_min_order_test.dart` | pass | 1.30 | 9 |
| `test/home_out_of_area_test.dart` | pass | 1.30 | 9 |
| `test/home_refresh_test.dart` | pass | 1.30 | 10 |
| `test/home_tab_swipe_test.dart` | pass | 1.30 | 9 |
| `test/ranking_theme_test.dart` | pass | 1.30 | 9 |
| `test/order_sheet_note_renew_test.dart` | pass | 1.29 | 9 |
| `test/system_nav_bar_test.dart` | pass | 1.27 | 8 |
| `test/splash_promo_test.dart` | pass | 1.24 | 8 |
| `test/nutrition_allergen_test.dart` | pass | 1.21 | 7 |
| `test/payment_flow_test.dart` | pass | 1.20 | 7 |
| `test/product_tile_overflow_test.dart` | pass | 1.20 | 7 |
| `test/image_decode_size_test.dart` | pass | 1.19 | 7 |
| `test/notice_test.dart` | pass | 1.19 | 7 |
| `test/phone_number_formatter_test.dart` | pass | 1.19 | 7 |
| `test/review_photo_viewer_test.dart` | pass | 1.19 | 7 |
| `test/catalog_mapping_test.dart` | pass | 1.18 | 7 |
| `test/checkout_controller_test.dart` | pass | 1.18 | 7 |
| `test/cart_controller_test.dart` | pass | 1.17 | 7 |
| `test/checkout_api_test.dart` | pass | 1.15 | 7 |
| `test/naver_token_source_test.dart` | pass | 1.15 | 7 |
| `test/address_api_test.dart` | pass | 1.14 | 7 |
| `test/auth_api_test.dart` | pass | 1.14 | 7 |
| `test/cart_hidden_lines_test.dart` | pass | 1.11 | 7 |
| `test/auth_address_test.dart` | pass | 1.01 | 7 |
| `test/image_url_test.dart` | pass | 0.96 | 7 |
| `test/claim_steps_test.dart` | pass | 0.94 | 7 |
| `test/api_wiring_test.dart` | pass | 0.93 | 7 |
| `test/nutrition_filter_test.dart` | pass | 0.93 | 7 |
| `test/tracking_map_fit_test.dart` | pass | 0.93 | 7 |
| `test/guest_cart_test.dart` | pass | 0.87 | 7 |
| `test/kakao_token_source_test.dart` | pass | 0.85 | 7 |
| `test/image_width_param_test.dart` | pass | 0.84 | 7 |
| `test/claims_api_test.dart` | pass | 0.81 | 7 |
