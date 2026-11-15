import createClient from 'openapi-fetch';
import { describe, expect, it } from 'vitest';

import type { EmployeeAuthPaths } from './employeeAuth';
import { createOperatorSessionSource } from './operatorSession';
import { TokenStore } from './tokens';

const session = (roles: string[], centers: string[]) => ({
  sessionId: 'SES-1',
  operatorId: 'OP-1',
  app: 'backoffice',
  issuedAt: '2026-11-15T00:00:00Z',
  expiresAt: '2026-11-15T00:15:00Z',
  roles,
  centers,
});
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const fail500 = () => json({ type: 'about:blank', title: 't', status: 500, code: 'INTERNAL_ERROR', traceId: 'tr' }, 500);

function setup(replies: Array<() => Response | Promise<Response>>) {
  let n = 0;
  const employeeAuth = createClient<EmployeeAuthPaths>({
    baseUrl: 'http://gw/api/v1',
    fetch: async () => {
      const reply = replies[Math.min(n, replies.length - 1)]!;
      n += 1;
      return reply();
    },
  });
  const store = new TokenStore();
  return { store, source: createOperatorSessionSource({ employeeAuth }, store), calls: () => n };
}

const settle = () => new Promise((r) => setTimeout(r, 0));

describe('createOperatorSessionSource — sessions/current 응답이 화면 세션', () => {
  it('토큰이 생기면 받아서 역할·센터를 응답 값으로(토큰을 풀지 않는다)', async () => {
    const { store, source } = setup([() => json(session(['MFC_SUPERVISOR'], ['MFC-A', 'MFC-B']))]);
    const stop = source.start();
    expect(source.getState().status).toBe('signed-out');
    store.accessToken = 'not-a-jwt';
    expect(source.getState().status).toBe('loading');
    await settle();
    const s = source.getState();
    expect(s.status === 'ready' && s.session).toMatchObject({ subject: 'OP-1', roles: ['MFC_SUPERVISOR'], centers: ['MFC-A', 'MFC-B'], sessionId: 'SES-1' });
    stop();
  });

  it('처음 받기가 실패하면 failed(빈 역할로 두지 않는다) → reload 로 다시', async () => {
    const { store, source } = setup([fail500, () => json(session(['CS_AGENT'], []))]);
    store.accessToken = 'a';
    const stop = source.start();
    await settle();
    expect(source.getState().status).toBe('failed');
    await source.reload();
    expect(source.getState().status).toBe('ready');
    stop();
  });

  it('이미 받은 뒤 다시 받다 실패하면 앞의 값을 그대로 둔다', async () => {
    const { store, source } = setup([() => json(session(['CS_AGENT'], [])), fail500]);
    store.accessToken = 'a';
    const stop = source.start();
    await settle();
    store.accessToken = 'b'; // 갱신
    await settle();
    const s = source.getState();
    expect(s.status === 'ready' && s.session.roles).toEqual(['CS_AGENT']);
    stop();
  });

  it('늦게 온 옛 응답은 버린다(갱신 뒤 새 응답이 이긴다)', async () => {
    let releaseOld: (r: Response) => void = () => undefined;
    const { store, source } = setup([() => new Promise<Response>((r) => (releaseOld = r)), () => json(session(['NEW'], []))]);
    store.accessToken = 'a';
    const stop = source.start();
    store.accessToken = 'b';
    await settle();
    releaseOld(json(session(['OLD'], [])));
    await settle();
    const s = source.getState();
    expect(s.status === 'ready' && s.session.roles).toEqual(['NEW']);
    stop();
  });

  it('토큰이 지워지면 signed-out', async () => {
    const { store, source } = setup([() => json(session(['CS_AGENT'], []))]);
    store.accessToken = 'a';
    const stop = source.start();
    await settle();
    store.clear();
    expect(source.getState().status).toBe('signed-out');
    stop();
  });

  it('탭이 다시 보이면 다시 받는다(30초 안에는 한 번)', async () => {
    const listeners: Array<() => void> = [];
    const doc = { visibilityState: 'visible' as DocumentVisibilityState, addEventListener: (_: string, l: () => void) => void listeners.push(l), removeEventListener: () => undefined };
    const { store, source, calls } = setup([() => json(session(['A'], [])), () => json(session(['B'], []))]);
    store.accessToken = 'a';
    const stop = source.start({ doc: doc as never, now: () => 0 });
    await settle();
    expect(calls()).toBe(1);
    listeners.forEach((l) => l());
    listeners.forEach((l) => l());
    await settle();
    expect(calls()).toBe(2);
    const s = source.getState();
    expect(s.status === 'ready' && s.session.roles).toEqual(['B']);
    stop();
  });
});
