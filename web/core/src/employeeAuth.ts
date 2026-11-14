// 직원 로그인 employee-auth-service — ADR-0056, 백엔드 handoff 2026-11-12 clients-request-backoffice-employee-auth-login,
// 계약 employee-auth-service.yaml 0.3.0.
// 직원용 웹 앱(백오피스·인사팀 백오피스)은 OAuth 클라이언트가 아니다: Keycloak 주소·client_id 를 모른다. 게이트웨이의 로그인 시작 주소로 브라우저를
// 이동시키고(302 → Keycloak 로그인 화면 → 복귀 주소 ?ticket=), 티켓을 PMart 직원 토큰으로 바꾼다.
// - 티켓은 60초·1회용이고 로그인을 시작한 deviceId + code_verifier 로만 바뀐다. 실패하면 다시 로그인(같은 티켓을 다시 보내지 않는다).
// - refresh token 은 한 번만 쓴다. 갱신은 pmartFetch 의 single-flight 한 곳에서만 부른다.
// - 웹 백오피스의 refresh token 은 HttpOnly 쿠키다(ADR-0059, handoff 2026-11-13 web-common-request-refresh-cookie): 화면 코드는 값을 못 본다.
//   티켓 교환·쿠키 갱신·로그아웃 세 호출만 credentials: 'include'(쿠키가 심기고·실리고·지워지는 곳). 갱신은 CSRF 쿠키 값을 X-CSRF-Token 으로 보낸다.
//   서버가 BODY 로 답하면(목·시험) 예전처럼 본문 refresh token 으로 갱신한다.
// - 조용한 로그인 확인(silent — handoff 2026-11-13 web-common-request-silent-login): 토큰 없이 열렸을 때 로그인 버튼을 보이기 전에 한 번,
//   화면 없이 Keycloak 세션만 확인한다. 세션이 없으면 ?error=LOGIN_REQUIRED 로 돌아온다(오류가 아니라 로그인 버튼).
// - 로그아웃 전파(ADR-0061, handoff 2026-11-14 web-common-request-logout-propagation): 같은 브라우저의 다른 앱에서 로그아웃하면 서버가 이 앱
//   세션도 끝낸다. 출처가 달라 탭끼리 알릴 수 없으므로, 탭이 다시 보일 때 세션을 한 번 확인한다(watchEmployeeSessionOnVisible).
// - 티켓·verifier·토큰을 로그·오류 문구에 남기지 않는다.
import type { Client } from 'openapi-fetch';

import { IdempotencyKey } from './command';
import { ProblemFailure, UnknownResultFailure } from './failure';
import type { components, paths } from './generated/employee-auth';
import { PUBLIC_HEADER, request } from './pmartFetch';
import { sha256 } from './sha256';
import type { TokenStore } from './tokens';

/** employee-auth-service 계약 경로 타입 — 앱이 `createClient<EmployeeAuthPaths>` 로 클라이언트를 만든다 */
export type EmployeeAuthPaths = paths;
export type EmployeeSession = components['schemas']['EmployeeSession'];

/** 이 모듈이 쓰는 API 클라이언트(앱의 Api 중 employeeAuth 만) */
export interface EmployeeAuthApi {
  readonly employeeAuth: Client<paths>;
}

export interface EmployeeAuthConfig {
  /** employee-auth 설정의 앱 이름(pmart.employee-auth.apps.<app>) — backoffice, hr-backoffice */
  readonly app: string;
  /** `X-Source-System` */
  readonly sourceSystem: string;
  /** 로그인 시작 기록(verifier·기기 ID)을 두는 sessionStorage 키 */
  readonly pendingKey: string;
  /** 이 탭에서 조용한 로그인 확인을 이미 했다는 표시를 두는 sessionStorage 키(되풀이 방지) */
  readonly silentKey: string;
}

/** 브라우저 이동(로그인 시작·Keycloak 로그아웃). 시험에서 바꿔 끼울 수 있게 한 곳에 둔다 */
export const browser = {
  assign(url: string): void {
    globalThis.location.assign(url);
  },
  /** `document.cookie` — CSRF 쿠키 값을 읽는 데만 쓴다(refresh 쿠키는 HttpOnly 라 여기에 없다) */
  cookies(): string {
    return typeof document === 'undefined' ? '' : document.cookie;
  },
};

