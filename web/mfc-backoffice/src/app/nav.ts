// 메뉴 묶음(handoff mfc-backoffice/2026-11-15-request-mfc-backoffice §2) — 모든 메뉴가 센터 하나(`/c/:mfcId/…`) 아래에 있다.
// 기능 목록은 §2-1(2026-11-15 백엔드 점검)을 옮겼다. 화면을 만들면 그 메뉴의 `ready` 를 true 로 바꾼다.
import { messages as m } from '../shared/messages';

export type MenuKey = keyof typeof m.menus;
export type GroupKey = keyof typeof m.groups;

export interface MenuItem {
  readonly key: MenuKey;
  /** 센터 아래 경로(`/c/:mfcId/<segment>`) */
  readonly segment: string;
  /** 화면을 만들었다(false 면 "준비 중") */
  readonly ready: boolean;
  /** 서버 API 가 있는 기능 */
  readonly apiReady: readonly string[];
  /** 서버 API 가 아직 없거나 계약만 있는 기능 */
  readonly apiMissing: readonly string[];
}

export interface MenuGroup {
  readonly key: GroupKey;
  readonly items: readonly MenuItem[];
}

export const navGroups: readonly MenuGroup[] = [
  {
    // 실시간 관제 — 홈(예외 처리함)·센터 대시보드. 2026-11-21 사용자 "레퍼런스(corap/mfc-admin) 구조 따오기" — 업무 흐름 묶음
    key: 'overview',
    items: [
      {
        key: 'ops',
        segment: 'ops',
        ready: true,
        apiReady: ['출하 약속 초과·임박(작업 promisedReadyAt)', '결품·파손 줄 수(fulfillment 결품 지표)', '피킹 파손 품질 사고', '인계 확인 필요 포장'],
        apiMissing: ['결품(SHORT) 건별 센터 목록', '출하 약속 임박·초과 서버 건수'],
      },
      {
        // 센터 대시보드(2026-11-21 사용자) — 오늘 숫자·14일 추이(기존 지표 API 만)
        key: 'dashboard',
        segment: 'dashboard',
        ready: true,
        apiReady: ['피킹 줄·결품 지표(fulfillment)', '결품 많은 상품(by-sku)', '정시 배송 지표(dispatch DD-4)', '끝나지 않은 작업', '작업자', '배송 현황(bff)'],
        apiMissing: [],
      },
      {
        // 센터 도면(2026-11-21 사용자) — 위에서 본 도면, 랙 → 칸별 상품, 작업자 → 정보·진행 중·예정 작업
        key: 'floor',
        segment: 'floor',
        ready: true,
        apiReady: ['칸 목록(상태·카테고리)', '칸별 재고(stock-units locationPrefix 0.33.0)', '작업자', '끝나지 않은 작업'],
        apiMissing: ['작업자 현재 위치(요청 mfc-backoffice/2026-11-21-backend-worker-floor-positions)', '칸 도면 좌표 대부분 미등록'],
      },
    ],
  },
  {
    // 출고 운영 — 작업 → 포장 인계 → 배송 → 배차 지연·실패 → 반납
    key: 'outbound',
    items: [
      {
        key: 'tasks',
        segment: 'tasks',
        ready: true,
        apiReady: ['작업 목록·상세', '작업 풀기', '포장 상세·인계 상태', '확인 필요 포장 목록·확인'],
        apiMissing: [],
      },
      {
        // 포장 인계 현황(bff 0.11.0, 2026-11-17 request-packing-handover — 보기만)
        key: 'packingHandover',
        segment: 'packing-handover',
        ready: true,
        apiReady: ['출고별 단계(출고요청·피킹중·패킹중·출고대기·인계)·포장별 인계·배송(보기만)'],
        apiMissing: [],
      },
      {
        key: 'deliveries',
        segment: 'deliveries',
        ready: true,
        apiReady: ['진행 중 배송(수행·배차·열린 사건)'],
        apiMissing: [],
      },
      {
        // 배차 지연(delivery-dispatch 0.12.0 — 2026-11-19 백엔드 요청 request-dispatch-delays)
        key: 'dispatchDelays',
        segment: 'dispatch-delays',
        ready: true,
        apiReady: ['배차 지연 배송(픽업 전, 지연 안내 난 것)', '배송 번호 묶음 조회', '배차 불가로 취소(claim 0.11.0 DC-1)'],
        apiMissing: [],
      },
      {
        key: 'dispatchFailures',
        segment: 'dispatch-failures',
        ready: true,
        apiReady: ['배차 실패 사건 목록·상세(보기만)'],
        apiMissing: [],
      },
      {
        // 반납 인증번호(delivery-execution 0.28.0 — 2026-11-19 PC 3, PDA 와 같은 API)
        key: 'returnHandovers',
        segment: 'return-handovers',
        ready: true,
        apiReady: ['반납 기다리는 회수·반납 배송과 인증번호', '새 번호 내기(잠김 풀기)'],
        apiMissing: [],
      },
    ],
  },
  {
    // 입고·재고 — 입고 → 이동·보충 → 재고 → 위치 → 품질
    key: 'inbound',
    items: [
      {
        key: 'inbound',
        segment: 'inbound',
        ready: true,
        apiReady: ['입고 작업 목록·상세', '품질검사·적치', '회수품 반입·조회·목록', '초기 보유 수령·센터별 목록', '공급 요청 만들기·수정·철회·조회·목록'],
        apiMissing: ['입고 예정(TRF) — 계약만'],
      },
      {
        key: 'moves',
        segment: 'moves',
        ready: true,
        apiReady: ['이동 지시 목록·상세', '이동 지시 만들기·취소'],
        apiMissing: [],
      },
      {
        key: 'inventory',
        segment: 'inventory',
        ready: true,
        apiReady: ['센터 전체 재고 목록', '상품별 재고', '재고 이력', 'LOT 추적', '위치·LOT 정정', '순환 실사 만들기·입력·승인·목록', '보충 기준', '출하 부적격 LOT'],
        apiMissing: [],
      },
      {
        // 상품 관리(2026-11-25 사용자 "재고탭에서 빼서 상품관리 탭으로 밖에 두자. 센터 취급물품에 대한 거") — 이 센터 취급 상품·본사 상품 불러오기
        key: 'products',
        segment: 'products',
        ready: true,
        apiReady: ['센터 상품 취급 ON/OFF·새 상품', '본사 상품 목록(product-service)', '취급 일괄 켜기'],
        apiMissing: [],
      },
      {
        key: 'locations',
        segment: 'locations',
        ready: true,
        apiReady: ['칸 목록·상세·등록·수정', '닫기·열기·폐지', '적치 후보'],
        apiMissing: [],
      },
      {
        key: 'quality',
        segment: 'quality',
        ready: true,
        apiReady: ['격리·해제 요청', '해제 승인(다른 관리자)', '폐기 요청·결정·실행', '회수품 검수', '판정·폐기·검수 목록', '품질 사고 목록·등록·닫기(0.6.0)'],
        apiMissing: ['품질 사고 고객 영향 접수 건(2차)'],
      },
    ],
  },
  {
    // 인력·센터 — 배정·작업자·운영 제한
    key: 'people',
    items: [
      {
        key: 'assignments',
        segment: 'assignments',
        ready: true,
        apiReady: ['배정 목록', '배정·재배정', '배정 추천 계산·확정·조회', '지난 배정 추천 목록'],
        apiMissing: [],
      },
      {
        key: 'workers',
        segment: 'workers',
        ready: true,
        apiReady: ['작업자 목록·상세', '등록·업무·자격·상태·속도 변경', '근무 목록·등록·취소', '휴게·일일크루 등록'],
        apiMissing: [],
      },
      {
        key: 'restrictions',
        segment: 'restrictions',
        ready: true,
        apiReady: ['운영 제한 목록·상세', '등록(승인 근거 필수)·해제'],
        apiMissing: [],
      },
    ],
  },
];

export const allMenus: readonly MenuItem[] = navGroups.flatMap((g) => g.items);

export const centerPath = (mfcId: string, segment = allMenus[0]!.segment) => `/c/${encodeURIComponent(mfcId)}/${segment}`;

/** 센터 관리자 앱을 쓰지 않는 계정: MFC_WORKER 만 있다(현장은 PDA 앱) */
export const isWorkerOnly = (roles: readonly string[]) => roles.length > 0 && roles.every((r) => r === 'MFC_WORKER');
