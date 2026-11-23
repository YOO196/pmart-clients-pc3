import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'features/address/presentation/address_screens.dart';
import 'features/address/presentation/postcode_screen.dart' show PostcodeResult;
import 'features/cart/presentation/cart_merge_screen.dart';
import 'features/start/presentation/start_controller.dart';
import 'features/coupons/presentation/coupon_screens.dart';
import 'features/wishlist/presentation/wishlist_screens.dart';
import 'features/withdrawal/presentation/withdrawal_screen.dart';
import 'features/start/presentation/start_screens.dart';
import 'features/start/presentation/terms_list_screen.dart';
import 'features/auth/domain/auth.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/cart/presentation/cart_screen.dart';
import 'features/checkout/presentation/delivery_select_screen.dart';
import 'features/checkout/presentation/order_sheet_screen.dart';
import 'features/claims/presentation/claims_screens.dart';
import 'features/claims/presentation/my_claims_screen.dart';
import 'features/catalog/domain/catalog.dart' show ProductTile;
import 'features/catalog/presentation/category_screen.dart';
import 'features/notifications/presentation/notifications_screens.dart';
import 'features/redelivery/presentation/redelivery_screens.dart';
import 'features/payment/presentation/payment_screen.dart';
import 'features/profile/presentation/phone_verification_screen.dart';
import 'features/profile/presentation/my_info_screen.dart';
import 'features/reviews/domain/reviews.dart'
    show ReviewEligibility, ReviewTarget;