/** CSRF 쿠키 이름 — 세션마다 다르다(탭별 세션). 값은 세션 동안 바뀌지 않는다 */
export const csrfCookieName = (sessionId: string) => `__Secure-pmart_ea_csrf_${sessionId}`;

function readCookie(name: string): string | null {
  for (const part of browser.cookies().split(';')) {
    const eq = part.indexOf('=');
    if (eq > 0 && part.slice(0, eq).trim() === name) return part.slice(eq + 1).trim() || null;
  }
  return null;
}

/** 복귀 주소 경로 — 백엔드 허용 목록(return-uris)에 `<출처>/auth/callback` 으로 들어 있다 */
export const CALLBACK_PATH = '/auth/callback';

/** 복귀 주소 `?error=` 로 오는 코드(계약 completeEmployeeLogin) */
const RETURN_ERRORS = ['IDP_ERROR', 'LOGIN_REQUIRED', 'IDP_REJECTED', 'IDP_UNAVAILABLE', 'EMPLOYEE_NOT_REGISTERED', 'ACCOUNT_NOT_AVAILABLE'] as const;
type ReturnError = (typeof RETURN_ERRORS)[number];

/** LOGIN_REQUIRED = 조용한 로그인 확인인데 Keycloak 세션이 없다 — 오류가 아니다. 로그인 버튼 화면을 보인다 */
export type EmployeeLoginErrorCode =
  | ReturnError
  /** 돌아왔는데 이 탭에서 시작한 로그인 기록이 없다(다른 탭·오래된 주소·새로고침) */
  | 'NO_PENDING'
  /** 티켓이 없거나 서버가 거절(60초 넘김·이미 씀·다른 기기·verifier 불일치) */
  | 'TICKET_INVALID'
  /** 티켓 교환 결과를 모른다(네트워크·5xx). 티켓은 1회용이라 다시 로그인해야 한다 */
  | 'NETWORK'
  /** 계약에 없는 error 값 */
  | 'UNKNOWN';

export class EmployeeLoginError extends Error {
  constructor(
    readonly code: EmployeeLoginErrorCode,
    /** 로그인을 시작할 때 가려던 앱 안 경로(이 탭의 시작 기록이 있을 때) — LOGIN_REQUIRED 뒤 로그인 화면이 이어서 쓴다 */
    readonly from?: string,
  ) {
    super(code);
    this.name = 'EmployeeLoginError';
  }
}

interface Pending {
  readonly verifier: string;
  /** 로그인을 시작한 기기 ID — 티켓 교환·갱신에 같은 값을 보낸다 */
  readonly deviceId: string;
  /** 로그인 뒤 돌아갈 앱 안 경로 */
  readonly from: string;
}

export interface EmployeeLoginDeps {
  readonly storage?: Storage | null;
  readonly origin?: string;
}

function sessionStorageOrNull(): Storage | null {
  try {
    return typeof sessionStorage === 'undefined' ? null : sessionStorage;
  } catch {
    return null;
  }
}

const deps = (d: EmployeeLoginDeps = {}) => ({
  storage: d.storage === undefined ? sessionStorageOrNull() : d.storage,
  origin: d.origin ?? globalThis.location.origin,
});

export function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/** RFC 7636 S256: BASE64URL(SHA256(ASCII(verifier))). LAN 은 http 라 crypto.subtle 이 없어 sha256.ts 를 쓴다 */
export async function codeChallenge(verifier: string): Promise<string> {
  return base64Url(await sha256(new TextEncoder().encode(verifier)));
}

function readPending(storage: Storage | null, pendingKey: string): Pending | null {
  const raw = storage?.getItem(pendingKey);
  if (!raw) return null;
  try {
    const p = JSON.parse(raw) as Partial<Pending>;
    return typeof p.verifier === 'string' && typeof p.deviceId === 'string' && typeof p.from === 'string' ? (p as Pending) : null;
  } catch {
    return null;
  }
}

