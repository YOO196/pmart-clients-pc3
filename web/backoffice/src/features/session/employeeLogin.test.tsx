// 직원 로그인 employee-auth(LOGIN_MODE=employee-auth, 빌드 모드 lan) — 백엔드 handoff 2026-11-12, 계약 employee-auth-service.yaml.
import { render, screen } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it, vi } from 'vitest';

import { API_BASE, createApi, SOURCE_SYSTEM } from '../../api/client';
import {
  beginEmployeeLogin,
  codeChallenge,
  completeEmployeeLogin,
  EmployeeLoginError,
  LOGIN_PENDING_KEY,
  logoutEmployee,
  refreshEmployeeTokens,
} from '../../api/employeeAuth';
import { PmartFailure } from '../../api/failure';
import { createPmartFetch } from '../../api/pmartFetch';
import { mockOperatorToken } from '../../api/session';
import { sha256Fallback } from '../../api/sha256';
import { TokenStore } from '../../api/tokens';
import { App } from '../../app/App';
import { problem } from '../../mocks/support';
import { server } from '../../test/server';

vi.mock('../../api/employeeAuth', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../api/employeeAuth')>()),
  LOGIN_MODE: 'employee-auth',
}));

const ORIGIN = 'http://192.168.0.40';
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

  it('로그아웃: 직원 토큰으로 POST /employee-auth/logouts(allDevices=false) 뒤 토큰 삭제 — 서버가 실패해도 이 탭은 지운다', async () => {
    const sent: Sent[] = [];
    let status = 204;
    server.use(
      http.post('*/api/v1/employee-auth/logouts', async ({ request }) => {
        sent.push({ headers: request.headers, body: (await request.json()) as Record<string, unknown> });
        return new HttpResponse(null, { status });
      }),
    );
    for (const s of [204, 500]) {
      status = s;
      const { api, store } = client();
      store.setPair(pair());
      await logoutEmployee(api, store);
      expect(store.accessToken).toBeNull();
      expect(store.refreshToken).toBeNull();
    }
    expect(sent[0]!.headers.get('Authorization')).toBe(`Bearer ${access()}`);
    expect(sent[0]!.headers.get('Idempotency-Key')).toBeTruthy();
    expect(sent[0]!.body).toEqual({ allDevices: false });
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
    expect(paths.some((p) => p.endsWith('/auth/sessions/current') && !p.includes('employee-auth'))).toBe(false);
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

describe('운영자 계정 화면(employee-auth 로그인에서는 내림)', () => {
  it('메뉴에 없고, 주소로 들어가도 안내만 — 계정 API 를 부르지 않는다', async () => {
    const paths: string[] = [];
    const listener = ({ request }: { request: Request }) => void paths.push(new URL(request.url).pathname);
    server.events.on('request:start', listener);
    render(<App memory initialPath="/operators" initialToken={access(['OPERATOR_ADMIN'])} />);
    expect(await screen.findByRole('note')).toHaveTextContent('이 화면에서 관리하지 않아요');
    expect(screen.queryByRole('link', { name: '운영자 계정' })).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: '승인함' })).toBeInTheDocument();
    server.events.removeListener('request:start', listener);
    expect(paths.some((p) => p.includes('/operator-accounts'))).toBe(false);
  });
});
