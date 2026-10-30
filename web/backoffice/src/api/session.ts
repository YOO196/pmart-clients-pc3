// 운영자 세션. 토큰 클레임(typ·roles·centers, docs/handoff 백엔드 2026-10-30 §1·§2)을 화면 편의용으로만 읽는다.
// 서명 검증·권한 판정은 서버가 한다. 버튼을 숨기거나 막는 데 쓰지 않고 안내에만 쓴다.

export interface OperatorSession {
  readonly subject: string;
  readonly type: string;
  readonly roles: readonly string[];
  readonly centers: readonly string[];
  /** sid 클레임(서버 세션) */
  readonly sessionId?: string;
  /** exp 클레임(초). 화면은 만료 판정에 쓰지 않는다(서버 401 → 갱신) */
  readonly expiresAtSeconds?: number;
}

function decodeSegment(segment: string): unknown {
  const base64 = segment.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  const bytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}

const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);

/** JWT 본문을 읽는다. 형식이 아니면 null(토큰 값을 오류 문구·로그에 남기지 않는다). */
export function parseOperatorToken(token: string): OperatorSession | null {
  const parts = token.trim().split('.');
  if (parts.length < 2 || !parts[1]) return null;
  try {
    const claims = decodeSegment(parts[1]);
    if (typeof claims !== 'object' || claims === null) return null;
    const c = claims as Record<string, unknown>;
    return {
      subject: typeof c['sub'] === 'string' ? c['sub'] : '',
      type: typeof c['typ'] === 'string' ? c['typ'] : '',
      roles: strings(c['roles']),
      centers: strings(c['centers']),
      ...(typeof c['sid'] === 'string' ? { sessionId: c['sid'] } : {}),
      ...(typeof c['exp'] === 'number' ? { expiresAtSeconds: c['exp'] } : {}),
    };
  } catch {
    return null;
  }
}

function encodeSegment(value: unknown): string {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/** 목 모드 전용 서명 없는 토큰. MSW 핸들러가 같은 클레임을 읽는다. */
export function mockOperatorToken(claims: {
  sub: string;
  roles: readonly string[];
  centers: readonly string[];
  sid?: string;
  exp?: number;
}): string {
  return `${encodeSegment({ alg: 'none', typ: 'JWT' })}.${encodeSegment({ ...claims, typ: 'OPERATOR' })}.mock`;
}
