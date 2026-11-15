// 목 서버 상태(메모리). 테스트마다 resetDb() 로 되돌린다.

export interface MockSession {
  readonly sessionId: string;
  readonly operatorId: string;
  readonly deviceId: string;
  refreshToken: string;
  readonly used: Set<string>;
  revoked: boolean;
  readonly issuedAt: string;
}

/** 직원 권한의 효력은 employee-auth-service 가 정본이다 — 목 로그인이 토큰에 싣는 값 */
export interface MockGrant {
  readonly roles: readonly string[];
  readonly centers: readonly string[];
}

/** 목 로그인 계정(로그인 화면의 버튼) */
export const mockLogins = [
  { operatorId: 'OP-sup-1', label: '센터 관리자(MFC 1곳)' },
  { operatorId: 'OP-sup-2', label: '센터 관리자(MFC 2곳)' },
  { operatorId: 'OP-wkr-1', label: '현장 작업자(MFC_WORKER)' },
  { operatorId: 'OP-admin-1', label: '운영 관리자(센터 없음)' },
] as const;

function seedGrants(): Array<[string, MockGrant]> {
  return [
    ['OP-sup-1', { roles: ['MFC_SUPERVISOR'], centers: ['MFC-BSN-01'] }],
    ['OP-sup-2', { roles: ['MFC_SUPERVISOR'], centers: ['MFC-BSN-01', 'MFC-SEL-01'] }],
    ['OP-wkr-1', { roles: ['MFC_WORKER'], centers: ['MFC-BSN-01'] }],
    ['OP-admin-1', { roles: ['OPERATOR_ADMIN'], centers: [] }],
  ];
}

export const db = {
  grants: new Map<string, MockGrant>(),
  /** 정지·퇴사(로그인 불가) 운영자 */
  suspended: new Set<string>(),
  sessions: new Map<string, MockSession>(),
  idempotent: new Map<string, { status: number; body: unknown }>(),
  seq: 100,
};

export function resetDb(): void {
  db.grants = new Map(seedGrants());
  db.suspended = new Set();
  db.sessions = new Map();
  db.idempotent = new Map();
  db.seq = 100;
}

resetDb();

export const nextSeq = () => (db.seq += 1);
export const timestamp = () => new Date().toISOString();