import 'features/reviews/presentation/reviews_screens.dart';
import 'features/support/domain/faq.dart';
import 'features/support/presentation/chat_screen.dart';
import 'features/support/presentation/faq_screens.dart';
import 'features/support/presentation/inquiry_screens.dart';
import 'features/orders/presentation/my_screen.dart';
import 'features/profile/presentation/consents_screens.dart';
import 'features/orders/presentation/order_help_screen.dart';
import 'features/orders/presentation/orders_screens.dart';
import 'features/catalog/presentation/home_providers.dart' show SectionRef;
import 'features/catalog/presentation/home_screen.dart';
import 'features/catalog/presentation/section_items_screen.dart';
import 'features/catalog/presentation/product_detail_screen.dart';
import 'features/catalog/presentation/product_list_screen.dart';
import 'features/catalog/presentation/search_screen.dart';
import 'l10n/gen/app_localizations.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 라우트. 탭은 각자 내비게이션 스택을 가진다(탭을 오가도 검색어·스크롤이 남는다).
/// 상품 상세는 탭 위로 올린다. 로그인 리다이렉트·딥링크(알림 → 화면)는 로그인 단계에서 붙인다.
final routerProvider = Provider<GoRouter>((ref) {
  // 처음 실행 단계(환영·약관 → 로그인/둘러보기 → 주소)가 바뀌면 redirect 를 다시 본다.
  final startStep = ValueNotifier<StartStep>(ref.read(startStepProvider));
  ref.listen(startStepProvider, (_, s) => startStep.value = s);
  ref.onDispose(startStep.dispose);
  var resolved = false;
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: startStep,
    redirect: (_, state) {
      final step = startStep.value;
      if (step == StartStep.ready) resolved = true;
      return startRedirect(step, state.matchedLocation, resolved: resolved);
    },
    routes: [
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: StartRoutes.splash,
        builder: (_, _) => const StartSplashScreen(),
        routes: [
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'welcome',
            builder: (_, _) => const WelcomeScreen(),
          ),
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'entry',
            builder: (_, _) => const LoginScreen(entry: true),
          ),
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'address',
            builder: (_, _) => const StartAddressScreen(),
          ),
        ],
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '${StartRoutes.termsPrefix}:type/:version',
        builder: (_, state) => ConsentTermScreen(
          type: state.pathParameters['type']!,
          version: state.pathParameters['version']!,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _TabShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const HomeScreen(),
                routes: [
                  // 장바구니는 하단 탭에서 빼고 상단바에만(사용자 2026-11-21) — 홈 위에 올라오는 전체 화면.
                  // 아이콘·떠 있는 막대는 push(뒤로 가면 보던 화면), 주문서의 "장바구니로"는 go(홈 위 장바구니).
                  _slide(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'cart',
                    builder: (_, _) => const CartScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/categories',
                builder: (_, _) => const CategoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                // 하단 탭 "주문내역"(사용자 2026-11-21 "주문 내역을 하단바로") — 주문 상세 등은 그대로 전체 화면.
                path: '/orders',
                builder: (_, _) => const OrderListScreen(),
                routes: [
                  _slide(
                    parentNavigatorKey: rootNavigatorKey,
                    path: ':orderId',
                    builder: (_, state) => OrderDetailScreen(
                      orderId: state.pathParameters['orderId']!,
                    ),
                    routes: [
                      // 오배송 다시 배송비 결제(ADR-0065, order-orchestration 0.3.0).
                      _slide(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'redelivery-payments/:redeliveryPaymentId',
                        builder: (_, state) => RedeliveryPaymentScreen(
                          orderId: state.pathParameters['orderId']!,
                          redeliveryPaymentId:
                              state.pathParameters['redeliveryPaymentId']!,
                        ),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'cancel',
                        // 레퍼런스 9-1 4: 가운데 창 "주문을 취소할까요?"
                        pageBuilder: (_, state) => PmartDialogPage<void>(
                          key: state.pageKey,
                          child: CancelScreen(
                            orderId: state.pathParameters['orderId']!,
                          ),
                        ),
                      ),
                      GoRoute(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'reschedule',
                        // 레퍼런스 9-1 4: 예약시간 변경은 아래 시트
                        pageBuilder: (_, state) => PmartSheetPage<void>(
                          key: state.pageKey,
                          child: RescheduleScreen(
                            orderId: state.pathParameters['orderId']!,
                          ),
                        ),
                      ),
                      // 리뷰 요청 알림(REVIEW_REQUESTED) → 그 주문의 리뷰 쓰기(하나면 바로, 여럿이면 고르기).
                      _slide(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'review',
                        builder: (_, state) => OrderReviewEntryScreen(
                          orderId: state.pathParameters['orderId']!,
                        ),
                      ),
                      // 주문 문의하기 — "무엇을 도와드릴까요?"(레퍼런스 9-2 3-1): 배송 신고 종류 → 문의 남기기.
                      _slide(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'help',
                        builder: (_, state) => OrderHelpScreen(
                          orderId: state.pathParameters['orderId']!,
                        ),
                      ),
                      // 주문 단위 배송 현황 — 배송 ID 를 몰라도 지도부터 뜬다(BR-61).
                      _slide(
                        parentNavigatorKey: rootNavigatorKey,
                        path: 'tracking',
                        builder: (_, state) => OrderTrackingScreen(
                          orderId: state.pathParameters['orderId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/my',
                builder: (_, _) => const MyScreen(),
                routes: [
                  // 마이 → 주문내역은 밀려 들어오는 화면(사용자 2026-11-21 "마이페이지 항목 전부 애니메이션").
                  // 하단 탭 "주문내역"과 같은 화면, 뒤로 가면 마이.
                  _slide(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'orders',
                    builder: (_, _) => const OrderListScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/checkout/delivery',
        builder: (_, _) => const DeliverySelectScreen(),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/checkout',
        builder: (_, _) => const OrderSheetScreen(),
      ),
      // 주문서 → 할인쿠폰 고르기(order 0.18.0). 지금 고른 쿠폰 ID 를 넘겨 받고, 고른 결과(CouponPick)를 돌려준다.
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/checkout/coupons',
        // 레퍼런스 6-5 는 X 로 닫는 창 — 아래에서 올라오고 아래로 내려간다.
        pageBuilder: (_, state) => CupertinoPage<CouponPick>(
          key: state.pageKey,
          fullscreenDialog: true,
          child: CouponPickScreen(
            selected: state.extra is String ? state.extra! as String : null,
          ),
        ),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/payments/:draftId',
        builder: (_, state) =>
            PaymentScreen(draftId: state.pathParameters['draftId']!),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/deliveries/:deliveryId',
        // orderId 는 주문 상세에서 들어올 때만 붙는다(알림에서 열면 배송 정보만으로 그린다).
        builder: (_, state) => TrackingScreen(
          deliveryId: state.pathParameters['deliveryId']!,
          orderId: state.uri.queryParameters['orderId'],
        ),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/claims',
        builder: (_, _) => const MyClaimsScreen(),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/claims/:claimId',
        builder: (_, state) =>
            ClaimScreen(claimId: state.pathParameters['claimId']!),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/notifications',
        builder: (_, _) => const NotificationCenterScreen(),
        routes: [
          // 'settings' 를 ':notificationId' 보다 먼저 둔다.
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'settings',
            builder: (_, _) => const NotificationSettingsScreen(),
          ),
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: ':notificationId',
            builder: (_, state) => NotificationDetailScreen(
              notificationId: state.pathParameters['notificationId']!,
            ),
          ),
        ],
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/login',
        builder: (_, state) => LoginScreen(
          purpose: state.uri.queryParameters['purpose'] == 'checkout'
              ? LoginPurpose.checkout
              : LoginPurpose.general,
        ),
      ),
      // 주문서 로그인 뒤 병합 확인(SCR-CART-MERGE-001). extra = 로그인 전 비회원 cartId.
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/cart/merge',
        builder: (_, state) =>
            CartMergeScreen(guestCartId: state.extra! as String),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        // 휴대폰 번호 확인(OCTOMO, customer 0.9.0).
        path: '/me/phone-verification',
        builder: (_, _) => const PhoneVerificationScreen(),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/me/info',
        builder: (_, state) =>
            MyInfoScreen(signup: state.uri.queryParameters['from'] == 'signup'),
      ),
      // 약관 및 정책(로그인하지 않아도) — 본문은 /terms/{항목}/{버전}
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/me/terms',
        builder: (_, _) => const TermsListScreen(),
      ),
      // 찜한 상품(customer 0.13.0, ADR-0081)
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/me/wishlist',
        builder: (_, _) => const WishlistScreen(),
      ),
      // 쿠폰함(promotion 0.2.0 — 쿠폰 받기·사용 가능·지난 쿠폰, ADR-0082).
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/me/coupons',
        builder: (_, _) => const CouponBoxScreen(),
      ),
      // 회원 탈퇴(customer 0.12.0, ADR-0077): 안내·재인증·접수, 대기 중이면 상태·철회.
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/me/withdrawal',
        builder: (_, _) => const WithdrawalScreen(),
      ),
      // 로그인해 있는 고객의 재동의(CU-1 §3 — 주문 전 확인). 동의하면 true 로 돌아간다.
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/me/consents/reconsent',
        // 레퍼런스 13-9: 아래 시트(사용자 결정 2026-11-20)
        pageBuilder: (_, state) => PmartSheetPage<bool>(
          key: state.pageKey,
          child: const ReconsentScreen(),
        ),
      ),
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/addresses',
        builder: (_, _) => const AddressListScreen(),
        routes: [
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'new',
            // 처음 실행 주소 화면은 고른 검색 결과를 넘긴다.
            builder: (_, state) => AddressFormScreen(
              initial: state.extra is PostcodeResult
                  ? state.extra! as PostcodeResult
                  : null,
            ),
          ),
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'edit',
            builder: (_, _) => const AddressEditScreen(),
            routes: [
              // 레퍼런스 3-1 2-4: 주소 편집의 [수정] → 주소 상세(값 채움)
              _slide(
                parentNavigatorKey: rootNavigatorKey,
                path: ':addressId',
                builder: (_, state) => AddressFormScreen(
                  editAddressId: state.pathParameters['addressId'],
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/products',
        // 사용자 요청(2026-11-20): 카테고리를 누르면 오른쪽에서 밀려 들어오고, 뒤로 가면 오른쪽으로 빠진다.
        pageBuilder: (_, state) => CupertinoPage<void>(
          key: state.pageKey,
          child: ProductListScreen(
            categoryId: state.uri.queryParameters['categoryId'] ?? '',
            title: state.uri.queryParameters['title'],
            onSale: state.uri.queryParameters['onSale'] == 'true',
          ),
        ),
      ),
      // 홈 영역 "전체보기". 영역·홈 구성 버전은 홈에서 넘긴다(없으면 홈으로).
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/sections/:sectionId',
        redirect: (_, state) => state.extra is SectionRef ? null : '/',
        builder: (_, state) =>
            SectionItemsScreen(target: state.extra! as SectionRef),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/products/:productId',
        // 카드에서 오면 카드 값(이름·사진·가격)을 넘겨 상세 첫 프레임에 바로 그린다(백엔드 요청 2026-11-19 상세 속도 R1).
        // 사용자 요청(2026-11-20): 상품을 누르면 카테고리 목록처럼 오른쪽에서 밀려 들어오고, 뒤로 가면 오른쪽으로 빠진다.
        pageBuilder: (_, state) => CupertinoPage<void>(
          key: state.pageKey,
          child: ProductDetailScreen(
            productId: state.pathParameters['productId']!,
            preview: switch (state.extra) {
              final ProductTile t => t,
              _ => null,
            },
          ),
        ),
        routes: [
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'reviews',
            builder: (_, state) => ProductReviewsScreen(
              productId: state.pathParameters['productId']!,
            ),
          ),
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'review-photos',
            builder: (_, state) => ReviewPhotosScreen(
              productId: state.pathParameters['productId']!,
            ),
          ),
        ],
      ),
      // 고객센터: 메인 → 문의 남기기·내 문의(case-service inquiries). 문의 남기기는 주문·AI 상담에서 값을 넘겨 받을 수 있다.
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/support',
        builder: (_, _) => const SupportScreen(),
        routes: [
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'chat',
            builder: (_, _) => const ChatScreen(),
          ),
          // 자주 묻는 질문(customer-assistant 0.2.0). 검색어·분류는 쿼리로.
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'faqs',
            builder: (_, state) => FaqListScreen(
              q: state.uri.queryParameters['q'],
              category: state.uri.queryParameters['category'],
            ),
            routes: [
              _slide(
                parentNavigatorKey: rootNavigatorKey,
                path: ':faqId',
                builder: (_, state) => FaqDetailScreen(
                  faqId: state.pathParameters['faqId']!,
                  initial: state.extra is Faq ? state.extra! as Faq : null,
                ),
              ),
            ],
          ),
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'inquiries',
            builder: (_, _) => const InquiryListScreen(),
            routes: [
              _slide(
                parentNavigatorKey: rootNavigatorKey,
                path: 'new',
                builder: (_, state) => InquiryFormScreen(
                  args: switch (state.extra) {
                    final InquiryFormArgs a => a,
                    _ => InquiryFormArgs(
                      orderId: state.uri.queryParameters['orderId'],
                    ),
                  },
                ),
              ),
              _slide(
                parentNavigatorKey: rootNavigatorKey,
                path: ':inquiryId',
                builder: (_, state) => InquiryDetailScreen(
                  inquiryId: state.pathParameters['inquiryId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      // 리뷰 관리(리뷰 쓰기·내가 쓴 리뷰). 작성 화면은 대상(ReviewTarget)을 넘겨 받는다(없으면 리뷰 관리로).
      _slide(
        parentNavigatorKey: rootNavigatorKey,
        path: '/reviews',
        // ?tab=mine 이면 "내가 쓴 리뷰" 칸으로 연다(리뷰 쓰기 흐름의 [내가 쓴 리뷰], 초안 09-E).
        builder: (_, state) => ReviewManageScreen(
          initialMine: state.uri.queryParameters['tab'] == 'mine',
        ),
        routes: [
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'write',
            redirect: (_, state) =>
                state.extra is ReviewTarget ? null : '/reviews',
            builder: (_, state) =>
                ReviewWriteScreen(target: state.extra! as ReviewTarget),
          ),
          // 내가 쓴 리뷰 하나(수정·삭제 버튼). 자격(상품명 사본)은 목록에서 넘겨 받는다(없어도 연다).
          _slide(
            parentNavigatorKey: rootNavigatorKey,
            path: 'mine/:reviewId',
            builder: (_, state) => MyReviewScreen(
              reviewId: state.pathParameters['reviewId']!,
              eligibility: state.extra is ReviewEligibility
                  ? state.extra! as ReviewEligibility
                  : null,
            ),
            routes: [
              _slide(
                parentNavigatorKey: rootNavigatorKey,
                path: 'edit',
                redirect: (_, state) => state.extra is ReviewEditTarget
                    ? null
                    : '/reviews/mine/${state.pathParameters['reviewId']}',
                builder: (_, state) =>
                    ReviewEditScreen(target: state.extra! as ReviewEditTarget),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _TabShell extends StatelessWidget {
  const _TabShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 홈이 아닌 탭에서 뒤로 — 앱을 닫지 않고 홈 탭으로(애니메이션 없이, 사용자 2026-11-21). 탭 안에 올린 화면이 있으면 그것부터 닫힌다.
    return PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: [
            NavigationDestination(
              icon: const PmartLineIcon(PmartLineIcons.home),
              label: l10n.navHome,
            ),
            NavigationDestination(
              icon: const PmartLineIcon(PmartLineIcons.grid),
              label: l10n.navCategory,
            ),
            NavigationDestination(
              icon: const PmartLineIcon(PmartLineIcons.search),
              label: l10n.navSearch,
            ),
            NavigationDestination(
              icon: const PmartLineIcon(PmartLineIcons.receipt),
              label: l10n.navOrders,
            ),
            NavigationDestination(
              icon: const PmartLineIcon(PmartLineIcons.user),
              label: l10n.navMy,
            ),
          ],
        ),
      ),
    );
  }
}

/// 화면을 여는 경로(사용자 2026-11-21 "주문상세·마이페이지 항목 전부 들어가기·뒤로 애니메이션 한 쌍").
/// go_router 가 `builder:` 경로를 앱 종류 판별에 실패해 전환 없는 페이지(NoTransitionPage)로 만들고 있었다 —
/// 상품 화면처럼 CupertinoPage 로 오른쪽에서 밀려 들어오고 뒤로 가면 오른쪽으로 빠지게 한다(전체 화면 창은 아래에서).
/// 하단 탭 첫 화면·처음 실행 단계(`/start`)는 그대로(탭 전환·시작 화면 → 홈은 미끄러지지 않게).
GoRoute _slide({
  required String path,
  required GoRouterWidgetBuilder builder,
  GlobalKey<NavigatorState>? parentNavigatorKey,
  GoRouterRedirect? redirect,
  List<RouteBase> routes = const <RouteBase>[],
  String? name,
  bool fullscreenDialog = false,
}) => GoRoute(
  path: path,
  name: name,
  parentNavigatorKey: parentNavigatorKey,
  redirect: redirect,
  routes: routes,
  pageBuilder: (context, state) => CupertinoPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    fullscreenDialog: fullscreenDialog,
    child: builder(context, state),
  ),
);
