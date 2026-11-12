// 직원 로그인 employee-auth-service — ADR-0056, 백엔드 handoff 2026-11-12 clients-request-backoffice-employee-auth-login,
// 계약 employee-auth-service.yaml 0.1.0.
// 백오피스는 OAuth 클라이언트가 아니다: Keycloak 주소·client_id 를 모른다. 게이트웨이의 로그인 시작 주소로 브라우저를
// 이동시키고(302 → Keycloak 로그인 화면 → 복귀 주소 ?ticket=), 티켓을 PMart 직원 토큰으로 바꾼다.
// - 티켓은 60초·1회용이고 로그인을 시작한 deviceId + code_verifier 로만 바뀐다. 실패하면 다시 로그인(같은 티켓을 다시 보내지 않는다).
// - refresh token 은 한 번만 쓴다. 갱신은 pmartFetch 의 single-flight 한 곳에서만 부른다.
// - 티켓·verifier·토큰을 로그·오류 문구에 남기지 않는다.
import type { Api } from './client';
import { IdempotencyKey, SOURCE_SYSTEM } from './command';
import { ProblemFailure } from './failure';
import type { components } from './generated/employee-auth';
import { PUBLIC_HEADER, request, requestNoContent } from './pmartFetch';
import { sha256 } from './sha256';
import type { TokenStore } from './tokens';

export type LoginMode = 'auth-service' | 'employee-auth';

/** 빌드 때 고른 로그인 방식(vite.config.ts). lan = employee-auth, mock·local = auth-service(아이디·비밀번호). */
export const LOGIN_MODE: LoginMode = import.meta.env.VITE_PMART_LOGIN === 'employee-auth' ? 'employee-auth' : 'auth-service';

export type EmployeeSession = components['schemas']['EmployeeSession'];

/** employee-auth 설정의 앱 이름(pmart.employee-auth.apps.backoffice) */
export const EMPLOYEE_APP = 'backoffice';
/** 복귀 주소 경로 — 백엔드 허용 목록(return-uris)에 `<출처>/auth/callback` 으로 들어 있다 */
export const CALLBACK_PATH = '/auth/callback';
export const LOGIN_PENDING_KEY = 'pmart.backoffice.login.pending';