/** 세션을 끝내야 하는 갱신 거절 코드 */
const SESSION_ENDING = new Set(['TOKEN_INVALID', 'TOKEN_REUSED', 'SESSION_EXPIRED', 'ACCOUNT_NOT_AVAILABLE']);
/** 쿠키 갱신에서 이 탭이 그 세션을 더 쓸 수 없는 거절(세션 자체는 서버에 남는다) */
const CSRF_INVALID = 'CSRF_INVALID';

export interface EmployeeLogoutOutcome {
  /**
   * Keycloak 로그아웃 주소(SSO — handoff 2026-11-12 clients-request-backoffice-sso-logout). 브라우저를 이 주소로 이동시켜야
   * Keycloak 세션까지 끝난다(끝나면 <출처>/login 으로 돌아온다). 토큰 값이 들어 있으니 로그·오류 문구에 남기지 않는다.
   */
  readonly idpLogoutUri?: string;
  /** 서버가 로그아웃을 확인해 주지 않았다(실패·결과 불명) — Keycloak 세션이 남아 다음 로그인이 비밀번호 없이 될 수 있다 */
  readonly idpSessionMayRemain: boolean;
}

/** http(s) 주소만 이동 대상으로 받는다(javascript: 등 다른 scheme 은 버린다) */
function httpUrl(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  try {
    const u = new URL(value);
    return u.protocol === 'https:' || u.protocol === 'http:' ? u.toString() : undefined;
  } catch {
    return undefined;
  }
}

export interface EmployeeAuth {
  /**
   * 로그인 시작: code_verifier 와 기기 ID 를 이 탭의 sessionStorage 에 두고 게이트웨이의 로그인 시작 주소를 돌려준다.
   * 호출한 쪽이 그 주소로 이동한다(`browser.assign`).
   */
  readonly beginEmployeeLogin: (apiBase: string, from: string, store: TokenStore, d?: EmployeeLoginDeps) => Promise<string>;
  /** 이 탭에서 조용한 로그인 확인을 아직 하지 않았다(로그아웃 직후·LOGIN_REQUIRED 뒤에는 false — 버튼만 보인다) */
  readonly canTrySilentLogin: (d?: EmployeeLoginDeps) => boolean;
  /**
   * 조용한 로그인 확인 시작(silent=true): 주소를 돌려주고 "했다"고 표시한다. 이미 했으면 null(다시 하지 않는다).
   * 호출한 쪽이 그 주소로 이동한다 — 화면 없이 Keycloak 을 다녀와 ?ticket= 또는 ?error=LOGIN_REQUIRED 로 돌아온다.
   */
  readonly beginSilentEmployeeLogin: (apiBase: string, from: string, store: TokenStore, d?: EmployeeLoginDeps) => Promise<string | null>;
  /** 복귀 주소로 돌아온 뒤: 티켓을 직원 토큰으로 바꿔 store 에 넣고, 돌아갈 앱 경로를 돌려준다. 실패는 EmployeeLoginError */
  readonly completeEmployeeLogin: (api: EmployeeAuthApi, params: URLSearchParams, store: TokenStore, d?: EmployeeLoginDeps) => Promise<string>;
  /** pmartFetch 의 refresh 훅. 새 access token, 세션이 끝났으면 null */
  readonly refreshEmployeeTokens: (api: EmployeeAuthApi, store: TokenStore) => Promise<string | null>;
  /** 서버 세션을 끝내고 이 탭의 토큰을 지운다. idpLogoutUri 로 이동하는 것은 호출한 쪽이 한다 */
  readonly logoutEmployee: (api: EmployeeAuthApi, store: TokenStore) => Promise<EmployeeLogoutOutcome>;
}

