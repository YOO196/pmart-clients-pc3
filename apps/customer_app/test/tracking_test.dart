import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_delivery_tracking/pmart_api_delivery_tracking.dart'
    as trk;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/data/orders_repository.dart';
import 'package:customer_app/features/orders/data/sse_parser.dart';
import 'package:customer_app/features/orders/domain/orders.dart';
import 'package:customer_app/features/orders/domain/tracking.dart';
import 'package:customer_app/features/orders/presentation/orders_screens.dart';
import 'package:customer_app/shared/order_status.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// SSE 본문을 조각으로 흘리는 어댑터. 요청과 본문 구독 취소 여부를 기록한다.
final class _SseAdapter implements HttpClientAdapter {
  _SseAdapter(this.chunks, {this.status = 200, this.endStream = true});

  final List<List<int>> chunks;
  final int status;
  final bool endStream;
  final requests = <RequestOptions>[];
  var bodyCancelled = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final c = StreamController<Uint8List>(onCancel: () => bodyCancelled = true);
    for (final ch in chunks) {
      c.add(Uint8List.fromList(ch));
    }
    if (endStream) unawaited(c.close());
    return ResponseBody(
      c.stream,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(HttpClientAdapter adapter) => createPmartDio(
  baseUrl: 'http://test.invalid/api/v1',
  sourceSystem: sourceSystem,
  tokens: TokenStore(MemoryKeyValueStore()),
  refresher: (_) async => null,
  adapter: adapter,
  delay: (_) async {},
);

Map<String, Object?> _etaJson({
  String stage = 'TO_CUSTOMER',
  String status = 'AVAILABLE',
}) => {
  'deliveryId': 'dlv-s2',
  'stage': stage,
  'dropEta': {
    'status': status,
    if (status == 'AVAILABLE') 'etaAt': '2026-10-24T03:20:00Z',
    if (status == 'AVAILABLE') 'remainingSeconds': 600,
  },
  'asOf': {'asOf': '2026-10-24T03:00:00Z', 'freshness': 'CURRENT'},
};

void main() {
  setUpAll(initPmartFormatting);

  group('4단계 대응(서버 상태만)', () {
    test('주문 상태별 단계. 결제 전·모르는 값은 확인 중(null)', () {
      final expected = <OrderStatus, TrackStep?>{
        OrderStatus.draft: null,
        OrderStatus.resourcePending: null,
        OrderStatus.paymentPending: null,
        OrderStatus.paymentUnknown: null,
        OrderStatus.confirmed: TrackStep.confirmed,
        OrderStatus.preparing: TrackStep.preparing,
        OrderStatus.partiallyHandedOver: TrackStep.preparing,
        OrderStatus.inDelivery: TrackStep.delivering,
        OrderStatus.partiallyDelivered: TrackStep.delivering,
        OrderStatus.completed: TrackStep.delivered,
        OrderStatus.cancelled: null,
        OrderStatus.expired: null,
        OrderStatus.unknown: null,
      };
      expect(expected.keys.toSet(), OrderStatus.values.toSet());
      for (final e in expected.entries) {
        expect(trackStepOfOrder(e.key), e.value, reason: '${e.key}');
      }
    });

    test('배송 상태별 단계. FAILED·CANCELLED·모르는 값은 단계 없음', () {
      final expected = <ShipmentState, TrackStep?>{
        ShipmentState.planned: TrackStep.confirmed,
        ShipmentState.preparing: TrackStep.preparing,
        ShipmentState.ready: TrackStep.preparing,
        ShipmentState.handedOver: TrackStep.delivering,
        ShipmentState.inDelivery: TrackStep.delivering,
        ShipmentState.delivered: TrackStep.delivered,
        ShipmentState.failed: null,
        ShipmentState.cancelled: null,
        ShipmentState.unknown: null,
      };
      expect(expected.keys.toSet(), ShipmentState.values.toSet());
      for (final e in expected.entries) {
        expect(trackStepOfShipment(e.key), e.value, reason: '${e.key}');
      }
    });

    test('배달 단계(stage)별. DONE 만으로는 배달 완료가 아니다', () {
      final expected = <DeliveryStage, TrackStep?>{
        DeliveryStage.unassigned: TrackStep.confirmed,
        DeliveryStage.toStore: TrackStep.confirmed,
        DeliveryStage.atStore: TrackStep.confirmed,
        DeliveryStage.toCustomer: TrackStep.delivering,
        DeliveryStage.atCustomer: TrackStep.delivering,
        DeliveryStage.done: null,
        DeliveryStage.unknown: null,
      };
      expect(expected.keys.toSet(), DeliveryStage.values.toSet());
      for (final e in expected.entries) {
        expect(trackStepOfStage(e.key), e.value, reason: '${e.key}');
      }
    });

    test('모르는 값만 있으면 확인 중, 단계를 앞당기지 않는다', () {
      expect(trackProgressOf(), const TrackProgress());
      expect(
        trackProgressOf(
          order: OrderStatus.unknown,
          shipment: ShipmentState.unknown,
          stage: DeliveryStage.unknown,
        ),
        const TrackProgress(),
      );
      expect(
        trackProgressOf(stage: DeliveryStage.done).step,
        isNull,
        reason: '종료(DONE)는 완료·실패·취소를 가르지 않는다',
      );
    });

    test('배달 완료는 배송 DELIVERED 또는 주문 COMPLETED 일 때만', () {
      expect(
        trackProgressOf(
          order: OrderStatus.inDelivery,
          shipment: ShipmentState.inDelivery,
          stage: DeliveryStage.done,
        ).step,
        TrackStep.delivering,
      );
      expect(
        trackProgressOf(shipment: ShipmentState.delivered).step,
        TrackStep.delivered,
      );
      expect(
        trackProgressOf(order: OrderStatus.completed).step,
        TrackStep.delivered,
      );
    });

    test('배송 실패·취소는 멈춤(단계 없음), 완료로 보이지 않는다', () {
      final failed = trackProgressOf(
        order: OrderStatus.inDelivery,
        shipment: ShipmentState.failed,
        stage: DeliveryStage.done,
      );
      expect(failed.halted, isTrue);
      expect(failed.step, isNull);
      expect(trackProgressOf(order: OrderStatus.cancelled).halted, isTrue);
    });

    test('PARTIALLY_* 는 부분 표시, 주문 전체 단계는 앞당기지 않는다', () {
      final p = trackProgressOf(order: OrderStatus.partiallyDelivered);
      expect(p.partial, isTrue);
      expect(p.step, TrackStep.delivering);
      final h = trackProgressOf(order: OrderStatus.partiallyHandedOver);
      expect(h.partial, isTrue);
      expect(h.step, TrackStep.preparing);
      // 이 배송이 끝났다는 서버 값이 있으면 이 배송은 완료로 보인다.
      expect(
        trackProgressOf(
          order: OrderStatus.partiallyDelivered,
          shipment: ShipmentState.delivered,
        ),
        const TrackProgress(step: TrackStep.delivered, partial: true),
      );
    });
  });

  group('SSE 파서', () {
    List<SseMessage> parse(String text) {
      final p = SseParser();
      return [
        for (final line in const LineSplitter().convert(text)) ?p.add(line),
      ];
    }

    test('빈 줄에서 내보내고, data 여러 줄은 줄바꿈으로 잇는다', () {
      final m = parse('event: ETA_UPDATED\nid: 7\ndata: {"a":\ndata: 1}\n\n');
      expect(m, hasLength(1));
      expect(m.single.event, 'ETA_UPDATED');
      expect(m.single.id, '7');
      expect(m.single.data, '{"a":\n1}');
    });

    test('주석·data 없는 메시지는 건너뛰고, id 는 다음 메시지로 이어진다', () {
      final m = parse(
        ': keep-alive\n\nid: 3\nevent: X\n\ndata: a\n\ndata:b\r\n\r\n',
      );
      expect(m.map((e) => e.data), ['a', 'b']);
      expect(m.map((e) => e.id), ['3', '3']);
      expect(m.first.event, isNull, reason: 'data 없는 메시지의 event 는 버린다');
    });

    test('마지막 빈 줄이 없으면 내보내지 않는다(끊긴 메시지)', () {
      expect(parse('data: half'), isEmpty);
    });

    test('StreamEvent 변환: 계약 값만, 읽을 수 없으면 unknown', () {
      SseMessage msg(Object? body) =>
          SseMessage(data: jsonEncode(body), id: '9');
      final eta = trackingEventFromSse(
        'dlv-s2',
        msg({
          'id': '10',
          'type': 'ETA_UPDATED',
          'deliveryId': 'dlv-s2',
          'sentAt': '2026-10-24T03:00:00Z',
          'eta': _etaJson(),
        }),
      );
      expect(eta.type, TrackingEventType.etaUpdated);
      expect(eta.id, '10');
      expect(eta.eta?.stage, DeliveryStage.toCustomer);
      expect(eta.eta?.remainingSeconds, 600);

      final stage = trackingEventFromSse(
        'dlv-s2',
        msg({
          'type': 'STAGE_CHANGED',
          'deliveryId': 'dlv-s2',
          'sentAt': '2026-10-24T03:00:00Z',
          'stage': 'AT_CUSTOMER',
        }),
      );
      expect(stage.type, TrackingEventType.stageChanged);
      expect(stage.id, '9', reason: '본문에 id 가 없으면 SSE id');
      expect(stage.stage, DeliveryStage.atCustomer);

      expect(
        trackingEventFromSse(
          'd',
          msg({
            'type': 'RIDER_MOVED',
            'deliveryId': 'd',
            'sentAt': '2026-10-24T03:00:00Z',
          }),
        ).type,
        TrackingEventType.unknown,
      );
      expect(
        trackingEventFromSse('d', const SseMessage(data: 'not json')).type,
        TrackingEventType.unknown,
      );
    });
  });

  group('API 구독', () {
    test('스트림 응답을 줄로 읽어 이벤트로, Accept·Last-Event-ID 를 보낸다', () async {
      final text =
          ': ping\n\n'
          'id: 1\nevent: ETA_UPDATED\ndata: ${jsonEncode({'type': 'ETA_UPDATED', 'deliveryId': 'dlv-s2', 'sentAt': '2026-10-24T03:00:00Z', 'eta': _etaJson()})}\n\n'
          'id: 2\nevent: STREAM_END\ndata: {"type":"STREAM_END","deliveryId":"dlv-s2","sentAt":"2026-10-24T03:30:00Z"}\n\n';
      final bytes = utf8.encode(text);
      // 줄·글자 중간에서 잘라 보낸다.
      final adapter = _SseAdapter([
        bytes.sublist(0, 7),
        bytes.sublist(7, 61),
        bytes.sublist(61),
      ]);
      final repo = ApiOrdersRepository(_dio(adapter));
      final events = await repo.track('dlv-s2', lastEventId: '0').toList();

      expect(events.map((e) => e.type), [
        TrackingEventType.etaUpdated,
        TrackingEventType.streamEnd,
      ]);
      expect(events.first.eta?.status, EtaStatus.available);
      final req = adapter.requests.single;
      expect(req.uri.path, '/api/v1/deliveries/dlv-s2/stream');
      expect(req.headers['Accept'], 'text/event-stream');
      expect(req.headers['Last-Event-ID'], '0');
      expect(req.responseType, ResponseType.stream);
    });

    test('구독을 취소하면 연결 본문도 닫힌다', () async {
      final adapter = _SseAdapter([
        utf8.encode(
          'data: {"type":"HEARTBEAT","deliveryId":"d","sentAt":"2026-10-24T03:00:00Z"}\n\n',
        ),
      ], endStream: false);
      final repo = ApiOrdersRepository(_dio(adapter));
      final first = Completer<TrackingEvent>();
      final sub = repo.track('d').listen(first.complete);
      expect((await first.future).type, TrackingEventType.heartbeat);
      await sub.cancel();
      expect(adapter.bodyCancelled, isTrue);
    });

    test('연결 실패는 PmartFailure 오류(배송 실패 아님)', () async {
      final adapter = _SseAdapter(const [], status: 503);
      final repo = ApiOrdersRepository(_dio(adapter));
      await expectLater(repo.track('d').toList(), throwsA(isA<PmartFailure>()));
    });
  });

  group('배송현황 화면', () {
    Future<void> openTracking(
      WidgetTester t,
      MockOrdersRepository orders, {
      required String orderId,
      required String deliveryId,
    }) async {
      t.view
        ..physicalSize = const Size(800, 2400)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(testApp(const [], orders: orders));
      await t.pumpAndSettle();
      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-login')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-orders')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('order-$orderId')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(ValueKey('track-$deliveryId')));
      await t.tap(find.byKey(ValueKey('track-$deliveryId')));
      await t.pumpAndSettle();
      expect(find.byType(TrackingScreen), findsOneWidget);
    }

    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('예약배달: 서버 도착 구간·취소/시간 변경 진입, 단계는 주문 확인', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero);
      await openTracking(
        t,
        orders,
        orderId: 'order-seed-4',
        deliveryId: 'dlv-1',
      );
      expect(key('track-reserved'), findsOneWidget);
      // 서버 도착 구간(18:00~19:00, 서울 시각)을 그대로 보인다.
      expect(
        t.widget<Text>(key('track-reserved')).data,
        allOf(contains('6:00'), contains('7:00'), endsWith('예약')),
      );
      expect(key('track-cancel'), findsOneWidget);
      expect(key('track-reschedule'), findsOneWidget);
      expect(key('track-step-current-confirmed'), findsOneWidget);
      expect(key('track-step-current-delivered'), findsNothing);

      // 시간 변경 화면에 다녀오는 동안 연결을 닫고, 돌아오면 다시 붙는다.
      await t.tap(key('track-reschedule'));
      await t.pumpAndSettle();
      expect(orders.openTrackCount, 0);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(orders.openTrackCount, 1);
    });

