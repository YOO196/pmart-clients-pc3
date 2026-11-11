import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it } from 'vitest';

import { loginOperator, refreshOperatorTokens } from '../../api/auth';
import { createApi, SOURCE_SYSTEM, tokens } from '../../api/client';
import { request } from '../../api/pmartFetch';
import { createPmartFetch } from '../../api/pmartFetch';
import { SESSION_STORAGE_KEY } from '../../api/sessionPersistence';
import { TokenStore } from '../../api/tokens';
import { App } from '../../app/App';
import { mockAuthPolicy } from '../../mocks/authHandlers';
import { db } from '../../mocks/db';
import { mockAccounts, mockTokenFor, MOCK_PASSWORD } from '../../mocks/operators';
import { as, renderAt } from '../../test/render';
import { server } from '../../test/server';
import { messages as m } from '../../shared/messages';

const ACCESS = mockAuthPolicy.accessSeconds;
afterEach(() => {
  mockAuthPolicy.accessSeconds = ACCESS;
});

/** 앱과 같은 구성의 독립 클라이언트(토큰 저장소를 테스트가 들여다본다) */
function client() {
  const store = new TokenStore();
  // refresh 는 호출 시점에 api 를 참조한다(client.ts 와 같은 구성).
  const api: ReturnType<typeof createApi> = createApi(createPmartFetch({ sourceSystem: SOURCE_SYSTEM, tokens: store, refresh: () => refreshOperatorTokens(api, store) }));
  return { api, store };
}

function recordRequests() {
  const sent: Request[] = [];
  const listener = ({ request: r }: { request: Request }) => {
    sent.push(r.clone());
  };
  server.events.on('request:start', listener);
  return { sent, stop: () => server.events.removeListener('request:start', listener) };
}

async function login(user: ReturnType<typeof userEvent.setup>, loginId: string, password = MOCK_PASSWORD) {
  await user.type(await screen.findByLabelText('아이디'), loginId);
  await user.type(screen.getByLabelText('비밀번호'), password);
  await user.click(screen.getByRole('button', { name: '로그인' }));
}