/** 앱마다 한 번 만든다(앱 이름·출처·보관 키가 다르다). */
export function createEmployeeAuth({ app, sourceSystem, pendingKey, silentKey }: EmployeeAuthConfig): EmployeeAuth {
  /**
   * 로그인 시작: code_verifier 와 기기 ID 를 이 탭의 sessionStorage 에 두고 게이트웨이의 로그인 시작 주소를 돌려준다.
   * 호출한 쪽이 그 주소로 이동한다(fetch 가 아니라 브라우저 이동 — 302 를 따라 Keycloak 화면으로 간다).
   */
  function beginEmployeeLogin(apiBase: string, from: string, store: TokenStore, d?: EmployeeLoginDeps): Promise<string> {
    return begin(apiBase, from, store, false, d);
  }

  function canTrySilentLogin(d?: EmployeeLoginDeps): boolean {
    // 표시를 둘 곳이 없으면 되풀이를 막을 수 없으므로 하지 않는다.
    const { storage } = deps(d);
    return storage !== null && storage.getItem(silentKey) === null;
  }

  async function beginSilentEmployeeLogin(apiBase: string, from: string, store: TokenStore, d?: EmployeeLoginDeps): Promise<string | null> {
    if (!canTrySilentLogin(d)) return null;
    deps(d).storage?.setItem(silentKey, '1'); // 이동하기 전에 표시한다 — 돌아와서 다시 시작하지 않게
    return begin(apiBase, from, store, true, d);
  }

  async function begin(apiBase: string, from: string, store: TokenStore, silent: boolean, d?: EmployeeLoginDeps): Promise<string> {
    const { storage, origin } = deps(d);
    const pending: Pending = {
      verifier: base64Url(crypto.getRandomValues(new Uint8Array(32))), // 43자(계약 43~128)
      deviceId: store.deviceId,
      from,
    };
    storage?.setItem(pendingKey, JSON.stringify(pending));
    const query = new URLSearchParams({
      app,
      deviceId: pending.deviceId,
      codeChallenge: await codeChallenge(pending.verifier),
      codeChallengeMethod: 'S256',
      returnUri: `${origin}${CALLBACK_PATH}`,
      ...(silent ? { silent: 'true' } : {}),
    });
    return `${apiBase}/employee-auth/logins?${query.toString()}`;
  }

  const inflight = new Map<string, Promise<string>>();

  /**
   * 복귀 주소로 돌아온 뒤: 티켓을 직원 토큰으로 바꿔 store 에 넣는다. 돌아갈 앱 경로를 돌려준다.
   * 같은 티켓으로 두 번 부르면(StrictMode 이중 실행) 첫 요청을 같이 기다린다(티켓은 한 번만 쓸 수 있다).
   */
  function completeEmployeeLogin(api: EmployeeAuthApi, params: URLSearchParams, store: TokenStore, d?: EmployeeLoginDeps): Promise<string> {
    const key = params.get('ticket') ?? params.get('error') ?? '';
    let p = inflight.get(key);
    if (!p) {
      p = exchange(api, params, store, d).finally(() => setTimeout(() => inflight.delete(key), 0));
      inflight.set(key, p);
    }
    return p;
  }

  async function exchange(api: EmployeeAuthApi, params: URLSearchParams, store: TokenStore, d?: EmployeeLoginDeps): Promise<string> {
    const { storage } = deps(d);
    const pending = readPending(storage, pendingKey);
    storage?.removeItem(pendingKey); // verifier 는 한 번만 쓴다
    const error = params.get('error');
    if (error) throw new EmployeeLoginError((RETURN_ERRORS as readonly string[]).includes(error) ? (error as ReturnError) : 'UNKNOWN', pending?.from);
    if (!pending) throw new EmployeeLoginError('NO_PENDING');
    const ticket = params.get('ticket');
    if (!ticket) throw new EmployeeLoginError('TICKET_INVALID');

    store.clear();
    // 페이지가 다시 열렸으므로 기기 ID 를 로그인 시작 때 값으로 되돌린다(티켓·갱신이 이 값에 묶인다).
    store.useDevice(pending.deviceId);
    try {
      const result = await request(
        'POST',
        api.employeeAuth.POST('/employee-auth/tokens', {
          params: {
            header: { 'Idempotency-Key': IdempotencyKey.generate().value, 'X-Source-System': sourceSystem, 'X-Device-Id': pending.deviceId },
          },
          headers: { [PUBLIC_HEADER]: '1' },
          body: { ticket, codeVerifier: pending.verifier },
          credentials: 'include', // 응답의 Set-Cookie(refresh·CSRF)가 저장되려면 필요하다
        }),
      );
      store.setPair(result.tokens);
      // 세션이 생겼다 — 이 세션이 끝난 뒤에는 조용한 로그인 확인을 다시 한 번 할 수 있다.
      storage?.removeItem(silentKey);
      return pending.from;
    } catch (e) {
      if (e instanceof ProblemFailure) {
        if (e.problem.code === 'ACCOUNT_NOT_AVAILABLE') throw new EmployeeLoginError('ACCOUNT_NOT_AVAILABLE');
        if (e.problem.status === 401) throw new EmployeeLoginError('TICKET_INVALID');
      }
      throw new EmployeeLoginError('NETWORK');
    }
  }

  /**
   * pmartFetch 의 refresh 훅. 새 access token 을 돌려주고, 세션이 끝났으면(이 탭이 더 쓸 수 없으면) null.
   * 응답을 잃으면(결과 불명) 같은 refresh token 을 다시 보내지 않는다 — 서버가 재사용으로 보고 세션을 끊는다(TOKEN_REUSED).
   */
  function refreshEmployeeTokens(api: EmployeeAuthApi, store: TokenStore): Promise<string | null> {
    const sessionId = store.cookieSessionId;
    return sessionId ? refreshWithCookie(api, store, sessionId) : refreshWithBody(api, store);
  }

  /**
   * refresh 쿠키 갱신(ADR-0059). refresh token 은 브라우저가 쿠키로 싣고, 여기서는 CSRF 쿠키 값을 헤더로 보낸다.
   * CSRF 쿠키가 없거나 403 CSRF_INVALID 면 이 탭은 그 세션을 못 쓴다 → null(값을 다시 받는 API 는 없다 — 새 로그인).
   * 결과를 모르면(응답 유실·연결 오류) null: 새 쿠키를 못 받았을 수 있어 다시 보내면 옛 쿠키 재사용으로 세션이 끝난다.
   */
  async function refreshWithCookie(api: EmployeeAuthApi, store: TokenStore, sessionId: string): Promise<string | null> {
    const csrf = readCookie(csrfCookieName(sessionId));
    if (!csrf) return null;
    try {
      const pair = await request(
        'POST',
        api.employeeAuth.POST('/employee-auth/tokens/refresh/{sessionId}', {
          params: {
            path: { sessionId },
            header: {
              'Idempotency-Key': IdempotencyKey.generate().value,
              'X-Source-System': sourceSystem,
              'X-Device-Id': store.deviceId,
              'X-CSRF-Token': csrf,
            },
          },
          headers: { [PUBLIC_HEADER]: '1' },
          credentials: 'include',
        }),
      );
      store.setPair(pair);
      return pair.accessToken;
    } catch (e) {
      if (e instanceof ProblemFailure) {
        if (SESSION_ENDING.has(e.problem.code) || e.problem.code === CSRF_INVALID) return null;
        throw e; // 서버가 거절 사유를 알려 줬다(429 등) — 쿠키는 쓰이지 않았다
      }
      if (e instanceof UnknownResultFailure) return null;
      throw e;
    }
  }

  async function refreshWithBody(api: EmployeeAuthApi, store: TokenStore): Promise<string | null> {
    const refreshToken = store.refreshToken;
    if (!refreshToken) return null;
    try {
      const pair = await request(
        'POST',
        api.employeeAuth.POST('/employee-auth/tokens/refresh', {
          params: {
            header: { 'Idempotency-Key': IdempotencyKey.generate().value, 'X-Source-System': sourceSystem, 'X-Device-Id': store.deviceId },
          },
          headers: { [PUBLIC_HEADER]: '1' },
          body: { refreshToken },
        }),
      );
      store.setPair(pair);
      return pair.accessToken;
    } catch (e) {
      if (e instanceof ProblemFailure && SESSION_ENDING.has(e.problem.code)) return null;
      throw e;
    }
  }

  /**
   * 서버 세션을 끝낸다. 결과와 관계없이 이 탭의 토큰은 지운다(로그아웃은 멱등).
   * 백오피스는 SSO 라 Keycloak 세션이 남아 있다 — 응답의 idpLogoutUri 로 브라우저를 이동시키는 것은 호출한 쪽이 한다(토큰을 지운 뒤).
   * 이미 끝난 세션이면 idpLogoutUri 없이 200(Keycloak 세션도 이미 끝난 것으로 본다).
   * refresh 쿠키 세션이면 응답 Set-Cookie 가 쿠키 둘을 지운다(credentials: 'include'). 서버 호출이 실패해도 store.clear() 로 세션 ID 를
   * 지우므로 남은 쿠키는 이 탭에서 쓸 수 없다(CSRF 쿠키 이름을 알 길이 없다 — 서버 무활동 한도로 끝난다).
   */
  async function logoutEmployee(api: EmployeeAuthApi, store: TokenStore): Promise<EmployeeLogoutOutcome> {
    // 로그아웃 뒤에는 조용한 로그인 확인을 하지 않는다(남은 Keycloak 세션으로 곧바로 다시 들어가지 않게 — 버튼만).
    deps().storage?.setItem(silentKey, '1');
    try {
      if (!store.accessToken) return { idpSessionMayRemain: false };
      const result = await request(
        'POST',
        api.employeeAuth.POST('/employee-auth/logouts', {
          params: { header: { 'Idempotency-Key': IdempotencyKey.generate().value, 'X-Source-System': sourceSystem } },
          body: { allDevices: false },
          credentials: 'include',
        }),
      );
      const idpLogoutUri = httpUrl(result.idpLogoutUri);
      return { ...(idpLogoutUri ? { idpLogoutUri } : {}), idpSessionMayRemain: false };
    } catch {
      // 서버 세션 종료를 확인하지 못해도 이 탭은 로그아웃한다(access 는 최대 15분, 세션은 최대 12시간으로 끝난다).
      return { idpSessionMayRemain: true };
    } finally {
      store.clear();
    }
  }

  return { beginEmployeeLogin, canTrySilentLogin, beginSilentEmployeeLogin, completeEmployeeLogin, refreshEmployeeTokens, logoutEmployee };
}

