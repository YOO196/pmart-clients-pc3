// Keycloak 로그인(PKCE)·갱신·로그아웃·클레임 — 백엔드 handoff 2026-11-11 clients-request-backoffice-keycloak-login.
import { beforeEach, describe, expect, it } from 'vitest';

import {
  beginKeycloakLogin,
  codeChallenge,
  completeKeycloakLogin,
  forgetDiscovery,
  KEYCLOAK,
  KeycloakLoginError,
  keycloakLogoutUrl,
  OIDC_PENDING_KEY,
  refreshKeycloakTokens,
  type KeycloakConfig,
} from './keycloak';
import { parseIdToken, parseOperatorToken } from './session';
import { sha256Fallback } from './sha256';
import { TokenStore } from './tokens';

const config: KeycloakConfig = { issuer: 'http://kc.test/realms/pmart-staff', clientId: 'pmart-backoffice' };
const origin = 'http://192.168.0.40';
const discovery = {
  issuer: config.issuer,
  authorization_endpoint: `${config.issuer}/protocol/openid-connect/auth`,
  token_endpoint: `${config.issuer}/protocol/openid-connect/token`,
  end_session_endpoint: `${config.issuer}/protocol/openid-connect/logout`,
};

const seg = (v: unknown) =>
  btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(v))))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
const jwt = (claims: Record<string, unknown>) => `${seg({ alg: 'RS256' })}.${seg(claims)}.sig`;

interface Sent {
  readonly url: string;
  readonly body: URLSearchParams;
}

/** .well-known + 토큰 주소 가짜. tokenReply 가 토큰 요청 응답을 고른다 */
function fakeKeycloak(tokenReply: (body: URLSearchParams) => Response) {
  const sent: Sent[] = [];
  const fetchImpl = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url === `${config.issuer}/.well-known/openid-configuration`) return Promise.resolve(Response.json(discovery));
    if (url === discovery.token_endpoint) {
      const body = new URLSearchParams(typeof init?.body === 'string' ? init.body : '');
      sent.push({ url, body });
      expect(new Headers(init?.headers).get('content-type')).toBe('application/x-www-form-urlencoded');
      return Promise.resolve(tokenReply(body));
    }
    return Promise.reject(new TypeError(`unexpected ${url}`));
  }) as typeof fetch;
  return { fetchImpl, sent, deps: { config, fetchImpl, storage: sessionStorage, origin } };
}

const toHex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');

beforeEach(() => {
  forgetDiscovery();
  sessionStorage.clear();
});

