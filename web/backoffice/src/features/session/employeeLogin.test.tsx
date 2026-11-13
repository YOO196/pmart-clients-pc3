// 직원 로그인 employee-auth(실서버 모드 — 게이트웨이 로그인 시작·티켓 교환·갱신·SSO 로그아웃) — 백엔드 handoff 2026-11-12, 계약 employee-auth-service.yaml.
// 목 계정 버튼 로그인은 mockLogin.test.tsx.
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { API_BASE, createApi, SOURCE_SYSTEM } from '../../api/client';
import {
  beginEmployeeLogin,
  browser,
  codeChallenge,
  completeEmployeeLogin,
  EmployeeLoginError,
  LOGIN_PENDING_KEY,
  logoutEmployee,
  refreshEmployeeTokens,
} from '../../api/employeeAuth';
import { PmartFailure } from '@pmart/web-core';
import { createPmartFetch } from '@pmart/web-core';
import { mockOperatorToken } from '@pmart/web-core';
import { sha256Fallback } from '@pmart/web-core';
import { TokenStore } from '@pmart/web-core';
import { App } from '../../app/App';
import { env } from '../../env';
import { problem } from '../../mocks/support';
import { server } from '../../test/server';

// 이 파일은 실서버 모드의 로그인 화면(목 계정 버튼 없음)을 본다.
beforeEach(() => {
  env.isMock = false;
});
afterEach(() => {
  env.isMock = true;
});

const ORIGIN = 'http://192.168.0.40';
const IDP_LOGOUT = 'https://192.168.0.40:8443/iam/realms/pmart-staff/protocol/openid-connect/logout?id_token_hint=HINT&post_logout_redirect_uri=http%3A%2F%2F192.168.0.40%2Flogin';
const access = (roles: readonly string[] = ['PRICE_APPROVER']) =>
  mockOperatorToken({ sub: 'OP-ea-1', roles, centers: ['MFC-GANGNAM'], sid: 'SES-ea-1', exp: 1_800_000_000 });
const pair = (accessToken = access(), refreshToken = 'ea-refresh-1') => ({
  accessToken,
  refreshToken,
  accessTokenExpiresAt: '2026-11-12T10:15:00Z',
  refreshTokenExpiresAt: '2026-11-12T22:00:00Z',
  sessionId: 'SES-ea-1',
});

/** 앱과 같은 구성의 독립 클라이언트 */
function client() {
  const store = new TokenStore();
  const api: ReturnType<typeof createApi> = createApi(
    createPmartFetch({ sourceSystem: SOURCE_SYSTEM, tokens: store, refresh: () => refreshEmployeeTokens(api, store), sleep: () => Promise.resolve() }),
  );
  return { api, store };
}

interface Sent {
  readonly headers: Headers;
  readonly body: Record<string, unknown>;
}

/** 티켓 교환 가짜. reply 가 응답을 고른다 */
function exchangeHandler(reply: () => Response = () => HttpResponse.json({ operatorId: 'OP-ea-1', roles: ['PRICE_APPROVER'], centers: ['MFC-GANGNAM'], tokens: pair() })) {
  const sent: Sent[] = [];
  server.use(
    http.post('*/api/v1/employee-auth/tokens', async ({ request }) => {
      sent.push({ headers: request.headers, body: (await request.json()) as Record<string, unknown> });
      return reply();
    }),
  );
  return sent;
}

const pending = () => JSON.parse(sessionStorage.getItem(LOGIN_PENDING_KEY)!) as { verifier: string; deviceId: string; from: string };
const toHex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');

