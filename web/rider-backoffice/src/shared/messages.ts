// 화면 문구(1차 한국어). 컴포넌트에 문구를 흩어 쓰지 않는다. 공통 문구는 @pmart/web-ui.
import { employeeLoginMessages, uiMessages } from '@pmart/web-ui';

export const messages = {
  appTitle: 'PMart 라이더',
  goHome: 'PMart 라이더 백오피스 홈으로',
  mockBadge: '목 데이터',
  ...uiMessages,

  nav: {
    session: '내 세션',
    login: '로그인',
  },

  /** 메뉴 묶음·하위 메뉴(뼈대 — 이름·순서는 PC 5 가 정해도 된다) */
  groups: {
    control: '관제',
    riders: '라이더',
    deliveries: '배송·배차',
    support: '지원센터',
  },
  menus: {
    riderMap: '라이더 관제',
    riders: '라이더 찾기',
    deliveries: '배송 찾기',
    cases: '접수 건',
  },

  /** RIDER_OPS·OPERATOR_ADMIN 이 아닌 역할 — 막지 않고 안내만(판정은 서버, API 마다 403) */
  noRiderRole: '라이더 운영(RIDER_OPS) 권한이 없어요. 서버가 허락하지 않는 화면은 "권한이 없습니다"로 보여요.',

  preparing: {
    title: '화면 준비 중',
    body: '이 메뉴의 화면은 아직 만들지 않았어요.',
    apiMissing: '서버 API 가 아직 없는 기능',
    apiReady: '서버 API 가 있는 기능(다음 차례에 화면을 만들어요)',
  },

  login: {
    title: '라이더 백오피스 로그인',
    mockAccounts: '목 계정으로 로그인(목 모드에는 Keycloak 이 없어요)',
  },
  employeeLogin: employeeLoginMessages,

  session: {
    title: '내 세션',
    signOut: '로그아웃',
    current: '서버 세션',
    sessionId: '세션 ID',
    subject: '운영자 ID',
    roles: '역할',
    centers: '센터',
    ssoNote: '로그아웃하면 같은 브라우저의 다른 백오피스도 다음에 비밀번호를 다시 물어요(직원 계정 로그인을 함께 써요).',
  },

  /** Problem code → 문구. 분기는 code 로만 한다. 없는 code 는 일반 문구 + code 표시. */
  problem: {
    FORBIDDEN: '권한이 없습니다.',
    VALIDATION_FAILED: '입력값을 확인해 주세요.',
    NOT_FOUND: '찾지 못했어요.',
    INVALID_STATE: '지금 상태에서는 할 수 없는 요청이에요. 새로 불러온 뒤 확인해 주세요.',
    VERSION_CONFLICT: '다른 사람이 먼저 바꿨어요. 새로 고침한 뒤 다시 해 주세요.',
    IDEMPOTENCY_CONFLICT: '같은 요청 번호로 다른 내용이 이미 처리됐어요. 새로 시작해 주세요.',
    RATE_LIMITED: '요청이 많아요. 잠시 후 다시 해 주세요.',
    INTERNAL_ERROR: '서버에서 처리하지 못했어요(서버 오류). 아래 문의 번호를 백엔드에 알려 주세요.',
    TOKEN_INVALID: '세션이 끝났어요. 다시 로그인해 주세요.',
    TOKEN_REUSED: '세션이 끝났어요. 다시 로그인해 주세요.',
    DEPENDENCY_UNAVAILABLE: '다른 서비스 응답을 받지 못해 처리하지 않았어요. 잠시 후 다시 해 주세요.',
  } as Readonly<Record<string, string>>,

  /** 검증 사유 code → 문구(없는 code 는 code 그대로) */
  reason: {
    REQUIRED: '필요한 값이 없어요',
    INVALID_FORMAT: '형식이 맞지 않아요',
    NOT_ALLOWED: '넣을 수 없는 값이에요',
  } as Readonly<Record<string, string>>,
} as const;