describe('SHA-256·PKCE', () => {
  it('순수 JS SHA-256 이 표준 값과 같다(LAN 은 http 라 crypto.subtle 이 없다)', async () => {
    const enc = new TextEncoder();
    expect(toHex(sha256Fallback(enc.encode('')))).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(toHex(sha256Fallback(enc.encode('abc')))).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    for (const n of [55, 56, 63, 64, 65, 1000]) {
      const data = crypto.getRandomValues(new Uint8Array(n));
      expect(toHex(sha256Fallback(data))).toBe(toHex(new Uint8Array(await crypto.subtle.digest('SHA-256', data))));
    }
  });

  it('code_challenge 가 RFC 7636 부록 B 예시와 같다', async () => {
    expect(await codeChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk')).toBe('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });
});

describe('로그인', () => {
  it('인가 주소: 공개 클라이언트·code·openid·S256·redirect /login/callback, 비밀값 없음', async () => {
    const kc = fakeKeycloak(() => new Response(null, { status: 500 }));
    const url = new URL(await beginKeycloakLogin('/prices', kc.deps));
    expect(`${url.origin}${url.pathname}`).toBe(discovery.authorization_endpoint);
    const q = url.searchParams;
    expect(q.get('client_id')).toBe('pmart-backoffice');
    expect(q.get('response_type')).toBe('code');
    expect(q.get('scope')).toBe('openid');
    expect(q.get('redirect_uri')).toBe('http://192.168.0.40/login/callback');
    expect(q.get('code_challenge_method')).toBe('S256');
    expect(q.has('client_secret')).toBe(false);

    const pending = JSON.parse(sessionStorage.getItem(OIDC_PENDING_KEY)!) as Record<string, string>;
    expect(q.get('state')).toBe(pending['state']);
    expect(q.get('nonce')).toBe(pending['nonce']);
    expect(pending['verifier']!.length).toBeGreaterThanOrEqual(43);
    expect(q.get('code_challenge')).toBe(await codeChallenge(pending['verifier']!));
    expect(q.has('code_verifier')).toBe(false); // verifier 는 인가 주소에 싣지 않는다
  });

  async function startedLogin(tokenReply: (body: URLSearchParams) => Response) {
    const kc = fakeKeycloak(tokenReply);
    const url = new URL(await beginKeycloakLogin('/prices', kc.deps));
    const pending = JSON.parse(sessionStorage.getItem(OIDC_PENDING_KEY)!) as Record<string, string>;
    return { kc, state: url.searchParams.get('state')!, nonce: pending['nonce']!, verifier: pending['verifier']! };
  }

  it('돌아오면 code + verifier 로 토큰을 받고 원래 경로를 돌려준다. 기록은 한 번만 쓴다', async () => {
    let nonce = '';
    const s = await startedLogin(() => Response.json({ access_token: 'A1', refresh_token: 'R1', id_token: jwt({ nonce, name: '김운영' }) }));
    nonce = s.nonce;
    const store = new TokenStore();
    const from = await completeKeycloakLogin(new URLSearchParams({ code: 'C1', state: s.state }), store, s.kc.deps);

    expect(from).toBe('/prices');
    expect(store.accessToken).toBe('A1');
    expect(store.refreshToken).toBe('R1');
    expect(parseIdToken(store.idToken).name).toBe('김운영');
    const body = s.kc.sent[0]!.body;
    expect(Object.fromEntries(body)).toEqual({
      grant_type: 'authorization_code',
      client_id: 'pmart-backoffice',
      code: 'C1',
      redirect_uri: 'http://192.168.0.40/login/callback',
      code_verifier: s.verifier,
    });
    expect(sessionStorage.getItem(OIDC_PENDING_KEY)).toBeNull();
  });

  it('같은 code 로 두 번 불러도(StrictMode) 토큰 요청은 한 번', async () => {
    let nonce = '';
    const s = await startedLogin(() => Response.json({ access_token: 'A1', refresh_token: 'R1', id_token: jwt({ nonce }) }));
    nonce = s.nonce;
    const store = new TokenStore();
    const params = new URLSearchParams({ code: 'C-twice', state: s.state });
    const [a, b] = await Promise.all([completeKeycloakLogin(params, store, s.kc.deps), completeKeycloakLogin(params, store, s.kc.deps)]);
    expect([a, b]).toEqual(['/prices', '/prices']);
    expect(s.kc.sent).toHaveLength(1);
  });

  const failsWith = async (p: Promise<unknown>, code: string) => {
    const e = await p.then(
      () => null,
      (x: unknown) => x,
    );
    expect(e).toBeInstanceOf(KeycloakLoginError);
    expect((e as KeycloakLoginError).code).toBe(code);
  };

  it('state 가 다르면 토큰을 요청하지 않는다', async () => {
    const s = await startedLogin(() => Response.json({}));
    const store = new TokenStore();
    await failsWith(completeKeycloakLogin(new URLSearchParams({ code: 'C2', state: 'other' }), store, s.kc.deps), 'STATE_MISMATCH');
    expect(s.kc.sent).toHaveLength(0);
    expect(store.accessToken).toBeNull();
  });

  it('이 탭에서 시작한 로그인이 없으면 NO_PENDING', async () => {
    const kc = fakeKeycloak(() => Response.json({}));
    await failsWith(completeKeycloakLogin(new URLSearchParams({ code: 'C3', state: 's' }), new TokenStore(), kc.deps), 'NO_PENDING');
  });

  it('ID 토큰 nonce 가 다르면 토큰을 넣지 않는다', async () => {
    const s = await startedLogin(() => Response.json({ access_token: 'A', refresh_token: 'R', id_token: jwt({ nonce: 'other' }) }));
    const store = new TokenStore();
    await failsWith(completeKeycloakLogin(new URLSearchParams({ code: 'C4', state: s.state }), store, s.kc.deps), 'STATE_MISMATCH');
    expect(store.accessToken).toBeNull();
  });

  it('Keycloak 오류로 돌아오면 PROVIDER_ERROR(설명문은 담지 않는다)', async () => {
    const s = await startedLogin(() => Response.json({}));
    const p = completeKeycloakLogin(new URLSearchParams({ error: 'access_denied', error_description: 'x', state: s.state }), new TokenStore(), s.kc.deps);
    await failsWith(p, 'PROVIDER_ERROR');
    await p.catch((e: KeycloakLoginError) => expect(e.message).toBe('PROVIDER_ERROR'));
  });

  it('code 거절(400 invalid_grant) → TOKEN_REJECTED, 5xx → NETWORK(결과 불명)', async () => {
    const s1 = await startedLogin(() => Response.json({ error: 'invalid_grant' }, { status: 400 }));
    await failsWith(completeKeycloakLogin(new URLSearchParams({ code: 'C5', state: s1.state }), new TokenStore(), s1.kc.deps), 'TOKEN_REJECTED');
    const s2 = await startedLogin(() => new Response(null, { status: 503 }));
    await failsWith(completeKeycloakLogin(new URLSearchParams({ code: 'C6', state: s2.state }), new TokenStore(), s2.kc.deps), 'NETWORK');
  });

  it('.well-known 의 발급자가 다르면 쓰지 않는다', async () => {
    const fetchImpl = (() => Promise.resolve(Response.json({ ...discovery, issuer: 'http://evil/realms/x' }))) as typeof fetch;
    await failsWith(beginKeycloakLogin('/', { config, fetchImpl, storage: sessionStorage, origin }), 'DISCOVERY_FAILED');
  });
});

describe('갱신·로그아웃', () => {
  const loggedIn = () => {
    const store = new TokenStore();
    store.setPair({ accessToken: 'A0', refreshToken: 'R0', idToken: 'ID0' });
    return store;
  };

  it('refresh_token 으로 갱신하고 새 refresh·ID 토큰으로 바꾼다', async () => {
    const kc = fakeKeycloak(() => Response.json({ access_token: 'A1', refresh_token: 'R1', id_token: 'ID1' }));
    const store = loggedIn();
    expect(await refreshKeycloakTokens(store, kc.deps)).toBe('A1');
    expect(Object.fromEntries(kc.sent[0]!.body)).toEqual({ grant_type: 'refresh_token', client_id: 'pmart-backoffice', refresh_token: 'R0' });
    expect([store.accessToken, store.refreshToken, store.idToken]).toEqual(['A1', 'R1', 'ID1']);
  });

  it('새 refresh 를 안 주면 쓰던 것을 계속 쓴다', async () => {
    const kc = fakeKeycloak(() => Response.json({ access_token: 'A1' }));
    const store = loggedIn();
    await refreshKeycloakTokens(store, kc.deps);
    expect([store.refreshToken, store.idToken]).toEqual(['R0', 'ID0']);
  });

  it('invalid_grant(12시간 끝·비활성) → null, 5xx·네트워크 → 던진다(세션 종료로 단정하지 않음)', async () => {
    expect(await refreshKeycloakTokens(loggedIn(), fakeKeycloak(() => Response.json({ error: 'invalid_grant' }, { status: 400 })).deps)).toBeNull();
    await expect(refreshKeycloakTokens(loggedIn(), fakeKeycloak(() => new Response(null, { status: 502 })).deps)).rejects.toBeInstanceOf(KeycloakLoginError);
    const offline = (() => Promise.reject(new TypeError('offline'))) as typeof fetch;
    await expect(refreshKeycloakTokens(loggedIn(), { config, fetchImpl: offline, storage: null, origin })).rejects.toBeInstanceOf(KeycloakLoginError);
  });

  it('로그아웃: 탭의 토큰을 지우고 end_session 주소(id_token_hint·post_logout_redirect_uri)', async () => {
    const kc = fakeKeycloak(() => Response.json({}));
    const store = loggedIn();
    const url = new URL((await keycloakLogoutUrl(store, kc.deps))!);
    expect(`${url.origin}${url.pathname}`).toBe(discovery.end_session_endpoint);
    expect(url.searchParams.get('id_token_hint')).toBe('ID0');
    expect(url.searchParams.get('post_logout_redirect_uri')).toBe('http://192.168.0.40/login');
    expect(url.searchParams.get('client_id')).toBe('pmart-backoffice');
    expect([store.accessToken, store.refreshToken, store.idToken]).toEqual([null, null, null]);
  });
});

describe('Keycloak 토큰 클레임(화면용)', () => {
  it('iss 로 직원 판단, 운영자 ID 는 pmart_operator_id, 역할은 realm_access.roles 에서 기본 역할 제외', () => {
    const s = parseOperatorToken(
      jwt({
        iss: KEYCLOAK.issuer,
        sub: '1f0e-uuid',
        typ: 'Bearer',
        pmart_operator_id: 'OP-eaf58e67',
        realm_access: { roles: ['OPERATOR_ADMIN', 'default-roles-pmart-staff', 'offline_access', 'uma_authorization'] },
        centers: ['MFC-GN-01'],
        exp: 1_800_000_000,
      }),
    );
    expect(s).toEqual({
      subject: 'OP-eaf58e67',
      issuer: 'keycloak',
      type: 'OPERATOR',
      roles: ['OPERATOR_ADMIN'],
      centers: ['MFC-GN-01'],
      expiresAtSeconds: 1_800_000_000,
    });
  });

  it('centers 가 없으면 빈 목록, auth-service 토큰은 지금처럼 sub·roles', () => {
    expect(parseOperatorToken(jwt({ iss: KEYCLOAK.issuer, realm_access: { roles: [] } }))?.centers).toEqual([]);
    const legacy = parseOperatorToken(jwt({ iss: 'pmart-auth', sub: 'OP-1', typ: 'OPERATOR', roles: ['MD'], centers: [] }));
    expect(legacy).toMatchObject({ subject: 'OP-1', issuer: 'auth-service', type: 'OPERATOR', roles: ['MD'] });
  });

  it('표시 이름: name, 없으면 성·이름. auth_time 은 있을 때만', () => {
    expect(parseIdToken(jwt({ name: '김운영', auth_time: 1_700_000_000 }))).toEqual({ name: '김운영', authTimeSeconds: 1_700_000_000 });
    expect(parseIdToken(jwt({ family_name: '김', given_name: '운영' }))).toEqual({ name: '김 운영' });
    expect(parseIdToken(null)).toEqual({});
  });
});