describe('SHA-256·code_challenge', () => {
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

describe('로그인 시작', () => {
  it('게이트웨이 로그인 시작 주소: app·deviceId·codeChallenge(S256)·returnUri /auth/callback, verifier 는 싣지 않는다', async () => {
    const store = new TokenStore();
    const url = new URL(await beginEmployeeLogin('http://192.168.0.40:8080/api/v1', '/prices', store, { origin: ORIGIN }));
    expect(`${url.origin}${url.pathname}`).toBe('http://192.168.0.40:8080/api/v1/employee-auth/logins');
    const q = url.searchParams;
    const p = pending();
    expect(q.get('app')).toBe('backoffice');
    expect(q.get('deviceId')).toBe(store.deviceId);
    expect(q.get('codeChallengeMethod')).toBe('S256');
    expect(q.get('returnUri')).toBe('http://192.168.0.40/auth/callback');
    expect(p.verifier).toMatch(/^[A-Za-z0-9\-._~]{43,128}$/);
    expect(q.get('codeChallenge')).toBe(await codeChallenge(p.verifier));
    expect(url.href).not.toContain(p.verifier);
    expect(p).toMatchObject({ deviceId: store.deviceId, from: '/prices' });
  });
});

describe('티켓 교환', () => {
  it('티켓 + verifier 를 시작한 기기 ID 로 보내 토큰을 받는다 — 페이지가 다시 열려도 기기 ID 를 되살리고, 기록은 한 번만 쓴다', async () => {
    const sent = exchangeHandler();
    const before = new TokenStore();
    await beginEmployeeLogin(API_BASE, '/prices', before, { origin: ORIGIN });
    const p = pending();
    const { api, store } = client(); // 복귀 뒤의 새 페이지(기기 ID 가 새로 만들어진 상태)
    expect(store.deviceId).not.toBe(p.deviceId);

    expect(await completeEmployeeLogin(api, new URLSearchParams({ ticket: 'TICKET-1' }), store)).toBe('/prices');

    expect(sent).toHaveLength(1);
    expect(sent[0]!.body).toEqual({ ticket: 'TICKET-1', codeVerifier: p.verifier });
    expect(sent[0]!.headers.get('X-Device-Id')).toBe(p.deviceId);
    expect(sent[0]!.headers.get('X-Source-System')).toBe(SOURCE_SYSTEM);
    expect(sent[0]!.headers.get('Idempotency-Key')).toBeTruthy();
    expect(sent[0]!.headers.has('Authorization')).toBe(false);
    expect(store.accessToken).toBe(access());
    expect(store.refreshToken).toBe('ea-refresh-1');
    expect(store.deviceId).toBe(p.deviceId);
    expect(sessionStorage.getItem(LOGIN_PENDING_KEY)).toBeNull();
  });

  it('같은 티켓으로 두 번 불러도(StrictMode) 요청은 한 번', async () => {
    const sent = exchangeHandler();
    const { api, store } = client();
    await beginEmployeeLogin(API_BASE, '/prices', store, { origin: ORIGIN });
    const params = new URLSearchParams({ ticket: 'TICKET-2' });
    const [a, b] = await Promise.all([completeEmployeeLogin(api, params, store), completeEmployeeLogin(api, params, store)]);
    expect([a, b]).toEqual(['/prices', '/prices']);
    expect(sent).toHaveLength(1);
  });

  it('복귀 주소 ?error= 는 코드 그대로, 모르는 값은 UNKNOWN — 토큰을 요청하지 않는다', async () => {
    const sent = exchangeHandler();
    const { api, store } = client();
    for (const [error, code] of [
      ['ACCOUNT_NOT_AVAILABLE', 'ACCOUNT_NOT_AVAILABLE'],
      ['IDP_UNAVAILABLE', 'IDP_UNAVAILABLE'],
      ['something_else', 'UNKNOWN'],
    ] as const) {
      await beginEmployeeLogin(API_BASE, '/prices', store, { origin: ORIGIN });
      await expect(completeEmployeeLogin(api, new URLSearchParams({ error }), store)).rejects.toMatchObject({ code });
      expect(sessionStorage.getItem(LOGIN_PENDING_KEY)).toBeNull();
    }
    expect(sent).toHaveLength(0);
  });

  it('이 탭에서 시작한 기록이 없으면 NO_PENDING, 티켓이 없으면 TICKET_INVALID — 요청하지 않는다', async () => {
    const sent = exchangeHandler();
    const { api, store } = client();
    await expect(completeEmployeeLogin(api, new URLSearchParams({ ticket: 'TICKET-3' }), store)).rejects.toMatchObject({ code: 'NO_PENDING' });
    await beginEmployeeLogin(API_BASE, '/prices', store, { origin: ORIGIN });
    await expect(completeEmployeeLogin(api, new URLSearchParams(), store)).rejects.toMatchObject({ code: 'TICKET_INVALID' });
    expect(sent).toHaveLength(0);
  });

  it('서버 거절: 401 → TICKET_INVALID, 403 ACCOUNT_NOT_AVAILABLE, 5xx → NETWORK(결과 불명 — 같은 티켓을 다시 보내지 않는다)', async () => {
    for (const [reply, code] of [
      [() => problem(401, 'TICKET_INVALID'), 'TICKET_INVALID'],
      [() => problem(403, 'ACCOUNT_NOT_AVAILABLE'), 'ACCOUNT_NOT_AVAILABLE'],
      [() => new HttpResponse(null, { status: 502 }), 'NETWORK'],
    ] as const) {
      const sent = exchangeHandler(reply);
      const { api, store } = client();
      await beginEmployeeLogin(API_BASE, '/prices', store, { origin: ORIGIN });
      const error: unknown = await completeEmployeeLogin(api, new URLSearchParams({ ticket: `T-${code}` }), store).catch((e: unknown) => e);
      expect(error).toBeInstanceOf(EmployeeLoginError);
      expect((error as EmployeeLoginError).code).toBe(code);
      expect(sent).toHaveLength(1);
      expect(store.accessToken).toBeNull();
    }
  });
});

describe('갱신·로그아웃', () => {
  function refreshHandler(reply: () => Response) {
    const sent: Sent[] = [];
    server.use(
      http.post('*/api/v1/employee-auth/tokens/refresh', async ({ request }) => {
        sent.push({ headers: request.headers, body: (await request.json()) as Record<string, unknown> });
        return reply();
      }),
    );
    return sent;
  }

  it('갱신: refresh token 을 로그인한 기기 ID 로 보내고 새 쌍으로 바꾼다(회전)', async () => {
    const next = access(['PRICE_APPROVER', 'MD']);
    const sent = refreshHandler(() => HttpResponse.json(pair(next, 'ea-refresh-2')));
    const { api, store } = client();
    store.setPair(pair());
    expect(await refreshEmployeeTokens(api, store)).toBe(next);
    expect(sent[0]!.body).toEqual({ refreshToken: 'ea-refresh-1' });
    expect(sent[0]!.headers.get('X-Device-Id')).toBe(store.deviceId);
    expect(sent[0]!.headers.get('Idempotency-Key')).toBeTruthy();
    expect(store.refreshToken).toBe('ea-refresh-2');
  });

  it('갱신 거절(TOKEN_INVALID·TOKEN_REUSED)은 세션 종료(null), 5xx 는 종료로 단정하지 않고 던진다', async () => {
    for (const code of ['TOKEN_INVALID', 'TOKEN_REUSED']) {
      refreshHandler(() => problem(401, code));
      const { api, store } = client();
      store.setPair(pair());
      expect(await refreshEmployeeTokens(api, store)).toBeNull();
    }
    refreshHandler(() => problem(503, 'DEPENDENCY_UNAVAILABLE'));
    const { api, store } = client();
    store.setPair(pair());
    await expect(refreshEmployeeTokens(api, store)).rejects.toBeInstanceOf(PmartFailure);
    expect(store.refreshToken).toBe('ea-refresh-1');
  });

  function logoutHandler(reply: () => Response) {
    const sent: Sent[] = [];
    server.use(
      http.post('*/api/v1/employee-auth/logouts', async ({ request }) => {
        sent.push({ headers: request.headers, body: (await request.json()) as Record<string, unknown> });
        return reply();
      }),
    );
    return sent;
  }

  it('로그아웃(SSO): 직원 토큰으로 POST /employee-auth/logouts → 200 idpLogoutUri 를 돌려주고 토큰을 지운다', async () => {
    const sent = logoutHandler(() => HttpResponse.json({ idpLogoutUri: IDP_LOGOUT }));
    const { api, store } = client();
    store.setPair(pair());
    expect(await logoutEmployee(api, store)).toEqual({ idpLogoutUri: IDP_LOGOUT, idpSessionMayRemain: false });
    expect(store.accessToken).toBeNull();
    expect(store.refreshToken).toBeNull();
    expect(sent[0]!.headers.get('Authorization')).toBe(`Bearer ${access()}`);
    expect(sent[0]!.headers.get('Idempotency-Key')).toBeTruthy();
    expect(sent[0]!.body).toEqual({ allDevices: false });
  });

  it('로그아웃: 이미 끝난 세션(200, 주소 없음)은 그대로 끝, http(s) 가 아닌 주소는 버린다', async () => {
    for (const body of [{}, { idpLogoutUri: 'javascript:alert(1)' }, { idpLogoutUri: 'not a url' }]) {
      logoutHandler(() => HttpResponse.json(body));
      const { api, store } = client();
      store.setPair(pair());
      expect(await logoutEmployee(api, store)).toEqual({ idpSessionMayRemain: false });
      expect(store.accessToken).toBeNull();
    }
  });

  it('로그아웃: 서버가 실패해도 이 탭의 토큰은 지우고, Keycloak 세션이 남았을 수 있다고 알린다', async () => {
    logoutHandler(() => new HttpResponse(null, { status: 500 }));
    const { api, store } = client();
    store.setPair(pair());
    expect(await logoutEmployee(api, store)).toEqual({ idpSessionMayRemain: true });
    expect(store.accessToken).toBeNull();
    expect(store.refreshToken).toBeNull();
  });
});

describe('화면', () => {
  function sessionHandler() {
    server.use(
      http.get('*/api/v1/employee-auth/sessions/current', () =>
        HttpResponse.json({ sessionId: 'SES-ea-1', operatorId: 'OP-ea-1', app: 'backoffice', issuedAt: '2026-11-12T01:00:00Z', expiresAt: '2026-11-12T01:15:00Z' }),
      ),
    );
  }

  it('로그인 화면은 "직원 계정으로 로그인" 버튼만 — 아이디·비밀번호를 받지 않는다', () => {
    render(<App memory initialPath="/login" />);
    expect(screen.getByRole('button', { name: '직원 계정으로 로그인' })).toBeInTheDocument();
    expect(screen.queryByLabelText('비밀번호')).not.toBeInTheDocument();
  });

  it('/auth/callback?ticket= 으로 돌아오면 토큰을 받아 원래 화면으로 — 세션은 employee-auth 에서 읽고 비밀번호 변경은 없다', async () => {
    const exchanged = exchangeHandler();
    sessionHandler();
    await beginEmployeeLogin(API_BASE, '/session', new TokenStore(), { origin: ORIGIN });
    const paths: string[] = [];
    const listener = ({ request }: { request: Request }) => void paths.push(new URL(request.url).pathname);
    server.events.on('request:start', listener);

    render(<App memory initialPath="/auth/callback?ticket=TICKET-UI" />);

    expect(await screen.findByRole('heading', { name: '내 세션' })).toBeInTheDocument();
    expect(screen.getByText('내 세션: OP-ea-1')).toBeInTheDocument();
    expect(screen.getByText('PRICE_APPROVER')).toBeInTheDocument();
    expect(await screen.findByText('SES-ea-1')).toBeInTheDocument();
    expect(screen.getByText('backoffice')).toBeInTheDocument();
    expect(screen.getByText(/직원 계정\(Keycloak\)에서 관리해요/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '비밀번호 변경' })).not.toBeInTheDocument();
    server.events.removeListener('request:start', listener);

    expect(exchanged).toHaveLength(1);
    expect(exchanged[0]!.body['ticket']).toBe('TICKET-UI');
  });

  it('역할이 비어 있으면 권한 승인 대기 안내', async () => {
    exchangeHandler(() => HttpResponse.json({ operatorId: 'OP-ea-1', roles: [], centers: [], tokens: pair(access([])) }));
    sessionHandler();
    await beginEmployeeLogin(API_BASE, '/session', new TokenStore(), { origin: ORIGIN });
    render(<App memory initialPath="/auth/callback?ticket=TICKET-NOROLE" />);
    expect(await screen.findByText(/권한 승인 대기/)).toBeInTheDocument();
  });

  it('?error=ACCOUNT_NOT_AVAILABLE 로 돌아오면 사유 안내 + 다시 로그인, 토큰을 요청하지 않는다', async () => {
    const exchanged = exchangeHandler();
    await beginEmployeeLogin(API_BASE, '/session', new TokenStore(), { origin: ORIGIN });
    render(<App memory initialPath="/auth/callback?error=ACCOUNT_NOT_AVAILABLE" />);
    expect(await screen.findByRole('alert')).toHaveTextContent('정지되었거나 퇴사 처리된 계정이에요');
    expect(screen.getByRole('link', { name: '다시 로그인' })).toBeInTheDocument();
    expect(exchanged).toHaveLength(0);
  });
});

describe('운영자 계정 화면(없앰 — 직원 등록·권한은 인사팀 백오피스)', () => {
  it('메뉴에 없고, 계정 API 를 부르지 않는다', async () => {
    const paths: string[] = [];
    const listener = ({ request }: { request: Request }) => void paths.push(new URL(request.url).pathname);
    server.events.on('request:start', listener);
    render(<App memory initialPath="/approvals" initialToken={access(['OPERATOR_ADMIN'])} />);
    expect(await screen.findByRole('link', { name: '승인함' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: '운영자 계정' })).not.toBeInTheDocument();
    server.events.removeListener('request:start', listener);
    expect(paths.some((p) => p.includes('/operator-accounts') || p.includes('/auth/operator-logins'))).toBe(false);
  });
});

describe('로그아웃 화면(SSO)', () => {
  afterEach(() => vi.restoreAllMocks());

  function signedIn(logoutReply: () => Response) {
    const assign = vi.spyOn(browser, 'assign').mockImplementation(() => undefined);
    server.use(
      http.get('*/api/v1/employee-auth/sessions/current', () =>
        HttpResponse.json({ sessionId: 'SES-ea-1', operatorId: 'OP-ea-1', app: 'backoffice', issuedAt: '2026-11-12T01:00:00Z', expiresAt: '2026-11-12T01:15:00Z' }),
      ),
      http.post('*/api/v1/employee-auth/logouts', () => logoutReply()),
    );
    render(<App memory initialPath="/session" initialToken={access()} />);
    return assign;
  }

  it('로그인 시작 버튼은 게이트웨이 로그인 시작 주소로 브라우저를 옮긴다', async () => {
    const assign = vi.spyOn(browser, 'assign').mockImplementation(() => undefined);
    render(<App memory initialPath="/login" />);
    await userEvent.click(screen.getByRole('button', { name: '직원 계정으로 로그인' }));
    await waitFor(() => expect(assign).toHaveBeenCalledTimes(1));
    expect(assign.mock.calls[0]![0]).toContain('/api/v1/employee-auth/logins?app=backoffice');
  });

  it('로그아웃하면 토큰을 지운 뒤 Keycloak 로그아웃 주소로 브라우저를 옮긴다', async () => {
    const assign = signedIn(() => HttpResponse.json({ idpLogoutUri: IDP_LOGOUT }));
    expect(screen.getByText(/공용 PC 에서는 자리를 뜰 때 꼭 로그아웃/)).toBeInTheDocument();
    await userEvent.click(await screen.findByRole('button', { name: '로그아웃' }));
    await waitFor(() => expect(assign).toHaveBeenCalledWith(IDP_LOGOUT));
    expect(sessionStorage.getItem('pmart.backoffice.session')).toBeNull();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('서버가 로그아웃을 확인해 주지 못하면 이동하지 않고, 로그인 화면에서 브라우저를 닫으라고 안내한다', async () => {
    const assign = signedIn(() => new HttpResponse(null, { status: 503 }));
    await userEvent.click(await screen.findByRole('button', { name: '로그아웃' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('브라우저를 닫아 주세요');
    expect(screen.getByRole('button', { name: '직원 계정으로 로그인' })).toBeInTheDocument();
    expect(assign).not.toHaveBeenCalled();
  });
});
