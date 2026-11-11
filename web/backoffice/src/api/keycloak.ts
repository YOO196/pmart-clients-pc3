// 직원 로그인 Keycloak(Realm pmart-staff) — ADR-0054 결정 D·L, 백엔드 handoff 2026-11-11 clients-request-backoffice-keycloak-login.
// Authorization Code + PKCE(S256). 공개 클라이언트라 client secret 이 없다. 백오피스는 비밀번호를 받지 않는다.
// - 표준 OIDC 만 쓴다(Keycloak 전용 API 없음). 인가·토큰·로그아웃 주소는 .well-known 에서 읽는다.
// - 토큰 주소는 form-urlencoded 단순 요청으로 부른다(사용자 정의 머리글을 붙이지 않아 CORS 사전 요청이 없다).
// - ID 토큰은 화면 표시(name)·로그아웃 힌트에만 쓴다. 서명 검증·권한 판정은 서버(게이트웨이)가 access token 으로 한다.
// - 토큰·code·verifier 를 로그·오류 문구에 남기지 않는다.
import { sha256 } from './sha256';
import type { TokenStore } from './tokens';

export type LoginMode = 'auth-service' | 'keycloak';

/** 빌드 때 고른 로그인 방식(vite.config.ts). 옮기는 동안 두 방식을 설정값으로 고른다(결정 D). */
export const LOGIN_MODE: LoginMode = import.meta.env.VITE_PMART_LOGIN === 'keycloak' ? 'keycloak' : 'auth-service';

export interface KeycloakConfig {
  /** 발급자(iss). 이 값과 같은 iss 의 토큰을 직원(운영자) 토큰으로 본다 */
  readonly issuer: string;
  readonly clientId: string;
}

export const KEYCLOAK: KeycloakConfig = {
  issuer: import.meta.env.VITE_PMART_KEYCLOAK_ISSUER,
  clientId: import.meta.env.VITE_PMART_KEYCLOAK_CLIENT_ID,
};

export const CALLBACK_PATH = '/login/callback';
export const OIDC_PENDING_KEY = 'pmart.backoffice.oidc.pending';

export type KeycloakErrorCode =
  /** .well-known 을 읽지 못함(네트워크·형식·발급자 불일치) */
  | 'DISCOVERY_FAILED'
  /** 돌아왔는데 이 탭에서 시작한 로그인 기록이 없다(다른 탭·오래된 주소·새로고침 두 번) */
  | 'NO_PENDING'
  /** state·nonce 가 맞지 않는다 */
  | 'STATE_MISMATCH'
  /** Keycloak 이 돌려준 오류(사용자 취소 access_denied 등) */
  | 'PROVIDER_ERROR'
  /** 토큰 주소가 code 를 거절했다 */
  | 'TOKEN_REJECTED'
  /** 토큰 요청의 결과를 모른다(네트워크·5xx) */
  | 'NETWORK';

export class KeycloakLoginError extends Error {
  constructor(
    readonly code: KeycloakErrorCode,
    /** Keycloak 의 error 값(access_denied 등). 설명문은 담지 않는다 */
    readonly providerError?: string,
  ) {
    super(code);
    this.name = 'KeycloakLoginError';
  }
}

interface Discovery {
  readonly authorization_endpoint: string;
  readonly token_endpoint: string;
  readonly end_session_endpoint?: string;
}

interface Pending {
  readonly state: string;
  readonly nonce: string;
  readonly verifier: string;
  readonly redirectUri: string;
  /** 로그인 뒤 돌아갈 앱 안 경로 */
  readonly from: string;
}

interface TokenResponse {
  readonly access_token: string;
  readonly refresh_token?: string;
  readonly id_token?: string;
}

export interface KeycloakDeps {
  readonly config?: KeycloakConfig;
  readonly fetchImpl?: typeof fetch;
  readonly storage?: Storage | null;
  readonly origin?: string;
}

const deps = (d: KeycloakDeps = {}) => ({
  config: d.config ?? KEYCLOAK,
  fetchImpl: d.fetchImpl ?? ((input: RequestInfo | URL, init?: RequestInit) => globalThis.fetch(input, init)),
  storage: d.storage === undefined ? sessionStorageOrNull() : d.storage,
  origin: d.origin ?? globalThis.location.origin,
});

function sessionStorageOrNull(): Storage | null {
  try {
    return typeof sessionStorage === 'undefined' ? null : sessionStorage;
  } catch {
    return null;
  }
}

export function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