/** 복귀 주소 `?error=` 로 오는 코드(계약 completeEmployeeLogin) */
const RETURN_ERRORS = ['IDP_ERROR', 'IDP_REJECTED', 'IDP_UNAVAILABLE', 'EMPLOYEE_NOT_REGISTERED', 'ACCOUNT_NOT_AVAILABLE'] as const;
type ReturnError = (typeof RETURN_ERRORS)[number];

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
  constructor(readonly code: EmployeeLoginErrorCode) {
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

/**
 * 로그인 시작: code_verifier 와 기기 ID 를 이 탭의 sessionStorage 에 두고 게이트웨이의 로그인 시작 주소를 돌려준다.
 * 호출한 쪽이 그 주소로 이동한다(fetch 가 아니라 브라우저 이동 — 302 를 따라 Keycloak 화면으로 간다).
 */
export async function beginEmployeeLogin(apiBase: string, from: string, store: TokenStore, d?: EmployeeLoginDeps): Promise<string> {
  const { storage, origin } = deps(d);
  const pending: Pending = {
    verifier: base64Url(crypto.getRandomValues(new Uint8Array(32))), // 43자(계약 43~128)
    deviceId: store.deviceId,
    from,
  };
  storage?.setItem(LOGIN_PENDING_KEY, JSON.stringify(pending));
  const query = new URLSearchParams({
    app: EMPLOYEE_APP,
    deviceId: pending.deviceId,
    codeChallenge: await codeChallenge(pending.verifier),
    codeChallengeMethod: 'S256',
    returnUri: `${origin}${CALLBACK_PATH}`,
  });
  return `${apiBase}/employee-auth/logins?${query.toString()}`;
}

function readPending(storage: Storage | null): Pending | null {
  const raw = storage?.getItem(LOGIN_PENDING_KEY);
  if (!raw) return null;
  try {
    const p = JSON.parse(raw) as Partial<Pending>;
    return typeof p.verifier === 'string' && typeof p.deviceId === 'string' && typeof p.from === 'string' ? (p as Pending) : null;
  } catch {
    return null;
  }
}

const inflight = new Map<string, Promise<string>>();

/**
 * 복귀 주소로 돌아온 뒤: 티켓을 직원 토큰으로 바꿔 store 에 넣는다. 돌아갈 앱 경로를 돌려준다.
 * 같은 티켓으로 두 번 부르면(StrictMode 이중 실행) 첫 요청을 같이 기다린다(티켓은 한 번만 쓸 수 있다).
 */
export function completeEmployeeLogin(api: Api, params: URLSearchParams, store: TokenStore, d?: EmployeeLoginDeps): Promise<string> {
  const key = params.get('ticket') ?? params.get('error') ?? '';
  let p = inflight.get(key);
  if (!p) {
    p = exchange(api, params, store, d).finally(() => setTimeout(() => inflight.delete(key), 0));
    inflight.set(key, p);
  }
  return p;
}

async function exchange(api: Api, params: URLSearchParams, store: TokenStore, d?: EmployeeLoginDeps): Promise<string> {
  const { storage } = deps(d);
  const pending = readPending(storage);
  storage?.removeItem(LOGIN_PENDING_KEY); // verifier 는 한 번만 쓴다
  const error = params.get('error');
  if (error) throw new EmployeeLoginError((RETURN_ERRORS as readonly string[]).includes(error) ? (error as ReturnError) : 'UNKNOWN');
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
          header: { 'Idempotency-Key': IdempotencyKey.generate().value, 'X-Source-System': SOURCE_SYSTEM, 'X-Device-Id': pending.deviceId },
        },
        headers: { [PUBLIC_HEADER]: '1' },
        body: { ticket, codeVerifier: pending.verifier },
      }),
    );
    store.setPair(result.tokens);
    return pending.from;
  } catch (e) {
    if (e instanceof ProblemFailure) {
      if (e.problem.code === 'ACCOUNT_NOT_AVAILABLE') throw new EmployeeLoginError('ACCOUNT_NOT_AVAILABLE');
      if (e.problem.status === 401) throw new EmployeeLoginError('TICKET_INVALID');
    }
    throw new EmployeeLoginError('NETWORK');
  }
}

/** 세션을 끝내야 하는 갱신 거절 코드 */
const SESSION_ENDING = new Set(['TOKEN_INVALID', 'TOKEN_REUSED', 'SESSION_EXPIRED', 'ACCOUNT_NOT_AVAILABLE']);

/**
 * pmartFetch 의 refresh 훅. 새 access token 을 돌려주고, 세션이 끝났으면 null.
 * 응답을 잃으면(결과 불명) 같은 refresh token 을 다시 보내지 않는다 — 서버가 재사용으로 보고 세션을 끊는다(TOKEN_REUSED).
 */
export async function refreshEmployeeTokens(api: Api, store: TokenStore): Promise<string | null> {
  const refreshToken = store.refreshToken;
  if (!refreshToken) return null;
  try {
    const pair = await request(
      'POST',
      api.employeeAuth.POST('/employee-auth/tokens/refresh', {
        params: {
          header: { 'Idempotency-Key': IdempotencyKey.generate().value, 'X-Source-System': SOURCE_SYSTEM, 'X-Device-Id': store.deviceId },
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

/** 서버 세션을 끝낸다. 결과와 관계없이 이 탭의 토큰은 지운다(로그아웃은 멱등). Keycloak 세션은 로그인 때 이미 끝났다. */
export async function logoutEmployee(api: Api, store: TokenStore): Promise<void> {
  try {
    if (store.accessToken) {
      await requestNoContent(
        'POST',
        api.employeeAuth.POST('/employee-auth/logouts', {
          params: { header: { 'Idempotency-Key': IdempotencyKey.generate().value, 'X-Source-System': SOURCE_SYSTEM } },
          body: { allDevices: false },
        }),
      );
    }
  } catch {
    // 서버 세션 종료를 확인하지 못해도 이 탭은 로그아웃한다(access 는 최대 15분, 세션은 최대 12시간으로 끝난다).
  } finally {
    store.clear();
  }
}
