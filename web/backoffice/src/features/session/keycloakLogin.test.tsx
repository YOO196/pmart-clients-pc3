// 백오피스 화면 — Keycloak 로그인 방식(LOGIN_MODE=keycloak, 빌드 모드 lan-keycloak). handoff 2026-11-11.
import { render, screen } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { beginKeycloakLogin, forgetDiscovery, KEYCLOAK, OIDC_PENDING_KEY } from '../../api/keycloak';
import { App } from '../../app/App';
import { server } from '../../test/server';

vi.mock('../../api/keycloak', async (importOriginal) => ({ ...(await importOriginal<typeof import('../../api/keycloak')>()), LOGIN_MODE: 'keycloak' }));

const seg = (v: unknown) =>
  btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(v))))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
const jwt = (claims: Record<string, unknown>) => `${seg({ alg: 'RS256' })}.${seg(claims)}.sig`;

const tokenEndpoint = `${KEYCLOAK.issuer}/protocol/openid-connect/token`;
const accessToken = jwt({
  iss: KEYCLOAK.issuer,
  sub: 'kc-uuid',
  typ: 'Bearer',
  pmart_operator_id: 'OP-kc-1',
  realm_access: { roles: ['PRICE_APPROVER', 'default-roles-pmart-staff', 'offline_access'] },
  exp: 1_800_000_000,
});

function keycloakHandlers(tokenBodies: URLSearchParams[]) {
  server.use(
    http.get(`${KEYCLOAK.issuer}/.well-known/openid-configuration`, () =>
      HttpResponse.json({
        issuer: KEYCLOAK.issuer,
        authorization_endpoint: `${KEYCLOAK.issuer}/protocol/openid-connect/auth`,
        token_endpoint: tokenEndpoint,
        end_session_endpoint: `${KEYCLOAK.issuer}/protocol/openid-connect/logout`,
      }),
    ),
    http.post(tokenEndpoint, async ({ request }) => {
      tokenBodies.push(new URLSearchParams(await request.text()));
      const nonce = (JSON.parse(sessionStorage.getItem('test.nonce') ?? '""') as string) || '';
      return HttpResponse.json({ access_token: accessToken, refresh_token: 'kc-refresh', id_token: jwt({ nonce, name: '김운영' }) });
    }),
  );
}

beforeEach(() => forgetDiscovery());

describe('Keycloak 로그인 화면', () => {
  it('로그인 화면은 Keycloak 버튼만 — 아이디·비밀번호를 받지 않는다', () => {
    render(<App memory initialPath="/login" />);
    expect(screen.getByRole('button', { name: 'Keycloak 으로 로그인' })).toBeInTheDocument();
    expect(screen.queryByLabelText('비밀번호')).not.toBeInTheDocument();
  });

  it('돌아오면 토큰을 받아 원래 화면으로, 이름·운영자 ID·역할(기본 역할 제외)을 보이고 /auth/sessions/current 는 부르지 않는다', async () => {
    const bodies: URLSearchParams[] = [];
    keycloakHandlers(bodies);
    const authorize = new URL(await beginKeycloakLogin('/session'));
    const pending = JSON.parse(sessionStorage.getItem(OIDC_PENDING_KEY)!) as { nonce: string };
    sessionStorage.setItem('test.nonce', JSON.stringify(pending.nonce));

    const sent: string[] = [];
    const listener = ({ request }: { request: Request }) => void sent.push(new URL(request.url).pathname);
    server.events.on('request:start', listener);
    render(<App memory initialPath={`/login/callback?code=CODE-1&state=${authorize.searchParams.get('state')}`} />);

    expect(await screen.findByRole('heading', { name: '내 세션' })).toBeInTheDocument();
    expect(screen.getByText('내 세션: 김운영')).toBeInTheDocument();
    expect(screen.getByText('김운영 (OP-kc-1)')).toBeInTheDocument();
    expect(screen.getByText('PRICE_APPROVER')).toBeInTheDocument();
    expect(screen.getByText(/Keycloak 계정 화면에서 바꿔요/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '비밀번호 변경' })).not.toBeInTheDocument();
    server.events.removeListener('request:start', listener);

    expect(bodies).toHaveLength(1);
    expect(bodies[0]!.get('grant_type')).toBe('authorization_code');
    expect(bodies[0]!.get('code')).toBe('CODE-1');
    expect(sent.some((p) => p.endsWith('/auth/sessions/current'))).toBe(false);
  });

  it('state 가 맞지 않으면 토큰을 요청하지 않고 다시 로그인 안내', async () => {
    const bodies: URLSearchParams[] = [];
    keycloakHandlers(bodies);
    await beginKeycloakLogin('/session');
    render(<App memory initialPath="/login/callback?code=CODE-2&state=forged" />);
    expect(await screen.findByRole('alert')).toHaveTextContent('로그인 확인 값이 맞지 않아요');
    expect(screen.getByRole('link', { name: '다시 로그인' })).toBeInTheDocument();
    expect(bodies).toHaveLength(0);
  });
});
