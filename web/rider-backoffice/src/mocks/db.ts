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
  { operatorId: 'OP-rops-1', label: '라이더 운영(RIDER_OPS)' },
  { operatorId: 'OP-admin-1', label: '운영 관리자(OPERATOR_ADMIN)' },
  { operatorId: 'OP-cs-1', label: '고객센터 상담원(CS_AGENT)' },
] as const;

function seedGrants(): Array<[string, MockGrant]> {
  return [
    ['OP-rops-1', { roles: ['RIDER_OPS'], centers: [] }],
    ['OP-admin-1', { roles: ['OPERATOR_ADMIN'], centers: [] }],
    ['OP-cs-1', { roles: ['CS_AGENT'], centers: [] }],
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