const randomString = (byteLength: number) => base64Url(crypto.getRandomValues(new Uint8Array(byteLength)));

/** RFC 7636 S256: BASE64URL(SHA256(ASCII(verifier))) */
export async function codeChallenge(verifier: string): Promise<string> {
  return base64Url(await sha256(new TextEncoder().encode(verifier)));
}

const discoveries = new Map<string, Promise<Discovery>>();

async function discover(config: KeycloakConfig, fetchImpl: typeof fetch): Promise<Discovery> {
  let p = discoveries.get(config.issuer);
  if (!p) {
    p = (async () => {
      const res = await fetchImpl(`${config.issuer}/.well-known/openid-configuration`);
      if (!res.ok) throw new KeycloakLoginError('DISCOVERY_FAILED');
      const d = (await res.json()) as Partial<Discovery> & { issuer?: string };
      // 다른 발급자의 설정이면 쓰지 않는다(주소 오타·프록시).
      if (d.issuer !== config.issuer || typeof d.authorization_endpoint !== 'string' || typeof d.token_endpoint !== 'string') {
        throw new KeycloakLoginError('DISCOVERY_FAILED');
      }
      return d as Discovery;
    })().catch((e: unknown) => {
      discoveries.delete(config.issuer); // 실패는 기억하지 않는다(다음 시도에 다시 읽는다)
      throw e instanceof KeycloakLoginError ? e : new KeycloakLoginError('DISCOVERY_FAILED');
    });
    discoveries.set(config.issuer, p);
  }
  return p;
}

/** 테스트용: 읽어 둔 .well-known 을 잊는다 */
export function forgetDiscovery(): void {
  discoveries.clear();
}

/**
 * 로그인 시작: PKCE·state·nonce 를 이 탭의 sessionStorage 에 두고 Keycloak 인가 주소를 돌려준다.
 * 호출한 쪽이 그 주소로 이동한다(location.assign).
 */
export async function beginKeycloakLogin(from: string, d?: KeycloakDeps): Promise<string> {
  const { config, fetchImpl, storage, origin } = deps(d);
  const discovery = await discover(config, fetchImpl);
  const pending: Pending = {
    state: randomString(16),
    nonce: randomString(16),
    verifier: randomString(32), // 43자(RFC 7636 최소 43)
    redirectUri: `${origin}${CALLBACK_PATH}`,
    from,
  };
  storage?.setItem(OIDC_PENDING_KEY, JSON.stringify(pending));
  const url = new URL(discovery.authorization_endpoint);
  url.search = new URLSearchParams({
    client_id: config.clientId,
    response_type: 'code',
    scope: 'openid',
    redirect_uri: pending.redirectUri,
    state: pending.state,
    nonce: pending.nonce,
    code_challenge: await codeChallenge(pending.verifier),
    code_challenge_method: 'S256',
  }).toString();
  return url.toString();
}

function readPending(storage: Storage | null): Pending | null {
  const raw = storage?.getItem(OIDC_PENDING_KEY);
  if (!raw) return null;
  try {
    const p = JSON.parse(raw) as Partial<Pending>;
    return typeof p.state === 'string' &&
      typeof p.nonce === 'string' &&
      typeof p.verifier === 'string' &&
      typeof p.redirectUri === 'string' &&
      typeof p.from === 'string'
      ? (p as Pending)
      : null;
  } catch {
    return null;
  }
}