    testWidgets('실시간 이벤트로 갱신하고, 종료(DONE)만으로는 배달 완료가 아니다', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero);
      await openTracking(
        t,
        orders,
        orderId: 'order-seed-1',
        deliveryId: 'dlv-s2',
      );
      expect(orders.openTrackCount, 1);
      expect(key('track-step-current-delivering'), findsOneWidget);
      expect(key('track-partial'), findsOneWidget);
      expect(key('track-live-fallback'), findsNothing);

      orders.emitTracking(
        'dlv-s2',
        TrackingEvent(
          type: TrackingEventType.etaUpdated,
          id: '1',
          eta: etaFromContract(
            'dlv-s2',
            trk.DeliveryEta.fromJson(_etaJson(stage: 'AT_CUSTOMER')),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('곧 도착해요'), findsOneWidget);

      // 단계만 DONE 으로 바뀜: 주문을 다시 묻지만 배송은 아직 IN_DELIVERY → 완료 아님.
      orders.emitTracking(
        'dlv-s2',
        const TrackingEvent(
          type: TrackingEventType.stageChanged,
          stage: DeliveryStage.done,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('배송이 끝났어요'), findsOneWidget);
      expect(key('track-step-current-delivered'), findsNothing);
      expect(key('track-step-current-delivering'), findsOneWidget);

      // 서버가 배송 DELIVERED 를 주고 스트림을 끝내면 그때 완료.
      final o = orders.orderJson('order-seed-1')!;
      orders.overrides['order-seed-1'] = {
        ...o,
        'status': 'COMPLETED',
        'shipments': [
          for (final s
              in (o['shipments']! as List).cast<Map<String, Object?>>())
            {...s, 'state': 'DELIVERED'},
        ],
      };
      orders.emitTracking(
        'dlv-s2',
        const TrackingEvent(type: TrackingEventType.streamEnd),
      );
      await orders.dropTracking('dlv-s2');
      await t.pumpAndSettle();
      expect(key('track-step-current-delivered'), findsOneWidget);
      expect(
        key('track-live-fallback'),
        findsNothing,
        reason: '정상 종료는 끊김이 아니다',
      );
      expect(orders.trackOpens, 1, reason: '종료 뒤 다시 붙지 않는다');
    });

    testWidgets('구독 실패 → 주기 조회 안내, 재연결되면 안내를 걷는다', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero)
        ..trackFails = true;
      await openTracking(
        t,
        orders,
        orderId: 'order-seed-1',
        deliveryId: 'dlv-s2',
      );
      expect(key('track-live-fallback'), findsOneWidget);
      expect(find.text('실시간 연결이 끊겨 주기적으로 확인하고 있어요'), findsOneWidget);
      // 끊김은 배송 실패·완료가 아니다.
      expect(find.text('배송하지 못함'), findsNothing);
      expect(key('track-step-current-delivered'), findsNothing);
      expect(key('track-step-current-delivering'), findsOneWidget);

      orders.trackFails = false;
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(orders.openTrackCount, 1);
      expect(key('track-live-fallback'), findsNothing);
    });

    testWidgets('구독·위치 조회가 모두 실패해도 배송 실패·완료로 보이지 않는다', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero)
        ..trackFails = true
        ..etaFails = true;
      await openTracking(
        t,
        orders,
        orderId: 'order-seed-1',
        deliveryId: 'dlv-s2',
      );
      expect(key('eta-failed'), findsOneWidget);
      expect(key('track-live-fallback'), findsOneWidget);
      expect(find.text('배송하지 못함'), findsNothing);
      expect(find.text('배달 완료'), findsNothing);
    });

    testWidgets('화면을 닫으면 구독을 닫는다, 앱이 가려져도 닫는다', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero);
      await openTracking(
        t,
        orders,
        orderId: 'order-seed-1',
        deliveryId: 'dlv-s2',
      );
      expect(orders.openTrackCount, 1);

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump();
      expect(orders.openTrackCount, 0);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(orders.openTrackCount, 1);

      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.byType(TrackingScreen), findsNothing);
      expect(orders.openTrackCount, 0);
    });
  });
}