describe('운영자 로그인 화면', () => {
  it('세션이 없으면 로그인으로 보내고, 로그인하면 가려던 화면으로 돌아간다', async () => {
    const user = userEvent.setup();
    const rec = recordRequests();
    render(<App memory initialPath="/products?saleState=ON_SALE" />);

    expect(await screen.findByRole('heading', { name: '운영자 로그인' })).toBeInTheDocument();
    await login(user, 'md');

    expect(await screen.findByRole('heading', { name: '상품 조회' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '내 세션: MD 김' })).toBeInTheDocument();

    const post = rec.sent.find((r) => new URL(r.url).pathname.endsWith('/auth/operator-logins'));
    expect(post?.headers.get('X-Source-System')).toBe('backoffice-web');
    expect(post?.headers.get('X-Device-Id')).toMatch(/[0-9a-f-]{36}/);
    expect(post?.headers.has('Idempotency-Key')).toBe(false); // 계약: 로그인은 키를 받지 않는다
    expect(post?.headers.has('Authorization')).toBe(false);
    expect(post?.url).not.toContain(MOCK_PASSWORD);
    // 로그인 뒤 요청은 Bearer 를 붙인다
    await waitFor(() => {
      const list = rec.sent.find((r) => new URL(r.url).pathname.endsWith('/products'));
      expect(list?.headers.get('Authorization')).toMatch(/^Bearer /);
    });
    rec.stop();
  });

  it('새로고침(앱 다시 마운트)해도 이 탭에 보관한 refresh token 으로 세션을 되살려 로그인 화면으로 보내지 않는다', async () => {
    const user = userEvent.setup();
    const first = render(<App memory initialPath="/products" />);
    await screen.findByRole('heading', { name: '운영자 로그인' });
    await login(user, 'md');
    expect(await screen.findByRole('heading', { name: '상품 조회' })).toBeInTheDocument();
    const saved = sessionStorage.getItem(SESSION_STORAGE_KEY);
    expect(saved).toContain('"refreshToken"');
    expect(saved).not.toContain(tokens.accessToken ?? '--'); // access 는 저장하지 않는다
    const savedRefresh = (JSON.parse(saved!) as { refreshToken: string }).refreshToken;

    // 새로고침: 메모리 토큰은 사라지고 sessionStorage 만 남는다.
    first.unmount();
    tokens.accessToken = null;
    sessionStorage.setItem(SESSION_STORAGE_KEY, saved!);
    render(<App memory initialPath="/products" />);

    expect(await screen.findByRole('heading', { name: '상품 조회' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: '운영자 로그인' })).not.toBeInTheDocument();
    // 복원된 세션은 토큰 클레임으로 표시한다(로그인 응답의 표시 이름은 없다).
    expect(screen.getByRole('link', { name: /내 세션: / })).toBeInTheDocument();
    // refresh 는 회전된다(같은 값을 다시 쓰지 않는다).
    const rotated = (JSON.parse(sessionStorage.getItem(SESSION_STORAGE_KEY)!) as { refreshToken: string }).refreshToken;
    expect(rotated).not.toBe(savedRefresh);
  });

  it('보관한 refresh token 이 더는 유효하지 않으면(세션 종료) 보관을 지우고 로그인 화면으로 보낸다', async () => {
    sessionStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify({ refreshToken: 'rt-gone', deviceId: 'dev-1' }));
    render(<App memory initialPath="/products" />);

    expect(await screen.findByRole('heading', { name: '운영자 로그인' })).toBeInTheDocument();
    expect(sessionStorage.getItem(SESSION_STORAGE_KEY)).toBeNull();
  });

  it('아이디·비밀번호가 틀리면 LOGIN_FAILED 문구, 5번 틀리면 ACCOUNT_LOCKED', async () => {
    const user = userEvent.setup();
    render(<App memory initialPath="/login" />);
    await login(user, 'md', 'wrong-password');
    expect(await screen.findByRole('alert')).toHaveAttribute('data-code', 'LOGIN_FAILED');
    expect(screen.getByText('아이디 또는 비밀번호가 맞지 않아요.')).toBeInTheDocument();

    for (let i = 0; i < 4; i++) {
      await user.click(screen.getByRole('button', { name: '로그인' }));
      await waitFor(() => expect(screen.getByRole('button', { name: '로그인' })).toBeEnabled());
    }
    expect(await screen.findByRole('alert')).toHaveAttribute('data-code', 'ACCOUNT_LOCKED');
  });

  it('임시 비밀번호 계정은 비밀번호 변경으로 안내하고, 바꾸면 안내가 사라진다', async () => {
    const user = userEvent.setup();
    const md = db.accounts.get('op-md-1')!;
    md.account = { ...md.account, passwordChangeRequired: true };
    render(<App memory initialPath="/login" />);
    await login(user, 'md');

    expect(await screen.findByText('임시 비밀번호로 로그인했어요. 비밀번호를 바꿔 주세요.')).toBeInTheDocument();
    await user.type(screen.getByLabelText('현재 비밀번호'), MOCK_PASSWORD);
    await user.type(screen.getByLabelText('새 비밀번호'), 'new-password-123');
    await user.type(screen.getByLabelText('새 비밀번호 확인'), 'new-password-123');
    await user.click(screen.getByRole('button', { name: '비밀번호 변경' }));

    expect(await screen.findByText(/비밀번호를 바꿨어요/)).toBeInTheDocument();
    expect(db.accounts.get('op-md-1')?.password).toBe('new-password-123');
  });

  it('로그아웃하면 서버 세션을 끝내고 로그인 화면으로 간다', async () => {
    const user = userEvent.setup();
    render(<App memory initialPath="/login" />);
    await login(user, 'md');
    await user.click(await screen.findByRole('link', { name: '내 세션: MD 김' }));
    await user.click(await screen.findByRole('button', { name: '로그아웃' }));

    expect(await screen.findByRole('heading', { name: '운영자 로그인' })).toBeInTheDocument();
    expect([...db.sessions.values()].every((s) => s.revoked)).toBe(true);
  });

  it('토큰을 갱신할 수 없으면(세션 종료) 로그인 화면으로 보낸다', async () => {
    const expired = mockTokenFor(mockAccounts[1], 'sess-gone');
    const payload = JSON.parse(atob(expired.split('.')[1]!.replace(/-/g, '+').replace(/_/g, '/'))) as Record<string, unknown>;
    expect(payload['sid']).toBe('sess-gone');
    db.sessions.set('sess-gone', {
      sessionId: 'sess-gone',
      operatorId: 'op-md-1',
      deviceId: 'x',
      refreshToken: 'rt-x',
      used: new Set(),
      revoked: true,
      issuedAt: '2026-10-30T00:00:00Z',
      expiresAt: '2026-10-30T12:00:00Z',
    });
    render(<App memory initialPath="/products" initialToken={expired} />);
    expect(await screen.findByRole('heading', { name: '운영자 로그인' })).toBeInTheDocument();
  });
});