/** JWT 본문 클레임(서명 확인 없이 — 화면 편의용). 형식이 아니면 null */
export function jwtClaims(token: string): Record<string, unknown> | null {
  const part = token.split('.')[1];
  if (!part) return null;
  try {
    const base64 = part.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
    const bytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
    const v: unknown = JSON.parse(new TextDecoder().decode(bytes));
    return typeof v === 'object' && v !== null ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

async function postToken(tokenEndpoint: string, body: Record<string, string>, fetchImpl: typeof fetch): Promise<Response> {
  try {
    return await fetchImpl(tokenEndpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(body).toString(),
    });
  } catch {
    throw new KeycloakLoginError('NETWORK');
  }
}

const inflight = new Map<string, Promise<string>>();

/**
 * Keycloak 에서 돌아온 뒤: state 확인 → code 를 토큰으로 바꿔 store 에 넣는다. 돌아갈 앱 경로를 돌려준다.
 * 같은 code 로 두 번 부르면(StrictMode 이중 실행) 첫 요청을 같이 기다린다(code 는 한 번만 쓸 수 있다).
 */
export function completeKeycloakLogin(params: URLSearchParams, store: TokenStore, d?: KeycloakDeps): Promise<string> {
  const key = params.get('code') ?? params.get('error') ?? '';
  let p = inflight.get(key);
  if (!p) {
    p = exchange(params, store, d).finally(() => setTimeout(() => inflight.delete(key), 0));
    inflight.set(key, p);
  }
  return p;
}

async function exchange(params: URLSearchParams, store: TokenStore, d?: KeycloakDeps): Promise<string> {
  const { config, fetchImpl, storage } = deps(d);
  const pending = readPending(storage);
  storage?.removeItem(OIDC_PENDING_KEY); // 한 번만 쓴다
  const error = params.get('error');
  if (error) throw new KeycloakLoginError('PROVIDER_ERROR', error);
  if (!pending) throw new KeycloakLoginError('NO_PENDING');
  const code = params.get('code');
  if (!code || params.get('state') !== pending.state) throw new KeycloakLoginError('STATE_MISMATCH');

  const discovery = await discover(config, fetchImpl);
  const res = await postToken(
    discovery.token_endpoint,
    {
      grant_type: 'authorization_code',
      client_id: config.clientId,
      code,
      redirect_uri: pending.redirectUri,
      code_verifier: pending.verifier,
    },
    fetchImpl,
  );
  if (res.status >= 500) throw new KeycloakLoginError('NETWORK');
  if (!res.ok) throw new KeycloakLoginError('TOKEN_REJECTED');
  const t = (await res.json()) as Partial<TokenResponse>;
  if (typeof t.access_token !== 'string' || typeof t.refresh_token !== 'string') throw new KeycloakLoginError('TOKEN_REJECTED');
  const idClaims = t.id_token ? jwtClaims(t.id_token) : null;
  if (t.id_token && idClaims?.['nonce'] !== pending.nonce) throw new KeycloakLoginError('STATE_MISMATCH');

  store.clear();
  store.setPair({ accessToken: t.access_token, refreshToken: t.refresh_token, ...(t.id_token ? { idToken: t.id_token } : {}) });
  return pending.from;
}

/**
 * pmartFetch 의 refresh 훅(Keycloak). 새 access token, 세션이 끝났으면 null(invalid_grant — 12시간 끝·비활성·로그아웃).
 * 네트워크·5xx 는 세션 종료로 단정하지 않고 던진다.
 */
export async function refreshKeycloakTokens(store: TokenStore, d?: KeycloakDeps): Promise<string | null> {
  const refreshToken = store.refreshToken;
  if (!refreshToken) return null;
  const { config, fetchImpl } = deps(d);
  const discovery = await discover(config, fetchImpl);
  const res = await postToken(discovery.token_endpoint, { grant_type: 'refresh_token', client_id: config.clientId, refresh_token: refreshToken }, fetchImpl);
  if (res.status === 400 || res.status === 401) return null;
  if (!res.ok) throw new KeycloakLoginError('NETWORK');
  const t = (await res.json()) as Partial<TokenResponse>;
  if (typeof t.access_token !== 'string') return null;
  store.setPair({
    accessToken: t.access_token,
    // Keycloak 이 새 refresh 를 주면 바꾸고, 안 주면 쓰던 것을 계속 쓴다.
    refreshToken: t.refresh_token ?? refreshToken,
    ...(t.id_token ? { idToken: t.id_token } : store.idToken ? { idToken: store.idToken } : {}),
  });
  return t.access_token;
}

/**
 * 로그아웃: 이 탭의 토큰을 지우고 Keycloak 로그아웃 주소를 돌려준다(호출한 쪽이 이동).
 * .well-known 을 읽지 못하면 null — 탭의 토큰은 이미 지웠으므로 앱 로그인 화면으로 보낸다(Keycloak 세션은 12시간 수명으로 끝난다).
 */
export async function keycloakLogoutUrl(store: TokenStore, d?: KeycloakDeps): Promise<string | null> {
  const { config, fetchImpl, origin } = deps(d);
  const idToken = store.idToken;
  store.clear();
  try {
    const discovery = await discover(config, fetchImpl);
    if (!discovery.end_session_endpoint) return null;
    const url = new URL(discovery.end_session_endpoint);
    url.search = new URLSearchParams({
      client_id: config.clientId,
      post_logout_redirect_uri: `${origin}/login`,
      ...(idToken ? { id_token_hint: idToken } : {}),
    }).toString();
    return url.toString();
  } catch {
    return null;
  }
}