export interface SessionWatchDeps {
  readonly doc?: Pick<Document, 'visibilityState' | 'addEventListener' | 'removeEventListener'>;
  readonly now?: () => number;
  /** 마지막 확인 뒤 이 시간 안이면 건너뛴다(탭을 빨리 오갈 때). 기본 30초 */
  readonly minIntervalMs?: number;
}

/**
 * 탭이 다시 보일 때(visibilitychange → visible) 세션이 있으면 `GET /employee-auth/sessions/current` 를 한 번 부른다(Bearer, 쿠키 없음).
 * 200 이면 아무것도 하지 않는다. 401 이면 pmartFetch 의 401 처리 그대로다 — 갱신 한 번, 거절되면 store 가 비워져 앱이 로그인 화면
 * (조용한 로그인 확인 → 버튼)으로 간다. 네트워크 오류·5xx 는 버린다(다음 호출 때 다시 드러난다).
 * 돌려준 함수를 부르면 그만 본다.
 */
export function watchEmployeeSessionOnVisible(api: EmployeeAuthApi, store: TokenStore, d: SessionWatchDeps = {}): () => void {
  const doc = d.doc ?? (typeof document === 'undefined' ? null : document);
  if (!doc) return () => undefined;
  const now = d.now ?? Date.now;
  const minIntervalMs = d.minIntervalMs ?? 30_000;
  let last: number | null = null;
  const onChange = () => {
    if (doc.visibilityState !== 'visible' || store.accessToken === null) return;
    const at = now();
    if (last !== null && at - last < minIntervalMs) return;
    last = at;
    void api.employeeAuth.GET('/employee-auth/sessions/current', {}).catch(() => undefined);
  };
  doc.addEventListener('visibilitychange', onChange);
  return () => doc.removeEventListener('visibilitychange', onChange);
}