describe('토큰 갱신(refresh 회전)', () => {
  it('동시에 401 이 나도 갱신은 한 번, 새 refresh token 으로 바꾸고 원 요청을 다시 보낸다', async () => {
    const { api, store } = client();
    mockAuthPolicy.accessSeconds = -1; // 이미 만료된 access token
    await loginOperator(api, store, { loginId: 'md', password: MOCK_PASSWORD });
    mockAuthPolicy.accessSeconds = ACCESS;
    const firstRefresh = store.refreshToken;
    const rec = recordRequests();

    const [a, b] = await Promise.all([
      request('GET', api.approval.GET('/approvals', {})),
      request('GET', api.product.GET('/products', {})),
    ]);

    expect(a.items).toBeDefined();
    expect(b.items).toBeDefined();
    const refreshes = rec.sent.filter((r) => new URL(r.url).pathname.endsWith('/auth/tokens'));
    expect(refreshes).toHaveLength(1);
    expect(refreshes[0]?.headers.get('X-Device-Id')).toBe(store.deviceId);
    expect(refreshes[0]?.headers.get('Idempotency-Key')).toBeTruthy();
    expect(refreshes[0]?.headers.has('Authorization')).toBe(false);
    expect(store.refreshToken).not.toBe(firstRefresh);
    rec.stop();
  });

  it('이미 쓴 refresh token 을 다시 보내면 TOKEN_REUSED → 세션 종료(null)', async () => {
    const { api, store } = client();
    await loginOperator(api, store, { loginId: 'md', password: MOCK_PASSWORD });
    const old = store.refreshToken!;
    expect(await refreshOperatorTokens(api, store)).toBeTruthy();

    store.setPair({ accessToken: store.accessToken!, refreshToken: old });
    expect(await refreshOperatorTokens(api, store)).toBeNull();
    expect([...db.sessions.values()][0]?.revoked).toBe(true);
  });

  it('갱신 때 역할을 계정에서 다시 읽는다(관리자가 바꾼 역할이 새 토큰에 반영)', async () => {
    const { api, store } = client();
    await loginOperator(api, store, { loginId: 'md', password: MOCK_PASSWORD });
    const md = db.accounts.get('op-md-1')!;
    md.account = { ...md.account, roles: ['MD', 'PRICE_APPROVER'] };
    const access = await refreshOperatorTokens(api, store);
    const claims = JSON.parse(atob(access!.split('.')[1]!.replace(/-/g, '+').replace(/_/g, '/'))) as { roles: string[] };
    expect(claims.roles).toEqual(['MD', 'PRICE_APPROVER']);
  });
});

describe('운영자 계정 관리', () => {
  it('관리자는 계정을 만들 수 있고, 새 계정은 비밀번호 변경 필요로 표시된다', async () => {
    const user = userEvent.setup();
    const view = renderAt('/operators', as.admin);
    await screen.findByRole('cell', { name: 'admin' });
    await user.type(screen.getAllByLabelText('아이디')[0]!, 'md2');
    await user.type(screen.getByLabelText('표시 이름'), 'MD 최');
    await user.type(screen.getByLabelText('초기 비밀번호'), 'initial-pass-1');
    // 역할도 목록에서 고른다(쉼표 입력은 오타 위험).
    const roles = screen.getAllByRole('button', { name: '역할' })[0]!;
    expect(roles).toHaveTextContent('역할을 고르세요');
    await user.click(roles);
    await user.click(await screen.findByRole('checkbox', { name: 'MD' }));
    expect(roles).toHaveTextContent('역할 1개 선택');
    await user.keyboard('{Escape}');
    // 센터는 center-master 목록에서 고른다(쉼표 입력 아님).
    // 닫힌 드롭다운을 열고 체크박스로 여러 개 고른다.
    const centers = screen.getAllByRole('button', { name: '센터' })[0]!;
    await waitFor(() => expect(centers).toBeEnabled());
    expect(centers).toHaveTextContent('센터를 고르세요');
    await user.click(centers);
    await user.click(await screen.findByRole('checkbox', { name: '부산진구 MFC · MFC-BSN-01 · MFC' }));
    await user.click(screen.getByRole('checkbox', { name: /CDC01/ }));
    expect(centers).toHaveTextContent('센터 2개 선택');
    await user.keyboard('{Escape}');
    expect(screen.queryByRole('checkbox', { name: /CDC01/ })).toBeNull();
    await user.click(screen.getByRole('button', { name: '계정 만들기' }));

    expect(await screen.findByText(/계정 md2 를 만들었어요/)).toBeInTheDocument();
    expect(await screen.findByRole('cell', { name: 'md2' })).toBeInTheDocument();
    const post = view.mutations('/operator-accounts')[0]!;
    expect(post.headers.get('Idempotency-Key')).toBeTruthy();
    const body = (await post.json()) as { roles: string[]; centers: string[] };
    expect(body.roles).toEqual(['MD']);
    expect(body.centers).toEqual(['CDC01', 'MFC-BSN-01']);
    expect([...db.accounts.values()].find((a) => a.account.loginId === 'md2')?.account.passwordChangeRequired).toBe(true);
    view.stop();
  });

  it('관리자가 아니면 FORBIDDEN 화면이다', async () => {
    renderAt('/operators', as.md);
    expect(await screen.findByText('이용할 수 없는 화면이에요')).toBeInTheDocument();
  });

  it('수정은 X-Expected-Version 으로 보내고, 그 사이 바뀌었으면 VERSION_CONFLICT', async () => {
    const user = userEvent.setup();
    const view = renderAt('/operators', as.admin);
    const row = (await screen.findByRole('cell', { name: 'md' })).closest('tr')!;
    await user.click(row.querySelector('button')!);
    const md = db.accounts.get('op-md-1')!;
    md.account = { ...md.account, version: 5 }; // 다른 관리자가 먼저 바꿈
    await user.click(screen.getByRole('button', { name: '저장' }));

    expect(await screen.findByRole('alert')).toHaveAttribute('data-code', 'VERSION_CONFLICT');
    expect(view.mutations('/operator-accounts/op-md-1')[0]?.headers.get('X-Expected-Version')).toBe('0');
    view.stop();
  });

  it('수정: 목록에 없는 역할은 "(목록에 없음)"으로 남아 저장 때 지워지지 않고, 드롭다운으로 역할을 더한다', async () => {
    const md = db.accounts.get('op-md-1')!;
    md.account = { ...md.account, roles: ['MD', 'LEGACY_ROLE'] };
    const user = userEvent.setup();
    const view = renderAt('/operators', as.admin);
    const row = (await screen.findByRole('cell', { name: 'md' })).closest('tr')!;
    await user.click(row.querySelector('button')!);
    expect(screen.getByText('LEGACY_ROLE (목록에 없음)')).toBeInTheDocument();
    const roles = screen.getAllByRole('button', { name: '역할' }).at(-1)!;
    expect(roles).toHaveTextContent('역할 2개 선택');
    await user.click(roles);
    await user.click(await screen.findByRole('checkbox', { name: 'PRICE_APPROVER · 가격 승인' }));
    await user.keyboard('{Escape}');
    await user.click(screen.getByRole('button', { name: '저장' }));

    expect(await screen.findByText(m.operators.saved)).toBeInTheDocument();
    const put = view.mutations('/operator-accounts/op-md-1')[0]!;
    expect([...((await put.json()) as { roles: string[] }).roles].sort()).toEqual(['LEGACY_ROLE', 'MD', 'PRICE_APPROVER']);
    view.stop();
  });
});
